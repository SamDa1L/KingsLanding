class_name GeneratedMapData
extends RefCounted


const GeneratedTileDataScript := preload("res://scripts/mapgen/GeneratedTileData.gd")
const GeneratedChunkDataScript := preload("res://scripts/mapgen/GeneratedChunkData.gd")

var seed: int = 0
var width: int = 0
var height: int = 0
var chunk_size: int = 32
var world_origin: Vector2i = Vector2i.ZERO
var tiles: Dictionary = {}
var generated_chunks: Dictionary = {}


func _init() -> void:
	reset()


func reset() -> void:
	seed = 0
	width = 0
	height = 0
	chunk_size = 32
	world_origin = Vector2i.ZERO
	tiles.clear()
	generated_chunks.clear()


func setup(map_seed: int, map_width: int, map_height: int, map_chunk_size: int = 32, map_world_origin: Vector2i = Vector2i.ZERO) -> void:
	seed = map_seed
	width = max(map_width, 0)
	height = max(map_height, 0)
	chunk_size = max(map_chunk_size, 1)
	world_origin = map_world_origin
	tiles.clear()
	generated_chunks.clear()


func setup_sparse(map_seed: int, map_chunk_size: int = 32) -> void:
	setup(map_seed, 0, 0, map_chunk_size, Vector2i.ZERO)


func is_inside(cell: Vector2i) -> bool:
	if _is_sparse_mode():
		return true
	return cell.x >= 0 and cell.x < width and cell.y >= 0 and cell.y < height


func ensure_tile(cell: Vector2i):
	if not _is_sparse_mode() and not is_inside(cell):
		return null
	if not tiles.has(cell):
		var tile = GeneratedTileDataScript.new()
		tile.cell = cell
		tiles[cell] = tile
		_register_cell_chunk(cell)
	return tiles[cell]


func set_tile(cell: Vector2i, tile_data) -> void:
	if tile_data == null:
		return
	if not _is_sparse_mode() and not is_inside(cell):
		return
	tile_data.cell = cell
	tiles[cell] = tile_data
	_register_cell_chunk(cell)


func set_tile_data(tile_data) -> void:
	if tile_data == null:
		return
	set_tile(tile_data.cell, tile_data)


func get_tile(cell: Vector2i):
	if not _is_sparse_mode() and not is_inside(cell):
		return null
	return tiles.get(cell)


func has_tile(cell: Vector2i) -> bool:
	if not _is_sparse_mode() and not is_inside(cell):
		return false
	return tiles.has(cell)


func clear_tile(cell: Vector2i) -> void:
	tiles.erase(cell)
	_prune_cell_from_chunk(cell)


func get_all_cells() -> Array[Vector2i]:
	if width <= 0 or height <= 0:
		var sparse_result: Array[Vector2i] = []
		for cell in tiles.keys():
			sparse_result.append(cell)
		sparse_result.sort()
		return sparse_result

	var result: Array[Vector2i] = []
	for y in range(height):
		for x in range(width):
			result.append(Vector2i(x, y))
	return result


func get_chunk_coords_for_cell(cell: Vector2i) -> Vector2i:
	return get_chunk_coords_for_world_cell(get_world_cell(cell))


func get_chunk_coords_for_world_cell(world_cell: Vector2i) -> Vector2i:
	return Vector2i(floori(float(world_cell.x) / float(chunk_size)), floori(float(world_cell.y) / float(chunk_size)))


func get_world_cell(cell: Vector2i) -> Vector2i:
	if _is_sparse_mode():
		return cell
	return cell + world_origin


func get_chunk_origin(chunk_coords: Vector2i) -> Vector2i:
	if _is_sparse_mode():
		return chunk_coords * chunk_size
	return (chunk_coords * chunk_size) - world_origin


func has_chunk(chunk_coords: Vector2i) -> bool:
	return generated_chunks.has(chunk_coords)


func get_chunk(chunk_coords: Vector2i):
	return generated_chunks.get(chunk_coords)


func ensure_chunk(chunk_coords: Vector2i):
	if generated_chunks.has(chunk_coords):
		return generated_chunks[chunk_coords]

	var chunk = GeneratedChunkDataScript.new()
	chunk.setup(chunk_coords, get_chunk_origin(chunk_coords), chunk_size)
	generated_chunks[chunk_coords] = chunk
	return chunk


func get_generated_chunk_coords() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for chunk_coords in generated_chunks.keys():
		result.append(chunk_coords)
	result.sort()
	return result


func get_chunk_cells(chunk_coords: Vector2i) -> Array[Vector2i]:
	var chunk = get_chunk(chunk_coords)
	if chunk == null:
		return []

	var result: Array[Vector2i] = []
	for cell in chunk.cells.keys():
		result.append(cell)
	result.sort()
	return result


