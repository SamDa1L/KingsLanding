class_name GroundCellData
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


func setup(next_cell: Vector2i, rule: GroundRule) -> void:
	cell = next_cell
	if rule == null:
		return
	apply_rule(rule)


func apply_rule(rule: GroundRule) -> void:
	if rule == null:
		return
	ground_type = rule.ground_type
	ground_zone = rule.ground_zone
	ground_role = rule.ground_role
	connector = rule.connector
	top_tag = rule.top_tag
	right_tag = rule.right_tag
	bottom_tag = rule.bottom_tag
	left_tag = rule.left_tag
	visual_theme = rule.visual_theme
	variant_index = rule.variant_index
	buildable = rule.buildable
	passable = rule.passable


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
	}
