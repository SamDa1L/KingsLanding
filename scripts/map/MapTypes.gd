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
			return "城堡"
		TerrainType.FOREST:
			return "森林"
		TerrainType.STONE:
			return "石料"
		TerrainType.PLAIN:
			return "平原"
		TerrainType.ROAD:
			return "道路"
		TerrainType.EMPTY:
			return "空地"
		TerrainType.WATER:
			return "水域"
		TerrainType.MOUNTAIN:
			return "山地"
		_:
			return "未知"


static func get_building_label(building_type: int) -> String:
	match building_type:
		BuildingType.TOWN_CENTER:
			return "城堡"
		BuildingType.LUMBER_CAMP:
			return "伐木场"
		BuildingType.QUARRY:
			return "采石场"
		BuildingType.FARM:
			return "农场"
		BuildingType.HOUSE:
			return "住宅"
		_:
			return "未知"


static func get_tax_policy_label(tax_policy: int) -> String:
	match tax_policy:
		TaxPolicy.LOW:
			return "低税"
		TaxPolicy.NORMAL:
			return "正常税"
		TaxPolicy.HIGH:
			return "重税"
		_:
			return "未知"


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
			return "木材"
		TerrainType.STONE:
			return "石料"
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


static func get_building_cost(building_type: int) -> Dictionary:
	match building_type:
		BuildingType.LUMBER_CAMP:
			return {
				RESOURCE_WOOD: 8.0,
				RESOURCE_STONE: 4.0,
				RESOURCE_GOLD: 4.0,
			}
		BuildingType.QUARRY:
			return {
				RESOURCE_WOOD: 4.0,
				RESOURCE_STONE: 8.0,
				RESOURCE_GOLD: 4.0,
			}
		BuildingType.FARM:
			return {
				RESOURCE_WOOD: 6.0,
				RESOURCE_STONE: 2.0,
				RESOURCE_GOLD: 4.0,
			}
		BuildingType.HOUSE:
			return {
				RESOURCE_WOOD: 12.0,
				RESOURCE_STONE: 6.0,
				RESOURCE_GOLD: 6.0,
			}
		_:
			return {}


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


