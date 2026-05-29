class_name ResourceRegion
extends RefCounted

const MapTypes := preload("res://scripts/map/MapTypes.gd")

const TERRAIN_FOREST := MapTypes.TerrainType.FOREST
const TERRAIN_STONE := MapTypes.TerrainType.STONE
const TERRAIN_EMPTY := MapTypes.TerrainType.EMPTY

const RESOURCE_WOOD: StringName = &"wood"
const RESOURCE_STONE: StringName = &"stone"

var region_id: int = -1
var terrain_type: int = TERRAIN_EMPTY
var cells: Array[Vector2i] = []
var area: int = 0
var adjacent_empty_cells: Array[Vector2i] = []


func _init() -> void:
	setup(-1, TERRAIN_EMPTY)


func setup(next_region_id: int, next_terrain_type: int) -> void:
	region_id = next_region_id
	terrain_type = next_terrain_type
	cells.clear()
	adjacent_empty_cells.clear()
	area = 0


func add_cell(cell: Vector2i) -> void:
	if cells.has(cell):
		return
	cells.append(cell)
	area = cells.size()


func add_adjacent_empty_cell(cell: Vector2i) -> void:
	if adjacent_empty_cells.has(cell):
		return
	adjacent_empty_cells.append(cell)


func get_resource_type() -> StringName:
	match terrain_type:
		TERRAIN_FOREST:
			return RESOURCE_WOOD
		TERRAIN_STONE:
			return RESOURCE_STONE
		_:
			return &""


func get_resource_label() -> String:
	match terrain_type:
		TERRAIN_FOREST:
			return "Wood"
		TERRAIN_STONE:
			return "Stone"
		_:
			return ""


func contains_cell(cell: Vector2i) -> bool:
	return cells.has(cell)


func is_production_region() -> bool:
	return get_resource_type() != &""


func get_buildable_cell_count() -> int:
	return adjacent_empty_cells.size()


func get_farmable_cell_count() -> int:
	if terrain_type == MapTypes.TerrainType.PLAIN:
		return area
	return 0


func get_summary() -> Dictionary:
	return {
		"region_id": region_id,
		"terrain_type": terrain_type,
		"terrain_label": MapTypes.get_terrain_label(terrain_type),
		"resource_type": get_resource_type(),
		"area": area,
		"adjacent_buildable_cells": get_buildable_cell_count(),
		"farmable_cells": get_farmable_cell_count(),
	}

