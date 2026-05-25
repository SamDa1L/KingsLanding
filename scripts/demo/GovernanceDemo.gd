extends Node2D

const DemoMapReaderScript := preload("res://scripts/demo/DemoMapReader.gd")
const ResourceRegionScannerScript := preload("res://scripts/map/ResourceRegionScanner.gd")
const InitialBuildingSpawnerScript := preload("res://scripts/buildings/InitialBuildingSpawner.gd")
const BuildingPlacementControllerScript := preload("res://scripts/placement/BuildingPlacementController.gd")
const ProductionCalculatorScript := preload("res://scripts/economy/ProductionCalculator.gd")
const GovernanceStateScript := preload("res://scripts/governance/GovernanceState.gd")
const TaxSystemScript := preload("res://scripts/governance/TaxSystem.gd")
const HappinessSystemScript := preload("res://scripts/governance/HappinessSystem.gd")
const RiotSystemScript := preload("res://scripts/governance/RiotSystem.gd")
const VictoryDefeatSystemScript := preload("res://scripts/governance/VictoryDefeatSystem.gd")
const VILLAGER_SCENE := preload("res://scenes/characters/villagersPawn/Pawn.tscn")

const CASTLE_SCENE := preload("res://scenes/buildings/Castle/Castle.tscn")
const LUMBER_CAMP_SCENE := preload("res://scenes/buildings/TreeHouse/TreeLoggingHouse.tscn")
const QUARRY_SCENE := preload("res://scenes/buildings/StoneHouse/StoneQuarry.tscn")
const FARM_SCENE := preload("res://scenes/buildings/Farm/Farm.tscn")
const HOUSE_SCENE := preload("res://scenes/buildings/House/PawnHouse.tscn")
const INITIAL_BUILDING_SEED := 20260523
const HOME_EXIT_OFFSET := Vector2(0, 40)
const WORK_ENTRY_OFFSET := Vector2(0, 36)
const VILLAGER_START_DELAY_STEP := 1.2
const PLACEMENT_PREVIEW_SIZE := Vector2(56, 56)
const PLACEMENT_VALID_COLOR := Color(0.2, 0.95, 0.3, 0.42)
const PLACEMENT_INVALID_COLOR := Color(1.0, 0.18, 0.12, 0.42)
const HOUSE_POPULATION_CAPACITY := 5
const CAMERA_MIN_ZOOM := 1.0
const CAMERA_MAX_ZOOM := 2.0
const CAMERA_ZOOM_STEP := 0.125
const GAME_WORLD_VIEWPORT_RIGHT := 922.0
const GAME_WORLD_VIEWPORT_BOTTOM := 720.0

@onready var ground_layer: TileMapLayer = $MapRoot/GroundLayer
@onready var resource_layer: TileMapLayer = $MapRoot/ResourceLayer
@onready var decor_layer: TileMapLayer = $MapRoot/DecorLayer
@onready var buildings_root: Node2D = $BuildingsRoot
@onready var characters_root: Node2D = $CharactersRoot
@onready var placement_overlay: Node2D = $PlacementOverlay
@onready var placement_preview: Polygon2D = $PlacementOverlay/PreviewNode
@onready var hover_hint_label: Label = $PlacementOverlay/HoverHintLabel
@onready var population_label: Label = $UIRoot/TopResourceBar/HBoxContainer/PopulationLabel
@onready var population_cap_label: Label = $UIRoot/TopResourceBar/HBoxContainer/PopulationCapLabel
@onready var gold_label: Label = $UIRoot/TopResourceBar/HBoxContainer/GoldLabel
@onready var food_label: Label = $UIRoot/TopResourceBar/HBoxContainer/FoodLabel
@onready var wood_label: Label = $UIRoot/TopResourceBar/HBoxContainer/WoodLabel
@onready var stone_label: Label = $UIRoot/TopResourceBar/HBoxContainer/StoneLabel
@onready var placement_panel: PanelContainer = $UIRoot/PlacementPanel
@onready var farm_button: Button = $UIRoot/PlacementPanel/VBoxContainer/GridContainer/FarmButton
@onready var lumber_camp_button: Button = $UIRoot/PlacementPanel/VBoxContainer/GridContainer/LumberCampButton
@onready var quarry_button: Button = $UIRoot/PlacementPanel/VBoxContainer/GridContainer/QuarryButton
@onready var house_button: Button = $UIRoot/PlacementPanel/VBoxContainer/GridContainer/HouseButton
@onready var cancel_placement_button: Button = $UIRoot/PlacementPanel/VBoxContainer/CancelButton
@onready var placement_status_label: Label = $UIRoot/PlacementPanel/VBoxContainer/StatusLabel
@onready var economy_status_label: Label = $UIRoot/EconomyPanel/VBoxContainer/EconomyStatusLabel
@onready var speed_button: Button = $UIRoot/TimeControlPanel/VBoxContainer/HBoxContainer/SpeedButton
@onready var pause_button: Button = $UIRoot/TimeControlPanel/VBoxContainer/HBoxContainer/PauseButton
@onready var time_control_status_label: Label = $UIRoot/TimeControlPanel/VBoxContainer/TimeControlStatusLabel
@onready var tax_policy_button: Button = $UIRoot/TaxPanel/VBoxContainer/TaxPolicyButton
@onready var tax_status_label: Label = $UIRoot/TaxPanel/VBoxContainer/TaxStatusLabel
@onready var happiness_status_label: Label = $UIRoot/HappinessPanel/VBoxContainer/HappinessStatusLabel
@onready var riot_status_label: Label = $UIRoot/RiotPanel/VBoxContainer/RiotStatusLabel
@onready var victory_status_label: Label = $UIRoot/VictoryPanel/VBoxContainer/VictoryStatusLabel
@onready var hud_status_label: Label = $UIRoot/HudPanel/VBoxContainer/HudStatusLabel
@onready var event_log_label: Label = $UIRoot/HudPanel/VBoxContainer/EventLogLabel
@onready var top_resource_bar: PanelContainer = $UIRoot/TopResourceBar
@onready var time_control_panel: PanelContainer = $UIRoot/TimeControlPanel
@onready var tax_panel: PanelContainer = $UIRoot/TaxPanel
@onready var happiness_panel: PanelContainer = $UIRoot/HappinessPanel
@onready var main_camera: Camera2D = $MainCamera

var grid: RefCounted
var map_read_result: Dictionary = {}
var resource_regions: Dictionary = {}
var farmable_regions: Array = []
var initial_buildings: Array = []
var villager_states: Dictionary = {}
var occupied_cells: Dictionary = {}
var placement_controller: RefCounted = null
var production_calculator: RefCounted = null
var governance_state: RefCounted = null
var resource_inventory: Node = null
var game_clock: Node = null
var tax_system: RefCounted = null
var happiness_system: RefCounted = null
var riot_system: RefCounted = null
var victory_defeat_system: RefCounted = null
var last_minute_delta: Dictionary = {}
var last_tax_message: String = ""
var last_happiness_message: String = ""
var last_happiness_report: Dictionary = {}
var last_riot_message: String = ""
var last_riot_report: Dictionary = {}
var last_victory_defeat_report: Dictionary = {}
var event_log_messages: Array[String] = []
var last_daily_happiness_delta: float = 0.0
var last_tax_day_index: int = -1
var placement_mode_active: bool = false
var selected_building_type: int = -1
var hovered_cell: Vector2i = Vector2i(-1, -1)
var hovered_result: RefCounted = null
var last_placement_message: String = ""
var selected_building_data: RefCounted = null
var selected_building_node: Node2D = null
var last_collection_message: String = ""
var is_camera_dragging: bool = false
var camera_drag_last_mouse: Vector2 = Vector2.ZERO


func _ready() -> void:
	_setup_economy_systems()
	_read_demo_map()
	_setup_placement_overlay()
	_setup_placement_ui()
	_setup_economy_ui()
	_setup_time_control_ui()
	_setup_tax_ui()
	_setup_happiness_ui()
	_setup_riot_ui()
	_setup_victory_ui()
	if main_camera != null:
		main_camera.make_current()
	_update_placement_overlay()
	_update_economy_ui()
	_update_stage14_hud()
	_apply_ui_layout()


