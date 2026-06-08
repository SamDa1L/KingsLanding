extends Node2D

const DemoMapReaderScript := preload("res://scripts/demo/DemoMapReader.gd")
const ResourceRegionScannerScript := preload("res://scripts/map/ResourceRegionScanner.gd")
const InitialBuildingSpawnerScript := preload("res://scripts/buildings/InitialBuildingSpawner.gd")
const BuildingPlacementControllerScript := preload("res://scripts/placement/BuildingPlacementController.gd")
const BuildingFootprintRulesScript := preload("res://scripts/buildings/BuildingFootprintRules.gd")
const ProductionCalculatorScript := preload("res://scripts/economy/ProductionCalculator.gd")
const ResourceDepletionStateScript := preload("res://scripts/resources/ResourceDepletionState.gd")
const GeneratedTileDataScript := preload("res://scripts/mapgen/GeneratedTileData.gd")
const TileRenderDefinitionScript := preload("res://scripts/mapgen/TileRenderDefinition.gd")
const GovernanceStateScript := preload("res://scripts/governance/GovernanceState.gd")
const TaxSystemScript := preload("res://scripts/governance/TaxSystem.gd")
const HappinessSystemScript := preload("res://scripts/governance/HappinessSystem.gd")
const RiotSystemScript := preload("res://scripts/governance/RiotSystem.gd")
const VictoryDefeatSystemScript := preload("res://scripts/governance/VictoryDefeatSystem.gd")
const VILLAGER_SCENE := preload("res://scenes/characters/villagersPawn/Pawn.tscn")
const BUILDING_HOVER_OUTLINE_SHADER := preload("res://assets/shaders/building_hover_outline.gdshader")
const BUILDING_HOVER_OUTLINE_ROOT_NAME := "HoverOutlineRoot"
const BUILDING_HOVER_OUTLINE_Z_INDEX := 2
const VILLAGER_ROUTE_POINT_NAME := "VillagerPoint"

const CASTLE_SCENE := preload("res://scenes/buildings/Castle/Castle.tscn")
const LUMBER_CAMP_SCENE := preload("res://scenes/buildings/TreeHouse/TreeLoggingHouse.tscn")
const QUARRY_SCENE := preload("res://scenes/buildings/StoneHouse/StoneQuarry.tscn")
const FARM_SCENE := preload("res://scenes/buildings/Farm/Farm.tscn")
const HOUSE_SCENE := preload("res://scenes/buildings/House/PawnHouse.tscn")
const INITIAL_BUILDING_SEED := 20260523
const HOME_EXIT_OFFSET := Vector2(0, 40)
const WORK_ENTRY_OFFSET := Vector2(0, 36)
const VILLAGER_START_DELAY_STEP := 1.2
const IDLE_VILLAGER_START_DELAY_STEP := 0.35
const INITIAL_POPULATION := 3
const CASTLE_POPULATION_CAPACITY := INITIAL_POPULATION
const CASTLE_INITIAL_VILLAGER_WANDER_BOUNDS_SIZE := Vector2(192, 192)
const CASTLE_INITIAL_VILLAGER_WANDER_REACH_RADIUS := 20
const CASTLE_INITIAL_VILLAGER_WANDER_PREFERRED_RADIUS := 14
const PLACEMENT_PREVIEW_SIZE := Vector2(56, 56)
const PLACEMENT_VALID_COLOR := Color(0.2, 0.95, 0.3, 0.42)
const PLACEMENT_INVALID_COLOR := Color(1.0, 0.18, 0.12, 0.42)
const HOUSE_POPULATION_CAPACITY := 5
const IDLE_VILLAGER_WANDER_RADIUS := 96.0
const CAMERA_MIN_ZOOM := 0.5
const CAMERA_MAX_ZOOM := 2.0
const CAMERA_ZOOM_STEP := 0.125
const GAME_WORLD_VIEWPORT_RIGHT := 922.0
const GAME_WORLD_VIEWPORT_BOTTOM := 720.0
const HAPPINESS_PANEL_TOP := 236.0
const HAPPINESS_PANEL_HEIGHT := 84.0
const PLACEMENT_PANEL_HEIGHT := 372.0
const WORKER_POPUP_MARGIN := 8.0
const WORKER_POPUP_Y_OFFSET := 12.0
const VILLAGER_NAVIGATION_TERRAIN_MISS := -1
const VILLAGER_PATH_RETRY_COUNT := 3
const RESOURCE_TASK_IDLE := &"idle"
const RESOURCE_TASK_GOING_TO_RESOURCE := &"going_to_resource"
const RESOURCE_TASK_COLLECTING := &"collecting"
const RESOURCE_TASK_RETURNING_TO_BUILDING := &"returning_to_building"
const RESOURCE_TASK_DELIVERING := &"delivering"
const RESOURCE_TASK_WAITING_FOR_STORAGE := &"waiting_for_storage"
const RESOURCE_TASK_RESTING := &"resting"
const RESOURCE_TASK_FAILED := &"failed"
const RESOURCE_TASK_CARRY_AMOUNT := 5.0
const RESOURCE_TASK_DEFAULT_SHIFT_MINUTES := 90.0

@export var enable_console_debug_logs: bool = false
@export var spawn_initial_production_buildings: bool = false

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
@onready var worker_control_panel: PanelContainer = $UIRoot/PlacementPanel/VBoxContainer/WorkerControlPanel
@onready var worker_status_label: Label = $UIRoot/PlacementPanel/VBoxContainer/WorkerControlPanel/VBoxContainer/WorkerStatusLabel
@onready var worker_minus_button: Button = $UIRoot/PlacementPanel/VBoxContainer/WorkerControlPanel/VBoxContainer/HBoxContainer/WorkerMinusButton
@onready var worker_count_label: Label = $UIRoot/PlacementPanel/VBoxContainer/WorkerControlPanel/VBoxContainer/HBoxContainer/WorkerCountLabel
@onready var worker_plus_button: Button = $UIRoot/PlacementPanel/VBoxContainer/WorkerControlPanel/VBoxContainer/HBoxContainer/WorkerPlusButton
@onready var harvest_button: Button = $UIRoot/PlacementPanel/VBoxContainer/HarvestButton
@onready var worker_popup_panel: PanelContainer = $UIRoot/WorkerPopupPanel
@onready var worker_popup_status_label: Label = $UIRoot/WorkerPopupPanel/MarginContainer/VBoxContainer/WorkerPopupStatusLabel
@onready var worker_popup_minus_button: Button = $UIRoot/WorkerPopupPanel/MarginContainer/VBoxContainer/HBoxContainer/WorkerPopupMinusButton
@onready var worker_popup_count_label: Label = $UIRoot/WorkerPopupPanel/MarginContainer/VBoxContainer/HBoxContainer/WorkerPopupCountLabel
@onready var worker_popup_plus_button: Button = $UIRoot/WorkerPopupPanel/MarginContainer/VBoxContainer/HBoxContainer/WorkerPopupPlusButton
@onready var build_cost_tooltip_panel: PanelContainer = $UIRoot/BuildCostTooltipPanel
@onready var build_cost_tooltip_title_label: Label = $UIRoot/BuildCostTooltipPanel/MarginContainer/VBoxContainer/TitleLabel
@onready var build_cost_tooltip_cost_label: Label = $UIRoot/BuildCostTooltipPanel/MarginContainer/VBoxContainer/CostLabel
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
@onready var riot_panel: PanelContainer = $UIRoot/RiotPanel
@onready var victory_panel: PanelContainer = $UIRoot/VictoryPanel
@onready var hud_panel: PanelContainer = $UIRoot/HudPanel
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
var resource_depletion_state: RefCounted = null
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
var hovered_building_node: Node2D = null
var last_collection_message: String = ""
var is_camera_dragging: bool = false
var camera_drag_last_mouse: Vector2 = Vector2.ZERO
var worker_assignment_rng := RandomNumberGenerator.new()
var villager_assignments: Dictionary = {}
var worker_resource_tasks: Dictionary = {}
var _is_syncing_population_state: bool = false
var pending_house_villager_spawn_contexts: Array[Dictionary] = []


func _ready() -> void:
	worker_assignment_rng.seed = INITIAL_BUILDING_SEED
	if get_viewport() != null and not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.connect(_on_viewport_size_changed)
	if main_camera != null:
		main_camera.make_current()
	_setup_economy_systems()
	_read_demo_map()
	_setup_placement_overlay()
	_setup_placement_ui()
	_setup_economy_ui()
	_setup_food_hover_ui()
	_setup_time_control_ui()
	_setup_tax_ui()
	_setup_happiness_ui()
	_setup_riot_ui()
	_setup_victory_ui()
	_update_placement_overlay()
	_update_economy_ui()
	_update_stage14_hud()
	_apply_ui_layout()
	_clamp_camera_to_game_viewport()


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
		happiness_panel.offset_top = HAPPINESS_PANEL_TOP
		happiness_panel.offset_bottom = HAPPINESS_PANEL_TOP + HAPPINESS_PANEL_HEIGHT
	if placement_panel != null:
		placement_panel.anchor_left = 1.0
		placement_panel.anchor_right = 1.0
		placement_panel.offset_left = -352.0
		placement_panel.offset_right = -16.0
		placement_panel.offset_top = viewport_size.y - PLACEMENT_PANEL_HEIGHT
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
		happiness_status_label.custom_minimum_size = Vector2(304, 64)
	var showing_production_menu := not placement_mode_active and _is_selected_building_manageable_production()
	if placement_status_label != null:
		placement_status_label.custom_minimum_size = Vector2(304, 118) if showing_production_menu else Vector2(304, 42)
	if worker_control_panel != null:
		worker_control_panel.custom_minimum_size = Vector2(304, 86)
	if worker_status_label != null:
		worker_status_label.custom_minimum_size = Vector2(292, 24)
	if worker_count_label != null:
		worker_count_label.custom_minimum_size = Vector2(172, 28)
	if worker_minus_button != null:
		worker_minus_button.custom_minimum_size = Vector2(56, 36)
	if worker_plus_button != null:
		worker_plus_button.custom_minimum_size = Vector2(56, 36)
	if worker_popup_panel != null:
		worker_popup_panel.custom_minimum_size = Vector2(236, 78)
	if worker_popup_status_label != null:
		worker_popup_status_label.custom_minimum_size = Vector2(200, 24)
	if worker_popup_count_label != null:
		worker_popup_count_label.custom_minimum_size = Vector2(120, 28)
	if worker_popup_minus_button != null:
		worker_popup_minus_button.custom_minimum_size = Vector2(44, 34)
	if worker_popup_plus_button != null:
		worker_popup_plus_button.custom_minimum_size = Vector2(44, 34)
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


func _process(delta: float) -> void:
	_tick_worker_resource_tasks(_get_scaled_game_minutes(delta))
	if placement_mode_active:
		_update_placement_hover()
	else:
		_update_resource_hover_hint()
	_update_camera_drag()
	_position_worker_popup_panel()


func _handle_camera_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			if _is_pointer_over_worker_popup():
				is_camera_dragging = false
				return
			if placement_mode_active:
				is_camera_dragging = false
				return
			if mouse_button.pressed:
				if _is_pointer_inside_game_viewport():
					is_camera_dragging = true
					camera_drag_last_mouse = get_viewport().get_mouse_position()
			elif is_camera_dragging:
				is_camera_dragging = false
			return
		if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_button.pressed:
			if _is_pointer_inside_game_viewport():
				_adjust_camera_zoom(1.0 + CAMERA_ZOOM_STEP)
				get_viewport().set_input_as_handled()
		elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_button.pressed:
			if _is_pointer_inside_game_viewport():
				_adjust_camera_zoom(1.0 - CAMERA_ZOOM_STEP)
				get_viewport().set_input_as_handled()


func _update_camera_drag() -> void:
	if not is_camera_dragging or main_camera == null:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		is_camera_dragging = false
		return
	if placement_mode_active:
		is_camera_dragging = false
		return
	var current_mouse := get_viewport().get_mouse_position()
	var delta := current_mouse - camera_drag_last_mouse
	camera_drag_last_mouse = current_mouse
	if is_equal_approx(delta.length(), 0.0):
		return
	var world_delta := -delta / main_camera.zoom.x
	main_camera.global_position += world_delta
	_clamp_camera_to_game_viewport()


func _adjust_camera_zoom(multiplier: float) -> void:
	if main_camera == null:
		return
	var next_zoom := clampf(main_camera.zoom.x * multiplier, CAMERA_MIN_ZOOM, CAMERA_MAX_ZOOM)
	if is_equal_approx(next_zoom, main_camera.zoom.x):
		return
	var mouse_world_before := main_camera.get_global_mouse_position()
	main_camera.zoom = Vector2(next_zoom, next_zoom)
	var mouse_world_after := main_camera.get_global_mouse_position()
	main_camera.global_position += mouse_world_before - mouse_world_after
	_clamp_camera_to_game_viewport()


func _clamp_camera_to_game_viewport() -> void:
	if main_camera == null:
		return
	return


func _is_pointer_inside_game_viewport() -> bool:
	var mouse_pos := get_viewport().get_mouse_position()
	return _get_game_viewport_rect().has_point(mouse_pos)


func _get_game_viewport_rect() -> Rect2:
	var viewport_size := get_viewport_rect().size
	var right_edge := minf(GAME_WORLD_VIEWPORT_RIGHT, viewport_size.x)
	var divider := get_node_or_null("UIRoot/ViewportDivider") as ColorRect
	if divider != null:
		right_edge = clampf(divider.offset_left, 0.0, viewport_size.x)
	return Rect2(Vector2.ZERO, Vector2(right_edge, viewport_size.y))


func _on_viewport_size_changed() -> void:
	_apply_ui_layout()
	_clamp_camera_to_game_viewport()


func _setup_economy_systems() -> void:
	production_calculator = ProductionCalculatorScript.new()
	resource_depletion_state = ResourceDepletionStateScript.new()
	tax_system = TaxSystemScript.new()
	happiness_system = HappinessSystemScript.new()
	riot_system = RiotSystemScript.new()
	victory_defeat_system = VictoryDefeatSystemScript.new()
	governance_state = GovernanceStateScript.new()
	governance_state.set_population(INITIAL_POPULATION)
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


func _setup_food_hover_ui() -> void:
	if top_resource_bar != null:
		top_resource_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	if food_label != null:
		food_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_update_food_tooltip()


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
	if _is_game_time_paused():
		return "时间：%s / 暂停中" % time_text
	return "时间：%s" % time_text


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
	var idle_population: int = max(population - _get_assigned_worker_total(), 0)
	if population_label != null:
		population_label.text = "人口 %d / 空闲 %d" % [population, idle_population]
	if population_cap_label != null:
		population_cap_label.text = "上限 %d" % _get_population_cap()
	if gold_label != null:
		gold_label.text = "金币 %d" % int(float(resources.get(MapTypes.RESOURCE_GOLD, 0.0)))
	if food_label != null:
		food_label.text = "食物 %d" % int(float(resources.get(MapTypes.RESOURCE_FOOD, 0.0)))
		_update_food_tooltip()
	if wood_label != null:
		wood_label.text = "木头 %d" % int(float(resources.get(MapTypes.RESOURCE_WOOD, 0.0)))
	if stone_label != null:
		stone_label.text = "石材 %d" % int(float(resources.get(MapTypes.RESOURCE_STONE, 0.0)))


func _update_food_tooltip() -> void:
	if food_label == null:
		return
	var food_output_per_hour: float = _get_food_output_per_minute() * 60.0
	var food_consumption_per_hour: float = 0.0
	if production_calculator != null and governance_state != null:
		food_consumption_per_hour = production_calculator.get_food_consumption_per_minute(governance_state.population) * 60.0
	food_label.tooltip_text = "食物产出/小时 %.1f\n食物消耗/小时 %.1f\n供给：%s" % [
		food_output_per_hour,
		food_consumption_per_hour,
		_get_food_supply_status_text(),
	]


func _get_food_output_per_minute() -> float:
	if production_calculator == null:
		return 0.0
	var regions_by_id: Dictionary = _get_regions_by_id()
	var total_food: float = 0.0
	for building in initial_buildings:
		if building == null or not building.is_active:
			continue
		var present_workers := _get_present_workers_for_building(building)
		var building_output: Dictionary = production_calculator.get_building_output_per_minute_with_present_workers(building, regions_by_id, present_workers)
		total_food += float(building_output.get(MapTypes.RESOURCE_FOOD, 0.0))
	return total_food


func _get_food_supply_status_text() -> String:
	if happiness_system == null or governance_state == null:
		return "未知"
	var report: Dictionary = happiness_system.build_daily_report(governance_state, _get_resource_inventory_snapshot(), _get_last_riot_penalty())
	return str(report.get("food_status", "未知"))


func _get_stage14_hud_text() -> String:
	var time_text := "未知"
	if game_clock != null and game_clock.has_method("get_time_text"):
		time_text = str(game_clock.call("get_time_text"))
	var day_text := "第 %d 天" % _get_current_day_count()
	var speed_text := _get_current_speed_label()
	var pause_text := "暂停中" if _is_game_time_paused() else "运行中"
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
	var castle_capacity := 0
	var house_count := 0
	for building in initial_buildings:
		if building == null:
			continue
		match int(building.building_type):
			MapTypes.BuildingType.TOWN_CENTER:
				castle_capacity += CASTLE_POPULATION_CAPACITY
			MapTypes.BuildingType.HOUSE:
				house_count += 1
	var house_capacity := castle_capacity + house_count * HOUSE_POPULATION_CAPACITY
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


func _get_scaled_game_minutes(delta: float) -> float:
	if delta <= 0.0:
		return 0.0
	if game_clock != null and game_clock.has_method("get_scaled_delta") and game_clock.has_method("get_minutes_per_second"):
		return float(game_clock.call("get_scaled_delta", delta)) * float(game_clock.call("get_minutes_per_second"))
	if _is_game_time_paused():
		return 0.0
	return delta


