class_name MapTypes
extends RefCounted


enum TerrainType {
	TOWN_CENTER,
	FOREST,
	STONE,
	PLAIN,
	ROAD,
	EMPTY,
	WATER,
	MOUNTAIN,
}


enum BuildingType {
	TOWN_CENTER,
	LUMBER_CAMP,
	QUARRY,
	FARM,
	HOUSE,
}


enum TaxPolicy {
	LOW,
	NORMAL,
	HIGH,
}


const RESOURCE_FOOD: StringName = &"food"
const RESOURCE_WOOD: StringName = &"wood"
const RESOURCE_STONE: StringName = &"stone"
const RESOURCE_GOLD: StringName = &"gold"

const CARDINAL_DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]


static func is_resource_terrain(terrain_type: int) -> bool:
	return terrain_type == TerrainType.FOREST or terrain_type == TerrainType.STONE


static func is_blocking_terrain(terrain_type: int) -> bool:
	return terrain_type == TerrainType.WATER or terrain_type == TerrainType.MOUNTAIN


static func is_walkable_terrain(terrain_type: int) -> bool:
	return terrain_type != TerrainType.WATER and terrain_type != TerrainType.MOUNTAIN


static func is_buildable_terrain(terrain_type: int) -> bool:
	return terrain_type == TerrainType.EMPTY or terrain_type == TerrainType.PLAIN


static func is_farmable_terrain(terrain_type: int) -> bool:
	return terrain_type == TerrainType.PLAIN


static func get_cardinal_directions() -> Array[Vector2i]:
	return CARDINAL_DIRECTIONS.duplicate()


static func get_terrain_label(terrain_type: int) -> String:
	match terrain_type:
		TerrainType.TOWN_CENTER:
			return "Town Center"
		TerrainType.FOREST:
			return "Forest"
		TerrainType.STONE:
			return "Stone"
		TerrainType.PLAIN:
			return "Plain"
		TerrainType.ROAD:
			return "Road"
		TerrainType.EMPTY:
			return "Empty"
		TerrainType.WATER:
			return "Water"
		TerrainType.MOUNTAIN:
			return "Mountain"
		_:
			return "Unknown"


static func get_building_label(building_type: int) -> String:
	match building_type:
		BuildingType.TOWN_CENTER:
			return "Castle"
		BuildingType.LUMBER_CAMP:
			return "Lumber Camp"
		BuildingType.QUARRY:
			return "Quarry"
		BuildingType.FARM:
			return "Farm"
		BuildingType.HOUSE:
			return "House"
		_:
			return "Unknown"


static func get_tax_policy_label(tax_policy: int) -> String:
	match tax_policy:
		TaxPolicy.LOW:
			return "Low"
		TaxPolicy.NORMAL:
			return "Normal"
		TaxPolicy.HIGH:
			return "High"
		_:
			return "Unknown"


static func get_resource_name_for_terrain(terrain_type: int) -> StringName:
	match terrain_type:
		TerrainType.FOREST:
			return RESOURCE_WOOD
		TerrainType.STONE:
			return RESOURCE_STONE
		_:
			return &""


static func get_resource_label_for_terrain(terrain_type: int) -> String:
	match terrain_type:
		TerrainType.FOREST:
			return "Wood"
		TerrainType.STONE:
			return "Stone"
		_:
			return ""


static func get_resource_name_for_building(building_type: int) -> StringName:
	match building_type:
		BuildingType.LUMBER_CAMP:
			return RESOURCE_WOOD
		BuildingType.QUARRY:
			return RESOURCE_STONE
		BuildingType.FARM:
			return RESOURCE_FOOD
		_:
			return &""


static func get_default_building_type_for_terrain(terrain_type: int) -> int:
	match terrain_type:
		TerrainType.FOREST:
			return BuildingType.LUMBER_CAMP
		TerrainType.STONE:
			return BuildingType.QUARRY
		TerrainType.PLAIN:
			return BuildingType.FARM
		TerrainType.TOWN_CENTER:
			return BuildingType.TOWN_CENTER
		_:
			return -1


static func is_production_building(building_type: int) -> bool:
	return get_resource_name_for_building(building_type) != &""


