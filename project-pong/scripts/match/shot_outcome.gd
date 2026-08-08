extends RefCounted
class_name ShotOutcome


static func for_attempt(did_score: bool, cup: Node3D, delay_seconds: float, winner_value: Variant = null, options := {}) -> Dictionary:
	var outcome := {
		"was_score": did_score,
		"scored_cup": cup,
		"scored_cup_index": -1,
		"removed_cup_indices": [],
		"ignored_cup_indices": _read_int_array(options.get("ignored_cup_indices", [])),
		"bonus_shots": int(options.get("bonus_shots", 0)),
		"extra_turns": int(options.get("extra_turns", 0)),
		"same_side_next_turn": bool(options.get("same_side_next_turn", false)),
		"reset_delay": delay_seconds,
		"winner": winner_value,
		"ui_messages": _read_string_array(options.get("ui_messages", [])),
		"rule_triggers": _read_dictionary_array(options.get("rule_triggers", [])),
		"ruleset_id": str(options.get("ruleset_id", "")),
	}

	if cup != null and is_instance_valid(cup):
		outcome["scored_cup_index"] = int(cup.get_meta("cup_index", -1))
		add_removed_cup_index(outcome, int(outcome["scored_cup_index"]))

	for cup_index in _read_int_array(options.get("removed_cup_indices", [])):
		add_removed_cup_index(outcome, cup_index)

	return outcome


static func add_removed_cup_index(outcome: Dictionary, cup_index: int) -> void:
	if cup_index < 0:
		return

	var removed: Array = outcome.get("removed_cup_indices", [])
	if removed.has(cup_index):
		return

	removed.append(cup_index)
	removed.sort()
	outcome["removed_cup_indices"] = removed


static func add_ignored_cup_index(outcome: Dictionary, cup_index: int) -> void:
	if cup_index < 0:
		return

	var ignored: Array = outcome.get("ignored_cup_indices", [])
	if ignored.has(cup_index):
		return

	ignored.append(cup_index)
	ignored.sort()
	outcome["ignored_cup_indices"] = ignored


static func add_rule_trigger(outcome: Dictionary, rule_id: StringName, metadata := {}) -> void:
	var triggers: Array = outcome.get("rule_triggers", [])
	var trigger: Dictionary = metadata.duplicate()
	trigger["rule_id"] = String(rule_id)
	triggers.append(trigger)
	outcome["rule_triggers"] = triggers


static func _read_int_array(values: Variant) -> Array[int]:
	var result: Array[int] = []
	var input: Array = values if values is Array else []
	for value in input:
		result.append(int(value))
	result.sort()
	return result


static func _read_string_array(values: Variant) -> Array[String]:
	var result: Array[String] = []
	var input: Array = values if values is Array else []
	for value in input:
		result.append(str(value))
	return result


static func _read_dictionary_array(values: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var input: Array = values if values is Array else []
	for value in input:
		if value is Dictionary:
			result.append(value.duplicate(true))
	return result
