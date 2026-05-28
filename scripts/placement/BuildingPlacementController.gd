class_name BuildingPlacementController
extends RefCounted

const PlacementValidatorScript := preload("res://scripts/placement/PlacementValidator.gd")
const BuildingDataScript := preload("res://scripts/buildings/BuildingData.gd")
const MapTypes := preload("res://scripts/map/MapTypes.gd")

var validator: RefCounted = null
var occupied_cells: Dictionary = {}
var resource_inventory: Node = null


func setup(grid: RefCounted, resource_regions: Dictionary, farmable_regions: Array, next_occupied_cells: Dictionary = {}, castle_cell: Vector2i = Vector2i(-1, -1), next_resource_inventory: Node = null) -> void:
	occupied_cells = next_occupied_cells
	resource_inventory = next_resource_inventory
	validator = PlacementValidatorScript.new()
	validator.setup(grid, resource_regions, farmable_regions, occupied_cells, castle_cell)


func can_place(building_type: int, cell: Vector2i) -> RefCounted:
	var result: RefCounted = validator.validate(building_type, cell)
	if result == null:
		return null
	var cost := MapTypes.get_building_cost(building_type)
	result.cost = cost
	result.resource_cost_ok = _can_afford_cost(cost)
	if bool(result.can_place) and not bool(result.resource_cost_ok):
		result.can_place = false
		result.reason = _build_insufficient_cost_text(cost)
	return result


func place(building_type: int, cell: Vector2i) -> RefCounted:
	var result: RefCounted = can_place(building_type, cell)
	if not result.can_place:
		return result

	var cost := MapTypes.get_building_cost(building_type)
	if not _spend_cost(cost):
		result.can_place = false
		result.resource_cost_ok = false
		result.reason = _build_insufficient_cost_text(cost)
		return result

	occupied_cells[cell] = true
	var building := BuildingDataScript.new()
	building.setup(building_type)
	building.position = cell
	if result.bind_region != null:
		building.linked_region_id = int(result.bind_region.region_id)
	return building


func _can_afford_cost(cost: Dictionary) -> bool:
	if cost.is_empty():
		return true
	if resource_inventory == null or not resource_inventory.has_method("get_float_amount"):
		return true
	for resource_type in cost.keys():
		var required_amount := float(cost.get(resource_type, 0.0))
		if required_amount <= 0.0:
			continue
		var current_amount := float(resource_inventory.call("get_float_amount", resource_type))
		if current_amount + 0.001 < required_amount:
			return false
	return true


func _spend_cost(cost: Dictionary) -> bool:
	if cost.is_empty():
		return true
	if not _can_afford_cost(cost):
		return false
	if resource_inventory == null or not resource_inventory.has_method("apply_delta"):
		return true
	var delta: Dictionary = {}
	for resource_type in cost.keys():
		var required_amount := float(cost.get(resource_type, 0.0))
		if required_amount > 0.0:
			delta[resource_type] = -required_amount
	if not delta.is_empty():
		resource_inventory.call("apply_delta", delta)
	return true


func _build_insufficient_cost_text(cost: Dictionary) -> String:
	var missing_parts: Array[String] = []
	if resource_inventory == null or not resource_inventory.has_method("get_float_amount"):
		return "资源库存不可用"
	for resource_type in cost.keys():
		var required_amount := float(cost.get(resource_type, 0.0))
		if required_amount <= 0.0:
			continue
		var current_amount := float(resource_inventory.call("get_float_amount", resource_type))
		if current_amount + 0.001 >= required_amount:
			continue
		missing_parts.append("%s %.0f/%.0f" % [_get_resource_label(resource_type), current_amount, required_amount])
	if missing_parts.is_empty():
		return "资源不足"
	return "资源不足：%s" % "，".join(missing_parts)


func _get_resource_label(resource_type: StringName) -> String:
	match resource_type:
		MapTypes.RESOURCE_FOOD:
			return "食物"
		MapTypes.RESOURCE_WOOD:
			return "木材"
		MapTypes.RESOURCE_STONE:
			return "石料"
		MapTypes.RESOURCE_GOLD:
			return "金币"
		_:
			return str(resource_type)
