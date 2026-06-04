class_name WorldSemanticRuntimeView
extends Node


const GeneratedTileDataScript := preload("res://scripts/mapgen/GeneratedTileData.gd")
const ResourcePatchGeneratorScript := preload("res://scripts/mapgen/ResourcePatchGenerator.gd")
const TileRenderDefinitionScript := preload("res://scripts/mapgen/TileRenderDefinition.gd")
const WorldSemanticChunkScript := preload("res://scripts/mapgen/world/WorldSemanticChunk.gd")
const WorldSemanticGridScript := preload("res://scripts/mapgen/world/WorldSemanticGrid.gd")
const WorldSemanticStoreScript := preload("res://scripts/mapgen/world/WorldSemanticStore.gd")

const CARDINAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i.UP,
	Vector2i.RIGHT,
	Vector2i.DOWN,
	Vector2i.LEFT,
]

@export var render_padding_cells: int = 6
@export var runtime_chunk_preload_margin: int = 2
@export var runtime_chunk_keep_margin: int = 3
@export var runtime_visual_chunks_per_frame: int = 6
@export var camera_coverage_safety_margin: int = 1
@export var unload_idle_delay_seconds: float = 0.25

var semantic_store: WorldSemanticStore = null
var current_identity: WorldGenerationIdentity = null
var ground_layer: TileMapLayer = null
var resource_layer: TileMapLayer = null
var transition_layer: TileMapLayer = null
var main_camera: Camera2D = null
var last_error: String = ""

var _runtime_generator: ResourcePatchGenerator = ResourcePatchGeneratorScript.new()
var _runtime_semantic_chunks: Dictionary = {}
var _runtime_rendered_resource_counts: Dictionary = {}
var _prewarmed_chunk_resource_counts: Dictionary = {}
var _rendered_chunk_coords: Dictionary = {}
var _runtime_visual_chunk_queue: Array[Vector2i] = []
var _runtime_visual_chunk_queue_set: Dictionary = {}
var _tile_pixel_size: Vector2 = Vector2(16.0, 16.0)
var _current_visible_chunk_rect: Rect2i = Rect2i()
var _camera_cell: Vector2i = Vector2i.ZERO
var _previous_camera_cell: Vector2i = Vector2i.ZERO
var _last_camera_chunk_delta: Vector2i = Vector2i.ZERO
var _time_since_camera_moved: float = 0.0
var _initialized: bool = false

var _prewarmed_cell_count: int = 0
var _prewarmed_resource_count: int = 0
var _runtime_active_resource_count: int = 0
var _runtime_generated_chunk_count: int = 0
var _runtime_generated_cell_count: int = 0
var _runtime_generated_resource_count: int = 0
var _runtime_unloaded_chunk_count: int = 0


func setup(
	next_identity: WorldGenerationIdentity,
	next_store: WorldSemanticStore,
	next_ground_layer: TileMapLayer,
	next_resource_layer: TileMapLayer,
	next_transition_layer: TileMapLayer,
	next_camera: Camera2D,
	next_runtime_chunks: Dictionary = {}
) -> bool:
	last_error = ""

	if not is_inside_tree():
		last_error = "WorldSemanticRuntimeView.setup requires the node to be inside the scene tree"
		return false
	if next_identity == null or not next_identity.is_valid():
		last_error = "WorldSemanticRuntimeView.setup requires a valid identity"
		return false
	if next_store == null or next_store.prewarm_state != WorldSemanticStoreScript.PrewarmState.READY:
		last_error = "WorldSemanticRuntimeView.setup requires a READY semantic store"
		return false
	if int(next_store.expected_semantic_digest) != int(next_identity.semantic_digest):
		last_error = "WorldSemanticRuntimeView.setup identity digest does not match store"
		return false
	if next_store.expected_semantic_hash256 != next_identity.semantic_hash256:
		last_error = "WorldSemanticRuntimeView.setup identity hash does not match store"
		return false
	if next_store.expected_canonical_identity_bytes != next_identity.canonical_identity_bytes:
		last_error = "WorldSemanticRuntimeView.setup canonical identity does not match store"
		return false
	if next_ground_layer == null or next_resource_layer == null or next_transition_layer == null:
		last_error = "WorldSemanticRuntimeView.setup requires ground/resource/transition layers"
		return false
	if next_camera == null:
		last_error = "WorldSemanticRuntimeView.setup requires a camera"
		return false
	for runtime_chunk_key_variant in next_runtime_chunks.keys():
		if typeof(runtime_chunk_key_variant) != TYPE_VECTOR2I:
			last_error = "WorldSemanticRuntimeView.setup runtime chunk keys must be Vector2i"
			return false
		var runtime_chunk_variant: Variant = next_runtime_chunks[runtime_chunk_key_variant]
		if runtime_chunk_variant != null and not (runtime_chunk_variant is WorldSemanticChunk):
			last_error = "WorldSemanticRuntimeView.setup runtime chunk values must be WorldSemanticChunk or null"
			return false

	current_identity = next_identity
	semantic_store = next_store
	ground_layer = next_ground_layer
	resource_layer = next_resource_layer
	transition_layer = next_transition_layer
	main_camera = next_camera
	_runtime_semantic_chunks = next_runtime_chunks.duplicate()
	_tile_pixel_size = _resolve_tile_pixel_size()

	_reset_visual_state(false)
	_rebuild_runtime_cache_metrics()

	_previous_camera_cell = _global_position_to_world_cell(main_camera.global_position)
	_camera_cell = _previous_camera_cell
	_last_camera_chunk_delta = Vector2i.ZERO
	_time_since_camera_moved = unload_idle_delay_seconds
	_initialized = true

	refresh_now()
	return true


