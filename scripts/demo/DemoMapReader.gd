class_name DemoMapReader
extends RefCounted

const GridMapDataScript := preload("res://scripts/map/GridMapData.gd")

const TERRAIN_TYPE_FIELD := "terrain_type"
const RESOURCE_TYPE_FIELD := "resource_type"

var cell_offset: Vector2i = Vector2i.ZERO
var used_rect: Rect2i = Rect2i()
var ground_cells_read: int = 0
var resource_cells_read: int = 0


func read_layers(ground_layer: TileMapLayer, resource_layer: TileMapLayer) -> Dictionary:
	ground_cells_read = 0
	resource_cells_read = 0
	cell_offset = Vector2i.ZERO
	used_rect = Rect2i()

	if ground_layer == null:
		push_error("DemoMapReader requires GroundLayer.")
		return {}
	if resource_layer == null:
		push_error("DemoMapReader requires ResourceLayer.")
		return {}

	var ground_cells: Array[Vector2i] = ground_layer.get_used_cells()
	var resource_cells: Array[Vector2i] = resource_layer.get_used_cells()
	used_rect = _get_used_rect_from_cells(ground_cells, resource_cells)
	cell_offset = used_rect.position

	var grid := GridMapDataScript.new()
	grid.resize(used_rect.size.x, used_rect.size.y)
	grid.fill_terrain(MapTypes.TerrainType.EMPTY)

	for cell in ground_cells:
		grid.set_terrain(_to_grid_cell(cell), _read_ground_terrain(ground_layer, cell))
		ground_cells_read += 1

	for cell in resource_cells:
		var resource_terrain := _read_resource_terrain(resource_layer, cell)
		if resource_terrain >= 0:
			grid.set_terrain(_to_grid_cell(cell), resource_terrain)
			resource_cells_read += 1

	return {
		"grid": grid,
		"used_rect": used_rect,
		"cell_offset": cell_offset,
		"ground_cells_read": ground_cells_read,
		"resource_cells_read": resource_cells_read,
		"terrain_counts": _count_terrain(grid),
	}


func map_cell_to_grid_cell(map_cell: Vector2i) -> Vector2i:
	return map_cell - cell_offset


func grid_cell_to_map_cell(grid_cell: Vector2i) -> Vector2i:
	return grid_cell + cell_offset


func _to_grid_cell(map_cell: Vector2i) -> Vector2i:
	return map_cell_to_grid_cell(map_cell)


func _get_used_rect_from_cells(ground_cells: Array[Vector2i], resource_cells: Array[Vector2i]) -> Rect2i:
	var all_cells: Array[Vector2i] = []
	all_cells.append_array(ground_cells)
	all_cells.append_array(resource_cells)
	if all_cells.is_empty():
		return Rect2i(Vector2i.ZERO, Vector2i.ZERO)

	var min_cell := all_cells[0]
	var max_cell := all_cells[0]
	for cell in all_cells:
		min_cell.x = min(min_cell.x, cell.x)
		min_cell.y = min(min_cell.y, cell.y)
		max_cell.x = max(max_cell.x, cell.x)
		max_cell.y = max(max_cell.y, cell.y)

	return Rect2i(min_cell, max_cell - min_cell + Vector2i.ONE)


func _read_ground_terrain(layer: TileMapLayer, cell: Vector2i) -> int:
	var tile_data := layer.get_cell_tile_data(cell)
	if tile_data == null:
		return MapTypes.TerrainType.EMPTY

	var terrain_type := _get_custom_data_string(tile_data, TERRAIN_TYPE_FIELD)
	match terrain_type:
		"plain":
			return MapTypes.TerrainType.PLAIN
		"road":
			return MapTypes.TerrainType.ROAD
		"water":
			return MapTypes.TerrainType.WATER
		"mountain":
			return MapTypes.TerrainType.MOUNTAIN
		_:
			return MapTypes.TerrainType.EMPTY


func _read_resource_terrain(layer: TileMapLayer, cell: Vector2i) -> int:
	var tile_data := layer.get_cell_tile_data(cell)
	if tile_data == null:
		return -1

	var resource_type := _get_custom_data_string(tile_data, RESOURCE_TYPE_FIELD)
	match resource_type:
		"wood":
			return MapTypes.TerrainType.FOREST
		"stone":
			return MapTypes.TerrainType.STONE

	var terrain_type := _get_custom_data_string(tile_data, TERRAIN_TYPE_FIELD)
	match terrain_type:
		"forest":
			return MapTypes.TerrainType.FOREST
		"stone":
			return MapTypes.TerrainType.STONE
		_:
			return -1


func _get_custom_data_string(tile_data: TileData, field_name: String) -> String:
	var value: Variant = tile_data.get_custom_data(field_name)
	if value == null:
		return ""
	return str(value).strip_edges().to_lower()


func _count_terrain(grid: RefCounted) -> Dictionary:
	var counts: Dictionary = {
		MapTypes.TerrainType.FOREST: 0,
		MapTypes.TerrainType.STONE: 0,
		MapTypes.TerrainType.PLAIN: 0,
		MapTypes.TerrainType.ROAD: 0,
		MapTypes.TerrainType.WATER: 0,
		MapTypes.TerrainType.MOUNTAIN: 0,
		MapTypes.TerrainType.EMPTY: 0,
	}

	for cell in grid.get_all_cells():
		var terrain_type: int = grid.get_terrain(cell)
		if not counts.has(terrain_type):
			counts[terrain_type] = 0
		counts[terrain_type] += 1

	return counts

