class_name Villager
extends Node2D

signal state_changed(villager: Node2D, state_name: StringName)

enum VillagerState {
	IDLE,
	GOING_TO_WORK,
	WORKING,
	RETURNING_HOME,
	RESTING,
	WANDERING,
}

const RESOURCE_TASK_STATE_GOING_TO_RESOURCE := &"going_to_resource"
const RESOURCE_TASK_STATE_COLLECTING := &"collecting"
const RESOURCE_TASK_STATE_RETURNING_TO_BUILDING := &"returning_to_building"
const RESOURCE_TASK_STATE_DELIVERING := &"delivering"
const RESOURCE_TASK_STATE_RESTING := &"resting"
const RESOURCE_TYPE_WOOD := &"wood"
const RESOURCE_TYPE_STONE := &"stone"

@export var move_speed: float = 55.0
@export var minimum_work_minutes: float = 90.0
@export var rest_duration_minutes: float = 30.0
@export var idle_duration: float = 1.0
@export var arrival_distance: float = 4.0
@export var home_position: Vector2 = Vector2.ZERO
@export var work_position: Vector2 = Vector2.ZERO
@export var wander_radius: float = 96.0
@export var show_status_label: bool = true

var work_duration: float:
	get:
		return minimum_work_minutes
	set(value):
		minimum_work_minutes = max(value, 0.0)

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var status_label: Label = $StatusLabel

var current_state: VillagerState = VillagerState.IDLE
var _target_position: Vector2 = Vector2.ZERO
var _state_timer: float = 0.0
var _resource_work_status_text: String = ""
var _resource_work_status_color: Color = Color(1.0, 1.0, 1.0, 0.92)
var _resource_task_animation_state: StringName = &""
var _resource_task_animation_resource_type: StringName = &""
var _resource_task_animation_carried_amount: float = 0.0
var _resource_task_animation_has_facing_override: bool = false
var _resource_task_animation_facing_left: bool = false
var _route_ready: bool = false
var _pending_initialization: bool = false
var _pending_start_delay: float = 0.0
var _last_horizontal_sign: float = 1.0
var _wander_bounds: Rect2 = Rect2()
var _wander_target: Vector2 = Vector2.ZERO
var _wander_pause_timer: float = 0.0
var _wander_center: Vector2 = Vector2.ZERO
var _wander_mode: bool = false
var _route_builder: Callable = Callable()
var _wander_target_builder: Callable = Callable()
var _navigation_points: Array[Vector2] = []
var _navigation_index: int = 0


func _ready() -> void:
	if _pending_initialization:
		_initialize_route()
	elif _route_ready:
		_play_idle_animation()
	_update_status_label()


func setup_route(home: Vector2, work: Vector2, start_delay: float = 0.0, route_builder: Callable = Callable()) -> void:
	_wander_mode = false
	home_position = home
	work_position = work
	position = home_position
	_set_route_builder(route_builder)
	_clear_navigation_path()
	_route_ready = true
	_pending_start_delay = max(start_delay, 0.0)
	_pending_initialization = true

	if is_node_ready():
		_initialize_route()


func setup_idle_wander(
	anchor: Vector2,
	wander_bounds: Rect2,
	start_delay: float = 0.0,
	next_wander_radius: float = 96.0,
	route_builder: Callable = Callable(),
	wander_target_builder: Callable = Callable()
) -> void:
	_wander_mode = true
	home_position = anchor
	work_position = anchor
	position = anchor
	wander_radius = max(next_wander_radius, 8.0)
	_wander_bounds = wander_bounds
	_wander_center = wander_bounds.get_center()
	_set_route_builder(route_builder)
	_set_wander_target_builder(wander_target_builder)
	_clear_navigation_path()
	_route_ready = true
	_pending_start_delay = max(start_delay, 0.0)
	_pending_initialization = true
	if is_node_ready():
		_initialize_wander()


func retarget_to_work(home: Vector2, work: Vector2, route_builder: Callable = Callable()) -> void:
	_wander_mode = false
	home_position = home
	work_position = work
	_set_route_builder(route_builder)
	_clear_navigation_path()
	_route_ready = true
	_pending_initialization = false
	_pending_start_delay = 0.0
	_set_state(VillagerState.GOING_TO_WORK)


