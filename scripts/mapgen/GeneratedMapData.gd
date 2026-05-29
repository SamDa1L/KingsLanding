class_name GeneratedMapData
extends RefCounted


const GeneratedTileDataScript := preload("res://scripts/mapgen/GeneratedTileData.gd")

var seed: int = 0
var width: int = 0
var height: int = 0
var chunk_size: int = 32
var tiles: Dictionary = {}


func _init() -> void:
	reset()


func reset() -> void:
	seed = 0
	width = 0
	height = 0
	chunk_size = 32
	tiles.clear()


func setup(map_seed: int, map_width: int, map_height: int, map_chunk_size: int = 32) -> void:
	seed = map_seed
	width = max(map_width, 0)
	height = max(map_height, 0)
	chunk_size = max(map_chunk_size, 1)
	tiles.clear()


func is_inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < width and cell.y >= 0 and cell.y < height


func ensure_tile(cell: Vector2i):
	if not is_inside(cell):
		return null
	if not tiles.has(cell):
		var tile = GeneratedTileDataScript.new()
		tile.cell = cell
		tiles[cell] = tile
	return tiles[cell]


func set_tile(cell: Vector2i, tile_data) -> void:
	if tile_data == null:
		return
	if not is_inside(cell):
		return
	tile_data.cell = cell
	tiles[cell] = tile_data


func set_tile_data(tile_data) -> void:
	if tile_data == null:
		return
	set_tile(tile_data.cell, tile_data)


func get_tile(cell: Vector2i):
	if not is_inside(cell):
		return null
	return tiles.get(cell)


func has_tile(cell: Vector2i) -> bool:
	return is_inside(cell) and tiles.has(cell)


func clear_tile(cell: Vector2i) -> void:
	tiles.erase(cell)


func get_all_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(height):
		for x in range(width):
			result.append(Vector2i(x, y))
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
		"tile_count": tiles.size(),
	}