func _get_starting_resources() -> Dictionary:
	return {
		MapTypes.RESOURCE_FOOD: 40.0,
		MapTypes.RESOURCE_WOOD: 36.0,
		MapTypes.RESOURCE_STONE: 28.0,
		MapTypes.RESOURCE_GOLD: 24.0,
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
	initial_buildings = spawner.spawn_initial_buildings(
		grid,
		resource_regions,
		farmable_regions,
		INITIAL_BUILDING_SEED,
		spawn_initial_production_buildings
	)
	for building in initial_buildings:
		_register_occupied_cells_for_building(building)
		_instantiate_building_visual(building)
		_clear_building_footprint_resource_visuals(building)
		_append_initial_building_event(building)
	_initialize_worker_assignments()
	_sync_villager_population_to_assignments()
	_print_initial_building_summary(spawner)
	_print_villager_summary()


func _clear_initial_building_nodes() -> void:
	selected_building_data = null
	selected_building_node = null
	hovered_building_node = null
	if worker_popup_panel != null:
		worker_popup_panel.visible = false
	for child in buildings_root.get_children():
		child.queue_free()

func _clear_villager_nodes() -> void:
	for child in characters_root.get_children():
		child.queue_free()
	villager_states.clear()
	villager_assignments.clear()
	worker_resource_tasks.clear()


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
	_ensure_building_hover_outline_node(building_node)
	_ensure_building_click_area(building_node, building)
	building_node.position = _grid_cell_to_building_position(building.position) - _get_building_placement_anchor_offset(building_node)
	buildings_root.add_child(building_node)
	_update_building_visual_state(building, building_node)
	return building_node

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
	villager.call(
		"setup_route",
		home_position,
		work_position,
		float(index) * VILLAGER_START_DELAY_STEP,
		Callable(self, "_build_villager_route_points")
	)
	villager_states[villager] = villager.call("get_state_name")
	villager_assignments[villager] = work_building
	_start_or_clear_worker_resource_task(villager, work_building)
	if enable_console_debug_logs:
		print(
			"stage6 villager route | name=", villager.name,
			" work=", MapTypes.get_building_label(int(work_building.building_type)),
			" home=", home_position,
			" work_pos=", work_position
		)


func _spawn_idle_villager(index: int, anchor_position: Vector2, wander_bounds: Rect2) -> void:
	var villager := VILLAGER_SCENE.instantiate() as Node2D
	if villager == null:
		push_warning("Failed to instantiate idle villager scene.")
		return
	if not villager.has_method("setup_idle_wander"):
		push_warning("Villager scene does not expose setup_idle_wander().")
		villager.queue_free()
		return

	villager.name = "VillagerIdle%d" % index
	villager.z_index = 50
	characters_root.add_child(villager)
	if villager.has_signal("state_changed"):
		villager.connect("state_changed", Callable(self, "_on_villager_state_changed"))
	villager.call(
		"setup_idle_wander",
		anchor_position,
		wander_bounds,
		float(index) * IDLE_VILLAGER_START_DELAY_STEP,
		IDLE_VILLAGER_WANDER_RADIUS,
		Callable(self, "_build_villager_route_points"),
		Callable(self, "_pick_villager_wander_target_position")
	)
	villager_states[villager] = villager.call("get_state_name")
	villager_assignments[villager] = null


func _initialize_worker_assignments() -> void:
	_assign_workers_to_production_buildings()
	_sync_household_count()


func _sync_population_dependent_state() -> void:
	if _is_syncing_population_state:
		return
	_is_syncing_population_state = true
	_reconcile_worker_assignments_to_population()
	_sync_household_count()
	_sync_villager_population_to_assignments()
	_update_top_resource_bar()
	_update_economy_ui()
	_update_worker_control_ui()
	_refresh_stage14_hud()
	_is_syncing_population_state = false


func _sync_household_count() -> void:
	if governance_state == null:
		return
	var house_count := 0
	for building in initial_buildings:
		if building != null and int(building.building_type) == MapTypes.BuildingType.HOUSE:
			house_count += 1
	governance_state.households = house_count


func _assign_workers_to_production_buildings() -> void:
	var production_buildings := _get_production_buildings()
	if production_buildings.is_empty():
		return

	for building in production_buildings:
		if building != null and building.has_method("set_worker_count"):
			building.call("set_worker_count", 0)

	var population := 0
	if governance_state != null:
		population = int(governance_state.population)
	var remaining_workers: int = max(population, 0)
	if remaining_workers <= 0:
		return

	var shuffled_buildings := production_buildings.duplicate()
	_shuffle_array_in_place(shuffled_buildings)

	var assigned_any := true
	while remaining_workers > 0 and assigned_any:
		assigned_any = false
		for building in shuffled_buildings:
			if remaining_workers <= 0:
				break
			if building == null or not building.has_method("get_worker_count") or not building.has_method("get_worker_capacity"):
				continue
			var worker_count := int(building.call("get_worker_count"))
			var worker_capacity := int(building.call("get_worker_capacity"))
			if worker_count >= worker_capacity:
				continue
			building.call("add_workers", 1)
			remaining_workers -= 1
			assigned_any = true


func _reconcile_worker_assignments_to_population() -> void:
	var production_buildings := _get_production_buildings()
	if production_buildings.is_empty():
		return
	var allowed_workers := int(governance_state.population) if governance_state != null else 0
	allowed_workers = max(allowed_workers, 0)
	var assigned_workers := _get_assigned_worker_total()
	if assigned_workers <= allowed_workers:
		return
	var overflow := assigned_workers - allowed_workers
	for building in production_buildings:
		if overflow <= 0:
			break
		if building == null or not building.has_method("get_worker_count"):
			continue
		var current_count := int(building.call("get_worker_count"))
		if current_count <= 0:
			continue
		var removable: int = mini(current_count, overflow)
		building.call("remove_workers", removable)
		overflow -= removable


func _rebuild_villager_population() -> void:
	_clear_villager_nodes()

	var home_building := _find_home_building()
	if home_building == null:
		push_warning("No castle or house available for villager population rebuild.")
		return

	var home_position := _get_building_route_point_for_root(home_building, characters_root, HOME_EXIT_OFFSET)
	var wander_bounds := _get_idle_villager_wander_bounds()

	var worker_index := 0
	for building in _get_production_buildings():
		if building == null:
			continue
		var worker_count := int(building.call("get_worker_count")) if building.has_method("get_worker_count") else 0
		if worker_count <= 0:
			continue
		var work_position := _get_building_route_point_for_root(building, characters_root, WORK_ENTRY_OFFSET)
		for local_index in range(worker_count):
			_spawn_villager_route(worker_index, home_position, work_position, building)
			worker_index += 1

	var assigned_workers := _get_assigned_worker_total()
	var idle_population: int = max(int(governance_state.population) - assigned_workers, 0) if governance_state != null else 0
	for idle_index in range(idle_population):
		_spawn_fallback_idle_villager(idle_index, wander_bounds)


func _sync_villager_population_to_assignments() -> void:
	var target_population := int(governance_state.population) if governance_state != null else 0
	target_population = max(target_population, 0)
	var current_population := characters_root.get_child_count() if characters_root != null else 0

	if current_population < target_population:
		_spawn_additional_idle_villagers(target_population - current_population)
	elif current_population > target_population:
		_remove_excess_villagers(current_population - target_population)

	_rebalance_villager_assignments()


func _spawn_additional_idle_villagers(count: int) -> void:
	if count <= 0:
		return
	var default_wander_bounds: Rect2 = _get_idle_villager_wander_bounds()
	var default_anchor_position: Vector2 = default_wander_bounds.get_center()
	var castle_spawn_context: Dictionary = _get_initial_castle_villager_spawn_context()
	var start_index := characters_root.get_child_count()
	for local_index in range(count):
		var villager_index: int = start_index + local_index
		var house_spawn_context: Dictionary = _consume_pending_house_villager_spawn_context()
		if not house_spawn_context.is_empty():
			_spawn_house_idle_villager(villager_index, house_spawn_context, default_anchor_position, default_wander_bounds)
		elif _should_spawn_initial_villager_near_castle(villager_index, castle_spawn_context):
			_spawn_initial_castle_idle_villager(villager_index, castle_spawn_context, default_anchor_position, default_wander_bounds)
		else:
			_spawn_fallback_idle_villager(villager_index, default_wander_bounds)


func _spawn_fallback_idle_villager(villager_index: int, fallback_wander_bounds: Rect2) -> void:
	_spawn_idle_villager(villager_index, fallback_wander_bounds.get_center(), fallback_wander_bounds)


func _consume_pending_house_villager_spawn_context() -> Dictionary:
	if pending_house_villager_spawn_contexts.is_empty():
		return {}
	var spawn_context: Dictionary = pending_house_villager_spawn_contexts.pop_front()
	return spawn_context


func _spawn_house_idle_villager(villager_index: int, house_spawn_context: Dictionary, default_anchor_position: Vector2, default_wander_bounds: Rect2) -> void:
	var anchor_position: Vector2 = house_spawn_context.get("anchor_position", default_anchor_position)
	var wander_bounds: Rect2 = house_spawn_context.get("wander_bounds", default_wander_bounds)
	_spawn_idle_villager(villager_index, anchor_position, wander_bounds)
	var villager: Node = characters_root.get_child(characters_root.get_child_count() - 1) if characters_root != null and characters_root.get_child_count() > 0 else null
	if villager == null or not is_instance_valid(villager):
		return
	villager.set_meta("home_building_cell", house_spawn_context.get("house_cell", Vector2i(-1, -1)))


func _spawn_idle_villager_for_house(villager_index: int, house_building: RefCounted, default_wander_bounds: Rect2) -> void:
	if house_building == null:
		_spawn_fallback_idle_villager(villager_index, default_wander_bounds)
		return
	var house_spawn_context: Dictionary = _build_house_villager_spawn_context(house_building)
	_spawn_house_idle_villager(villager_index, house_spawn_context, default_wander_bounds.get_center(), default_wander_bounds)


func _spawn_initial_castle_idle_villager(villager_index: int, castle_spawn_context: Dictionary, default_anchor_position: Vector2, default_wander_bounds: Rect2) -> void:
	var anchor_position: Vector2 = castle_spawn_context.get("anchor_position", default_anchor_position)
	var wander_bounds: Rect2 = castle_spawn_context.get("wander_bounds", default_wander_bounds)
	_spawn_idle_villager(villager_index, anchor_position, wander_bounds)
	var villager: Node = characters_root.get_child(characters_root.get_child_count() - 1) if characters_root != null and characters_root.get_child_count() > 0 else null
	if villager == null or not is_instance_valid(villager):
		return
	villager.set_meta("wander_rule", "castle_initial_grid")
	villager.set_meta("castle_cell", castle_spawn_context.get("castle_cell", Vector2i(-1, -1)))


func _get_initial_castle_villager_spawn_context() -> Dictionary:
	if characters_root == null:
		return {}
	var castle_building: RefCounted = _find_castle_building()
	if castle_building == null:
		return {}
	var anchor_position: Vector2 = _get_building_route_point_for_root(castle_building, characters_root, HOME_EXIT_OFFSET)
	var wander_bounds: Rect2 = Rect2(anchor_position - CASTLE_INITIAL_VILLAGER_WANDER_BOUNDS_SIZE * 0.5, CASTLE_INITIAL_VILLAGER_WANDER_BOUNDS_SIZE)
	return {
		"anchor_position": anchor_position,
		"wander_bounds": wander_bounds,
		"castle_cell": castle_building.position,
	}


func _build_house_villager_spawn_context(house_building: RefCounted) -> Dictionary:
	if house_building == null or characters_root == null:
		return {}
	var anchor_position: Vector2 = _get_building_route_point_for_root(house_building, characters_root, HOME_EXIT_OFFSET)
	var wander_bounds: Rect2 = Rect2(anchor_position - CASTLE_INITIAL_VILLAGER_WANDER_BOUNDS_SIZE * 0.5, CASTLE_INITIAL_VILLAGER_WANDER_BOUNDS_SIZE)
	return {
		"anchor_position": anchor_position,
		"wander_bounds": wander_bounds,
		"house_cell": house_building.position,
	}


func _should_spawn_initial_villager_near_castle(villager_index: int, castle_spawn_context: Dictionary) -> bool:
	return villager_index < INITIAL_POPULATION and not castle_spawn_context.is_empty()


func _remove_excess_villagers(count: int) -> void:
	if count <= 0:
		return
	var removable: Array[Node2D] = []
	for villager in _get_idle_villagers():
		removable.append(villager)
		if removable.size() >= count:
			break
	if removable.size() < count:
		for villager in _get_assigned_villagers():
			if removable.has(villager):
				continue
			removable.append(villager)
			if removable.size() >= count:
				break
	for villager in removable:
		_unregister_villager(villager)
		if villager.get_parent() == characters_root:
			characters_root.remove_child(villager)
		villager.queue_free()


func _rebalance_villager_assignments() -> void:
	var home_building := _find_home_building()
	if home_building == null:
		return
	var home_position := _get_building_route_point_for_root(home_building, characters_root, HOME_EXIT_OFFSET)
	var wander_bounds := _get_idle_villager_wander_bounds()
	var idle_pool := _get_idle_villagers()

	for building in _get_production_buildings():
		if building == null or not building.has_method("get_worker_count"):
			continue
		var desired_workers := int(building.call("get_worker_count"))
		var assigned_villagers := _get_villagers_for_building(building)
		var releasable_villagers := _get_releasable_villagers(assigned_villagers)
		while assigned_villagers.size() > desired_workers and not releasable_villagers.is_empty():
			var villager_to_idle := releasable_villagers.pop_back() as Node2D
			assigned_villagers.erase(villager_to_idle)
			_assign_villager_to_idle(villager_to_idle, wander_bounds)
			idle_pool.append(villager_to_idle)
		while assigned_villagers.size() < desired_workers and not idle_pool.is_empty():
			var villager_to_work := idle_pool.pop_back() as Node2D
			_assign_villager_to_building(villager_to_work, building, home_position)
			assigned_villagers.append(villager_to_work)

	for villager in idle_pool:
		_assign_villager_to_idle(villager, wander_bounds)


func _get_villager_assignment(villager: Node2D) -> RefCounted:
	if villager == null or not is_instance_valid(villager):
		return null
	return villager_assignments.get(villager, null)


func _get_idle_villagers() -> Array:
	var result: Array = []
	for villager in characters_root.get_children():
		if not (villager is Node2D):
			continue
		var villager_node := villager as Node2D
		if _get_villager_assignment(villager_node) == null:
			result.append(villager_node)
	return result


func _get_releasable_villagers(villagers: Array) -> Array:
	var result: Array = []
	for villager in villagers:
		if not (villager is Node2D):
			continue
		var villager_node := villager as Node2D
		if not is_instance_valid(villager_node):
			continue
		if villager_node.has_method("is_locked_to_work_cycle") and bool(villager_node.call("is_locked_to_work_cycle")):
			continue
		result.append(villager_node)
	return result


func _get_assigned_villagers() -> Array:
	var result: Array = []
	for villager in characters_root.get_children():
		if not (villager is Node2D):
			continue
		var villager_node := villager as Node2D
		if _get_villager_assignment(villager_node) != null:
			result.append(villager_node)
	return result


func _get_villagers_for_building(building: RefCounted) -> Array:
	var result: Array = []
	if building == null:
		return result
	for villager in characters_root.get_children():
		if not (villager is Node2D):
			continue
		var villager_node := villager as Node2D
		if villager_assignments.get(villager_node, null) == building:
			result.append(villager_node)
	return result


func _assign_villager_to_building(villager: Node2D, building: RefCounted, home_position: Vector2) -> void:
	if villager == null or not is_instance_valid(villager) or building == null:
		return
	var work_position := _get_building_route_point_for_root(building, characters_root, WORK_ENTRY_OFFSET)
	if villager.has_method("retarget_to_work"):
		villager.call("retarget_to_work", home_position, work_position, Callable(self, "_build_villager_route_points"))
	villager_assignments[villager] = building
	villager_states[villager] = villager.call("get_state_name") if villager.has_method("get_state_name") else &"unknown"
	_start_or_clear_worker_resource_task(villager, building)


func _assign_villager_to_idle(villager: Node2D, wander_bounds: Rect2) -> void:
	if villager == null or not is_instance_valid(villager):
		return
	_clear_worker_resource_task(villager)
	var wander_context: Dictionary = _get_villager_idle_wander_context(villager, wander_bounds)
	var anchor_position: Vector2 = wander_context.get("anchor_position", wander_bounds.get_center())
	var next_wander_bounds: Rect2 = wander_context.get("wander_bounds", wander_bounds)
	if villager.has_method("retarget_to_idle"):
		villager.call(
			"retarget_to_idle",
			anchor_position,
			next_wander_bounds,
			IDLE_VILLAGER_WANDER_RADIUS,
			Callable(self, "_build_villager_route_points"),
			Callable(self, "_pick_villager_wander_target_position")
		)
	villager_assignments[villager] = null
	villager_states[villager] = villager.call("get_state_name") if villager.has_method("get_state_name") else &"unknown"


func _get_villager_idle_wander_context(villager: Node2D, fallback_wander_bounds: Rect2) -> Dictionary:
	if villager == null or not is_instance_valid(villager):
		return _build_wander_context_from_bounds(fallback_wander_bounds)
	var home_cell_variant: Variant = villager.get_meta("home_building_cell", Vector2i(-1, -1))
	if typeof(home_cell_variant) == TYPE_VECTOR2I:
		var home_cell: Vector2i = home_cell_variant
		var home_building: RefCounted = _find_building_at_cell(MapTypes.BuildingType.HOUSE, home_cell)
		if home_building != null:
			return _build_wander_context_for_building(home_building)
	if str(villager.get_meta("wander_rule", "")) == "castle_initial_grid":
		var castle_cell_variant: Variant = villager.get_meta("castle_cell", Vector2i(-1, -1))
		if typeof(castle_cell_variant) == TYPE_VECTOR2I:
			var castle_building: RefCounted = _find_building_at_cell(MapTypes.BuildingType.TOWN_CENTER, castle_cell_variant)
			if castle_building != null:
				return _build_wander_context_for_building(castle_building)
		var fallback_castle: RefCounted = _find_castle_building()
		if fallback_castle != null:
			return _build_wander_context_for_building(fallback_castle)
	return _build_wander_context_from_bounds(fallback_wander_bounds)


func _build_wander_context_for_building(building: RefCounted) -> Dictionary:
	if building == null or characters_root == null:
		return _build_wander_context_from_bounds(_get_idle_villager_wander_bounds())
	var anchor_position: Vector2 = _get_building_route_point_for_root(building, characters_root, HOME_EXIT_OFFSET)
	var wander_bounds: Rect2 = Rect2(anchor_position - CASTLE_INITIAL_VILLAGER_WANDER_BOUNDS_SIZE * 0.5, CASTLE_INITIAL_VILLAGER_WANDER_BOUNDS_SIZE)
	return {
		"anchor_position": anchor_position,
		"wander_bounds": wander_bounds,
	}


func _build_wander_context_from_bounds(wander_bounds: Rect2) -> Dictionary:
	return {
		"anchor_position": wander_bounds.get_center(),
		"wander_bounds": wander_bounds,
	}


func _unregister_villager(villager: Node2D) -> void:
	if villager == null:
		return
	villager_assignments.erase(villager)
	villager_states.erase(villager)
	worker_resource_tasks.erase(villager)


func _get_assigned_worker_total() -> int:
	var total := 0
	for building in _get_production_buildings():
		if building == null or not building.has_method("get_worker_count"):
			continue
		total += int(building.call("get_worker_count"))
	return total


func _get_present_workers_for_building(building: RefCounted) -> int:
	if building == null:
		return 0
	var assigned_workers := _get_villagers_for_building(building)
	var present_workers := 0
	for villager in assigned_workers:
		if villager == null or not is_instance_valid(villager):
			continue
		if villager.has_method("is_at_worksite") and bool(villager.call("is_at_worksite")):
			present_workers += 1
	return present_workers


func _get_resting_workers_for_building(building: RefCounted) -> int:
	if building == null:
		return 0
	var assigned_workers := _get_villagers_for_building(building)
	var resting_workers := 0
	for villager in assigned_workers:
		if villager == null or not is_instance_valid(villager):
			continue
		if villager.has_method("is_resting") and bool(villager.call("is_resting")):
			resting_workers += 1
	return resting_workers


func _get_traveling_workers_for_building(building: RefCounted) -> int:
	if building == null:
		return 0
	var assigned_workers := _get_villagers_for_building(building)
	var traveling_workers := 0
	for villager in assigned_workers:
		if villager == null or not is_instance_valid(villager):
			continue
		if villager.has_method("is_at_worksite") and bool(villager.call("is_at_worksite")):
			continue
		if villager.has_method("is_resting") and bool(villager.call("is_resting")):
			continue
		traveling_workers += 1
	return traveling_workers


func _start_or_clear_worker_resource_task(villager: Node2D, building: RefCounted) -> void:
	if not _should_create_worker_resource_task_for_building(building):
		_clear_worker_resource_task(villager)
		return
	var target: Dictionary = _find_resource_collection_target_for_building(building, villager)
	if not bool(target.get("ok", false)):
		worker_resource_tasks[villager] = _build_failed_worker_resource_task(villager, building, str(target.get("reason", "无法找到资源采集目标。")))
		_update_worker_resource_task_visual_status(villager, worker_resource_tasks[villager])
		return
	var task: Dictionary = _build_worker_resource_task(villager, building, target)
	worker_resource_tasks[villager] = task
	_retarget_villager_to_resource_task(villager, task)


func _should_create_worker_resource_task_for_building(building: RefCounted) -> bool:
	if building == null:
		return false
	var resource_type: StringName = MapTypes.get_resource_name_for_building(int(building.building_type))
	return _is_depletable_resource_type(resource_type)


func _build_worker_resource_task(villager: Node2D, building: RefCounted, target: Dictionary) -> Dictionary:
	var target_work_cell: Vector2i = target.get("work_cell", Vector2i(-1, -1))
	var target_work_position: Vector2 = _get_resource_collection_work_position(target_work_cell)
	var building_delivery_position: Vector2 = _get_resource_collection_building_delivery_position(building)
	var collect_required_minutes: float = _get_resource_task_collect_required_minutes(building)
	return {
		"worker_node": villager,
		"building": building,
		"resource_type": StringName(str(target.get("resource_type", &""))),
		"target_resource_cell": target.get("resource_cell", Vector2i(-1, -1)),
		"target_work_cell": target_work_cell,
		"target_work_position": target_work_position,
		"building_delivery_position": building_delivery_position,
		"state": RESOURCE_TASK_GOING_TO_RESOURCE,
		"collect_elapsed_seconds": 0.0,
		"collect_required_seconds": collect_required_minutes,
		"collect_elapsed_minutes": 0.0,
		"collect_required_minutes": collect_required_minutes,
		"carried_amount": 0.0,
		"carry_amount_per_trip": RESOURCE_TASK_CARRY_AMOUNT,
		"delivered_amount": 0.0,
		"shift_elapsed_minutes": 0.0,
		"shift_required_minutes": RESOURCE_TASK_DEFAULT_SHIFT_MINUTES,
		"pending_rest_after_delivery": false,
		"shift_resting": false,
		"failure_reason": "",
	}


func _build_failed_worker_resource_task(villager: Node2D, building: RefCounted, reason: String) -> Dictionary:
	return {
		"worker_node": villager,
		"building": building,
		"resource_type": MapTypes.get_resource_name_for_building(int(building.building_type)) if building != null else &"",
		"target_resource_cell": Vector2i(-1, -1),
		"target_work_cell": Vector2i(-1, -1),
		"target_work_position": Vector2.ZERO,
		"building_delivery_position": Vector2.ZERO,
		"state": RESOURCE_TASK_FAILED,
		"collect_elapsed_seconds": 0.0,
		"collect_required_seconds": 0.0,
		"collect_elapsed_minutes": 0.0,
		"collect_required_minutes": 0.0,
		"carried_amount": 0.0,
		"carry_amount_per_trip": 0.0,
		"delivered_amount": 0.0,
		"shift_elapsed_minutes": 0.0,
		"shift_required_minutes": RESOURCE_TASK_DEFAULT_SHIFT_MINUTES,
		"pending_rest_after_delivery": false,
		"shift_resting": false,
		"failure_reason": reason,
	}


func _clear_worker_resource_task(villager: Node2D) -> void:
	if villager == null:
		return
	worker_resource_tasks.erase(villager)
	_clear_worker_resource_task_visual_status(villager)


func _retarget_villager_to_resource_task(villager: Node2D, task: Dictionary) -> void:
	if villager == null or not is_instance_valid(villager):
		return
	_update_villager_resource_task_targets(villager, task, true)
	villager_states[villager] = villager.call("get_state_name") if villager.has_method("get_state_name") else &"unknown"
	_sync_worker_resource_task_state(villager)


func _update_villager_resource_task_targets(villager: Node2D, task: Dictionary, restart_cycle: bool) -> void:
	if villager == null or not is_instance_valid(villager):
		return
	if villager.has_method("set_work_duration_minutes"):
		villager.call("set_work_duration_minutes", float(task.get("collect_required_minutes", 0.0)))
	var building_delivery_position: Vector2 = task.get("building_delivery_position", Vector2.ZERO)
	var target_work_position: Vector2 = task.get("target_work_position", Vector2.ZERO)
	if not restart_cycle and villager.has_method("update_work_cycle_targets"):
		villager.call("update_work_cycle_targets", building_delivery_position, target_work_position, Callable(self, "_build_villager_route_points"))
		return
	if villager.has_method("retarget_to_work"):
		villager.call("retarget_to_work", building_delivery_position, target_work_position, Callable(self, "_build_villager_route_points"))


func _get_resource_task_collect_required_minutes(building: RefCounted) -> float:
	if building == null or production_calculator == null:
		return 1.0
	if not production_calculator.has_method("get_single_worker_output_per_minute"):
		return 1.0
	var output_per_minute: float = float(production_calculator.call("get_single_worker_output_per_minute", int(building.building_type)))
	if output_per_minute <= 0.0:
		return 1.0
	return RESOURCE_TASK_CARRY_AMOUNT / output_per_minute


func _ensure_worker_resource_task_shift_fields(task: Dictionary) -> Dictionary:
	if not task.has("shift_elapsed_minutes"):
		task["shift_elapsed_minutes"] = 0.0
	if not task.has("shift_required_minutes"):
		task["shift_required_minutes"] = RESOURCE_TASK_DEFAULT_SHIFT_MINUTES
	if not task.has("pending_rest_after_delivery"):
		task["pending_rest_after_delivery"] = false
	if not task.has("shift_resting"):
		task["shift_resting"] = false
	return task


func _is_worker_resource_task_shift_active_state(task_state: StringName) -> bool:
	return task_state == RESOURCE_TASK_GOING_TO_RESOURCE \
		or task_state == RESOURCE_TASK_COLLECTING \
		or task_state == RESOURCE_TASK_RETURNING_TO_BUILDING \
		or task_state == RESOURCE_TASK_DELIVERING


func _advance_worker_resource_task_shift(villager: Node2D, task: Dictionary, delta_game_minutes: float) -> Dictionary:
	if delta_game_minutes <= 0.0 or bool(task.get("shift_resting", false)):
		return task
	if bool(task.get("pending_rest_after_delivery", false)):
		return task
	var task_state: StringName = StringName(str(task.get("state", RESOURCE_TASK_IDLE)))
	if not _is_worker_resource_task_shift_active_state(task_state):
		return task
	var shift_required_minutes: float = max(float(task.get("shift_required_minutes", RESOURCE_TASK_DEFAULT_SHIFT_MINUTES)), 0.0)
	if shift_required_minutes <= 0.0:
		return task
	var shift_elapsed_minutes: float = max(float(task.get("shift_elapsed_minutes", 0.0)), 0.0)
	shift_elapsed_minutes = minf(shift_elapsed_minutes + delta_game_minutes, shift_required_minutes)
	task["shift_elapsed_minutes"] = shift_elapsed_minutes
	if shift_elapsed_minutes < shift_required_minutes:
		return task
	task["pending_rest_after_delivery"] = true
	if task_state == RESOURCE_TASK_GOING_TO_RESOURCE or task_state == RESOURCE_TASK_COLLECTING:
		task["state"] = RESOURCE_TASK_RETURNING_TO_BUILDING
		_request_villager_return_to_building(villager)
	return task


func _should_worker_resource_task_rest_after_trip(task: Dictionary) -> bool:
	if bool(task.get("pending_rest_after_delivery", false)):
		return true
	var shift_required_minutes: float = max(float(task.get("shift_required_minutes", RESOURCE_TASK_DEFAULT_SHIFT_MINUTES)), 0.0)
	if shift_required_minutes <= 0.0:
		return false
	return max(float(task.get("shift_elapsed_minutes", 0.0)), 0.0) >= shift_required_minutes


func _finish_worker_resource_task_trip_prepare(villager: Node2D, task: Dictionary, should_rest: bool) -> Dictionary:
	if should_rest:
		task["state"] = RESOURCE_TASK_RESTING
		task["shift_resting"] = true
		task["pending_rest_after_delivery"] = false
		_update_villager_resource_task_targets(villager, task, false)
		return task
	task["state"] = RESOURCE_TASK_GOING_TO_RESOURCE
	task["shift_resting"] = false
	task["pending_rest_after_delivery"] = false
	_update_villager_resource_task_targets(villager, task, true)
	return task


func _tick_worker_resource_tasks(delta_game_minutes: float) -> void:
	if delta_game_minutes <= 0.0 or worker_resource_tasks.is_empty():
		return
	var villager_keys: Array = worker_resource_tasks.keys()
	for villager_variant in villager_keys:
		if not (villager_variant is Node2D):
			continue
		var villager := villager_variant as Node2D
		if villager == null or not is_instance_valid(villager):
			worker_resource_tasks.erase(villager)
			continue
		_tick_worker_resource_task(villager, delta_game_minutes)


func _tick_worker_resource_task(villager: Node2D, delta_game_minutes: float) -> void:
	if not worker_resource_tasks.has(villager):
		return
	var task: Dictionary = worker_resource_tasks.get(villager, {})
	var current_task_state: StringName = StringName(str(task.get("state", RESOURCE_TASK_IDLE)))
	if current_task_state == RESOURCE_TASK_FAILED:
		return
	if current_task_state == RESOURCE_TASK_WAITING_FOR_STORAGE:
		_tick_worker_resource_waiting_for_storage_task(villager, task)
		return
	task = _ensure_worker_resource_task_shift_fields(task)
	worker_resource_tasks[villager] = task
	_sync_worker_resource_task_state(villager)
	task = worker_resource_tasks.get(villager, {})
	task = _ensure_worker_resource_task_shift_fields(task)
	task = _advance_worker_resource_task_shift(villager, task, delta_game_minutes)
	worker_resource_tasks[villager] = task
	var task_state: StringName = StringName(str(task.get("state", RESOURCE_TASK_IDLE)))
	if task_state == RESOURCE_TASK_COLLECTING:
		_tick_worker_resource_collecting_task(villager, task, delta_game_minutes)
	elif task_state == RESOURCE_TASK_DELIVERING:
		_try_deliver_worker_resource_task(villager, task)


func _tick_worker_resource_waiting_for_storage_task(villager: Node2D, task: Dictionary) -> void:
	if not _can_worker_resource_task_deliver_to_storage(task):
		worker_resource_tasks[villager] = task
		_update_worker_resource_task_visual_status(villager, task)
		return
	task["state"] = RESOURCE_TASK_DELIVERING
	task["failure_reason"] = ""
	worker_resource_tasks[villager] = task
	_try_deliver_worker_resource_task(villager, task)


func _tick_worker_resource_collecting_task(villager: Node2D, task: Dictionary, delta_game_minutes: float) -> void:
	var required_minutes: float = max(float(task.get("collect_required_minutes", task.get("collect_required_seconds", 0.0))), 0.0)
	var elapsed_minutes: float = max(float(task.get("collect_elapsed_minutes", task.get("collect_elapsed_seconds", 0.0))), 0.0)
	var carry_amount_per_trip: float = max(float(task.get("carry_amount_per_trip", RESOURCE_TASK_CARRY_AMOUNT)), 0.0)
	var carried_amount: float = max(float(task.get("carried_amount", 0.0)), 0.0)
	if elapsed_minutes >= required_minutes or carried_amount >= carry_amount_per_trip:
		return
	if required_minutes <= 0.0 or carry_amount_per_trip <= 0.0:
		return
	var collect_delta_minutes: float = minf(delta_game_minutes, required_minutes - elapsed_minutes)
	var requested_amount: float = minf((carry_amount_per_trip / required_minutes) * collect_delta_minutes, carry_amount_per_trip - carried_amount)
	if requested_amount <= 0.0:
		return
	var consumed_amount: float = _consume_worker_resource_cell(task, requested_amount)
	if consumed_amount <= 0.0:
		_apply_worker_resource_target_depletion(task)
		if carried_amount <= 0.0:
			task = _try_switch_empty_worker_to_next_resource_target(villager, task, "采集失败：目标资源格已采空。")
		else:
			task["state"] = RESOURCE_TASK_FAILED
			task["failure_reason"] = "采集失败：目标资源格已采空。"
		worker_resource_tasks[villager] = task
		_update_worker_resource_task_visual_status(villager, task)
		return
	var actual_collect_delta_minutes: float = collect_delta_minutes * clampf(consumed_amount / requested_amount, 0.0, 1.0)
	elapsed_minutes = minf(elapsed_minutes + actual_collect_delta_minutes, required_minutes)
	carried_amount = minf(carried_amount + consumed_amount, carry_amount_per_trip)
	task["collect_elapsed_minutes"] = elapsed_minutes
	task["collect_elapsed_seconds"] = elapsed_minutes
	task["carried_amount"] = carried_amount
	worker_resource_tasks[villager] = task
	_apply_worker_resource_target_depletion(task)
	_update_worker_resource_task_visual_status(villager, task)
	if _is_worker_resource_target_depleted(task):
		task["collect_elapsed_minutes"] = required_minutes
		task["collect_elapsed_seconds"] = required_minutes
		task["state"] = RESOURCE_TASK_RETURNING_TO_BUILDING
		worker_resource_tasks[villager] = task
		_request_villager_return_to_building(villager)
		_update_worker_resource_task_visual_status(villager, task)


func _try_switch_empty_worker_to_next_resource_target(villager: Node2D, task: Dictionary, fallback_reason: String) -> Dictionary:
	if max(float(task.get("carried_amount", 0.0)), 0.0) > 0.0:
		task["state"] = RESOURCE_TASK_FAILED
		task["failure_reason"] = fallback_reason
		return task
	var building_variant: Variant = task.get("building", null)
	if not (building_variant is RefCounted):
		task["state"] = RESOURCE_TASK_FAILED
		task["failure_reason"] = "采集失败：缺少建筑数据。"
		return task
	var building: RefCounted = building_variant
	var resource_type: StringName = StringName(str(task.get("resource_type", &"")))
	var target: Dictionary = _find_resource_collection_target_for_building(building, villager)
	if not bool(target.get("ok", false)):
		task["state"] = RESOURCE_TASK_FAILED
		task["failure_reason"] = fallback_reason
		var region: RefCounted = _get_resource_region_for_building(building, _get_regions_by_id())
		_update_building_linked_resource_depleted_status(building, region, resource_type)
		return task
	_apply_resource_collection_target_to_task(task, target, building)
	_reset_worker_resource_task_collection_progress(task)
	task["state"] = RESOURCE_TASK_GOING_TO_RESOURCE
	task["failure_reason"] = ""
	task["pending_rest_after_delivery"] = false
	task["shift_resting"] = false
	_update_villager_resource_task_targets(villager, task, true)
	return task


func _limit_worker_resource_collect_amount_by_storage(villager: Node2D, task: Dictionary, requested_amount: float) -> float:
	if requested_amount <= 0.0:
		return 0.0
	var building_variant: Variant = task.get("building", null)
	if not (building_variant is RefCounted):
		return requested_amount
	var resource_type: StringName = StringName(str(task.get("resource_type", &"")))
	if resource_type == &"":
		return requested_amount
	var building: RefCounted = building_variant
	var available_amount: float = _get_building_available_storage_amount(building, resource_type)
	if is_inf(available_amount):
		return requested_amount
	var reserved_amount: float = _get_reserved_worker_resource_amount_for_building(building, resource_type, villager)
	var carried_amount: float = max(float(task.get("carried_amount", 0.0)), 0.0)
	var remaining_available_amount: float = max(available_amount - reserved_amount - carried_amount, 0.0)
	return minf(requested_amount, remaining_available_amount)


func _get_building_available_storage_amount(building: RefCounted, resource_type: StringName) -> float:
	if building == null or resource_type == &"":
		return INF
	if not building.has_method("get_storage_capacity") or not building.has_method("get_stored_amount"):
		return INF
	var capacity_amount: float = float(building.call("get_storage_capacity", resource_type))
	if capacity_amount <= 0.0:
		return 0.0
	var stored_amount: float = float(building.call("get_stored_amount", resource_type))
	return max(capacity_amount - stored_amount, 0.0)


func _get_reserved_worker_resource_amount_for_building(building: RefCounted, resource_type: StringName, excluded_villager: Node2D) -> float:
	var reserved_amount: float = 0.0
	for task_villager_variant in worker_resource_tasks.keys():
		if task_villager_variant == excluded_villager:
			continue
		var task_variant: Variant = worker_resource_tasks.get(task_villager_variant, {})
		if typeof(task_variant) != TYPE_DICTIONARY:
			continue
		var next_task: Dictionary = task_variant
		if next_task.get("building", null) != building:
			continue
		if StringName(str(next_task.get("resource_type", &""))) != resource_type:
			continue
		if StringName(str(next_task.get("state", RESOURCE_TASK_IDLE))) == RESOURCE_TASK_FAILED:
			continue
		reserved_amount += max(float(next_task.get("carried_amount", 0.0)), 0.0)
	return reserved_amount


func _consume_worker_resource_cell(task: Dictionary, amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var resource_cell: Vector2i = task.get("target_resource_cell", Vector2i(-1, -1))
	if resource_cell.x < 0:
		return 0.0
	var resource_type: StringName = StringName(str(task.get("resource_type", &"")))
	if resource_type == &"":
		return 0.0
	if resource_depletion_state == null or not resource_depletion_state.has_method("consume"):
		return amount
	return float(resource_depletion_state.call("consume", resource_cell, resource_type, amount))


func _apply_worker_resource_target_depletion(task: Dictionary) -> void:
	var resource_cell: Vector2i = task.get("target_resource_cell", Vector2i(-1, -1))
	if resource_cell.x < 0:
		return
	var resource_type: StringName = StringName(str(task.get("resource_type", &"")))
	if resource_type == &"" or resource_depletion_state == null or not resource_depletion_state.has_method("is_depleted"):
		return
	if not bool(resource_depletion_state.call("is_depleted", resource_cell, resource_type)):
		return
	var building_variant: Variant = task.get("building", null)
	if not (building_variant is RefCounted):
		return
	var building: RefCounted = building_variant
	var region: RefCounted = _get_resource_region_for_building(building, _get_regions_by_id())
	_apply_depleted_resource_cells_to_grid(region, resource_type)


func _is_worker_resource_target_depleted(task: Dictionary) -> bool:
	var resource_cell: Vector2i = task.get("target_resource_cell", Vector2i(-1, -1))
	if resource_cell.x < 0:
		return true
	var resource_type: StringName = StringName(str(task.get("resource_type", &"")))
	if resource_type == &"":
		return true
	if resource_depletion_state == null or not resource_depletion_state.has_method("is_depleted"):
		return false
	return bool(resource_depletion_state.call("is_depleted", resource_cell, resource_type))


func _request_villager_return_to_building(villager: Node2D) -> void:
	if villager == null or not is_instance_valid(villager):
		return
	if villager.has_method("force_return_home_from_work"):
		villager.call("force_return_home_from_work")


func _try_deliver_worker_resource_task(villager: Node2D, task: Dictionary) -> void:
	var carried_amount: float = float(task.get("carried_amount", 0.0))
	if carried_amount <= 0.0:
		worker_resource_tasks[villager] = task
		return
	var building_variant: Variant = task.get("building", null)
	if not (building_variant is RefCounted):
		task["state"] = RESOURCE_TASK_FAILED
		task["failure_reason"] = "交付失败：缺少建筑数据。"
		worker_resource_tasks[villager] = task
		return
	var building: RefCounted = building_variant
	var resource_type: StringName = StringName(str(task.get("resource_type", &"")))
	if resource_type == &"" or not building.has_method("add_to_storage"):
		task["state"] = RESOURCE_TASK_FAILED
		task["failure_reason"] = "交付失败：缺少资源类型或库存接口。"
		worker_resource_tasks[villager] = task
		return
	var accepted_amount: float = float(building.call("add_to_storage", resource_type, carried_amount))
	if accepted_amount <= 0.0:
		task = _set_worker_resource_task_waiting_for_storage(task)
		worker_resource_tasks[villager] = task
		_update_worker_resource_task_visual_status(villager, task)
		_update_building_visual_for_data(building)
		return
	task["carried_amount"] = max(carried_amount - accepted_amount, 0.0)
	task["delivered_amount"] = float(task.get("delivered_amount", 0.0)) + accepted_amount
	if float(task.get("carried_amount", 0.0)) <= 0.0:
		task = _prepare_worker_resource_task_for_next_trip(villager, task, building, resource_type)
	else:
		task = _set_worker_resource_task_waiting_for_storage(task)
	worker_resource_tasks[villager] = task
	_update_worker_resource_task_visual_status(villager, task)
	_update_building_visual_for_data(building)


func _set_worker_resource_task_waiting_for_storage(task: Dictionary) -> Dictionary:
	task = _ensure_worker_resource_task_shift_fields(task)
	task["state"] = RESOURCE_TASK_WAITING_FOR_STORAGE
	task["failure_reason"] = "等待清空建筑库存。"
	task["pending_rest_after_delivery"] = false
	return task


func _can_worker_resource_task_deliver_to_storage(task: Dictionary) -> bool:
	var building_variant: Variant = task.get("building", null)
	if not (building_variant is RefCounted):
		return false
	var resource_type: StringName = StringName(str(task.get("resource_type", &"")))
	if resource_type == &"":
		return false
	var available_amount: float = _get_building_available_storage_amount(building_variant, resource_type)
	return is_inf(available_amount) or available_amount > 0.0


func _prepare_worker_resource_task_for_next_trip(villager: Node2D, task: Dictionary, building: RefCounted, resource_type: StringName) -> Dictionary:
	task = _ensure_worker_resource_task_shift_fields(task)
	var should_rest: bool = _should_worker_resource_task_rest_after_trip(task)
	if _is_worker_resource_target_collectable(task):
		_reset_worker_resource_task_collection_progress(task)
		return _finish_worker_resource_task_trip_prepare(villager, task, should_rest)
	var target: Dictionary = _find_resource_collection_target_for_building(building, villager)
	if not bool(target.get("ok", false)):
		task["state"] = RESOURCE_TASK_FAILED
		task["failure_reason"] = str(target.get("reason", "附近资源已采尽。"))
		var region: RefCounted = _get_resource_region_for_building(building, _get_regions_by_id())
		_update_building_linked_resource_depleted_status(building, region, resource_type)
		return task
	_apply_resource_collection_target_to_task(task, target, building)
	_reset_worker_resource_task_collection_progress(task)
	return _finish_worker_resource_task_trip_prepare(villager, task, should_rest)


func _is_worker_resource_target_collectable(task: Dictionary) -> bool:
	var resource_cell: Vector2i = task.get("target_resource_cell", Vector2i(-1, -1))
	if resource_cell.x < 0:
		return false
	var resource_type: StringName = StringName(str(task.get("resource_type", &"")))
	var required_terrain: int = _get_required_resource_terrain_for_resource(resource_type)
	if required_terrain < 0:
		return false
	if not _is_collectable_resource_cell(resource_cell, required_terrain, resource_type):
		return false
	return _find_resource_collection_work_cell(resource_cell).x >= 0


func _apply_resource_collection_target_to_task(task: Dictionary, target: Dictionary, building: RefCounted) -> void:
	var target_work_cell: Vector2i = target.get("work_cell", Vector2i(-1, -1))
	task["resource_type"] = StringName(str(target.get("resource_type", task.get("resource_type", &""))))
	task["target_resource_cell"] = target.get("resource_cell", Vector2i(-1, -1))
	task["target_work_cell"] = target_work_cell
	task["target_work_position"] = _get_resource_collection_work_position(target_work_cell)
	task["building_delivery_position"] = _get_resource_collection_building_delivery_position(building)


func _reset_worker_resource_task_collection_progress(task: Dictionary) -> void:
	task["collect_elapsed_seconds"] = 0.0
	task["collect_elapsed_minutes"] = 0.0
	task["carried_amount"] = 0.0


func _get_resource_collection_work_position(work_cell: Vector2i) -> Vector2:
	if work_cell.x < 0:
		return Vector2.ZERO
	return _grid_cell_to_root_position(work_cell, characters_root)


func _get_resource_collection_building_delivery_position(building: RefCounted) -> Vector2:
	if building == null:
		return Vector2.ZERO
	return _get_building_route_point_for_root(building, characters_root, WORK_ENTRY_OFFSET)


func _sync_worker_resource_task_state(villager: Node2D) -> void:
	if villager == null or not worker_resource_tasks.has(villager):
		return
	var task: Dictionary = worker_resource_tasks.get(villager, {})
	var current_task_state: StringName = StringName(str(task.get("state", RESOURCE_TASK_IDLE)))
	if current_task_state == RESOURCE_TASK_FAILED:
		return
	if current_task_state == RESOURCE_TASK_WAITING_FOR_STORAGE:
		if _can_worker_resource_task_deliver_to_storage(task):
			task["state"] = RESOURCE_TASK_DELIVERING
			task["failure_reason"] = ""
		else:
			worker_resource_tasks[villager] = task
			_update_worker_resource_task_visual_status(villager, task)
			return
	task = _ensure_worker_resource_task_shift_fields(task)
	var villager_cycle_state := _get_villager_work_cycle_state(villager)
	match villager_cycle_state:
		&"going_to_work":
			if bool(task.get("shift_resting", false)):
				task["shift_resting"] = false
				task["pending_rest_after_delivery"] = false
				task["shift_elapsed_minutes"] = 0.0
			task["state"] = RESOURCE_TASK_GOING_TO_RESOURCE
		&"working":
			task["state"] = RESOURCE_TASK_COLLECTING
		&"returning_home":
			task["state"] = RESOURCE_TASK_RETURNING_TO_BUILDING
		&"resting":
			if max(float(task.get("carried_amount", 0.0)), 0.0) > 0.0:
				task["state"] = RESOURCE_TASK_DELIVERING
			else:
				task["state"] = RESOURCE_TASK_RESTING
				task["shift_resting"] = true
				task["pending_rest_after_delivery"] = false
		_:
			task["state"] = RESOURCE_TASK_IDLE
	worker_resource_tasks[villager] = task
	_update_worker_resource_task_visual_status(villager, task)


func _update_worker_resource_task_visual_status(villager: Node2D, task: Dictionary) -> void:
	if villager == null or not is_instance_valid(villager):
		return
	var task_state: StringName = StringName(str(task.get("state", RESOURCE_TASK_IDLE)))
	var resource_type: StringName = StringName(str(task.get("resource_type", &"")))
	_update_worker_resource_task_animation_state(villager, task_state, resource_type, task)
	if not villager.has_method("set_resource_work_status"):
		return
	var status_text: String = _get_worker_resource_task_visual_text(task_state, resource_type, task)
	if status_text.is_empty():
		_clear_worker_resource_task_visual_status(villager)
		return
	villager.call("set_resource_work_status", status_text, _get_worker_resource_task_visual_color(task_state, resource_type))


func _update_worker_resource_task_animation_state(villager: Node2D, task_state: StringName, resource_type: StringName, task: Dictionary) -> void:
	if villager == null or not is_instance_valid(villager) or not villager.has_method("set_resource_task_animation_state"):
		return
	var carried_amount: float = max(float(task.get("carried_amount", 0.0)), 0.0)
	var animation_task_state: StringName = RESOURCE_TASK_DELIVERING if task_state == RESOURCE_TASK_WAITING_FOR_STORAGE else task_state
	villager.call("set_resource_task_animation_state", animation_task_state, resource_type, carried_amount)
	if villager.has_method("set_resource_task_animation_facing_override"):
		var facing_data: Dictionary = _get_worker_resource_collect_facing_override(task_state, task)
		villager.call(
			"set_resource_task_animation_facing_override",
			bool(facing_data.get("has_override", false)),
			bool(facing_data.get("facing_left", false))
		)


func _get_worker_resource_collect_facing_override(task_state: StringName, task: Dictionary) -> Dictionary:
	if task_state != RESOURCE_TASK_COLLECTING:
		return {"has_override": false, "facing_left": false}
	var resource_cell: Vector2i = task.get("target_resource_cell", Vector2i(-1, -1))
	var work_cell: Vector2i = task.get("target_work_cell", Vector2i(-1, -1))
	if resource_cell.x < 0 or work_cell.x < 0:
		return {"has_override": false, "facing_left": false}
	if resource_cell.x == work_cell.x:
		return {"has_override": false, "facing_left": false}
	return {"has_override": true, "facing_left": resource_cell.x < work_cell.x}


func _clear_worker_resource_task_visual_status(villager: Node2D) -> void:
	if villager == null or not is_instance_valid(villager):
		return
	if villager.has_method("clear_resource_task_animation_state"):
		villager.call("clear_resource_task_animation_state")
	if villager.has_method("clear_resource_work_status"):
		villager.call("clear_resource_work_status")


func _get_worker_resource_task_visual_text(task_state: StringName, resource_type: StringName, task: Dictionary) -> String:
	match task_state:
		RESOURCE_TASK_COLLECTING:
			var progress_percent: int = _get_worker_resource_task_collect_progress_percent(task)
			if resource_type == MapTypes.RESOURCE_WOOD:
				return "砍木 %d%%" % progress_percent
			if resource_type == MapTypes.RESOURCE_STONE:
				return "采石 %d%%" % progress_percent
			return "采集 %d%%" % progress_percent
		RESOURCE_TASK_RETURNING_TO_BUILDING:
			var carried_amount: float = float(task.get("carried_amount", 0.0))
			if carried_amount <= 0.0:
				return "返回"
			if resource_type == MapTypes.RESOURCE_WOOD:
				return "运木 %.1f" % carried_amount
			if resource_type == MapTypes.RESOURCE_STONE:
				return "运石 %.1f" % carried_amount
			return "运送 %.1f" % carried_amount
		RESOURCE_TASK_GOING_TO_RESOURCE:
			if resource_type == MapTypes.RESOURCE_WOOD:
				return "去森林"
			if resource_type == MapTypes.RESOURCE_STONE:
				return "去石材"
			return "前往资源"
		RESOURCE_TASK_RESTING:
			return "休息"
		RESOURCE_TASK_WAITING_FOR_STORAGE:
			var waiting_carried_amount: float = float(task.get("carried_amount", 0.0))
			if waiting_carried_amount > 0.0:
				return "等清库存 %.1f" % waiting_carried_amount
			return "等清库存"
		RESOURCE_TASK_FAILED:
			return _get_worker_resource_task_failure_display_text(task)
		_:
			return ""


func _get_worker_resource_task_failure_display_text(task: Dictionary) -> String:
	var failure_reason: String = str(task.get("failure_reason", ""))
	if failure_reason.contains("库存已满"):
		return "库存已满"
	if failure_reason.contains("没有可到达工作格") or failure_reason.contains("没有可达"):
		return "无可达资源"
	if failure_reason.contains("没有可采集资源格") or failure_reason.contains("附近资源已采尽") or failure_reason.contains("目标资源格已采空"):
		return "资源采尽"
	if failure_reason.contains("没有绑定") or failure_reason.contains("绑定资源区域"):
		return "未绑定资源"
	if failure_reason.contains("缺少建筑") or failure_reason.contains("缺少资源类型") or failure_reason.contains("库存接口"):
		return "任务异常"
	return "资源停止"


func _get_worker_resource_task_collect_progress_percent(task: Dictionary) -> int:
	var carry_amount_per_trip: float = max(float(task.get("carry_amount_per_trip", RESOURCE_TASK_CARRY_AMOUNT)), 0.001)
	var carried_amount: float = max(float(task.get("carried_amount", 0.0)), 0.0)
	return clampi(int(round((carried_amount / carry_amount_per_trip) * 100.0)), 0, 100)


func _get_worker_resource_task_visual_color(task_state: StringName, resource_type: StringName) -> Color:
	match task_state:
		RESOURCE_TASK_COLLECTING:
			if resource_type == MapTypes.RESOURCE_WOOD:
				return Color(0.72, 1.0, 0.52, 1.0)
			if resource_type == MapTypes.RESOURCE_STONE:
				return Color(0.82, 0.88, 1.0, 1.0)
			return Color(0.90, 1.0, 0.78, 1.0)
		RESOURCE_TASK_RETURNING_TO_BUILDING:
			return Color(1.0, 0.90, 0.55, 1.0)
		RESOURCE_TASK_RESTING:
			return Color(0.75, 0.88, 1.0, 1.0)
		RESOURCE_TASK_WAITING_FOR_STORAGE:
			return Color(1.0, 0.78, 0.25, 1.0)
		RESOURCE_TASK_FAILED:
			return Color(1.0, 0.55, 0.55, 1.0)
		_:
			return Color(1.0, 0.95, 0.70, 1.0)


func _get_villager_work_cycle_state(villager: Node2D) -> StringName:
	if villager == null or not is_instance_valid(villager):
		return &"unknown"
	if villager.has_method("get_work_cycle_state_name"):
		return StringName(str(villager.call("get_work_cycle_state_name")))
	if villager.has_method("get_state_name"):
		return StringName(str(villager.call("get_state_name")))
	return &"unknown"


func _get_worker_resource_tasks_for_building(building: RefCounted) -> Array:
	var result: Array = []
	if building == null:
		return result
	for task_variant in worker_resource_tasks.values():
		if typeof(task_variant) != TYPE_DICTIONARY:
			continue
		var task: Dictionary = task_variant
		if task.get("building", null) == building:
			result.append(task.duplicate())
	return result


func _has_active_worker_resource_tasks_for_building(building: RefCounted) -> bool:
	if building == null:
		return false
	for task_variant in worker_resource_tasks.values():
		if typeof(task_variant) != TYPE_DICTIONARY:
			continue
		var task: Dictionary = task_variant
		if task.get("building", null) != building:
			continue
		var state := StringName(str(task.get("state", RESOURCE_TASK_IDLE)))
		if state != RESOURCE_TASK_FAILED:
			return true
	return false


func _get_idle_villager_wander_bounds() -> Rect2:
	if map_read_result.is_empty():
		return Rect2(Vector2.ZERO, Vector2(1024, 768))

	var used_rect: Rect2i = map_read_result.get("used_rect", Rect2i()) as Rect2i
	var offset: Vector2i = map_read_result.get("cell_offset", Vector2i.ZERO) as Vector2i
	var top_left_map := offset
	var bottom_right_map := offset + used_rect.size
	var top_left_world := characters_root.to_local(ground_layer.to_global(ground_layer.map_to_local(top_left_map)))
	var bottom_right_world := characters_root.to_local(ground_layer.to_global(ground_layer.map_to_local(bottom_right_map)))
	var min_corner := Vector2(minf(top_left_world.x, bottom_right_world.x), minf(top_left_world.y, bottom_right_world.y))
	var max_corner := Vector2(maxf(top_left_world.x, bottom_right_world.x), maxf(top_left_world.y, bottom_right_world.y))
	return Rect2(min_corner, max_corner - min_corner)


func _get_villager_navigation_terrain(cell: Vector2i) -> int:
	if grid == null:
		return VILLAGER_NAVIGATION_TERRAIN_MISS
	if not grid.is_inside(cell):
		return VILLAGER_NAVIGATION_TERRAIN_MISS
	return int(grid.get_terrain(cell))


func _is_villager_walkable_cell(cell: Vector2i) -> bool:
	if grid == null or not grid.is_inside(cell):
		return false
	return not grid.get_blocks_movement(cell)


func _root_position_to_grid_cell(root_position: Vector2, target_root: Node2D) -> Vector2i:
	if ground_layer == null or target_root == null:
		return Vector2i.ZERO
	var global_position: Vector2 = target_root.to_global(root_position)
	var local_position: Vector2 = ground_layer.to_local(global_position)
	var map_cell: Vector2i = ground_layer.local_to_map(local_position)
	return map_cell - (map_read_result.get("cell_offset", Vector2i.ZERO) as Vector2i)


func _get_navigation_cell_world_span() -> float:
	if ground_layer == null:
		return 16.0
	var origin: Vector2 = _grid_cell_to_root_position(Vector2i.ZERO, characters_root)
	var step_x: Vector2 = _grid_cell_to_root_position(Vector2i.RIGHT, characters_root)
	var step_y: Vector2 = _grid_cell_to_root_position(Vector2i.DOWN, characters_root)
	var x_span: float = origin.distance_to(step_x)
	var y_span: float = origin.distance_to(step_y)
	return maxf(maxf(x_span, y_span), 1.0)


func _find_nearest_villager_walkable_cell(origin_cell: Vector2i, max_radius: int = 8) -> Vector2i:
	if _is_villager_walkable_cell(origin_cell):
		return origin_cell
	for radius in range(1, max_radius + 1):
		for y in range(origin_cell.y - radius, origin_cell.y + radius + 1):
			for x in range(origin_cell.x - radius, origin_cell.x + radius + 1):
				if abs(x - origin_cell.x) != radius and abs(y - origin_cell.y) != radius:
					continue
				var candidate := Vector2i(x, y)
				if _is_villager_walkable_cell(candidate):
					return candidate
	return Vector2i(-1, -1)


func _build_villager_route_points(from_position: Vector2, to_position: Vector2) -> Array[Vector2]:
	var route_points: Array[Vector2] = []
	if ground_layer == null or characters_root == null:
		route_points.append(to_position)
		return route_points

	var start_cell: Vector2i = _find_nearest_villager_walkable_cell(_root_position_to_grid_cell(from_position, characters_root))
	var goal_cell: Vector2i = _find_nearest_villager_walkable_cell(_root_position_to_grid_cell(to_position, characters_root))
	if start_cell.x < 0 or goal_cell.x < 0:
		return route_points

	var cell_path: Array[Vector2i] = _build_villager_cell_path(start_cell, goal_cell)
	if cell_path.is_empty():
		if start_cell == goal_cell:
			route_points.append(to_position)
		return route_points

	for cell in cell_path:
		var cell_position: Vector2 = _grid_cell_to_root_position(cell, characters_root)
		if cell_position.distance_to(from_position) <= 0.01:
			continue
		if not route_points.is_empty() and cell_position.distance_to(route_points[route_points.size() - 1]) <= 0.01:
			continue
		route_points.append(cell_position)

	if route_points.is_empty() or route_points[route_points.size() - 1].distance_to(to_position) > 0.01:
		route_points.append(to_position)
	return route_points


func _build_villager_cell_path(start_cell: Vector2i, goal_cell: Vector2i) -> Array[Vector2i]:
	if start_cell.x < 0 or goal_cell.x < 0:
		return []
	if not _is_villager_walkable_cell(start_cell) or not _is_villager_walkable_cell(goal_cell):
		return []
	if start_cell == goal_cell:
		return [goal_cell]

	var distance: int = _get_manhattan_distance(start_cell, goal_cell)
	var paddings: Array[int] = [
		maxi(12, int(ceili(float(distance) * 0.5)) + 8),
		maxi(24, distance + 12),
		maxi(48, distance * 2 + 16),
	]
	var tried_paddings: Dictionary = {}
	for padding in paddings:
		if tried_paddings.has(padding):
			continue
		tried_paddings[padding] = true
		var search_rect := Rect2i(
			Vector2i(mini(start_cell.x, goal_cell.x) - padding, mini(start_cell.y, goal_cell.y) - padding),
			Vector2i(abs(start_cell.x - goal_cell.x) + 1 + padding * 2, abs(start_cell.y - goal_cell.y) + 1 + padding * 2)
		)
		var path: Array[Vector2i] = _run_villager_a_star(start_cell, goal_cell, search_rect)
		if not path.is_empty():
			return path
	return []


func _run_villager_a_star(start_cell: Vector2i, goal_cell: Vector2i, search_rect: Rect2i) -> Array[Vector2i]:
	var open_set: Array[Vector2i] = [start_cell]
	var open_lookup: Dictionary = {start_cell: true}
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start_cell: 0}
	var f_score: Dictionary = {start_cell: _get_octile_distance_cost(start_cell, goal_cell)}

	while not open_set.is_empty():
		var current_index: int = 0
		var current_cell: Vector2i = open_set[0]
		var current_score: int = int(f_score.get(current_cell, 2147483647))
		for candidate_index in range(1, open_set.size()):
			var candidate_cell: Vector2i = open_set[candidate_index]
			var candidate_score: int = int(f_score.get(candidate_cell, 2147483647))
			if candidate_score < current_score:
				current_index = candidate_index
				current_cell = candidate_cell
				current_score = candidate_score

		open_set.remove_at(current_index)
		open_lookup.erase(current_cell)

		if current_cell == goal_cell:
			return _reconstruct_villager_cell_path(came_from, current_cell)

		for direction in MapTypes.get_eight_directions():
			var neighbor: Vector2i = current_cell + direction
			if not search_rect.has_point(neighbor):
				continue
			if not _is_villager_walkable_cell(neighbor):
				continue
			if _is_diagonal_direction(direction) and not _can_move_diagonally(current_cell, direction):
				continue
			var step_cost: int = _get_direction_step_cost(direction)
			var tentative_score: int = int(g_score.get(current_cell, 2147483647)) + step_cost
			var existing_score: int = int(g_score.get(neighbor, 2147483647))
			if tentative_score >= existing_score:
				continue
			came_from[neighbor] = current_cell
			g_score[neighbor] = tentative_score
			f_score[neighbor] = tentative_score + _get_octile_distance_cost(neighbor, goal_cell)
			if not open_lookup.has(neighbor):
				open_set.append(neighbor)
				open_lookup[neighbor] = true
	return []


func _reconstruct_villager_cell_path(came_from: Dictionary, current_cell: Vector2i) -> Array[Vector2i]:
	var reversed_path: Array[Vector2i] = [current_cell]
	var cursor: Vector2i = current_cell
	while came_from.has(cursor):
		cursor = came_from[cursor]
		reversed_path.append(cursor)
	reversed_path.reverse()
	return reversed_path


func _get_manhattan_distance(from_cell: Vector2i, to_cell: Vector2i) -> int:
	return abs(from_cell.x - to_cell.x) + abs(from_cell.y - to_cell.y)


func _get_octile_distance_cost(from_cell: Vector2i, to_cell: Vector2i) -> int:
	var dx: int = abs(from_cell.x - to_cell.x)
	var dy: int = abs(from_cell.y - to_cell.y)
	var diagonal_steps: int = mini(dx, dy)
	var straight_steps: int = maxi(dx, dy) - diagonal_steps
	return diagonal_steps * 14 + straight_steps * 10


func _is_diagonal_direction(direction: Vector2i) -> bool:
	return direction.x != 0 and direction.y != 0


func _get_direction_step_cost(direction: Vector2i) -> int:
	return 14 if _is_diagonal_direction(direction) else 10


func _can_move_diagonally(from_cell: Vector2i, direction: Vector2i) -> bool:
	var horizontal_neighbor := from_cell + Vector2i(direction.x, 0)
	var vertical_neighbor := from_cell + Vector2i(0, direction.y)
	return _is_villager_walkable_cell(horizontal_neighbor) and _is_villager_walkable_cell(vertical_neighbor)


func _pick_villager_wander_target_position(
	current_position: Vector2,
	wander_center: Vector2,
	wander_radius: float,
	wander_bounds: Rect2
) -> Vector2:
	var castle_grid_target: Variant = _pick_initial_castle_villager_wander_target_position(current_position)
	if typeof(castle_grid_target) == TYPE_VECTOR2:
		return castle_grid_target
	var current_cell: Vector2i = _find_nearest_villager_walkable_cell(_root_position_to_grid_cell(current_position, characters_root))
	var center_cell: Vector2i = _find_nearest_villager_walkable_cell(_root_position_to_grid_cell(wander_center, characters_root))
	var cell_span: float = _get_navigation_cell_world_span()
	var cell_radius: int = maxi(1, int(ceili(wander_radius / maxf(cell_span, 1.0))))
	var candidates: Array[Vector2i] = []

	for y in range(center_cell.y - cell_radius, center_cell.y + cell_radius + 1):
		for x in range(center_cell.x - cell_radius, center_cell.x + cell_radius + 1):
			var candidate_cell: Vector2i = Vector2i(x, y)
			if not _is_villager_walkable_cell(candidate_cell):
				continue
			var candidate_position: Vector2 = _grid_cell_to_root_position(candidate_cell, characters_root)
			if wander_bounds.size != Vector2.ZERO and not wander_bounds.has_point(candidate_position):
				continue
			if candidate_position.distance_to(wander_center) > wander_radius + cell_span * 0.5:
				continue
			candidates.append(candidate_cell)

	if candidates.is_empty():
		if current_cell.x >= 0:
			return _grid_cell_to_root_position(current_cell, characters_root)
		return wander_center

	_shuffle_array_in_place(candidates)
	for candidate_cell in candidates:
		if candidate_cell == current_cell and candidates.size() > 1:
			continue
		return _grid_cell_to_root_position(candidate_cell, characters_root)
	return _grid_cell_to_root_position(candidates[0], characters_root)


func _pick_initial_castle_villager_wander_target_position(current_position: Vector2) -> Variant:
	var villager: Node = _find_villager_by_root_position(current_position)
	if villager == null or not is_instance_valid(villager):
		return null
	if str(villager.get_meta("wander_rule", "")) != "castle_initial_grid":
		return null
	var castle_cell_variant: Variant = villager.get_meta("castle_cell", Vector2i(-1, -1))
	if typeof(castle_cell_variant) != TYPE_VECTOR2I:
		return null
	var castle_cell: Vector2i = castle_cell_variant
	if castle_cell.x < 0 or castle_cell.y < 0:
		return null
	var target_cell: Vector2i = _pick_initial_castle_villager_wander_cell(castle_cell, _root_position_to_grid_cell(current_position, characters_root))
	if target_cell.x < 0 or target_cell.y < 0:
		return _get_building_route_point_for_root(_find_castle_building(), characters_root, HOME_EXIT_OFFSET)
	return _grid_cell_to_root_position(target_cell, characters_root)


func _find_villager_by_root_position(root_position: Vector2) -> Node:
	if characters_root == null:
		return null
	for child in characters_root.get_children():
		var villager: Node2D = child as Node2D
		if villager == null:
			continue
		if villager.position.distance_to(root_position) <= 0.01:
			return villager
	return null


func _pick_initial_castle_villager_wander_cell(castle_cell: Vector2i, current_cell: Vector2i) -> Vector2i:
	var candidates: Array[Vector2i] = []
	var preferred_candidates: Array[Vector2i] = []
	var start_cell: Vector2i = current_cell
	if start_cell.x < 0 or not _is_villager_walkable_cell(start_cell):
		start_cell = _find_nearest_villager_walkable_cell(castle_cell, CASTLE_INITIAL_VILLAGER_WANDER_REACH_RADIUS)
	if start_cell.x < 0:
		return Vector2i(-1, -1)

	var visited: Dictionary = {start_cell: true}
	var queue: Array[Vector2i] = [start_cell]
	var queue_index: int = 0
	while queue_index < queue.size():
		var search_cell: Vector2i = queue[queue_index]
		queue_index += 1
		var distance_from_castle: int = _get_chebyshev_distance(search_cell, castle_cell)
		if distance_from_castle > CASTLE_INITIAL_VILLAGER_WANDER_REACH_RADIUS:
			continue
		if not _is_cell_blocked_by_non_castle_building(search_cell, castle_cell):
			candidates.append(search_cell)
			if distance_from_castle <= CASTLE_INITIAL_VILLAGER_WANDER_PREFERRED_RADIUS:
				preferred_candidates.append(search_cell)

		for direction in MapTypes.get_eight_directions():
			var neighbor_cell: Vector2i = search_cell + direction
			if visited.has(neighbor_cell):
				continue
			if _get_chebyshev_distance(neighbor_cell, castle_cell) > CASTLE_INITIAL_VILLAGER_WANDER_REACH_RADIUS:
				continue
			if not _is_villager_walkable_cell(neighbor_cell):
				continue
			if _is_diagonal_direction(direction) and not _can_move_diagonally(search_cell, direction):
				continue
			visited[neighbor_cell] = true
			queue.append(neighbor_cell)
	if candidates.is_empty():
		return Vector2i(-1, -1)
	var selectable_candidates: Array[Vector2i] = preferred_candidates if not preferred_candidates.is_empty() else candidates
	_shuffle_array_in_place(selectable_candidates)
	for candidate_cell in selectable_candidates:
		if candidate_cell == current_cell and candidates.size() > 1:
			continue
		return candidate_cell
	return selectable_candidates[0]


func _is_cell_blocked_by_non_castle_building(cell: Vector2i, castle_cell: Vector2i) -> bool:
	if not occupied_cells.has(cell):
		return false
	for castle_footprint_cell in BuildingFootprintRulesScript.get_castle_footprint_cells(castle_cell):
		if castle_footprint_cell == cell:
			return false
	return true


func _get_chebyshev_distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(abs(a.x - b.x), abs(a.y - b.y))


func _shuffle_array_in_place(values: Array) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap_index := worker_assignment_rng.randi_range(0, index)
		var temp = values[index]
		values[index] = values[swap_index]
		values[swap_index] = temp


func _setup_placement_controller() -> void:
	placement_controller = BuildingPlacementControllerScript.new()
	placement_controller.setup(grid, resource_regions, farmable_regions, occupied_cells, _get_castle_cell(), resource_inventory)


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
	if harvest_button != null and not harvest_button.pressed.is_connected(_on_harvest_button_pressed):
		harvest_button.pressed.connect(_on_harvest_button_pressed)
	if worker_minus_button != null and not worker_minus_button.pressed.is_connected(_on_worker_minus_button_pressed):
		worker_minus_button.pressed.connect(_on_worker_minus_button_pressed)
	if worker_plus_button != null and not worker_plus_button.pressed.is_connected(_on_worker_plus_button_pressed):
		worker_plus_button.pressed.connect(_on_worker_plus_button_pressed)
	if worker_popup_minus_button != null and not worker_popup_minus_button.pressed.is_connected(_on_worker_minus_button_pressed):
		worker_popup_minus_button.pressed.connect(_on_worker_minus_button_pressed)
	if worker_popup_plus_button != null and not worker_popup_plus_button.pressed.is_connected(_on_worker_plus_button_pressed):
		worker_popup_plus_button.pressed.connect(_on_worker_plus_button_pressed)
	if farm_button != null:
		if not farm_button.mouse_entered.is_connected(Callable(self, "_on_build_button_mouse_entered").bind(MapTypes.BuildingType.FARM, farm_button)):
			farm_button.mouse_entered.connect(Callable(self, "_on_build_button_mouse_entered").bind(MapTypes.BuildingType.FARM, farm_button))
		if not farm_button.mouse_exited.is_connected(Callable(self, "_on_build_button_mouse_exited")):
			farm_button.mouse_exited.connect(_on_build_button_mouse_exited)
	if lumber_camp_button != null:
		if not lumber_camp_button.mouse_entered.is_connected(Callable(self, "_on_build_button_mouse_entered").bind(MapTypes.BuildingType.LUMBER_CAMP, lumber_camp_button)):
			lumber_camp_button.mouse_entered.connect(Callable(self, "_on_build_button_mouse_entered").bind(MapTypes.BuildingType.LUMBER_CAMP, lumber_camp_button))
		if not lumber_camp_button.mouse_exited.is_connected(Callable(self, "_on_build_button_mouse_exited")):
			lumber_camp_button.mouse_exited.connect(_on_build_button_mouse_exited)
	if quarry_button != null:
		if not quarry_button.mouse_entered.is_connected(Callable(self, "_on_build_button_mouse_entered").bind(MapTypes.BuildingType.QUARRY, quarry_button)):
			quarry_button.mouse_entered.connect(Callable(self, "_on_build_button_mouse_entered").bind(MapTypes.BuildingType.QUARRY, quarry_button))
		if not quarry_button.mouse_exited.is_connected(Callable(self, "_on_build_button_mouse_exited")):
			quarry_button.mouse_exited.connect(_on_build_button_mouse_exited)
	if house_button != null:
		if not house_button.mouse_entered.is_connected(Callable(self, "_on_build_button_mouse_entered").bind(MapTypes.BuildingType.HOUSE, house_button)):
			house_button.mouse_entered.connect(Callable(self, "_on_build_button_mouse_entered").bind(MapTypes.BuildingType.HOUSE, house_button))
		if not house_button.mouse_exited.is_connected(Callable(self, "_on_build_button_mouse_exited")):
			house_button.mouse_exited.connect(_on_build_button_mouse_exited)
	_update_placement_ui()


func _on_placement_button_pressed(building_type: int) -> void:
	_enter_placement_mode(building_type)


func _on_build_button_mouse_entered(building_type: int, anchor_button: Control) -> void:
	_show_build_cost_tooltip(building_type, anchor_button)


func _on_build_button_mouse_exited() -> void:
	_hide_build_cost_tooltip()


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
		if _is_screen_position_over_interactive_panel(event.position):
			return
		_exit_placement_mode()
		_clear_selected_building()
		return
	if event.button_index == MOUSE_BUTTON_LEFT and event.pressed and placement_mode_active:
		_try_place_selected_building()
		return


func _enter_placement_mode(building_type: int) -> void:
	_clear_selected_building()
	placement_mode_active = true
	selected_building_type = building_type
	last_placement_message = "已选择：%s，请移动鼠标预览放置位置。" % MapTypes.get_building_label(selected_building_type)
	if enable_console_debug_logs:
		print("stage7 placement mode | selected=", MapTypes.get_building_label(selected_building_type))
	_update_worker_control_ui()
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
	_update_worker_control_ui()
	if enable_console_debug_logs:
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


func _update_resource_hover_hint() -> void:
	if hover_hint_label == null:
		return
	if ground_layer == null or grid == null:
		hover_hint_label.visible = false
		return
	if not _is_pointer_inside_game_viewport() or _is_pointer_over_worker_popup():
		hover_hint_label.visible = false
		return
	if hovered_building_node != null and is_instance_valid(hovered_building_node):
		hover_hint_label.visible = false
		return

	var next_cell: Vector2i = _get_mouse_grid_cell()
	var hint_text: String = _get_resource_hover_hint_text(next_cell)
	if hint_text.is_empty():
		hover_hint_label.visible = false
		return
	hover_hint_label.visible = true
	hover_hint_label.position = get_global_mouse_position() + Vector2(16, -16)
	hover_hint_label.text = hint_text


func _get_resource_hover_hint_text(cell: Vector2i) -> String:
	if grid == null or not grid.has_method("is_inside") or not bool(grid.call("is_inside", cell)):
		return ""
	var terrain_type: int = int(grid.call("get_terrain", cell))
	var resource_type: StringName = MapTypes.get_resource_name_for_terrain(terrain_type)
	if not _is_depletable_resource_type(resource_type):
		return ""
	var remaining_amount: float = _get_resource_cell_remaining_amount(cell, resource_type)
	var default_amount: float = _get_resource_cell_default_amount(resource_type)
	var resource_label: String = _get_resource_label(resource_type)
	return "%s资源\n格子：%s\n剩余：%.1f / %.1f" % [resource_label, str(cell), remaining_amount, default_amount]


func _get_resource_cell_remaining_amount(cell: Vector2i, resource_type: StringName) -> float:
	if resource_depletion_state == null or not resource_depletion_state.has_method("get_remaining_amount"):
		return 0.0
	return float(resource_depletion_state.call("get_remaining_amount", cell, resource_type))


func _get_resource_cell_default_amount(resource_type: StringName) -> float:
	if resource_depletion_state == null or not resource_depletion_state.has_method("get_default_amount_for_resource"):
		return 0.0
	return float(resource_depletion_state.call("get_default_amount_for_resource", resource_type))


func _try_place_selected_building() -> void:
	if placement_controller == null or selected_building_type < 0:
		return
	if hovered_result == null:
		hovered_result = placement_controller.can_place(selected_building_type, hovered_cell)
	if not bool(hovered_result.can_place):
		last_placement_message = "放置失败：%s" % str(hovered_result.reason)
		_append_event_log("无法放置 %s：%s" % [MapTypes.get_building_label(selected_building_type), str(hovered_result.reason)])
		if enable_console_debug_logs:
			print("stage7 placement blocked | building=", MapTypes.get_building_label(selected_building_type), " cell=", hovered_cell, " reason=", hovered_result.reason)
		_update_placement_overlay()
		return

	var placed_building: RefCounted = placement_controller.place(selected_building_type, hovered_cell)
	if placed_building == null:
		last_placement_message = "放置失败：缺少建筑数据。"
		_append_event_log("无法放置 %s：缺少建筑数据。" % MapTypes.get_building_label(selected_building_type))
		_update_placement_overlay()
		return
	if placed_building.has_method("is_valid") and not bool(placed_building.can_place):
		last_placement_message = "放置失败：%s" % str(placed_building.reason)
		_append_event_log("无法放置 %s：%s" % [MapTypes.get_building_label(selected_building_type), str(placed_building.reason)])
		if enable_console_debug_logs:
			print("stage7 placement blocked | building=", MapTypes.get_building_label(selected_building_type), " cell=", hovered_cell, " reason=", placed_building.reason)
		_update_placement_overlay()
		return

	initial_buildings.append(placed_building)
	_register_occupied_cells_for_building(placed_building)
	_instantiate_building_visual(placed_building)
	_clear_building_footprint_resource_visuals(placed_building)
	last_placement_message = "建造完成：%s，位置 %s" % [placed_building.get_building_label(), str(placed_building.position)]
	_append_event_log(last_placement_message)
	if enable_console_debug_logs:
		print("stage7 placement success | building=", placed_building.get_building_label(), " cell=", placed_building.position)
	_sync_household_count()
	if int(placed_building.building_type) == MapTypes.BuildingType.HOUSE and governance_state != null:
		_queue_house_villager_spawn_contexts(placed_building, HOUSE_POPULATION_CAPACITY)
		governance_state.set_population(int(governance_state.population) + HOUSE_POPULATION_CAPACITY)
		_append_event_log("住宅新增人口 +%d" % HOUSE_POPULATION_CAPACITY)
	_sync_population_dependent_state()
	_update_placement_hover(true)


func _queue_house_villager_spawn_contexts(house_building: RefCounted, count: int) -> void:
	if house_building == null or count <= 0 or characters_root == null:
		return
	var house_spawn_context: Dictionary = _build_house_villager_spawn_context(house_building)
	if house_spawn_context.is_empty():
		return
	for _index in range(count):
		pending_house_villager_spawn_contexts.append(house_spawn_context.duplicate(true))


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
		return "建筑：%s" % building_label
	if bool(hovered_result.can_place):
		return "建筑：%s\n格子：%s\n可放置" % [building_label, str(hovered_cell)]
	return "建筑：%s\n格子：%s\n不可放置：%s" % [building_label, str(hovered_cell), str(hovered_result.reason)]

func _is_selected_building_town_center() -> bool:
	if selected_building_data == null:
		return false
	return int(selected_building_data.building_type) == MapTypes.BuildingType.TOWN_CENTER


func _is_selected_building_manageable_production() -> bool:
	if selected_building_data == null:
		return false
	if not MapTypes.is_production_building(int(selected_building_data.building_type)):
		return false
	if not selected_building_data.has_method("has_workers"):
		return false
	return bool(selected_building_data.call("has_workers"))


func _should_show_placement_panel() -> bool:
	return placement_mode_active or _is_selected_building_town_center() or _is_selected_building_manageable_production()


func _set_placement_buttons_visible(next_visible: bool) -> void:
	if farm_button != null:
		farm_button.visible = next_visible
	if lumber_camp_button != null:
		lumber_camp_button.visible = next_visible
	if quarry_button != null:
		quarry_button.visible = next_visible
	if house_button != null:
		house_button.visible = next_visible


func _update_shared_building_panel_mode() -> void:
	var showing_castle_menu := placement_mode_active or _is_selected_building_town_center()
	var showing_production_menu := not placement_mode_active and _is_selected_building_manageable_production()
	if placement_panel != null:
		placement_panel.visible = showing_castle_menu or showing_production_menu
	_set_placement_buttons_visible(showing_castle_menu)
	if cancel_placement_button != null:
		cancel_placement_button.visible = showing_castle_menu
	if worker_control_panel != null:
		worker_control_panel.visible = showing_production_menu
	if harvest_button != null:
		harvest_button.visible = showing_production_menu
	if placement_status_label != null:
		placement_status_label.visible = showing_castle_menu or showing_production_menu
		placement_status_label.custom_minimum_size = Vector2(304, 118) if showing_production_menu else Vector2(304, 42)


func _update_placement_ui() -> void:
	_update_shared_building_panel_mode()
	_update_placement_button_texts()
	if cancel_placement_button != null:
		cancel_placement_button.disabled = not placement_mode_active
	if placement_status_label != null:
		if _is_selected_building_manageable_production() and not placement_mode_active:
			placement_status_label.text = _get_selected_building_management_text()
		else:
			placement_status_label.text = _get_placement_status_text()
	if harvest_button != null:
		harvest_button.disabled = not _can_harvest_selected_building()


func _on_game_minute_changed(total_minutes: int) -> void:
	if _is_victory_defeat_finalized():
		return
	_apply_minute_economy()
	_apply_daily_happiness_if_needed(total_minutes)
	_refresh_stage14_hud()

func _on_game_time_changed(_time_text: String) -> void:
	_update_time_control_ui()
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
	_sync_population_dependent_state()
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
		var present_workers := _get_present_workers_for_building(building)
		var building_output: Dictionary = production_calculator.get_building_output_per_minute_with_present_workers(building, regions_by_id, present_workers)
		for resource_type in building_output.keys():
			if resource_type == MapTypes.RESOURCE_GOLD:
				continue
			var resource_name: StringName = StringName(str(resource_type))
			var output_amount: float = float(building_output[resource_type])
			var region: RefCounted = _get_resource_region_for_building(building, regions_by_id)
			if _is_depletable_resource_type(resource_name):
				if _has_active_worker_resource_tasks_for_building(building):
					_update_building_linked_resource_depleted_status(building, region, resource_name)
					continue
				_update_building_linked_resource_depleted_status(building, region, resource_name)
				output_amount = _get_depletion_aware_resource_output_amount(building, region, resource_name, present_workers)
				output_amount = minf(output_amount, _get_region_remaining_resource_amount(region, resource_name))
			var accepted_amount: float = building.add_to_storage(resource_name, output_amount)
			if accepted_amount > 0.0 and _is_depletable_resource_type(resource_name):
				_consume_region_resource(region, resource_name, accepted_amount)
				_apply_depleted_resource_cells_to_grid(region, resource_name)
			_add_to_delta(building_delta, resource_name, accepted_amount)
		_update_building_visual_for_data(building)
	return building_delta


func _is_depletable_resource_type(resource_type: StringName) -> bool:
	return resource_type == MapTypes.RESOURCE_WOOD or resource_type == MapTypes.RESOURCE_STONE


func _get_resource_region_for_building(building: RefCounted, regions_by_id: Dictionary) -> RefCounted:
	if building == null:
		return null
	var required_terrain: int = _get_required_resource_terrain_for_building(int(building.building_type))
	if required_terrain < 0:
		return null
	var linked_region_id: int = int(building.linked_region_id)
	if regions_by_id.has(required_terrain):
		var regions_variant: Variant = regions_by_id.get(required_terrain, {})
		if typeof(regions_variant) == TYPE_DICTIONARY:
			var regions_for_terrain: Dictionary = regions_variant
			if regions_for_terrain.has(linked_region_id):
				var matched_region_variant: Variant = regions_for_terrain[linked_region_id]
				if matched_region_variant is RefCounted:
					return matched_region_variant
	if regions_by_id.has(linked_region_id):
		var region_variant: Variant = regions_by_id.get(linked_region_id, null)
		if region_variant is RefCounted:
			return region_variant
	return null


func _find_resource_collection_target_for_building(building: RefCounted, excluded_villager: Node2D = null) -> Dictionary:
	if building == null:
		return _build_resource_collection_target_failure("缺少建筑数据。")
	var resource_type: StringName = MapTypes.get_resource_name_for_building(int(building.building_type))
	if not _is_depletable_resource_type(resource_type):
		return _build_resource_collection_target_failure("建筑不是可采集资源建筑。")
	var region: RefCounted = _get_resource_region_for_building(building, _get_regions_by_id())
	if region == null:
		return _build_resource_collection_target_failure("建筑没有绑定可用资源区域。")
	var reserved_resource_cells: Dictionary = _get_reserved_resource_cells_for_building(building, excluded_villager)
	var resource_cell: Vector2i = _find_collectable_resource_cell_for_region(building, region, resource_type, reserved_resource_cells)
	if resource_cell.x < 0:
		return _build_resource_collection_target_failure("绑定资源区域没有未被占用的可采集资源格。")
	var work_cell: Vector2i = _find_resource_collection_work_cell(resource_cell)
	if work_cell.x < 0:
		return _build_resource_collection_target_failure("资源格旁边没有可到达工作格。")
	return {
		"ok": true,
		"reason": "",
		"building": building,
		"region": region,
		"resource_type": resource_type,
		"resource_cell": resource_cell,
		"work_cell": work_cell,
	}


func _build_resource_collection_target_failure(reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"building": null,
		"region": null,
		"resource_type": &"",
		"resource_cell": Vector2i(-1, -1),
		"work_cell": Vector2i(-1, -1),
	}


func _get_reserved_resource_cells_for_building(building: RefCounted, excluded_villager: Node2D = null) -> Dictionary:
	var reserved_resource_cells: Dictionary = {}
	if building == null:
		return reserved_resource_cells
	for villager_variant in worker_resource_tasks.keys():
		if excluded_villager != null and villager_variant == excluded_villager:
			continue
		var task_variant: Variant = worker_resource_tasks.get(villager_variant, {})
		if typeof(task_variant) != TYPE_DICTIONARY:
			continue
		var task: Dictionary = task_variant
		if task.get("building", null) != building:
			continue
		var task_state: StringName = StringName(str(task.get("state", RESOURCE_TASK_IDLE)))
		if task_state == RESOURCE_TASK_IDLE or task_state == RESOURCE_TASK_FAILED:
			continue
		var resource_cell_variant: Variant = task.get("target_resource_cell", Vector2i(-1, -1))
		if typeof(resource_cell_variant) != TYPE_VECTOR2I:
			continue
		var resource_cell: Vector2i = resource_cell_variant
		if resource_cell.x < 0:
			continue
		reserved_resource_cells[resource_cell] = true
	return reserved_resource_cells


func _is_resource_cell_reserved(resource_cell: Vector2i, reserved_resource_cells: Dictionary) -> bool:
	return not reserved_resource_cells.is_empty() and reserved_resource_cells.has(resource_cell)


func _find_collectable_resource_cell_for_region(building: RefCounted, region: RefCounted, resource_type: StringName, reserved_resource_cells: Dictionary = {}) -> Vector2i:
	if building == null or region == null:
		return Vector2i(-1, -1)
	var required_terrain: int = _get_required_resource_terrain_for_resource(resource_type)
	if required_terrain < 0:
		return Vector2i(-1, -1)
	var best_cell: Vector2i = Vector2i(-1, -1)
	var best_distance: int = 9223372036854775807
	for cell_variant in _get_region_cells(region):
		if typeof(cell_variant) != TYPE_VECTOR2I:
			continue
		var cell: Vector2i = cell_variant
		if _is_resource_cell_reserved(cell, reserved_resource_cells):
			continue
		if not _is_collectable_resource_cell(cell, required_terrain, resource_type):
			continue
		if _find_resource_collection_work_cell(cell).x < 0:
			continue
		var distance: int = _get_manhattan_distance(cell, building.position)
		if distance < best_distance:
			best_distance = distance
			best_cell = cell
	return best_cell


func _is_collectable_resource_cell(cell: Vector2i, required_terrain: int, resource_type: StringName) -> bool:
	if grid == null or not grid.has_method("is_inside") or not bool(grid.call("is_inside", cell)):
		return false
	if int(grid.call("get_terrain", cell)) != required_terrain:
		return false
	if resource_depletion_state != null and resource_depletion_state.has_method("is_depleted"):
		if bool(resource_depletion_state.call("is_depleted", cell, resource_type)):
			return false
	return true


func _find_resource_collection_work_cell(resource_cell: Vector2i) -> Vector2i:
	var best_cell: Vector2i = Vector2i(-1, -1)
	var best_distance: int = 9223372036854775807
	for direction in MapTypes.get_cardinal_directions():
		var candidate_cell: Vector2i = resource_cell + direction
		if not _is_valid_resource_collection_work_cell(candidate_cell):
			continue
		var distance: int = _get_manhattan_distance(candidate_cell, _get_castle_cell())
		if distance < best_distance:
			best_distance = distance
			best_cell = candidate_cell
	return best_cell


func _is_valid_resource_collection_work_cell(cell: Vector2i) -> bool:
	if occupied_cells.has(cell):
		return false
	return _is_villager_walkable_cell(cell)


func _get_required_resource_terrain_for_building(building_type: int) -> int:
	match building_type:
		MapTypes.BuildingType.LUMBER_CAMP:
			return MapTypes.TerrainType.FOREST
		MapTypes.BuildingType.QUARRY:
			return MapTypes.TerrainType.STONE
		_:
			return -1


func _get_required_resource_terrain_for_resource(resource_type: StringName) -> int:
	match resource_type:
		MapTypes.RESOURCE_WOOD:
			return MapTypes.TerrainType.FOREST
		MapTypes.RESOURCE_STONE:
			return MapTypes.TerrainType.STONE
		_:
			return -1


func _get_depletion_aware_resource_output_amount(building: RefCounted, region: RefCounted, resource_type: StringName, present_workers: int) -> float:
	if building == null or region == null or production_calculator == null:
		return 0.0
	var required_terrain: int = _get_required_resource_terrain_for_resource(resource_type)
	if required_terrain < 0:
		return 0.0
	var active_cell_count: int = _get_active_resource_cell_count(region, resource_type)
	if production_calculator.has_method("get_limited_resource_output_per_minute"):
		return float(production_calculator.call(
			"get_limited_resource_output_per_minute",
			int(building.building_type),
			required_terrain,
			active_cell_count,
			present_workers
		))
	return 0.0


func _get_active_resource_cell_count(region: RefCounted, resource_type: StringName) -> int:
	if region == null:
		return 0
	var required_terrain: int = _get_required_resource_terrain_for_resource(resource_type)
	if required_terrain < 0:
		return 0
	var cells: Array = _get_region_cells(region)
	var active_count: int = 0
	for cell_variant in cells:
		if typeof(cell_variant) != TYPE_VECTOR2I:
			continue
		var cell: Vector2i = cell_variant
		if resource_depletion_state != null and resource_depletion_state.has_method("is_depleted"):
			if bool(resource_depletion_state.call("is_depleted", cell, resource_type)):
				continue
		if grid != null and grid.has_method("is_inside") and bool(grid.call("is_inside", cell)):
			if int(grid.call("get_terrain", cell)) != required_terrain:
				continue
		active_count += 1
	return active_count


func _get_region_remaining_resource_amount(region: RefCounted, resource_type: StringName) -> float:
	if region == null or resource_depletion_state == null:
		return INF
	if not resource_depletion_state.has_method("get_total_remaining_amount"):
		return INF
	var cells: Array = _get_region_cells(region)
	if cells.is_empty():
		return 0.0
	return float(resource_depletion_state.call("get_total_remaining_amount", cells, resource_type))


func _consume_region_resource(region: RefCounted, resource_type: StringName, amount: float) -> float:
	if amount <= 0.0 or region == null or resource_depletion_state == null:
		return 0.0
	if not resource_depletion_state.has_method("consume_from_cells"):
		return 0.0
	var cells: Array = _get_region_cells(region)
	if cells.is_empty():
		return 0.0
	return float(resource_depletion_state.call("consume_from_cells", cells, resource_type, amount))


func _apply_depleted_resource_cells_to_grid(region: RefCounted, resource_type: StringName) -> void:
	if grid == null or region == null or resource_depletion_state == null:
		return
	if not resource_depletion_state.has_method("is_depleted"):
		return
	var depleted_cells: Array[Vector2i] = []
	for cell_variant in _get_region_cells(region):
		if typeof(cell_variant) != TYPE_VECTOR2I:
			continue
		var cell: Vector2i = cell_variant
		if not bool(resource_depletion_state.call("is_depleted", cell, resource_type)):
			continue
		if _apply_depleted_resource_cell_to_grid(cell, resource_type):
			depleted_cells.append(cell)
	if depleted_cells.is_empty():
		return
	for depleted_cell in depleted_cells:
		_remove_resource_cell_from_region(region, depleted_cell)
		_add_depleted_cell_as_region_adjacent_empty_cell(region, depleted_cell)
	_update_buildings_linked_to_region_resource_status(region, resource_type)
	if _is_resource_region_empty(region):
		_append_resource_region_depleted_event(region, resource_type)
	_invalidate_placement_reachability_cache()


func _apply_depleted_resource_cell_to_grid(cell: Vector2i, resource_type: StringName) -> bool:
	if grid == null:
		return false
	if not grid.has_method("is_inside") or not bool(grid.call("is_inside", cell)):
		return false
	var required_terrain: int = _get_required_resource_terrain_for_resource(resource_type)
	if required_terrain < 0:
		return false
	var current_terrain: int = int(grid.call("get_terrain", cell))
	if current_terrain != required_terrain and current_terrain != MapTypes.TerrainType.PLAIN:
		return false
	if current_terrain == required_terrain:
		grid.call("set_terrain", cell, MapTypes.TerrainType.PLAIN)
		if grid.has_method("set_blocks_movement"):
			grid.call("set_blocks_movement", cell, false)
	_refresh_depleted_resource_visual_cell(cell)
	return true


func _apply_restored_resource_depletion_to_world() -> void:
	if resource_depletion_state == null or not resource_depletion_state.has_method("export_changed_cells"):
		return
	var changed_cells_variant: Variant = resource_depletion_state.call("export_changed_cells")
	if typeof(changed_cells_variant) != TYPE_ARRAY:
		return
	var changed_cells: Array = changed_cells_variant
	var touched_regions: Dictionary = {}
	var applied_cell_count: int = 0
	for entry_variant in changed_cells:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if not bool(entry.get("depleted", false)):
			continue
		var resource_type: StringName = StringName(str(entry.get("resource_type", "")))
		if not _is_depletable_resource_type(resource_type):
			continue
		var cell: Vector2i = Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))
		if not _apply_depleted_resource_cell_to_grid(cell, resource_type):
			continue
		applied_cell_count += 1
		_remove_depleted_resource_cell_from_regions(cell, resource_type, touched_regions)
	for touched_region_variant in touched_regions.values():
		if typeof(touched_region_variant) != TYPE_DICTIONARY:
			continue
		var touched_region: Dictionary = touched_region_variant
		var region_variant: Variant = touched_region.get("region", null)
		if not (region_variant is RefCounted):
			continue
		var region: RefCounted = region_variant
		var region_resource_type: StringName = StringName(str(touched_region.get("resource_type", "")))
		_update_buildings_linked_to_region_resource_status(region, region_resource_type)
	if applied_cell_count > 0:
		_refresh_farmable_regions_after_resource_depletion()
	if applied_cell_count > 0 or not touched_regions.is_empty():
		_invalidate_placement_reachability_cache()


