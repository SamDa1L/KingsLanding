class_name RiotSystem
extends RefCounted

const MapTypes := preload("res://scripts/map/MapTypes.gd")

const CONSEQUENCE_NONE: StringName = &"none"
const CONSEQUENCE_BURN_FARM: StringName = &"burn_farm"
const CONSEQUENCE_DAMAGE_LUMBER_CAMP: StringName = &"damage_lumber_camp"
const CONSEQUENCE_DAMAGE_QUARRY: StringName = &"damage_quarry"
const CONSEQUENCE_POPULATION_FLEE: StringName = &"population_flee"
const CONSEQUENCE_WAREHOUSE_ROBBERY: StringName = &"warehouse_robbery"
const CONSEQUENCE_TOWN_CENTER_DAMAGED: StringName = &"town_center_damaged"

const RIOT_HAPPINESS_PENALTY := 12.0
const POPULATION_FLEE_AMOUNT := 2
const WAREHOUSE_ROBBERY_RATE := 0.25
const WAREHOUSE_ROBBERY_MIN_LOSS := 5.0

var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.randomize()


func set_seed(seed: int) -> void:
	rng.seed = seed


func build_risk_report(governance_state: RefCounted, happiness_override: float = -1.0) -> Dictionary:
	var happiness := _get_happiness(governance_state, happiness_override)
	var risk_label := get_risk_label(happiness)
	var daily_probability := get_daily_probability(happiness)
	return {
		"happiness": happiness,
		"risk_label": risk_label,
		"daily_probability": daily_probability,
		"daily_probability_percent": daily_probability * 100.0,
		"reason": "幸福度 %.1f，暴乱风险%s，每日概率 %.0f%%" % [happiness, risk_label, daily_probability * 100.0],
	}


func roll_daily_riot(governance_state: RefCounted, buildings: Array, inventory: Node, day_index: int = 0, happiness_override: float = -1.0) -> Dictionary:
	var report := build_risk_report(governance_state, happiness_override)
	_write_riot_risk(governance_state, float(report.get("daily_probability_percent", 0.0)))
	var probability := float(report.get("daily_probability", 0.0))
	var roll := rng.randf()
	var triggered := probability > 0.0 and roll < probability
	report["day"] = day_index
	report["roll"] = roll
	report["triggered"] = triggered
	report["riot_penalty"] = RIOT_HAPPINESS_PENALTY if triggered else 0.0
	report["consequence_id"] = CONSEQUENCE_NONE
	report["consequence_label"] = "无"
	report["effect"] = "无暴乱发生"
	report["message"] = _format_no_riot_message(report)
	if triggered:
		var consequence_id := _choose_consequence_id(governance_state, buildings, inventory)
		report["consequence_id"] = consequence_id
		report["consequence_label"] = get_consequence_label(consequence_id)
		report["effect"] = get_consequence_preview(consequence_id)
		report["message"] = _format_pending_riot_message(report)
	return report


func apply_daily_riot(governance_state: RefCounted, buildings: Array, inventory: Node, day_index: int = 0, happiness_override: float = -1.0) -> Dictionary:
	var report := roll_daily_riot(governance_state, buildings, inventory, day_index, happiness_override)
	return apply_riot_consequence(report, governance_state, buildings, inventory)


func apply_forced_riot(governance_state: RefCounted, buildings: Array, inventory: Node, consequence_id: StringName = &"", day_index: int = 0) -> Dictionary:
	var report := build_risk_report(governance_state)
	_write_riot_risk(governance_state, float(report.get("daily_probability_percent", 0.0)))
	var selected_consequence := consequence_id
	if selected_consequence == &"" or not _can_apply_consequence(selected_consequence, governance_state, buildings, inventory):
		selected_consequence = _choose_consequence_id(governance_state, buildings, inventory)
	report["day"] = day_index
	report["roll"] = 0.0
	report["triggered"] = true
	report["riot_penalty"] = RIOT_HAPPINESS_PENALTY
	report["consequence_id"] = selected_consequence
	report["consequence_label"] = get_consequence_label(selected_consequence)
	report["effect"] = get_consequence_preview(selected_consequence)
	report["message"] = _format_pending_riot_message(report)
	return apply_riot_consequence(report, governance_state, buildings, inventory)


func apply_riot_consequence(report: Dictionary, governance_state: RefCounted, buildings: Array, inventory: Node) -> Dictionary:
	if not bool(report.get("triggered", false)):
		return report

	var consequence_id: StringName = report.get("consequence_id", CONSEQUENCE_NONE)
	if consequence_id == CONSEQUENCE_NONE:
		consequence_id = _choose_consequence_id(governance_state, buildings, inventory)
		report["consequence_id"] = consequence_id
		report["consequence_label"] = get_consequence_label(consequence_id)

	match consequence_id:
		CONSEQUENCE_BURN_FARM:
			_damage_one_building(report, buildings, MapTypes.BuildingType.FARM)
		CONSEQUENCE_DAMAGE_LUMBER_CAMP:
			_damage_one_building(report, buildings, MapTypes.BuildingType.LUMBER_CAMP)
		CONSEQUENCE_DAMAGE_QUARRY:
			_damage_one_building(report, buildings, MapTypes.BuildingType.QUARRY)
		CONSEQUENCE_POPULATION_FLEE:
			_apply_population_flee(report, governance_state)
		CONSEQUENCE_WAREHOUSE_ROBBERY:
			_apply_warehouse_robbery(report, inventory)
		CONSEQUENCE_TOWN_CENTER_DAMAGED:
			_apply_town_center_damage(report, governance_state)
		_:
			report["effect"] = "暴乱发生，但没有可破坏目标"

	report["message"] = _format_riot_message(report)
	return report