func _apply_ui_layout() -> void:
	if not is_inside_tree():
		return
	var viewport_size := get_viewport_rect().size
	if main_camera != null:
		main_camera.make_current()
	if top_resource_bar != null:
		top_resource_bar.offset_left = 16.0
		top_resource_bar.offset_top = 16.0
		top_resource_bar.offset_right = max(GAME_WORLD_VIEWPORT_RIGHT - 16.0, viewport_size.x - 372.0)
		top_resource_bar.offset_bottom = 50.0
	if time_control_panel != null:
		time_control_panel.anchor_left = 1.0
		time_control_panel.anchor_right = 1.0
		time_control_panel.offset_left = -352.0
		time_control_panel.offset_right = -16.0
		time_control_panel.offset_top = 16.0
		time_control_panel.offset_bottom = 112.0
	if tax_panel != null:
		tax_panel.anchor_left = 1.0
		tax_panel.anchor_right = 1.0
		tax_panel.offset_left = -352.0
		tax_panel.offset_right = -16.0
		tax_panel.offset_top = 124.0
		tax_panel.offset_bottom = 224.0
	if happiness_panel != null:
		happiness_panel.anchor_left = 1.0
		happiness_panel.anchor_right = 1.0
		happiness_panel.offset_left = -352.0
		happiness_panel.offset_right = -16.0
		happiness_panel.offset_top = 236.0
		happiness_panel.offset_bottom = 424.0
	if placement_panel != null:
		placement_panel.anchor_left = 1.0
		placement_panel.anchor_right = 1.0
		placement_panel.offset_left = -352.0
		placement_panel.offset_right = -16.0
		placement_panel.offset_top = viewport_size.y - 284.0
		placement_panel.offset_bottom = viewport_size.y - 16.0
	if speed_button != null:
		speed_button.custom_minimum_size = Vector2(136, 40)
	if pause_button != null:
		pause_button.custom_minimum_size = Vector2(96, 40)
	if time_control_status_label != null:
		time_control_status_label.custom_minimum_size = Vector2(304, 48)
	if tax_policy_button != null:
		tax_policy_button.custom_minimum_size = Vector2(0, 0)
	if tax_status_label != null:
		tax_status_label.custom_minimum_size = Vector2(304, 68)
	if happiness_status_label != null:
		happiness_status_label.custom_minimum_size = Vector2(304, 172)
	if placement_status_label != null:
		placement_status_label.custom_minimum_size = Vector2(304, 42)
	if cancel_placement_button != null:
		cancel_placement_button.custom_minimum_size = Vector2(0, 0)
	if farm_button != null:
		farm_button.custom_minimum_size = Vector2(152, 64)
	if lumber_camp_button != null:
		lumber_camp_button.custom_minimum_size = Vector2(152, 64)
	if quarry_button != null:
		quarry_button.custom_minimum_size = Vector2(152, 64)
	if house_button != null:
		house_button.custom_minimum_size = Vector2(152, 64)
	if has_node("UIRoot/GameViewportMask"):
		var mask := get_node("UIRoot/GameViewportMask") as ColorRect
		if mask != null:
			mask.offset_left = 0.0
			mask.offset_top = 0.0
			mask.offset_right = viewport_size.x
			mask.offset_bottom = viewport_size.y
	if has_node("UIRoot/ViewportDivider"):
		var divider := get_node("UIRoot/ViewportDivider") as ColorRect
		if divider != null:
			divider.offset_left = GAME_WORLD_VIEWPORT_RIGHT
			divider.offset_top = 0.0
			divider.offset_right = viewport_size.x
			divider.offset_bottom = viewport_size.y


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_placement_key(event)
	elif event is InputEventMouseButton:
		_handle_mouse_button_input(event)


func _input(event: InputEvent) -> void:
	_handle_camera_input(event)


func _process(_delta: float) -> void:
	_update_placement_hover()
	_update_camera_drag()


func _handle_camera_input(event: InputEvent) -> void:
	if not _is_pointer_inside_game_viewport():
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed:
			is_camera_dragging = false
		return
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_MIDDLE:
			is_camera_dragging = mouse_button.pressed
			camera_drag_last_mouse = get_viewport().get_mouse_position()
			get_viewport().set_input_as_handled()
		elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_button.pressed:
			_adjust_camera_zoom(1.0 + CAMERA_ZOOM_STEP)
			get_viewport().set_input_as_handled()
		elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_button.pressed:
			_adjust_camera_zoom(1.0 - CAMERA_ZOOM_STEP)
			get_viewport().set_input_as_handled()


func _update_camera_drag() -> void:
	if not is_camera_dragging or main_camera == null:
		return
	var current_mouse := get_viewport().get_mouse_position()
	var delta := current_mouse - camera_drag_last_mouse
	camera_drag_last_mouse = current_mouse
	if is_equal_approx(delta.length(), 0.0):
		return
	var world_delta := -delta * main_camera.zoom
	main_camera.global_position += world_delta
	_clamp_camera_to_game_viewport()


func _adjust_camera_zoom(multiplier: float) -> void:
	if main_camera == null:
		return
	var next_zoom := clampf(main_camera.zoom.x * multiplier, CAMERA_MIN_ZOOM, CAMERA_MAX_ZOOM)
	main_camera.zoom = Vector2(next_zoom, next_zoom)
	_clamp_camera_to_game_viewport()


func _clamp_camera_to_game_viewport() -> void:
	if main_camera == null:
		return
	var half_width := GAME_WORLD_VIEWPORT_RIGHT * 0.5 * main_camera.zoom.x
	var half_height := GAME_WORLD_VIEWPORT_BOTTOM * 0.5 * main_camera.zoom.y
	var center := Vector2(GAME_WORLD_VIEWPORT_RIGHT * 0.5, GAME_WORLD_VIEWPORT_BOTTOM * 0.5)
	main_camera.global_position.x = clampf(main_camera.global_position.x, center.x - half_width, center.x + half_width)
	main_camera.global_position.y = clampf(main_camera.global_position.y, center.y - half_height, center.y + half_height)


func _is_pointer_inside_game_viewport() -> bool:
	var mouse_pos := get_viewport().get_mouse_position()
	return mouse_pos.x < GAME_WORLD_VIEWPORT_RIGHT and mouse_pos.y < GAME_WORLD_VIEWPORT_BOTTOM


func _setup_economy_systems() -> void:
	production_calculator = ProductionCalculatorScript.new()
	tax_system = TaxSystemScript.new()
	happiness_system = HappinessSystemScript.new()
	riot_system = RiotSystemScript.new()
	victory_defeat_system = VictoryDefeatSystemScript.new()
	governance_state = GovernanceStateScript.new()
	governance_state.set_population(3)
	governance_state.set_tax_policy(MapTypes.TaxPolicy.NORMAL)
	if governance_state.has_signal("tax_policy_changed"):
		governance_state.connect("tax_policy_changed", Callable(self, "_on_tax_policy_changed"))
	if governance_state.has_signal("happiness_changed"):
		governance_state.connect("happiness_changed", Callable(self, "_on_happiness_changed"))
	if governance_state.has_signal("population_changed"):
		governance_state.connect("population_changed", Callable(self, "_on_population_changed"))
	if governance_state.has_signal("riot_risk_changed"):
		governance_state.connect("riot_risk_changed", Callable(self, "_on_riot_risk_changed"))
	if governance_state.has_signal("town_center_damage_changed"):
		governance_state.connect("town_center_damage_changed", Callable(self, "_on_town_center_damage_changed"))

	if has_node("/root/ResourceInventory"):
		resource_inventory = get_node("/root/ResourceInventory")
		if resource_inventory.has_method("reset_resources"):
			resource_inventory.call("reset_resources", _get_starting_resources())
		if resource_inventory.has_signal("inventory_changed"):
			resource_inventory.connect("inventory_changed", Callable(self, "_on_inventory_changed"))
	else:
		push_warning("ResourceInventory autoload is not available.")

	if has_node("/root/GameClock"):
		game_clock = get_node("/root/GameClock")
		if game_clock.has_signal("minute_changed"):
			game_clock.connect("minute_changed", Callable(self, "_on_game_minute_changed"))
		if game_clock.has_signal("time_changed"):
			game_clock.connect("time_changed", Callable(self, "_on_game_time_changed"))
		if game_clock.has_signal("time_scale_changed"):
			game_clock.connect("time_scale_changed", Callable(self, "_on_game_time_scale_changed"))
		if game_clock.has_signal("speed_changed"):
			game_clock.connect("speed_changed", Callable(self, "_on_game_speed_changed"))
		if game_clock.has_signal("pause_changed"):
			game_clock.connect("pause_changed", Callable(self, "_on_game_pause_changed"))
	else:
		push_warning("GameClock autoload is not available.")

func _setup_economy_ui() -> void:
	_update_economy_ui()


func _setup_time_control_ui() -> void:
	if speed_button != null:
		speed_button.pressed.connect(_on_speed_button_pressed)
	if pause_button != null:
		pause_button.pressed.connect(_on_pause_button_pressed)
	_update_time_control_ui()


func _on_speed_button_pressed() -> void:
	if game_clock != null and game_clock.has_method("cycle_speed"):
		game_clock.call("cycle_speed")
	_update_time_control_ui()


func _on_pause_button_pressed() -> void:
	if game_clock != null and game_clock.has_method("toggle_pause"):
		game_clock.call("toggle_pause")
	_update_time_control_ui()


func _setup_tax_ui() -> void:
	if tax_policy_button != null:
		tax_policy_button.pressed.connect(_on_tax_policy_button_pressed)
	_update_tax_ui()


func _setup_happiness_ui() -> void:
	_update_happiness_ui()


func _setup_riot_ui() -> void:
	_update_riot_ui()


func _setup_victory_ui() -> void:
	_update_victory_ui()

func _on_tax_policy_button_pressed() -> void:
	cycle_tax_policy()


func cycle_tax_policy() -> void:
	if governance_state == null or tax_system == null:
		return
	var next_policy: int = int(tax_system.get_next_policy(governance_state.tax_policy))
	set_tax_policy(next_policy)


func set_tax_policy(next_policy: int) -> void:
	if governance_state == null:
		return
	governance_state.set_tax_policy(next_policy)


func _update_tax_ui() -> void:
	if not is_node_ready():
		return
	if tax_policy_button != null:
		tax_policy_button.text = "税率：%s" % _get_current_tax_policy_label()
	if tax_status_label != null:
		tax_status_label.text = _get_tax_status_text()


