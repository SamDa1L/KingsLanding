@tool
extends Area2D

@export var hover_size: Vector2 = Vector2(96, 80)
@export var show_editor_preview: bool = true
@export var preview_color: Color = Color(1.0, 0.88, 0.24, 0.85)
@export var preview_width: float = 2.0

var _last_hover_size: Vector2 = Vector2.ZERO
var _last_show_editor_preview: bool = false
var _last_preview_color: Color = Color(-1.0, -1.0, -1.0, -1.0)
var _last_preview_width: float = -1.0


func _enter_tree() -> void:
	set_process(Engine.is_editor_hint())


func _ready() -> void:
	input_pickable = true
	collision_layer = 2
	collision_mask = 0
	_sync_hover_area()


func _process(_delta: float) -> void:
	if _has_settings_changed():
		_sync_hover_area()


func _has_settings_changed() -> bool:
	return hover_size != _last_hover_size or show_editor_preview != _last_show_editor_preview or preview_color != _last_preview_color or not is_equal_approx(preview_width, _last_preview_width)


func _sync_hover_area() -> void:
	_last_hover_size = hover_size
	_last_show_editor_preview = show_editor_preview
	_last_preview_color = preview_color
	_last_preview_width = preview_width

	var clamped_size := Vector2(max(hover_size.x, 1.0), max(hover_size.y, 1.0))
	var collision_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape != null:
		var rectangle_shape := collision_shape.shape as RectangleShape2D
		if rectangle_shape == null:
			rectangle_shape = RectangleShape2D.new()
			collision_shape.shape = rectangle_shape
		rectangle_shape.size = clamped_size

	var hover_preview := get_node_or_null("HoverPreview") as Line2D
	if hover_preview == null:
		return

	var half_size := clamped_size * 0.5
	hover_preview.points = PackedVector2Array([
		Vector2(-half_size.x, -half_size.y),
		Vector2(half_size.x, -half_size.y),
		Vector2(half_size.x, half_size.y),
		Vector2(-half_size.x, half_size.y),
		Vector2(-half_size.x, -half_size.y),
	])
	hover_preview.default_color = preview_color
	hover_preview.width = preview_width
	hover_preview.visible = Engine.is_editor_hint() and show_editor_preview
