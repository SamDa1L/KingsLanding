class_name GroundRule
extends Resource


@export var rule_name: String = ""
@export_enum("plain", "water") var ground_type: String = "plain"
@export_enum("top", "bottom", "left", "right", "center") var ground_zone: String = "center"
@export_enum("TL", "T", "TR", "L", "M", "R", "BL", "BM", "BR") var ground_role: String = "M"
@export_enum("none", "W", "P") var connector: String = "none"

@export_enum("plain", "plain_edge_top", "plain_edge_right", "plain_edge_bottom", "plain_edge_left", "plain_edge_top_water", "plain_edge_right_water", "plain_edge_bottom_water", "plain_edge_left_water", "water", "water_edge_top", "water_edge_right", "water_edge_bottom", "water_edge_left", "plain_water", "outer") var top_tag: String = "plain"
@export_enum("plain", "plain_edge_top", "plain_edge_right", "plain_edge_bottom", "plain_edge_left", "plain_edge_top_water", "plain_edge_right_water", "plain_edge_bottom_water", "plain_edge_left_water", "water", "water_edge_top", "water_edge_right", "water_edge_bottom", "water_edge_left", "plain_water", "outer") var right_tag: String = "plain"
@export_enum("plain", "plain_edge_top", "plain_edge_right", "plain_edge_bottom", "plain_edge_left", "plain_edge_top_water", "plain_edge_right_water", "plain_edge_bottom_water", "plain_edge_left_water", "water", "water_edge_top", "water_edge_right", "water_edge_bottom", "water_edge_left", "plain_water", "outer") var bottom_tag: String = "plain"
@export_enum("plain", "plain_edge_top", "plain_edge_right", "plain_edge_bottom", "plain_edge_left", "plain_edge_top_water", "plain_edge_right_water", "plain_edge_bottom_water", "plain_edge_left_water", "water", "water_edge_top", "water_edge_right", "water_edge_bottom", "water_edge_left", "plain_water", "outer") var left_tag: String = "plain"

@export_enum("grass_plain", "sand_plain") var visual_theme: String = "grass_plain"
@export var variant_index: int = 1

@export var buildable: bool = true
@export var passable: bool = true
@export var weight: float = 1.0

@export_group("Tile Binding")
@export var tile_set: TileSet
@export var tile_source_id: int = -1
@export var tile_atlas_coords: Vector2i = Vector2i(-1, -1)
@export var tile_alternative: int = 0


func get_edge_tag(direction: Vector2i) -> StringName:
	if direction == Vector2i.UP:
		return StringName(top_tag)
	if direction == Vector2i.RIGHT:
		return StringName(right_tag)
	if direction == Vector2i.DOWN:
		return StringName(bottom_tag)
	if direction == Vector2i.LEFT:
		return StringName(left_tag)
	return &""


func has_valid_tile_binding() -> bool:
	return tile_set != null and tile_source_id >= 0 and tile_atlas_coords.x >= 0 and tile_atlas_coords.y >= 0


func get_logic_key() -> String:
	return "%s_%s_%s_%d" % [
		ground_type,
		ground_role,
		connector,
		variant_index,
	]
