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
@export var include_resources_runtime: bool = false
@export var include_transitions_runtime: bool = false

var map_data: RefCounted
var generator: RefCounted
var renderer: GeneratedMapRenderer
var base_layer: TileMapLayer
var resource_layer: TileMapLayer
var transition_layer: TileMapLayer
var camera: Camera2D

var chunk_states: Dictionary = {}
var generation_queue: Array[Vector2i] = []
var apply_queue: Array[Dictionary] = []
var unload_queue: Array[Dictionary] = []
var loaded_chunks: Dictionary = {}
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


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	process_frame_count += 1
	if not is_runtime_initialized:
		return
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
	next_camera: Camera2D = null
) -> void:
	map_seed = next_seed
	generator = next_generator
	renderer = next_renderer
	base_layer = next_base_layer
	resource_layer = next_resource_layer
	transition_layer = next_transition_layer
	camera = next_camera

	map_data = GeneratedMapDataScript.new()
	map_data.setup_sparse(map_seed, chunk_size)

	chunk_states.clear()
	generation_queue.clear()
	apply_queue.clear()
	unload_queue.clear()
	loaded_chunks.clear()
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
	last_camera_position = _get_camera_position()
	is_runtime_initialized = true
	_update_camera_snapshot(1.0)
	_update_required_chunks()


func get_debug_snapshot() -> Dictionary:
	return {
		"ready": is_runtime_initialized,
		"process_frames": get_process_frame_count(),
		"camera_cell": get_current_camera_cell(),
		"camera_chunk": get_current_camera_chunk(),
		"generation_queue_size": get_generation_queue_size(),
		"generation_queue_preview": get_generation_queue_preview(3),
		"apply_queue_size": get_apply_queue_size(),
		"unload_queue_size": get_unload_queue_size(),
		"loaded_chunk_count": get_loaded_chunk_count(),
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
		"camera_velocity": camera_velocity,
		"map_tile_count": 0 if map_data == null else map_data.tiles.size(),
	}


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


func _get_required_chunks() -> Dictionary:
	var result: Dictionary = {}
	var radius: int = max(visible_radius, 0)
	for y in range(current_camera_chunk.y - radius, current_camera_chunk.y + radius + 1):
		for x in range(current_camera_chunk.x - radius, current_camera_chunk.x + radius + 1):
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

	var seen: Dictionary = {}
	for step in range(1, directional_preload_extra + 1):
		var center_chunk := current_camera_chunk + velocity_direction * (visible_radius + step)
		if velocity_direction == Vector2i.LEFT or velocity_direction == Vector2i.RIGHT:
			for offset_y in range(-preload_radius, preload_radius + 1):
				var preload_chunk := Vector2i(center_chunk.x, current_camera_chunk.y + offset_y)
				if required_chunks.has(preload_chunk) or seen.has(preload_chunk):
					continue
				seen[preload_chunk] = true
				result.append(preload_chunk)
		else:
			for offset_x in range(-preload_radius, preload_radius + 1):
				var preload_chunk := Vector2i(current_camera_chunk.x + offset_x, center_chunk.y)
				if required_chunks.has(preload_chunk) or seen.has(preload_chunk):
					continue
				seen[preload_chunk] = true
				result.append(preload_chunk)

	return result


func _update_required_chunks() -> void:
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
	var current_state: int = int(chunk_states.get(chunk_coords, ChunkState.EMPTY))
	if current_state != ChunkState.EMPTY and current_state != ChunkState.UNLOADED:
		return

	chunk_states[chunk_coords] = ChunkState.QUEUED
	generation_queue.append(chunk_coords)


func _prune_stale_generation_queue() -> void:
	var keep_chunks: Dictionary = _build_keep_chunks()
	var pruned_queue: Array[Vector2i] = []
	for chunk_coords in generation_queue:
		if keep_chunks.has(chunk_coords):
			pruned_queue.append(chunk_coords)
			continue

		var current_state: int = int(chunk_states.get(chunk_coords, ChunkState.EMPTY))
		if current_state == ChunkState.QUEUED:
			chunk_states[chunk_coords] = ChunkState.EMPTY
			continue

		pruned_queue.append(chunk_coords)

	generation_queue = pruned_queue


func _build_keep_chunks() -> Dictionary:
	var keep_chunks: Dictionary = {}
	var radius: int = max(keep_radius, visible_radius)
	for y in range(current_camera_chunk.y - radius, current_camera_chunk.y + radius + 1):
		for x in range(current_camera_chunk.x - radius, current_camera_chunk.x + radius + 1):
			keep_chunks[Vector2i(x, y)] = true
	for chunk_coords in required_chunks.keys():
		keep_chunks[chunk_coords] = true
	for chunk_coords in preload_chunks.keys():
		keep_chunks[chunk_coords] = true
	return keep_chunks


func _reprioritize_generation_queue() -> void:
	if generation_queue.size() <= 1:
		return

	var required_list: Array[Vector2i] = []
	var preload_list: Array[Vector2i] = []
	var other_list: Array[Vector2i] = []

	for chunk_coords in generation_queue:
		if required_chunks.has(chunk_coords):
			required_list.append(chunk_coords)
		elif preload_chunks.has(chunk_coords):
			preload_list.append(chunk_coords)
		else:
			other_list.append(chunk_coords)

	generation_queue = required_list
	generation_queue.append_array(preload_list)
	generation_queue.append_array(other_list)


