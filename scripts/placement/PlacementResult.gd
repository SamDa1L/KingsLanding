class_name PlacementResult
extends RefCounted

var can_place: bool = false
var reason: String = ""
var target_cell: Vector2i = Vector2i(-1, -1)
var bind_region: RefCounted = null
var building_type: int = -1
var cost: Dictionary = {}
var resource_cost_ok: bool = true


func setup(next_can_place: bool, next_reason: String, next_target_cell: Vector2i, next_bind_region: RefCounted, next_building_type: int, next_cost: Dictionary = {}, next_resource_cost_ok: bool = true) -> void:
	can_place = next_can_place
	reason = next_reason
	target_cell = next_target_cell
	bind_region = next_bind_region
	building_type = next_building_type
	cost = next_cost
	resource_cost_ok = next_resource_cost_ok


func is_valid() -> bool:
	return can_place


func get_failure_reason() -> String:
	return reason
