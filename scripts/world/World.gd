extends Node2D

const VILLAGER_SCENE := preload("res://scenes/characters/villagersPawn/Pawn.tscn")
const BUILDING_SCENE := preload("res://scenes/buildings/BuildingBase.tscn")

const BUILDING_DEFINITIONS: Array[Dictionary] = [
	{"name": "Castle", "position": Vector2(0, 0), "color": Color(0.44, 0.44, 0.50, 1.0), "label": "城堡", "size": Vector2(120, 104)},
	{"name": "HouseA", "position": Vector2(-220, 112), "color": Color(0.60, 0.38, 0.22, 1.0), "label": "住宅", "size": Vector2(86, 74)},
	{"name": "HouseB", "position": Vector2(-280, 38), "color": Color(0.62, 0.39, 0.24, 1.0), "label": "住宅", "size": Vector2(86, 74)},
	{"name": "HouseC", "position": Vector2(-150, 44), "color": Color(0.58, 0.36, 0.21, 1.0), "label": "住宅", "size": Vector2(86, 74)},
	{"name": "Farm", "position": Vector2(340, 120), "color": Color(0.76, 0.62, 0.25, 1.0), "label": "农场", "size": Vector2(110, 88), "resource": &"food", "rate": 0.45, "capacity": 12},
	{"name": "LumberCamp", "position": Vector2(-330, -135), "color": Color(0.12, 0.39, 0.16, 1.0), "label": "伐木场", "size": Vector2(104, 82), "resource": &"wood", "rate": 0.35, "capacity": 10},
	{"name": "Quarry", "position": Vector2(330, -135), "color": Color(0.45, 0.45, 0.45, 1.0), "label": "采石场", "size": Vector2(104, 82), "resource": &"stone", "rate": 0.25, "capacity": 8},
	{"name": "Warehouse", "position": Vector2(0, 210), "color": Color(0.50, 0.33, 0.20, 1.0), "label": "仓库", "size": Vector2(110, 82)},
]

const VILLAGER_ROUTE_DEFINITIONS: Array[Dictionary] = [
	{"name": "VillagerFarm", "home": "HouseA", "work": "Farm", "start_delay": 0.0},
	{"name": "VillagerLumber", "home": "HouseB", "work": "LumberCamp", "start_delay": 1.2},
	{"name": "VillagerQuarry", "home": "HouseC", "work": "Quarry", "start_delay": 2.4},
]

const HOME_EXIT_OFFSET := Vector2(0, 40)
const WORK_ENTRY_OFFSET := Vector2(0, 36)

@onready var hud: CanvasLayer = $UIRoot/Hud
@onready var main_camera: Camera2D = $MainCamera
@onready var villager_root: Node2D = $VillagerRoot
@onready var building_root: Node2D = $BuildingRoot

var _game_clock: Node = null
var _resource_inventory: Node = null
var _building_positions: Dictionary = {}
var _selected_building: Node = null
var _villager_states: Dictionary = {}


func _ready() -> void:
	main_camera.make_current()
	_bind_resource_inventory()
	_spawn_buildings()
	_spawn_villagers()
	_bind_game_clock()
	_update_villager_hud()


func _bind_resource_inventory() -> void:
	if not has_node("/root/ResourceInventory"):
		push_warning("ResourceInventory 自动加载未启用。")
		return

	_resource_inventory = get_node("/root/ResourceInventory")
	if _resource_inventory.has_signal("inventory_changed"):
		_resource_inventory.connect("inventory_changed", Callable(self, "_on_inventory_changed"))
		_on_inventory_changed(_resource_inventory.call("get_all_resources"))


func _bind_game_clock() -> void:
	if not has_node("/root/GameClock"):
		push_warning("GameClock 自动加载未启用。")
		return

	_game_clock = get_node("/root/GameClock")
	if not _game_clock.has_signal("time_changed"):
		push_warning("GameClock 存在，但缺少 time_changed 信号。")
		return

	_game_clock.connect("time_changed", Callable(self, "_on_time_changed"))
	_on_time_changed(str(_game_clock.call("get_time_text")))


