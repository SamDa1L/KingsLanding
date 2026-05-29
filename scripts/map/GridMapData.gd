class_name GridMapData
extends RefCounted

const MapTypes := preload("res://scripts/map/MapTypes.gd")

const DEFAULT_EMPTY_TERRAIN := MapTypes.TerrainType.EMPTY

var width: int = 0
var height: int = 0
var _cells: Dictionary = {}


func _init() -> void:
	resize(0, 0)


func setup(map_width: int, map_height: int) -> void:
	resize(map_width, map_height)


func resize(map_width: int, map_height: int) -> void:
	width = max(map_width, 0)
	height = max(map_height, 0)
	_cells.clear()


func is_inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < width and cell.y >= 0 and cell.y < height


func set_terrain(cell: Vector2i, terrain_type: int) -> void:
	if not is_inside(cell):
		return
	_cells[cell] = terrain_type


func get_terrain(cell: Vector2i, default_terrain: int = DEFAULT_EMPTY_TERRAIN) -> int:
	if not is_inside(cell):
		return default_terrain
	if _cells.has(cell):
		return int(_cells[cell])
	return default_terrain


func has_cell(cell: Vector2i) -> bool:
	return is_inside(cell) and _cells.has(cell)


func clear_cell(cell: Vector2i) -> void:
	_cells.erase(cell)


func fill_terrain(terrain_type: int) -> void:
	_cells.clear()
	for y in range(height):
		for x in range(width):
			_cells[Vector2i(x, y)] = terrain_type


func get_cells_with_terrain(terrain_type: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in _cells.keys():
		if int(_cells[cell]) == terrain_type:
			result.append(cell)
	return result


func get_all_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(height):
		for x in range(width):
			result.append(Vector2i(x, y))
	return result
