class_name ChunkStreamingManager
extends Node


const GeneratedMapDataScript := preload("res://scripts/mapgen/GeneratedMapData.gd")
const GeneratedMapRendererScript := preload("res://scripts/mapgen/GeneratedMapRenderer.gd")

enum ChunkState {
	EMPTY,
	QUEUED,
	GENERATING,
	GENERATED,
	APPLYING,
	VISIBLE,
	UNLOADING,
	UNLOADED,
}

@export var map_seed: int = 0
@export var chunk_size: int = 32
@export var visible_radius: int = 2
@export var preload_radius: int = 1
@export var directional_preload_extra: int = 3
@export var max_generate_cells_per_frame: int = 512
@export var max_tile_writes_per_frame: int = 768
@export var max_unload_cells_per_frame: int = 1024
@export var keep_radius: int = 5
@export var enable_chunk_cache: bool = true
@export var max_cached_chunks: int = 64
@export var include_resources_runtime: bool = false
@export var include_transitions_runtime: bool = false

var map_data: RefCounted
var source_map_data: RefCounted = null
var generator: RefCounted
var renderer: GeneratedMapRenderer
var base_layer: TileMapLayer
var resource_layer: TileMapLayer
var transition_layer: TileMapLayer
var camera: Camera2D
var _runtime_uses_source_map: bool = false
var _runtime_allow_source_map_fallback_generation: bool = false

var chunk_states: Dictionary = {}
var generation_queue: Array[Vector2i] = []
var apply_queue: Array[Dictionary] = []
var unload_queue: Array[Dictionary] = []
var loaded_chunks: Dictionary = {}
var cached_chunks: Dictionary = {}
var cached_chunk_order: Array[Vector2i] = []
var required_chunks: Dictionary = {}
var preload_chunks: Dictionary = {}
var active_generation_task: Dictionary = {}
var last_camera_position: Vector2 = Vector2.ZERO
var camera_velocity: Vector2 = Vector2.ZERO
var current_camera_cell: Vector2i = Vector2i.ZERO
var current_camera_chunk: Vector2i = Vector2i.ZERO
var process_frame_count: int = 0
var is_runtime_initialized: bool = false
var generated_cells_this_frame: int = 0
var last_generation_time_ms: float = 0.0
var tile_writes_this_frame: int = 0
var last_apply_time_ms: float = 0.0
var unloaded_cells_this_frame: int = 0
var last_unload_time_ms: float = 0.0
var last_loaded_debug_chunks: Array[Vector2i] = []
var last_unloaded_debug_chunks: Array[Vector2i] = []
var last_refreshed_debug_chunks: Array[Vector2i] = []
var visible_chunks: Dictionary = {}


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	process_frame_count += 1
	if not is_runtime_initialized:
		return
	last_loaded_debug_chunks.clear()
	last_unloaded_debug_chunks.clear()
	last_refreshed_debug_chunks.clear()
	_update_camera_snapshot(delta)
	_update_required_chunks()
	_process_generation_budget()
	_process_apply_budget()
	_process_unload_budget()


func setup_runtime(
	next_seed: int,
	next_generator: RefCounted,
	next_renderer: GeneratedMapRenderer,
	next_base_layer: TileMapLayer = null,
	next_resource_layer: TileMapLayer = null,
	next_transition_layer: TileMapLayer = null,
	next_camera: Camera2D = null,
	next_source_map_data: RefCounted = null
) -> void:
	map_seed = next_seed
	generator = next_generator
	renderer = next_renderer
	base_layer = next_base_layer
	resource_layer = next_resource_layer
	transition_layer = next_transition_layer
	camera = next_camera
	source_map_data = next_source_map_data
	_runtime_uses_source_map = source_map_data != null
	_runtime_allow_source_map_fallback_generation = _runtime_uses_source_map
	if _runtime_uses_source_map and source_map_data != null and int(source_map_data.chunk_size) > 0:
		chunk_size = max(int(source_map_data.chunk_size), 1)

	map_data = GeneratedMapDataScript.new()
	map_data.setup_sparse(map_seed, chunk_size)

	chunk_states.clear()
	generation_queue.clear()
	apply_queue.clear()
	unload_queue.clear()
	loaded_chunks.clear()
	cached_chunks.clear()
	cached_chunk_order.clear()
	required_chunks.clear()
	preload_chunks.clear()
	active_generation_task.clear()
	camera_velocity = Vector2.ZERO
	current_camera_cell = Vector2i.ZERO
	current_camera_chunk = Vector2i.ZERO
	generated_cells_this_frame = 0
	last_generation_time_ms = 0.0
	tile_writes_this_frame = 0
	last_apply_time_ms = 0.0
	unloaded_cells_this_frame = 0
	last_unload_time_ms = 0.0
	last_loaded_debug_chunks.clear()
	last_unloaded_debug_chunks.clear()
	last_refreshed_debug_chunks.clear()
	visible_chunks.clear()
	last_camera_position = _get_camera_position()
	is_runtime_initialized = true
	_update_camera_snapshot(1.0)
	_update_required_chunks()


