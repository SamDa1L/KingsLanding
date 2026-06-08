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
var linked_resource_depleted: bool = false


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
	linked_resource_depleted = false
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


func set_linked_resource_depleted(depleted: bool) -> void:
	linked_resource_depleted = depleted


func is_linked_resource_depleted() -> bool:
	return linked_resource_depleted


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


func to_save_data() -> Dictionary:
	return {
		"building_type": building_type,
		"position": position,
		"linked_region_id": linked_region_id,
		"display_name": display_name,
		"resource_type": resource_type,
		"is_active": is_active,
		"stored_resources": stored_resources.duplicate(true),
		"storage_capacity": storage_capacity.duplicate(true),
		"worker_count": worker_count,
		"worker_capacity": worker_capacity,
		"linked_resource_depleted": linked_resource_depleted,
	}


func restore_from_save_data(save_data: Dictionary) -> bool:
	if save_data.is_empty():
		return false
	var next_building_type: int = int(save_data.get("building_type", MapTypes.BuildingType.HOUSE))
	setup(next_building_type)

	var position_value: Variant = save_data.get("position", position)
	if typeof(position_value) == TYPE_VECTOR2I:
		position = position_value
	linked_region_id = int(save_data.get("linked_region_id", linked_region_id))
	display_name = str(save_data.get("display_name", display_name))
	var resource_type_value: Variant = save_data.get("resource_type", resource_type)
	resource_type = StringName(str(resource_type_value))
	is_active = bool(save_data.get("is_active", is_active))

	var next_storage_capacity: Dictionary = _normalize_resource_amount_dictionary(save_data.get("storage_capacity", storage_capacity), storage_capacity)
	var next_stored_resources: Dictionary = _normalize_resource_amount_dictionary(save_data.get("stored_resources", stored_resources), stored_resources)
	storage_capacity = next_storage_capacity
	stored_resources = next_stored_resources
	worker_capacity = max(int(save_data.get("worker_capacity", worker_capacity)), 0)
	worker_count = clampi(int(save_data.get("worker_count", worker_count)), 0, worker_capacity)
	linked_resource_depleted = bool(save_data.get("linked_resource_depleted", linked_resource_depleted))
	_sync_legacy_storage_values()
	return true


static func from_save_data(save_data: Dictionary) -> BuildingData:
	var building := BuildingData.new()
	if not building.restore_from_save_data(save_data):
		return null
	return building


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


static func _normalize_resource_amount_dictionary(source_variant: Variant, fallback: Dictionary = {}) -> Dictionary:
	if typeof(source_variant) != TYPE_DICTIONARY:
		return fallback.duplicate(true)
	var source: Dictionary = source_variant
	var result: Dictionary = {}
	for resource_type_key in source.keys():
		var resource_name := StringName(str(resource_type_key))
		result[resource_name] = max(float(source.get(resource_type_key, 0.0)), 0.0)
	return result


func _get_resource_label(next_resource_type: StringName) -> String:
	match next_resource_type:
		&"food":
			return "食物"
		&"wood":
			return "木头"
		&"stone":
			return "石材"
		_:
			return "资源"