func set_work_duration_minutes(next_duration: float) -> void:
	minimum_work_minutes = max(next_duration, 0.0)
	if current_state == VillagerState.WORKING:
		_state_timer = minimum_work_minutes


func update_work_cycle_targets(home: Vector2, work: Vector2, route_builder: Callable = Callable()) -> void:
	home_position = home
	work_position = work
	_set_route_builder(route_builder)
	_route_ready = true
	match current_state:
		VillagerState.GOING_TO_WORK:
			_target_position = work_position
			_rebuild_navigation_path(_target_position)
		VillagerState.WORKING:
			_target_position = work_position
			_clear_navigation_path()
		VillagerState.RETURNING_HOME:
			_target_position = home_position
			_rebuild_navigation_path(_target_position)
		VillagerState.RESTING:
			_target_position = home_position
			_clear_navigation_path()


func force_return_home_from_work() -> void:
	if current_state == VillagerState.GOING_TO_WORK or current_state == VillagerState.WORKING or current_state == VillagerState.RETURNING_HOME:
		_set_state(VillagerState.RETURNING_HOME)


func set_resource_work_status(text: String, color: Color = Color(1.0, 1.0, 1.0, 0.92)) -> void:
	_resource_work_status_text = text
	_resource_work_status_color = color
	_update_status_label()


func clear_resource_work_status() -> void:
	_resource_work_status_text = ""
	_update_status_label()


func set_resource_task_animation_state(task_state: StringName, resource_type: StringName, carried_amount: float = 0.0) -> void:
	_resource_task_animation_state = task_state
	_resource_task_animation_resource_type = resource_type
	_resource_task_animation_carried_amount = max(carried_amount, 0.0)
	_refresh_resource_task_animation()


func set_resource_task_animation_facing_override(has_override: bool, facing_left: bool = false) -> void:
	_resource_task_animation_has_facing_override = has_override
	_resource_task_animation_facing_left = facing_left
	_refresh_resource_task_animation()


func clear_resource_task_animation_state() -> void:
	_resource_task_animation_state = &""
	_resource_task_animation_resource_type = &""
	_resource_task_animation_carried_amount = 0.0
	_resource_task_animation_has_facing_override = false
	_resource_task_animation_facing_left = false
	_refresh_resource_task_animation()


func retarget_to_idle(
	anchor: Vector2,
	wander_bounds: Rect2,
	next_wander_radius: float = 96.0,
	route_builder: Callable = Callable(),
	wander_target_builder: Callable = Callable()
) -> void:
	_wander_mode = true
	home_position = anchor
	work_position = anchor
	wander_radius = max(next_wander_radius, 8.0)
	_wander_bounds = wander_bounds
	_wander_center = wander_bounds.get_center()
	_set_route_builder(route_builder)
	_set_wander_target_builder(wander_target_builder)
	_clear_navigation_path()
	_route_ready = true
	_pending_initialization = false
	_pending_start_delay = 0.0
	_set_wander_state(false, 0.0)


func get_state_name() -> StringName:
	match current_state:
		VillagerState.IDLE:
			return &"idle"
		VillagerState.GOING_TO_WORK:
			return &"moving"
		VillagerState.WORKING:
			return &"working"
		VillagerState.RETURNING_HOME:
			return &"moving"
		VillagerState.RESTING:
			return &"resting"
		VillagerState.WANDERING:
			return &"idle"
		_:
			return &"unknown"


func get_work_cycle_state_name() -> StringName:
	match current_state:
		VillagerState.IDLE:
			return &"idle"
		VillagerState.GOING_TO_WORK:
			return &"going_to_work"
		VillagerState.WORKING:
			return &"working"
		VillagerState.RETURNING_HOME:
			return &"returning_home"
		VillagerState.RESTING:
			return &"resting"
		VillagerState.WANDERING:
			return &"wandering"
		_:
			return &"unknown"


func is_assigned_to_work() -> bool:
	return current_state == VillagerState.GOING_TO_WORK or current_state == VillagerState.WORKING or current_state == VillagerState.RETURNING_HOME or current_state == VillagerState.RESTING


func is_at_worksite() -> bool:
	return current_state == VillagerState.WORKING