func teardown(clear_visuals: bool = true, clear_runtime_cache: bool = false) -> void:
	if clear_visuals:
		_clear_all_rendered_cells()
	_reset_visual_state(clear_runtime_cache)
	semantic_store = null
	current_identity = null
	ground_layer = null
	resource_layer = null
	transition_layer = null
	main_camera = null
	_initialized = false
	last_error = ""


func is_initialized() -> bool:
	return _initialized


func refresh_now() -> void:
	if not _initialized:
		return
	_update_camera_tracking()
	_ensure_runtime_chunks_for_visible_view(true, false)
	_process_runtime_visual_chunk_queue(maxi(runtime_visual_chunks_per_frame, 1))


func flush_runtime_visual_queue(max_chunks: int = 256) -> int:
	if not _initialized:
		return 0
	var processed_total := 0
	var budget: int = maxi(max_chunks, 0)
	while not _runtime_visual_chunk_queue.is_empty() and processed_total < budget:
		var before_size := _runtime_visual_chunk_queue.size()
		_process_runtime_visual_chunk_queue(1)
		if _runtime_visual_chunk_queue.size() >= before_size:
			break
		processed_total += 1
	return processed_total


func ensure_chunk_for_world_cell(world_cell: Vector2i) -> bool:
	if not _initialized:
		return false
	_ensure_runtime_chunk_for_world_cell(world_cell)
	return get_terrain_id(world_cell) != WorldSemanticStoreScript.QUERY_MISS


func can_show_camera_position_without_gray(world_position: Vector2) -> bool:
	if not _initialized:
		return false
	var target_camera_cell: Vector2i = _global_position_to_world_cell(world_position)
	var visible_chunk_rect: Rect2i = _compute_visible_chunk_rect(target_camera_cell)
	var safe_chunk_rect: Rect2i = _expand_chunk_rect(visible_chunk_rect, camera_coverage_safety_margin)

	for chunk_y in range(safe_chunk_rect.position.y, safe_chunk_rect.end.y):
		for chunk_x in range(safe_chunk_rect.position.x, safe_chunk_rect.end.x):
			var chunk_coords := Vector2i(chunk_x, chunk_y)
			if _rendered_chunk_coords.has(chunk_coords):
				continue
			return false
	return true


func is_minimum_entry_visual_ready(world_position: Vector2) -> bool:
	return can_show_camera_position_without_gray(world_position)


func is_background_visual_build_complete() -> bool:
	if not _initialized:
		return false
	return _runtime_visual_chunk_queue.is_empty()


func request_visual_coverage_for_camera_position(world_position: Vector2) -> void:
	if not _initialized:
		return
	var target_camera_cell: Vector2i = _global_position_to_world_cell(world_position)
	var visible_chunk_rect: Rect2i = _compute_visible_chunk_rect(target_camera_cell)
	var target_chunk_rect: Rect2i = _expand_chunk_rect(visible_chunk_rect, runtime_chunk_preload_margin)
	for chunk_y in range(target_chunk_rect.position.y, target_chunk_rect.end.y):
		for chunk_x in range(target_chunk_rect.position.x, target_chunk_rect.end.x):
			var chunk_coords := Vector2i(chunk_x, chunk_y)
			if _rendered_chunk_coords.has(chunk_coords):
				continue
			_enqueue_runtime_visual_chunk(chunk_coords)


func has_runtime_cached_chunk(chunk_coords: Vector2i) -> bool:
	return _runtime_semantic_chunks.has(chunk_coords)


func is_chunk_rendered(chunk_coords: Vector2i) -> bool:
	return _rendered_chunk_coords.has(chunk_coords)


func get_runtime_chunks() -> Dictionary:
	return _runtime_semantic_chunks.duplicate()