func get_debug_snapshot() -> Dictionary:
	var visible_chunk_rect := get_visible_chunk_rect()
	var keep_chunk_rect := get_keep_chunk_rect()
	return {
		"ready": is_runtime_initialized,
		"process_frames": get_process_frame_count(),
		"camera_cell": get_current_camera_cell(),
		"camera_chunk": get_current_camera_chunk(),
		"visible_chunk_rect": visible_chunk_rect,
		"keep_chunk_rect": keep_chunk_rect,
		"visible_chunk_count_estimate": max(visible_chunk_rect.size.x, 0) * max(visible_chunk_rect.size.y, 0),
		"generation_queue_size": get_generation_queue_size(),
		"generation_queue_preview": get_generation_queue_preview(3),
		"apply_queue_size": get_apply_queue_size(),
		"unload_queue_size": get_unload_queue_size(),
		"loaded_chunk_count": get_loaded_chunk_count(),
		"loaded_chunk_preview": get_loaded_chunk_preview(3),
		"cached_chunk_count": get_cached_chunk_count(),
		"required_chunk_count": get_required_chunk_count(),
		"queued_chunk_count": get_queued_chunk_count(),
		"queued_state_chunk_count": get_queued_state_chunk_count(),
		"queue_head_chunk": get_generation_queue_head(),
		"preload_chunk_count": get_preload_chunk_count(),
		"active_generation_tasks_count": get_active_generation_task_count(),
		"generated_cells_this_frame": get_generated_cells_this_frame(),
		"generation_time_ms": get_last_generation_time_ms(),
		"tile_writes_this_frame": get_tile_writes_this_frame(),
		"apply_time_ms": get_last_apply_time_ms(),
		"unloaded_cells_this_frame": get_unloaded_cells_this_frame(),
		"unload_time_ms": get_last_unload_time_ms(),
		"visible_chunk_count": get_chunk_state_count(ChunkState.VISIBLE),
		"applying_chunk_count": get_chunk_state_count(ChunkState.APPLYING),
		"unloading_chunk_count": get_chunk_state_count(ChunkState.UNLOADING),
		"last_loaded_chunk_preview": get_last_loaded_chunk_preview(3),
		"last_unloaded_chunk_preview": get_last_unloaded_chunk_preview(3),
		"last_refreshed_chunk_preview": get_last_refreshed_chunk_preview(3),
		"camera_velocity": camera_velocity,
		"map_tile_count": 0 if map_data == null else map_data.tiles.size(),
	}


func flush_pending_runtime_tasks(max_iterations: int = 16) -> void:
	if not is_runtime_initialized:
		return

	var safe_iterations: int = max(max_iterations, 0)
	for _iteration in range(safe_iterations):
		if generation_queue.is_empty() and active_generation_task.is_empty() and apply_queue.is_empty() and unload_queue.is_empty():
			break
		_process_generation_budget()
		_process_apply_budget()
		_process_unload_budget()


func flush_until_visible_base_ready(max_iterations: int = 64) -> void:
	if not is_runtime_initialized:
		return

	var safe_iterations: int = max(max_iterations, 0)
	for _iteration in range(safe_iterations):
		_update_required_chunks()
		if is_visible_base_ready():
			break
		_process_generation_budget()
		_process_apply_budget()
		_process_unload_budget()


func is_visible_base_ready() -> bool:
	var visible_rect := get_visible_chunk_rect()
	for y in range(visible_rect.position.y, visible_rect.position.y + visible_rect.size.y):
		for x in range(visible_rect.position.x, visible_rect.position.x + visible_rect.size.x):
			if not _is_chunk_base_ready(Vector2i(x, y)):
				return false
	return true


func get_process_frame_count() -> int:
	return process_frame_count


func get_current_camera_cell() -> Vector2i:
	return current_camera_cell


func get_current_camera_chunk() -> Vector2i:
	return current_camera_chunk


func get_generation_queue_size() -> int:
	return generation_queue.size()


func get_apply_queue_size() -> int:
	return apply_queue.size()


func get_unload_queue_size() -> int:
	return unload_queue.size()


func get_loaded_chunk_count() -> int:
	return loaded_chunks.size()


func get_cached_chunk_count() -> int:
	return cached_chunks.size()


func get_loaded_chunk_preview(limit: int = 3) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var sorted_chunks: Array[Vector2i] = []
	for chunk_coords in loaded_chunks.keys():
		sorted_chunks.append(chunk_coords)
	sorted_chunks.sort()
	for chunk_index in range(min(max(limit, 0), sorted_chunks.size())):
		result.append(sorted_chunks[chunk_index])
	return result


func get_required_chunk_count() -> int:
	return required_chunks.size()


func get_queued_chunk_count() -> int:
	return generation_queue.size()


func get_queued_state_chunk_count() -> int:
	return get_chunk_state_count(ChunkState.QUEUED)


func get_generation_queue_head() -> Vector2i:
	if generation_queue.is_empty():
		return Vector2i.ZERO
	return generation_queue[0]


func get_generation_queue_preview(limit: int = 3) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var safe_limit: int = max(limit, 0)
	for queue_index in range(min(safe_limit, generation_queue.size())):
		result.append(generation_queue[queue_index])
	return result


func get_preload_chunk_count() -> int:
	return preload_chunks.size()