func is_resting() -> bool:
	return current_state == VillagerState.RESTING


func is_locked_to_work_cycle() -> bool:
	return current_state == VillagerState.GOING_TO_WORK or current_state == VillagerState.WORKING or current_state == VillagerState.RETURNING_HOME


func get_status_label_text() -> String:
	if not _resource_work_status_text.is_empty():
		return _resource_work_status_text
	match current_state:
		VillagerState.IDLE:
			return "待命"
		VillagerState.GOING_TO_WORK:
			return "前往"
		VillagerState.WORKING:
			return "工作"
		VillagerState.RETURNING_HOME:
			return "回家"
		VillagerState.RESTING:
			return "休息"
		VillagerState.WANDERING:
			return "闲逛"
		_:
			return ""


func _process(delta: float) -> void:
	if not _route_ready:
		return

	var scaled_game_minutes := _get_scaled_game_minutes(delta)
	_set_animation_speed_for_clock()
	if scaled_game_minutes <= 0.0:
		_pause_animation_if_possible()
		return
	_resume_animation_if_possible()
	_tick_state_machine(scaled_game_minutes)


func debug_advance_minutes(minute_count: float) -> void:
	if not _route_ready or minute_count <= 0.0:
		return
	var remaining_minutes := minute_count
	while remaining_minutes > 0.0:
		var step := minf(1.0, remaining_minutes)
		_tick_state_machine(step)
		remaining_minutes -= step


func _initialize_route() -> void:
	if not _route_ready:
		return

	_pending_initialization = false
	if _wander_mode:
		_initialize_wander()
		return
	_set_state(VillagerState.IDLE, _pending_start_delay)


func _initialize_wander() -> void:
	_pending_initialization = false
	_set_wander_state(true, _pending_start_delay)


func _tick_state_machine(delta_game_minutes: float) -> void:
	match current_state:
		VillagerState.IDLE:
			_tick_wait(delta_game_minutes, VillagerState.GOING_TO_WORK)
		VillagerState.GOING_TO_WORK:
			_move_to_target(delta_game_minutes, VillagerState.WORKING)
		VillagerState.WORKING:
			_tick_wait(delta_game_minutes, VillagerState.RETURNING_HOME)
		VillagerState.RETURNING_HOME:
			_move_to_target(delta_game_minutes, VillagerState.RESTING)
		VillagerState.RESTING:
			_tick_wait(delta_game_minutes, VillagerState.GOING_TO_WORK)
		VillagerState.WANDERING:
			_tick_wander(delta_game_minutes)


func _tick_wait(delta: float, next_state: VillagerState) -> void:
	_state_timer -= delta
	if _state_timer <= 0.0:
		_set_state(next_state)


func _move_to_target(delta: float, next_state: VillagerState) -> void:
	_ensure_navigation_path(_target_position)
	var remaining_distance: float = move_speed * delta
	var last_direction: Vector2 = Vector2.ZERO
	while remaining_distance > 0.0:
		var next_navigation_target: Vector2 = _get_active_navigation_target(_target_position)
		var to_target := next_navigation_target - position
		var distance_to_target: float = to_target.length()
		if distance_to_target <= arrival_distance:
			position = next_navigation_target
			if _advance_navigation_target():
				continue
			_set_state(next_state)
			return
		var step_distance: float = minf(remaining_distance, distance_to_target)
		position = position.move_toward(next_navigation_target, step_distance)
		remaining_distance -= step_distance
		last_direction = to_target
		if step_distance + arrival_distance < distance_to_target:
			break
	if last_direction != Vector2.ZERO:
		_play_walk_animation(last_direction)