func _remove_depleted_resource_cell_from_regions(cell: Vector2i, resource_type: StringName, touched_regions: Dictionary) -> void:
	var required_terrain: int = _get_required_resource_terrain_for_resource(resource_type)
	if required_terrain < 0:
		return
	var regions_variant: Variant = resource_regions.get(required_terrain, [])
	if typeof(regions_variant) != TYPE_ARRAY:
		return
	var regions: Array = regions_variant
	for region_variant in regions:
		if not (region_variant is RefCounted):
			continue
		var region: RefCounted = region_variant
		if not _get_region_cells(region).has(cell):
			continue
		_remove_resource_cell_from_region(region, cell)
		_add_depleted_cell_as_region_adjacent_empty_cell(region, cell)
		var key: String = "%d:%d" % [required_terrain, int(region.get("region_id"))]
		touched_regions[key] = {
			"region": region,
			"resource_type": resource_type,
		}
		return


func _add_depleted_cell_as_region_adjacent_empty_cell(region: RefCounted, cell: Vector2i) -> void:
	if region == null:
		return
	if region.has_method("is_empty") and bool(region.call("is_empty")):
		return
	if region.has_method("add_adjacent_empty_cell"):
		region.call("add_adjacent_empty_cell", cell)


func _refresh_farmable_regions_after_resource_depletion() -> void:
	if grid == null:
		return
	var scanner: ResourceRegionScanner = ResourceRegionScannerScript.new()
	farmable_regions = scanner.scan_farmable_regions(grid)
	if placement_controller != null:
		_setup_placement_controller()