func get_risk_label(happiness: float) -> String:
	if happiness >= 70.0:
		return "低"
	if happiness >= 40.0:
		return "中"
	return "高"


func get_daily_probability(happiness: float) -> float:
	if happiness >= 70.0:
		return 0.0
	if happiness >= 50.0:
		return 0.05
	if happiness >= 30.0:
		return 0.20
	return 0.50


func get_consequence_label(consequence_id: StringName) -> String:
	match consequence_id:
		CONSEQUENCE_BURN_FARM:
			return "烧毁农场"
		CONSEQUENCE_DAMAGE_LUMBER_CAMP:
			return "破坏伐木场"
		CONSEQUENCE_DAMAGE_QUARRY:
			return "破坏采石场"
		CONSEQUENCE_POPULATION_FLEE:
			return "人口逃亡"
		CONSEQUENCE_WAREHOUSE_ROBBERY:
			return "抢劫仓库"
		CONSEQUENCE_TOWN_CENTER_DAMAGED:
			return "城堡受损"
		_:
			return "无"


func get_consequence_preview(consequence_id: StringName) -> String:
	match consequence_id:
		CONSEQUENCE_BURN_FARM:
			return "一座农场停产，食物产出下降"
		CONSEQUENCE_DAMAGE_LUMBER_CAMP:
			return "一座伐木场停产，木材产出下降"
		CONSEQUENCE_DAMAGE_QUARRY:
			return "一座采石场停产，石料产出下降"
		CONSEQUENCE_POPULATION_FLEE:
			return "人口 -%d，税收和劳动力下降" % POPULATION_FLEE_AMOUNT
		CONSEQUENCE_WAREHOUSE_ROBBERY:
			return "仓库中的食物和金币被抢走"
		CONSEQUENCE_TOWN_CENTER_DAMAGED:
			return "城堡耐久下降，后续可接失败条件"
		_:
			return "无"


func _get_happiness(governance_state: RefCounted, happiness_override: float) -> float:
	if happiness_override >= 0.0:
		return clampf(happiness_override, 0.0, 100.0)
	if governance_state == null:
		return 50.0
	return clampf(float(governance_state.happiness), 0.0, 100.0)


func _choose_consequence_id(governance_state: RefCounted, buildings: Array, inventory: Node) -> StringName:
	var candidates := _get_available_consequence_ids(governance_state, buildings, inventory)
	if candidates.is_empty():
		return CONSEQUENCE_NONE
	return candidates[rng.randi_range(0, candidates.size() - 1)]


func _get_available_consequence_ids(governance_state: RefCounted, buildings: Array, inventory: Node) -> Array[StringName]:
	var candidates: Array[StringName] = []
	if _has_active_building(buildings, MapTypes.BuildingType.FARM):
		candidates.append(CONSEQUENCE_BURN_FARM)
	if _has_active_building(buildings, MapTypes.BuildingType.LUMBER_CAMP):
		candidates.append(CONSEQUENCE_DAMAGE_LUMBER_CAMP)
	if _has_active_building(buildings, MapTypes.BuildingType.QUARRY):
		candidates.append(CONSEQUENCE_DAMAGE_QUARRY)
	if governance_state != null and int(governance_state.population) > 0:
		candidates.append(CONSEQUENCE_POPULATION_FLEE)
	if _has_robbable_resources(inventory):
		candidates.append(CONSEQUENCE_WAREHOUSE_ROBBERY)
	if governance_state != null:
		candidates.append(CONSEQUENCE_TOWN_CENTER_DAMAGED)
	return candidates


func _can_apply_consequence(consequence_id: StringName, governance_state: RefCounted, buildings: Array, inventory: Node) -> bool:
	match consequence_id:
		CONSEQUENCE_BURN_FARM:
			return _has_active_building(buildings, MapTypes.BuildingType.FARM)
		CONSEQUENCE_DAMAGE_LUMBER_CAMP:
			return _has_active_building(buildings, MapTypes.BuildingType.LUMBER_CAMP)
		CONSEQUENCE_DAMAGE_QUARRY:
			return _has_active_building(buildings, MapTypes.BuildingType.QUARRY)
		CONSEQUENCE_POPULATION_FLEE:
			return governance_state != null and int(governance_state.population) > 0
		CONSEQUENCE_WAREHOUSE_ROBBERY:
			return _has_robbable_resources(inventory)
		CONSEQUENCE_TOWN_CENTER_DAMAGED:
			return governance_state != null
		_:
			return false