func _process_generation_budget() -> void:
	generated_cells_this_frame = 0
	last_generation_time_ms = 0.0
	if generator == null or map_data == null:
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

		var task_cells: Array[Vector2i] = active_generation_task.get("cells", [])
		var next_local_index: int = int(active_generation_task.get("next_local_index", 0))
		if next_local_index >= task_cells.size():
			_finish_generation_task(active_generation_task)
			active_generation_task.clear()
			continue

		var world_cell: Vector2i = task_cells[next_local_index]
		var tile = generator.generate_tile(map_seed, world_cell)
		if tile != null:
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
	var base_cells: Array[Vector2i] = task.get("cells", [])
	var resource_cells: Array[Vector2i] = []
	if include_resources_runtime:
		resource_cells = base_cells
		_apply_runtime_resources_to_cells(base_cells)
	var transition_cells: Array[Vector2i] = []
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

	var task_cells: Array[Vector2i] = active_generation_task.get("cells", [])
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
			result.append(chunk_origin + Vector2i(local_x, local_y))
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
		var base_cells: Array[Vector2i] = task.get("base_cells", [])
		var base_index: int = int(task.get("base_index", 0))
		if base_index < base_cells.size():
			var base_cell: Vector2i = base_cells[base_index]
			tile_writes_this_frame += renderer.render_base_cell(base_layer, map_data, base_cell)
			task["base_index"] = base_index + 1
			apply_queue[0] = task
			continue

		var resource_cells: Array[Vector2i] = task.get("resource_cells", [])
		var resource_index: int = int(task.get("resource_index", 0))
		if include_resources_runtime and resource_layer != null and resource_index < resource_cells.size():
			var resource_cell: Vector2i = resource_cells[resource_index]
			tile_writes_this_frame += renderer.render_resource_cell(resource_layer, map_data, resource_cell)
			task["resource_index"] = resource_index + 1
			apply_queue[0] = task
			continue

		var transition_cells: Array[Vector2i] = task.get("transition_cells", [])
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
		var cells: Array[Vector2i] = task.get("cells", [])
		var next_index: int = int(task.get("next_index", 0))
		if next_index >= cells.size():
			var finished_chunk_coords: Vector2i = task.get("chunk_coords", Vector2i.ZERO)
			chunk_states[finished_chunk_coords] = ChunkState.UNLOADED
			unload_queue.remove_at(0)
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
	var keep_chunks: Dictionary = _build_keep_chunks()

	for chunk_coords in loaded_chunks.keys():
		var current_state: int = int(chunk_states.get(chunk_coords, ChunkState.EMPTY))
		if keep_chunks.has(chunk_coords):
			continue
		if current_state == ChunkState.VISIBLE:
			_enqueue_unload_task(chunk_coords)

	for queue_index in range(apply_queue.size() - 1, -1, -1):
		var task: Dictionary = apply_queue[queue_index]
		var chunk_coords: Vector2i = task.get("chunk_coords", Vector2i.ZERO)
		if keep_chunks.has(chunk_coords):
			continue
		apply_queue.remove_at(queue_index)
		_enqueue_unload_task(chunk_coords)

	if not active_generation_task.is_empty():
		var active_chunk_coords: Vector2i = active_generation_task.get("chunk_coords", Vector2i.ZERO)
		if not keep_chunks.has(active_chunk_coords):
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

	chunk_states[chunk_coords] = ChunkState.UNLOADING
	loaded_chunks.erase(chunk_coords)
	unload_queue.append({
		"chunk_coords": chunk_coords,
		"cells": chunk_cells,
		"next_index": 0,
		"snapshot": snapshot,
	})


func _restore_unloading_chunks_if_needed() -> void:
	var keep_chunks: Dictionary = _build_keep_chunks()
	for queue_index in range(unload_queue.size() - 1, -1, -1):
		var task: Dictionary = unload_queue[queue_index]
		var chunk_coords: Vector2i = task.get("chunk_coords", Vector2i.ZERO)
		if not keep_chunks.has(chunk_coords):
			continue
		_cancel_unload_task(queue_index)


func _cancel_unload_task(queue_index: int) -> void:
	if queue_index < 0 or queue_index >= unload_queue.size():
		return

	var task: Dictionary = unload_queue[queue_index]
	unload_queue.remove_at(queue_index)

	var chunk_coords: Vector2i = task.get("chunk_coords", Vector2i.ZERO)
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


func _find_unload_task_index(chunk_coords: Vector2i) -> int:
	for queue_index in range(unload_queue.size()):
		var task: Dictionary = unload_queue[queue_index]
		if task.get("chunk_coords", Vector2i.ZERO) == chunk_coords:
			return queue_index
	return -1


func _collect_transition_refresh_cells_for_chunk(chunk_coords: Vector2i) -> Array[Vector2i]:
	if map_data == null:
		return []
	if not map_data.has_method("get_transition_refresh_cells_for_chunk"):
		return []
	return map_data.get_transition_refresh_cells_for_chunk(chunk_coords)


func _enqueue_transition_refresh_task(chunk_coords: Vector2i) -> void:
	var transition_cells: Array[Vector2i] = _collect_transition_refresh_cells_for_chunk(chunk_coords)
	if transition_cells.is_empty():
		return

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


func _apply_runtime_resources_to_cells(cells: Array[Vector2i]) -> void:
	if not include_resources_runtime:
		return
	if generator == null or not generator.has_method("apply_runtime_resource_to_tile"):
		return

	for cell in cells:
		var tile = map_data.get_tile(cell)
		if tile == null:
			continue
		generator.apply_runtime_resource_to_tile(tile, map_seed)
