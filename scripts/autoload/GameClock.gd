extends Node

signal time_changed(time_text: String)
signal minute_changed(total_minutes: int)
signal hour_changed(hour_index: int)
signal time_scale_changed(scale: float)
signal speed_changed(speed_scale: float, speed_label: String)
signal pause_changed(paused: bool)

const SPEED_STEPS: Array[float] = [1.0, 2.0, 3.0]

@export var start_hour: int = 8
@export var start_minute: int = 0
@export var minutes_per_second: float = 1.0

var time_scale: float = 1.0
var _speed_index: int = 0
var _selected_time_scale: float = 1.0
var _is_paused: bool = false
var _accumulated_seconds: float = 0.0
var _total_minutes: int = 0
var _last_hour_index: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	reset_clock(start_hour, start_minute)
	_apply_effective_time_scale(true)


func _process(delta: float) -> void:
	var scaled_delta := get_scaled_delta(delta)
	if scaled_delta <= 0.0:
		return

	_accumulated_seconds += scaled_delta
	var seconds_per_game_minute := 1.0 / minutes_per_second
	while _accumulated_seconds >= seconds_per_game_minute:
		_accumulated_seconds -= seconds_per_game_minute
		_total_minutes += 1
		emit_time()
		minute_changed.emit(_total_minutes)
		_emit_hour_changed_if_needed()


func reset_clock(hour: int = -1, minute: int = -1) -> void:
	var reset_hour := start_hour if hour < 0 else hour
	var reset_minute := start_minute if minute < 0 else minute
	_accumulated_seconds = 0.0
	_total_minutes = reset_hour * 60 + reset_minute
	_last_hour_index = get_hour_index()
	emit_time()


func reset_time_control() -> void:
	var was_paused := _is_paused
	_speed_index = 0
	_selected_time_scale = 1.0
	_is_paused = false
	speed_changed.emit(_selected_time_scale, get_speed_label())
	_apply_effective_time_scale(true)
	if was_paused:
		pause_changed.emit(false)


func advance_minutes(minute_count: int) -> void:
	if minute_count <= 0:
		return
	for _minute_index in range(minute_count):
		if _is_paused:
			break
		_total_minutes += 1
		emit_time()
		minute_changed.emit(_total_minutes)
		_emit_hour_changed_if_needed()


func get_time_scale() -> float:
	return time_scale


func get_selected_time_scale() -> float:
	return _selected_time_scale


func get_minutes_per_second() -> float:
	return minutes_per_second


func get_scaled_delta(delta: float) -> float:
	return delta * time_scale


func get_total_minutes() -> int:
	return _total_minutes


func get_hour_index() -> int:
	return int(_total_minutes / 60)


func is_time_paused() -> bool:
	return _is_paused


func get_speed_label() -> String:
	return _format_scale_label(_selected_time_scale)


func get_time_control_label() -> String:
	if _is_paused:
		return "暂停中 / %s" % get_speed_label()
	return "运行中 / %s" % get_speed_label()


func set_time_scale(next_time_scale: float) -> void:
	var clamped_scale: float = max(next_time_scale, 0.0)
	if is_equal_approx(clamped_scale, 0.0):
		set_paused(true)
		return

	_set_selected_time_scale(clamped_scale)
	set_paused(false)


func cycle_speed() -> void:
	_speed_index = (_speed_index + 1) % SPEED_STEPS.size()
	_set_selected_time_scale(SPEED_STEPS[_speed_index])


func toggle_pause() -> void:
	set_paused(not _is_paused)


func set_paused(paused: bool) -> void:
	if _is_paused == paused:
		return
	_is_paused = paused
	_apply_effective_time_scale()
	pause_changed.emit(_is_paused)


func emit_time() -> void:
	time_changed.emit(get_time_text())


func _set_selected_time_scale(next_time_scale: float) -> void:
	var clamped_scale: float = max(next_time_scale, 0.01)
	var previous_selected := _selected_time_scale
	_selected_time_scale = clamped_scale
	_speed_index = _get_matching_speed_index(clamped_scale)
	if not is_equal_approx(previous_selected, _selected_time_scale):
		speed_changed.emit(_selected_time_scale, get_speed_label())
	_apply_effective_time_scale()


func _apply_effective_time_scale(force_emit: bool = false) -> void:
	var next_time_scale := 0.0 if _is_paused else _selected_time_scale
	if force_emit or not is_equal_approx(time_scale, next_time_scale):
		time_scale = next_time_scale
		time_scale_changed.emit(time_scale)
	else:
		time_scale = next_time_scale


func _get_matching_speed_index(scale: float) -> int:
	for index in range(SPEED_STEPS.size()):
		if is_equal_approx(SPEED_STEPS[index], scale):
			return index
	return _speed_index


func _format_scale_label(scale: float) -> String:
	var rounded_scale: float = round(scale)
	if is_equal_approx(scale, rounded_scale):
		return "%dx" % int(rounded_scale)
	return "%.1fx" % scale


func _emit_hour_changed_if_needed() -> void:
	var current_hour := get_hour_index()
	if current_hour == _last_hour_index:
		return
	_last_hour_index = current_hour
	hour_changed.emit(current_hour)


func get_time_text() -> String:
	var hour := int(_total_minutes / 60.0) % 24
	var minute := _total_minutes % 60
	var period := "AM"
	if hour >= 12:
		period = "PM"
	var display_hour := hour % 12
	if display_hour == 0:
		display_hour = 12
	return "%s %02d:%02d" % [period, display_hour, minute]
