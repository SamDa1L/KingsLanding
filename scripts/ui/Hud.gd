extends CanvasLayer

@onready var time_display: Label = $TimeDisplay
@onready var resource_label: Label = $ResourcePanel/ResourceLabel
@onready var villager_label: Label = $VillagerPanel/VillagerLabel
@onready var building_label: Label = $BuildingPanel/BuildingLabel
@onready var message_label: Label = $MessagePanel/MessageLabel

var _message_timer: float = 0.0


func _process(delta: float) -> void:
	if _message_timer <= 0.0:
		return

	_message_timer -= delta
	if _message_timer <= 0.0:
		message_label.text = "Territory running. Click buildings to collect."


func set_time_text(time_text: String) -> void:
	time_display.text = time_text


func set_resources(resources: Dictionary) -> void:
	var food := _get_resource_amount(resources, &"food")
	var wood := _get_resource_amount(resources, &"wood")
	var stone := _get_resource_amount(resources, &"stone")
	var gold := _get_resource_amount(resources, &"gold")
	resource_label.text = "Food %d   Wood %d   Stone %d   Gold %d" % [food, wood, stone, gold]


func set_villager_counts(counts: Dictionary) -> void:
	var idle := int(counts.get(&"idle", 0))
	var moving := int(counts.get(&"moving", 0))
	var working := int(counts.get(&"working", 0))
	villager_label.text = "Villagers Idle %d   Moving %d   Working %d" % [idle, moving, working]


func set_selected_building(building_info: Dictionary) -> void:
	var building_name := str(building_info.get("name", "None"))
	var status := str(building_info.get("status", "Unknown"))
	var resource_label_text := str(building_info.get("resource_label", "None"))
	var stored := int(building_info.get("stored_amount", 0))
	var capacity := int(building_info.get("capacity", 0))
	var rate := float(building_info.get("rate_per_minute", 0.0))

	if bool(building_info.get("is_production", false)):
		building_label.text = "%s\n%s %d/%d   +%.2f/min\n%s" % [building_name, resource_label_text, stored, capacity, rate, status]
	else:
		building_label.text = "%s\nSupport building\n%s" % [building_name, status]


func show_message(message: String, duration: float = 2.4) -> void:
	message_label.text = message
	_message_timer = duration


func _get_resource_amount(resources: Dictionary, resource_type: StringName) -> int:
	if resources.has(resource_type):
		return int(resources[resource_type])
	if resources.has(str(resource_type)):
		return int(resources[str(resource_type)])
	return 0
