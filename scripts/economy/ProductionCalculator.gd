class_name ProductionCalculator
extends RefCounted

const MapTypes := preload("res://scripts/map/MapTypes.gd")
const TaxSystemScript := preload("res://scripts/governance/TaxSystem.gd")

const FARM_FOOD_PER_WORKER_PER_MINUTE := 0.8
const WOOD_PER_PRESENT_WORKER_PER_MINUTE := 1.0
const STONE_PER_PRESENT_WORKER_PER_MINUTE := 0.7
const WOOD_PER_FOREST_CELL_PER_MINUTE := 0.5
const STONE_PER_STONE_CELL_PER_MINUTE := 0.35
const MIN_WOOD_PER_MINUTE := 1.0
const MAX_WOOD_PER_MINUTE := 12.0
const MIN_STONE_PER_MINUTE := 1.0
const MAX_STONE_PER_MINUTE := 8.0
const FOOD_CONSUMPTION_PER_POPULATION_PER_MINUTE := 1.0 / 1440.0


func get_region_output_per_minute(region: RefCounted, building_type: int) -> float:
	if region == null:
		return 0.0
	if not _building_matches_region(building_type, region.terrain_type):
		return 0.0
	var raw_output := float(region.area) * get_cell_output_per_minute(region.terrain_type)
	match building_type:
		MapTypes.BuildingType.LUMBER_CAMP:
			return clampf(raw_output, MIN_WOOD_PER_MINUTE, MAX_WOOD_PER_MINUTE)
		MapTypes.BuildingType.QUARRY:
			return clampf(raw_output, MIN_STONE_PER_MINUTE, MAX_STONE_PER_MINUTE)
		_:
			return raw_output


func get_building_output_per_minute(building: RefCounted, regions_by_id: Dictionary) -> Dictionary:
	var present_worker_count := _get_worker_count(building)
	return get_building_output_per_minute_with_present_workers(building, regions_by_id, present_worker_count)


func get_building_output_per_minute_with_present_workers(building: RefCounted, regions_by_id: Dictionary, present_worker_count: int) -> Dictionary:
	var output: Dictionary = {}
	if building == null or not building.is_active or not building.is_production_building():
		return output

	var resource_type := MapTypes.get_resource_name_for_building(building.building_type)
	if resource_type == &"":
		return output

	if present_worker_count <= 0:
		return output

	var amount := 0.0
	if building.building_type == MapTypes.BuildingType.FARM:
		amount = float(present_worker_count) * FARM_FOOD_PER_WORKER_PER_MINUTE
	else:
		var region := _get_region_for_building(building, regions_by_id)
		if region == null:
			return output
		var region_output := get_region_output_per_minute(region, building.building_type)
		var worker_output := _get_worker_limited_output_per_minute(building.building_type, present_worker_count)
		amount = min(region_output, worker_output)

	if amount > 0.0:
		output[resource_type] = amount
	return output


func get_cell_output_per_minute(terrain_type: int) -> float:
	match terrain_type:
		MapTypes.TerrainType.FOREST:
			return WOOD_PER_FOREST_CELL_PER_MINUTE
		MapTypes.TerrainType.STONE:
			return STONE_PER_STONE_CELL_PER_MINUTE
		_:
			return 0.0


func get_tax_income_per_minute(population: int, tax_policy: int) -> float:
	var tax_system := TaxSystemScript.new()
	return tax_system.get_minute_gold_income(population, tax_policy)


func get_food_consumption_per_minute(population: int) -> float:
	return float(max(population, 0)) * FOOD_CONSUMPTION_PER_POPULATION_PER_MINUTE


func calculate_minute_delta(buildings: Array, regions_by_id: Dictionary, governance_state: RefCounted) -> Dictionary:
	var delta := {
		MapTypes.RESOURCE_FOOD: 0.0,
		MapTypes.RESOURCE_WOOD: 0.0,
		MapTypes.RESOURCE_STONE: 0.0,
		MapTypes.RESOURCE_GOLD: 0.0,
	}

	for building in buildings:
		var building_output := get_building_output_per_minute(building, regions_by_id)
		for resource_type in building_output.keys():
			delta[resource_type] += float(building_output[resource_type])

	if governance_state != null:
		delta[MapTypes.RESOURCE_FOOD] -= get_food_consumption_per_minute(governance_state.population)
		delta[MapTypes.RESOURCE_GOLD] += get_tax_income_per_minute(governance_state.population, governance_state.tax_policy)

	return delta


func _building_matches_region(building_type: int, terrain_type: int) -> bool:
	match building_type:
		MapTypes.BuildingType.LUMBER_CAMP:
			return terrain_type == MapTypes.TerrainType.FOREST
		MapTypes.BuildingType.QUARRY:
			return terrain_type == MapTypes.TerrainType.STONE
		_:
			return false


func _get_region_for_building(building: RefCounted, regions_by_id: Dictionary) -> RefCounted:
	if building == null:
		return null
	var linked_region_id: int = int(building.linked_region_id)
	var terrain_type := _get_required_region_terrain(building.building_type)
	if terrain_type >= 0 and regions_by_id.has(terrain_type) and regions_by_id[terrain_type] is Dictionary:
		var regions_for_terrain: Dictionary = regions_by_id[terrain_type]
		if regions_for_terrain.has(linked_region_id):
			return regions_for_terrain[linked_region_id]
	if regions_by_id.has(linked_region_id):
		return regions_by_id[linked_region_id]
	return null


func _get_required_region_terrain(building_type: int) -> int:
	match building_type:
		MapTypes.BuildingType.LUMBER_CAMP:
			return MapTypes.TerrainType.FOREST
		MapTypes.BuildingType.QUARRY:
			return MapTypes.TerrainType.STONE
		_:
			return -1


func _get_worker_multiplier(building: RefCounted) -> float:
	if building == null:
		return 0.0
	if building.has_method("get_worker_count") and building.has_method("get_worker_capacity"):
		if int(building.call("get_worker_capacity")) <= 0:
			return 0.0
		return float(max(int(building.call("get_worker_count")), 0))
	return 1.0


func _get_worker_count(building: RefCounted) -> int:
	if building == null:
		return 0
	if building.has_method("get_worker_count") and building.has_method("get_worker_capacity"):
		if int(building.call("get_worker_capacity")) <= 0:
			return 0
		return max(int(building.call("get_worker_count")), 0)
	return 1


func _get_worker_limited_output_per_minute(building_type: int, present_worker_count: int) -> float:
	if present_worker_count <= 0:
		return 0.0
	match building_type:
		MapTypes.BuildingType.LUMBER_CAMP:
			return float(present_worker_count) * WOOD_PER_PRESENT_WORKER_PER_MINUTE
		MapTypes.BuildingType.QUARRY:
			return float(present_worker_count) * STONE_PER_PRESENT_WORKER_PER_MINUTE
		MapTypes.BuildingType.FARM:
			return float(present_worker_count) * FARM_FOOD_PER_WORKER_PER_MINUTE
		_:
			return 0.0
