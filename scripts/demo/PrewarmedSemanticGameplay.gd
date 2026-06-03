class_name PrewarmedSemanticGameplay
extends Node2D


const GeneratedTileDataScript := preload("res://scripts/mapgen/GeneratedTileData.gd")
const ResourcePatchGeneratorScript := preload("res://scripts/mapgen/ResourcePatchGenerator.gd")
const TileRenderDefinitionScript := preload("res://scripts/mapgen/TileRenderDefinition.gd")
const WorldSemanticMapSaveScript := preload("res://scripts/mapgen/world/WorldSemanticMapSave.gd")
const WorldSemanticChunkScript := preload("res://scripts/mapgen/world/WorldSemanticChunk.gd")
const WorldSemanticGridScript := preload("res://scripts/mapgen/world/WorldSemanticGrid.gd")
const WorldSemanticStoreScript := preload("res://scripts/mapgen/world/WorldSemanticStore.gd")
const WorldSessionScript := preload("res://scripts/mapgen/world/WorldSession.gd")

const DEFAULT_CAMERA_MOVE_SPEED_PIXELS: float = 960.0
const DEFAULT_DRAG_CAMERA_MAX_SPEED_PIXELS: float = 3584.0
const DEFAULT_ZOOM_STEP: float = 0.1
const MIN_CAMERA_ZOOM: float = 0.5
const MAX_CAMERA_ZOOM: float = 2.0
const DEFAULT_INITIAL_CAMERA_ZOOM: float = 1.0
const SELF_SCENE_PATH := "res://scenes/testScenes/PrewarmedSemanticGameplay.tscn"
const DEFAULT_BOOTSTRAP_LOADING_SCENE_PATH := "res://scenes/loading/RandomGovernanceWorldLoading.tscn"
const VISUAL_STAGE_READY: int = 0
const VISUAL_STAGE_GROUND: int = 1
const VISUAL_STAGE_RESOURCE: int = 2
const VISUAL_STAGE_TRANSITION: int = 3
const VISUAL_STAGE_DONE: int = 4
const VISUAL_BUILD_MODE_INITIAL_VIEW: int = 0
const VISUAL_BUILD_MODE_FULL_PREWARM: int = 1
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
@export var drag_camera_max_speed_pixels_per_second: float = DEFAULT_DRAG_CAMERA_MAX_SPEED_PIXELS
@export var camera_zoom_step: float = DEFAULT_ZOOM_STEP
@export var initial_camera_zoom: float = DEFAULT_INITIAL_CAMERA_ZOOM
@export var bootstrap_loading_when_store_missing: bool = true
@export var auto_build_full_visuals_on_ready: bool = true
@export var visual_build_mode: int = VISUAL_BUILD_MODE_INITIAL_VIEW
@export_file("*.tscn") var bootstrap_loading_scene_path: String = DEFAULT_BOOTSTRAP_LOADING_SCENE_PATH

@onready var main_camera: Camera2D = $MainCamera
@onready var ground_layer: TileMapLayer = $MapRoot/GroundLayer
@onready var resource_layer: TileMapLayer = $MapRoot/ResourceLayer
@onready var transition_layer: TileMapLayer = $MapRoot/TransitionLayer
@onready var save_map_button: Button = $UIRoot/MapSavePanel/VBoxContainer/SaveMapButton
@onready var reset_map_button: Button = $UIRoot/MapSavePanel/VBoxContainer/ResetMapButton
@onready var status_label: Label = $UIRoot/InfoPanel/MarginContainer/VBoxContainer/StatusLabel
@onready var stats_label: Label = $UIRoot/InfoPanel/MarginContainer/VBoxContainer/StatsLabel
@onready var help_label: Label = $UIRoot/InfoPanel/MarginContainer/VBoxContainer/HelpLabel

var semantic_store: WorldSemanticStore = null
var current_identity = null
var player_cell: Vector2i = Vector2i.ZERO
var camera_cell: Vector2i = Vector2i.ZERO
var previous_camera_cell: Vector2i = Vector2i.ZERO
var initialization_failed: bool = false
var last_status_message: String = ""
var is_camera_dragging: bool = false
var camera_drag_last_mouse: Vector2 = Vector2.ZERO
var pending_drag_world_delta: Vector2 = Vector2.ZERO
var _time_since_camera_moved: float = 0.0

var _runtime_generator: ResourcePatchGenerator = ResourcePatchGeneratorScript.new()
var _runtime_semantic_chunks: Dictionary = {}
var _runtime_rendered_resource_counts: Dictionary = {}
var _prewarmed_chunk_resource_counts: Dictionary = {}
var _rendered_chunk_coords: Dictionary = {}
var _tile_pixel_size: Vector2 = Vector2(16.0, 16.0)
var _session_seed: int = 0
var _prewarmed_cell_count: int = 0
var _prewarmed_resource_count: int = 0
var _runtime_active_resource_count: int = 0
var _runtime_generated_chunk_count: int = 0
var _runtime_generated_cell_count: int = 0
var _runtime_generated_resource_count: int = 0
var _runtime_unloaded_chunk_count: int = 0
var _current_visible_chunk_rect: Rect2i = Rect2i()
var _visual_build_stage: int = VISUAL_STAGE_READY
var _visual_build_chunk_cursor: Vector2i = Vector2i.ZERO
var _visual_build_cell_cursor: Vector2i = Vector2i.ZERO
var _visual_build_done_units: int = 0
var _visual_build_total_units: int = 0
var _visual_build_chunk_list: Array[Vector2i] = []
var _visual_build_chunk_index: int = 0
var _runtime_visual_chunk_queue: Array[Vector2i] = []
var _runtime_visual_chunk_queue_set: Dictionary = {}
var _last_camera_chunk_delta: Vector2i = Vector2i.ZERO
var _auto_save_after_initial_build: bool = false


