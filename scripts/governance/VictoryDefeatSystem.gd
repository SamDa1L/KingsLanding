class_name VictoryDefeatSystem
extends RefCounted

const TARGET_COMPLETED_DAY := 10
const TARGET_POPULATION := 20
const TARGET_HAPPINESS := 50.0
const REQUIRED_CONSECUTIVE_RIOT_DAYS := 2

const RESULT_NONE: StringName = &"none"
const RESULT_VICTORY: StringName = &"victory"
const RESULT_DEFEAT: StringName = &"defeat"

const REASON_NONE: StringName = &"none"
const REASON_VICTORY_DAY_10: StringName = &"victory_day_10"
const REASON_DAY_10_TARGET_MISSED: StringName = &"day_10_target_missed"
const REASON_POPULATION_ZERO: StringName = &"population_zero"
const REASON_HAPPINESS_ZERO_RIOTS: StringName = &"happiness_zero_riots"
const REASON_TOWN_CENTER_DESTROYED: StringName = &"town_center_destroyed"

var result_type: StringName = RESULT_NONE
var reason_id: StringName = REASON_NONE
var reason_text: String = "尚未结算"
var consecutive_riot_days: int = 0
var completed_day_index: int = 0
var final_report: Dictionary = {}


func reset() -> void:
	result_type = RESULT_NONE
	reason_id = REASON_NONE
	reason_text = "尚未结算"
	consecutive_riot_days = 0
	completed_day_index = 0
	final_report = {}


func has_result() -> bool:
	return result_type != RESULT_NONE


func is_victory() -> bool:
	return result_type == RESULT_VICTORY


func is_defeat() -> bool:
	return result_type == RESULT_DEFEAT


func build_status_report(governance_state: RefCounted) -> Dictionary:
	return _build_report(governance_state, RESULT_NONE, REASON_NONE, "目标进行中", completed_day_index)


func check_immediate_defeat(governance_state: RefCounted) -> Dictionary:
	if has_result():
		return final_report
	return _check_defeat(governance_state, completed_day_index)


func evaluate_daily_result(governance_state: RefCounted, day_index: int, riot_triggered: bool) -> Dictionary:
	if has_result():
		return final_report

	completed_day_index = max(completed_day_index, day_index)
	if riot_triggered:
		consecutive_riot_days += 1
	else:
		consecutive_riot_days = 0

	var defeat_report := _check_defeat(governance_state, completed_day_index)
	if bool(defeat_report.get("has_result", false)):
		return defeat_report

	if completed_day_index >= TARGET_COMPLETED_DAY:
		if _meets_victory_conditions(governance_state):
			return _set_result(governance_state, RESULT_VICTORY, REASON_VICTORY_DAY_10, "第 10 天结束：人口、幸福度和城镇中心状态均达标", completed_day_index)
		return _set_result(governance_state, RESULT_DEFEAT, _get_day_10_failure_reason(governance_state), _get_day_10_failure_text(governance_state), completed_day_index)

	return _build_report(governance_state, RESULT_NONE, REASON_NONE, "目标进行中", completed_day_index)


func _check_defeat(governance_state: RefCounted, day_index: int) -> Dictionary:
	if governance_state == null:
		return _build_report(governance_state, RESULT_NONE, REASON_NONE, "治理状态未初始化", day_index)

	if int(governance_state.population) <= 0:
		return _set_result(governance_state, RESULT_DEFEAT, REASON_POPULATION_ZERO, "人口归零，领地治理失败", day_index)

	if bool(governance_state.town_center_destroyed):
		return _set_result(governance_state, RESULT_DEFEAT, REASON_TOWN_CENTER_DESTROYED, "城镇中心被摧毁，领地治理失败", day_index)

	if float(governance_state.happiness) <= 0.0 and consecutive_riot_days >= REQUIRED_CONSECUTIVE_RIOT_DAYS:
		return _set_result(governance_state, RESULT_DEFEAT, REASON_HAPPINESS_ZERO_RIOTS, "幸福度为 0 且连续 2 天暴乱，领地治理失败", day_index)

	return _build_report(governance_state, RESULT_NONE, REASON_NONE, "目标进行中", day_index)


func _meets_victory_conditions(governance_state: RefCounted) -> bool:
	if governance_state == null:
		return false
	var population_ok := int(governance_state.population) >= TARGET_POPULATION
	var happiness_ok := float(governance_state.happiness) >= TARGET_HAPPINESS
	var town_center_ok := not bool(governance_state.town_center_destroyed)
	return population_ok and happiness_ok and town_center_ok


func _get_day_10_failure_reason(governance_state: RefCounted) -> StringName:
	if governance_state == null:
		return REASON_NONE
	if bool(governance_state.town_center_destroyed):
		return REASON_TOWN_CENTER_DESTROYED
	return REASON_DAY_10_TARGET_MISSED


func _get_day_10_failure_text(governance_state: RefCounted) -> String:
	if governance_state == null:
		return "第 10 天结束：治理状态缺失，无法达成胜利"
	var missing: Array[String] = []
	if int(governance_state.population) < TARGET_POPULATION:
		missing.append("人口 %d/%d" % [int(governance_state.population), TARGET_POPULATION])
	if float(governance_state.happiness) < TARGET_HAPPINESS:
		missing.append("幸福度 %.1f/%.1f" % [float(governance_state.happiness), TARGET_HAPPINESS])
	if bool(governance_state.town_center_destroyed):
		missing.append("城镇中心已摧毁")
	return "第 10 天结束：未达成胜利目标（%s）" % "，".join(missing)


func _set_result(governance_state: RefCounted, next_result_type: StringName, next_reason_id: StringName, next_reason_text: String, day_index: int) -> Dictionary:
	result_type = next_result_type
	reason_id = next_reason_id
	reason_text = next_reason_text
	final_report = _build_report(governance_state, result_type, reason_id, reason_text, day_index)
	return final_report


func _build_report(governance_state: RefCounted, next_result_type: StringName, next_reason_id: StringName, next_reason_text: String, day_index: int) -> Dictionary:
	var population := 0
	var happiness := 0.0
	var town_center_destroyed := false
	var town_center_damage := 0
	if governance_state != null:
		population = int(governance_state.population)
		happiness = float(governance_state.happiness)
		town_center_destroyed = bool(governance_state.town_center_destroyed)
		town_center_damage = int(governance_state.town_center_damage)
	return {
		"has_result": next_result_type != RESULT_NONE,
		"result_type": next_result_type,
		"reason_id": next_reason_id,
		"reason_text": next_reason_text,
		"completed_day_index": day_index,
		"target_day": TARGET_COMPLETED_DAY,
		"population": population,
		"target_population": TARGET_POPULATION,
		"happiness": happiness,
		"target_happiness": TARGET_HAPPINESS,
		"town_center_destroyed": town_center_destroyed,
		"town_center_damage": town_center_damage,
		"consecutive_riot_days": consecutive_riot_days,
		"required_consecutive_riot_days": REQUIRED_CONSECUTIVE_RIOT_DAYS,
	}