func get_terrain_id(world_cell: Vector2i) -> int:
	var chunk: WorldSemanticChunk = _borrow_semantic_chunk_for_world_cell(world_cell)
	if chunk == null:
		return WorldSemanticStoreScript.QUERY_MISS
	return chunk.get_terrain_id_by_index(WorldSemanticGridScript.world_cell_to_local_index(world_cell))


func get_base_resource_id(world_cell: Vector2i) -> int:
	var chunk: WorldSemanticChunk = _borrow_semantic_chunk_for_world_cell(world_cell)
	if chunk == null:
		return WorldSemanticStoreScript.QUERY_MISS
	return chunk.get_base_resource_id_by_index(WorldSemanticGridScript.world_cell_to_local_index(world_cell))


func get_flags(world_cell: Vector2i) -> int:
	var chunk: WorldSemanticChunk = _borrow_semantic_chunk_for_world_cell(world_cell)
	if chunk == null:
		return WorldSemanticStoreScript.QUERY_MISS
	return chunk.get_flags_by_index(WorldSemanticGridScript.world_cell_to_local_index(world_cell))


func get_base_resource_amount(world_cell: Vector2i) -> int:
	var chunk: WorldSemanticChunk = _borrow_semantic_chunk_for_world_cell(world_cell)
	if chunk == null:
		return WorldSemanticStoreScript.QUERY_MISS
	return chunk.get_base_resource_amount_by_index(WorldSemanticGridScript.world_cell_to_local_index(world_cell))


func get_patch_key_payload(world_cell: Vector2i, out_payload: PackedInt32Array) -> int:
	if out_payload.size() < WorldSemanticChunkScript.PATCH_KEY_STRIDE:
		return WorldSemanticStoreScript.PatchLookupResult.MISS

	var chunk: WorldSemanticChunk = _borrow_semantic_chunk_for_world_cell(world_cell)
	if chunk == null:
		return WorldSemanticStoreScript.PatchLookupResult.MISS

	var local_index := WorldSemanticGridScript.world_cell_to_local_index(world_cell)
	if chunk.get_base_resource_id_by_index(local_index) == WorldSemanticChunkScript.RESOURCE_NONE:
		return WorldSemanticStoreScript.PatchLookupResult.NONE
	if chunk.copy_patch_payload_by_index(local_index, out_payload) == WorldSemanticChunkScript.INVALID_INDEX:
		return WorldSemanticStoreScript.PatchLookupResult.MISS
	return WorldSemanticStoreScript.PatchLookupResult.FOUND


func get_debug_snapshot() -> Dictionary:
	return {
		"initialized": _initialized,
		"camera_cell": _camera_cell,
		"visible_chunk_rect": _current_visible_chunk_rect,
		"rendered_chunk_count": _rendered_chunk_coords.size(),
		"runtime_cached_chunk_count": _runtime_semantic_chunks.size(),
		"runtime_generated_chunk_count": _runtime_generated_chunk_count,
		"runtime_generated_cell_count": _runtime_generated_cell_count,
		"runtime_generated_resource_count": _runtime_generated_resource_count,
		"runtime_active_resource_count": _runtime_active_resource_count,
		"runtime_unloaded_chunk_count": _runtime_unloaded_chunk_count,
		"queue_size": _runtime_visual_chunk_queue.size(),
		"prewarm_rendered_cell_count": _prewarmed_cell_count,
		"prewarm_rendered_resource_count": _prewarmed_resource_count,
		"last_error": last_error,
	}


func _process(delta: float) -> void:
	if not _initialized:
		return

	var camera_moved: bool = _update_camera_tracking()
	if camera_moved:
		_time_since_camera_moved = 0.0
	else:
		_time_since_camera_moved += delta

	var allow_unload: bool = _time_since_camera_moved >= unload_idle_delay_seconds
	_ensure_runtime_chunks_for_visible_view(false, allow_unload)
	_process_runtime_visual_chunk_queue(runtime_visual_chunks_per_frame)


func _reset_visual_state(clear_runtime_cache: bool) -> void:
	if ground_layer != null:
		ground_layer.clear()
	if resource_layer != null:
		resource_layer.clear()
	if transition_layer != null:
		transition_layer.clear()

	_runtime_rendered_resource_counts.clear()
	_prewarmed_chunk_resource_counts.clear()
	_rendered_chunk_coords.clear()
	_runtime_visual_chunk_queue.clear()
	_runtime_visual_chunk_queue_set.clear()
	_current_visible_chunk_rect = Rect2i()
	_time_since_camera_moved = 0.0
	_runtime_active_resource_count = 0
	_runtime_unloaded_chunk_count = 0
	_prewarmed_cell_count = 0
	_prewarmed_resource_count = 0

	if clear_runtime_cache:
		_runtime_semantic_chunks.clear()
		_runtime_generated_chunk_count = 0
		_runtime_generated_cell_count = 0
		_runtime_generated_resource_count = 0