func _invalidate_placement_reachability_cache() -> void:
	if placement_controller != null and placement_controller.has_method("invalidate_reachability_cache"):
		placement_controller.call("invalidate_reachability_cache")


func _remove_resource_cell_from_region(region: RefCounted, cell: Vector2i) -> void:
	if region == null:
		return
	if region.has_method("remove_cell"):
		region.call("remove_cell", cell)
		return
	var cells: Array = _get_region_cells(region)
	if not cells.has(cell):
		return
	cells.erase(cell)
	region.set("area", cells.size())


func _update_buildings_linked_to_region_resource_status(region: RefCounted, resource_type: StringName) -> void:
	if region == null:
		return
	var region_id: int = int(region.get("region_id"))
	for building in initial_buildings:
		if building == null:
			continue
		if int(building.linked_region_id) != region_id:
			continue
		if MapTypes.get_resource_name_for_building(int(building.building_type)) != resource_type:
			continue
		_update_building_linked_resource_depleted_status(building, region, resource_type)


func _update_building_linked_resource_depleted_status(building: RefCounted, region: RefCounted, resource_type: StringName) -> void:
	if building == null or not building.has_method("set_linked_resource_depleted"):
		return
	var depleted: bool = region == null or _get_active_resource_cell_count(region, resource_type) <= 0
	building.call("set_linked_resource_depleted", depleted)


