extends Node3D
class_name ComputerClassicMatchGame

const MatchConstants := preload("res://scripts/match/pong_match_constants.gd")
const ClassicMatchModelScript := preload("res://scripts/match/classic_match_model.gd")
const CupRackBuilderScript := preload("res://scripts/match/cup_rack_builder.gd")
const RackStateScript := preload("res://scripts/match/rack_state.gd")
const ComputerTargetSelectorScript := preload("res://scripts/match/computer_target_selector.gd")
const HouseRuleIdsScript := preload("res://scripts/house_rules/house_rule_ids.gd")
const HouseRulesProfileScript := preload("res://scripts/house_rules/house_rules_profile.gd")
const HouseRulesSettingsStoreScript := preload("res://scripts/house_rules/house_rules_settings_store.gd")
const ShotContextScript := preload("res://scripts/house_rules/shot_context.gd")
const ShotContactSummaryScript := preload("res://scripts/house_rules/shot_contact_summary.gd")
const HouseRulesResolverScript := preload("res://scripts/house_rules/house_rules_resolver.gd")

const SIDE_ONE := MatchConstants.PLAYER_ONE_SLOT
const SIDE_TWO := MatchConstants.PLAYER_TWO_SLOT
const SIDE_ONE_ID := &"computer_one"
const SIDE_TWO_ID := &"computer_two"

@export var side_one_cup_parent_path: NodePath
@export var side_two_cup_parent_path: NodePath
@export var status_label_path: NodePath
@export var shot_log_label_path: NodePath
@export var cup_visual_scene: PackedScene
@export var cup_collision_scene: PackedScene
@export var table_center_z := -1.56
@export var table_length_meters := 2.7432
@export var rack_end_margin := 0.14
@export var cup_height_y := 0.78
@export var cup_spacing := 0.105
@export var shots_per_turn := 2
@export var reset_delay := 0.15
@export var scored_reset_delay := 0.25
@export var autoplay_on_ready := true
@export_range(0.1, 20.0, 0.1) var shots_per_second := 4.0
@export_range(1, 500, 1) var max_automatic_shots := 160
@export var deterministic_seed := 20260808
@export_enum("saved_profile", "default_profile", "custom_list") var house_rules_source := "custom_list"
@export var custom_enabled_house_rules := PackedStringArray([
	"bouncing",
	"chain_lightning",
])
@export_enum("most_central", "closest") var side_one_target_heuristic := "most_central"
@export_enum("most_central", "closest") var side_two_target_heuristic := "closest"
@export_range(0.0, 0.35, 0.005) var side_one_accuracy_error_radius := 0.055
@export_range(0.0, 0.35, 0.005) var side_two_accuracy_error_radius := 0.075
@export_range(0.01, 0.15, 0.005) var virtual_score_radius := 0.045
@export_range(0.0, 1.0, 0.01) var side_one_playable_bounce_chance := 0.15
@export_range(0.0, 1.0, 0.01) var side_two_playable_bounce_chance := 0.05
@export_range(0.0, 1.0, 0.01) var side_one_chain_contact_chance := 0.05
@export_range(0.0, 1.0, 0.01) var side_two_chain_contact_chance := 0.10
@export var hide_removed_cups := true

var _side_one_cup_parent: Node3D
var _side_two_cup_parent: Node3D
var _status_label: Label3D
var _shot_log_label: Label3D
var _rack_state_by_slot: Dictionary = {}
var _match_model = ClassicMatchModelScript.new()
var _house_rules_profile
var _house_rules_profile_override = null
var _rng := RandomNumberGenerator.new()
var _shot_countdown := 0.0
var _shots_simulated := 0
var _shot_log: Array[Dictionary] = []
var _initialized := false


func _ready() -> void:
	if OS.has_feature("template"):
		push_warning("[ComputerClassicMatch] Editor-only simulation scene is disabled in exported builds.")
		set_physics_process(false)
		return

	_initialize_if_needed()
	if _try_run_cli_automatic_test():
		return

	set_physics_process(autoplay_on_ready)


func _physics_process(delta: float) -> void:
	if not autoplay_on_ready:
		return
	if _match_model.is_complete() or _shots_simulated >= max_automatic_shots:
		set_physics_process(false)
		return

	_shot_countdown -= delta
	if _shot_countdown > 0.0:
		return

	step_simulation()
	_shot_countdown = 1.0 / maxf(0.1, shots_per_second)