func _update_happiness_ui() -> void:
	if not is_node_ready():
		return
	if happiness_status_label != null:
		happiness_status_label.text = _get_happiness_status_text()


func _update_riot_ui() -> void:
	if not is_node_ready():
		return
	if riot_status_label != null:
		riot_status_label.text = _get_riot_status_text()


func _update_victory_ui() -> void:
	if not is_node_ready():
		return
	if victory_status_label != null:
		victory_status_label.text = _get_victory_status_text()

func _update_time_control_ui() -> void:
	if not is_node_ready():
		return
	if speed_button != null:
		speed_button.text = "速度：%s" % _get_current_speed_label()
	if pause_button != null:
		pause_button.text = "恢复" if _is_game_time_paused() else "暂停"
	if time_control_status_label != null:
		time_control_status_label.text = _get_time_control_status_text()


func _get_time_control_status_text() -> String:
	var time_text := "--:--"
	if game_clock != null and game_clock.has_method("get_time_text"):
		time_text = str(game_clock.call("get_time_text"))
	var run_text := "暂停中" if _is_game_time_paused() else "运行中"
	return "%s / %s / %s" % [time_text, run_text, _get_current_speed_label()]


func _update_stage14_hud() -> void:
	if not is_node_ready():
		return
	_update_top_resource_bar()
	if hud_status_label != null:
		hud_status_label.text = _get_stage14_hud_text()
	if event_log_label != null:
		event_log_label.text = _get_event_log_text()
	_apply_ui_layout()


func _update_top_resource_bar() -> void:
	var resources: Dictionary = _get_resource_inventory_snapshot()
	var population := 0
	if governance_state != null:
		population = int(governance_state.population)
	if population_label != null:
		population_label.text = "人口 %d" % population
	if population_cap_label != null:
		population_cap_label.text = "上限 %d" % _get_population_cap()
	if gold_label != null:
		gold_label.text = "金币 %d" % int(float(resources.get(MapTypes.RESOURCE_GOLD, 0.0)))
	if food_label != null:
		food_label.text = "食物 %d" % int(float(resources.get(MapTypes.RESOURCE_FOOD, 0.0)))
	if wood_label != null:
		wood_label.text = "木材 %d" % int(float(resources.get(MapTypes.RESOURCE_WOOD, 0.0)))
	if stone_label != null:
		stone_label.text = "石料 %d" % int(float(resources.get(MapTypes.RESOURCE_STONE, 0.0)))


func _get_stage14_hud_text() -> String:
	var time_text := "未知"
	if game_clock != null and game_clock.has_method("get_time_text"):
		time_text = str(game_clock.call("get_time_text"))
	var day_text := "第 %d 天" % _get_current_day_count()
	var speed_text := _get_current_speed_label()
	var pause_text := "暂停" if _is_game_time_paused() else "运行中"
	var current_population := 0
	if governance_state != null:
		current_population = int(governance_state.population)
	var lines: Array[String] = []
	lines.append("%s %s" % [day_text, time_text])
	lines.append("速度：%s / %s" % [speed_text, pause_text])
	lines.append("人口：%d / %d" % [current_population, _get_population_cap()])
	lines.append(_get_selected_building_text())
	return "\n".join(lines)

func _get_current_day_count() -> int:
	if governance_state == null:
		return 1
	return max(int(governance_state.day_count), 1)


func _get_current_total_minutes() -> int:
	if game_clock != null and game_clock.has_method("get_total_minutes"):
		return int(game_clock.call("get_total_minutes"))
	return max((_get_current_day_count() - 1) * 1440, 0)


func _get_population_cap() -> int:
	var house_count := 0
	for building in initial_buildings:
		if building != null and int(building.building_type) == MapTypes.BuildingType.HOUSE:
			house_count += 1
	var house_capacity := house_count * HOUSE_POPULATION_CAPACITY
	if governance_state == null:
		return house_capacity
	return max(int(governance_state.population), house_capacity)


func _get_current_speed_label() -> String:
	if game_clock != null and game_clock.has_method("get_speed_label"):
		return str(game_clock.call("get_speed_label"))
	if game_clock != null and game_clock.has_method("get_time_scale"):
		return "%sx" % str(game_clock.call("get_time_scale"))
	return "1x"


func _is_game_time_paused() -> bool:
	if game_clock != null and game_clock.has_method("is_time_paused"):
		return bool(game_clock.call("is_time_paused"))
	if game_clock != null and game_clock.has_method("get_time_scale"):
		return is_equal_approx(float(game_clock.call("get_time_scale")), 0.0)
	return false


func _get_starting_resources() -> Dictionary:
	return {
		MapTypes.RESOURCE_FOOD: 5.0,
		MapTypes.RESOURCE_WOOD: 0.0,
		MapTypes.RESOURCE_STONE: 0.0,
		MapTypes.RESOURCE_GOLD: 10.0,
	}


func _read_demo_map() -> void:
	var reader := DemoMapReaderScript.new()
	map_read_result = reader.read_layers(ground_layer, resource_layer)
	if map_read_result.is_empty():
		push_error("GovernanceDemo failed to read map layers.")
		return

	grid = map_read_result["grid"]
	var scanner := ResourceRegionScannerScript.new()
	resource_regions = scanner.scan_all_resource_regions(grid)
	farmable_regions = scanner.scan_farmable_regions(grid)
	_print_map_summary(map_read_result, resource_regions, scanner)
	_spawn_initial_buildings()
	_setup_placement_controller()


func _spawn_initial_buildings() -> void:
	_clear_initial_building_nodes()
	_clear_villager_nodes()
	event_log_messages.clear()
	occupied_cells.clear()
	var spawner := InitialBuildingSpawnerScript.new()
	initial_buildings = spawner.spawn_initial_buildings(grid, resource_regions, farmable_regions, INITIAL_BUILDING_SEED)
	for building in initial_buildings:
		_register_occupied_cell(building.position)
		_instantiate_building_visual(building)
		_append_initial_building_event(building)
	_spawn_initial_villagers()
	_print_initial_building_summary(spawner)
	_print_villager_summary()


func _clear_initial_building_nodes() -> void:
	selected_building_data = null
	selected_building_node = null
	for child in buildings_root.get_children():
		child.queue_free()

func _clear_villager_nodes() -> void:
	for child in characters_root.get_children():
		child.queue_free()
	villager_states.clear()


func _instantiate_building_visual(building: RefCounted) -> Node2D:
	var building_scene := _get_building_scene(int(building.building_type))
	if building_scene == null:
		push_warning("Missing building scene for %s." % MapTypes.get_building_label(int(building.building_type)))
		return null
	var building_node := building_scene.instantiate() as Node2D
	if building_node == null:
		push_warning("Building scene is not Node2D: %s." % MapTypes.get_building_label(int(building.building_type)))
		return null
	building_node.name = _get_building_node_name(building)
	building_node.position = _grid_cell_to_building_position(building.position)
	building_node.set_meta("building_type", building.building_type)
	building_node.set_meta("linked_region_id", building.linked_region_id)
	building_node.set_meta("grid_cell", building.position)
	building_node.set_meta("building_data", building)
	_ensure_building_feedback_nodes(building_node)
	_ensure_building_click_area(building_node, building)
	buildings_root.add_child(building_node)
	_update_building_visual_state(building, building_node)
	return building_node

func _spawn_initial_villagers() -> void:
	var home_building := _find_home_building()
	if home_building == null:
		push_warning("No castle or house available for villager home route.")
		return

	var work_buildings := _get_production_buildings()
	if work_buildings.is_empty():
		push_warning("No production buildings available for villager routes.")
		return

	var home_position := _get_building_position_for_root(home_building, characters_root) + HOME_EXIT_OFFSET
	for index in range(work_buildings.size()):
		var work_building: RefCounted = work_buildings[index]
		var work_position := _get_building_position_for_root(work_building, characters_root) + WORK_ENTRY_OFFSET
		_spawn_villager_route(index, home_position, work_position, work_building)


func _spawn_villager_route(index: int, home_position: Vector2, work_position: Vector2, work_building: RefCounted) -> void:
	var villager := VILLAGER_SCENE.instantiate() as Node2D
	if villager == null:
		push_warning("Failed to instantiate villager scene.")
		return
	if not villager.has_method("setup_route"):
		push_warning("Villager scene does not expose setup_route().")
		villager.queue_free()
		return

	villager.name = "Villager%s%d" % [MapTypes.get_building_label(int(work_building.building_type)).replace(" ", ""), index]
	villager.z_index = 50
	characters_root.add_child(villager)
	if villager.has_signal("state_changed"):
		villager.connect("state_changed", Callable(self, "_on_villager_state_changed"))
	villager.call("setup_route", home_position, work_position, float(index) * VILLAGER_START_DELAY_STEP)
	villager_states[villager] = villager.call("get_state_name")
	print(
		"stage6 villager route | name=", villager.name,
		" work=", MapTypes.get_building_label(int(work_building.building_type)),
		" home=", home_position,
		" work_pos=", work_position
	)


func _setup_placement_controller() -> void:
	placement_controller = BuildingPlacementControllerScript.new()
	placement_controller.setup(grid, resource_regions, farmable_regions, occupied_cells, _get_castle_cell())


