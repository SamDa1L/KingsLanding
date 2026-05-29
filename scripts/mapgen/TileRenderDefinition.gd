class_name TileRenderDefinition
extends RefCounted


const GeneratedTileDataScript := preload("res://scripts/mapgen/GeneratedTileData.gd")

const TILE_SOURCE_ID := 0

const INVALID_ATLAS := Vector2i(-1, -1)

const BASE_TILE_ATLAS := {
	GeneratedTileDataScript.TERRAIN_PLAIN: Vector2i(1, 1),
	GeneratedTileDataScript.TERRAIN_WATER: Vector2i(1, 5),
	GeneratedTileDataScript.TERRAIN_SHALLOW_WATER: Vector2i(1, 5),
	GeneratedTileDataScript.TERRAIN_SAND: Vector2i(1, 8),
}

const RESOURCE_TILE_ATLAS := {
	&"wood": Vector2i(6, 1),
	&"stone": Vector2i(6, 3),
}

const TRANSITION_TILE_ATLAS := {
	&"water_to_land": {
		1: Vector2i(1, 4),
		2: Vector2i(2, 5),
		3: Vector2i(2, 4),
		4: Vector2i(3, 6),
		5: Vector2i(1, 4),
		6: Vector2i(4, 6),
		7: Vector2i(2, 4),
		8: Vector2i(3, 5),
		9: Vector2i(0, 4),
		10: Vector2i(3, 5),
		11: Vector2i(0, 4),
		12: Vector2i(5, 6),
		13: Vector2i(5, 6),
		14: Vector2i(4, 6),
		15: Vector2i(1, 4),
	}
}


static func get_base_tile(base_terrain: StringName) -> Vector2i:
	return BASE_TILE_ATLAS.get(base_terrain, INVALID_ATLAS)


static func get_resource_tile(resource_type: StringName) -> Vector2i:
	return RESOURCE_TILE_ATLAS.get(resource_type, INVALID_ATLAS)


static func get_transition_tile(transition_name: StringName, mask: int) -> Vector2i:
	if not TRANSITION_TILE_ATLAS.has(transition_name):
		return INVALID_ATLAS
	var transition_tiles: Dictionary = TRANSITION_TILE_ATLAS[transition_name]
	return transition_tiles.get(mask, INVALID_ATLAS)