func _tick_wander(delta: float) -> void:
	if _wander_pause_timer > 0.0:
		_wander_pause_timer -= delta
		if _wander_pause_timer <= 0.0:
			_pick_next_wander_target()
		return

	if position.distance_to(_wander_target) <= arrival_distance:
		_wander_pause_timer = randf_range(0.4, 1.2)
		_clear_navigation_path()
		_play_idle_animation()
		return

	_ensure_navigation_path(_wander_target)
	var remaining_distance: float = move_speed * delta
	var last_direction: Vector2 = Vector2.ZERO
	while remaining_distance > 0.0:
		var next_navigation_target: Vector2 = _get_active_navigation_target(_wander_target)
		var to_target := next_navigation_target - position
		var distance_to_target: float = to_target.length()
		if distance_to_target <= arrival_distance:
			position = next_navigation_target
			if _advance_navigation_target():
				continue
			if position.distance_to(_wander_target) <= arrival_distance:
				_wander_pause_timer = randf_range(0.4, 1.2)
				_clear_navigation_path()
				_play_idle_animation()
				return
			_rebuild_navigation_path(_wander_target)
			if _navigation_points.is_empty():
				break
			continue
		var step_distance: float = minf(remaining_distance, distance_to_target)
		position = position.move_toward(next_navigation_target, step_distance)
		remaining_distance -= step_distance
		last_direction = to_target
		if step_distance + arrival_distance < distance_to_target:
			break
	if last_direction != Vector2.ZERO:
		_play_walk_animation(last_direction)


func _set_state(next_state: VillagerState, override_duration: float = -1.0) -> void:
	current_state = next_state

	match current_state:
		VillagerState.IDLE:
			_target_position = home_position
			_clear_navigation_path()
			_state_timer = override_duration if override_duration >= 0.0 else idle_duration
			_play_idle_animation()
		VillagerState.GOING_TO_WORK:
			_target_position = work_position
			_rebuild_navigation_path(_target_position)
			_play_walk_animation(work_position - position)
		VillagerState.WORKING:
			_target_position = work_position
			_clear_navigation_path()
			_state_timer = override_duration if override_duration >= 0.0 else minimum_work_minutes
			_play_idle_animation()
		VillagerState.RETURNING_HOME:
			_target_position = home_position
			_rebuild_navigation_path(_target_position)
			_play_walk_animation(home_position - position)
		VillagerState.RESTING:
			_target_position = home_position
			_clear_navigation_path()
			_state_timer = override_duration if override_duration >= 0.0 else rest_duration_minutes
			_play_idle_animation()

	_update_status_label()
	state_changed.emit(self, get_state_name())


func _set_wander_state(start_pause: bool, override_duration: float = -1.0) -> void:
	current_state = VillagerState.WANDERING
	_wander_pause_timer = override_duration if override_duration >= 0.0 else idle_duration
	_clear_navigation_path()
	_pick_next_wander_target()
	if not start_pause:
		_wander_pause_timer = 0.0
	_update_status_label()
	state_changed.emit(self, get_state_name())


func _pick_next_wander_target() -> void:
	var center := _wander_center
	if _wander_bounds.size != Vector2.ZERO:
		center = _wander_bounds.get_center()
	if _wander_target_builder.is_valid():
		var built_target: Variant = _wander_target_builder.call(position, center, wander_radius, _wander_bounds)
		if typeof(built_target) == TYPE_VECTOR2:
			_wander_target = built_target
			_rebuild_navigation_path(_wander_target)
			return
	_wander_target = _clamp_to_wander_bounds(center + Vector2(randf_range(-wander_radius, wander_radius), randf_range(-wander_radius, wander_radius)))
	_rebuild_navigation_path(_wander_target)


func _clamp_to_wander_bounds(target: Vector2) -> Vector2:
	if _wander_bounds.size == Vector2.ZERO:
		return target
	var min_corner := _wander_bounds.position
	var max_corner := _wander_bounds.position + _wander_bounds.size
	return Vector2(clampf(target.x, min_corner.x, max_corner.x), clampf(target.y, min_corner.y, max_corner.y))


func _set_route_builder(route_builder: Callable) -> void:
	if route_builder.is_valid():
		_route_builder = route_builder


func _set_wander_target_builder(wander_target_builder: Callable) -> void:
	if wander_target_builder.is_valid():
		_wander_target_builder = wander_target_builder


func _clear_navigation_path() -> void:
	_navigation_points.clear()
	_navigation_index = 0


func _ensure_navigation_path(final_target: Vector2) -> void:
	if not _navigation_points.is_empty():
		return
	_rebuild_navigation_path(final_target)