func get_active_generation_task_count() -> int:
	return 0 if active_generation_task.is_empty() else 1


func get_generated_cells_this_frame() -> int:
	return generated_cells_this_frame


func get_last_generation_time_ms() -> float:
	return last_generation_time_ms


func get_tile_writes_this_frame() -> int:
	return tile_writes_this_frame


func get_last_apply_time_ms() -> float:
	return last_apply_time_ms


func get_unloaded_cells_this_frame() -> int:
	return unloaded_cells_this_frame


func get_last_unload_time_ms() -> float:
	return last_unload_time_ms


func get_last_loaded_chunk_preview(limit: int = 3) -> Array[Vector2i]:
	return _get_preview_chunks(last_loaded_debug_chunks, limit)


func get_last_unloaded_chunk_preview(limit: int = 3) -> Array[Vector2i]:
	return _get_preview_chunks(last_unloaded_debug_chunks, limit)


func get_last_refreshed_chunk_preview(limit: int = 3) -> Array[Vector2i]:
	return _get_preview_chunks(last_refreshed_debug_chunks, limit)


func get_chunk_state_count(target_state: int) -> int:
	var count := 0
	for state_value in chunk_states.values():
		if int(state_value) == target_state:
			count += 1
	return count


func _update_camera_snapshot(delta: float) -> void:
	var camera_position := _get_camera_position()
	var safe_delta := maxf(delta, 0.000001)
	camera_velocity = (camera_position - last_camera_position) / safe_delta
	last_camera_position = camera_position
	current_camera_cell = _get_camera_center_cell()
	current_camera_chunk = _get_chunk_coords_for_cell(current_camera_cell)


func _get_camera_center_cell() -> Vector2i:
	var tile_size := _get_tile_size()
	return Vector2i(
		floori(_get_camera_position().x / tile_size.x),
		floori(_get_camera_position().y / tile_size.y)
	)


func _get_chunk_coords_for_cell(cell: Vector2i) -> Vector2i:
	if map_data == null:
		return Vector2i.ZERO
	return map_data.get_chunk_coords_for_world_cell(cell)


func _get_camera_position() -> Vector2:
	if camera == null:
		return Vector2.ZERO
	return camera.global_position


func _get_tile_size() -> Vector2:
	if base_layer != null and base_layer.tile_set != null:
		return Vector2(base_layer.tile_set.tile_size)
	return Vector2(16.0, 16.0)


func _get_camera_visible_world_rect() -> Rect2:
	if camera == null:
		return Rect2(_get_camera_position(), Vector2.ZERO)

	var viewport_rect := get_viewport().get_visible_rect()
	var viewport_size := viewport_rect.size
	var zoom_x := maxf(camera.zoom.x, 0.001)
	var zoom_y := maxf(camera.zoom.y, 0.001)
	var visible_world_size := Vector2(
		viewport_size.x / zoom_x,
		viewport_size.y / zoom_y
	)
	var half_size := visible_world_size * 0.5
	var world_top_left := _get_camera_position() - half_size
	return Rect2(world_top_left, visible_world_size)


func _get_visible_cell_rect() -> Rect2i:
	if base_layer == null:
		return Rect2i(current_camera_cell, Vector2i.ONE)

	var world_rect := _get_camera_visible_world_rect()
	var p0 := world_rect.position
	var p1 := world_rect.position + Vector2(world_rect.size.x, 0.0)
	var p2 := world_rect.position + Vector2(0.0, world_rect.size.y)
	var p3 := world_rect.position + world_rect.size
	var c0 := base_layer.local_to_map(base_layer.to_local(p0))
	var c1 := base_layer.local_to_map(base_layer.to_local(p1))
	var c2 := base_layer.local_to_map(base_layer.to_local(p2))
	var c3 := base_layer.local_to_map(base_layer.to_local(p3))
	var min_x := mini(mini(c0.x, c1.x), mini(c2.x, c3.x))
	var min_y := mini(mini(c0.y, c1.y), mini(c2.y, c3.y))
	var max_x := maxi(maxi(c0.x, c1.x), maxi(c2.x, c3.x))
	var max_y := maxi(maxi(c0.y, c1.y), maxi(c2.y, c3.y))
	return Rect2i(
		Vector2i(min_x, min_y),
		Vector2i(max_x - min_x + 1, max_y - min_y + 1)
	)


func _cell_to_chunk_coords(cell: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(cell.x) / float(chunk_size)),
		floori(float(cell.y) / float(chunk_size))
	)


func get_visible_chunk_rect() -> Rect2i:
	var cell_rect := _get_visible_cell_rect()
	var min_cell := cell_rect.position
	var max_cell := cell_rect.position + cell_rect.size - Vector2i.ONE
	var min_chunk := _cell_to_chunk_coords(min_cell)
	var max_chunk := _cell_to_chunk_coords(max_cell)
	return Rect2i(
		min_chunk,
		max_chunk - min_chunk + Vector2i.ONE
	)


func get_keep_chunk_rect() -> Rect2i:
	var visible_chunk_rect := get_visible_chunk_rect()
	var margin: int = max(keep_radius, 0)
	return _expand_chunk_rect(visible_chunk_rect, margin)