func _ready() -> void:
	if not has_node("/root/WorldSession"):
		initialization_failed = true
		last_status_message = "WorldSession autoload is missing"
		_update_ui()
		return

	if save_map_button != null:
		save_map_button.pressed.connect(_on_save_map_pressed)
	if reset_map_button != null:
		reset_map_button.pressed.connect(_on_reset_map_pressed)

	var session = get_node("/root/WorldSession")
	var restored_saved_world: bool = false
	semantic_store = session.get_ready_semantic_store()
	if semantic_store == null:
		if _try_restore_saved_world(session):
			restored_saved_world = true
			semantic_store = session.get_ready_semantic_store()
		else:
			if bootstrap_loading_when_store_missing and _bootstrap_via_loading_scene():
				return
			initialization_failed = true
			last_status_message = "No READY semantic store is available"
			_update_ui()
			return

	if semantic_store == null:
		if bootstrap_loading_when_store_missing and _bootstrap_via_loading_scene():
			return
		initialization_failed = true
		last_status_message = "No READY semantic store is available"
		_update_ui()
		return

	current_identity = session.identity
	if current_identity == null or not current_identity.is_valid():
		initialization_failed = true
		last_status_message = "WorldSession identity is missing or invalid"
		_update_ui()
		return

	_session_seed = int(current_identity.seed)
	_tile_pixel_size = _resolve_tile_pixel_size()
	player_cell = Vector2i.ZERO
	if not restored_saved_world:
		camera_cell = Vector2i.ZERO
		previous_camera_cell = Vector2i.ZERO

	main_camera.make_current()
	main_camera.zoom = Vector2(initial_camera_zoom, initial_camera_zoom)
	_auto_save_after_initial_build = not WorldSemanticMapSaveScript.has_save()

	if auto_build_full_visuals_on_ready:
		prepare_full_visual_build()
		last_status_message = "Building full prewarmed tilemap"
		_update_ui()
		while process_full_visual_build_budget(0):
			pass

		if is_full_visual_build_complete():
			finalize_full_visual_build()


func _process(delta: float) -> void:
	if initialization_failed:
		return
	if not is_full_visual_build_complete():
		return

	var camera_moved: bool = _apply_pending_drag_motion(delta)
	_update_camera_cell_from_camera_position()
	if camera_moved:
		_time_since_camera_moved = 0.0
	else:
		_time_since_camera_moved += delta
	var allow_unload: bool = not is_camera_dragging and _time_since_camera_moved >= unload_idle_delay_seconds
	_ensure_runtime_chunks_for_visible_view(false, allow_unload)
	_process_runtime_visual_chunk_queue(runtime_visual_chunks_per_frame)
	_update_ui()


func _unhandled_input(event: InputEvent) -> void:
	if initialization_failed:
		return

	if event is InputEventMouseButton and event.pressed:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			is_camera_dragging = true
			camera_drag_last_mouse = get_viewport().get_mouse_position()
			pending_drag_world_delta = Vector2.ZERO
			get_viewport().set_input_as_handled()
			return
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_camera_zoom(main_camera.zoom.x + camera_zoom_step)
			get_viewport().set_input_as_handled()
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_camera_zoom(main_camera.zoom.x - camera_zoom_step)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var released_mouse_event := event as InputEventMouseButton
		if released_mouse_event.button_index == MOUSE_BUTTON_LEFT:
			is_camera_dragging = false
			pending_drag_world_delta = Vector2.ZERO
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and is_camera_dragging:
		var current_mouse := get_viewport().get_mouse_position()
		var mouse_delta := current_mouse - camera_drag_last_mouse
		camera_drag_last_mouse = current_mouse
		if not is_equal_approx(mouse_delta.length(), 0.0):
			pending_drag_world_delta -= mouse_delta / main_camera.zoom.x
		get_viewport().set_input_as_handled()


func get_semantic_store():
	return semantic_store


