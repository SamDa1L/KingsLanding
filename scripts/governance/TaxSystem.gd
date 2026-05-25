class_name TaxSystem
extends RefCounted

const MapTypes := preload("res://scripts/map/MapTypes.gd")

const TAX_POLICIES: Array[int] = [
	MapTypes.TaxPolicy.LOW,
	MapTypes.TaxPolicy.NORMAL,
	MapTypes.TaxPolicy.HIGH,
]

const DAILY_GOLD_PER_PERSON: Dictionary = {
	MapTypes.TaxPolicy.LOW: 1.0,
	MapTypes.TaxPolicy.NORMAL: 2.0,
	MapTypes.TaxPolicy.HIGH: 3.0,
}

const DAILY_HAPPINESS_DELTA: Dictionary = {
	MapTypes.TaxPolicy.LOW: 5.0,
	MapTypes.TaxPolicy.NORMAL: 0.0,
	MapTypes.TaxPolicy.HIGH: -8.0,
}


func get_daily_gold_per_person(tax_policy: int) -> float:
	return float(DAILY_GOLD_PER_PERSON.get(tax_policy, DAILY_GOLD_PER_PERSON[MapTypes.TaxPolicy.NORMAL]))


func get_minute_gold_per_person(tax_policy: int) -> float:
	return get_daily_gold_per_person(tax_policy) / 1440.0


func get_minute_gold_income(population: int, tax_policy: int) -> float:
	return float(max(population, 0)) * get_minute_gold_per_person(tax_policy)


func get_daily_happiness_delta(tax_policy: int) -> float:
	return float(DAILY_HAPPINESS_DELTA.get(tax_policy, DAILY_HAPPINESS_DELTA[MapTypes.TaxPolicy.NORMAL]))


func get_next_policy(tax_policy: int) -> int:
	var current_index := TAX_POLICIES.find(tax_policy)
	if current_index < 0:
		return MapTypes.TaxPolicy.NORMAL
	return TAX_POLICIES[(current_index + 1) % TAX_POLICIES.size()]


func get_policy_label(tax_policy: int) -> String:
	return MapTypes.get_tax_policy_label(tax_policy)


func get_policy_summary(tax_policy: int, population: int) -> String:
	var daily_income := get_daily_gold_per_person(tax_policy) * float(max(population, 0))
	var happiness_delta := get_daily_happiness_delta(tax_policy)
	return "%s Tax | Gold %.1f/day | Happiness %+0.1f/day" % [get_policy_label(tax_policy), daily_income, happiness_delta]


func apply_daily_happiness(governance_state: RefCounted) -> float:
	if governance_state == null:
		return 0.0
	var happiness_delta := get_daily_happiness_delta(governance_state.tax_policy)
	if governance_state.has_method("adjust_happiness"):
		governance_state.adjust_happiness(happiness_delta)
	return happiness_delta
