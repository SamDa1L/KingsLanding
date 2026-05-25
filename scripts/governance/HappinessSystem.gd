class_name HappinessSystem
extends RefCounted

const MapTypes := preload("res://scripts/map/MapTypes.gd")
const TaxSystemScript := preload("res://scripts/governance/TaxSystem.gd")

const FOOD_SUFFICIENT_DAYS := 2.0
const FOOD_SUFFICIENT_DELTA := 5.0
const FOOD_ENOUGH_DELTA := 0.0
const FOOD_SHORTAGE_DELTA := -8.0
const FAMINE_DELTA := -20.0
const STABLE_STREAK_DAYS := 3
const STABLE_STREAK_DELTA := 2.0

var stable_day_count: int = 0
var tax_system: RefCounted = TaxSystemScript.new()


func build_daily_report(governance_state: RefCounted, resources: Dictionary, riot_penalty: float = 0.0) -> Dictionary:
	var population := 0
	var tax_policy := MapTypes.TaxPolicy.NORMAL
	if governance_state != null:
		population = int(governance_state.population)
		tax_policy = int(governance_state.tax_policy)

	var food_amount := _get_food_amount(resources)
	var daily_food_need := get_daily_food_need(population)
	var food_days := get_food_days(food_amount, daily_food_need)
	var food_status := get_food_status(food_amount, daily_food_need)
	var food_delta := get_food_happiness_delta(food_amount, daily_food_need)
	var tax_delta := float(tax_system.get_daily_happiness_delta(tax_policy))
	var is_stable_day := _is_stable_day(food_delta, tax_delta, riot_penalty)
	var next_stable_day_count := stable_day_count + 1 if is_stable_day else 0
	var stable_delta := STABLE_STREAK_DELTA if next_stable_day_count >= STABLE_STREAK_DAYS else 0.0
	var total_delta := food_delta + tax_delta + stable_delta - absf(riot_penalty)

	return {
		"population": population,
		"tax_policy": tax_policy,
		"food_amount": food_amount,
		"daily_food_need": daily_food_need,
		"food_days": food_days,
		"food_status": food_status,
		"food_delta": food_delta,
		"tax_delta": tax_delta,
		"stable_eligible": is_stable_day,
		"stable_day_count": next_stable_day_count,
		"stable_delta": stable_delta,
		"riot_penalty": absf(riot_penalty),
		"total_delta": total_delta,
	}


func apply_daily_happiness(governance_state: RefCounted, resources: Dictionary, riot_penalty: float = 0.0) -> Dictionary:
	var report := build_daily_report(governance_state, resources, riot_penalty)
	stable_day_count = int(report["stable_day_count"])
	report["summary"] = format_report(report)
	if governance_state != null and governance_state.has_method("adjust_happiness"):
		governance_state.adjust_happiness(float(report["total_delta"]))
	return report


func get_daily_food_need(population: int) -> float:
	return float(max(population, 0))


func get_food_days(food_amount: float, daily_food_need: float) -> float:
	if daily_food_need <= 0.0:
		return INF
	return max(food_amount, 0.0) / daily_food_need


func get_food_happiness_delta(food_amount: float, daily_food_need: float) -> float:
	if food_amount <= 0.0:
		return FAMINE_DELTA
	if daily_food_need <= 0.0:
		return FOOD_SUFFICIENT_DELTA
	var food_days := get_food_days(food_amount, daily_food_need)
	if food_days > FOOD_SUFFICIENT_DAYS:
		return FOOD_SUFFICIENT_DELTA
	if food_days >= 1.0:
		return FOOD_ENOUGH_DELTA
	return FOOD_SHORTAGE_DELTA


func get_food_status(food_amount: float, daily_food_need: float) -> String:
	if food_amount <= 0.0:
		return "饥荒"
	if daily_food_need <= 0.0:
		return "充足"
	var food_days := get_food_days(food_amount, daily_food_need)
	if food_days > FOOD_SUFFICIENT_DAYS:
		return "充足"
	if food_days >= 1.0:
		return "刚好够吃"
	return "不足"


func get_stable_reward_delta() -> float:
	if stable_day_count >= STABLE_STREAK_DAYS:
		return STABLE_STREAK_DELTA
	return 0.0


func set_stable_day_count(next_count: int) -> void:
	stable_day_count = max(next_count, 0)


func format_report(report: Dictionary) -> String:
	return "食物状态：%s | 食物 %+0.1f | 税率 %+0.1f | 稳定 %+0.1f | 暴乱 -%0.1f | 合计 %+0.1f" % [
		str(report.get("food_status", "未知")),
		float(report.get("food_delta", 0.0)),
		float(report.get("tax_delta", 0.0)),
		float(report.get("stable_delta", 0.0)),
		float(report.get("riot_penalty", 0.0)),
		float(report.get("total_delta", 0.0)),
	]


func _is_stable_day(food_delta: float, tax_delta: float, riot_penalty: float) -> bool:
	return food_delta >= 0.0 and tax_delta >= 0.0 and riot_penalty <= 0.0


func _get_food_amount(resources: Dictionary) -> float:
	return max(float(resources.get(MapTypes.RESOURCE_FOOD, 0.0)), 0.0)