func _spawn_buildings() -> void:
	for definition in BUILDING_DEFINITIONS:
		var building := BUILDING_SCENE.instantiate() as Area2D
		building.name = definition["name"]
		building.position = definition["position"]
		building.set("display_name", definition["label"])
		building.set("fill_color", definition["color"])
		building.set("interaction_size", definition["size"])
		building_root.add_child(building)
		_building_positions[definition["name"]] = definition["position"]
		_connect_building_feedback(building)

		if definition.has("resource"):
			building.call("configure_production", definition["resource"], float(definition["rate"]), int(definition["capacity"]))


func _connect_building_feedback(building: Node) -> void:
	if building.has_signal("building_selected"):
		building.connect("building_selected", Callable(self, "_on_building_selected").bind(building))
	if building.has_signal("resource_collected"):
		building.connect("resource_collected", Callable(self, "_on_resource_collected"))
	if building.has_signal("storage_changed"):
		building.connect("storage_changed", Callable(self, "_on_building_storage_changed").bind(building))


func _spawn_villagers() -> void:
	for definition in VILLAGER_ROUTE_DEFINITIONS:
		_spawn_villager(definition)


func _spawn_villager(definition: Dictionary) -> void:
	var home_position := _get_building_position(str(definition["home"])) + HOME_EXIT_OFFSET
	var work_position := _get_building_position(str(definition["work"])) + WORK_ENTRY_OFFSET
	var start_delay := float(definition.get("start_delay", 0.0))

	var villager := VILLAGER_SCENE.instantiate() as Node2D
	villager.name = str(definition["name"])
	villager_root.add_child(villager)
	if villager.has_signal("state_changed"):
		villager.connect("state_changed", Callable(self, "_on_villager_state_changed"))
	villager.call("setup_route", home_position, work_position, start_delay)
	_villager_states[villager] = villager.call("get_state_name")


func _get_building_position(building_name: String) -> Vector2:
	if _building_positions.has(building_name):
		return _building_positions[building_name]

	push_warning("缺少建筑位置：%s。" % building_name)
	return Vector2.ZERO


func _set_selected_building(building: Node) -> void:
	if _selected_building != null and is_instance_valid(_selected_building) and _selected_building.has_method("set_selected"):
		_selected_building.call("set_selected", false)

	_selected_building = building
	if _selected_building != null and _selected_building.has_method("set_selected"):
		_selected_building.call("set_selected", true)
	if _selected_building != null and _selected_building.has_method("get_building_info"):
		hud.call("set_selected_building", _selected_building.call("get_building_info"))


func _update_selected_building_panel(building: Node) -> void:
	if _selected_building == building and building.has_method("get_building_info"):
		hud.call("set_selected_building", building.call("get_building_info"))


func _update_villager_hud() -> void:
	var counts: Dictionary = {
		&"idle": 0,
		&"moving": 0,
		&"working": 0,
	}

	for state_name in _villager_states.values():
		if counts.has(state_name):
			counts[state_name] += 1

	hud.call("set_villager_counts", counts)


func _on_time_changed(time_text: String) -> void:
	hud.call("set_time_text", time_text)


func _on_inventory_changed(resources: Dictionary) -> void:
	hud.call("set_resources", resources)


func _on_building_selected(building_info: Dictionary, building: Node) -> void:
	_set_selected_building(building)
	if bool(building_info.get("is_production", false)):
		hud.call("show_message", "%s 已选中。产出后再次点击即可领取。" % str(building_info.get("name", "建筑")))
	else:
		hud.call("show_message", "%s 已选中。" % str(building_info.get("name", "建筑")))


func _on_resource_collected(building_name: String, resource_type: StringName, amount: int) -> void:
	hud.call("show_message", "已从%s领取 %d%s。" % [building_name, amount, _get_resource_label(resource_type)])


func _on_building_storage_changed(_building_name: String, _stored_amount: int, _capacity: int, building: Node) -> void:
	_update_selected_building_panel(building)


func _on_villager_state_changed(villager: Node2D, state_name: StringName) -> void:
	_villager_states[villager] = state_name
	_update_villager_hud()


func _get_resource_label(resource_type: StringName) -> String:
	match resource_type:
		&"food":
			return "食物"
		&"wood":
			return "木材"
		&"stone":
			return "石料"
		_:
			return "资源"
