extends Node

signal inventory_changed(resources: Dictionary)

const FOOD := &"food"
const WOOD := &"wood"
const STONE := &"stone"
const GOLD := &"gold"

var _resources: Dictionary = {
	FOOD: 0,
	WOOD: 0,
	STONE: 0,
	GOLD: 0,
}


func _ready() -> void:
	emit_inventory_changed()


func add_resource(resource_type: StringName, amount: int) -> void:
	if amount <= 0:
		return

	_ensure_resource(resource_type)
	_resources[resource_type] += amount
	emit_inventory_changed()


func add_amount(resource_type: StringName, amount: float) -> void:
	if is_equal_approx(amount, 0.0):
		return

	_ensure_resource(resource_type)
	_resources[resource_type] = max(float(_resources[resource_type]) + amount, 0.0)
	emit_inventory_changed()


func apply_delta(delta: Dictionary) -> void:
	var has_changes := false
	for resource_type in delta.keys():
		var resource_name := _normalize_resource_type(resource_type)
		var amount := float(delta[resource_type])
		if is_equal_approx(amount, 0.0):
			continue
		_ensure_resource(resource_name)
		_resources[resource_name] = max(float(_resources[resource_name]) + amount, 0.0)
		has_changes = true
	if has_changes:
		emit_inventory_changed()


func reset_resources(next_resources: Dictionary = {}) -> void:
	_resources = {
		FOOD: 0,
		WOOD: 0,
		STONE: 0,
		GOLD: 0,
	}
	for resource_type in next_resources.keys():
		var resource_name := _normalize_resource_type(resource_type)
		_resources[resource_name] = max(float(next_resources[resource_type]), 0.0)
	emit_inventory_changed()


func get_amount(resource_type: StringName) -> int:
	_ensure_resource(resource_type)
	return int(floor(float(_resources[resource_type])))


func get_float_amount(resource_type: StringName) -> float:
	_ensure_resource(resource_type)
	return float(_resources[resource_type])


func get_all_resources() -> Dictionary:
	return _resources.duplicate()


func emit_inventory_changed() -> void:
	inventory_changed.emit(get_all_resources())


func _ensure_resource(resource_type: StringName) -> void:
	if not _resources.has(resource_type):
		_resources[resource_type] = 0


func _normalize_resource_type(resource_type: Variant) -> StringName:
	if resource_type is StringName:
		return resource_type
	return StringName(str(resource_type))