func _setup_placement_overlay() -> void:
	if placement_preview != null:
		var half_size := PLACEMENT_PREVIEW_SIZE * 0.5
		placement_preview.polygon = PackedVector2Array([
			Vector2(-half_size.x, -half_size.y),
			Vector2(half_size.x, -half_size.y),
			Vector2(half_size.x, half_size.y),
			Vector2(-half_size.x, half_size.y),
		])
		placement_preview.visible = false
		placement_preview.z_index = 100
	if hover_hint_label != null:
		hover_hint_label.visible = false
		hover_hint_label.z_index = 101


func _setup_placement_ui() -> void:
	if farm_button != null:
		farm_button.pressed.connect(_on_placement_button_pressed.bind(MapTypes.BuildingType.FARM))
	if lumber_camp_button != null:
		lumber_camp_button.pressed.connect(_on_placement_button_pressed.bind(MapTypes.BuildingType.LUMBER_CAMP))
	if quarry_button != null:
		quarry_button.pressed.connect(_on_placement_button_pressed.bind(MapTypes.BuildingType.QUARRY))
	if house_button != null:
		house_button.pressed.connect(_on_placement_button_pressed.bind(MapTypes.BuildingType.HOUSE))
	if cancel_placement_button != null:
		cancel_placement_button.pressed.connect(_on_cancel_placement_button_pressed)
	_update_placement_ui()


func _on_placement_button_pressed(building_type: int) -> void:
	_enter_placement_mode(building_type)


func _on_cancel_placement_button_pressed() -> void:
	_exit_placement_mode()


func _handle_placement_key(event: InputEventKey) -> void:
	match event.keycode:
		KEY_1:
			_enter_placement_mode(MapTypes.BuildingType.FARM)
		KEY_2:
			_enter_placement_mode(MapTypes.BuildingType.LUMBER_CAMP)
		KEY_3:
			_enter_placement_mode(MapTypes.BuildingType.QUARRY)
		KEY_4:
			_enter_placement_mode(MapTypes.BuildingType.HOUSE)
		KEY_ESCAPE:
			_exit_placement_mode()


