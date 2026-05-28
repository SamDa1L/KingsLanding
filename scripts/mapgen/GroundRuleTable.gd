class_name GroundRuleTable
extends Resource


@export var rules: Array[GroundRule] = []


func add_rule(rule: GroundRule) -> void:
	if rule == null:
		return
	if rules.has(rule):
		return
	rules.append(rule)


func get_rules() -> Array[GroundRule]:
	return rules.duplicate()


func get_rules_for_ground_type(target_ground_type: StringName) -> Array[GroundRule]:
	var result: Array[GroundRule] = []
	for rule in rules:
		if rule == null:
			continue
		if rule.ground_type != target_ground_type:
			continue
		result.append(rule)
	return result


func get_rules_for_role(target_ground_type: StringName, target_ground_role: StringName) -> Array[GroundRule]:
	var result: Array[GroundRule] = []
	for rule in rules:
		if rule == null:
			continue
		if rule.ground_type != target_ground_type:
			continue
		if rule.ground_role != target_ground_role:
			continue
		result.append(rule)
	return result


func get_rules_for_connector(target_ground_type: StringName, target_ground_role: StringName, target_connector: StringName) -> Array[GroundRule]:
	var result: Array[GroundRule] = []
	for rule in rules:
		if rule == null:
			continue
		if rule.ground_type != target_ground_type:
			continue
		if rule.ground_role != target_ground_role:
			continue
		if rule.connector != target_connector:
			continue
		result.append(rule)
	return result


func has_rule_named(target_rule_name: String) -> bool:
	for rule in rules:
		if rule == null:
			continue
		if rule.rule_name == target_rule_name:
			return true
	return false