func _expand_chunk_rect(rect: Rect2i, margin: int) -> Rect2i:
	var safe_margin: int = max(margin, 0)
	return Rect2i(
		rect.position - Vector2i(safe_margin, safe_margin),
		rect.size + Vector2i(safe_margin * 2, safe_margin * 2)
	)


func _is_chunk_inside_rect(chunk_coords: Vector2i, rect: Rect2i) -> bool:
	return chunk_coords.x >= rect.position.x \
		and chunk_coords.y >= rect.position.y \
		and chunk_coords.x < rect.position.x + rect.size.x \
		and chunk_coords.y < rect.position.y + rect.size.y


func _get_required_chunks() -> Dictionary:
	var result: Dictionary = {}
	var required_rect := _expand_chunk_rect(get_visible_chunk_rect(), max(preload_radius, 0))
	var min_x := required_rect.position.x
	var min_y := required_rect.position.y
	var max_x := required_rect.position.x + required_rect.size.x - 1
	var max_y := required_rect.position.y + required_rect.size.y - 1
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			result[Vector2i(x, y)] = true
	return result


func _get_chunks_in_rect(rect: Rect2i) -> Dictionary:
	var result: Dictionary = {}
	var min_x := rect.position.x
	var min_y := rect.position.y
	var max_x := rect.position.x + rect.size.x - 1
	var max_y := rect.position.y + rect.size.y - 1
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			result[Vector2i(x, y)] = true
	return result


func _get_directional_preload_chunks() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if directional_preload_extra <= 0:
		return result

	var velocity_direction := Vector2i.ZERO
	if absf(camera_velocity.x) >= absf(camera_velocity.y):
		if camera_velocity.x > 0.01:
			velocity_direction = Vector2i.RIGHT
		elif camera_velocity.x < -0.01:
			velocity_direction = Vector2i.LEFT
	else:
		if camera_velocity.y > 0.01:
			velocity_direction = Vector2i.DOWN
		elif camera_velocity.y < -0.01:
			velocity_direction = Vector2i.UP

	if velocity_direction == Vector2i.ZERO:
		return result

	var required_rect := _expand_chunk_rect(get_visible_chunk_rect(), max(preload_radius, 0))
	var min_x := required_rect.position.x
	var min_y := required_rect.position.y
	var max_x := required_rect.position.x + required_rect.size.x - 1
	var max_y := required_rect.position.y + required_rect.size.y - 1
	var seen: Dictionary = {}
	for step in range(1, directional_preload_extra + 1):
		if velocity_direction == Vector2i.LEFT or velocity_direction == Vector2i.RIGHT:
			var target_x := max_x + step if velocity_direction == Vector2i.RIGHT else min_x - step
			for y in range(min_y, max_y + 1):
				var preload_chunk := Vector2i(target_x, y)
				if required_chunks.has(preload_chunk) or seen.has(preload_chunk):
					continue
				seen[preload_chunk] = true
				result.append(preload_chunk)
		else:
			var target_y := max_y + step if velocity_direction == Vector2i.DOWN else min_y - step
			for x in range(min_x, max_x + 1):
				var preload_chunk := Vector2i(x, target_y)
				if required_chunks.has(preload_chunk) or seen.has(preload_chunk):
					continue
				seen[preload_chunk] = true
				result.append(preload_chunk)

	return result


func _update_required_chunks() -> void:
	visible_chunks = _get_chunks_in_rect(get_visible_chunk_rect())
	required_chunks = _get_required_chunks()
	preload_chunks.clear()

	for preload_chunk in _get_directional_preload_chunks():
		preload_chunks[preload_chunk] = true

	_restore_unloading_chunks_if_needed()
	_prune_stale_generation_queue()
	_request_far_chunk_unload()

	for chunk_coords in required_chunks.keys():
		_request_chunk(chunk_coords)
	for chunk_coords in preload_chunks.keys():
		_request_chunk(chunk_coords)

	_reprioritize_generation_queue()


func _request_chunk(chunk_coords: Vector2i) -> void:
	var chunk_overlaps_source_map := _chunk_overlaps_source_map(chunk_coords)
	if _runtime_uses_source_map and not chunk_overlaps_source_map and not _runtime_allow_source_map_fallback_generation:
		return
	_cancel_unload_if_needed(chunk_coords)
	var current_state: int = int(chunk_states.get(chunk_coords, ChunkState.EMPTY))
	if current_state != ChunkState.EMPTY and current_state != ChunkState.UNLOADED:
		return
	if enable_chunk_cache and cached_chunks.has(chunk_coords):
		_restore_chunk_from_cache(chunk_coords)
		return

	chunk_states[chunk_coords] = ChunkState.QUEUED
	generation_queue.append(chunk_coords)


func _prune_stale_generation_queue() -> void:
	var keep_rect := get_keep_chunk_rect()
	var pruned_queue: Array[Vector2i] = []
	for chunk_coords in generation_queue:
		if _is_chunk_inside_rect(chunk_coords, keep_rect):
			pruned_queue.append(chunk_coords)
			continue

		var current_state: int = int(chunk_states.get(chunk_coords, ChunkState.EMPTY))
		if current_state == ChunkState.QUEUED:
			chunk_states[chunk_coords] = ChunkState.UNLOADED
			continue

		pruned_queue.append(chunk_coords)

	generation_queue = pruned_queue