func _rebuild_runtime_cache_metrics() -> void:
	_runtime_generated_chunk_count = _runtime_semantic_chunks.size()
	_runtime_generated_cell_count = _runtime_generated_chunk_count * WorldSemanticGridScript.TILES_PER_CHUNK
	_runtime_generated_resource_count = 0
	for runtime_chunk_variant in _runtime_semantic_chunks.values():
		var runtime_chunk: WorldSemanticChunk = runtime_chunk_variant
		if runtime_chunk == null:
			continue
		_runtime_generated_resource_count += _count_resource_tiles_in_chunk(runtime_chunk)


func _update_camera_tracking() -> bool:
	if main_camera == null or ground_layer == null:
		return false
	var next_camera_cell: Vector2i = _global_position_to_world_cell(main_camera.global_position)
	if next_camera_cell == _camera_cell:
		_last_camera_chunk_delta = Vector2i.ZERO
		return false

	_previous_camera_cell = _camera_cell
	_camera_cell = next_camera_cell
	var previous_chunk: Vector2i = WorldSemanticGridScript.world_cell_to_chunk_coords(_previous_camera_cell)
	var current_chunk: Vector2i = WorldSemanticGridScript.world_cell_to_chunk_coords(_camera_cell)
	_last_camera_chunk_delta = current_chunk - previous_chunk
	return true


func _ensure_runtime_chunks_for_visible_view(force_refresh: bool, allow_unload: bool = true) -> void:
	var visible_chunk_rect: Rect2i = _compute_visible_chunk_rect(_camera_cell)
	if not force_refresh and visible_chunk_rect == _current_visible_chunk_rect:
		if allow_unload:
			var steady_keep_chunk_rect: Rect2i = _expand_chunk_rect(visible_chunk_rect, runtime_chunk_keep_margin)
			_unload_rendered_prewarm_chunks_outside_keep_rect(steady_keep_chunk_rect)
			_unload_runtime_chunks_outside_keep_rect(steady_keep_chunk_rect)
		return

	_current_visible_chunk_rect = visible_chunk_rect
	var target_chunk_rect: Rect2i = _expand_chunk_rect(visible_chunk_rect, runtime_chunk_preload_margin)
	var keep_chunk_rect: Rect2i = _expand_chunk_rect(visible_chunk_rect, runtime_chunk_keep_margin)

	_render_chunk_rect_immediately(visible_chunk_rect)
	_enqueue_chunk_rect_for_preload(target_chunk_rect, visible_chunk_rect)

	if allow_unload:
		_unload_rendered_prewarm_chunks_outside_keep_rect(keep_chunk_rect)
		_unload_runtime_chunks_outside_keep_rect(keep_chunk_rect)
	else:
		_prune_runtime_visual_chunk_queue(keep_chunk_rect)


func _ensure_runtime_chunk_for_world_cell(world_cell: Vector2i) -> void:
	var chunk_coords: Vector2i = WorldSemanticGridScript.world_cell_to_chunk_coords(world_cell)
	if current_identity.prewarm_chunk_rect.has_point(chunk_coords):
		if not _rendered_chunk_coords.has(chunk_coords):
			_render_prewarmed_chunk(chunk_coords)
		return
	if _runtime_semantic_chunks.has(chunk_coords):
		if not _rendered_chunk_coords.has(chunk_coords):
			_render_runtime_chunk(chunk_coords)
		return
	_generate_and_render_runtime_chunk(chunk_coords)


func _render_chunk_rect_immediately(chunk_rect: Rect2i) -> void:
	for chunk_y in range(chunk_rect.position.y, chunk_rect.end.y):
		for chunk_x in range(chunk_rect.position.x, chunk_rect.end.x):
			var chunk_coords := Vector2i(chunk_x, chunk_y)
			if _rendered_chunk_coords.has(chunk_coords):
				continue
			if current_identity.prewarm_chunk_rect.has_point(chunk_coords):
				_render_prewarmed_chunk(chunk_coords)
			else:
				_generate_and_render_runtime_chunk(chunk_coords)


func _enqueue_chunk_rect_for_preload(target_chunk_rect: Rect2i, visible_chunk_rect: Rect2i) -> void:
	var pending_chunks: Array[Vector2i] = []
	for chunk_y in range(target_chunk_rect.position.y, target_chunk_rect.end.y):
		for chunk_x in range(target_chunk_rect.position.x, target_chunk_rect.end.x):
			var chunk_coords := Vector2i(chunk_x, chunk_y)
			if visible_chunk_rect.has_point(chunk_coords):
				continue
			if _rendered_chunk_coords.has(chunk_coords):
				continue
			pending_chunks.append(chunk_coords)

	pending_chunks.sort_custom(Callable(self, "_compare_chunk_coords_for_preload_priority"))
	for chunk_coords in pending_chunks:
		_enqueue_runtime_visual_chunk(chunk_coords)


