class_name PlacementValidator
extends RefCounted

const MapTypes := preload("res://scripts/map/MapTypes.gd")
const PlacementResultScript := preload("res://scripts/placement/PlacementResult.gd")

var grid: RefCounted = null
var resource_regions: Dictionary = {}
var farmable_regions: Array = []
var occupied_cells: Dictionary = {}
var castle_cell: Vector2i = Vector2i(-1, -1)


func setup(next_grid: RefCounted, next_resource_regions: Dictionary, next_farmable_regions: Array, next_occupied_cells: Dictionary = {}, next_castle_cell: Vector2i = Vector2i(-1, -1)) -> void:
	grid = next_grid
	resource_regions = next_resource_regions
	farmable_regions = next_farmable_regions
	occupied_cells = next_occupied_cells
	castle_cell = next_castle_cell


func validate(building_type: int, cell: Vector2i) -> RefCounted:
	if grid == null:
		return _result(false, "网格缺失。", cell, null, building_type)
	if not grid.is_inside(cell):
		return _result(false, "目标格子超出地图范围。", cell, null, building_type)
	if occupied_cells.has(cell):
		return _result(false, "目标格子已被占用。", cell, null, building_type)

	var terrain_type: int = grid.get_terrain(cell)
	match building_type:
		MapTypes.BuildingType.TOWN_CENTER:
			return _validate_castle(cell, terrain_type)
		MapTypes.BuildingType.LUMBER_CAMP:
			return _validate_resource_building(cell, terrain_type, MapTypes.TerrainType.FOREST, resource_regions.get(MapTypes.TerrainType.FOREST, []), "伐木场")
		MapTypes.BuildingType.QUARRY:
			return _validate_resource_building(cell, terrain_type, MapTypes.TerrainType.STONE, resource_regions.get(MapTypes.TerrainType.STONE, []), "采石场")
		MapTypes.BuildingType.FARM:
			return _validate_farm(cell, terrain_type)
		MapTypes.BuildingType.HOUSE:
			return _validate_house(cell, terrain_type)
		_:
			return _result(false, "未知建筑类型。", cell, null, building_type)


func _validate_castle(cell: Vector2i, terrain_type: int) -> RefCounted:
	if not _is_castle_terrain(terrain_type):
		return _result(false, "城堡必须放置在空地、平原或城堡地块上。", cell, null, MapTypes.BuildingType.TOWN_CENTER)
	return _result(true, "", cell, null, MapTypes.BuildingType.TOWN_CENTER)


func _validate_resource_building(cell: Vector2i, terrain_type: int, resource_terrain: int, regions: Array, label: String) -> RefCounted:
	if terrain_type != MapTypes.TerrainType.EMPTY and terrain_type != MapTypes.TerrainType.PLAIN:
		return _result(false, "%s必须放置在可建造的空地或平原格子上。" % label, cell, null, -1)
	var region := _find_region_for_cell_or_adjacency(regions, cell)
	if region == null:
		return _result(false, "%s必须贴近%s板块。" % [label, MapTypes.get_terrain_label(resource_terrain)], cell, null, -1)
	return _result(true, "", cell, region, -1)


func _validate_farm(cell: Vector2i, terrain_type: int) -> RefCounted:
	if terrain_type != MapTypes.TerrainType.PLAIN:
		return _result(false, "农场必须放置在平原地块上。", cell, null, MapTypes.BuildingType.FARM)
	var region := _find_region_containing_cell(farmable_regions, cell)
	if region == null:
		return _result(false, "农场必须放置在可耕种的平原板块内。", cell, null, MapTypes.BuildingType.FARM)
	return _result(true, "", cell, region, MapTypes.BuildingType.FARM)


func _validate_house(cell: Vector2i, terrain_type: int) -> RefCounted:
	if terrain_type == MapTypes.TerrainType.WATER or terrain_type == MapTypes.TerrainType.MOUNTAIN:
		return _result(false, "住宅不能放置在水域或山地上。", cell, null, MapTypes.BuildingType.HOUSE)
	if terrain_type == MapTypes.TerrainType.FOREST or terrain_type == MapTypes.TerrainType.STONE:
		return _result(false, "住宅不能放置在资源地块上。", cell, null, MapTypes.BuildingType.HOUSE)
	return _result(true, "", cell, null, MapTypes.BuildingType.HOUSE)


func _find_region_for_cell_or_adjacency(regions: Array, cell: Vector2i) -> RefCounted:
	for region in regions:
		if region.contains_cell(cell) or region.adjacent_empty_cells.has(cell):
			return region
	return null


func _find_region_containing_cell(regions: Array, cell: Vector2i) -> RefCounted:
	for region in regions:
		if region.contains_cell(cell):
			return region
	return null


func _is_castle_terrain(terrain_type: int) -> bool:
	return terrain_type == MapTypes.TerrainType.EMPTY or terrain_type == MapTypes.TerrainType.PLAIN or terrain_type == MapTypes.TerrainType.TOWN_CENTER


func _result(can_place: bool, reason: String, cell: Vector2i, region: RefCounted, building_type: int) -> RefCounted:
	var result := PlacementResultScript.new()
	result.setup(can_place, reason, cell, region, building_type)
	return result
