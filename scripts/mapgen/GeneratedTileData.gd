class_name GeneratedTileData
extends RefCounted


const TERRAIN_WATER: StringName = &"water"
const TERRAIN_SHALLOW_WATER: StringName = &"shallow_water"
const TERRAIN_SAND: StringName = &"sand"
const TERRAIN_PLAIN: StringName = &"plain"
const TERRAIN_MUD: StringName = &"mud"

const RESOURCE_NONE: StringName = &"none"
const RESOURCE_WOOD: StringName = &"wood"
const RESOURCE_STONE: StringName = &"stone"

var cell: Vector2i = Vector2i.ZERO
var base_terrain: StringName = TERRAIN_PLAIN
var resource_type: StringName = RESOURCE_NONE
var resource_patch_id: int = -1

var buildable: bool = true
var passable: bool = true

var height_value: float = 0.0
var moisture_value: float = 0.0
var temperature_value: float = 0.0
var resource_value: float = 0.0


func _init() -> void:
	reset()


func reset() -> void:
	cell = Vector2i.ZERO
	base_terrain = TERRAIN_PLAIN
	resource_type = RESOURCE_NONE
	resource_patch_id = -1
	buildable = true
	passable = true
	height_value = 0.0
	moisture_value = 0.0
	temperature_value = 0.0
	resource_value = 0.0


func setup(next_cell: Vector2i, next_base_terrain: StringName) -> void:
	cell = next_cell
	base_terrain = next_base_terrain


func set_base_terrain(next_base_terrain: StringName, next_buildable: bool, next_passable: bool) -> void:
	base_terrain = next_base_terrain
	buildable = next_buildable
	passable = next_passable


func set_resource(next_resource_type: StringName, next_resource_patch_id: int, next_resource_value: float = 0.0) -> void:
	resource_type = next_resource_type
	resource_patch_id = next_resource_patch_id
	resource_value = next_resource_value


func clear_resource() -> void:
	resource_type = RESOURCE_NONE
	resource_patch_id = -1
	resource_value = 0.0


func set_noise_values(next_height: float, next_moisture: float, next_temperature: float) -> void:
	height_value = next_height
	moisture_value = next_moisture
	temperature_value = next_temperature


func is_water() -> bool:
	return base_terrain == TERRAIN_WATER or base_terrain == TERRAIN_SHALLOW_WATER


func has_resource() -> bool:
	return resource_type != RESOURCE_NONE


func clone() -> RefCounted:
	var copy := GeneratedTileData.new()
	copy.cell = cell
	copy.base_terrain = base_terrain
	copy.resource_type = resource_type
	copy.resource_patch_id = resource_patch_id
	copy.buildable = buildable
	copy.passable = passable
	copy.height_value = height_value
	copy.moisture_value = moisture_value
	copy.temperature_value = temperature_value
	copy.resource_value = resource_value
	return copy


func to_dictionary() -> Dictionary:
	return {
		"cell": cell,
		"base_terrain": base_terrain,
		"resource_type": resource_type,
		"resource_patch_id": resource_patch_id,
		"buildable": buildable,
		"passable": passable,
		"height_value": height_value,
		"moisture_value": moisture_value,
		"temperature_value": temperature_value,
		"resource_value": resource_value,
	}