func prepare_full_visual_build() -> void:
	ground_layer.clear()
	resource_layer.clear()
	transition_layer.clear()
	_runtime_rendered_resource_counts.clear()
	_prewarmed_chunk_resource_counts.clear()
	_rendered_chunk_coords.clear()
	_runtime_visual_chunk_queue.clear()
	_runtime_visual_chunk_queue_set.clear()
	_runtime_active_resource_count = 0
	_runtime_generated_chunk_count = 0
	_runtime_generated_cell_count = 0
	_runtime_generated_resource_count = 0
	_runtime_unloaded_chunk_count = 0
	_prewarmed_cell_count = 0
	_prewarmed_resource_count = 0
	_current_visible_chunk_rect = Rect2i()
	main_camera.global_position = _world_cell_to_global_position(camera_cell)
	_update_camera_cell_from_camera_position()
	_visual_build_chunk_list = _make_initial_visual_build_chunk_list()
	_visual_build_chunk_index = 0
	_visual_build_stage = VISUAL_STAGE_GROUND
	_visual_build_chunk_cursor = _visual_build_chunk_list[0] if not _visual_build_chunk_list.is_empty() else current_identity.prewarm_chunk_rect.position
	_visual_build_cell_cursor = current_identity.prewarm_tile_rect.position
	_visual_build_done_units = 0
	if visual_build_mode == VISUAL_BUILD_MODE_FULL_PREWARM:
		_visual_build_total_units = WorldSemanticGridScript.PREWARM_TOTAL_CHUNKS * 2 \
			+ current_identity.prewarm_tile_rect.size.x * current_identity.prewarm_tile_rect.size.y
	else:
		_visual_build_total_units = _visual_build_chunk_list.size() * 3
	last_status_message = "Visual build prepared"
	_update_ui()


func process_full_visual_build_budget(max_units: int) -> bool:
	if initialization_failed:
		return false
	if _visual_build_stage == VISUAL_STAGE_READY:
		prepare_full_visual_build()
	if _visual_build_stage == VISUAL_STAGE_DONE:
		return false

	var processed_units: int = 0
	while _visual_build_stage != VISUAL_STAGE_DONE and (max_units <= 0 or processed_units < max_units):
		match _visual_build_stage:
			VISUAL_STAGE_GROUND:
				if not _process_next_ground_chunk():
					return false
				processed_units += 1
			VISUAL_STAGE_RESOURCE:
				if not _process_next_resource_chunk():
					return false
				processed_units += 1
			VISUAL_STAGE_TRANSITION:
				if not _process_next_transition_cell():
					return false
				processed_units += 1
			_:
				_visual_build_stage = VISUAL_STAGE_DONE

	return _visual_build_stage != VISUAL_STAGE_DONE


func finalize_full_visual_build() -> void:
	if initialization_failed:
		return
	if not is_full_visual_build_complete():
		return
	_update_camera_cell_from_camera_position()
	_ensure_runtime_chunks_for_visible_view(true)
	last_status_message = "READY"
	if _auto_save_after_initial_build:
		_auto_save_after_initial_build = false
		if WorldSemanticMapSaveScript.save_world(
			current_identity,
			semantic_store,
			_runtime_semantic_chunks,
			camera_cell,
			main_camera.zoom.x
		):
			last_status_message = "READY | auto-saved initial map"
	_update_ui()


func is_full_visual_build_complete() -> bool:
	return _visual_build_stage == VISUAL_STAGE_DONE


func get_visual_build_stage_name() -> String:
	match _visual_build_stage:
		VISUAL_STAGE_READY:
			return "准备绘制"
		VISUAL_STAGE_GROUND:
			return "绘制基础地形"
		VISUAL_STAGE_RESOURCE:
			return "绘制资源层"
		VISUAL_STAGE_TRANSITION:
			return "绘制水陆过渡"
		VISUAL_STAGE_DONE:
			return "绘制完成"
	return "未知绘制阶段"


func get_visual_build_done_units() -> int:
	return _visual_build_done_units


func get_visual_build_total_units() -> int:
	return _visual_build_total_units


func _try_restore_saved_world(session) -> bool:
	if not WorldSemanticMapSaveScript.has_save():
		return false
	if session.state != WorldSessionScript.WorldSessionState.EMPTY:
		return false

	var loaded_world: Dictionary = WorldSemanticMapSaveScript.load_world()
	if loaded_world.is_empty():
		return false

	if not session.restore_ready_world(loaded_world["identity"], loaded_world["semantic_store"]):
		return false

	_runtime_semantic_chunks = loaded_world["runtime_chunks"]
	_runtime_generated_chunk_count = _runtime_semantic_chunks.size()
	_runtime_generated_cell_count = _runtime_generated_chunk_count * WorldSemanticGridScript.TILES_PER_CHUNK
	_runtime_generated_resource_count = 0
	for chunk_variant in _runtime_semantic_chunks.values():
		var runtime_chunk: WorldSemanticChunk = chunk_variant
		if runtime_chunk == null:
			continue
		_runtime_generated_resource_count += _count_resource_tiles_in_chunk(runtime_chunk)
	current_identity = loaded_world["identity"]
	semantic_store = loaded_world["semantic_store"]
	player_cell = Vector2i.ZERO
	camera_cell = loaded_world.get("camera_cell", Vector2i.ZERO)
	previous_camera_cell = camera_cell
	initial_camera_zoom = float(loaded_world.get("camera_zoom", initial_camera_zoom))
	last_status_message = "Loaded saved map"
	return true


