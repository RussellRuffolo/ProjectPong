extends RefCounted
class_name ShotContext

const ProfileScript := preload("res://scripts/house_rules/house_rules_profile.gd")
const ContactSummaryScript := preload("res://scripts/house_rules/shot_contact_summary.gd")
const SELF_PATH := "res://scripts/house_rules/shot_context.gd"

var mode_id := &""
var active_side := &""
var opponent_side := &""
var active_player_id := 0
var opponent_player_id := 0
var active_slot := 0
var target_slot := 0
var selected_rule_id := &""
var selected_cup_index := -1
var normal_shots_taken := 0
var normal_shots_per_turn := 2
var bonus_shots_available := 0
var ball: Node3D
var target_rack_state
var rules_profile = ProfileScript.new()
var contact_summary = ContactSummaryScript.new()


static func from_dictionary(data: Dictionary):
	var context = load(SELF_PATH).new()
	context.mode_id = StringName(str(data.get("mode_id", "")))
	context.active_side = StringName(str(data.get("active_side", "")))
	context.opponent_side = StringName(str(data.get("opponent_side", "")))
	context.active_player_id = int(data.get("active_player_id", 0))
	context.opponent_player_id = int(data.get("opponent_player_id", 0))
	context.active_slot = int(data.get("active_slot", 0))
	context.target_slot = int(data.get("target_slot", 0))
	context.selected_rule_id = StringName(str(data.get("selected_rule_id", "")))
	context.selected_cup_index = int(data.get("selected_cup_index", -1))
	context.normal_shots_taken = int(data.get("normal_shots_taken", 0))
	context.normal_shots_per_turn = int(data.get("normal_shots_per_turn", 2))
	context.bonus_shots_available = int(data.get("bonus_shots_available", 0))

	var profile_value: Variant = data.get("rules_profile", {})
	if profile_value is Dictionary:
		context.rules_profile = ProfileScript.from_dictionary(profile_value)

	var contacts_value: Variant = data.get("contact_summary", {})
	if contacts_value is Dictionary:
		context.contact_summary = ContactSummaryScript.from_dictionary(contacts_value)

	return context


func is_rule_enabled(rule_id: StringName) -> bool:
	return rules_profile != null and rules_profile.is_enabled(rule_id)


func get_available_target_cup_indices() -> Array[int]:
	var indices: Array[int] = []
	if target_rack_state == null or not target_rack_state.has_method("get_available_cups"):
		return indices

	for cup in target_rack_state.call("get_available_cups"):
		if cup == null or not is_instance_valid(cup):
			continue
		var cup_index := int(cup.get_meta("cup_index", -1))
		if cup_index >= 0:
			indices.append(cup_index)

	indices.sort()
	return indices


func to_debug_dictionary() -> Dictionary:
	return {
		"mode_id": String(mode_id),
		"active_side": String(active_side),
		"opponent_side": String(opponent_side),
		"active_player_id": active_player_id,
		"opponent_player_id": opponent_player_id,
		"active_slot": active_slot,
		"target_slot": target_slot,
		"selected_rule_id": String(selected_rule_id),
		"selected_cup_index": selected_cup_index,
		"normal_shots_taken": normal_shots_taken,
		"normal_shots_per_turn": normal_shots_per_turn,
		"bonus_shots_available": bonus_shots_available,
		"rules_profile": rules_profile.to_dictionary() if rules_profile != null else {},
		"contact_summary": contact_summary.to_dictionary() if contact_summary != null else {},
		"available_target_cup_indices": get_available_target_cup_indices(),
	}
