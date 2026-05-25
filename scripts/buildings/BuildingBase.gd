extends Area2D

signal building_selected(building_info: Dictionary)
signal resource_collected(building_name: String, resource_type: StringName, amount: int)
signal storage_changed(building_name: String, stored_amount: int, capacity: int)

const SECONDS_PER_GAME_MINUTE := 10.0

@export var display_name: String = "Building"
@export var fill_color: Color = Color(0.55, 0.43, 0.28, 1.0)
@export var label_offset_y: float = 34.0
@export var interaction_size: Vector2 = Vector2(96, 80)
@export var is_production_building: bool = false
@export var resource_type: StringName = &""
@export var production_per_minute: float = 0.0
@export var storage_capacity: int = 10

@onready var selection_outline: Polygon2D = $SelectionOutline
@onready var visual: CanvasItem = $Visual
@onready var label: Label = $Label
@onready var interaction_shape: CollisionShape2D = $InteractionShape
@onready var storage_label: Label = $StorageLabel
@onready var ready_indicator: Polygon2D = $ReadyIndicator

var stored_amount: int = 0
var _production_progress: float = 0.0
var _resource_inventory: Node = null


func _ready() -> void:
	_apply_visual_color()
	label.text = display_name
	label.position.y = label_offset_y
	if interaction_shape.shape is RectangleShape2D:
		(interaction_shape.shape as RectangleShape2D).size = interaction_size

	if has_node("/root/ResourceInventory"):
		_resource_inventory = get_node("/root/ResourceInventory")

	_update_feedback()


func _apply_visual_color() -> void:
	if visual == null:
		return
	if visual is Polygon2D:
		(visual as Polygon2D).color = fill_color
	else:
		visual.modulate = fill_color


func _process(delta: float) -> void:
	if not is_production_building:
		return
	if resource_type == &"":
		return
	if stored_amount >= storage_capacity:
		return

	_production_progress += production_per_minute * _get_scaled_game_minutes(delta)
	var produced_amount := int(_production_progress)
	if produced_amount <= 0:
		return

	_production_progress -= produced_amount
	stored_amount = min(stored_amount + produced_amount, storage_capacity)
	storage_changed.emit(display_name, stored_amount, storage_capacity)
	_update_feedback()


func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			building_selected.emit(get_building_info())
			_collect_stored_resource()


func configure_production(next_resource_type: StringName, next_rate: float, next_capacity: int) -> void:
	resource_type = next_resource_type
	production_per_minute = next_rate
	storage_capacity = next_capacity
	is_production_building = resource_type != &"" and production_per_minute > 0.0 and storage_capacity > 0
	_update_feedback()


func _get_scaled_game_minutes(delta: float) -> float:
	if has_node("/root/GameClock"):
		var game_clock := get_node("/root/GameClock")
		if game_clock.has_method("get_scaled_delta"):
			return float(game_clock.call("get_scaled_delta", delta)) / SECONDS_PER_GAME_MINUTE
	return delta / SECONDS_PER_GAME_MINUTE


func set_selected(value: bool) -> void:
	selection_outline.visible = value


func get_building_info() -> Dictionary:
	return {
		"name": display_name,
		"node_name": name,
		"is_production": is_production_building,
		"resource_type": resource_type,
		"resource_label": _get_resource_label(resource_type),
		"stored_amount": stored_amount,
		"capacity": storage_capacity,
		"rate_per_minute": production_per_minute,
		"status": _get_status_text(),
	}


func _collect_stored_resource() -> void:
	if not is_production_building:
		return
	if stored_amount <= 0:
		return
	if _resource_inventory == null:
		push_warning("ResourceInventory autoload is not available.")
		return

	var collected_amount := stored_amount
	stored_amount = 0
	_production_progress = 0.0
	_resource_inventory.call("add_resource", resource_type, collected_amount)
	resource_collected.emit(display_name, resource_type, collected_amount)
	storage_changed.emit(display_name, stored_amount, storage_capacity)
	_update_feedback()


func _update_feedback() -> void:
	if not is_node_ready():
		return

	ready_indicator.visible = is_production_building and stored_amount > 0
	storage_label.visible = is_production_building

	if not is_production_building:
		storage_label.text = ""
		return

	var resource_label := _get_resource_label(resource_type)
	storage_label.text = "%s %d/%d" % [resource_label, stored_amount, storage_capacity]

	if stored_amount >= storage_capacity:
		storage_label.modulate = Color(1.0, 0.78, 0.25, 1.0)
	elif stored_amount > 0:
		storage_label.modulate = Color(0.75, 1.0, 0.65, 1.0)
	else:
		storage_label.modulate = Color(1.0, 1.0, 1.0, 1.0)


func _get_status_text() -> String:
	if not is_production_building:
		return "Support building"
	if stored_amount >= storage_capacity:
		return "Storage full"
	if stored_amount > 0:
		return "Ready to collect"
	return "Producing"


func _get_resource_label(next_resource_type: StringName) -> String:
	match next_resource_type:
		&"food":
			return "Food"
		&"wood":
			return "Wood"
		&"stone":
			return "Stone"
		_:
			return "None"