func _on_save_map_pressed() -> void:
	if initialization_failed:
		return
	if current_identity == null or semantic_store == null:
		last_status_message = "Save failed: world is not ready"
		_update_ui()
		return

	if WorldSemanticMapSaveScript.save_world(
		current_identity,
		semantic_store,
		_runtime_semantic_chunks,
		camera_cell,
		main_camera.zoom.x
	):
		last_status_message = "Map saved"
	else:
		last_status_message = "Save failed"
	_update_ui()


func _on_reset_map_pressed() -> void:
	if has_node("/root/WorldSession"):
		var session = get_node("/root/WorldSession")
		if session.state == WorldSessionScript.WorldSessionState.READY:
			session.end_current_world()
		elif session.state == WorldSessionScript.WorldSessionState.PREWARMING:
			session.invalidate_current_prewarm()

	if _bootstrap_via_loading_scene():
		queue_free()
		return

	initialization_failed = true
	last_status_message = "Reset failed: could not start loading"
	_update_ui()


func is_world_cell_accessible(_world_cell: Vector2i) -> bool:
	return true


func try_move_player_to_cell(world_cell: Vector2i) -> bool:
	_ensure_runtime_chunk_for_world_cell(world_cell)
	player_cell = world_cell
	last_status_message = "Player moved to %s" % str(world_cell)
	return true


func try_move_camera_to_cell(world_cell: Vector2i) -> bool:
	_ensure_runtime_chunk_for_world_cell(world_cell)
	camera_cell = world_cell
	main_camera.global_position = _world_cell_to_global_position(camera_cell)
	_ensure_runtime_chunks_for_visible_view(true)
	_process_runtime_visual_chunk_queue(runtime_visual_chunks_per_frame)
	last_status_message = "Camera moved to %s" % str(world_cell)
	return true


func get_terrain_id(world_cell: Vector2i) -> int:
	if semantic_store == null:
		return WorldSemanticStoreScript.QUERY_MISS
	return _lookup_terrain_id(world_cell)


func get_base_resource_id(world_cell: Vector2i) -> int:
	if semantic_store == null:
		return WorldSemanticStoreScript.QUERY_MISS

	var chunk: WorldSemanticChunk = _borrow_semantic_chunk_for_world_cell(world_cell)
	if chunk == null:
		return WorldSemanticStoreScript.QUERY_MISS

	return chunk.get_base_resource_id_by_index(WorldSemanticGridScript.world_cell_to_local_index(world_cell))


func get_flags(world_cell: Vector2i) -> int:
	if semantic_store == null:
		return WorldSemanticStoreScript.QUERY_MISS

	var chunk: WorldSemanticChunk = _borrow_semantic_chunk_for_world_cell(world_cell)
	if chunk == null:
		return WorldSemanticStoreScript.QUERY_MISS

	return chunk.get_flags_by_index(WorldSemanticGridScript.world_cell_to_local_index(world_cell))


func get_base_resource_amount(world_cell: Vector2i) -> int:
	if semantic_store == null:
		return WorldSemanticStoreScript.QUERY_MISS

	var chunk: WorldSemanticChunk = _borrow_semantic_chunk_for_world_cell(world_cell)
	if chunk == null:
		return WorldSemanticStoreScript.QUERY_MISS

	return chunk.get_base_resource_amount_by_index(WorldSemanticGridScript.world_cell_to_local_index(world_cell))


func get_patch_key_payload(world_cell: Vector2i, out_payload: PackedInt32Array) -> int:
	if semantic_store == null:
		return WorldSemanticStoreScript.PatchLookupResult.MISS
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


func _apply_pending_drag_motion(delta: float) -> bool:
	if pending_drag_world_delta.is_zero_approx():
		return false

	var max_step: float = drag_camera_max_speed_pixels_per_second * delta
	var step: Vector2 = pending_drag_world_delta
	if max_step > 0.0 and step.length() > max_step:
		step = step.normalized() * max_step

	var next_position: Vector2 = main_camera.global_position + step
	if _can_show_camera_position_without_gray(next_position):
		main_camera.global_position = next_position
		pending_drag_world_delta = Vector2.ZERO
		return true

	_request_visual_coverage_for_camera_position(next_position)
	pending_drag_world_delta = Vector2.ZERO
	return false


func _set_camera_zoom(next_zoom: float) -> void:
	var clamped_zoom := clampf(next_zoom, MIN_CAMERA_ZOOM, MAX_CAMERA_ZOOM)
	main_camera.zoom = Vector2(clamped_zoom, clamped_zoom)
	_ensure_runtime_chunks_for_visible_view(true)
	_process_runtime_visual_chunk_queue(runtime_visual_chunks_per_frame)


func _update_camera_cell_from_camera_position() -> void:
	previous_camera_cell = camera_cell
	camera_cell = _global_position_to_world_cell(main_camera.global_position)
	var previous_chunk: Vector2i = WorldSemanticGridScript.world_cell_to_chunk_coords(previous_camera_cell)
	var current_chunk: Vector2i = WorldSemanticGridScript.world_cell_to_chunk_coords(camera_cell)
	_last_camera_chunk_delta = current_chunk - previous_chunk


