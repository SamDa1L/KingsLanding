class_name ResourceDepletionState
extends RefCounted

const MapTypesScript := preload("res://scripts/map/MapTypes.gd")

const SAVE_VERSION: int = 1
const DEFAULT_WOOD_PER_CELL: int = 120
const DEFAULT_STONE_PER_CELL: int = 160

var default_wood_per_cell: float = float(DEFAULT_WOOD_PER_CELL)
var default_stone_per_cell: float = float(DEFAULT_STONE_PER_CELL)
var changed_cells: Dictionary = {}


func _init(p_default_wood_per_cell: int = DEFAULT_WOOD_PER_CELL, p_default_stone_per_cell: int = DEFAULT_STONE_PER_CELL) -> void:
	default_wood_per_cell = float(maxi(0, p_default_wood_per_cell))
	default_stone_per_cell = float(maxi(0, p_default_stone_per_cell))


func clear() -> void:
	changed_cells.clear()


func is_supported_resource_type(resource_type: StringName) -> bool:
	return resource_type == MapTypesScript.RESOURCE_WOOD or resource_type == MapTypesScript.RESOURCE_STONE


func get_default_amount_for_resource(resource_type: StringName) -> float:
	match resource_type:
		MapTypesScript.RESOURCE_WOOD:
			return default_wood_per_cell
		MapTypesScript.RESOURCE_STONE:
			return default_stone_per_cell
		_:
			return 0


func get_default_amount_for_terrain(terrain_type: int) -> float:
	var resource_type: StringName = MapTypesScript.get_resource_name_for_terrain(terrain_type)
	return get_default_amount_for_resource(resource_type)


func get_remaining_amount(cell: Vector2i, resource_type: StringName) -> float:
	var default_amount: float = get_default_amount_for_resource(resource_type)
	if default_amount <= 0.0:
		return 0.0

	var key: String = _make_key(cell, resource_type)
	if not changed_cells.has(key):
		return default_amount

	var record: Dictionary = _get_record(key)
	return clampf(float(record.get("remaining_amount", default_amount)), 0.0, default_amount)


func set_remaining_amount(cell: Vector2i, resource_type: StringName, remaining_amount: float) -> void:
	var default_amount: float = get_default_amount_for_resource(resource_type)
	if default_amount <= 0.0:
		return

	var clamped_amount: float = clampf(remaining_amount, 0.0, default_amount)
	var key: String = _make_key(cell, resource_type)
	if clamped_amount >= default_amount:
		changed_cells.erase(key)
		return

	changed_cells[key] = {
		"cell": cell,
		"resource_type": str(resource_type),
		"remaining_amount": clamped_amount,
		"depleted": clamped_amount <= 0,
	}


func consume(cell: Vector2i, resource_type: StringName, requested_amount: float) -> float:
	if requested_amount <= 0.0:
		return 0.0

	var current_amount: float = get_remaining_amount(cell, resource_type)
	if current_amount <= 0.0:
		return 0.0

	var consumed_amount: float = minf(requested_amount, current_amount)
	set_remaining_amount(cell, resource_type, current_amount - consumed_amount)
	return consumed_amount


func is_depleted(cell: Vector2i, resource_type: StringName) -> bool:
	return get_remaining_amount(cell, resource_type) <= 0.0


func get_changed_cell_count() -> int:
	return changed_cells.size()


func get_total_remaining_amount(cells: Array, resource_type: StringName) -> float:
	var total_amount: float = 0.0
	for cell_variant in cells:
		if typeof(cell_variant) != TYPE_VECTOR2I:
			continue
		var cell: Vector2i = cell_variant
		total_amount += get_remaining_amount(cell, resource_type)
	return total_amount


func consume_from_cells(cells: Array, resource_type: StringName, requested_amount: float) -> float:
	if requested_amount <= 0.0:
		return 0.0

	var remaining_request: float = requested_amount
	var consumed_total: float = 0.0
	for cell_variant in cells:
		if remaining_request <= 0.0:
			break
		if typeof(cell_variant) != TYPE_VECTOR2I:
			continue

		var cell: Vector2i = cell_variant
		var consumed_amount: float = consume(cell, resource_type, remaining_request)
		if consumed_amount <= 0.0:
			continue
		consumed_total += consumed_amount
		remaining_request -= consumed_amount
	return consumed_total


func export_changed_cells() -> Array:
	var result: Array = []
	for key_variant in changed_cells.keys():
		var key: String = str(key_variant)
		var record: Dictionary = _get_record(key)
		if record.is_empty():
			continue

		var cell: Vector2i = _read_cell(record)
		var resource_type: String = str(record.get("resource_type", ""))
		var remaining_amount: float = float(record.get("remaining_amount", 0.0))
		result.append({
			"x": cell.x,
			"y": cell.y,
			"resource_type": resource_type,
			"remaining_amount": remaining_amount,
			"depleted": remaining_amount <= 0,
		})
	return result


func import_changed_cells(saved_cells: Array) -> void:
	changed_cells.clear()
	for entry_variant in saved_cells:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue

		var entry: Dictionary = entry_variant
		var cell: Vector2i = _read_cell(entry)
		var resource_type: StringName = StringName(str(entry.get("resource_type", "")))
		var default_amount: float = get_default_amount_for_resource(resource_type)
		var remaining_amount: float = float(entry.get("remaining_amount", default_amount))
		set_remaining_amount(cell, resource_type, remaining_amount)


func to_save_data() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"default_wood_per_cell": default_wood_per_cell,
		"default_stone_per_cell": default_stone_per_cell,
		"changed_cells": export_changed_cells(),
	}


func load_save_data(save_data: Dictionary) -> void:
	changed_cells.clear()
	if save_data.is_empty():
		return

	default_wood_per_cell = maxf(0.0, float(save_data.get("default_wood_per_cell", DEFAULT_WOOD_PER_CELL)))
	default_stone_per_cell = maxf(0.0, float(save_data.get("default_stone_per_cell", DEFAULT_STONE_PER_CELL)))

	var changed_cells_variant: Variant = save_data.get("changed_cells", [])
	if typeof(changed_cells_variant) == TYPE_ARRAY:
		var saved_cells: Array = changed_cells_variant
		import_changed_cells(saved_cells)


func _get_record(key: String) -> Dictionary:
	var record_variant: Variant = changed_cells.get(key, {})
	if typeof(record_variant) != TYPE_DICTIONARY:
		return {}
	return record_variant


func _read_cell(record: Dictionary) -> Vector2i:
	var cell_variant: Variant = record.get("cell", null)
	if typeof(cell_variant) == TYPE_VECTOR2I:
		return cell_variant

	var x: int = int(record.get("x", 0))
	var y: int = int(record.get("y", 0))
	return Vector2i(x, y)


func _make_key(cell: Vector2i, resource_type: StringName) -> String:
	return "%d,%d,%s" % [cell.x, cell.y, str(resource_type)]