func _is_resource_region_empty(region: RefCounted) -> bool:
	if region == null:
		return true
	if region.has_method("is_empty"):
		return bool(region.call("is_empty"))
	return _get_region_cells(region).is_empty()


func _append_resource_region_depleted_event(region: RefCounted, resource_type: StringName) -> void:
	var resource_label: String = _get_resource_label(resource_type)
	var region_id: int = -1
	if region != null:
		region_id = int(region.get("region_id"))
	_append_event_log("%s资源区域 #%d 已采尽，绑定建筑将停止产出。" % [resource_label, region_id])


func _refresh_depleted_resource_visual_cell(grid_cell: Vector2i) -> void:
	var map_cell: Vector2i = _grid_cell_to_map_cell(grid_cell)
	var runtime_view: Variant = _get_semantic_runtime_view_for_visual_refresh()
	if runtime_view != null and runtime_view.has_method("mark_resource_cell_depleted_for_visuals"):
		runtime_view.call("mark_resource_cell_depleted_for_visuals", map_cell)
	_render_plain_ground_visual_cell(map_cell)
	_clear_resource_visual_cell(map_cell)


func _render_plain_ground_visual_cell(map_cell: Vector2i) -> void:
	if ground_layer == null:
		return
	var atlas_coords: Vector2i = TileRenderDefinitionScript.get_base_tile(GeneratedTileDataScript.TERRAIN_PLAIN)
	if atlas_coords == TileRenderDefinitionScript.INVALID_ATLAS:
		ground_layer.set_cell(map_cell, -1)
		return
	ground_layer.set_cell(map_cell, TileRenderDefinitionScript.TILE_SOURCE_ID, atlas_coords, 0)