func _handle_mouse_button_input(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_exit_placement_mode()
		return
	if event.button_index == MOUSE_BUTTON_LEFT and event.pressed and placement_mode_active:
		_try_place_selected_building()


func _enter_placement_mode(building_type: int) -> void:
	placement_mode_active = true
	selected_building_type = building_type
	last_placement_message = "已选择：%s。移动鼠标查看能否放置，左键确认。" % MapTypes.get_building_label(selected_building_type)
	print("stage7 placement mode | selected=", MapTypes.get_building_label(selected_building_type))
	_update_placement_hover(true)


func _exit_placement_mode() -> void:
	if not placement_mode_active:
		return
	placement_mode_active = false
	selected_building_type = -1
	hovered_cell = Vector2i(-1, -1)
	hovered_result = null
	last_placement_message = "已退出放置模式。"
	_update_placement_overlay()
	print("stage7 placement mode | exited")


func _update_placement_hover(force_update: bool = false) -> void:
	if not placement_mode_active or placement_controller == null:
		_update_placement_overlay()
		return

	var next_cell := _get_mouse_grid_cell()
	if not force_update and next_cell == hovered_cell:
		return
	hovered_cell = next_cell
	hovered_result = placement_controller.can_place(selected_building_type, hovered_cell)
	_update_placement_overlay()


func _update_placement_overlay() -> void:
	var has_active_preview := placement_mode_active and hovered_result != null
	if placement_preview != null:
		placement_preview.visible = has_active_preview
		if has_active_preview:
			placement_preview.position = _grid_cell_to_root_position(hovered_cell, placement_overlay)
			placement_preview.color = PLACEMENT_VALID_COLOR if bool(hovered_result.can_place) else PLACEMENT_INVALID_COLOR
	if hover_hint_label != null:
		hover_hint_label.visible = placement_mode_active
		if placement_mode_active:
			hover_hint_label.position = get_global_mouse_position() + Vector2(16, -16)
			hover_hint_label.text = _get_placement_hint_text()
	_update_placement_ui()


func _try_place_selected_building() -> void:
	if placement_controller == null or selected_building_type < 0:
		return
	if hovered_result == null:
		hovered_result = placement_controller.can_place(selected_building_type, hovered_cell)
	if not bool(hovered_result.can_place):
		last_placement_message = "放置失败：%s" % str(hovered_result.reason)
		_append_event_log("不能建造%s：%s" % [MapTypes.get_building_label(selected_building_type), str(hovered_result.reason)])
		print("stage7 placement blocked | building=", MapTypes.get_building_label(selected_building_type), " cell=", hovered_cell, " reason=", hovered_result.reason)
		_update_placement_overlay()
		return

	var placed_building: RefCounted = placement_controller.place(selected_building_type, hovered_cell)
	if placed_building == null:
		last_placement_message = "放置失败：没有创建出建筑数据。"
		_append_event_log("不能建造%s：没有创建出建筑数据。" % MapTypes.get_building_label(selected_building_type))
		_update_placement_overlay()
		return
	if placed_building.has_method("is_valid") and not bool(placed_building.can_place):
		last_placement_message = "放置失败：%s" % str(placed_building.reason)
		_append_event_log("不能建造%s：%s" % [MapTypes.get_building_label(selected_building_type), str(placed_building.reason)])
		print("stage7 placement blocked | building=", MapTypes.get_building_label(selected_building_type), " cell=", hovered_cell, " reason=", placed_building.reason)
		_update_placement_overlay()
		return

	initial_buildings.append(placed_building)
	_register_occupied_cell(placed_building.position)
	_instantiate_building_visual(placed_building)
	last_placement_message = "建造完成：%s，格子 %s。" % [placed_building.get_building_label(), str(placed_building.position)]
	_append_event_log(last_placement_message)
	print("stage7 placement success | building=", placed_building.get_building_label(), " cell=", placed_building.position)
	_update_placement_hover(true)


func debug_stage7_try_place(building_type: int, cell: Vector2i) -> bool:
	if placement_controller == null:
		return false
	selected_building_type = building_type
	hovered_cell = cell
	hovered_result = placement_controller.can_place(selected_building_type, hovered_cell)
	var before_count := initial_buildings.size()
	_try_place_selected_building()
	return initial_buildings.size() > before_count


func debug_stage7_can_place(building_type: int, cell: Vector2i) -> RefCounted:
	if placement_controller == null:
		return null
	return placement_controller.can_place(building_type, cell)


func _get_mouse_grid_cell() -> Vector2i:
	var local_position := ground_layer.to_local(get_global_mouse_position())
	var map_cell := ground_layer.local_to_map(local_position)
	return map_cell - (map_read_result.get("cell_offset", Vector2i.ZERO) as Vector2i)


func _get_placement_hint_text() -> String:
	if not placement_mode_active or selected_building_type < 0:
		return ""
	var building_label := MapTypes.get_building_label(selected_building_type)
	if hovered_result == null:
		return "当前建筑：%s" % building_label
	if bool(hovered_result.can_place):
		return "当前建筑：%s\n当前位置：%s\n可以放置。" % [building_label, str(hovered_cell)]
	return "当前建筑：%s\n当前位置：%s\n不能放置：%s" % [building_label, str(hovered_cell), str(hovered_result.reason)]

func _update_placement_ui() -> void:
	_update_placement_button_texts()
	if cancel_placement_button != null:
		cancel_placement_button.disabled = not placement_mode_active
	if placement_status_label != null:
		placement_status_label.text = _get_placement_status_text()
	_update_economy_ui()


func _on_game_minute_changed(total_minutes: int) -> void:
	if _is_victory_defeat_finalized():
		return
	_apply_minute_economy()
	_apply_daily_happiness_if_needed(total_minutes)
	_refresh_stage14_hud()

func _on_game_time_changed(_time_text: String) -> void:
	_update_economy_ui()
	_refresh_stage14_hud()


func _on_game_time_scale_changed(_scale: float) -> void:
	_update_time_control_ui()
	_refresh_stage14_hud()


func _on_game_speed_changed(_speed_scale: float, _speed_label: String) -> void:
	_update_time_control_ui()
	_refresh_stage14_hud()


func _on_game_pause_changed(_paused: bool) -> void:
	_update_time_control_ui()
	_refresh_stage14_hud()


func _on_inventory_changed(_resources: Dictionary) -> void:
	_update_economy_ui()
	_update_happiness_ui()
	_refresh_stage14_hud()

func _on_tax_policy_changed(_new_tax_policy: int) -> void:
	last_tax_message = "税率已切换：%s" % _get_current_tax_policy_label()
	_append_event_log(last_tax_message)
	_update_tax_ui()
	_update_happiness_ui()
	_update_economy_ui()
	_refresh_stage14_hud()

func _on_happiness_changed(_new_happiness: float) -> void:
	_update_tax_ui()
	_update_happiness_ui()
	_update_riot_ui()
	_update_economy_ui()
	_update_victory_ui()
	_check_immediate_defeat()
	_refresh_stage14_hud()


func _on_population_changed(_new_population: int) -> void:
	_update_tax_ui()
	_update_happiness_ui()
	_update_riot_ui()
	_update_economy_ui()
	_update_victory_ui()
	_check_immediate_defeat()
	_refresh_stage14_hud()


func _on_riot_risk_changed(_new_riot_risk: float) -> void:
	_update_riot_ui()
	_update_economy_ui()
	_refresh_stage14_hud()


func _on_town_center_damage_changed(_new_damage: int, _destroyed: bool) -> void:
	_update_riot_ui()
	_update_economy_ui()
	_update_victory_ui()
	_check_immediate_defeat()
	_refresh_stage14_hud()

func _apply_minute_economy() -> void:
	if production_calculator == null or governance_state == null or resource_inventory == null:
		return

	var regions_by_id := _get_regions_by_id()
	var building_delta := _apply_minute_building_storage(regions_by_id)
	var global_delta := _build_minute_global_delta()
	last_minute_delta = _merge_resource_deltas(building_delta, global_delta)
	resource_inventory.call("apply_delta", global_delta)
	_update_economy_ui()
	_refresh_stage14_hud()

func _get_regions_by_id() -> Dictionary:
	var regions_by_id: Dictionary = {}
	for terrain_type in resource_regions.keys():
		var regions_for_terrain: Dictionary = {}
		for region in resource_regions[terrain_type]:
			regions_for_terrain[int(region.region_id)] = region
		regions_by_id[int(terrain_type)] = regions_for_terrain
	return regions_by_id


func _apply_minute_building_storage(regions_by_id: Dictionary) -> Dictionary:
	var building_delta := _get_empty_resource_delta()
	for building in initial_buildings:
		if building == null or not building.is_active:
			continue
		var building_output: Dictionary = production_calculator.get_building_output_per_minute(building, regions_by_id)
		for resource_type in building_output.keys():
			if resource_type == MapTypes.RESOURCE_GOLD:
				continue
			var accepted_amount: float = building.add_to_storage(resource_type, float(building_output[resource_type]))
			_add_to_delta(building_delta, resource_type, accepted_amount)
		_update_building_visual_for_data(building)
	return building_delta


func _build_minute_global_delta() -> Dictionary:
	var global_delta := _get_empty_resource_delta()
	if governance_state == null:
		return global_delta
	global_delta[MapTypes.RESOURCE_FOOD] -= production_calculator.get_food_consumption_per_minute(governance_state.population)
	global_delta[MapTypes.RESOURCE_GOLD] += production_calculator.get_tax_income_per_minute(governance_state.population, governance_state.tax_policy)
	return global_delta


func _merge_resource_deltas(first_delta: Dictionary, second_delta: Dictionary) -> Dictionary:
	var merged := _get_empty_resource_delta()
	for resource_type in first_delta.keys():
		_add_to_delta(merged, resource_type, float(first_delta[resource_type]))
	for resource_type in second_delta.keys():
		_add_to_delta(merged, resource_type, float(second_delta[resource_type]))
	return merged


func _apply_daily_happiness_if_needed(total_minutes: int) -> void:
	if _is_victory_defeat_finalized():
		return
	if governance_state == null or happiness_system == null:
		return
	var day_index: int = int(total_minutes / 1440)
	if day_index <= 0 or day_index == last_tax_day_index:
		return
	last_tax_day_index = day_index
	governance_state.next_day()
	_apply_daily_riot(day_index)
	if _is_victory_defeat_finalized():
		return
	var resources_snapshot: Dictionary = _get_resource_inventory_snapshot()
	last_happiness_report = happiness_system.apply_daily_happiness(governance_state, resources_snapshot, _get_last_riot_penalty())
	last_daily_happiness_delta = float(last_happiness_report.get("total_delta", 0.0))
	last_happiness_message = "第 %d 天幸福度变化：%+0.1f | %s" % [governance_state.day_count, last_daily_happiness_delta, str(last_happiness_report.get("summary", ""))]
	last_tax_message = "第 %d 天税率影响：幸福度 %+0.1f" % [governance_state.day_count, float(last_happiness_report.get("tax_delta", 0.0))]
	_append_daily_happiness_events(last_happiness_report)
	_update_tax_ui()
	_update_happiness_ui()
	_update_riot_ui()
	_check_victory_defeat_after_day(day_index)
	_update_economy_ui()


func _apply_daily_riot(day_index: int) -> void:
	if riot_system == null or governance_state == null:
		return
	last_riot_report = riot_system.apply_daily_riot(governance_state, initial_buildings, resource_inventory, day_index)
	last_riot_message = str(last_riot_report.get("message", ""))
	if bool(last_riot_report.get("triggered", false)):
		_append_event_log(last_riot_message)
	_update_buildings_after_riot(last_riot_report)
	_update_all_building_visual_states()
	_check_immediate_defeat()


func _get_last_riot_penalty() -> float:
	if last_riot_report.is_empty():
		return 0.0
	if not bool(last_riot_report.get("triggered", false)):
		return 0.0
	return float(last_riot_report.get("riot_penalty", 0.0))

func _get_current_tax_policy_label() -> String:
	if governance_state == null:
		return "未知"
	return MapTypes.get_tax_policy_label(governance_state.tax_policy)


func _get_tax_status_text() -> String:
	if governance_state == null or tax_system == null:
		return "税收：未初始化"
	var daily_income: float = tax_system.get_daily_gold_per_person(governance_state.tax_policy) * float(max(governance_state.population, 0))
	var happiness_delta: float = tax_system.get_daily_happiness_delta(governance_state.tax_policy)
	var message: String = "暂无结算" if last_tax_message.is_empty() else last_tax_message
	return "税收：%s\n金币 +%.1f/天 / 幸福度 %+.1f/天\n%s" % [_get_current_tax_policy_label(), daily_income, happiness_delta, message]

func _get_empty_resource_delta() -> Dictionary:
	return {
		MapTypes.RESOURCE_FOOD: 0.0,
		MapTypes.RESOURCE_WOOD: 0.0,
		MapTypes.RESOURCE_STONE: 0.0,
		MapTypes.RESOURCE_GOLD: 0.0,
	}


func _add_to_delta(delta: Dictionary, resource_type: StringName, amount: float) -> void:
	if resource_type == &"" or is_equal_approx(amount, 0.0):
		return
	delta[resource_type] = float(delta.get(resource_type, 0.0)) + amount


func _update_economy_ui() -> void:
	if economy_status_label == null:
		return
	var resources_text := _get_resource_inventory_text()
	var delta_text := _get_minute_delta_text()
	var time_text := ""
	if game_clock != null and game_clock.has_method("get_time_text"):
		time_text = str(game_clock.call("get_time_text"))
	var time_control_text := _get_time_control_status_text()
	var tax_text := _get_tax_status_text()
	var happiness_text := _get_happiness_status_text()
	var selection_text := _get_selected_building_text()
	var collection_text := _get_collection_message_text()
	economy_status_label.text = "时间：%s\n%s\n%s\n%s\n库存：%s\n上次每分钟变化：%s\n%s\n%s" % [time_text, time_control_text, tax_text, happiness_text, resources_text, delta_text, selection_text, collection_text]


func _refresh_stage14_hud() -> void:
	_update_stage14_hud()

func _get_resource_inventory_text() -> String:
	if resource_inventory == null or not resource_inventory.has_method("get_all_resources"):
		return "N/A"
	var resources: Dictionary = resource_inventory.call("get_all_resources")
	var food := int(float(resources.get(MapTypes.RESOURCE_FOOD, 0.0)))
	var wood := int(float(resources.get(MapTypes.RESOURCE_WOOD, 0.0)))
	var stone := int(float(resources.get(MapTypes.RESOURCE_STONE, 0.0)))
	var gold := int(float(resources.get(MapTypes.RESOURCE_GOLD, 0.0)))
	return "Food %d / Wood %d / Stone %d / Gold %d" % [food, wood, stone, gold]


func _get_resource_inventory_snapshot() -> Dictionary:
	if resource_inventory == null or not resource_inventory.has_method("get_all_resources"):
		return {}
	return resource_inventory.call("get_all_resources")

func _get_happiness_status_text() -> String:
	if happiness_system == null or governance_state == null:
		return "幸福度：未初始化"
	var report: Dictionary = happiness_system.build_daily_report(governance_state, _get_resource_inventory_snapshot(), _get_last_riot_penalty())
	var food_amount: float = float(report.get("food_amount", 0.0))
	var daily_food_need: float = float(report.get("daily_food_need", 0.0))
	var food_days: float = float(report.get("food_days", 0.0))
	var food_days_text := "∞" if daily_food_need <= 0.0 else "%.1f" % food_days
	var riot_text := "未知"
	if riot_system != null:
		var riot_report: Dictionary = riot_system.build_risk_report(governance_state)
		riot_text = "%s %.0f%%" % [str(riot_report.get("risk_label", "未知")), float(riot_report.get("daily_probability_percent", 0.0))]
	var lines: Array[String] = []
	lines.append("幸福度 %.1f" % governance_state.happiness)
	lines.append("情绪 %s" % _get_happiness_mood_label(governance_state.happiness))
	lines.append("食物 %s / %s 天" % [str(report.get("food_status", "未知")), food_days_text])
	lines.append("民意变化 %+.1f" % float(report.get("total_delta", 0.0)))
	lines.append("暴乱 %s" % riot_text)
	lines.append("库存食物 %.1f / 每日消耗 %.1f" % [food_amount, daily_food_need])
	return "\n".join(lines)


func _get_happiness_mood_label(happiness: float) -> String:
	if happiness >= 80.0:
		return "满意"
	if happiness >= 60.0:
		return "平稳"
	if happiness >= 40.0:
		return "不安"
	if happiness >= 20.0:
		return "愤怒"
	return "崩溃"


func _get_riot_status_text() -> String:
	if riot_system == null or governance_state == null:
		return "未初始化"
	var risk_report: Dictionary = riot_system.build_risk_report(governance_state)
	var risk_label := str(risk_report.get("risk_label", "未知"))
	var probability := float(risk_report.get("daily_probability_percent", 0.0))
	var last_message := "暂无暴乱事件" if last_riot_message.is_empty() else last_riot_message
	var lines: Array[String] = []
	lines.append("暴乱风险：%s（每日 %.0f%%）" % [risk_label, probability])
	lines.append("原因：幸福度 %.1f" % governance_state.happiness)
	lines.append("城堡受损：%d/%d%s" % [
		int(governance_state.town_center_damage),
		GovernanceStateScript.TOWN_CENTER_MAX_DAMAGE,
		"（已摧毁）" if bool(governance_state.town_center_destroyed) else "",
	])
	lines.append("最近事件：%s" % last_message)
	return "\n".join(lines)

func _get_victory_status_text() -> String:
	if victory_defeat_system == null or governance_state == null:
		return "未初始化"
	var report: Dictionary = last_victory_defeat_report
	if report.is_empty() and victory_defeat_system.has_method("build_status_report"):
		report = victory_defeat_system.call("build_status_report", governance_state)
	var result_type: StringName = report.get("result_type", VictoryDefeatSystemScript.RESULT_NONE)
	var title := "进行中"
	if result_type == VictoryDefeatSystemScript.RESULT_VICTORY:
		title = "胜利"
	elif result_type == VictoryDefeatSystemScript.RESULT_DEFEAT:
		title = "失败"
	var lines: Array[String] = []
	lines.append("状态：%s" % title)
	lines.append("当前：第 %d 天 / 人口 %d / 幸福度 %.1f" % [
		int(report.get("completed_day_index", 0)),
		int(report.get("population", governance_state.population)),
		float(report.get("happiness", governance_state.happiness)),
	])
	lines.append("连续暴乱：%d/%d 天" % [
		int(report.get("consecutive_riot_days", 0)),
		int(report.get("required_consecutive_riot_days", VictoryDefeatSystemScript.REQUIRED_CONSECUTIVE_RIOT_DAYS)),
	])
	lines.append(str(report.get("reason_text", "进行中")))
	return "\n".join(lines)

func _is_victory_defeat_finalized() -> bool:
	return victory_defeat_system != null and victory_defeat_system.has_method("has_result") and bool(victory_defeat_system.call("has_result"))


func _check_immediate_defeat() -> Dictionary:
	if victory_defeat_system == null or governance_state == null:
		return {}
	if _is_victory_defeat_finalized():
		return last_victory_defeat_report
	last_victory_defeat_report = victory_defeat_system.call("check_immediate_defeat", governance_state)
	if bool(last_victory_defeat_report.get("has_result", false)):
		_finalize_victory_defeat_if_needed()
	_update_victory_ui()
	return last_victory_defeat_report


func _check_victory_defeat_after_day(day_index: int) -> Dictionary:
	if victory_defeat_system == null or governance_state == null:
		return {}
	if _is_victory_defeat_finalized():
		return last_victory_defeat_report
	var riot_triggered := bool(last_riot_report.get("triggered", false))
	last_victory_defeat_report = victory_defeat_system.call("evaluate_daily_result", governance_state, day_index, riot_triggered)
	if bool(last_victory_defeat_report.get("has_result", false)):
		_finalize_victory_defeat_if_needed()
	_update_victory_ui()
	return last_victory_defeat_report


func _finalize_victory_defeat_if_needed() -> void:
	if last_victory_defeat_report.is_empty() or not bool(last_victory_defeat_report.get("has_result", false)):
		return
	var result_message := str(last_victory_defeat_report.get("reason_text", ""))
	_append_event_log(result_message)
	if game_clock != null and game_clock.has_method("set_paused"):
		game_clock.call("set_paused", true)
	_update_time_control_ui()
	_update_economy_ui()


func _append_event_log(message: String) -> void:
	if message.is_empty():
		return
	event_log_messages.push_front(message)
	while event_log_messages.size() > 3:
		event_log_messages.pop_back()
	_update_stage14_hud()


func _get_event_log_text() -> String:
	if event_log_messages.is_empty():
		return "暂无"
	return " / ".join(event_log_messages)


func _append_initial_building_event(building: RefCounted) -> void:
	if building == null:
		return
	if int(building.building_type) == MapTypes.BuildingType.HOUSE:
		_append_event_log("初始住宅已生成，后续村民 home 点可优先使用住宅。")
		return
	if not building.is_production_building():
		return
	var region_text := "绑定资源板块 #%d" % int(building.linked_region_id)
	_append_event_log("初始%s已%s。" % [building.get_building_label(), region_text])


func _append_daily_happiness_events(report: Dictionary) -> void:
	if report.is_empty():
		return
	var summary := str(report.get("summary", ""))
	if not summary.is_empty():
		_append_event_log(summary)
	var food_status := str(report.get("food_status", ""))
	if food_status == "饥荒" or food_status == "不足":
		_append_event_log("粮食不足，幸福度 %+.1f。" % float(report.get("food_delta", 0.0)))
	elif food_status == "充足":
		_append_event_log("食物充足，幸福度 %+.1f。" % float(report.get("food_delta", 0.0)))
	var tax_delta := float(report.get("tax_delta", 0.0))
	if tax_delta < 0.0:
		_append_event_log("高税引发不满，幸福度 %+.1f。" % tax_delta)
	elif tax_delta > 0.0:
		_append_event_log("低税政策让人民满意，幸福度 %+.1f。" % tax_delta)


func _update_buildings_after_riot(report: Dictionary) -> void:
	if not bool(report.get("triggered", false)):
		return
	var damaged_cell: Vector2i = report.get("damaged_cell", Vector2i(-9999, -9999))
	for building in initial_buildings:
		if building == null or building.position != damaged_cell:
			continue
		var building_node := _find_building_node(building)
		if building_node != null:
			_apply_damaged_building_visual(building_node)
		break


func _apply_damaged_building_visual(building_node: Node2D) -> void:
	building_node.modulate = Color(0.42, 0.42, 0.42, 0.72)
	building_node.set_meta("riot_damaged", true)

func _get_minute_delta_text() -> String:
	if last_minute_delta.is_empty():
		return "暂无"
	var food := float(last_minute_delta.get(MapTypes.RESOURCE_FOOD, 0.0))
	var wood := float(last_minute_delta.get(MapTypes.RESOURCE_WOOD, 0.0))
	var stone := float(last_minute_delta.get(MapTypes.RESOURCE_STONE, 0.0))
	var gold := float(last_minute_delta.get(MapTypes.RESOURCE_GOLD, 0.0))
	return "Food %+0.2f / Wood %+0.2f / Stone %+0.2f / Gold %+0.2f" % [food, wood, stone, gold]


func _update_placement_button_texts() -> void:
	_set_placement_button_text(farm_button, MapTypes.BuildingType.FARM, "农场")
	_set_placement_button_text(lumber_camp_button, MapTypes.BuildingType.LUMBER_CAMP, "伐木场")
	_set_placement_button_text(quarry_button, MapTypes.BuildingType.QUARRY, "采石场")
	_set_placement_button_text(house_button, MapTypes.BuildingType.HOUSE, "住宅")


func _set_placement_button_text(button: Button, building_type: int, base_text: String) -> void:
	if button == null:
		return
	button.text = "▶ %s" % base_text if placement_mode_active and selected_building_type == building_type else base_text


func _get_placement_status_text() -> String:
	var lines: Array[String] = []
	if placement_mode_active and selected_building_type >= 0:
		lines.append("当前选择：%s" % MapTypes.get_building_label(selected_building_type))
		if hovered_result != null:
			lines.append("位置：%s" % str(hovered_cell))
			if bool(hovered_result.can_place):
				lines.append("放置：可以")
			else:
				lines.append("放置：不可以 - %s" % str(hovered_result.reason))
	else:
		lines.append("当前选择：无")
	if not last_placement_message.is_empty():
		lines.append(last_placement_message)
	return "\n".join(lines)

func _register_occupied_cell(cell: Vector2i) -> void:
	occupied_cells[cell] = true


func _find_home_building() -> RefCounted:
	for building in initial_buildings:
		if int(building.building_type) == MapTypes.BuildingType.HOUSE:
			return building
	for building in initial_buildings:
		if int(building.building_type) == MapTypes.BuildingType.TOWN_CENTER:
			return building
	return null


func _get_production_buildings() -> Array:
	var buildings: Array = []
	for building in initial_buildings:
		if MapTypes.is_production_building(int(building.building_type)):
			buildings.append(building)
	return buildings


func _get_castle_cell() -> Vector2i:
	for building in initial_buildings:
		if int(building.building_type) == MapTypes.BuildingType.TOWN_CENTER:
			return building.position
	return Vector2i(-1, -1)


func _get_building_scene(building_type: int) -> PackedScene:
	match building_type:
		MapTypes.BuildingType.TOWN_CENTER:
			return CASTLE_SCENE
		MapTypes.BuildingType.LUMBER_CAMP:
			return LUMBER_CAMP_SCENE
		MapTypes.BuildingType.QUARRY:
			return QUARRY_SCENE
		MapTypes.BuildingType.FARM:
			return FARM_SCENE
		MapTypes.BuildingType.HOUSE:
			return HOUSE_SCENE
		_:
			return null


func _ensure_building_feedback_nodes(building_node: Node2D) -> void:
	if not building_node.has_node("SelectionOutline"):
		var outline := Polygon2D.new()
		outline.name = "SelectionOutline"
		outline.visible = false
		outline.z_index = 80
		outline.color = Color(1.0, 0.86, 0.22, 0.38)
		outline.polygon = PackedVector2Array([Vector2(-62, -48), Vector2(62, -48), Vector2(62, 48), Vector2(-62, 48)])
		building_node.add_child(outline)
	if not building_node.has_node("ReadyIndicator"):
		var ready_indicator := Polygon2D.new()
		ready_indicator.name = "ReadyIndicator"
		ready_indicator.visible = false
		ready_indicator.z_index = 90
		ready_indicator.position = Vector2(46, -50)
		ready_indicator.color = Color(1.0, 0.82, 0.16, 1.0)
		ready_indicator.polygon = PackedVector2Array([Vector2(0, -10), Vector2(9, 0), Vector2(0, 10), Vector2(-9, 0)])
		building_node.add_child(ready_indicator)
	if not building_node.has_node("StorageLabel"):
		var storage_label := Label.new()
		storage_label.name = "StorageLabel"
		storage_label.visible = false
		storage_label.z_index = 95
		storage_label.position = Vector2(-72, -76)
		storage_label.size = Vector2(144, 24)
		storage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		storage_label.add_theme_font_size_override("font_size", 12)
		building_node.add_child(storage_label)


func _ensure_building_click_area(building_node: Node2D, building: RefCounted) -> void:
	if building_node == null or building == null or building_node.has_node("InteractionArea"):
		return
	var interaction_area := Area2D.new()
	interaction_area.name = "InteractionArea"
	interaction_area.input_pickable = true
	interaction_area.collision_layer = 2
	interaction_area.collision_mask = 0
	interaction_area.set_meta("building_data", building)
	interaction_area.set_meta("building_node", building_node)

	var collision_shape := CollisionShape2D.new()
	collision_shape.name = "CollisionShape2D"
	var shape := RectangleShape2D.new()
	shape.size = _get_click_area_size(building)
	collision_shape.shape = shape
	interaction_area.add_child(collision_shape)
	interaction_area.input_event.connect(Callable(self, "_on_building_input_event").bind(building, building_node))
	building_node.add_child(interaction_area)


func _get_click_area_size(building: RefCounted) -> Vector2:
	match int(building.building_type):
		MapTypes.BuildingType.TOWN_CENTER:
			return Vector2(220, 240)
		MapTypes.BuildingType.LUMBER_CAMP:
			return Vector2(120, 96)
		MapTypes.BuildingType.QUARRY:
			return Vector2(120, 96)
		MapTypes.BuildingType.FARM:
			return Vector2(120, 96)
		MapTypes.BuildingType.HOUSE:
			return Vector2(96, 84)
		_:
			return Vector2(100, 84)


func _on_building_input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int, building: RefCounted, building_node: Node2D) -> void:
	if placement_mode_active:
		return
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return
	_handle_building_click(building, building_node)