func _enqueue_runtime_visual_chunk(chunk_coords: Vector2i) -> void:
	if _runtime_visual_chunk_queue_set.has(chunk_coords):
		return
	_runtime_visual_chunk_queue_set[chunk_coords] = true
	_runtime_visual_chunk_queue.append(chunk_coords)


func _process_runtime_visual_chunk_queue(max_chunks: int) -> void:
	var processed_count: int = 0
	while processed_count < max_chunks and not _runtime_visual_chunk_queue.is_empty():
		var chunk_coords: Vector2i = _runtime_visual_chunk_queue.pop_front()
		_runtime_visual_chunk_queue_set.erase(chunk_coords)
		if _rendered_chunk_coords.has(chunk_coords):
			continue
		if current_identity.prewarm_chunk_rect.has_point(chunk_coords):
			_render_prewarmed_chunk(chunk_coords)
		else:
			_generate_and_render_runtime_chunk(chunk_coords)
		processed_count += 1


func _compare_chunk_coords_for_preload_priority(a: Vector2i, b: Vector2i) -> bool:
	var camera_chunk: Vector2i = WorldSemanticGridScript.world_cell_to_chunk_coords(_camera_cell)
	var motion: Vector2i = _last_camera_chunk_delta
	if motion != Vector2i.ZERO:
		var a_motion_score: int = motion.x * (a.x - camera_chunk.x) + motion.y * (a.y - camera_chunk.y)
		var b_motion_score: int = motion.x * (b.x - camera_chunk.x) + motion.y * (b.y - camera_chunk.y)
		if a_motion_score != b_motion_score:
			return a_motion_score > b_motion_score

	var a_dx: int = a.x - camera_chunk.x
	var a_dy: int = a.y - camera_chunk.y
	var b_dx: int = b.x - camera_chunk.x
	var b_dy: int = b.y - camera_chunk.y
	var a_distance_sq: int = a_dx * a_dx + a_dy * a_dy
	var b_distance_sq: int = b_dx * b_dx + b_dy * b_dy
	if a_distance_sq != b_distance_sq:
		return a_distance_sq < b_distance_sq
	if a.y != b.y:
		return a.y < b.y
	return a.x < b.x


func _render_prewarmed_chunk(chunk_coords: Vector2i) -> void:
	var chunk: WorldSemanticChunk = semantic_store.borrow_readonly_chunk(chunk_coords)
	if chunk == null:
		last_error = "Missing prewarmed semantic chunk at %s" % str(chunk_coords)
		return
	_render_semantic_chunk_base_and_resources(chunk, false)
	_prewarmed_chunk_resource_counts[chunk_coords] = _count_resource_tiles_in_chunk(chunk)
	_rendered_chunk_coords[chunk_coords] = true
	_refresh_transition_cells_for_chunk(chunk_coords)


func _generate_and_render_runtime_chunk(chunk_coords: Vector2i) -> void:
	if _runtime_semantic_chunks.has(chunk_coords):
		_render_runtime_chunk(chunk_coords)
		return

	var chunk_result: Dictionary = _runtime_generator.build_base_semantics_for_chunk_packed(chunk_coords, current_identity)
	if chunk_result.is_empty():
		last_error = "Runtime semantic generation returned empty chunk result at %s" % str(chunk_coords)
		return

	var chunk: WorldSemanticChunk = WorldSemanticChunkScript.from_validated_result(chunk_result)
	if chunk == null:
		last_error = "Runtime semantic generation returned invalid chunk at %s" % str(chunk_coords)
		return

	_runtime_semantic_chunks[chunk_coords] = chunk
	_runtime_generated_chunk_count += 1
	_runtime_generated_cell_count += WorldSemanticGridScript.TILES_PER_CHUNK
	_runtime_generated_resource_count += _count_resource_tiles_in_chunk(chunk)
	_render_runtime_chunk(chunk_coords)


func _render_runtime_chunk(chunk_coords: Vector2i) -> void:
	var chunk: WorldSemanticChunk = _runtime_semantic_chunks.get(chunk_coords, null)
	if chunk == null:
		last_error = "Missing runtime semantic chunk at %s" % str(chunk_coords)
		return

	var was_rendered: bool = _rendered_chunk_coords.has(chunk_coords)
	var previous_resource_count: int = int(_runtime_rendered_resource_counts.get(chunk_coords, 0))
	var resource_count: int = _count_resource_tiles_in_chunk(chunk)
	if was_rendered:
		_runtime_active_resource_count = maxi(_runtime_active_resource_count - previous_resource_count, 0)

	_runtime_rendered_resource_counts[chunk_coords] = resource_count
	_runtime_active_resource_count += resource_count
	_render_semantic_chunk_base_and_resources(chunk, true)
	_rendered_chunk_coords[chunk_coords] = true
	_refresh_transition_cells_for_chunk(chunk_coords)


