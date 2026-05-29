class_name ChunkedMapRuntimeController
extends RefCounted


const GeneratedMapDataScript := preload("res://scripts/mapgen/GeneratedMapData.gd")
const NoiseBasedMapGeneratorScript := preload("res://scripts/mapgen/NoiseBasedMapGenerator.gd")

const DEFAULT_ACTIVE_RADIUS := 1

var map_seed: int = 0
var chunk_size: int = 32
var active_radius: int = DEFAULT_ACTIVE_RADIUS
var map_data: RefCounted
var generator: RefCounted
var renderer: RefCounted
var base_layer: TileMapLayer
var resource_layer: TileMapLayer
var transition_layer: TileMapLayer
var current_center_chunk: Vector2i = Vector2i.ZERO

var loaded_chunks: Dictionary = {}
var cached_chunks: Dictionary = {}
var last_loaded_chunks: Array[Vector2i] = []
var last_unloaded_chunks: Array[Vector2i] = []
var last_refreshed_chunks: Array[Vector2i] = []


func setup(next_seed: int, next_chunk_size: int, next_generator: RefCounted, next_renderer: RefCounted, next_base_layer: TileMapLayer = null, next_resource_layer: TileMapLayer = null, next_transition_layer: TileMapLayer = null) -> void:
	map_seed = next_seed
	chunk_size = max(next_chunk_size, 1)
	generator = next_generator
	renderer = next_renderer
	base_layer = next_base_layer
	resource_layer = next_resource_layer
	transition_layer = next_transition_layer
	current_center_chunk = Vector2i.ZERO
	map_data = GeneratedMapDataScript.new()
	map_data.setup(map_seed, 0, 0, chunk_size, Vector2i.ZERO)
	loaded_chunks.clear()
	cached_chunks.clear()
	last_loaded_chunks.clear()
	last_unloaded_chunks.clear()
	last_refreshed_chunks.clear()


func update_active_center(center_chunk: Vector2i, radius: int = DEFAULT_ACTIVE_RADIUS) -> Dictionary:
	active_radius = max(radius, 0)
	current_center_chunk = center_chunk
	var desired_chunks: Dictionary = _build_desired_chunks(center_chunk, active_radius)
	return _rebuild_runtime_map(desired_chunks)


func load_chunk(chunk_coords: Vector2i) -> void:
	var desired_chunks: Dictionary = loaded_chunks.duplicate()
	desired_chunks[chunk_coords] = true
	_rebuild_runtime_map(desired_chunks)


func unload_chunk(chunk_coords: Vector2i) -> void:
	var desired_chunks: Dictionary = loaded_chunks.duplicate()
	desired_chunks.erase(chunk_coords)
	_rebuild_runtime_map(desired_chunks)


func get_loaded_chunk_coords() -> Array[Vector2i]:
	return _sorted_chunk_keys(loaded_chunks)


func get_cached_chunk_coords() -> Array[Vector2i]:
	return _sorted_chunk_keys(cached_chunks)


func has_loaded_chunk(chunk_coords: Vector2i) -> bool:
	return loaded_chunks.has(chunk_coords)


func has_cached_chunk(chunk_coords: Vector2i) -> bool:
	return cached_chunks.has(chunk_coords)


func get_tile(cell: Vector2i):
	if map_data == null:
		return null
	return map_data.get_tile(cell)


func _load_chunk(chunk_coords: Vector2i) -> void:
	if map_data == null:
		return

	var chunk_tiles: Dictionary = cached_chunks.get(chunk_coords, {})
	if chunk_tiles.is_empty():
		chunk_tiles = _generate_chunk_tiles(chunk_coords)
		cached_chunks[chunk_coords] = chunk_tiles

	loaded_chunks[chunk_coords] = true
	var changed_cells: Array[Vector2i] = []
	for world_cell in chunk_tiles.keys():
		var tile = chunk_tiles[world_cell]
		if tile == null:
			continue
		map_data.set_tile(world_cell, tile.clone())
		changed_cells.append(world_cell)

	last_loaded_chunks.append(chunk_coords)
	_render_chunk_cells(changed_cells)


func _unload_chunk(chunk_coords: Vector2i) -> void:
	if map_data == null:
		return

	var chunk_cells: Array[Vector2i] = map_data.get_chunk_cells(chunk_coords)
	var cached_tiles: Dictionary = {}
	var changed_cells: Array[Vector2i] = []
	for cell in chunk_cells:
		var tile = map_data.get_tile(cell)
		if tile != null:
			var world_cell: Vector2i = cell
			var clone = tile.clone()
			clone.cell = world_cell
			cached_tiles[world_cell] = clone
		map_data.clear_tile(cell)
		changed_cells.append(cell)

	cached_chunks[chunk_coords] = cached_tiles
	loaded_chunks.erase(chunk_coords)
	last_unloaded_chunks.append(chunk_coords)
	_clear_chunk_cells(changed_cells)