func _rebuild_navigation_path(final_target: Vector2) -> void:
	_clear_navigation_path()
	if not _route_builder.is_valid():
		return
	var route_variant: Variant = _route_builder.call(position, final_target)
	if typeof(route_variant) != TYPE_ARRAY:
		return
	var route_points: Array = route_variant
	for route_point_variant in route_points:
		if typeof(route_point_variant) != TYPE_VECTOR2:
			continue
		var route_point: Vector2 = route_point_variant
		if route_point.distance_to(position) <= arrival_distance * 0.5:
			continue
		if not _navigation_points.is_empty() and route_point.distance_to(_navigation_points[_navigation_points.size() - 1]) <= 0.01:
			continue
		_navigation_points.append(route_point)


func _get_active_navigation_target(final_target: Vector2) -> Vector2:
	if _navigation_index >= 0 and _navigation_index < _navigation_points.size():
		return _navigation_points[_navigation_index]
	return final_target


func _advance_navigation_target() -> bool:
	while _navigation_index < _navigation_points.size():
		_navigation_index += 1
		if _navigation_index >= _navigation_points.size():
			_clear_navigation_path()
			return false
		if position.distance_to(_navigation_points[_navigation_index]) > arrival_distance:
			return true
	_clear_navigation_path()
	return false


func _play_idle_animation() -> void:
	if _play_resource_task_idle_animation_if_needed():
		return

	if _play_animation_if_available([&"idle"]):
		animated_sprite.flip_h = false
		return

	if _play_animation_if_available([&"idle_right", &"idle_left"]):
		return

	_play_animation(&"idle")


func _play_walk_animation(direction: Vector2) -> void:
	var facing_left := direction.x < 0.0
	if direction.x < 0.0:
		_last_horizontal_sign = -1.0
	elif direction.x > 0.0:
		_last_horizontal_sign = 1.0
	else:
		facing_left = _last_horizontal_sign < 0.0
	if _play_resource_task_walk_animation_if_needed(facing_left):
		return

	if _play_animation_if_available([&"walk_left" if facing_left else &"walk_right"]):
		animated_sprite.flip_h = false
		return

	if _play_animation_if_available([&"run"]):
		animated_sprite.flip_h = facing_left
		return

	if _play_animation_if_available([&"run_left" if facing_left else &"run_right"]):
		animated_sprite.flip_h = false
		return

	_play_animation(&"run")
	animated_sprite.flip_h = facing_left


func _refresh_resource_task_animation() -> void:
	match current_state:
		VillagerState.GOING_TO_WORK, VillagerState.RETURNING_HOME:
			_play_walk_animation(_target_position - position)
		VillagerState.WORKING, VillagerState.RESTING, VillagerState.IDLE:
			_play_idle_animation()


func _play_resource_task_idle_animation_if_needed() -> bool:
	if _resource_task_animation_state == RESOURCE_TASK_STATE_COLLECTING:
		return _play_resource_collect_animation()
	if _resource_task_animation_state == RESOURCE_TASK_STATE_RETURNING_TO_BUILDING or _resource_task_animation_state == RESOURCE_TASK_STATE_DELIVERING:
		if _resource_task_animation_carried_amount > 0.0:
			return _play_resource_carried_idle_animation()
	if _resource_task_animation_state == RESOURCE_TASK_STATE_GOING_TO_RESOURCE:
		return _play_resource_tool_idle_animation()
	return false


func _play_resource_task_walk_animation_if_needed(facing_left: bool) -> bool:
	var animation_name: StringName = _get_resource_task_walk_animation_name()
	if animation_name == &"":
		return false
	if not _play_animation_if_available([animation_name]):
		return false
	animated_sprite.flip_h = facing_left
	return true


func _play_resource_collect_animation() -> bool:
	var played: bool = false
	if _resource_task_animation_resource_type == RESOURCE_TYPE_WOOD:
		played = _play_animation_if_available([&"interact_axe", &"idle_axe"])
	elif _resource_task_animation_resource_type == RESOURCE_TYPE_STONE:
		played = _play_animation_if_available([&"interact_pickaxe", &"idle_pickaxe"])
	if played and _resource_task_animation_has_facing_override:
		animated_sprite.flip_h = _resource_task_animation_facing_left
	return played