func _make_initial_visual_build_chunk_list() -> Array[Vector2i]:
	if visual_build_mode == VISUAL_BUILD_MODE_FULL_PREWARM:
		return WorldSemanticGridScript.enumerate_prewarm_chunk_coords()

	var visible_chunk_rect := _compute_visible_chunk_rect(camera_cell)
	var target_chunk_rect := _expand_chunk_rect(visible_chunk_rect, runtime_chunk_preload_margin)
	var result: Array[Vector2i] = []
	for chunk_y in range(target_chunk_rect.position.y, target_chunk_rect.end.y):
		for chunk_x in range(target_chunk_rect.position.x, target_chunk_rect.end.x):
			var chunk_coords := Vector2i(chunk_x, chunk_y)
			if not current_identity.prewarm_chunk_rect.has_point(chunk_coords):
				continue
			result.append(chunk_coords)
	return result


func _process_next_ground_chunk() -> bool:
	var chunk: WorldSemanticChunk = _borrow_visual_build_chunk()
	if chunk == null:
		return false
	_render_semantic_chunk_ground(chunk, false)
	_visual_build_done_units += 1
	_advance_visual_build_chunk_cursor(VISUAL_STAGE_RESOURCE)
	return true


func _process_next_resource_chunk() -> bool:
	var chunk: WorldSemanticChunk = _borrow_visual_build_chunk()
	if chunk == null:
		return false
	_render_semantic_chunk_resources(chunk, false)
	_visual_build_done_units += 1
	_prewarmed_chunk_resource_counts[chunk.chunk_coords] = _count_resource_tiles_in_chunk(chunk)
	_rendered_chunk_coords[chunk.chunk_coords] = true
	_advance_visual_build_chunk_cursor(VISUAL_STAGE_TRANSITION)
	return true


func _process_next_transition_cell() -> bool:
	if visual_build_mode == VISUAL_BUILD_MODE_INITIAL_VIEW:
		if _visual_build_chunk_index >= _visual_build_chunk_list.size():
			_visual_build_stage = VISUAL_STAGE_DONE
			return true
		_refresh_transition_cells_for_chunk(_visual_build_chunk_list[_visual_build_chunk_index])
		_visual_build_done_units += 1
		_visual_build_chunk_index += 1
		if _visual_build_chunk_index >= _visual_build_chunk_list.size():
			_visual_build_stage = VISUAL_STAGE_DONE
		return true

	_render_transition_cell(_visual_build_cell_cursor)
	_visual_build_done_units += 1
	_advance_visual_build_cell_cursor()
	return true


func _borrow_visual_build_chunk() -> WorldSemanticChunk:
	if visual_build_mode == VISUAL_BUILD_MODE_INITIAL_VIEW:
		if _visual_build_chunk_index >= _visual_build_chunk_list.size():
			_visual_build_stage = VISUAL_STAGE_DONE
			return null
		_visual_build_chunk_cursor = _visual_build_chunk_list[_visual_build_chunk_index]

	var chunk: WorldSemanticChunk = semantic_store.borrow_readonly_chunk(_visual_build_chunk_cursor)
	if chunk == null:
		initialization_failed = true
		last_status_message = "Missing prewarmed chunk %s" % str(_visual_build_chunk_cursor)
		_update_ui()
	return chunk


func _advance_visual_build_chunk_cursor(next_stage: int) -> void:
	if visual_build_mode == VISUAL_BUILD_MODE_INITIAL_VIEW:
		_visual_build_chunk_index += 1
		if _visual_build_chunk_index < _visual_build_chunk_list.size():
			return

		_visual_build_chunk_index = 0
		_visual_build_stage = next_stage
		if _visual_build_chunk_list.is_empty():
			_visual_build_stage = VISUAL_STAGE_DONE
		else:
			_visual_build_chunk_cursor = _visual_build_chunk_list[0]
		return

	_visual_build_chunk_cursor.x += 1
	if _visual_build_chunk_cursor.x < current_identity.prewarm_chunk_rect.end.x:
		return

	_visual_build_chunk_cursor.x = current_identity.prewarm_chunk_rect.position.x
	_visual_build_chunk_cursor.y += 1
	if _visual_build_chunk_cursor.y < current_identity.prewarm_chunk_rect.end.y:
		return

	_visual_build_chunk_cursor = current_identity.prewarm_chunk_rect.position
	_visual_build_stage = next_stage


func _advance_visual_build_cell_cursor() -> void:
	_visual_build_cell_cursor.x += 1
	if _visual_build_cell_cursor.x < current_identity.prewarm_tile_rect.end.x:
		return

	_visual_build_cell_cursor.x = current_identity.prewarm_tile_rect.position.x
	_visual_build_cell_cursor.y += 1
	if _visual_build_cell_cursor.y < current_identity.prewarm_tile_rect.end.y:
		return

	_visual_build_stage = VISUAL_STAGE_DONE


func _render_semantic_chunk_base_and_resources(chunk: WorldSemanticChunk, is_runtime_chunk: bool) -> void:
	_render_semantic_chunk_ground(chunk, is_runtime_chunk)
	_render_semantic_chunk_resources(chunk, is_runtime_chunk)


