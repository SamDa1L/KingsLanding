class_name BuildingData
extends RefCounted

const MapTypes := preload("res://scripts/map/MapTypes.gd")
const DEFAULT_STORAGE_CAPACITY_BY_BUILDING: Dictionary = {
	MapTypes.BuildingType.FARM: 10.0,
	MapTypes.BuildingType.LUMBER_CAMP: 30.0,
	MapTypes.BuildingType.QUARRY: 20.0,
}
const DEFAULT_WORKER_CAPACITY_BY_BUILDING: Dictionary = {
	MapTypes.BuildingType.FARM: 4,
	MapTypes.BuildingType.LUMBER_CAMP: 6,
	MapTypes.BuildingType.QUARRY: 6,
}

var building_type: int = MapTypes.BuildingType.HOUSE
var position: Vector2i = Vector2i.ZERO
var linked_region_id: int = -1
var display_name: String = "Building"
var resource_type: StringName = &""
var stored_amount: int = 0
var capacity: int = 0
var is_active: bool = true
var stored_resources: Dictionary = {}
var storage_capacity: Dictionary = {}
var worker_count: int = 0
var worker_capacity: int = 0


func _init() -> void:
	setup(MapTypes.BuildingType.HOUSE)


func setup(next_building_type: int) -> void:
	building_type = next_building_type
	display_name = MapTypes.get_building_label(building_type)
	resource_type = MapTypes.get_resource_name_for_building(building_type)
	position = Vector2i.ZERO
	linked_region_id = -1
	stored_resources = {}
	storage_capacity = {}
	stored_amount = 0
	capacity = 0
	is_active = true
	worker_count = 0
	worker_capacity = 0
	_configure_storage_defaults()
	_configure_worker_defaults()
	_sync_legacy_storage_values()


func is_production_building() -> bool:
	return resource_type != &""


func get_building_label() -> String:
	if display_name != "":
		return display_name
	return MapTypes.get_building_label(building_type)


func can_store_resources() -> bool:
	return is_production_building() and get_storage_capacity(resource_type) > 0.0


func has_workers() -> bool:
	return worker_capacity > 0


func get_worker_capacity() -> int:
	return max(worker_capacity, 0)


func get_worker_count() -> int:
	return max(worker_count, 0)


func set_worker_count(next_worker_count: int) -> int:
	worker_count = clampi(next_worker_count, 0, get_worker_capacity())
	return worker_count


func add_workers(amount: int) -> int:
	if amount <= 0:
		return get_worker_count()
	return set_worker_count(worker_count + amount)


func remove_workers(amount: int) -> int:
	if amount <= 0:
		return get_worker_count()
	return set_worker_count(worker_count - amount)


func can_accept_more_workers() -> bool:
	return get_worker_count() < get_worker_capacity()


func add_to_storage(next_resource_type: StringName, amount: float) -> float:
	if not is_active or amount <= 0.0 or next_resource_type == &"":
		return 0.0
	if not storage_capacity.has(next_resource_type):
		return 0.0

	var capacity_value := float(storage_capacity.get(next_resource_type, 0.0))
	if capacity_value <= 0.0:
		return 0.0

	var current_amount := float(stored_resources.get(next_resource_type, 0.0))
	var accepted_amount: float = float(min(amount, max(capacity_value - current_amount, 0.0)))
	if accepted_amount <= 0.0:
		return 0.0

	stored_resources[next_resource_type] = current_amount + accepted_amount
	_sync_legacy_storage_values()
	return accepted_amount


func claim_storage() -> Dictionary:
	var claimed: Dictionary = {}
	for next_resource_type in stored_resources.keys():
		var stored_value := float(stored_resources[next_resource_type])
		if stored_value <= 0.0:
			continue
		claimed[next_resource_type] = stored_value
		stored_resources[next_resource_type] = 0.0

	_sync_legacy_storage_values()
	return claimed


func get_stored_amount(next_resource_type: StringName) -> float:
	return float(stored_resources.get(next_resource_type, 0.0))


func get_storage_capacity(next_resource_type: StringName) -> float:
	return float(storage_capacity.get(next_resource_type, 0.0))


func has_claimable_resources() -> bool:
	for stored_value in stored_resources.values():
		if float(stored_value) > 0.0:
			return true
	return false


func get_storage_summary() -> String:
	if not can_store_resources():
		return "无本地库存"
	var stored_value := get_stored_amount(resource_type)
	var capacity_value := get_storage_capacity(resource_type)
	return "%s %.2f / %.2f" % [_get_resource_label(resource_type), stored_value, capacity_value]


func get_claim_empty_message() -> String:
	return "暂无可领取资源"


func clear_storage() -> void:
	for next_resource_type in stored_resources.keys():
		stored_resources[next_resource_type] = 0.0
	_sync_legacy_storage_values()


func _configure_storage_defaults() -> void:
	if resource_type == &"":
		return
	var capacity_value := _get_default_storage_capacity(building_type)
	if capacity_value <= 0.0:
		return
	stored_resources[resource_type] = 0.0
	storage_capacity[resource_type] = capacity_value


func _configure_worker_defaults() -> void:
	worker_capacity = _get_default_worker_capacity(building_type)
	worker_count = 1 if worker_capacity > 0 else 0
	worker_count = clampi(worker_count, 0, worker_capacity)


func _get_default_worker_capacity(next_building_type: int) -> int:
	return int(DEFAULT_WORKER_CAPACITY_BY_BUILDING.get(next_building_type, 0))


func _get_default_storage_capacity(next_building_type: int) -> float:
	return float(DEFAULT_STORAGE_CAPACITY_BY_BUILDING.get(next_building_type, 0.0))


func _sync_legacy_storage_values() -> void:
	if resource_type == &"":
		stored_amount = 0
		capacity = 0
		return
	stored_amount = int(floor(float(stored_resources.get(resource_type, 0.0))))
	capacity = int(floor(float(storage_capacity.get(resource_type, 0.0))))


func _get_resource_label(next_resource_type: StringName) -> String:
	match next_resource_type:
		&"food":
			return "食物"
		&"wood":
			return "木材"
		&"stone":
			return "石料"
		_:
			return "资源"