func _reprioritize_generation_queue() -> void:
	if generation_queue.size() <= 1:
		return

	var visible_list: Array[Vector2i] = []
	var required_list: Array[Vector2i] = []
	var preload_list: Array[Vector2i] = []
	var other_list: Array[Vector2i] = []

	for chunk_coords in generation_queue:
		if visible_chunks.has(chunk_coords):
			visible_list.append(chunk_coords)
		elif required_chunks.has(chunk_coords):
			required_list.append(chunk_coords)
		elif preload_chunks.has(chunk_coords):
			preload_list.append(chunk_coords)
		else:
			other_list.append(chunk_coords)

	generation_queue = visible_list
	generation_queue.append_array(required_list)
	generation_queue.append_array(preload_list)
	generation_queue.append_array(other_list)


func _process_generation_budget() -> void:
	generated_cells_this_frame = 0
	last_generation_time_ms = 0.0
	if map_data == null:
		return
	if not _runtime_uses_source_map and generator == null:
		return

	var frame_start_usec: int = Time.get_ticks_usec()
	var budget: int = max(max_generate_cells_per_frame, 0)
	if budget <= 0:
		return

	while generated_cells_this_frame < budget:
		if active_generation_task.is_empty():
			_start_next_generation_task()
			if active_generation_task.is_empty():
				break

		if bool(active_generation_task.get("cancel_requested", false)):
			_cancel_active_generation_task()
			continue

		var task_cells: Array = active_generation_task.get("cells", [])
		var next_local_index: int = int(active_generation_task.get("next_local_index", 0))
		if next_local_index >= task_cells.size():
			_finish_generation_task(active_generation_task)
			active_generation_task.clear()
			continue

		var world_cell: Vector2i = task_cells[next_local_index]
		if _runtime_uses_source_map:
			var source_cell := _source_world_cell_to_local_cell(world_cell)
			var source_tile = null
			if _is_source_world_cell_inside(world_cell):
				source_tile = source_map_data.get_tile(source_cell)
			if source_tile != null:
				map_data.set_tile(world_cell, source_tile.clone())
			elif generator != null and generator.has_method("generate_tile"):
				var fallback_tile = generator.generate_tile(map_seed, world_cell)
				if fallback_tile != null:
					if include_resources_runtime and generator.has_method("apply_runtime_resource_to_tile"):
						generator.apply_runtime_resource_to_tile(fallback_tile, map_seed)
					map_data.set_tile(world_cell, fallback_tile)
		else:
			var tile = generator.generate_tile(map_seed, world_cell)
			if tile != null:
				if include_resources_runtime and generator.has_method("apply_runtime_resource_to_tile"):
					generator.apply_runtime_resource_to_tile(tile, map_seed)
				map_data.set_tile(world_cell, tile)

		active_generation_task["next_local_index"] = next_local_index + 1
		generated_cells_this_frame += 1

		if int(active_generation_task.get("next_local_index", 0)) >= task_cells.size():
			_finish_generation_task(active_generation_task)
			active_generation_task.clear()

	last_generation_time_ms = float(Time.get_ticks_usec() - frame_start_usec) / 1000.0


func _start_next_generation_task() -> void:
	if not active_generation_task.is_empty():
		return
	if generation_queue.is_empty():
		return

	var chunk_coords: Vector2i = generation_queue[0]
	generation_queue.remove_at(0)
	chunk_states[chunk_coords] = ChunkState.GENERATING

	active_generation_task = {
		"chunk_coords": chunk_coords,
		"cells": _get_world_cells_for_chunk(chunk_coords),
		"next_local_index": 0,
	}


func _finish_generation_task(task: Dictionary) -> void:
	if task.is_empty():
		return

	var chunk_coords: Vector2i = task.get("chunk_coords", Vector2i.ZERO)
	var base_cells: Array = task.get("cells", [])
	var resource_cells: Array = []
	if include_resources_runtime:
		resource_cells = base_cells
		if not _runtime_uses_source_map:
			_apply_runtime_resources_to_cells(base_cells)
	var transition_cells: Array = []
	if include_transitions_runtime:
		transition_cells = _collect_transition_refresh_cells_for_chunk(chunk_coords)
	chunk_states[chunk_coords] = ChunkState.APPLYING
	apply_queue.append({
		"chunk_coords": chunk_coords,
		"base_cells": base_cells,
		"resource_cells": resource_cells,
		"transition_cells": transition_cells,
		"base_index": 0,
		"resource_index": 0,
		"transition_index": 0,
		"mark_visible_on_finish": true,
		"register_loaded_chunk_on_finish": true,
	})


func _cancel_active_generation_task() -> void:
	if active_generation_task.is_empty():
		return

	var task_cells: Array = active_generation_task.get("cells", [])
	var generated_count: int = int(active_generation_task.get("next_local_index", 0))
	var chunk_coords: Vector2i = active_generation_task.get("chunk_coords", Vector2i.ZERO)
	for cell_index in range(min(generated_count, task_cells.size())):
		map_data.clear_tile(task_cells[cell_index])

	chunk_states[chunk_coords] = ChunkState.UNLOADED
	active_generation_task.clear()


