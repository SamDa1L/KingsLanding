class_name Villager
extends Node2D

signal state_changed(villager: Node2D, state_name: StringName)

enum VillagerState {
	IDLE,
	GOING_TO_WORK,
	WORKING,
	RETURNING_HOME,
}

@export var move_speed: float = 55.0
@export var work_duration: float = 3.0
@export var idle_duration: float = 1.0
@export var arrival_distance: float = 4.0
@export var home_position: Vector2 = Vector2.ZERO
@export var work_position: Vector2 = Vector2.ZERO

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

var current_state: VillagerState = VillagerState.IDLE
var _target_position: Vector2 = Vector2.ZERO
var _state_timer: float = 0.0
var _route_ready: bool = false
var _pending_initialization: bool = false
var _pending_start_delay: float = 0.0
var _last_horizontal_sign: float = 1.0


func _ready() -> void:
	if _pending_initialization:
		_initialize_route()
	elif _route_ready:
		_play_idle_animation()


func setup_route(home: Vector2, work: Vector2, start_delay: float = 0.0) -> void:
	home_position = home
	work_position = work
	position = home_position
	_route_ready = true
	_pending_start_delay = max(start_delay, 0.0)
	_pending_initialization = true

	if is_node_ready():
		_initialize_route()


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
		_:
			return &"unknown"


func _process(delta: float) -> void:
	if not _route_ready:
		return

	var scaled_delta := _get_scaled_delta(delta)
	_set_animation_speed_for_clock()
	if scaled_delta <= 0.0:
		_pause_animation_if_possible()
		return
	_resume_animation_if_possible()

	match current_state:
		VillagerState.IDLE:
			_tick_wait(scaled_delta, VillagerState.GOING_TO_WORK)
		VillagerState.GOING_TO_WORK:
			_move_to_target(scaled_delta, VillagerState.WORKING)
		VillagerState.WORKING:
			_tick_wait(scaled_delta, VillagerState.RETURNING_HOME)
		VillagerState.RETURNING_HOME:
			_move_to_target(scaled_delta, VillagerState.IDLE)


func _initialize_route() -> void:
	if not _route_ready:
		return

	_pending_initialization = false
	_set_state(VillagerState.IDLE, _pending_start_delay)


func _tick_wait(delta: float, next_state: VillagerState) -> void:
	_state_timer -= delta
	if _state_timer <= 0.0:
		_set_state(next_state)


func _move_to_target(delta: float, next_state: VillagerState) -> void:
	var to_target := _target_position - position
	if to_target.length() <= arrival_distance:
		position = _target_position
		_set_state(next_state)
		return

	position = position.move_toward(_target_position, move_speed * delta)
	_play_walk_animation(to_target)


func _set_state(next_state: VillagerState, override_duration: float = -1.0) -> void:
	current_state = next_state

	match current_state:
		VillagerState.IDLE:
			_target_position = home_position
			_state_timer = override_duration if override_duration >= 0.0 else idle_duration
			_play_idle_animation()
		VillagerState.GOING_TO_WORK:
			_target_position = work_position
			_play_walk_animation(work_position - position)
		VillagerState.WORKING:
			_target_position = work_position
			_state_timer = override_duration if override_duration >= 0.0 else work_duration
			_play_idle_animation()
		VillagerState.RETURNING_HOME:
			_target_position = home_position
			_play_walk_animation(home_position - position)

	state_changed.emit(self, get_state_name())


func _play_idle_animation() -> void:
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


func _play_animation(animation_name: StringName) -> void:
	if animated_sprite.sprite_frames == null:
		return
	if not animated_sprite.sprite_frames.has_animation(animation_name):
		return
	if animated_sprite.animation != animation_name:
		animated_sprite.play(animation_name)
	_set_animation_speed_for_clock()


func _play_animation_if_available(animation_names: Array) -> bool:
	if animated_sprite.sprite_frames == null:
		return false

	for animation_name in animation_names:
		if animated_sprite.sprite_frames.has_animation(animation_name):
			if animated_sprite.animation != animation_name:
				animated_sprite.play(animation_name)
			_set_animation_speed_for_clock()
			return true

	return false


func _get_scaled_delta(delta: float) -> float:
	if has_node("/root/GameClock"):
		var game_clock := get_node("/root/GameClock")
		if game_clock != null and game_clock.has_method("get_scaled_delta"):
			return float(game_clock.call("get_scaled_delta", delta))
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