func reset_simulation(seed_override := -1) -> void:
	_initialize_if_needed()
	_rng.seed = deterministic_seed if int(seed_override) < 0 else int(seed_override)
	_shot_countdown = 0.0
	_shots_simulated = 0
	_shot_log.clear()
	_house_rules_profile = _build_house_rules_profile()
	_match_model.configure({
		"shots_per_turn": shots_per_turn,
		"rack_size": MatchConstants.RACK_SIZE,
	})
	_build_starting_racks()
	_match_model.reset_for_match(SIDE_ONE)
	_update_labels()
	print("[ComputerClassicMatch] Reset simulation with ruleset %s." % _house_rules_profile.get_compact_ruleset_id())


func step_simulation() -> Dictionary:
	_initialize_if_needed()
	if _match_model.match_phase != ClassicMatchModelScript.PHASE_PLAYING:
		return get_test_snapshot()

	var active_slot: int = int(_match_model.active_slot)
	var target_slot: int = _match_model.get_opponent_slot(active_slot)
	var target_rack_state = _get_rack_state(target_slot)
	var target_cup := ComputerTargetSelectorScript.select_target(
		target_rack_state,
		_get_target_heuristic(active_slot),
		_get_throw_origin(active_slot)
	)
	if target_cup == null:
		return get_test_snapshot()

	var landing_position := _roll_virtual_landing_position(target_cup, active_slot)
	var scored_cup := _find_virtual_scored_cup(target_rack_state, landing_position)
	var contact_summary = _build_virtual_contact_summary(active_slot, target_slot, target_rack_state, scored_cup)
	var context = _build_shot_context(active_slot, target_slot, target_rack_state, contact_summary)
	var was_score := scored_cup != null
	var outcome := HouseRulesResolverScript.resolve_attempt(
		context,
		was_score,
		scored_cup,
		scored_reset_delay if was_score else reset_delay,
		0
	)
	var transition := _match_model.apply_shot_outcome(active_slot, target_slot, outcome)
	_apply_removed_cup_indices(target_slot, transition.get("new_removed_cup_indices", []))
	_shots_simulated += 1

	var event := {
		"shot": _shots_simulated,
		"active_slot": active_slot,
		"target_slot": target_slot,
		"target_cup_index": _get_cup_index(target_cup),
		"scored_cup_index": _get_cup_index(scored_cup),
		"was_score": was_score,
		"resolved_score": bool(transition.get("resolved_score", false)),
		"new_removed_cup_indices": _read_int_array(transition.get("new_removed_cup_indices", [])),
		"rule_triggers": outcome.get("rule_triggers", []),
		"turn_advanced": bool(transition.get("turn_advanced", false)),
		"phase": str(transition.get("phase", "")),
		"winner_slot": int(transition.get("winner_slot", 0)),
	}
	_shot_log.append(event)
	if _shot_log.size() > 24:
		_shot_log.pop_front()

	_update_labels()
	print("[ComputerClassicMatch] Shot %d: %s -> cup %d, removed %s.%s" % [
		_shots_simulated,
		_format_slot(active_slot),
		int(event["scored_cup_index"]),
		event["new_removed_cup_indices"],
		_format_rule_triggers(outcome),
	])
	return event


func run_automatic_test(config: Dictionary = {}) -> Dictionary:
	apply_test_configuration(config)
	reset_simulation(int(config.get("seed", deterministic_seed)))

	var shot_limit: int = maxi(1, int(config.get("max_shots", max_automatic_shots)))
	while _match_model.match_phase == ClassicMatchModelScript.PHASE_PLAYING and _shots_simulated < shot_limit:
		step_simulation()

	var snapshot := get_test_snapshot()
	var passed := _is_test_snapshot_consistent(snapshot) and _match_model.is_complete()
	snapshot["passed"] = passed
	snapshot["failure_reason"] = "" if passed else _get_failure_reason(snapshot, shot_limit)
	return snapshot


func _try_run_cli_automatic_test() -> bool:
	var user_args := OS.get_cmdline_user_args()
	if not user_args.has("--codex-auto-test"):
		return false

	var config := {}
	for arg in user_args:
		if arg.begins_with("--codex-seed="):
			config["seed"] = int(arg.trim_prefix("--codex-seed="))
		elif arg.begins_with("--codex-max-shots="):
			config["max_shots"] = int(arg.trim_prefix("--codex-max-shots="))

	var result := run_automatic_test(config)
	print("[ComputerClassicMatchAutoTest] %s" % JSON.stringify(result))
	get_tree().quit(0 if bool(result.get("passed", false)) else 1)
	return true