func _clear_resource_visual_cell(map_cell: Vector2i) -> void:
	if resource_layer == null:
		return
	resource_layer.set_cell(map_cell, -1)


func _clear_building_footprint_resource_visuals(building: RefCounted) -> void:
	if building == null:
		return
	var runtime_view: Variant = _get_semantic_runtime_view_for_visual_refresh()
	for grid_cell in _get_building_footprint_cells(building):
		var map_cell: Vector2i = _grid_cell_to_map_cell(grid_cell)
		if runtime_view != null and runtime_view.has_method("mark_resource_cell_depleted_for_visuals"):
			runtime_view.call("mark_resource_cell_depleted_for_visuals", map_cell)
		_clear_resource_visual_cell(map_cell)


func _grid_cell_to_map_cell(grid_cell: Vector2i) -> Vector2i:
	var cell_offset: Vector2i = map_read_result.get("cell_offset", Vector2i.ZERO)
	return grid_cell + cell_offset


func _get_semantic_runtime_view_for_visual_refresh() -> Variant:
	if not has_method("get_semantic_runtime_view"):
		return null
	return call("get_semantic_runtime_view")


func _get_region_cells(region: RefCounted) -> Array:
	if region == null:
		return []
	var cells_variant: Variant = region.get("cells")
	if typeof(cells_variant) != TYPE_ARRAY:
		return []
	var cells: Array = cells_variant
	return cells


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
		return "税收系统未初始化"
	var daily_income: float = tax_system.get_daily_gold_per_person(governance_state.tax_policy) * float(max(governance_state.population, 0))
	var happiness_delta: float = tax_system.get_daily_happiness_delta(governance_state.tax_policy)
	var message: String = "暂无税收结算" if last_tax_message.is_empty() else last_tax_message
	return "税率：%s\n金币 +%.1f/天 | 幸福度 %+.1f/天\n%s" % [_get_current_tax_policy_label(), daily_income, happiness_delta, message]

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
	economy_status_label.text = "时间：%s\n%s\n%s\n%s\n库存：%s\n上分钟变化：%s\n%s\n%s" % [time_text, time_control_text, tax_text, happiness_text, resources_text, delta_text, selection_text, collection_text]