func _handle_building_click(building: RefCounted, building_node: Node2D) -> void:
	if building == null:
		return
	_set_selected_building(building, building_node)
	if building.has_claimable_resources():
		var claimed := _claim_building_storage(building)
		last_collection_message = _format_claim_message(building, claimed)
	else:
		last_collection_message = "%s %s。" % [building.get_building_label(), building.get_claim_empty_message()]
	_append_event_log(last_collection_message)
	_update_all_building_visual_states()
	_update_economy_ui()


func _set_selected_building(building: RefCounted, building_node: Node2D) -> void:
	selected_building_data = building
	selected_building_node = building_node


func _claim_building_storage(building: RefCounted) -> Dictionary:
	if building == null or resource_inventory == null:
		return {}
	var claimed: Dictionary = building.claim_storage()
	if not claimed.is_empty():
		resource_inventory.call("apply_delta", claimed)
	return claimed


func _format_claim_message(building: RefCounted, claimed: Dictionary) -> String:
	var parts: Array[String] = []
	for resource_type in claimed.keys():
		parts.append("%s +%.2f" % [_get_resource_label(resource_type), float(claimed[resource_type])])
	if parts.is_empty():
		return "%s %s。" % [building.get_building_label(), building.get_claim_empty_message()]
	return "%s 领取成功：%s" % [building.get_building_label(), " / ".join(parts)]


