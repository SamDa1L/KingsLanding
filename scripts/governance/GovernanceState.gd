class_name GovernanceState
extends RefCounted

const MapTypes := preload("res://scripts/map/MapTypes.gd")

signal tax_policy_changed(new_tax_policy: int)
signal population_changed(new_population: int)
signal happiness_changed(new_happiness: float)
signal stability_changed(new_stability: float)
signal riot_risk_changed(new_riot_risk: float)
signal town_center_damage_changed(new_damage: int, destroyed: bool)

const MIN_VALUE := 0.0
const MAX_VALUE := 100.0
const TOWN_CENTER_MAX_DAMAGE := 2

var population: int = 0
var households: int = 0
var gold: int = 0
var food: int = 0
var wood: int = 0
var stone: int = 0
var tax_policy: int = MapTypes.TaxPolicy.NORMAL
var happiness: float = 50.0
var stability: float = 50.0
var riot_risk: float = 0.0
var town_center_damage: int = 0
var town_center_destroyed: bool = false
var day_count: int = 1


func _init() -> void:
	population = 0
	households = 0
	gold = 0
	food = 0
	wood = 0
	stone = 0
	tax_policy = MapTypes.TaxPolicy.NORMAL
	happiness = 50.0
	stability = 50.0
	riot_risk = 0.0
	town_center_damage = 0
	town_center_destroyed = false
	day_count = 1


func set_population(next_population: int) -> void:
	population = max(next_population, 0)
	population_changed.emit(population)


func set_tax_policy(next_tax_policy: int) -> void:
	tax_policy = next_tax_policy
	tax_policy_changed.emit(tax_policy)


func add_gold(amount: int) -> void:
	gold = max(gold + amount, 0)


func add_food(amount: int) -> void:
	food = max(food + amount, 0)


func add_wood(amount: int) -> void:
	wood = max(wood + amount, 0)


func add_stone(amount: int) -> void:
	stone = max(stone + amount, 0)


func adjust_happiness(delta_value: float) -> void:
	set_happiness(happiness + delta_value)


func set_happiness(next_happiness: float) -> void:
	happiness = clampf(next_happiness, MIN_VALUE, MAX_VALUE)
	happiness_changed.emit(happiness)


func adjust_stability(delta_value: float) -> void:
	set_stability(stability + delta_value)


func set_stability(next_stability: float) -> void:
	stability = clampf(next_stability, MIN_VALUE, MAX_VALUE)
	stability_changed.emit(stability)


func adjust_riot_risk(delta_value: float) -> void:
	set_riot_risk(riot_risk + delta_value)


func set_riot_risk(next_riot_risk: float) -> void:
	var clamped_riot_risk := clampf(next_riot_risk, MIN_VALUE, MAX_VALUE)
	if is_equal_approx(riot_risk, clamped_riot_risk):
		return
	riot_risk = clamped_riot_risk
	riot_risk_changed.emit(riot_risk)


func damage_town_center(amount: int = 1) -> void:
	town_center_damage = max(town_center_damage + amount, 0)
	town_center_destroyed = town_center_damage >= TOWN_CENTER_MAX_DAMAGE
	town_center_damage_changed.emit(town_center_damage, town_center_destroyed)


func next_day() -> void:
	day_count += 1


func get_resource_snapshot() -> Dictionary:
	return {
		MapTypes.RESOURCE_FOOD: food,
		MapTypes.RESOURCE_WOOD: wood,
		MapTypes.RESOURCE_STONE: stone,
		MapTypes.RESOURCE_GOLD: gold,
	}