func _unload_rendered_prewarm_chunks_outside_keep_rect(keep_chunk_rect: Rect2i) -> void:
	_prune_runtime_visual_chunk_queue(keep_chunk_rect)
	var rendered_chunk_coords_list: Array = _rendered_chunk_coords.keys()
	for chunk_coords_variant in rendered_chunk_coords_list:
		var chunk_coords: Vector2i = chunk_coords_variant
		if not current_identity.prewarm_chunk_rect.has_point(chunk_coords):
			continue
		if keep_chunk_rect.has_point(chunk_coords):
			continue
		_clear_rendered_chunk_cells(chunk_coords)
		_prewarmed_cell_count = maxi(_prewarmed_cell_count - WorldSemanticGridScript.TILES_PER_CHUNK, 0)
		_prewarmed_resource_count = maxi(
			_prewarmed_resource_count - int(_prewarmed_chunk_resource_counts.get(chunk_coords, 0)),
			0
		)
		_prewarmed_chunk_resource_counts.erase(chunk_coords)
		_rendered_chunk_coords.erase(chunk_coords)


func _unload_runtime_chunks_outside_keep_rect(keep_chunk_rect: Rect2i) -> void:
	_prune_runtime_visual_chunk_queue(keep_chunk_rect)
	var rendered_chunk_coords_list: Array = _rendered_chunk_coords.keys()
	for chunk_coords_variant in rendered_chunk_coords_list:
		var chunk_coords: Vector2i = chunk_coords_variant
		if current_identity.prewarm_chunk_rect.has_point(chunk_coords):
			continue
		if keep_chunk_rect.has_point(chunk_coords):
			continue
		_unload_runtime_chunk(chunk_coords)


func _unload_runtime_chunk(chunk_coords: Vector2i) -> void:
	if not _rendered_chunk_coords.has(chunk_coords):
		return

	_clear_rendered_chunk_cells(chunk_coords)
	_runtime_active_resource_count = maxi(
		_runtime_active_resource_count - int(_runtime_rendered_resource_counts.get(chunk_coords, 0)),
		0
	)
	_runtime_rendered_resource_counts.erase(chunk_coords)
	_rendered_chunk_coords.erase(chunk_coords)
	_runtime_unloaded_chunk_count += 1
	_refresh_transition_cells_for_chunk(chunk_coords)


func _clear_rendered_chunk_cells(chunk_coords: Vector2i) -> void:
	var chunk_origin: Vector2i = WorldSemanticGridScript.chunk_coords_to_origin_cell(chunk_coords)
	var chunk_width: int = WorldSemanticGridScript.SEMANTIC_CHUNK_SIZE.x
	var chunk_height: int = WorldSemanticGridScript.SEMANTIC_CHUNK_SIZE.y

	for local_y in range(chunk_height):
		for local_x in range(chunk_width):
			_clear_rendered_cell(chunk_origin + Vector2i(local_x, local_y))


func _clear_all_rendered_cells() -> void:
	var rendered_chunk_coords_list: Array = _rendered_chunk_coords.keys()
	for chunk_coords_variant in rendered_chunk_coords_list:
		var chunk_coords: Vector2i = chunk_coords_variant
		_clear_rendered_chunk_cells(chunk_coords)


func _clear_rendered_cell(world_cell: Vector2i) -> void:
	if ground_layer != null:
		ground_layer.set_cell(world_cell, -1)
	if resource_layer != null:
		resource_layer.set_cell(world_cell, -1)
	if transition_layer != null:
		transition_layer.set_cell(world_cell, -1)


func _prune_runtime_visual_chunk_queue(keep_chunk_rect: Rect2i) -> void:
	if _runtime_visual_chunk_queue.is_empty():
		return

	var next_queue: Array[Vector2i] = []
	_runtime_visual_chunk_queue_set.clear()
	for chunk_coords in _runtime_visual_chunk_queue:
		if not keep_chunk_rect.has_point(chunk_coords):
			continue
		next_queue.append(chunk_coords)
		_runtime_visual_chunk_queue_set[chunk_coords] = true
	_runtime_visual_chunk_queue = next_queue


func _refresh_transition_cells_for_chunk(chunk_coords: Vector2i) -> void:
	var chunk_origin: Vector2i = WorldSemanticGridScript.chunk_coords_to_origin_cell(chunk_coords)
	var chunk_width: int = WorldSemanticGridScript.SEMANTIC_CHUNK_SIZE.x
	var chunk_height: int = WorldSemanticGridScript.SEMANTIC_CHUNK_SIZE.y
	var start_cell: Vector2i = chunk_origin - Vector2i.ONE
	var end_cell: Vector2i = chunk_origin + Vector2i(chunk_width, chunk_height)

	for world_y in range(start_cell.y, end_cell.y + 1):
		for world_x in range(start_cell.x, end_cell.x + 1):
			_render_transition_cell(Vector2i(world_x, world_y))