func _generate_chunk_tiles(chunk_coords: Vector2i) -> Dictionary:
	var result: Dictionary = {}
	if generator == null:
		return result

	var single_chunk_list: Array[Vector2i] = [chunk_coords]
	var generated_chunk_map = generator.generate_chunk_map(map_seed, single_chunk_list, chunk_size, true)
	for cell in generated_chunk_map.get_all_cells():
		var tile = generated_chunk_map.get_tile(cell)
		if tile == null:
			continue
		var target_cell: Vector2i = cell + generated_chunk_map.world_origin
		var copy = tile.clone()
		copy.cell = target_cell
		result[target_cell] = copy

	return result


func _build_desired_chunks(center_chunk: Vector2i, radius: int) -> Dictionary:
	var result: Dictionary = {}
	for y in range(center_chunk.y - radius, center_chunk.y + radius + 1):
		for x in range(center_chunk.x - radius, center_chunk.x + radius + 1):
			result[Vector2i(x, y)] = true
	return result


func _rebuild_runtime_map(desired_chunks: Dictionary) -> Dictionary:
	last_loaded_chunks.clear()
	last_unloaded_chunks.clear()
	last_refreshed_chunks.clear()

	var previous_loaded_set: Dictionary = loaded_chunks.duplicate()
	var chunks_to_unload: Array[Vector2i] = []
	for chunk_coords in previous_loaded_set.keys():
		if desired_chunks.has(chunk_coords):
			continue
		chunks_to_unload.append(chunk_coords)
	chunks_to_unload.sort()

	var chunks_to_load: Array[Vector2i] = []
	for chunk_coords in desired_chunks.keys():
		if previous_loaded_set.has(chunk_coords):
			continue
		chunks_to_load.append(chunk_coords)
	chunks_to_load.sort()

	for chunk_coords in chunks_to_unload:
		_unload_chunk(chunk_coords)

	for chunk_coords in chunks_to_load:
		_load_chunk(chunk_coords)

	_refresh_transition_edges_for_changed_chunks()

	return {
		"loaded": last_loaded_chunks.duplicate(),
		"unloaded": last_unloaded_chunks.duplicate(),
		"refreshed": last_refreshed_chunks.duplicate(),
		"active": get_loaded_chunk_coords(),
		"cached": get_cached_chunk_coords(),
	}


func _snapshot_chunk_tiles_from_current_map(chunk_coords: Vector2i) -> Dictionary:
	var result: Dictionary = {}
	if map_data == null:
		return result

	for cell in map_data.get_chunk_cells(chunk_coords):
		var tile = map_data.get_tile(cell)
		if tile == null:
			continue
		var world_cell: Vector2i = map_data.get_world_cell(cell)
		var clone = tile.clone()
		clone.cell = world_cell
		result[world_cell] = clone

	return result


func _get_chunk_bounds_from_desired_chunks(desired_chunks: Dictionary) -> Dictionary:
	var chunk_coords_list: Array[Vector2i] = []
	for chunk_coords in desired_chunks.keys():
		chunk_coords_list.append(chunk_coords)

	if chunk_coords_list.is_empty():
		return {
			"origin": Vector2i.ZERO,
			"size": Vector2i.ZERO,
		}

	var min_chunk: Vector2i = chunk_coords_list[0]
	var max_chunk: Vector2i = chunk_coords_list[0]
	for chunk_coords in chunk_coords_list:
		min_chunk.x = min(min_chunk.x, chunk_coords.x)
		min_chunk.y = min(min_chunk.y, chunk_coords.y)
		max_chunk.x = max(max_chunk.x, chunk_coords.x)
		max_chunk.y = max(max_chunk.y, chunk_coords.y)

	var origin := min_chunk * chunk_size
	var chunk_count := (max_chunk - min_chunk) + Vector2i.ONE
	var size := chunk_count * chunk_size

	return {
		"origin": origin,
		"size": size,
	}


func _render_chunk_cells(cells: Array[Vector2i]) -> void:
	if renderer == null or cells.is_empty():
		return
	if base_layer != null and renderer.has_method("render_base_cells"):
		renderer.render_base_cells(base_layer, map_data, cells)
	if resource_layer != null and renderer.has_method("render_resource_cells"):
		renderer.render_resource_cells(resource_layer, map_data, cells)
	if transition_layer != null and renderer.has_method("render_transition_cells"):
		renderer.render_transition_cells(transition_layer, map_data, cells)


func _clear_chunk_cells(cells: Array[Vector2i]) -> void:
	if cells.is_empty():
		return
	if base_layer != null:
		for cell in cells:
			base_layer.set_cell(cell, -1)
	if resource_layer != null:
		for cell in cells:
			resource_layer.set_cell(cell, -1)
	if transition_layer != null:
		for cell in cells:
			transition_layer.set_cell(cell, -1)


func _refresh_transition_edges_for_changed_chunks() -> void:
	if renderer == null or transition_layer == null or map_data == null:
		return

	var changed_chunks: Dictionary = {}
	for chunk_coords in last_loaded_chunks:
		changed_chunks[chunk_coords] = true
	for chunk_coords in last_unloaded_chunks:
		changed_chunks[chunk_coords] = true

	for chunk_coords in changed_chunks.keys():
		renderer.refresh_chunk_transition_edges(transition_layer, map_data, chunk_coords)
		last_refreshed_chunks.append(chunk_coords)


func _sorted_chunk_keys(source: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for chunk_coords in source.keys():
		result.append(chunk_coords)
	result.sort()
	return result