func apply_test_configuration(config: Dictionary) -> void:
	if config.has("max_shots"):
		max_automatic_shots = max(1, int(config["max_shots"]))
	if config.has("seed"):
		deterministic_seed = int(config["seed"])
	if config.has("side_one_target_heuristic"):
		side_one_target_heuristic = str(config["side_one_target_heuristic"])
	if config.has("side_two_target_heuristic"):
		side_two_target_heuristic = str(config["side_two_target_heuristic"])
	if config.has("side_one_accuracy_error_radius"):
		side_one_accuracy_error_radius = maxf(0.0, float(config["side_one_accuracy_error_radius"]))
	if config.has("side_two_accuracy_error_radius"):
		side_two_accuracy_error_radius = maxf(0.0, float(config["side_two_accuracy_error_radius"]))
	if config.has("virtual_score_radius"):
		virtual_score_radius = maxf(0.01, float(config["virtual_score_radius"]))
	if config.has("enabled_house_rule_ids") and config["enabled_house_rule_ids"] is Array:
		set_enabled_house_rule_ids(config["enabled_house_rule_ids"])
	if config.has("house_rules") and config["house_rules"] is Dictionary:
		set_house_rules(config["house_rules"])


func set_enabled_house_rule_ids(rule_ids: Array) -> void:
	var enabled_ids := PackedStringArray()
	for value in rule_ids:
		enabled_ids.append(str(value))
	custom_enabled_house_rules = enabled_ids
	house_rules_source = "custom_list"
	_house_rules_profile_override = null
	_house_rules_profile = _build_house_rules_profile()


func set_house_rules(rule_states: Dictionary) -> void:
	var profile = HouseRulesProfileScript.default_profile()
	for rule_id in HouseRuleIdsScript.all():
		var key := String(rule_id)
		if rule_states.has(key):
			profile.set_enabled(rule_id, bool(rule_states[key]))
		elif rule_states.has(rule_id):
			profile.set_enabled(rule_id, bool(rule_states[rule_id]))
	_house_rules_profile_override = profile
	_house_rules_profile = profile


func get_house_rules_interface() -> Dictionary:
	_initialize_if_needed()
	return {
		"source": house_rules_source,
		"ruleset_id": _house_rules_profile.get_compact_ruleset_id(),
		"rule_states": _house_rules_profile.get_rule_states(),
		"custom_enabled_house_rules": custom_enabled_house_rules,
	}


func get_test_snapshot() -> Dictionary:
	_initialize_if_needed()
	var snapshot := _match_model.to_dictionary()
	snapshot["scene"] = "res://scenes/editor/computer_classic_match.tscn"
	snapshot["shots_simulated"] = _shots_simulated
	snapshot["ruleset_id"] = _house_rules_profile.get_compact_ruleset_id() if _house_rules_profile != null else ""
	snapshot["house_rules"] = _house_rules_profile.to_dictionary() if _house_rules_profile != null else {}
	snapshot["remaining_by_slot"] = {
		SIDE_ONE: _match_model.get_remaining_count(SIDE_ONE),
		SIDE_TWO: _match_model.get_remaining_count(SIDE_TWO),
	}
	snapshot["state_consistent"] = _is_test_snapshot_consistent(snapshot)
	snapshot["shot_log"] = _shot_log.duplicate(true)
	return snapshot


func _initialize_if_needed() -> void:
	if _initialized:
		return

	_side_one_cup_parent = get_node_or_null(side_one_cup_parent_path) as Node3D
	_side_two_cup_parent = get_node_or_null(side_two_cup_parent_path) as Node3D
	_status_label = get_node_or_null(status_label_path) as Label3D
	_shot_log_label = get_node_or_null(shot_log_label_path) as Label3D
	if _side_one_cup_parent == null or _side_two_cup_parent == null:
		push_error("[ComputerClassicMatch] Cup rack parents are required.")
		return

	_initialized = true
	reset_simulation(deterministic_seed)


func _build_starting_racks() -> void:
	CupRackBuilderScript.clear_cup_parent(_side_one_cup_parent)
	CupRackBuilderScript.clear_cup_parent(_side_two_cup_parent)
	_rack_state_by_slot = {
		SIDE_ONE: RackStateScript.new(),
		SIDE_TWO: RackStateScript.new(),
	}

	var half_length := table_length_meters * 0.5
	var side_one_back_row_z := table_center_z + half_length - rack_end_margin
	var side_two_back_row_z := table_center_z - half_length + rack_end_margin
	var side_one_cups := CupRackBuilderScript.build_triangular_rack(_side_one_cup_parent, {
		"cup_visual_scene": cup_visual_scene,
		"cup_collision_scene": cup_collision_scene,
		"back_row_origin": Vector3(0.0, cup_height_y, side_one_back_row_z),
		"row_direction_z": -1.0,
		"cup_spacing": cup_spacing,
		"name_prefix": "ComputerOneCup",
		"owner_slot": SIDE_ONE,
		"owner_side": SIDE_ONE_ID,
	})
	var side_two_cups := CupRackBuilderScript.build_triangular_rack(_side_two_cup_parent, {
		"cup_visual_scene": cup_visual_scene,
		"cup_collision_scene": cup_collision_scene,
		"back_row_origin": Vector3(0.0, cup_height_y, side_two_back_row_z),
		"row_direction_z": 1.0,
		"cup_spacing": cup_spacing,
		"name_prefix": "ComputerTwoCup",
		"owner_slot": SIDE_TWO,
		"owner_side": SIDE_TWO_ID,
	})
	_get_rack_state(SIDE_ONE).configure(side_one_cups, SIDE_ONE, SIDE_ONE_ID)
	_get_rack_state(SIDE_TWO).configure(side_two_cups, SIDE_TWO, SIDE_TWO_ID)