func _has_active_building(buildings: Array, building_type: int) -> bool:
	for building in buildings:
		if building != null and int(building.building_type) == building_type and bool(building.is_active):
			return true
	return false


func _get_active_buildings(buildings: Array, building_type: int) -> Array:
	var matches: Array = []
	for building in buildings:
		if building != null and int(building.building_type) == building_type and bool(building.is_active):
			matches.append(building)
	return matches


func _damage_one_building(report: Dictionary, buildings: Array, building_type: int) -> void:
	var candidates := _get_active_buildings(buildings, building_type)
	if candidates.is_empty():
		report["effect"] = "暴乱目标不存在，未能破坏建筑"
		return
	var building: RefCounted = candidates[rng.randi_range(0, candidates.size() - 1)]
	building.is_active = false
	if building.has_method("clear_storage"):
		building.call("clear_storage")
	report["damaged_building_type"] = int(building.building_type)
	report["damaged_building_label"] = building.get_building_label() if building.has_method("get_building_label") else MapTypes.get_building_label(building_type)
	report["damaged_cell"] = building.position
	report["effect"] = "%s 已损坏并停止生产" % str(report.get("damaged_building_label", get_consequence_label(report.get("consequence_id", CONSEQUENCE_NONE))))


func _apply_population_flee(report: Dictionary, governance_state: RefCounted) -> void:
	if governance_state == null:
		report["effect"] = "人口数据不存在，无法结算逃亡"
		return
	var population_before := int(governance_state.population)
	var loss := mini(POPULATION_FLEE_AMOUNT, population_before)
	if governance_state.has_method("set_population"):
		governance_state.call("set_population", population_before - loss)
	report["population_before"] = population_before
	report["population_after"] = int(governance_state.population)
	report["population_loss"] = loss
	report["effect"] = "人口 -%d（%d → %d）" % [loss, population_before, int(governance_state.population)]


func _apply_warehouse_robbery(report: Dictionary, inventory: Node) -> void:
	if inventory == null or not inventory.has_method("get_all_resources") or not inventory.has_method("apply_delta"):
		report["effect"] = "资源仓库不存在，无法结算抢劫"
		return
	var resources: Dictionary = inventory.call("get_all_resources")
	var food_loss := _calculate_robbery_loss(float(resources.get(MapTypes.RESOURCE_FOOD, 0.0)))
	var gold_loss := _calculate_robbery_loss(float(resources.get(MapTypes.RESOURCE_GOLD, 0.0)))
	var delta := {
		MapTypes.RESOURCE_FOOD: -food_loss,
		MapTypes.RESOURCE_GOLD: -gold_loss,
	}
	inventory.call("apply_delta", delta)
	report["resource_delta"] = delta
	report["effect"] = "仓库损失 Food %.1f / Gold %.1f" % [food_loss, gold_loss]


func _apply_town_center_damage(report: Dictionary, governance_state: RefCounted) -> void:
	if governance_state == null:
		report["effect"] = "城堡状态不存在，无法记录受损"
		return
	if governance_state.has_method("damage_town_center"):
		governance_state.call("damage_town_center", 1)
	report["town_center_damage"] = int(governance_state.town_center_damage)
	report["town_center_destroyed"] = bool(governance_state.town_center_destroyed)
	report["effect"] = "城堡受损 %d 次" % int(report.get("town_center_damage", 1))


func _has_robbable_resources(inventory: Node) -> bool:
	if inventory == null or not inventory.has_method("get_all_resources"):
		return false
	var resources: Dictionary = inventory.call("get_all_resources")
	return float(resources.get(MapTypes.RESOURCE_FOOD, 0.0)) > 0.0 or float(resources.get(MapTypes.RESOURCE_GOLD, 0.0)) > 0.0


func _calculate_robbery_loss(current_amount: float) -> float:
	if current_amount <= 0.0:
		return 0.0
	return minf(current_amount, maxf(WAREHOUSE_ROBBERY_MIN_LOSS, current_amount * WAREHOUSE_ROBBERY_RATE))


func _write_riot_risk(governance_state: RefCounted, risk_percent: float) -> void:
	if governance_state == null:
		return
	if governance_state.has_method("set_riot_risk"):
		governance_state.call("set_riot_risk", risk_percent)
	else:
		governance_state.riot_risk = clampf(risk_percent, 0.0, 100.0)


func _format_no_riot_message(report: Dictionary) -> String:
	return "第 %d 天无暴乱：%s，随机值 %.2f" % [int(report.get("day", 0)), str(report.get("reason", "")), float(report.get("roll", 0.0))]


func _format_pending_riot_message(report: Dictionary) -> String:
	return "第 %d 天暴乱触发：%s，后果=%s" % [int(report.get("day", 0)), str(report.get("reason", "")), str(report.get("consequence_label", "未知"))]


func _format_riot_message(report: Dictionary) -> String:
	return "第 %d 天暴乱：%s；%s" % [int(report.get("day", 0)), str(report.get("consequence_label", "未知")), str(report.get("effect", ""))]