func get_boundary_cells(chunk_coords: Vector2i, direction_mask: int = 0) -> Array[Vector2i]:
	var chunk = get_chunk(chunk_coords)
	if chunk == null:
		return []
	return chunk.get_boundary_cells(direction_mask)


func get_neighbor_chunk_coords(chunk_coords: Vector2i, direction: Vector2i) -> Vector2i:
	return chunk_coords + direction


func can_read_neighbor_cell(cell: Vector2i, direction: Vector2i) -> bool:
	var neighbor_cell := cell + direction
	return has_tile(neighbor_cell)


func has_neighbor_chunk_for_cell(cell: Vector2i, direction: Vector2i) -> bool:
	var chunk_coords := get_chunk_coords_for_cell(cell)
	var neighbor_cell := cell + direction
	var neighbor_chunk_coords := get_chunk_coords_for_cell(neighbor_cell)
	if neighbor_chunk_coords == chunk_coords:
		return true
	return has_chunk(neighbor_chunk_coords)


func get_chunk_edge_refresh_cells(chunk_coords: Vector2i) -> Array[Vector2i]:
	var refresh_cells: Dictionary = {}
	var chunk = get_chunk(chunk_coords)
	if chunk == null:
		return []

	for cell in chunk.get_boundary_cells():
		refresh_cells[cell] = true
		for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var neighbor_cell: Vector2i = cell + direction
			if not has_tile(neighbor_cell):
				continue
			refresh_cells[neighbor_cell] = true

	var result: Array[Vector2i] = []
	for refresh_cell in refresh_cells.keys():
		result.append(refresh_cell)
	result.sort()
	return result


func get_adjacent_chunk_edge_refresh_cells(chunk_coords: Vector2i) -> Array[Vector2i]:
	var refresh_cells: Dictionary = {}
	for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var neighbor_chunk_coords: Vector2i = get_neighbor_chunk_coords(chunk_coords, direction)
		for cell in get_chunk_edge_refresh_cells(neighbor_chunk_coords):
			refresh_cells[cell] = true
	for cell in get_chunk_edge_refresh_cells(chunk_coords):
		refresh_cells[cell] = true

	var result: Array[Vector2i] = []
	for refresh_cell in refresh_cells.keys():
		result.append(refresh_cell)
	result.sort()
	return result


func get_transition_refresh_cells_for_chunk(chunk_coords: Vector2i) -> Array[Vector2i]:
	var refresh_cells: Dictionary = {}
	for cell in get_chunk_cells(chunk_coords):
		refresh_cells[cell] = true
	for cell in get_adjacent_chunk_edge_refresh_cells(chunk_coords):
		refresh_cells[cell] = true

	var result: Array[Vector2i] = []
	for refresh_cell in refresh_cells.keys():
		result.append(refresh_cell)
	result.sort()
	return result


func get_tiles_with_base_terrain(base_terrain: StringName) -> Array:
	var result: Array = []
	for tile in tiles.values():
		if tile == null:
			continue
		if tile.base_terrain == base_terrain:
			result.append(tile)
	return result


func get_tiles_with_resource(resource_type: StringName) -> Array:
	var result: Array = []
	for tile in tiles.values():
		if tile == null:
			continue
		if tile.resource_type == resource_type:
			result.append(tile)
	return result


func get_resource_patch_ids(resource_type: StringName = &"") -> Array[int]:
	var patch_ids: Dictionary = {}
	for tile in tiles.values():
		if tile == null:
			continue
		if tile.resource_patch_id < 0:
			continue
		if resource_type != &"" and tile.resource_type != resource_type:
			continue
		patch_ids[tile.resource_patch_id] = true
	var result: Array[int] = []
	for patch_id in patch_ids.keys():
		result.append(int(patch_id))
	result.sort()
	return result


func to_dictionary() -> Dictionary:
	return {
		"seed": seed,
		"width": width,
		"height": height,
		"chunk_size": chunk_size,
		"world_origin": world_origin,
		"tile_count": tiles.size(),
		"chunk_count": generated_chunks.size(),
	}


func _is_sparse_mode() -> bool:
	return width <= 0 or height <= 0


func _register_cell_chunk(cell: Vector2i) -> void:
	var chunk_coords := get_chunk_coords_for_cell(cell)
	var chunk = ensure_chunk(chunk_coords)
	chunk.register_cell(cell)


func _prune_cell_from_chunk(cell: Vector2i) -> void:
	var chunk_coords := get_chunk_coords_for_cell(cell)
	var chunk = get_chunk(chunk_coords)
	if chunk == null:
		return

	chunk.unregister_cell(cell)
	if chunk.get_cell_count() <= 0:
		generated_chunks.erase(chunk_coords)