func _build_house_rules_profile():
	if _house_rules_profile_override != null:
		return _house_rules_profile_override.duplicate_profile()

	match house_rules_source:
		"saved_profile":
			return HouseRulesSettingsStoreScript.load_profile()
		"default_profile":
			return HouseRulesProfileScript.default_profile()
		"custom_list":
			var profile = HouseRulesProfileScript.default_profile()
			for rule_id in HouseRuleIdsScript.all():
				profile.set_enabled(rule_id, custom_enabled_house_rules.has(String(rule_id)))
			return profile
		_:
			return HouseRulesProfileScript.default_profile()


func _build_shot_context(active_slot: int, target_slot: int, target_rack_state, contact_summary):
	var context = ShotContextScript.new()
	context.mode_id = &"computer_classic_match"
	context.active_side = _get_side_id(active_slot)
	context.opponent_side = _get_side_id(target_slot)
	context.active_player_id = active_slot
	context.opponent_player_id = target_slot
	context.active_slot = active_slot
	context.target_slot = target_slot
	context.target_rack_state = target_rack_state
	context.rules_profile = _house_rules_profile
	context.contact_summary = contact_summary
	context.normal_shots_taken = _match_model.shots_taken_this_turn + 1
	context.normal_shots_per_turn = shots_per_turn
	return context


func _build_virtual_contact_summary(active_slot: int, target_slot: int, target_rack_state, scored_cup: Node3D):
	var summary = ShotContactSummaryScript.new()
	if _rng.randf() < _get_playable_bounce_chance(active_slot):
		summary.record_table(&"table", 0.15)

	if scored_cup != null and _rng.randf() < _get_chain_contact_chance(active_slot):
		var contact_cup := _select_contact_cup(target_rack_state, _get_cup_index(scored_cup))
		if contact_cup != null:
			summary.record_cup(_get_cup_index(contact_cup), target_slot, _get_side_id(target_slot), 0.22, true)

	return summary


func _select_contact_cup(target_rack_state, scored_cup_index: int) -> Node3D:
	if target_rack_state == null:
		return null

	for cup in target_rack_state.get_available_cups():
		if _get_cup_index(cup) != scored_cup_index:
			return cup
	return null


func _roll_virtual_landing_position(target_cup: Node3D, active_slot: int) -> Vector3:
	var landing := _get_cup_top_center_position(target_cup)
	var error_radius := _get_accuracy_error_radius(active_slot)
	if error_radius <= 0.0:
		return landing

	var miss_angle := _rng.randf_range(0.0, TAU)
	var miss_distance := sqrt(_rng.randf()) * error_radius
	landing.x += cos(miss_angle) * miss_distance
	landing.z += sin(miss_angle) * miss_distance
	return landing


func _find_virtual_scored_cup(target_rack_state, landing_position: Vector3) -> Node3D:
	if target_rack_state == null:
		return null

	var selected_cup: Node3D = null
	var selected_distance := INF
	for cup in target_rack_state.get_available_cups():
		var offset: Vector3 = cup.global_position - landing_position
		var distance := Vector2(offset.x, offset.z).length()
		if distance <= virtual_score_radius and distance < selected_distance:
			selected_cup = cup
			selected_distance = distance
	return selected_cup


func _apply_removed_cup_indices(slot: int, values: Variant) -> void:
	var rack_state = _get_rack_state(slot)
	if rack_state == null:
		return

	for cup_index in _read_int_array(values):
		var cup: Node3D = rack_state.mark_scored(cup_index)
		if cup != null and is_instance_valid(cup) and hide_removed_cups:
			cup.visible = false