func _refresh_stage14_hud() -> void:
	_update_stage14_hud()


func _get_resource_inventory_text() -> String:
	if resource_inventory == null or not resource_inventory.has_method("get_all_resources"):
		return "未初始化"
	var resources: Dictionary = resource_inventory.call("get_all_resources")
	var food := int(float(resources.get(MapTypes.RESOURCE_FOOD, 0.0)))
	var wood := int(float(resources.get(MapTypes.RESOURCE_WOOD, 0.0)))
	var stone := int(float(resources.get(MapTypes.RESOURCE_STONE, 0.0)))
	var gold := int(float(resources.get(MapTypes.RESOURCE_GOLD, 0.0)))
	return "食物 %d / 木头 %d / 石材 %d / 金币 %d" % [food, wood, stone, gold]


func _get_resource_inventory_snapshot() -> Dictionary:
	if resource_inventory == null or not resource_inventory.has_method("get_all_resources"):
		return {}
	return resource_inventory.call("get_all_resources")

func _get_happiness_status_text() -> String:
	if happiness_system == null or governance_state == null:
		return "幸福度：未初始化"
	var lines: Array[String] = []
	lines.append("幸福度 %.1f" % governance_state.happiness)
	lines.append("情绪 %s" % _get_happiness_mood_label(governance_state.happiness))
	return "\n".join(lines)


func _get_happiness_mood_label(happiness: float) -> String:
	if happiness >= 80.0:
		return "愉快"
	if happiness >= 60.0:
		return "稳定"
	if happiness >= 40.0:
		return "不安"
	if happiness >= 20.0:
		return "愤怒"
	return "崩溃"


func _get_riot_status_text() -> String:
	if riot_system == null or governance_state == null:
		return "暴乱系统未初始化"
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
		return "胜负系统未初始化"
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
		_append_event_log("初始住宅已生成，村民会优先将其视为住所。")
		return
	if not building.is_production_building():
		return
	var region_text := "绑定资源板块 #%d" % int(building.linked_region_id)
	_append_event_log("初始%s已生成：%s" % [building.get_building_label(), region_text])


func _append_daily_happiness_events(report: Dictionary) -> void:
	if report.is_empty():
		return
	var summary := str(report.get("summary", ""))
	if not summary.is_empty():
		_append_event_log(summary)
	var food_status := str(report.get("food_status", ""))
	if food_status == "饥荒" or food_status == "不足":
		_append_event_log("食物短缺，幸福度 %+.1f" % float(report.get("food_delta", 0.0)))
	elif food_status == "刚好够吃" or food_status == "充足":
		_append_event_log("食物供给稳定，幸福度 %+.1f" % float(report.get("food_delta", 0.0)))
	var tax_delta := float(report.get("tax_delta", 0.0))
	if tax_delta < 0.0:
		_append_event_log("高税率引发不满，幸福度 %+.1f" % tax_delta)
	elif tax_delta > 0.0:
		_append_event_log("低税率提升支持，幸福度 %+.1f" % tax_delta)


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
	return "食物 %+0.2f / 木头 %+0.2f / 石材 %+0.2f / 金币 %+0.2f" % [food, wood, stone, gold]


func _update_placement_button_texts() -> void:
	_set_placement_button_text(farm_button, MapTypes.BuildingType.FARM, "农场")
	_set_placement_button_text(lumber_camp_button, MapTypes.BuildingType.LUMBER_CAMP, "伐木场")
	_set_placement_button_text(quarry_button, MapTypes.BuildingType.QUARRY, "采石场")
	_set_placement_button_text(house_button, MapTypes.BuildingType.HOUSE, "住宅")


func _set_placement_button_text(button: Button, building_type: int, base_text: String) -> void:
	if button == null:
		return
	button.text = "■ %s" % base_text if placement_mode_active and selected_building_type == building_type else base_text


func _get_placement_status_text() -> String:
	var lines: Array[String] = []
	if placement_mode_active and selected_building_type >= 0:
		lines.append("已选择：%s" % MapTypes.get_building_label(selected_building_type))
		if hovered_result != null:
			lines.append("格子：%s" % str(hovered_cell))
			if bool(hovered_result.can_place):
				lines.append("放置：合法")
			else:
				lines.append("放置：非法 - %s" % str(hovered_result.reason))
	else:
		lines.append("已选择：无")
	if not last_placement_message.is_empty():
		lines.append(last_placement_message)
	return "\n".join(lines)

func _register_occupied_cell(cell: Vector2i) -> void:
	occupied_cells[cell] = true


func _register_occupied_cells_for_building(building: RefCounted) -> void:
	if building == null:
		return
	BuildingFootprintRulesScript.register_building_footprint(occupied_cells, int(building.building_type), building.position)


func _get_building_footprint_cells(building: RefCounted) -> Array[Vector2i]:
	if building == null:
		return []
	return BuildingFootprintRulesScript.get_building_footprint_cells(int(building.building_type), building.position)


func _find_home_building() -> RefCounted:
	for building in initial_buildings:
		if int(building.building_type) == MapTypes.BuildingType.HOUSE:
			return building
	return _find_castle_building()


func _find_castle_building() -> RefCounted:
	for building in initial_buildings:
		if building != null and int(building.building_type) == MapTypes.BuildingType.TOWN_CENTER:
			return building
	return null


func _find_building_at_cell(building_type: int, cell: Vector2i) -> RefCounted:
	for building in initial_buildings:
		if building != null and int(building.building_type) == building_type and building.position == cell:
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


func _ensure_building_hover_outline_node(building_node: Node2D) -> void:
	if building_node == null or not is_instance_valid(building_node):
		return
	if building_node.get_node_or_null(BUILDING_HOVER_OUTLINE_ROOT_NAME) != null:
		return

	var outline_root := CanvasGroup.new()
	outline_root.name = BUILDING_HOVER_OUTLINE_ROOT_NAME
	outline_root.visible = false
	outline_root.z_index = BUILDING_HOVER_OUTLINE_Z_INDEX
	outline_root.fit_margin = 8.0
	outline_root.clear_margin = 8.0
	outline_root.material = _create_building_hover_outline_material()
	building_node.add_child(outline_root)

	for child in building_node.get_children():
		if child == outline_root:
			continue
		if not _should_copy_for_building_hover_outline(child):
			continue
		var outline_copy := child.duplicate() as CanvasItem
		if outline_copy == null:
			continue
		outline_root.add_child(outline_copy)
		_prune_building_hover_outline_duplicate(outline_copy)


func _should_copy_for_building_hover_outline(node: Node) -> bool:
	if node == null:
		return false
	if node.name == BUILDING_HOVER_OUTLINE_ROOT_NAME:
		return false
	if node is Control:
		return false
	if node is Area2D:
		return false
	if node is CollisionShape2D:
		return false
	if not (node is CanvasItem):
		return false
	match String(node.name):
		"HoverArea", "InteractionArea", "HoverPreview", "InteractionShape", "ReadyIndicator", "StorageLabel", "Label":
			return false
		_:
			return true


func _prune_building_hover_outline_duplicate(node: Node) -> void:
	if node == null:
		return
	for child in node.get_children():
		if _should_copy_for_building_hover_outline(child):
			_prune_building_hover_outline_duplicate(child)
		else:
			child.queue_free()


func _create_building_hover_outline_material() -> ShaderMaterial:
	var outline_shader_material := ShaderMaterial.new()
	outline_shader_material.shader = BUILDING_HOVER_OUTLINE_SHADER
	outline_shader_material.set_shader_parameter("outline_color", Color(1.0, 0.88, 0.24, 1.0))
	outline_shader_material.set_shader_parameter("outline_width_px", 2)
	outline_shader_material.set_shader_parameter("alpha_threshold", 0.05)
	return outline_shader_material


func _get_building_placement_anchor_offset(building_node: Node2D) -> Vector2:
	if building_node == null or not is_instance_valid(building_node):
		return Vector2.ZERO
	var placement_anchor := building_node.get_node_or_null("PlacementAnchor") as Node2D
	if placement_anchor == null:
		return Vector2.ZERO
	return placement_anchor.position


func _ensure_building_click_area(building_node: Node2D, building: RefCounted) -> void:
	if building_node == null or building == null:
		return
	var hover_area := building_node.get_node_or_null("HoverArea") as Area2D
	if hover_area != null:
		if not hover_area.has_signal("mouse_entered") or not hover_area.has_signal("mouse_exited"):
			return
		if not hover_area.mouse_entered.is_connected(Callable(self, "_on_building_mouse_entered").bind(building_node)):
			hover_area.mouse_entered.connect(Callable(self, "_on_building_mouse_entered").bind(building_node))
		if not hover_area.mouse_exited.is_connected(Callable(self, "_on_building_mouse_exited").bind(building_node)):
			hover_area.mouse_exited.connect(Callable(self, "_on_building_mouse_exited").bind(building_node))
		if not hover_area.input_event.is_connected(Callable(self, "_on_building_input_event").bind(building, building_node)):
			hover_area.input_event.connect(Callable(self, "_on_building_input_event").bind(building, building_node))
		if hover_area.has_meta("building_data"):
			hover_area.set_meta("building_data", building)
		else:
			hover_area.set_meta("building_data", building)
		hover_area.set_meta("building_node", building_node)
		return
	if building_node.has_node("InteractionArea"):
		return
	var interaction_area := Area2D.new()
	interaction_area.name = "InteractionArea"
	interaction_area.input_pickable = true
	interaction_area.collision_layer = 2
	interaction_area.collision_mask = 0
	interaction_area.set_meta("building_data", building)
	interaction_area.set_meta("building_node", building_node)
	interaction_area.mouse_entered.connect(Callable(self, "_on_building_mouse_entered").bind(building_node))
	interaction_area.mouse_exited.connect(Callable(self, "_on_building_mouse_exited").bind(building_node))

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
	last_collection_message = "%s 已选中" % building.get_building_label()
	_append_event_log(last_collection_message)
	_update_all_building_visual_states()
	_update_economy_ui()
	_update_worker_control_ui()
	_refresh_stage14_hud()


func _set_selected_building(building: RefCounted, building_node: Node2D) -> void:
	selected_building_data = building
	selected_building_node = building_node
	_update_worker_control_ui()
	_update_placement_ui()


func _clear_selected_building() -> void:
	var had_selection := selected_building_data != null or selected_building_node != null
	selected_building_data = null
	selected_building_node = null
	_update_worker_control_ui()
	_update_placement_ui()
	if not had_selection:
		return
	_update_economy_ui()
	_refresh_stage14_hud()


func _claim_building_storage(building: RefCounted) -> Dictionary:
	if building == null or resource_inventory == null:
		return {}
	var claimed: Dictionary = building.claim_storage()
	if not claimed.is_empty():
		resource_inventory.call("apply_delta", claimed)
	return claimed


func _can_harvest_selected_building() -> bool:
	if selected_building_data == null:
		return false
	if not selected_building_data.has_method("has_claimable_resources"):
		return false
	return bool(selected_building_data.call("has_claimable_resources"))


func _on_harvest_button_pressed() -> void:
	if selected_building_data == null:
		return
	var claimed := _claim_building_storage(selected_building_data)
	last_collection_message = _format_claim_message(selected_building_data, claimed)
	_append_event_log(last_collection_message)
	_resume_storage_blocked_worker_tasks_for_building(selected_building_data)
	_update_all_building_visual_states()
	_update_placement_ui()
	_update_worker_control_ui()
	_update_economy_ui()
	_refresh_stage14_hud()


func _resume_storage_blocked_worker_tasks_for_building(building: RefCounted) -> void:
	if building == null:
		return
	var villager_keys: Array = worker_resource_tasks.keys()
	for villager_variant in villager_keys:
		if not (villager_variant is Node2D):
			continue
		var villager := villager_variant as Node2D
		if villager == null or not is_instance_valid(villager):
			continue
		var task_variant: Variant = worker_resource_tasks.get(villager, {})
		if typeof(task_variant) != TYPE_DICTIONARY:
			continue
		var task: Dictionary = task_variant
		if task.get("building", null) != building:
			continue
		var task_state: StringName = StringName(str(task.get("state", RESOURCE_TASK_IDLE)))
		if task_state == RESOURCE_TASK_WAITING_FOR_STORAGE:
			_resume_waiting_worker_resource_task(villager, task)
		elif _is_legacy_storage_full_failed_worker_resource_task(task):
			_resume_legacy_storage_full_failed_worker_resource_task(villager, building, task)


func _resume_waiting_worker_resource_task(villager: Node2D, task: Dictionary) -> void:
	if not _can_worker_resource_task_deliver_to_storage(task):
		worker_resource_tasks[villager] = task
		_update_worker_resource_task_visual_status(villager, task)
		return
	task["state"] = RESOURCE_TASK_DELIVERING
	task["failure_reason"] = ""
	worker_resource_tasks[villager] = task
	_try_deliver_worker_resource_task(villager, task)


func _is_legacy_storage_full_failed_worker_resource_task(task: Dictionary) -> bool:
	if StringName(str(task.get("state", RESOURCE_TASK_IDLE))) != RESOURCE_TASK_FAILED:
		return false
	return str(task.get("failure_reason", "")).contains("库存已满")


func _resume_legacy_storage_full_failed_worker_resource_task(villager: Node2D, building: RefCounted, task: Dictionary) -> void:
	var carried_amount: float = max(float(task.get("carried_amount", 0.0)), 0.0)
	if carried_amount > 0.0:
		task["state"] = RESOURCE_TASK_DELIVERING
		task["failure_reason"] = ""
		worker_resource_tasks[villager] = task
		_try_deliver_worker_resource_task(villager, task)
		return
	var target: Dictionary = _find_resource_collection_target_for_building(building, villager)
	if not bool(target.get("ok", false)):
		worker_resource_tasks[villager] = _build_failed_worker_resource_task(villager, building, str(target.get("reason", "无法找到资源采集目标。")))
		_update_worker_resource_task_visual_status(villager, worker_resource_tasks[villager])
		return
	var restarted_task: Dictionary = _build_worker_resource_task(villager, building, target)
	worker_resource_tasks[villager] = restarted_task
	_retarget_villager_to_resource_task(villager, restarted_task)