func _get_selected_building_text() -> String:
	if selected_building_data == null:
		return "选中建筑：无"
	return "选中建筑：%s | 库存：%s" % [selected_building_data.get_building_label(), selected_building_data.get_storage_summary()]


func _get_collection_message_text() -> String:
	if last_collection_message.is_empty():
		return "领取反馈：暂无"
	return "领取反馈：%s" % last_collection_message


func _update_building_visual_for_data(building: RefCounted) -> void:
	var building_node := _find_building_node(building)
	if building_node != null:
		_update_building_visual_state(building, building_node)


func _update_all_building_visual_states() -> void:
	for building in initial_buildings:
		_update_building_visual_for_data(building)


func _find_building_node(building: RefCounted) -> Node2D:
	for child in buildings_root.get_children():
		if child is Node2D and child.has_meta("building_data") and child.get_meta("building_data") == building:
			return child as Node2D
	return null


func _update_building_visual_state(building: RefCounted, building_node: Node2D) -> void:
	if building == null or building_node == null or not is_instance_valid(building_node):
		return
	building_node.modulate = Color(1.0, 1.0, 1.0, 1.0) if bool(building.is_active) else Color(0.42, 0.42, 0.42, 0.72)
	var is_selected := selected_building_node == building_node
	if building_node.has_method("set_selected"):
		building_node.call("set_selected", is_selected)
	var selection_outline := building_node.get_node_or_null("SelectionOutline")
	if selection_outline is CanvasItem:
		(selection_outline as CanvasItem).visible = is_selected
	var storage_label := building_node.get_node_or_null("StorageLabel")
	if storage_label is Label:
		var label := storage_label as Label
		label.visible = building.can_store_resources()
		label.text = building.get_storage_summary()
		label.modulate = Color(0.85, 1.0, 0.75, 1.0) if building.has_claimable_resources() else Color(1.0, 1.0, 1.0, 0.8)
	var ready_indicator := building_node.get_node_or_null("ReadyIndicator")
	if ready_indicator is CanvasItem:
		(ready_indicator as CanvasItem).visible = bool(building.is_active) and building.has_claimable_resources()


func _get_resource_label(resource_type: StringName) -> String:
	match resource_type:
		MapTypes.RESOURCE_FOOD:
			return "Food"
		MapTypes.RESOURCE_WOOD:
			return "Wood"
		MapTypes.RESOURCE_STONE:
			return "Stone"
		MapTypes.RESOURCE_GOLD:
			return "Gold"
		_:
			return str(resource_type)


func debug_stage8_5_apply_minute() -> void:
	_apply_minute_economy()


func debug_stage9_cycle_speed() -> void:
	_on_speed_button_pressed()


func debug_stage9_toggle_pause() -> void:
	_on_pause_button_pressed()


func debug_stage10_cycle_tax_policy() -> void:
	cycle_tax_policy()


func debug_stage10_set_tax_policy(next_policy: int) -> void:
	set_tax_policy(next_policy)


func debug_stage10_apply_day(total_minutes: int = 1440) -> void:
	_apply_daily_happiness_if_needed(total_minutes)


func debug_stage11_apply_day(total_minutes: int = 1440) -> Dictionary:
	_apply_daily_happiness_if_needed(total_minutes)
	return last_happiness_report


func debug_stage11_set_stable_day_count(next_count: int) -> void:
	if happiness_system != null and happiness_system.has_method("set_stable_day_count"):
		happiness_system.call("set_stable_day_count", next_count)


func debug_stage11_get_last_report() -> Dictionary:
	return last_happiness_report


func debug_stage12_set_seed(seed: int) -> void:
	if riot_system != null and riot_system.has_method("set_seed"):
		riot_system.call("set_seed", seed)


func debug_stage12_apply_day(total_minutes: int = 1440) -> Dictionary:
	_apply_daily_happiness_if_needed(total_minutes)
	return last_riot_report


func debug_stage12_force_riot(consequence_id: StringName = &"") -> Dictionary:
	if riot_system == null:
		return {}
	last_riot_report = riot_system.apply_forced_riot(governance_state, initial_buildings, resource_inventory, consequence_id, governance_state.day_count)
	last_riot_message = str(last_riot_report.get("message", ""))
	_append_event_log(last_riot_message)
	_update_buildings_after_riot(last_riot_report)
	_update_all_building_visual_states()
	_update_riot_ui()
	_update_happiness_ui()
	_update_economy_ui()
	return last_riot_report


func debug_stage12_get_last_report() -> Dictionary:
	return last_riot_report


func debug_stage13_evaluate_day(day_index: int, riot_triggered: bool = false) -> Dictionary:
	if victory_defeat_system == null or governance_state == null:
		return {}
	if _is_victory_defeat_finalized():
		return last_victory_defeat_report
	last_victory_defeat_report = victory_defeat_system.call("evaluate_daily_result", governance_state, day_index, riot_triggered)
	if bool(last_victory_defeat_report.get("has_result", false)):
		_finalize_victory_defeat_if_needed()
	_update_victory_ui()
	return last_victory_defeat_report


