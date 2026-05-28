class_name MapCellData
extends RefCounted


var cell: Vector2i = Vector2i.ZERO

var ground_type: StringName = &"plain"
var ground_zone: StringName = &"center"
var ground_role: StringName = &"M"
var connector: StringName = &"none"

var top_tag: StringName = &"plain"
var right_tag: StringName = &"plain"
var bottom_tag: StringName = &"plain"
var left_tag: StringName = &"plain"

var visual_theme: StringName = &"grass_plain"
var variant_index: int = 1

var buildable: bool = true
var passable: bool = true

var resource_type: StringName = &"none"
var resource_patch_id: int = -1
var harvestable: bool = false


func _init() -> void:
	reset()


func reset() -> void:
	cell = Vector2i.ZERO
	ground_type = &"plain"
	ground_zone = &"center"
	ground_role = &"M"
	connector = &"none"
	top_tag = &"plain"
	right_tag = &"plain"
	bottom_tag = &"plain"
	left_tag = &"plain"
	visual_theme = &"grass_plain"
	variant_index = 1
	buildable = true
	passable = true
	resource_type = &"none"
	resource_patch_id = -1
	harvestable = false


func apply_ground_cell_data(ground_cell_data: GroundCellData) -> void:
	if ground_cell_data == null:
		return
	cell = ground_cell_data.cell
	ground_type = ground_cell_data.ground_type
	ground_zone = ground_cell_data.ground_zone
	ground_role = ground_cell_data.ground_role
	connector = ground_cell_data.connector
	top_tag = ground_cell_data.top_tag
	right_tag = ground_cell_data.right_tag
	bottom_tag = ground_cell_data.bottom_tag
	left_tag = ground_cell_data.left_tag
	visual_theme = ground_cell_data.visual_theme
	variant_index = ground_cell_data.variant_index
	buildable = ground_cell_data.buildable
	passable = ground_cell_data.passable


func set_resource_data(next_resource_type: StringName, next_resource_patch_id: int, next_harvestable: bool) -> void:
	resource_type = next_resource_type
	resource_patch_id = next_resource_patch_id
	harvestable = next_harvestable


func clear_resource_data() -> void:
	resource_type = &"none"
	resource_patch_id = -1
	harvestable = false


func get_edge_tag(direction: Vector2i) -> StringName:
	if direction == Vector2i.UP:
		return top_tag
	if direction == Vector2i.RIGHT:
		return right_tag
	if direction == Vector2i.DOWN:
		return bottom_tag
	if direction == Vector2i.LEFT:
		return left_tag
	return &""


func to_dictionary() -> Dictionary:
	return {
		"cell": cell,
		"ground_type": ground_type,
		"ground_zone": ground_zone,
		"ground_role": ground_role,
		"connector": connector,
		"top_tag": top_tag,
		"right_tag": right_tag,
		"bottom_tag": bottom_tag,
		"left_tag": left_tag,
		"visual_theme": visual_theme,
		"variant_index": variant_index,
		"buildable": buildable,
		"passable": passable,
		"resource_type": resource_type,
		"resource_patch_id": resource_patch_id,
		"harvestable": harvestable,
	}