func _render_semantic_chunk_ground(chunk: WorldSemanticChunk, is_runtime_chunk: bool) -> void:
	var chunk_origin := WorldSemanticGridScript.chunk_coords_to_origin_cell(chunk.chunk_coords)
	var chunk_width := WorldSemanticGridScript.SEMANTIC_CHUNK_SIZE.x
	var chunk_height := WorldSemanticGridScript.SEMANTIC_CHUNK_SIZE.y

	for local_y in range(chunk_height):
		for local_x in range(chunk_width):
			var local_index := local_y * chunk_width + local_x
			var world_cell := chunk_origin + Vector2i(local_x, local_y)
			var terrain_id := chunk.get_terrain_id_by_index(local_index)

			_render_base_cell(world_cell, terrain_id)

			if not is_runtime_chunk:
				_prewarmed_cell_count += 1


func _render_semantic_chunk_resources(chunk: WorldSemanticChunk, is_runtime_chunk: bool) -> void:
	var chunk_origin := WorldSemanticGridScript.chunk_coords_to_origin_cell(chunk.chunk_coords)
	var chunk_width := WorldSemanticGridScript.SEMANTIC_CHUNK_SIZE.x
	var chunk_height := WorldSemanticGridScript.SEMANTIC_CHUNK_SIZE.y

	for local_y in range(chunk_height):
		for local_x in range(chunk_width):
			var local_index := local_y * chunk_width + local_x
			var world_cell := chunk_origin + Vector2i(local_x, local_y)
			var resource_id := chunk.get_base_resource_id_by_index(local_index)

			_render_resource_cell(world_cell, resource_id)

			if not is_runtime_chunk:
				if resource_id != WorldSemanticChunkScript.RESOURCE_NONE:
					_prewarmed_resource_count += 1


func _render_base_cell(world_cell: Vector2i, terrain_id: int) -> void:
	var atlas_coords := TileRenderDefinitionScript.get_base_tile(_terrain_name_from_id(terrain_id))
	if atlas_coords == TileRenderDefinitionScript.INVALID_ATLAS:
		ground_layer.set_cell(world_cell, -1)
		return
	ground_layer.set_cell(world_cell, TileRenderDefinitionScript.TILE_SOURCE_ID, atlas_coords, 0)


func _render_resource_cell(world_cell: Vector2i, resource_id: int) -> void:
	if resource_id == WorldSemanticChunkScript.RESOURCE_NONE:
		resource_layer.set_cell(world_cell, -1)
		return

	var atlas_coords := TileRenderDefinitionScript.get_resource_tile(_resource_name_from_id(resource_id))
	if atlas_coords == TileRenderDefinitionScript.INVALID_ATLAS:
		resource_layer.set_cell(world_cell, -1)
		return
	resource_layer.set_cell(world_cell, TileRenderDefinitionScript.TILE_SOURCE_ID, atlas_coords, 0)


func _render_transition_cell(world_cell: Vector2i) -> void:
	transition_layer.set_cell(world_cell, -1)

	var terrain_id := _lookup_terrain_id(world_cell)
	if not _is_water_terrain_id(terrain_id):
		return

	var mask := 0
	for direction in CARDINAL_DIRECTIONS:
		var neighbor_terrain := _lookup_terrain_id(world_cell + direction)
		if _is_land_terrain_id(neighbor_terrain):
			mask |= _direction_to_mask(direction)

	if mask == 0:
		return

	var atlas_coords := TileRenderDefinitionScript.get_transition_tile(&"water_to_land", mask)
	if atlas_coords == TileRenderDefinitionScript.INVALID_ATLAS:
		return

	transition_layer.set_cell(world_cell, TileRenderDefinitionScript.TILE_SOURCE_ID, atlas_coords, 0)


func _ensure_runtime_chunks_for_visible_view(force_refresh: bool, allow_unload: bool = true) -> void:
	var visible_chunk_rect := _compute_visible_chunk_rect(camera_cell)
	if not force_refresh and visible_chunk_rect == _current_visible_chunk_rect:
		return

	_current_visible_chunk_rect = visible_chunk_rect
	var target_chunk_rect := _expand_chunk_rect(visible_chunk_rect, runtime_chunk_preload_margin)
	var keep_chunk_rect := _expand_chunk_rect(visible_chunk_rect, runtime_chunk_keep_margin)

	_render_chunk_rect_immediately(visible_chunk_rect)
	_enqueue_chunk_rect_for_preload(target_chunk_rect, visible_chunk_rect)

	if allow_unload:
		_unload_rendered_prewarm_chunks_outside_keep_rect(keep_chunk_rect)
		_unload_runtime_chunks_outside_keep_rect(keep_chunk_rect)
	else:
		_prune_runtime_visual_chunk_queue(keep_chunk_rect)


func _ensure_runtime_chunk_for_world_cell(world_cell: Vector2i) -> void:
	var chunk_coords := WorldSemanticGridScript.world_cell_to_chunk_coords(world_cell)
	if current_identity.prewarm_chunk_rect.has_point(chunk_coords):
		if not _rendered_chunk_coords.has(chunk_coords):
			_render_prewarmed_chunk(chunk_coords)
		return
	if _runtime_semantic_chunks.has(chunk_coords):
		if not _rendered_chunk_coords.has(chunk_coords):
			_render_runtime_chunk(chunk_coords)
		return
	_generate_and_render_runtime_chunk(chunk_coords)


