class_name InitialBuildingSpawner
extends RefCounted

const MapTypes := preload("res://scripts/map/MapTypes.gd")
const BuildingDataScript := preload("res://scripts/buildings/BuildingData.gd")
const BuildingFootprintRulesScript := preload("res://scripts/buildings/BuildingFootprintRules.gd")
const DEFAULT_RANDOM_SEED := 20260523

var last_spawn_warnings: Array[String] = []

var _rng := RandomNumberGenerator.new()


func spawn_initial_buildings(
	grid: RefCounted,
	resource_regions: Dictionary,
	farmable_regions: Array,
	seed: int = DEFAULT_RANDOM_SEED,
	include_production_buildings: bool = true
) -> Array:
	last_spawn_warnings.clear()
	_rng.seed = seed

	var occupied_cells: Dictionary = {}
	var buildings: Array = []
	var castle := _spawn_castle(grid, occupied_cells)
	if castle != null:
		buildings.append(castle)
	if not include_production_buildings:
		return buildings
	var lumber_camp := _spawn_building_for_regions(
		resource_regions.get(MapTypes.TerrainType.FOREST, []),
		MapTypes.BuildingType.LUMBER_CAMP,
		occupied_cells
	)
	if lumber_camp != null:
		buildings.append(lumber_camp)

	var quarry := _spawn_building_for_regions(
		resource_regions.get(MapTypes.TerrainType.STONE, []),
		MapTypes.BuildingType.QUARRY,
		occupied_cells
	)
	if quarry != null:
		buildings.append(quarry)

	var farm := _spawn_farm_for_regions(farmable_regions, occupied_cells)
	if farm != null:
		buildings.append(farm)

	return buildings


func _spawn_castle(grid: RefCounted, occupied_cells: Dictionary) -> RefCounted:
	var castle_cell := _find_castle_cell(grid)
	if castle_cell.x < 0 or castle_cell.y < 0:
		last_spawn_warnings.append("No legal cell for Castle.")
		return null

	var building := _create_building(MapTypes.BuildingType.TOWN_CENTER, castle_cell, -1)
	BuildingFootprintRulesScript.register_building_footprint(occupied_cells, MapTypes.BuildingType.TOWN_CENTER, castle_cell)
	return building


func _find_castle_cell(grid: RefCounted) -> Vector2i:
	if grid == null or grid.width <= 0 or grid.height <= 0:
		return Vector2i(-1, -1)

	var town_center_cell := _find_nearest_cell_with_terrain(grid, MapTypes.TerrainType.TOWN_CENTER)
	if town_center_cell.x >= 0 and town_center_cell.y >= 0:
		if BuildingFootprintRulesScript.is_castle_footprint_valid(grid, town_center_cell):
			return town_center_cell
		return BuildingFootprintRulesScript.find_nearest_valid_castle_cell(grid, town_center_cell)

	var center := Vector2i(grid.width / 2, grid.height / 2)
	return BuildingFootprintRulesScript.find_nearest_valid_castle_cell(grid, center)


func _find_nearest_cell_with_terrain(grid: RefCounted, terrain_type: int) -> Vector2i:
	if grid == null or grid.width <= 0 or grid.height <= 0:
		return Vector2i(-1, -1)

	var center := Vector2i(grid.width / 2, grid.height / 2)
	var best_cell := Vector2i(-1, -1)
	var best_distance: int = -1
	for cell in grid.get_all_cells():
		if grid.get_terrain(cell) != terrain_type:
			continue
		var distance: int = abs(cell.x - center.x) + abs(cell.y - center.y)
		if best_distance < 0 or distance < best_distance:
			best_distance = distance
			best_cell = cell

	return best_cell


func _is_castle_terrain(terrain_type: int) -> bool:
	return BuildingFootprintRulesScript.is_castle_terrain(terrain_type)


func _spawn_building_for_regions(regions: Array, building_type: int, occupied_cells: Dictionary) -> RefCounted:
	var shuffled_regions := _shuffled_array(regions)
	for region in shuffled_regions:
		if region == null:
			continue
		var candidate_cells := _shuffled_vector_array(region.adjacent_empty_cells)
		for cell in candidate_cells:
			if occupied_cells.has(cell):
				continue
			var building := _create_building(building_type, cell, int(region.region_id))
			occupied_cells[cell] = true
			return building

	last_spawn_warnings.append("No legal cell for %s." % MapTypes.get_building_label(building_type))
	return null


func _spawn_farm_for_regions(regions: Array, occupied_cells: Dictionary) -> RefCounted:
	var shuffled_regions := _shuffled_array(regions)
	for region in shuffled_regions:
		if region == null:
			continue
		var candidate_cells := _shuffled_vector_array(region.cells)
		for cell in candidate_cells:
			if occupied_cells.has(cell):
				continue
			var building := _create_building(MapTypes.BuildingType.FARM, cell, int(region.region_id))
			occupied_cells[cell] = true
			return building

	last_spawn_warnings.append("No legal cell for %s." % MapTypes.get_building_label(MapTypes.BuildingType.FARM))
	return null


func _create_building(building_type: int, cell: Vector2i, linked_region_id: int) -> RefCounted:
	var building := BuildingDataScript.new()
	building.setup(building_type)
	building.position = cell
	building.linked_region_id = linked_region_id
	return building


func _shuffled_array(values: Array) -> Array:
	var result := values.duplicate()
	for index in range(result.size() - 1, 0, -1):
		var swap_index := _rng.randi_range(0, index)
		var temp = result[index]
		result[index] = result[swap_index]
		result[swap_index] = temp
	return result


func _shuffled_vector_array(values: Array[Vector2i]) -> Array[Vector2i]:
	var result := values.duplicate()
	for index in range(result.size() - 1, 0, -1):
		var swap_index := _rng.randi_range(0, index)
		var temp: Vector2i = result[index]
		result[index] = result[swap_index]
		result[swap_index] = temp
	return result