func _play_resource_tool_idle_animation() -> bool:
	if _resource_task_animation_resource_type == RESOURCE_TYPE_WOOD:
		return _play_animation_if_available([&"idle_axe", &"idle"])
	if _resource_task_animation_resource_type == RESOURCE_TYPE_STONE:
		return _play_animation_if_available([&"idle_pickaxe", &"idle"])
	return false


func _play_resource_carried_idle_animation() -> bool:
	if _resource_task_animation_resource_type == RESOURCE_TYPE_WOOD:
		return _play_animation_if_available([&"idle_withWood", &"idle"])
	if _resource_task_animation_resource_type == RESOURCE_TYPE_STONE:
		return _play_animation_if_available([&"idle_withStone", &"idle"])
	return false


func _get_resource_task_walk_animation_name() -> StringName:
	if _resource_task_animation_state == RESOURCE_TASK_STATE_RETURNING_TO_BUILDING or _resource_task_animation_state == RESOURCE_TASK_STATE_DELIVERING:
		if _resource_task_animation_carried_amount > 0.0:
			if _resource_task_animation_resource_type == RESOURCE_TYPE_WOOD:
				return &"run_withWood"
			if _resource_task_animation_resource_type == RESOURCE_TYPE_STONE:
				return &"run_withStone"
	if _resource_task_animation_state == RESOURCE_TASK_STATE_GOING_TO_RESOURCE:
		if _resource_task_animation_resource_type == RESOURCE_TYPE_WOOD:
			return &"run_axe"
		if _resource_task_animation_resource_type == RESOURCE_TYPE_STONE:
			return &"run_pickaxe"
	return &""


func _play_animation(animation_name: StringName) -> void:
	if animated_sprite == null:
		return
	if animated_sprite.sprite_frames == null:
		return
	if not animated_sprite.sprite_frames.has_animation(animation_name):
		return
	if animated_sprite.animation != animation_name:
		animated_sprite.play(animation_name)
	_set_animation_speed_for_clock()


func _play_animation_if_available(animation_names: Array) -> bool:
	if animated_sprite == null:
		return false
	if animated_sprite.sprite_frames == null:
		return false

	for animation_name in animation_names:
		if animated_sprite.sprite_frames.has_animation(animation_name):
			if animated_sprite.animation != animation_name:
				animated_sprite.play(animation_name)
			_set_animation_speed_for_clock()
			return true

	return false


func _get_scaled_game_minutes(delta: float) -> float:
	if has_node("/root/GameClock"):
		var game_clock := get_node("/root/GameClock")
		if game_clock != null and game_clock.has_method("get_scaled_delta") and game_clock.has_method("get_minutes_per_second"):
			return float(game_clock.call("get_scaled_delta", delta)) * float(game_clock.call("get_minutes_per_second"))
	return delta


func _get_time_scale() -> float:
	if has_node("/root/GameClock"):
		var game_clock := get_node("/root/GameClock")
		if game_clock != null and game_clock.has_method("get_time_scale"):
			return float(game_clock.call("get_time_scale"))
	return 1.0


func _set_animation_speed_for_clock() -> void:
	if animated_sprite == null:
		return
	animated_sprite.speed_scale = _get_time_scale()


func _pause_animation_if_possible() -> void:
	if animated_sprite != null and animated_sprite.is_playing():
		animated_sprite.pause()


func _resume_animation_if_possible() -> void:
	if animated_sprite != null and not animated_sprite.is_playing():
		animated_sprite.play()


func _update_status_label() -> void:
	if status_label == null:
		return
	var next_text := get_status_label_text()
	status_label.visible = show_status_label and not next_text.is_empty()
	status_label.text = next_text
	if not _resource_work_status_text.is_empty():
		status_label.modulate = _resource_work_status_color
		return
	match current_state:
		VillagerState.WORKING:
			status_label.modulate = Color(0.90, 1.0, 0.78, 1.0)
		VillagerState.RESTING:
			status_label.modulate = Color(0.65, 0.85, 1.0, 1.0)
		VillagerState.GOING_TO_WORK, VillagerState.RETURNING_HOME:
			status_label.modulate = Color(1.0, 0.95, 0.70, 1.0)
		_:
			status_label.modulate = Color(1.0, 1.0, 1.0, 0.92)