func _enqueue_runtime_visual_chunk(chunk_coords: Vector2i) -> void:
	if _runtime_visual_chunk_queue_set.has(chunk_coords):
		return
	_runtime_visual_chunk_queue_set[chunk_coords] = true
	_runtime_visual_chunk_queue.append(chunk_coords)


func _can_show_camera_position_without_gray(world_position: Vector2) -> bool:
	var target_camera_cell := _global_position_to_world_cell(world_position)
	var visible_chunk_rect := _compute_visible_chunk_rect(target_camera_cell)
	var safe_chunk_rect := _expand_chunk_rect(visible_chunk_rect, camera_coverage_safety_margin)

	for chunk_y in range(safe_chunk_rect.position.y, safe_chunk_rect.end.y):
		for chunk_x in range(safe_chunk_rect.position.x, safe_chunk_rect.end.x):
			var chunk_coords := Vector2i(chunk_x, chunk_y)
			if _rendered_chunk_coords.has(chunk_coords):
				continue
			return false
	return true


func _request_visual_coverage_for_camera_position(world_position: Vector2) -> void:
	var target_camera_cell := _global_position_to_world_cell(world_position)
	var visible_chunk_rect := _compute_visible_chunk_rect(target_camera_cell)
	var target_chunk_rect := _expand_chunk_rect(visible_chunk_rect, runtime_chunk_preload_margin)
	for chunk_y in range(target_chunk_rect.position.y, target_chunk_rect.end.y):
		for chunk_x in range(target_chunk_rect.position.x, target_chunk_rect.end.x):
			var chunk_coords := Vector2i(chunk_x, chunk_y)
			if _rendered_chunk_coords.has(chunk_coords):
				continue
			_enqueue_runtime_visual_chunk(chunk_coords)


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
	var camera_chunk: Vector2i = WorldSemanticGridScript.world_cell_to_chunk_coords(camera_cell)
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
		return

	var chunk: WorldSemanticChunk = WorldSemanticChunkScript.from_validated_result(chunk_result)
	if chunk == null:
		return

	_runtime_semantic_chunks[chunk_coords] = chunk
	_runtime_generated_chunk_count += 1
	_runtime_generated_cell_count += WorldSemanticGridScript.TILES_PER_CHUNK
	_runtime_generated_resource_count += _count_resource_tiles_in_chunk(chunk)
	_render_runtime_chunk(chunk_coords)


func _render_runtime_chunk(chunk_coords: Vector2i) -> void:
	var chunk: WorldSemanticChunk = _runtime_semantic_chunks.get(chunk_coords, null)
	if chunk == null:
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

	var chunk_origin := WorldSemanticGridScript.chunk_coords_to_origin_cell(chunk_coords)
	var chunk_width := WorldSemanticGridScript.SEMANTIC_CHUNK_SIZE.x
	var chunk_height := WorldSemanticGridScript.SEMANTIC_CHUNK_SIZE.y

	for local_y in range(chunk_height):
		for local_x in range(chunk_width):
			var world_cell := chunk_origin + Vector2i(local_x, local_y)
			_clear_rendered_cell(world_cell)

	_runtime_active_resource_count = maxi(
		_runtime_active_resource_count - int(_runtime_rendered_resource_counts.get(chunk_coords, 0)),
		0
	)
	_runtime_rendered_resource_counts.erase(chunk_coords)
	_rendered_chunk_coords.erase(chunk_coords)
	_runtime_unloaded_chunk_count += 1
	_refresh_transition_cells_for_chunk(chunk_coords)


func _clear_rendered_chunk_cells(chunk_coords: Vector2i) -> void:
	var chunk_origin := WorldSemanticGridScript.chunk_coords_to_origin_cell(chunk_coords)
	var chunk_width := WorldSemanticGridScript.SEMANTIC_CHUNK_SIZE.x
	var chunk_height := WorldSemanticGridScript.SEMANTIC_CHUNK_SIZE.y

	for local_y in range(chunk_height):
		for local_x in range(chunk_width):
			_clear_rendered_cell(chunk_origin + Vector2i(local_x, local_y))


func _clear_rendered_cell(world_cell: Vector2i) -> void:
	ground_layer.set_cell(world_cell, -1)
	resource_layer.set_cell(world_cell, -1)
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
	var chunk_origin := WorldSemanticGridScript.chunk_coords_to_origin_cell(chunk_coords)
	var chunk_width := WorldSemanticGridScript.SEMANTIC_CHUNK_SIZE.x
	var chunk_height := WorldSemanticGridScript.SEMANTIC_CHUNK_SIZE.y
	var start_cell := chunk_origin - Vector2i.ONE
	var end_cell := chunk_origin + Vector2i(chunk_width, chunk_height)

	for world_y in range(start_cell.y, end_cell.y + 1):
		for world_x in range(start_cell.x, end_cell.x + 1):
			_render_transition_cell(Vector2i(world_x, world_y))