func _format_claim_message(building: RefCounted, claimed: Dictionary) -> String:
	var parts: Array[String] = []
	for resource_type in claimed.keys():
		parts.append("%s +%.2f" % [_get_resource_label(resource_type), float(claimed[resource_type])])
	if parts.is_empty():
		return "%s %s" % [building.get_building_label(), building.get_claim_empty_message()]
	return "%s 已领取：%s" % [building.get_building_label(), " / ".join(parts)]


func _get_selected_building_management_text() -> String:
	if selected_building_data == null:
		return ""
	var parts: Array[String] = [selected_building_data.get_building_label()]
	if selected_building_data.has_method("get_storage_summary"):
		parts.append("库存：%s" % selected_building_data.call("get_storage_summary"))
	if _can_harvest_selected_building():
		parts.append("可收获")
	else:
		parts.append("暂无可收获资源")
	var resource_remaining_text: String = _get_selected_building_resource_remaining_text(selected_building_data)
	if not resource_remaining_text.is_empty():
		parts.append(resource_remaining_text)
	return "\n".join(parts)


func _get_selected_building_text() -> String:
	if selected_building_data == null:
		return "选中建筑：无"
	var parts: Array[String] = ["选中建筑：%s" % selected_building_data.get_building_label()]
	if selected_building_data.has_method("has_workers") and bool(selected_building_data.call("has_workers")):
		var present_workers := _get_present_workers_for_building(selected_building_data)
		var resting_workers := _get_resting_workers_for_building(selected_building_data)
		parts.append("工人：%d/%d" % [
			int(selected_building_data.call("get_worker_count")),
			int(selected_building_data.call("get_worker_capacity"))
		])
		parts.append("到岗：%d" % present_workers)
		parts.append("休息：%d" % resting_workers)
	parts.append("库存：%s" % selected_building_data.get_storage_summary())
	var resource_remaining_text: String = _get_selected_building_resource_remaining_text(selected_building_data)
	if not resource_remaining_text.is_empty():
		parts.append(resource_remaining_text)
	if selected_building_data.has_method("is_linked_resource_depleted") and bool(selected_building_data.call("is_linked_resource_depleted")):
		parts.append("附近资源已采尽")
	return " | ".join(parts)


func _get_selected_building_resource_remaining_text(building: RefCounted) -> String:
	if building == null:
		return ""
	var resource_type: StringName = MapTypes.get_resource_name_for_building(int(building.building_type))
	if not _is_depletable_resource_type(resource_type):
		return ""
	var region: RefCounted = _get_resource_region_for_building(building, _get_regions_by_id())
	if region == null:
		return "绑定资源剩余：%s 0.0（有效格 0）" % _get_resource_label(resource_type)
	var remaining_amount: float = _get_region_remaining_resource_amount(region, resource_type)
	if is_inf(remaining_amount):
		return ""
	var active_cell_count: int = _get_active_resource_cell_count(region, resource_type)
	return "绑定资源剩余：%s %.1f（有效格 %d）" % [_get_resource_label(resource_type), remaining_amount, active_cell_count]


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
	var storage_label := building_node.get_node_or_null("StorageLabel")
	if storage_label is Label:
		var label := storage_label as Label
		label.visible = building.can_store_resources()
		label.text = building.get_storage_summary()
		label.modulate = Color(0.85, 1.0, 0.75, 1.0) if building.has_claimable_resources() else Color(1.0, 1.0, 1.0, 0.8)
	var ready_indicator := building_node.get_node_or_null("ReadyIndicator")
	if ready_indicator is CanvasItem:
		(ready_indicator as CanvasItem).visible = bool(building.is_active) and building.has_claimable_resources()


func _set_building_hover_outline_visible(building_node: Node2D, hover_visible: bool) -> void:
	if building_node == null or not is_instance_valid(building_node):
		return
	var hover_outline := building_node.get_node_or_null(BUILDING_HOVER_OUTLINE_ROOT_NAME) as CanvasItem
	if hover_outline != null:
		hover_outline.visible = hover_visible
	var hover_area := building_node.get_node_or_null("HoverArea") as Area2D
	if hover_area != null:
		var hover_preview := hover_area.get_node_or_null("HoverPreview") as CanvasItem
		if hover_preview != null:
			hover_preview.visible = false


func _refresh_building_hover_visuals() -> void:
	for child in buildings_root.get_children():
		if child is Node2D:
			var building_node := child as Node2D
			_set_building_hover_outline_visible(building_node, building_node == hovered_building_node)


func _on_building_mouse_entered(building_node: Node2D) -> void:
	if building_node == null or not is_instance_valid(building_node):
		return
	hovered_building_node = building_node
	_refresh_building_hover_visuals()


func _on_building_mouse_exited(building_node: Node2D) -> void:
	if building_node == null or hovered_building_node != building_node:
		return
	hovered_building_node = null
	_refresh_building_hover_visuals()


func _get_resource_label(resource_type: StringName) -> String:
	match resource_type:
		MapTypes.RESOURCE_FOOD:
			return "食物"
		MapTypes.RESOURCE_WOOD:
			return "木头"
		MapTypes.RESOURCE_STONE:
			return "石材"
		MapTypes.RESOURCE_GOLD:
			return "金币"
		_:
			return str(resource_type)


func debug_stage8_5_apply_minute() -> void:
	_apply_minute_economy()


func debug_resource_collection_target_for_building(building: RefCounted) -> Dictionary:
	return _find_resource_collection_target_for_building(building)


func debug_worker_resource_tasks_for_building(building: RefCounted) -> Array:
	return _get_worker_resource_tasks_for_building(building)


func debug_worker_resource_task_for_villager(villager: Node2D) -> Dictionary:
	if villager == null or not worker_resource_tasks.has(villager):
		return {}
	var task: Dictionary = worker_resource_tasks.get(villager, {})
	return task.duplicate()


func debug_sync_worker_resource_task_state(villager: Node2D) -> void:
	_sync_worker_resource_task_state(villager)


func debug_tick_worker_resource_tasks(delta_game_minutes: float) -> void:
	_tick_worker_resource_tasks(delta_game_minutes)


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
	for villager in characters_root.get_children():
		if villager != null and is_instance_valid(villager) and villager.has_method("debug_advance_minutes"):
			villager.call("debug_advance_minutes", float(minute_count))
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


func debug_get_worker_cycle_snapshot(building_type: int) -> Dictionary:
	var target_building: RefCounted = null
	for building in initial_buildings:
		if building != null and int(building.building_type) == building_type:
			target_building = building
			break
	if target_building == null:
		return {}
	return {
		"worker_count": int(target_building.call("get_worker_count")) if target_building.has_method("get_worker_count") else 0,
		"present_workers": _get_present_workers_for_building(target_building),
		"resting_workers": _get_resting_workers_for_building(target_building),
		"assigned_villagers": _get_villagers_for_building(target_building).size(),
	}


func debug_is_villager_walkable_cell(cell: Vector2i) -> bool:
	return _is_villager_walkable_cell(cell)


func debug_build_villager_cell_path(start_cell: Vector2i, goal_cell: Vector2i) -> Array[Vector2i]:
	return _build_villager_cell_path(start_cell, goal_cell)


func debug_get_villager_grid_cell(villager: Node2D) -> Vector2i:
	if villager == null:
		return Vector2i(-1, -1)
	return _root_position_to_grid_cell(villager.position, characters_root)

func debug_stage8_5_claim_building(building: RefCounted) -> Dictionary:
	var before_resources: Dictionary = {}
	if resource_inventory != null and resource_inventory.has_method("get_all_resources"):
		before_resources = resource_inventory.call("get_all_resources")
	_set_selected_building(building, _find_building_node(building))
	_on_harvest_button_pressed()
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


func _get_building_route_point_for_root(building: RefCounted, target_root: Node2D, fallback_offset: Vector2) -> Vector2:
	var building_node := _find_building_node(building)
	if building_node != null and is_instance_valid(building_node):
		var route_point := building_node.get_node_or_null(VILLAGER_ROUTE_POINT_NAME) as Node2D
		if route_point != null:
			return target_root.to_local(route_point.global_position)
		var placement_anchor := building_node.get_node_or_null("PlacementAnchor") as Node2D
		if placement_anchor != null:
			return target_root.to_local(placement_anchor.global_position) + fallback_offset
		return target_root.to_local(building_node.global_position) + fallback_offset
	return _get_building_position_for_root(building, target_root) + fallback_offset


func _grid_cell_to_root_position(grid_cell: Vector2i, target_root: Node2D) -> Vector2:
	var map_cell: Vector2i = grid_cell + (map_read_result.get("cell_offset", Vector2i.ZERO) as Vector2i)
	var global_position := ground_layer.to_global(ground_layer.map_to_local(map_cell))
	return target_root.to_local(global_position)


func _get_building_node_name(building: RefCounted) -> String:
	return "%s_%d_%d" % [MapTypes.get_building_label(int(building.building_type)).replace(" ", ""), building.position.x, building.position.y]


func _print_initial_building_summary(spawner: RefCounted) -> void:
	if not enable_console_debug_logs:
		for warning in spawner.last_spawn_warnings:
			push_warning("stage4 initial building skipped: %s" % warning)
		return

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
	if not enable_console_debug_logs:
		return

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
	if not enable_console_debug_logs:
		return

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
	if not enable_console_debug_logs:
		return

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
	_sync_worker_resource_task_state(villager)
	if state_name == &"resting":
		call_deferred("_rebalance_villager_assignments")
	if selected_building_data != null:
		_update_worker_control_ui()
		_update_economy_ui()
		_refresh_stage14_hud()
	if enable_console_debug_logs:
		print("stage6 villager state | name=", villager.name, " state=", state_name)


func _update_worker_control_ui() -> void:
	var should_show := not placement_mode_active and _is_selected_building_manageable_production()
	if worker_control_panel != null:
		worker_control_panel.visible = should_show
	if worker_popup_panel != null:
		worker_popup_panel.visible = false
	if worker_status_label != null:
		worker_status_label.visible = true
		worker_status_label.text = _get_worker_control_status_text()
	if worker_count_label != null:
		worker_count_label.visible = true
		worker_count_label.text = _get_worker_control_count_text()
	if worker_minus_button != null:
		worker_minus_button.visible = true
		worker_minus_button.disabled = not _can_change_selected_building_workers(-1)
	if worker_plus_button != null:
		worker_plus_button.visible = true
		worker_plus_button.disabled = not _can_change_selected_building_workers(1)
	if worker_popup_status_label != null:
		worker_popup_status_label.text = _get_worker_control_status_text()
	if worker_popup_count_label != null:
		worker_popup_count_label.text = _get_worker_control_count_text()
	if worker_popup_minus_button != null:
		worker_popup_minus_button.disabled = not _can_change_selected_building_workers(-1)
	if worker_popup_plus_button != null:
		worker_popup_plus_button.disabled = not _can_change_selected_building_workers(1)
	_update_placement_ui()
	if should_show and worker_popup_panel != null and worker_popup_panel.visible:
		_position_worker_popup_panel()


func _should_show_worker_popup() -> bool:
	if placement_mode_active:
		return false
	if selected_building_data == null or selected_building_node == null:
		return false
	if not is_instance_valid(selected_building_node):
		return false
	if not selected_building_data.has_method("has_workers"):
		return false
	return bool(selected_building_data.call("has_workers"))


func _get_worker_control_status_text() -> String:
	if selected_building_data == null:
		return ""
	var building_label: String = selected_building_data.get_building_label()
	var traveling_workers := _get_traveling_workers_for_building(selected_building_data)
	var resting_workers := _get_resting_workers_for_building(selected_building_data)
	var present_workers := _get_present_workers_for_building(selected_building_data)
	return "%s | 到岗 %d | 休息 %d | 在途 %d" % [
		building_label,
		present_workers,
		resting_workers,
		traveling_workers,
	]


func _get_worker_control_count_text() -> String:
	if selected_building_data == null:
		return "0/0"
	if not selected_building_data.has_method("get_worker_count") or not selected_building_data.has_method("get_worker_capacity"):
		return "0/0"
	var worker_count := int(selected_building_data.call("get_worker_count"))
	var capacity := int(selected_building_data.call("get_worker_capacity"))
	var idle_population := _get_idle_population()
	return "编制 %d/%d | 全局空闲 %d" % [worker_count, capacity, idle_population]


func _get_idle_population() -> int:
	var population := int(governance_state.population) if governance_state != null else 0
	return max(population - _get_assigned_worker_total(), 0)


func _can_change_selected_building_workers(delta: int) -> bool:
	if selected_building_data == null:
		return false
	if not selected_building_data.has_method("get_worker_count") or not selected_building_data.has_method("get_worker_capacity"):
		return false
	var current_count := int(selected_building_data.call("get_worker_count"))
	var capacity := int(selected_building_data.call("get_worker_capacity"))
	if delta < 0:
		return current_count > 0
	if delta > 0:
		return current_count < capacity and _get_idle_population() > 0
	return false


func _adjust_selected_building_workers(delta: int) -> bool:
	if not _can_change_selected_building_workers(delta):
		return false
	var current_count := int(selected_building_data.call("get_worker_count"))
	var capacity := int(selected_building_data.call("get_worker_capacity"))
	var next_count := clampi(current_count + delta, 0, capacity)
	if delta > 0:
		next_count = min(next_count, current_count + _get_idle_population())
	if next_count == current_count:
		return false
	selected_building_data.call("set_worker_count", next_count)
	last_collection_message = "%s 工人 %d/%d" % [
		selected_building_data.get_building_label(),
		next_count,
		capacity,
	]
	_append_event_log(last_collection_message)
	_rebalance_villager_assignments()
	_update_top_resource_bar()
	_update_worker_control_ui()
	_update_placement_ui()
	_update_economy_ui()
	_refresh_stage14_hud()
	return true


func _on_worker_minus_button_pressed() -> void:
	_adjust_selected_building_workers(-1)


func _on_worker_plus_button_pressed() -> void:
	_adjust_selected_building_workers(1)


func _position_worker_popup_panel() -> void:
	if worker_popup_panel == null or not worker_popup_panel.visible:
		return
	if selected_building_node == null or not is_instance_valid(selected_building_node):
		worker_popup_panel.visible = false
		return
	var anchor_world := _get_selected_building_popup_anchor_world()
	var screen_anchor: Vector2 = get_viewport().get_canvas_transform() * anchor_world
	var popup_size := worker_popup_panel.size
	if popup_size == Vector2.ZERO:
		popup_size = worker_popup_panel.get_combined_minimum_size()
	var viewport_rect := _get_game_viewport_rect()
	var next_x := screen_anchor.x - popup_size.x * 0.5
	var next_y := screen_anchor.y - popup_size.y - WORKER_POPUP_Y_OFFSET
	next_x = clampf(next_x, viewport_rect.position.x + WORKER_POPUP_MARGIN, viewport_rect.end.x - popup_size.x - WORKER_POPUP_MARGIN)
	next_y = clampf(next_y, viewport_rect.position.y + WORKER_POPUP_MARGIN, viewport_rect.end.y - popup_size.y - WORKER_POPUP_MARGIN)
	worker_popup_panel.position = Vector2(next_x, next_y)


func _show_build_cost_tooltip(building_type: int, anchor_button: Control) -> void:
	if build_cost_tooltip_panel == null or anchor_button == null:
		return
	if build_cost_tooltip_title_label != null:
		build_cost_tooltip_title_label.text = "%s 建造消耗" % MapTypes.get_building_label(building_type)
	if build_cost_tooltip_cost_label != null:
		build_cost_tooltip_cost_label.text = _format_build_cost_text(building_type)
	build_cost_tooltip_panel.visible = true
	call_deferred("_position_build_cost_tooltip", anchor_button)


func _hide_build_cost_tooltip() -> void:
	if build_cost_tooltip_panel != null:
		build_cost_tooltip_panel.visible = false


func _format_build_cost_text(building_type: int) -> String:
	var cost: Dictionary = MapTypes.get_building_cost(building_type)
	if cost.is_empty():
		return "无消耗"
	var order: Array[StringName] = [
		MapTypes.RESOURCE_WOOD,
		MapTypes.RESOURCE_STONE,
		MapTypes.RESOURCE_GOLD,
		MapTypes.RESOURCE_FOOD,
	]
	var parts: Array[String] = []
	for resource_type in order:
		if not cost.has(resource_type):
			continue
		parts.append("%s %d" % [_get_resource_label(resource_type), int(round(float(cost[resource_type])))])
	return "\n".join(parts)


func _position_build_cost_tooltip(anchor_button: Control) -> void:
	if build_cost_tooltip_panel == null or not build_cost_tooltip_panel.visible or anchor_button == null:
		return
	var tooltip_size := build_cost_tooltip_panel.size
	if tooltip_size == Vector2.ZERO:
		tooltip_size = build_cost_tooltip_panel.get_combined_minimum_size()
	var button_rect := anchor_button.get_global_rect()
	var viewport_rect := get_viewport_rect()
	var next_x := button_rect.position.x - tooltip_size.x - 12.0
	if next_x < 0.0:
		next_x = button_rect.end.x + 12.0
	var next_y := button_rect.position.y + (button_rect.size.y - tooltip_size.y) * 0.5
	next_x = clampf(next_x, viewport_rect.position.x + 8.0, viewport_rect.end.x - tooltip_size.x - 8.0)
	next_y = clampf(next_y, viewport_rect.position.y + 8.0, viewport_rect.end.y - tooltip_size.y - 8.0)
	build_cost_tooltip_panel.position = Vector2(next_x, next_y)


func _get_selected_building_popup_anchor_world() -> Vector2:
	if selected_building_node == null or not is_instance_valid(selected_building_node):
		return Vector2.ZERO
	var anchor_world := selected_building_node.global_position
	var placement_anchor := selected_building_node.get_node_or_null("PlacementAnchor") as Node2D
	if placement_anchor != null:
		anchor_world = placement_anchor.global_position
	var hover_area := selected_building_node.get_node_or_null("HoverArea") as Area2D
	if hover_area != null:
		anchor_world.x = hover_area.global_position.x
		var hover_shape := hover_area.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if hover_shape != null and hover_shape.shape is RectangleShape2D:
			var rect_shape := hover_shape.shape as RectangleShape2D
			anchor_world.y = hover_area.global_position.y - rect_shape.size.y * 0.5
		else:
			anchor_world.y = hover_area.global_position.y
	return anchor_world


func _is_pointer_over_worker_popup() -> bool:
	if worker_popup_panel == null or not worker_popup_panel.visible:
		return false
	return worker_popup_panel.get_global_rect().has_point(get_viewport().get_mouse_position())


func _is_screen_position_over_interactive_panel(screen_position: Vector2) -> bool:
	var panels: Array[Control] = [
		placement_panel,
		worker_popup_panel,
		build_cost_tooltip_panel,
		top_resource_bar,
		time_control_panel,
		tax_panel,
		happiness_panel,
		riot_panel,
		victory_panel,
		hud_panel,
	]
	for panel in panels:
		if panel != null and panel.visible and panel.get_global_rect().has_point(screen_position):
			return true
	return false


func debug_stage7_5_select_building(building_type: int) -> bool:
	for building in initial_buildings:
		if building != null and int(building.building_type) == building_type:
			var building_node := _find_building_node(building)
			_set_selected_building(building, building_node)
			return true
	return false


func debug_stage7_5_adjust_selected_workers(delta: int) -> bool:
	return _adjust_selected_building_workers(delta)
