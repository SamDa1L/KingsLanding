class_name BuildingPlacementController
extends RefCounted

const PlacementValidatorScript := preload("res://scripts/placement/PlacementValidator.gd")
const BuildingDataScript := preload("res://scripts/buildings/BuildingData.gd")

var validator: RefCounted = null
var occupied_cells: Dictionary = {}


func setup(grid: RefCounted, resource_regions: Dictionary, farmable_regions: Array, next_occupied_cells: Dictionary = {}, castle_cell: Vector2i = Vector2i(-1, -1)) -> void:
	occupied_cells = next_occupied_cells
	validator = PlacementValidatorScript.new()
	validator.setup(grid, resource_regions, farmable_regions, occupied_cells, castle_cell)


func can_place(building_type: int, cell: Vector2i) -> RefCounted:
	return validator.validate(building_type, cell)


func place(building_type: int, cell: Vector2i) -> RefCounted:
	var result: RefCounted = validator.validate(building_type, cell)
	if not result.can_place:
		return result

	occupied_cells[cell] = true
	var building := BuildingDataScript.new()
	building.setup(building_type)
	building.position = cell
	if result.bind_region != null:
		building.linked_region_id = int(result.bind_region.region_id)
	return building