func _get_world_cells_for_chunk(chunk_coords: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var chunk_origin: Vector2i = chunk_coords * chunk_size
	for local_y in range(chunk_size):
		for local_x in range(chunk_size):
			var world_cell := chunk_origin + Vector2i(local_x, local_y)
			result.append(world_cell)
	return result


func _process_apply_budget() -> void:
	tile_writes_this_frame = 0
	last_apply_time_ms = 0.0
	if renderer == null or base_layer == null:
		return

	var budget: int = max(max_tile_writes_per_frame, 0)
	if budget <= 0:
		return
	if apply_queue.is_empty():
		return

	var frame_start_usec: int = Time.get_ticks_usec()

	while tile_writes_this_frame < budget and not apply_queue.is_empty():
		var task: Dictionary = apply_queue[0]
		var base_cells: Array = task.get("base_cells", [])
		var base_index: int = int(task.get("base_index", 0))
		if base_index < base_cells.size():
			var base_cell: Vector2i = base_cells[base_index]
			tile_writes_this_frame += renderer.render_base_cell(base_layer, map_data, base_cell)
			task["base_index"] = base_index + 1
			apply_queue[0] = task
			continue

		var resource_cells: Array = task.get("resource_cells", [])
		var resource_index: int = int(task.get("resource_index", 0))
		if include_resources_runtime and resource_layer != null and resource_index < resource_cells.size():
			var resource_cell: Vector2i = resource_cells[resource_index]
			tile_writes_this_frame += renderer.render_resource_cell(resource_layer, map_data, resource_cell)
			task["resource_index"] = resource_index + 1
			apply_queue[0] = task
			continue

		var transition_cells: Array = task.get("transition_cells", [])
		var transition_index: int = int(task.get("transition_index", 0))
		if include_transitions_runtime and transition_layer != null and transition_index < transition_cells.size():
			var transition_cell: Vector2i = transition_cells[transition_index]
			renderer.render_transition_cell(transition_layer, map_data, transition_cell)
			tile_writes_this_frame += 1
			task["transition_index"] = transition_index + 1
			apply_queue[0] = task
			continue

		var finished_chunk_coords: Vector2i = task.get("chunk_coords", Vector2i.ZERO)
		if bool(task.get("mark_visible_on_finish", false)):
			chunk_states[finished_chunk_coords] = ChunkState.VISIBLE
		if bool(task.get("register_loaded_chunk_on_finish", false)):
			loaded_chunks[finished_chunk_coords] = true
			_append_debug_chunk(last_loaded_debug_chunks, finished_chunk_coords)
		apply_queue.remove_at(0)

	last_apply_time_ms = float(Time.get_ticks_usec() - frame_start_usec) / 1000.0


func _process_unload_budget() -> void:
	unloaded_cells_this_frame = 0
	last_unload_time_ms = 0.0
	if map_data == null:
		return

	var budget: int = max(max_unload_cells_per_frame, 0)
	if budget <= 0:
		return
	if unload_queue.is_empty():
		return

	var frame_start_usec: int = Time.get_ticks_usec()

	while unloaded_cells_this_frame < budget and not unload_queue.is_empty():
		var task: Dictionary = unload_queue[0]
		var cells: Array = task.get("cells", [])
		var next_index: int = int(task.get("next_index", 0))
		if next_index >= cells.size():
			var finished_chunk_coords: Vector2i = task.get("chunk_coords", Vector2i.ZERO)
			chunk_states[finished_chunk_coords] = ChunkState.UNLOADED
			unload_queue.remove_at(0)
			_append_debug_chunk(last_unloaded_debug_chunks, finished_chunk_coords)
			if include_transitions_runtime and transition_layer != null:
				_enqueue_transition_refresh_task(finished_chunk_coords)
			continue

		var cell: Vector2i = cells[next_index]
		if renderer != null:
			renderer.clear_cell_from_layers(cell, base_layer, resource_layer, transition_layer)
		map_data.clear_tile(cell)
		unloaded_cells_this_frame += 1

		task["next_index"] = next_index + 1
		unload_queue[0] = task

	last_unload_time_ms = float(Time.get_ticks_usec() - frame_start_usec) / 1000.0


func _request_far_chunk_unload() -> void:
	var keep_rect := get_keep_chunk_rect()

	for chunk_coords in loaded_chunks.keys():
		var current_state: int = int(chunk_states.get(chunk_coords, ChunkState.EMPTY))
		if _is_chunk_inside_rect(chunk_coords, keep_rect):
			continue
		if current_state == ChunkState.VISIBLE:
			_enqueue_unload_task(chunk_coords)

	for queue_index in range(apply_queue.size() - 1, -1, -1):
		var task: Dictionary = apply_queue[queue_index]
		var chunk_coords: Vector2i = task.get("chunk_coords", Vector2i.ZERO)
		if _is_chunk_inside_rect(chunk_coords, keep_rect):
			continue
		apply_queue.remove_at(queue_index)
		_enqueue_unload_task(chunk_coords)

	if not active_generation_task.is_empty():
		var active_chunk_coords: Vector2i = active_generation_task.get("chunk_coords", Vector2i.ZERO)
		if not _is_chunk_inside_rect(active_chunk_coords, keep_rect):
			active_generation_task["cancel_requested"] = true


func _enqueue_unload_task(chunk_coords: Vector2i) -> void:
	if _find_unload_task_index(chunk_coords) >= 0:
		return

	var chunk_cells: Array[Vector2i] = map_data.get_chunk_cells(chunk_coords)
	if chunk_cells.is_empty():
		chunk_states[chunk_coords] = ChunkState.UNLOADED
		loaded_chunks.erase(chunk_coords)
		return

	var snapshot: Dictionary = {}
	for cell in chunk_cells:
		var tile = map_data.get_tile(cell)
		if tile == null:
			continue
		snapshot[cell] = tile.clone()

	_store_cached_chunk_snapshot(chunk_coords, snapshot)

	chunk_states[chunk_coords] = ChunkState.UNLOADING
	loaded_chunks.erase(chunk_coords)
	unload_queue.append({
		"chunk_coords": chunk_coords,
		"cells": chunk_cells,
		"next_index": 0,
		"snapshot": snapshot,
	})


func _restore_unloading_chunks_if_needed() -> void:
	for queue_index in range(unload_queue.size() - 1, -1, -1):
		var task: Dictionary = unload_queue[queue_index]
		var chunk_coords: Vector2i = task.get("chunk_coords", Vector2i.ZERO)
		if not required_chunks.has(chunk_coords) and not preload_chunks.has(chunk_coords):
			continue
		_cancel_unload_task(queue_index)


func _cancel_unload_task(queue_index: int) -> void:
	if queue_index < 0 or queue_index >= unload_queue.size():
		return

	var task: Dictionary = unload_queue[queue_index]
	unload_queue.remove_at(queue_index)

	var chunk_coords: Vector2i = task.get("chunk_coords", Vector2i.ZERO)
	_touch_cached_chunk(chunk_coords)
	var snapshot: Dictionary = task.get("snapshot", {})
	var restore_cells: Array[Vector2i] = []
	for cell in snapshot.keys():
		var tile = snapshot[cell]
		if tile == null:
			continue
		map_data.set_tile(cell, tile.clone())
		restore_cells.append(cell)

	restore_cells.sort()
	var resource_cells: Array[Vector2i] = []
	if include_resources_runtime:
		resource_cells = restore_cells
	var transition_cells: Array[Vector2i] = []
	if include_transitions_runtime:
		transition_cells = _collect_transition_refresh_cells_for_chunk(chunk_coords)
	chunk_states[chunk_coords] = ChunkState.APPLYING
	apply_queue.append({
		"chunk_coords": chunk_coords,
		"base_cells": restore_cells,
		"resource_cells": resource_cells,
		"transition_cells": transition_cells,
		"base_index": 0,
		"resource_index": 0,
		"transition_index": 0,
		"mark_visible_on_finish": true,
		"register_loaded_chunk_on_finish": true,
	})


func _restore_chunk_from_cache(chunk_coords: Vector2i) -> void:
	var snapshot: Dictionary = cached_chunks.get(chunk_coords, {})
	if snapshot.is_empty():
		chunk_states[chunk_coords] = ChunkState.QUEUED
		generation_queue.append(chunk_coords)
		return

	_touch_cached_chunk(chunk_coords)
	var restore_cells: Array[Vector2i] = []
	for cell in snapshot.keys():
		var tile = snapshot[cell]
		if tile == null:
			continue
		map_data.set_tile(cell, tile.clone())
		restore_cells.append(cell)

	restore_cells.sort()
	var resource_cells: Array[Vector2i] = []
	if include_resources_runtime:
		resource_cells = restore_cells
	var transition_cells: Array[Vector2i] = []
	if include_transitions_runtime:
		transition_cells = _collect_transition_refresh_cells_for_chunk(chunk_coords)
	chunk_states[chunk_coords] = ChunkState.APPLYING
	apply_queue.append({
		"chunk_coords": chunk_coords,
		"base_cells": restore_cells,
		"resource_cells": resource_cells,
		"transition_cells": transition_cells,
		"base_index": 0,
		"resource_index": 0,
		"transition_index": 0,
		"mark_visible_on_finish": true,
		"register_loaded_chunk_on_finish": true,
	})


func _find_unload_task_index(chunk_coords: Vector2i) -> int:
	for queue_index in range(unload_queue.size()):
		var task: Dictionary = unload_queue[queue_index]
		if task.get("chunk_coords", Vector2i.ZERO) == chunk_coords:
			return queue_index
	return -1


func _find_apply_task_index(chunk_coords: Vector2i) -> int:
	for queue_index in range(apply_queue.size()):
		var task: Dictionary = apply_queue[queue_index]
		if task.get("chunk_coords", Vector2i.ZERO) == chunk_coords:
			return queue_index
	return -1


func _is_chunk_base_ready(chunk_coords: Vector2i) -> bool:
	var current_state: int = int(chunk_states.get(chunk_coords, ChunkState.EMPTY))
	if current_state == ChunkState.VISIBLE:
		return true
	if current_state != ChunkState.APPLYING:
		return false

	var task_index := _find_apply_task_index(chunk_coords)
	if task_index < 0:
		return false

	var task: Dictionary = apply_queue[task_index]
	var base_cells: Array = task.get("base_cells", [])
	var base_index: int = int(task.get("base_index", 0))
	return base_index >= base_cells.size()


func _collect_transition_refresh_cells_for_chunk(chunk_coords: Vector2i) -> Array[Vector2i]:
	if map_data == null:
		return []
	if not map_data.has_method("get_transition_refresh_cells_for_chunk"):
		return []
	return map_data.get_transition_refresh_cells_for_chunk(chunk_coords)


func _chunk_overlaps_source_map(chunk_coords: Vector2i) -> bool:
	if not _runtime_uses_source_map or source_map_data == null:
		return true
	if int(source_map_data.width) <= 0 or int(source_map_data.height) <= 0:
		return true

	var source_origin: Vector2i = source_map_data.world_origin
	var source_end: Vector2i = source_origin + Vector2i(int(source_map_data.width), int(source_map_data.height))
	var chunk_origin: Vector2i = chunk_coords * chunk_size
	var chunk_end: Vector2i = chunk_origin + Vector2i(chunk_size, chunk_size)

	return chunk_origin.x < source_end.x \
		and chunk_end.x > source_origin.x \
		and chunk_origin.y < source_end.y \
		and chunk_end.y > source_origin.y


func _source_world_cell_to_local_cell(world_cell: Vector2i) -> Vector2i:
	if source_map_data == null:
		return world_cell
	if int(source_map_data.width) <= 0 or int(source_map_data.height) <= 0:
		return world_cell
	return world_cell - source_map_data.world_origin


func _is_source_world_cell_inside(world_cell: Vector2i) -> bool:
	if source_map_data == null:
		return false
	if int(source_map_data.width) <= 0 or int(source_map_data.height) <= 0:
		return true

	var local_cell := _source_world_cell_to_local_cell(world_cell)
	return source_map_data.is_inside(local_cell)


func _enqueue_transition_refresh_task(chunk_coords: Vector2i) -> void:
	var transition_cells: Array[Vector2i] = _collect_transition_refresh_cells_for_chunk(chunk_coords)
	if transition_cells.is_empty():
		return
	_append_debug_chunk(last_refreshed_debug_chunks, chunk_coords)

	apply_queue.append({
		"chunk_coords": chunk_coords,
		"base_cells": [],
		"resource_cells": [],
		"transition_cells": transition_cells,
		"base_index": 0,
		"resource_index": 0,
		"transition_index": 0,
		"mark_visible_on_finish": false,
		"register_loaded_chunk_on_finish": false,
	})


func _apply_runtime_resources_to_cells(cells: Array) -> void:
	if not include_resources_runtime:
		return
	if generator == null or not generator.has_method("apply_runtime_resource_to_tile"):
		return

	for cell in cells:
		var tile = map_data.get_tile(cell)
		if tile == null:
			continue
		generator.apply_runtime_resource_to_tile(tile, map_seed)


func _cancel_unload_if_needed(chunk_coords: Vector2i) -> void:
	var state: int = int(chunk_states.get(chunk_coords, ChunkState.EMPTY))
	if state != ChunkState.UNLOADING:
		return

	var unload_task_index := _find_unload_task_index(chunk_coords)
	if unload_task_index >= 0:
		_cancel_unload_task(unload_task_index)
		return

	chunk_states[chunk_coords] = ChunkState.VISIBLE


func _store_cached_chunk_snapshot(chunk_coords: Vector2i, snapshot: Dictionary) -> void:
	if not enable_chunk_cache:
		return
	if snapshot.is_empty():
		return

	cached_chunks[chunk_coords] = snapshot
	_touch_cached_chunk(chunk_coords)
	_trim_cached_chunks()


func _touch_cached_chunk(chunk_coords: Vector2i) -> void:
	if not enable_chunk_cache:
		return

	var existing_index := cached_chunk_order.find(chunk_coords)
	if existing_index >= 0:
		cached_chunk_order.remove_at(existing_index)
	cached_chunk_order.append(chunk_coords)


func _trim_cached_chunks() -> void:
	if not enable_chunk_cache:
		cached_chunks.clear()
		cached_chunk_order.clear()
		return
	if max_cached_chunks <= 0:
		cached_chunks.clear()
		cached_chunk_order.clear()
		return

	while cached_chunk_order.size() > max_cached_chunks:
		var evict_chunk: Vector2i = cached_chunk_order[0]
		cached_chunk_order.remove_at(0)
		cached_chunks.erase(evict_chunk)


func _append_debug_chunk(target: Array[Vector2i], chunk_coords: Vector2i) -> void:
	if target.has(chunk_coords):
		return
	target.append(chunk_coords)


func _get_preview_chunks(source: Array[Vector2i], limit: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var safe_limit: int = max(limit, 0)
	for chunk_index in range(min(safe_limit, source.size())):
		result.append(source[chunk_index])
	return result
