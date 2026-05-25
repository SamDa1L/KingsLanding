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
		return _result(false, "Grid is missing.", cell, null, building_type)
	if not grid.is_inside(cell):
		return _result(false, "Target cell is outside the map.", cell, null, building_type)
	if occupied_cells.has(cell):
		return _result(false, "Target cell is already occupied.", cell, null, building_type)

	var terrain_type: int = grid.get_terrain(cell)
	match building_type:
		MapTypes.BuildingType.TOWN_CENTER:
			return _validate_castle(cell, terrain_type)
		MapTypes.BuildingType.LUMBER_CAMP:
			return _validate_resource_building(cell, terrain_type, MapTypes.TerrainType.FOREST, resource_regions.get(MapTypes.TerrainType.FOREST, []), "Lumber Camp")
		MapTypes.BuildingType.QUARRY:
			return _validate_resource_building(cell, terrain_type, MapTypes.TerrainType.STONE, resource_regions.get(MapTypes.TerrainType.STONE, []), "Quarry")
		MapTypes.BuildingType.FARM:
			return _validate_farm(cell, terrain_type)
		MapTypes.BuildingType.HOUSE:
			return _validate_house(cell, terrain_type)
		_:
			return _result(false, "Unknown building type.", cell, null, building_type)


func _validate_castle(cell: Vector2i, terrain_type: int) -> RefCounted:
	if not _is_castle_terrain(terrain_type):
		return _result(false, "Castle must be placed on empty, plain, or town center terrain.", cell, null, MapTypes.BuildingType.TOWN_CENTER)
	return _result(true, "", cell, null, MapTypes.BuildingType.TOWN_CENTER)


func _validate_resource_building(cell: Vector2i, terrain_type: int, resource_terrain: int, regions: Array, label: String) -> RefCounted:
	if terrain_type != MapTypes.TerrainType.EMPTY and terrain_type != MapTypes.TerrainType.PLAIN:
		return _result(false, "%s must be placed on a buildable empty or plain cell." % label, cell, null, -1)
	var region := _find_region_for_cell_or_adjacency(regions, cell)
	if region == null:
		return _result(false, "%s must be adjacent to a %s region." % [label, MapTypes.get_terrain_label(resource_terrain)], cell, null, -1)
	return _result(true, "", cell, region, -1)


func _validate_farm(cell: Vector2i, terrain_type: int) -> RefCounted:
	if terrain_type != MapTypes.TerrainType.PLAIN:
		return _result(false, "Farm must be placed on plain terrain.", cell, null, MapTypes.BuildingType.FARM)
	var region := _find_region_containing_cell(farmable_regions, cell)
	if region == null:
		return _result(false, "Farm must be placed inside a farmable plain region.", cell, null, MapTypes.BuildingType.FARM)
	return _result(true, "", cell, region, MapTypes.BuildingType.FARM)


func _validate_house(cell: Vector2i, terrain_type: int) -> RefCounted:
	if terrain_type == MapTypes.TerrainType.WATER or terrain_type == MapTypes.TerrainType.MOUNTAIN:
		return _result(false, "House cannot be placed on water or mountain.", cell, null, MapTypes.BuildingType.HOUSE)
	if terrain_type == MapTypes.TerrainType.FOREST or terrain_type == MapTypes.TerrainType.STONE:
		return _result(false, "House cannot be placed on resource terrain.", cell, null, MapTypes.BuildingType.HOUSE)
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