func _compute_visible_chunk_rect(center_cell: Vector2i) -> Rect2i:
	var viewport_world_size := get_viewport_rect().size * main_camera.zoom
	var half_width := int(ceili(viewport_world_size.x / _tile_pixel_size.x / 2.0)) + render_padding_cells
	var half_height := int(ceili(viewport_world_size.y / _tile_pixel_size.y / 2.0)) + render_padding_cells
	var visible_cell_rect := Rect2i(
		center_cell - Vector2i(half_width, half_height),
		Vector2i(half_width * 2 + 1, half_height * 2 + 1)
	)

	var min_chunk := WorldSemanticGridScript.world_cell_to_chunk_coords(visible_cell_rect.position)
	var max_chunk := WorldSemanticGridScript.world_cell_to_chunk_coords(visible_cell_rect.end - Vector2i.ONE)
	return Rect2i(min_chunk, max_chunk - min_chunk + Vector2i.ONE)


func _expand_chunk_rect(rect: Rect2i, margin: int) -> Rect2i:
	var safe_margin: int = maxi(margin, 0)
	return Rect2i(
		rect.position - Vector2i(safe_margin, safe_margin),
		rect.size + Vector2i(safe_margin * 2, safe_margin * 2)
	)


func _count_resource_tiles_in_chunk(chunk: WorldSemanticChunk) -> int:
	var resource_count := 0
	for local_index in range(WorldSemanticGridScript.TILES_PER_CHUNK):
		if chunk.get_base_resource_id_by_index(local_index) == WorldSemanticChunkScript.RESOURCE_NONE:
			continue
		resource_count += 1
	return resource_count


func _borrow_semantic_chunk_for_world_cell(world_cell: Vector2i) -> WorldSemanticChunk:
	var chunk_coords := WorldSemanticGridScript.world_cell_to_chunk_coords(world_cell)
	if current_identity.prewarm_chunk_rect.has_point(chunk_coords):
		return semantic_store.borrow_readonly_chunk(chunk_coords)
	return _runtime_semantic_chunks.get(chunk_coords, null)


func _lookup_terrain_id(world_cell: Vector2i) -> int:
	var chunk: WorldSemanticChunk = _borrow_semantic_chunk_for_world_cell(world_cell)
	if chunk == null:
		return WorldSemanticStoreScript.QUERY_MISS
	return chunk.get_terrain_id_by_index(WorldSemanticGridScript.world_cell_to_local_index(world_cell))


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


func _world_cell_to_global_position(world_cell: Vector2i) -> Vector2:
	return ground_layer.to_global(ground_layer.map_to_local(world_cell))


func _global_position_to_world_cell(world_position: Vector2) -> Vector2i:
	return ground_layer.local_to_map(ground_layer.to_local(world_position))


func _resolve_tile_pixel_size() -> Vector2:
	if ground_layer != null and ground_layer.tile_set != null:
		return Vector2(ground_layer.tile_set.tile_size)
	return Vector2(16.0, 16.0)


func _bootstrap_via_loading_scene() -> bool:
	if bootstrap_loading_scene_path.is_empty():
		return false

	var loading_scene_resource: Variant = load(bootstrap_loading_scene_path)
	if loading_scene_resource == null or not (loading_scene_resource is PackedScene):
		return false

	var gameplay_scene_resource: Variant = load(SELF_SCENE_PATH)
	if gameplay_scene_resource == null or not (gameplay_scene_resource is PackedScene):
		return false

	var loading_instance: Node = (loading_scene_resource as PackedScene).instantiate()
	if loading_instance == null:
		return false

	loading_instance.set("auto_start", true)
	loading_instance.set("auto_transition_to_gameplay", true)
	loading_instance.set("auto_free_on_transition", true)
	loading_instance.set("gameplay_scene", gameplay_scene_resource)

	if get_parent() != null:
		get_parent().call_deferred("add_child", loading_instance)
	else:
		get_tree().root.call_deferred("add_child", loading_instance)

	call_deferred("queue_free")
	return true


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


func _update_ui() -> void:
	if status_label != null:
		status_label.text = "状态: %s" % ("FAILED" if initialization_failed else "READY")
	if stats_label != null:
		stats_label.text = "seed=%d | camera=%s | visible_chunks=%s | prewarm_cells=%d | prewarm_resources=%d | runtime_saved_chunks=%d | runtime_active_chunks=%d | runtime_active_cells=%d | runtime_active_resources=%d | runtime_generated_total=%d | runtime_unloaded_total=%d | %s" % [
			_session_seed,
			str(camera_cell),
			str(_current_visible_chunk_rect),
			_prewarmed_cell_count,
			_prewarmed_resource_count,
			_runtime_semantic_chunks.size(),
			_runtime_rendered_resource_counts.size(),
			_runtime_rendered_resource_counts.size() * WorldSemanticGridScript.TILES_PER_CHUNK,
			_runtime_active_resource_count,
			_runtime_generated_chunk_count,
			_runtime_unloaded_chunk_count,
			last_status_message,
		]
	if help_label != null:
		if initialization_failed:
			help_label.text = last_status_message
		else:
			help_label.text = "鼠标左键拖拽镜头；滚轮向上放大，滚轮向下缩小。2048x2048 预创建范围一次性铺满；预创建区永久常驻，范围外按 chunk 流式生成并卸载。"