func _render_semantic_chunk_base_and_resources(chunk: WorldSemanticChunk, is_runtime_chunk: bool) -> void:
	_render_semantic_chunk_ground(chunk, is_runtime_chunk)
	_render_semantic_chunk_resources(chunk, is_runtime_chunk)


func _render_semantic_chunk_ground(chunk: WorldSemanticChunk, is_runtime_chunk: bool) -> void:
	var chunk_origin: Vector2i = WorldSemanticGridScript.chunk_coords_to_origin_cell(chunk.chunk_coords)
	var chunk_width: int = WorldSemanticGridScript.SEMANTIC_CHUNK_SIZE.x
	var chunk_height: int = WorldSemanticGridScript.SEMANTIC_CHUNK_SIZE.y

	for local_y in range(chunk_height):
		for local_x in range(chunk_width):
			var local_index: int = local_y * chunk_width + local_x
			var world_cell: Vector2i = chunk_origin + Vector2i(local_x, local_y)
			var terrain_id: int = chunk.get_terrain_id_by_index(local_index)

			_render_base_cell(world_cell, terrain_id)
			if not is_runtime_chunk:
				_prewarmed_cell_count += 1


func _render_semantic_chunk_resources(chunk: WorldSemanticChunk, is_runtime_chunk: bool) -> void:
	var chunk_origin: Vector2i = WorldSemanticGridScript.chunk_coords_to_origin_cell(chunk.chunk_coords)
	var chunk_width: int = WorldSemanticGridScript.SEMANTIC_CHUNK_SIZE.x
	var chunk_height: int = WorldSemanticGridScript.SEMANTIC_CHUNK_SIZE.y

	for local_y in range(chunk_height):
		for local_x in range(chunk_width):
			var local_index: int = local_y * chunk_width + local_x
			var world_cell: Vector2i = chunk_origin + Vector2i(local_x, local_y)
			var resource_id: int = chunk.get_base_resource_id_by_index(local_index)

			_render_resource_cell(world_cell, resource_id)
			if not is_runtime_chunk and resource_id != WorldSemanticChunkScript.RESOURCE_NONE:
				_prewarmed_resource_count += 1


func _render_base_cell(world_cell: Vector2i, terrain_id: int) -> void:
	var atlas_coords: Vector2i = TileRenderDefinitionScript.get_base_tile(_terrain_name_from_id(terrain_id))
	if atlas_coords == TileRenderDefinitionScript.INVALID_ATLAS:
		ground_layer.set_cell(world_cell, -1)
		return
	ground_layer.set_cell(world_cell, TileRenderDefinitionScript.TILE_SOURCE_ID, atlas_coords, 0)


func _render_resource_cell(world_cell: Vector2i, resource_id: int) -> void:
	if resource_id == WorldSemanticChunkScript.RESOURCE_NONE:
		resource_layer.set_cell(world_cell, -1)
		return

	var atlas_coords: Vector2i = TileRenderDefinitionScript.get_resource_tile(_resource_name_from_id(resource_id))
	if atlas_coords == TileRenderDefinitionScript.INVALID_ATLAS:
		resource_layer.set_cell(world_cell, -1)
		return
	resource_layer.set_cell(world_cell, TileRenderDefinitionScript.TILE_SOURCE_ID, atlas_coords, 0)


func _render_transition_cell(world_cell: Vector2i) -> void:
	transition_layer.set_cell(world_cell, -1)

	var terrain_id: int = _lookup_terrain_id(world_cell)
	if not _is_water_terrain_id(terrain_id):
		return

	var mask: int = 0
	for direction in CARDINAL_DIRECTIONS:
		var neighbor_terrain: int = _lookup_terrain_id(world_cell + direction)
		if _is_land_terrain_id(neighbor_terrain):
			mask |= _direction_to_mask(direction)

	if mask == 0:
		return

	var atlas_coords: Vector2i = TileRenderDefinitionScript.get_transition_tile(&"water_to_land", mask)
	if atlas_coords == TileRenderDefinitionScript.INVALID_ATLAS:
		return

	transition_layer.set_cell(world_cell, TileRenderDefinitionScript.TILE_SOURCE_ID, atlas_coords, 0)


func _borrow_semantic_chunk_for_world_cell(world_cell: Vector2i) -> WorldSemanticChunk:
	if not _initialized:
		return null
	var chunk_coords: Vector2i = WorldSemanticGridScript.world_cell_to_chunk_coords(world_cell)
	if current_identity.prewarm_chunk_rect.has_point(chunk_coords):
		return semantic_store.borrow_readonly_chunk(chunk_coords)
	return _runtime_semantic_chunks.get(chunk_coords, null)