func _update_labels() -> void:
	if _status_label != null:
		var status := "%s turn" % _format_slot(_match_model.active_slot)
		if _match_model.is_complete():
			status = "%s wins" % _format_slot(_match_model.winner_slot)
		_status_label.text = "%s\nCPU 1: %d / %d  CPU 2: %d / %d\nCups: %d - %d\nRules: %s" % [
			status,
			_match_model.get_score(SIDE_ONE),
			MatchConstants.RACK_SIZE,
			_match_model.get_score(SIDE_TWO),
			MatchConstants.RACK_SIZE,
			_match_model.get_remaining_count(SIDE_ONE),
			_match_model.get_remaining_count(SIDE_TWO),
			_house_rules_profile.get_compact_ruleset_id() if _house_rules_profile != null else "",
		]

	if _shot_log_label != null:
		var lines: Array[String] = []
		var start_index: int = maxi(0, _shot_log.size() - 8)
		for index in range(start_index, _shot_log.size()):
			var event: Dictionary = _shot_log[index]
			lines.append("#%d %s hit %d removed %s" % [
				int(event.get("shot", 0)),
				_format_slot(int(event.get("active_slot", 0))),
				int(event.get("scored_cup_index", -1)),
				event.get("new_removed_cup_indices", []),
			])
		_shot_log_label.text = "\n".join(lines)


func _is_test_snapshot_consistent(snapshot: Dictionary) -> bool:
	var scores := _read_two_int_array(snapshot.get("scores_by_slot", [0, 0]))
	var side_one_scored := _read_int_array(snapshot.get("scored_cups_slot_1", []))
	var side_two_scored := _read_int_array(snapshot.get("scored_cups_slot_2", []))
	return scores[0] == side_two_scored.size() and scores[1] == side_one_scored.size()


func _get_failure_reason(snapshot: Dictionary, shot_limit: int) -> String:
	if not bool(snapshot.get("state_consistent", false)):
		return "Shared model score and cup state diverged."
	if str(snapshot.get("phase", "")) != ClassicMatchModelScript.PHASE_COMPLETE:
		return "Match did not complete within %d simulated shots." % shot_limit
	return "Unknown automatic test failure."


func _get_rack_state(slot: int):
	return _rack_state_by_slot.get(slot, null)


func _get_target_heuristic(slot: int) -> String:
	return side_one_target_heuristic if slot == SIDE_ONE else side_two_target_heuristic


func _get_accuracy_error_radius(slot: int) -> float:
	return side_one_accuracy_error_radius if slot == SIDE_ONE else side_two_accuracy_error_radius


func _get_playable_bounce_chance(slot: int) -> float:
	return side_one_playable_bounce_chance if slot == SIDE_ONE else side_two_playable_bounce_chance


func _get_chain_contact_chance(slot: int) -> float:
	return side_one_chain_contact_chance if slot == SIDE_ONE else side_two_chain_contact_chance


func _get_throw_origin(slot: int) -> Vector3:
	var half_length := table_length_meters * 0.5
	var z := table_center_z + half_length + rack_end_margin
	if slot == SIDE_TWO:
		z = table_center_z - half_length - rack_end_margin
	return Vector3(0.0, cup_height_y + 0.4, z)


func _get_cup_top_center_position(cup: Node3D) -> Vector3:
	if cup != null and cup.has_method("get_top_center_position"):
		var top_position = cup.call("get_top_center_position")
		if top_position is Vector3:
			return top_position
	return cup.global_position if cup != null else Vector3.ZERO


func _get_side_id(slot: int) -> StringName:
	return SIDE_ONE_ID if slot == SIDE_ONE else SIDE_TWO_ID


func _format_slot(slot: int) -> String:
	if slot == SIDE_ONE:
		return "CPU 1"
	if slot == SIDE_TWO:
		return "CPU 2"
	return "CPU ?"


func _get_cup_index(cup: Node3D) -> int:
	return int(cup.get_meta("cup_index", -1)) if cup != null and is_instance_valid(cup) else -1


func _format_rule_triggers(outcome: Dictionary) -> String:
	var triggers: Array = outcome.get("rule_triggers", [])
	if triggers.is_empty():
		return ""
	return " Rules: %s" % [triggers]


func _read_two_int_array(values: Variant) -> Array[int]:
	var result: Array[int] = [0, 0]
	var input: Array = values if values is Array else []
	if input.size() > 0:
		result[0] = int(input[0])
	if input.size() > 1:
		result[1] = int(input[1])
	return result


func _read_int_array(values: Variant) -> Array[int]:
	var result: Array[int] = []
	var input: Array = values if values is Array else []
	for value in input:
		var cup_index := int(value)
		if not result.has(cup_index):
			result.append(cup_index)
	result.sort()
	return result
