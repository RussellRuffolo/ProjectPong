extends RefCounted
class_name HouseRulesResolver

const RuleIds := preload("res://scripts/house_rules/house_rule_ids.gd")
const ShotOutcomeScript := preload("res://scripts/match/shot_outcome.gd")


static func resolve_attempt(context, was_score: bool, scored_cup: Node3D, reset_delay: float, winner_value: Variant = null) -> Dictionary:
	var ruleset_id := ""
	if context != null and context.rules_profile != null:
		ruleset_id = context.rules_profile.get_compact_ruleset_id()

	var outcome := ShotOutcomeScript.for_attempt(was_score, scored_cup, reset_delay, winner_value, {
		"ruleset_id": ruleset_id,
	})
	if not was_score or scored_cup == null or not is_instance_valid(scored_cup):
		return outcome

	var scored_cup_index := int(outcome.get("scored_cup_index", -1))
	if scored_cup_index < 0:
		return outcome

	_apply_chain_lightning(context, outcome, scored_cup_index)
	_apply_bouncing(context, outcome, scored_cup_index)
	return outcome


static func _apply_chain_lightning(context, outcome: Dictionary, scored_cup_index: int) -> void:
	if not _is_rule_enabled(context, RuleIds.CHAIN_LIGHTNING):
		return
	if context.contact_summary == null:
		return

	var touched_indices: Array[int] = context.contact_summary.get_distinct_touched_target_cup_indices(
		int(context.target_slot),
		StringName(context.opponent_side),
		scored_cup_index
	)
	var removed_by_rule: Array[int] = []
	for cup_index in touched_indices:
		if not _is_available_target_cup(context, cup_index):
			continue
		ShotOutcomeScript.add_removed_cup_index(outcome, cup_index)
		removed_by_rule.append(cup_index)

	if removed_by_rule.is_empty():
		return

	ShotOutcomeScript.add_rule_trigger(outcome, RuleIds.CHAIN_LIGHTNING, {
		"touched_cup_indices": removed_by_rule,
	})


static func _apply_bouncing(context, outcome: Dictionary, scored_cup_index: int) -> void:
	if not _is_rule_enabled(context, RuleIds.BOUNCING):
		return
	if context.contact_summary == null:
		return
	if not context.contact_summary.has_playable_bounce_excluding_scored(
		scored_cup_index,
		int(context.target_slot),
		StringName(context.opponent_side)
	):
		return

	var excluded := _read_int_array(outcome.get("removed_cup_indices", []))
	var extra_cup_index := _find_lowest_available_target_cup_index(context, excluded)
	if extra_cup_index < 0:
		return

	ShotOutcomeScript.add_removed_cup_index(outcome, extra_cup_index)
	ShotOutcomeScript.add_rule_trigger(outcome, RuleIds.BOUNCING, {
		"extra_cup_index": extra_cup_index,
	})


static func _find_lowest_available_target_cup_index(context, excluded_indices: Array[int]) -> int:
	if context == null or not context.has_method("get_available_target_cup_indices"):
		return -1

	for cup_index in context.call("get_available_target_cup_indices"):
		if excluded_indices.has(int(cup_index)):
			continue
		if _is_available_target_cup(context, int(cup_index)):
			return int(cup_index)
	return -1


static func _is_available_target_cup(context, cup_index: int) -> bool:
	if context == null or context.target_rack_state == null:
		return false
	if cup_index < 0:
		return false
	if context.target_rack_state.has_method("is_scored") and bool(context.target_rack_state.call("is_scored", cup_index)):
		return false

	var cup: Node3D = null
	if context.target_rack_state.has_method("get_cup"):
		cup = context.target_rack_state.call("get_cup", cup_index) as Node3D
	if cup == null or not is_instance_valid(cup):
		return false
	if context.target_rack_state.has_method("is_available_cup"):
		return bool(context.target_rack_state.call("is_available_cup", cup))
	return true


static func _is_rule_enabled(context, rule_id: StringName) -> bool:
	if context == null:
		return false
	if context.has_method("is_rule_enabled"):
		return bool(context.call("is_rule_enabled", rule_id))
	return context.rules_profile != null and context.rules_profile.is_enabled(rule_id)


static func _read_int_array(values: Variant) -> Array[int]:
	var result: Array[int] = []
	var input: Array = values if values is Array else []
	for value in input:
		result.append(int(value))
	result.sort()
	return result
