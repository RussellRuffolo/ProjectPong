extends RefCounted
class_name HouseRulesProfile

const RuleIds := preload("res://scripts/house_rules/house_rule_ids.gd")

const SELF_PATH := "res://scripts/house_rules/house_rules_profile.gd"
const PROFILE_VERSION := 1
const COMPACT_PREFIX := "hr1"

var enabled_rules: Dictionary = {}


func _init(use_defaults := true) -> void:
	if use_defaults:
		reset_to_defaults()


static func default_profile():
	return _new_profile()


static func from_dictionary(data: Dictionary):
	var profile = _new_profile(false)
	profile.reset_to_defaults()

	var rules_value: Variant = data.get("enabled_rules", data.get("rules", {}))
	var rules: Dictionary = rules_value if rules_value is Dictionary else {}
	for rule_id in RuleIds.all():
		var key := String(rule_id)
		if rules.has(key):
			profile.set_enabled(rule_id, bool(rules[key]))

	return profile


func reset_to_defaults() -> void:
	enabled_rules.clear()
	for rule_id in RuleIds.all():
		enabled_rules[String(rule_id)] = true


func is_enabled(rule_id: StringName) -> bool:
	if not RuleIds.is_valid(rule_id):
		return false
	return bool(enabled_rules.get(String(rule_id), true))


func set_enabled(rule_id: StringName, is_enabled_value: bool) -> void:
	if not RuleIds.is_valid(rule_id):
		push_warning("[HouseRulesProfile] Ignoring unknown rule id: %s" % String(rule_id))
		return
	enabled_rules[String(rule_id)] = is_enabled_value


func toggle(rule_id: StringName) -> bool:
	var next_value := not is_enabled(rule_id)
	set_enabled(rule_id, next_value)
	return next_value


func get_enabled_rule_ids() -> Array[StringName]:
	var rule_ids: Array[StringName] = []
	for rule_id in RuleIds.all():
		if is_enabled(rule_id):
			rule_ids.append(rule_id)
	return rule_ids


func get_rule_states() -> Array[Dictionary]:
	var states: Array[Dictionary] = []
	for rule_id in RuleIds.all():
		states.append({
			"rule_id": rule_id,
			"name": RuleIds.display_name(rule_id),
			"enabled": is_enabled(rule_id),
			"scoring_summary": RuleIds.scoring_summary(rule_id),
			"authority_summary": RuleIds.authority_summary(rule_id),
		})
	return states


func to_dictionary() -> Dictionary:
	var rules := {}
	for rule_id in RuleIds.all():
		rules[String(rule_id)] = is_enabled(rule_id)

	return {
		"version": PROFILE_VERSION,
		"enabled_rules": rules,
		"compact_ruleset_id": get_compact_ruleset_id(),
	}


func duplicate_profile():
	var script = load(SELF_PATH)
	return script.from_dictionary(to_dictionary())


func get_compact_ruleset_id() -> String:
	var bit_string := ""
	for rule_id in RuleIds.all():
		bit_string += "1" if is_enabled(rule_id) else "0"
	return "%s-%s" % [COMPACT_PREFIX, bit_string]


static func _new_profile(use_defaults := true):
	return load(SELF_PATH).new(use_defaults)