func debug_stage13_get_last_report() -> Dictionary:
	return last_victory_defeat_report


func debug_stage13_reset_victory_state() -> void:
	if victory_defeat_system != null and victory_defeat_system.has_method("reset"):
		victory_defeat_system.call("reset")
	last_victory_defeat_report = {}
	_update_victory_ui()


func debug_stage15_advance_minutes(minute_count: int) -> void:
	if minute_count <= 0:
		return
	if game_clock != null and game_clock.has_method("advance_minutes"):
		game_clock.call("advance_minutes", minute_count)
		return
	var start_minutes: int = _get_current_total_minutes()
	for minute_offset in range(minute_count):
		var total_minutes: int = start_minutes + minute_offset + 1
		_on_game_minute_changed(total_minutes)


func debug_stage15_advance_days(day_count: int) -> void:
	if day_count <= 0:
		return
	if game_clock != null and game_clock.has_method("advance_minutes"):
		game_clock.call("advance_minutes", day_count * 1440)
		return
	var start_day_index: int = max(last_tax_day_index, 0)
	for day_offset in range(day_count):
		var total_minutes: int = (start_day_index + day_offset + 1) * 1440
		_on_game_minute_changed(total_minutes)


func debug_stage15_get_flow_snapshot() -> Dictionary:
	var counts := _count_buildings(initial_buildings)
	return {
		"has_grid": grid != null,
		"ground_cells_read": int(map_read_result.get("ground_cells_read", 0)),
		"resource_cells_read": int(map_read_result.get("resource_cells_read", 0)),
		"forest_region_count": _get_region_count(resource_regions, MapTypes.TerrainType.FOREST),
		"stone_region_count": _get_region_count(resource_regions, MapTypes.TerrainType.STONE),
		"farmable_region_count": farmable_regions.size(),
		"building_count": initial_buildings.size(),
		"castle_count": int(counts.get(MapTypes.BuildingType.TOWN_CENTER, 0)),
		"lumber_camp_count": int(counts.get(MapTypes.BuildingType.LUMBER_CAMP, 0)),
		"quarry_count": int(counts.get(MapTypes.BuildingType.QUARRY, 0)),
		"farm_count": int(counts.get(MapTypes.BuildingType.FARM, 0)),
		"house_count": int(counts.get(MapTypes.BuildingType.HOUSE, 0)),
		"villager_count": characters_root.get_child_count() if characters_root != null else 0,
		"population": int(governance_state.population) if governance_state != null else 0,
		"happiness": float(governance_state.happiness) if governance_state != null else 0.0,
		"riot_risk": float(governance_state.riot_risk) if governance_state != null else 0.0,
		"tax_policy": int(governance_state.tax_policy) if governance_state != null else -1,
		"day_count": int(governance_state.day_count) if governance_state != null else 0,
		"last_tax_day_index": last_tax_day_index,
		"last_minute_delta": last_minute_delta.duplicate(),
		"last_happiness_report": last_happiness_report.duplicate(),
		"last_riot_report": last_riot_report.duplicate(),
		"last_victory_defeat_report": last_victory_defeat_report.duplicate(),
		"event_log_count": event_log_messages.size(),
	}

func debug_stage8_5_claim_building(building: RefCounted) -> Dictionary:
	var before_resources: Dictionary = {}
	if resource_inventory != null and resource_inventory.has_method("get_all_resources"):
		before_resources = resource_inventory.call("get_all_resources")
	_handle_building_click(building, _find_building_node(building))
	var after_resources: Dictionary = {}
	if resource_inventory != null and resource_inventory.has_method("get_all_resources"):
		after_resources = resource_inventory.call("get_all_resources")
	var claimed_delta: Dictionary = {}
	for resource_type in after_resources.keys():
		claimed_delta[resource_type] = float(after_resources.get(resource_type, 0.0)) - float(before_resources.get(resource_type, 0.0))
	return claimed_delta


func _grid_cell_to_building_position(grid_cell: Vector2i) -> Vector2:
	return _grid_cell_to_root_position(grid_cell, buildings_root)


func _get_building_position_for_root(building: RefCounted, target_root: Node2D) -> Vector2:
	return _grid_cell_to_root_position(building.position, target_root)


func _grid_cell_to_root_position(grid_cell: Vector2i, target_root: Node2D) -> Vector2:
	var map_cell: Vector2i = grid_cell + (map_read_result.get("cell_offset", Vector2i.ZERO) as Vector2i)
	var global_position := ground_layer.to_global(ground_layer.map_to_local(map_cell))
	return target_root.to_local(global_position)


func _get_building_node_name(building: RefCounted) -> String:
	return "%s_%d_%d" % [MapTypes.get_building_label(int(building.building_type)).replace(" ", ""), building.position.x, building.position.y]


func _print_initial_building_summary(spawner: RefCounted) -> void:
	var counts := _count_buildings(initial_buildings)
	print(
		"stage4 initial buildings | total=", initial_buildings.size(),
		" castle=", int(counts.get(MapTypes.BuildingType.TOWN_CENTER, 0)),
		" lumber_camp=", int(counts.get(MapTypes.BuildingType.LUMBER_CAMP, 0)),
		" quarry=", int(counts.get(MapTypes.BuildingType.QUARRY, 0)),
		" farm=", int(counts.get(MapTypes.BuildingType.FARM, 0)),
		" seed=", INITIAL_BUILDING_SEED
	)
	for building in initial_buildings:
		print(
			"stage4 building | type=", MapTypes.get_building_label(int(building.building_type)),
			" cell=", building.position,
			" linked_region_id=", int(building.linked_region_id),
			" resource=", building.resource_type
		)
	for warning in spawner.last_spawn_warnings:
		push_warning("stage4 initial building skipped: %s" % warning)


func _print_villager_summary() -> void:
	var idle_count := 0
	var moving_count := 0
	var working_count := 0
	for state_name in villager_states.values():
		match state_name:
			&"idle":
				idle_count += 1
			&"moving":
				moving_count += 1
			&"working":
				working_count += 1
	print(
		"stage6 villager routes | total=", villager_states.size(),
		" idle=", idle_count,
		" moving=", moving_count,
		" working=", working_count
	)


func _count_buildings(buildings: Array) -> Dictionary:
	var counts: Dictionary = {}
	for building in buildings:
		var building_type: int = int(building.building_type)
		counts[building_type] = int(counts.get(building_type, 0)) + 1
	return counts


func _print_map_summary(read_result: Dictionary, regions: Dictionary, scanner: RefCounted) -> void:
	var counts: Dictionary = read_result["terrain_counts"]
	var used_rect: Rect2i = read_result["used_rect"]
	var decor_cells := decor_layer.get_used_cells().size()
	var forest_regions: Array = regions.get(MapTypes.TerrainType.FOREST, [])
	var stone_regions: Array = regions.get(MapTypes.TerrainType.STONE, [])
	print(
		"stage3 demo map read ok | size=", used_rect.size.x, "x", used_rect.size.y,
		" offset=", used_rect.position,
		" ground_cells=", int(read_result["ground_cells_read"]),
		" resource_cells=", int(read_result["resource_cells_read"]),
		" decor_cells_ignored=", decor_cells
	)
	print(
		"stage3 terrain counts | town_center=", _get_count(counts, MapTypes.TerrainType.TOWN_CENTER),
		" forest=", _get_count(counts, MapTypes.TerrainType.FOREST),
		" stone=", _get_count(counts, MapTypes.TerrainType.STONE),
		" plain=", _get_count(counts, MapTypes.TerrainType.PLAIN),
		" empty=", _get_count(counts, MapTypes.TerrainType.EMPTY),
		" road=", _get_count(counts, MapTypes.TerrainType.ROAD),
		" water=", _get_count(counts, MapTypes.TerrainType.WATER),
		" mountain=", _get_count(counts, MapTypes.TerrainType.MOUNTAIN)
	)
	print(
		"stage3 resource regions | forest=", forest_regions.size(),
		" forest_area=", scanner.get_total_area(forest_regions),
		" stone=", stone_regions.size(),
		" stone_area=", scanner.get_total_area(stone_regions)
	)
	_print_region_details("stage3 forest region", forest_regions)
	_print_region_details("stage3 stone region", stone_regions)
	_print_region_details("stage3 plain area", farmable_regions)
	print(
		"stage3 farmable terrain | plain_cells=", _get_count(counts, MapTypes.TerrainType.PLAIN),
		" plain_areas=", farmable_regions.size(),
		" farmable_cells=", scanner.get_total_area(farmable_regions)
	)


func _print_region_details(label: String, regions: Array) -> void:
	for region in regions:
		print(
			label,
			" | id=", int(region.region_id),
			" terrain=", MapTypes.get_terrain_label(int(region.terrain_type)),
			" area=", int(region.area),
			" adjacent_buildable_cells=", region.get_buildable_cell_count(),
			" farmable_cells=", region.get_farmable_cell_count()
		)


func _get_count(counts: Dictionary, terrain_type: int) -> int:
	return int(counts.get(terrain_type, 0))


func _get_region_count(regions: Dictionary, terrain_type: int) -> int:
	return (regions.get(terrain_type, []) as Array).size()


func _on_villager_state_changed(villager: Node2D, state_name: StringName) -> void:
	villager_states[villager] = state_name
	print("stage6 villager state | name=", villager.name, " state=", state_name)