func _lookup_terrain_id(world_cell: Vector2i) -> int:
	var chunk: WorldSemanticChunk = _borrow_semantic_chunk_for_world_cell(world_cell)
	if chunk == null:
		return WorldSemanticStoreScript.QUERY_MISS
	return chunk.get_terrain_id_by_index(WorldSemanticGridScript.world_cell_to_local_index(world_cell))


func _count_resource_tiles_in_chunk(chunk: WorldSemanticChunk) -> int:
	var resource_count := 0
	for local_index in range(WorldSemanticGridScript.TILES_PER_CHUNK):
		if chunk.get_base_resource_id_by_index(local_index) == WorldSemanticChunkScript.RESOURCE_NONE:
			continue
		resource_count += 1
	return resource_count


func _compute_visible_chunk_rect(center_cell: Vector2i) -> Rect2i:
	var viewport_size := Vector2(1280.0, 720.0)
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport_size = viewport.get_visible_rect().size
	var viewport_world_size: Vector2 = viewport_size * main_camera.zoom
	var half_width: int = int(ceili(viewport_world_size.x / _tile_pixel_size.x / 2.0)) + render_padding_cells
	var half_height: int = int(ceili(viewport_world_size.y / _tile_pixel_size.y / 2.0)) + render_padding_cells
	var visible_cell_rect := Rect2i(
		center_cell - Vector2i(half_width, half_height),
		Vector2i(half_width * 2 + 1, half_height * 2 + 1)
	)

	var min_chunk: Vector2i = WorldSemanticGridScript.world_cell_to_chunk_coords(visible_cell_rect.position)
	var max_chunk: Vector2i = WorldSemanticGridScript.world_cell_to_chunk_coords(visible_cell_rect.end - Vector2i.ONE)
	return Rect2i(min_chunk, max_chunk - min_chunk + Vector2i.ONE)


func _expand_chunk_rect(rect: Rect2i, margin: int) -> Rect2i:
	var safe_margin: int = maxi(margin, 0)
	return Rect2i(
		rect.position - Vector2i(safe_margin, safe_margin),
		rect.size + Vector2i(safe_margin * 2, safe_margin * 2)
	)


func _is_water_terrain_id(terrain_id: int) -> bool:
	return terrain_id == WorldSemanticChunkScript.TERRAIN_WATER or terrain_id == WorldSemanticChunkScript.TERRAIN_SHALLOW_WATER


func _is_land_terrain_id(terrain_id: int) -> bool:
	return terrain_id != WorldSemanticStoreScript.QUERY_MISS and not _is_water_terrain_id(terrain_id)


func _direction_to_mask(direction: Vector2i) -> int:
	if direction == Vector2i.UP:
		return TileRenderDefinitionScript.DIR_N
	if direction == Vector2i.RIGHT:
		return TileRenderDefinitionScript.DIR_E
	if direction == Vector2i.DOWN:
		return TileRenderDefinitionScript.DIR_S
	if direction == Vector2i.LEFT:
		return TileRenderDefinitionScript.DIR_W
	return 0


func _terrain_name_from_id(terrain_id: int) -> StringName:
	match terrain_id:
		WorldSemanticChunkScript.TERRAIN_WATER:
			return GeneratedTileDataScript.TERRAIN_WATER
		WorldSemanticChunkScript.TERRAIN_SHALLOW_WATER:
			return GeneratedTileDataScript.TERRAIN_SHALLOW_WATER
		WorldSemanticChunkScript.TERRAIN_SAND:
			return GeneratedTileDataScript.TERRAIN_SAND
		_:
			return GeneratedTileDataScript.TERRAIN_PLAIN


func _resource_name_from_id(resource_id: int) -> StringName:
	match resource_id:
		WorldSemanticChunkScript.RESOURCE_WOOD:
			return GeneratedTileDataScript.RESOURCE_WOOD
		WorldSemanticChunkScript.RESOURCE_STONE:
			return GeneratedTileDataScript.RESOURCE_STONE
		_:
			return GeneratedTileDataScript.RESOURCE_NONE


func _world_cell_to_global_position(world_cell: Vector2i) -> Vector2:
	return ground_layer.to_global(ground_layer.map_to_local(world_cell))


func _global_position_to_world_cell(world_position: Vector2) -> Vector2i:
	return ground_layer.local_to_map(ground_layer.to_local(world_position))


func _resolve_tile_pixel_size() -> Vector2:
	if ground_layer != null and ground_layer.tile_set != null:
		return Vector2(ground_layer.tile_set.tile_size)
	return Vector2(16.0, 16.0)
