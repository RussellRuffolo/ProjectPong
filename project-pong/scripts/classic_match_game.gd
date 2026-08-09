extends Node
class_name ClassicMatchGame

const MatchConstants := preload("res://scripts/match/pong_match_constants.gd")
const ClassicMatchModelScript := preload("res://scripts/match/classic_match_model.gd")
const CupRackBuilderScript := preload("res://scripts/match/cup_rack_builder.gd")
const RackStateScript := preload("res://scripts/match/rack_state.gd")
const ShotPhysicsScript := preload("res://scripts/match/shot_physics.gd")
const ShotScoreTrackerScript := preload("res://scripts/match/shot_score_tracker.gd")
const ShotAttemptEvaluatorScript := preload("res://scripts/match/shot_attempt_evaluator.gd")
const CupRemovalQueueScript := preload("res://scripts/match/cup_removal_queue.gd")
const ComputerPlayerProfileScript := preload("res://scripts/match/computer_player_profile.gd")
const ComputerThrowPlannerScript := preload("res://scripts/match/computer_throw_planner.gd")
const ComputerThrowPhysicsScript := preload("res://scripts/match/computer_throw_physics.gd")
const HouseRulesSettingsStoreScript := preload("res://scripts/house_rules/house_rules_settings_store.gd")
const ShotContextScript := preload("res://scripts/house_rules/shot_context.gd")
const ShotContactTrackerScript := preload("res://scripts/house_rules/shot_contact_tracker.gd")
const HouseRulesResolverScript := preload("res://scripts/house_rules/house_rules_resolver.gd")

const TURN_PLAYER := MatchConstants.PLAYER_ONE_SLOT
const TURN_COMPUTER := MatchConstants.PLAYER_TWO_SLOT
const COMPUTER_TARGET_MOST_CENTRAL := "most_central"

@export var ball_path: NodePath
@export var player_cup_parent_path: NodePath
@export var computer_cup_parent_path: NodePath
@export var status_label_path: NodePath
@export var cup_visual_scene: PackedScene
@export var cup_collision_scene: PackedScene
@export var table_center_z := -1.56
@export var table_length_meters := 2.7432
@export var rack_end_margin := 0.14
@export var cup_height_y := 0.78
@export var cup_spacing := 0.105
@export var shots_per_turn := 2
@export var ball_spawn_height := 1.18
@export var player_ball_spawn_z := 0.16
@export var computer_ball_spawn_z := -3.08
@export var miss_height := 0.45
@export var out_of_bounds_x := 1.45
@export var out_of_bounds_padding_z := 0.45
@export var settled_speed := 0.08
@export var settled_after_seconds := 1.25
@export var scoring_settle_seconds := 0.35
@export var max_attempt_seconds := 7.0
@export var reset_delay := 0.45
@export var scored_reset_delay := 0.8
@export var cup_remove_delay := 0.65
@export var turn_transition_delay := 0.85
@export var computer_shot_delay := 1.1
@export var computer_player_profile: Resource
@export_enum("most_central", "closest") var computer_target_heuristic := COMPUTER_TARGET_MOST_CENTRAL
@export_range(0.0, 0.35, 0.005) var computer_accuracy_error_radius := 0 # 0.055
@export var computer_throw_arc_height := 0.42
@export var computer_aim_top_clearance := 0.02
@export var return_to_menu_delay := 3.0
@export var menu_scene_path := "res://scenes/menu.tscn"

var _ball: ThrowableBall
var _player_cup_parent: Node3D
var _computer_cup_parent: Node3D
var _status_label: Label3D
var _match_model := ClassicMatchModelScript.new()
var _player_rack_state := RackStateScript.new()
var _computer_rack_state := RackStateScript.new()
var _pending_cup_removals := CupRemovalQueueScript.new()
var _house_rules_profile
var _contact_tracker := ShotContactTrackerScript.new()
var _score_tracker := ShotScoreTrackerScript.new()
var _rng := RandomNumberGenerator.new()
var _computer_profile
var _attempt_active := false
var _attempt_elapsed := 0.0
var _reset_countdown := -1.0
var _turn_transition_countdown := -1.0
var _pending_turn := TURN_PLAYER
var _computer_shot_countdown := -1.0
var _game_over := false
var _return_countdown := -1.0
var _last_computer_shot_summary := ""
var _computer_throw_plan: Dictionary = {}


func _ready() -> void:
	_ball = get_node_or_null(ball_path) as ThrowableBall
	_player_cup_parent = get_node_or_null(player_cup_parent_path) as Node3D
	_computer_cup_parent = get_node_or_null(computer_cup_parent_path) as Node3D
	_status_label = get_node_or_null(status_label_path) as Label3D

	if _ball == null:
		push_error("[ClassicMatch] Could not find the throwable ball.")
		return
	if _player_cup_parent == null or _computer_cup_parent == null:
		push_error("[ClassicMatch] Could not find both cup rack parents.")
		return

	_house_rules_profile = HouseRulesSettingsStoreScript.load_profile()
	_computer_profile = _resolve_computer_profile()
	print("[ClassicMatch] Loaded House Rules profile %s." % _house_rules_profile.get_compact_ruleset_id())
	print("[ClassicMatch] Loaded computer profile %s." % _computer_profile.get_profile_id_string())
	_rng.randomize()
	_ball.released.connect(_on_ball_released)
	_match_model.configure({
		"shots_per_turn": shots_per_turn,
		"rack_size": MatchConstants.RACK_SIZE,
	})
	_build_starting_racks()
	_match_model.reset_for_match(TURN_PLAYER)
	_start_player_turn()
	print("[ClassicMatch] Ready on a %.2fm table with %d cups per side." % [table_length_meters, MatchConstants.RACK_SIZE])


func _physics_process(delta: float) -> void:
	if _ball == null:
		return

	_update_pending_cup_removals(delta)

	if _game_over:
		_update_return_to_menu(delta)
		return

	if _turn_transition_countdown >= 0.0:
		_update_turn_transition(delta)
		return

	if _match_model.active_slot == TURN_PLAYER:
		_update_player_turn(delta)
	else:
		_update_computer_turn(delta)


func _build_starting_racks() -> void:
	CupRackBuilderScript.clear_cup_parent(_player_cup_parent)
	CupRackBuilderScript.clear_cup_parent(_computer_cup_parent)
	_player_rack_state.clear()
	_computer_rack_state.clear()
	_pending_cup_removals.clear()

	var half_length := table_length_meters * 0.5
	var player_back_row_z := table_center_z + half_length - rack_end_margin
	var computer_back_row_z := table_center_z - half_length + rack_end_margin
	var player_cups := CupRackBuilderScript.build_triangular_rack(_player_cup_parent, {
		"cup_visual_scene": cup_visual_scene,
		"cup_collision_scene": cup_collision_scene,
		"back_row_origin": Vector3(0.0, cup_height_y, player_back_row_z),
		"row_direction_z": -1.0,
		"cup_spacing": cup_spacing,
		"name_prefix": "PlayerCup",
		"owner_side": MatchConstants.PLAYER_SIDE,
	})
	var computer_cups := CupRackBuilderScript.build_triangular_rack(_computer_cup_parent, {
		"cup_visual_scene": cup_visual_scene,
		"cup_collision_scene": cup_collision_scene,
		"back_row_origin": Vector3(0.0, cup_height_y, computer_back_row_z),
		"row_direction_z": 1.0,
		"cup_spacing": cup_spacing,
		"name_prefix": "ComputerCup",
		"owner_side": MatchConstants.COMPUTER_SIDE,
	})
	_player_rack_state.configure(player_cups, 0, MatchConstants.PLAYER_SIDE)
	_computer_rack_state.configure(computer_cups, 0, MatchConstants.COMPUTER_SIDE)


func _start_player_turn() -> void:
	_reset_countdown = -1.0
	_turn_transition_countdown = -1.0
	_computer_shot_countdown = -1.0
	_last_computer_shot_summary = ""
	_reset_ball_for_player()
	_update_status_label()
	print("[ClassicMatch] Player turn started with %d shots." % _match_model.get_shots_remaining())


func _start_computer_turn() -> void:
	_attempt_active = false
	_reset_countdown = -1.0
	_turn_transition_countdown = -1.0
	_computer_shot_countdown = computer_shot_delay
	_computer_throw_plan.clear()
	_clear_score_candidate()
	_set_ball_grabbable(false)
	_ball.reset_to_transform(_get_computer_ball_spawn_transform(), true)
	_update_status_label()
	print("[ClassicMatch] Computer turn started with %d shots." % _match_model.get_shots_remaining())


func _schedule_turn(next_turn: int, delay: float) -> void:
	_pending_turn = next_turn
	_turn_transition_countdown = maxf(0.0, delay)
	_set_ball_grabbable(false)
	_update_status_label()


func _update_turn_transition(delta: float) -> void:
	_turn_transition_countdown -= delta
	if _turn_transition_countdown > 0.0:
		return

	_turn_transition_countdown = -1.0
	if _pending_turn == TURN_PLAYER:
		_start_player_turn()
	else:
		_start_computer_turn()


func _update_player_turn(delta: float) -> void:
	if _reset_countdown >= 0.0:
		_reset_countdown -= delta
		if _reset_countdown <= 0.0:
			_reset_ball_for_player()
		return

	if not _attempt_active:
		return

	_attempt_elapsed += delta
	_contact_tracker.update(_attempt_elapsed)
	if _try_confirm_score(delta, _computer_rack_state, Callable(self, "_resolve_player_attempt")):
		return

	if _is_miss(_computer_rack_state):
		_resolve_player_attempt(false, null)


func _update_computer_turn(delta: float) -> void:
	if _reset_countdown >= 0.0:
		_reset_countdown -= delta
		if _reset_countdown <= 0.0:
			_reset_ball_for_computer()
		return

	_computer_shot_countdown -= delta
	if _computer_shot_countdown >= 0.0:
		return

	if not _attempt_active:
		_execute_computer_throw()
		return

	_attempt_elapsed += delta
	_contact_tracker.update(_attempt_elapsed)
	if _try_confirm_score(delta, _player_rack_state, Callable(self, "_resolve_computer_attempt")):
		return

	if _try_confirm_planned_computer_score(_player_rack_state):
		return

	if _is_miss(_player_rack_state):
		_resolve_computer_attempt(false, null)


func _on_ball_released(_grabber: Node3D, _release_linear_velocity: Vector3, _release_angular_velocity: Vector3) -> void:
	if _game_over or _match_model.active_slot != TURN_PLAYER or _match_model.get_shots_remaining() <= 0:
		return
	if _attempt_active or _reset_countdown >= 0.0 or _turn_transition_countdown >= 0.0:
		return

	_attempt_active = true
	_attempt_elapsed = 0.0
	_clear_score_candidate()
	_contact_tracker.start_attempt(_ball)
	_set_ball_grabbable(false)
	_update_status_label()
	print("[ClassicMatch] Player released shot. %d shots remaining." % max(0, _match_model.get_shots_remaining() - 1))


func _try_confirm_score(delta: float, target_rack_state, resolve_attempt: Callable) -> bool:
	var resting_cup: Node3D = target_rack_state.find_resting_cup(_ball)
	var confirmed_cup: Node3D = _score_tracker.update(delta, resting_cup, _is_ball_settled(), scoring_settle_seconds)
	if confirmed_cup == null:
		return false

	resolve_attempt.call(true, confirmed_cup)
	return true


func _resolve_player_attempt(was_score: bool, scored_cup: Node3D) -> void:
	_attempt_active = false
	var outcome := _resolve_house_rule_attempt(
		was_score,
		scored_cup,
		_computer_rack_state,
		MatchConstants.PLAYER_SIDE,
		MatchConstants.COMPUTER_SIDE
	)
	var transition := _match_model.apply_shot_outcome(TURN_PLAYER, TURN_COMPUTER, outcome)
	_score_tracker.reset()

	var resolved_score := bool(transition.get("resolved_score", false))
	if resolved_score:
		var removed_count := _remove_computer_cup_indices(transition.get("new_removed_cup_indices", []))
		print("[ClassicMatch] Player scored and removed %d cup(s). Computer cups remaining: %d.%s" % [
			removed_count,
			_computer_rack_state.remaining_count(),
			_format_rule_triggers(outcome),
		])
	else:
		print("[ClassicMatch] Player missed.")

	_update_status_label()

	if _match_model.winner_slot == TURN_PLAYER:
		_finish_match(TURN_PLAYER)
		return

	if not bool(transition.get("turn_advanced", false)):
		_reset_countdown = float(outcome.get("reset_delay", reset_delay))
	else:
		var next_turn := int(transition.get("active_slot", TURN_COMPUTER))
		_schedule_turn(next_turn, float(outcome.get("reset_delay", scored_reset_delay)) if resolved_score else turn_transition_delay)


func _execute_computer_throw() -> void:
	if _match_model.get_shots_remaining() <= 0:
		_schedule_turn(TURN_PLAYER, turn_transition_delay)
		return

	var throw_transform := _get_computer_ball_spawn_transform()
	var throw_plan := ComputerThrowPlannerScript.build_throw_plan({
		"profile": _computer_profile,
		"target_rack_state": _player_rack_state,
		"ball": _ball,
		"launch_transform": throw_transform,
		"rng": _rng,
		"house_rules_profile": _house_rules_profile,
		"attempt_bounds": _get_attempt_bounds(),
		"table_bounds": _get_table_bounds(),
	})
	if not bool(throw_plan.get("success", false)):
		_schedule_turn(TURN_PLAYER, turn_transition_delay)
		return

	_attempt_active = true
	_attempt_elapsed = 0.0
	_clear_score_candidate()

	var target_cup := throw_plan.get("target_cup", null) as Node3D
	var release_velocity: Vector3 = throw_plan.get("launch_velocity", Vector3.ZERO)
	_computer_throw_plan = _serialize_throw_plan(throw_plan)
	ComputerThrowPhysicsScript.launch_ball(_ball, throw_transform, release_velocity)
	_contact_tracker.start_attempt(_ball)
	_last_computer_shot_summary = "Computer %s aimed at %s." % [
		str(throw_plan.get("shot_type", "direct")),
		target_cup.name if target_cup != null else "a cup",
	]
	_update_status_label()
	print("[ClassicMatch] Computer profile %s threw a %s shot at cup %d with velocity %s. %d shots remaining." % [
		str(throw_plan.get("profile_id", "")),
		str(throw_plan.get("shot_type", "direct")),
		int(throw_plan.get("target_cup_index", -1)),
		release_velocity,
		max(0, _match_model.get_shots_remaining() - 1),
	])


func _resolve_computer_attempt(was_score: bool, scored_cup: Node3D) -> void:
	_attempt_active = false
	var outcome := _resolve_house_rule_attempt(
		was_score,
		scored_cup,
		_player_rack_state,
		MatchConstants.COMPUTER_SIDE,
		MatchConstants.PLAYER_SIDE
	)
	var transition := _match_model.apply_shot_outcome(TURN_COMPUTER, TURN_PLAYER, outcome)
	_score_tracker.reset()
	_computer_throw_plan.clear()

	var resolved_score := bool(transition.get("resolved_score", false))
	if resolved_score:
		var removed_count := _remove_player_cup_indices(transition.get("new_removed_cup_indices", []))
		_last_computer_shot_summary = "Computer hit %s." % scored_cup.name
		print("[ClassicMatch] Computer scored and removed %d cup(s). Player cups remaining: %d.%s" % [
			removed_count,
			_player_rack_state.remaining_count(),
			_format_rule_triggers(outcome),
		])
	else:
		_last_computer_shot_summary = "Computer missed."
		print("[ClassicMatch] Computer missed.")

	_update_status_label()

	if _match_model.winner_slot == TURN_COMPUTER:
		_finish_match(TURN_COMPUTER)
		return

	if not bool(transition.get("turn_advanced", false)):
		_reset_countdown = float(outcome.get("reset_delay", reset_delay))
	else:
		_computer_shot_countdown = -1.0
		_schedule_turn(int(transition.get("active_slot", TURN_PLAYER)), turn_transition_delay)


func _remove_player_cup(cup: Node3D) -> void:
	_player_rack_state.mark_cup_scored(cup)
	_pending_cup_removals.queue_scored_cup(cup, cup_remove_delay)


func _remove_computer_cup(cup: Node3D) -> void:
	_computer_rack_state.mark_cup_scored(cup)
	_pending_cup_removals.queue_scored_cup(cup, cup_remove_delay)


func _remove_player_cup_indices(values: Variant) -> int:
	return _remove_cup_indices(_player_rack_state, values)


func _remove_computer_cup_indices(values: Variant) -> int:
	return _remove_cup_indices(_computer_rack_state, values)


func _remove_cup_indices(rack_state, values: Variant) -> int:
	var removed_count := 0
	for cup_index in _read_int_array(values):
		if rack_state.is_scored(cup_index):
			continue

		var cup: Node3D = rack_state.mark_scored(cup_index)
		if cup != null and is_instance_valid(cup):
			_pending_cup_removals.queue_scored_cup(cup, cup_remove_delay)
			removed_count += 1
	return removed_count


func _update_pending_cup_removals(delta: float) -> void:
	_pending_cup_removals.update(delta)


func _get_ball_resting_cup(target_rack_state) -> Node3D:
	return target_rack_state.find_resting_cup(_ball)


func _is_miss(target_rack_state) -> bool:
	return ShotAttemptEvaluatorScript.is_miss(
		_ball,
		_attempt_elapsed,
		_get_attempt_bounds(),
		_get_ball_resting_cup(target_rack_state),
		_is_ball_settled()
	)


func _is_ball_settled() -> bool:
	return ShotPhysicsScript.is_ball_settled(_ball, settled_speed)


func _reset_ball_for_player() -> void:
	_reset_countdown = -1.0
	_attempt_active = false
	_attempt_elapsed = 0.0
	_clear_score_candidate()
	_contact_tracker.clear()
	_ball.reset_to_transform(_get_player_ball_spawn_transform(), true)
	_set_ball_grabbable(_match_model.active_slot == TURN_PLAYER and _match_model.get_shots_remaining() > 0 and not _game_over)
	_update_status_label()


func _reset_ball_for_computer() -> void:
	_reset_countdown = -1.0
	_attempt_active = false
	_attempt_elapsed = 0.0
	_computer_throw_plan.clear()
	_clear_score_candidate()
	_contact_tracker.clear()
	_ball.reset_to_transform(_get_computer_ball_spawn_transform(), true)
	_computer_shot_countdown = computer_shot_delay if _match_model.get_shots_remaining() > 0 and not _game_over else -1.0
	_update_status_label()


func _get_player_ball_spawn_transform() -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(0.0, ball_spawn_height, player_ball_spawn_z))


func _get_computer_ball_spawn_transform() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, ball_spawn_height, computer_ball_spawn_z))


func _resolve_computer_profile():
	if computer_player_profile != null:
		return computer_player_profile

	var profile = ComputerPlayerProfileScript.default_profile()
	profile = profile.duplicate_profile()
	profile.target_heuristic = computer_target_heuristic
	profile.direct_aim_error_radius = computer_accuracy_error_radius
	return profile


func _set_ball_grabbable(is_grabbable: bool) -> void:
	if _ball != null and _ball.has_method("set_grabbable"):
		_ball.call("set_grabbable", is_grabbable)


func _finish_match(winner_turn: int) -> void:
	_game_over = true
	_return_countdown = return_to_menu_delay
	_attempt_active = false
	_reset_countdown = -1.0
	_turn_transition_countdown = -1.0
	_computer_shot_countdown = -1.0
	_set_ball_grabbable(false)
	_update_status_label()
	print("[ClassicMatch] %s won. Returning to menu in %.1f seconds." % [_format_turn(winner_turn), return_to_menu_delay])


func _update_return_to_menu(delta: float) -> void:
	_return_countdown -= delta
	if _return_countdown > 0.0:
		return

	if menu_scene_path.is_empty():
		return

	var error := get_tree().change_scene_to_file(menu_scene_path)
	if error != OK:
		push_error("[ClassicMatch] Could not return to menu %s. Error: %s." % [menu_scene_path, error])


func _clear_score_candidate() -> void:
	_score_tracker.reset()


func _resolve_house_rule_attempt(was_score: bool, scored_cup: Node3D, target_rack_state, active_side: StringName, opponent_side: StringName) -> Dictionary:
	var contact_summary = _contact_tracker.stop_and_get_summary(_attempt_elapsed)
	var context = _build_shot_context(contact_summary, target_rack_state, active_side, opponent_side)
	return HouseRulesResolverScript.resolve_attempt(
		context,
		was_score,
		scored_cup,
		scored_reset_delay if was_score else reset_delay
	)


func _try_confirm_planned_computer_score(target_rack_state) -> bool:
	if target_rack_state == null or not _is_perfect_direct_throw_plan(_computer_throw_plan):
		return false

	var target_cup_index := int(_computer_throw_plan.get("target_cup_index", -1))
	if target_cup_index < 0 or target_rack_state.is_scored(target_cup_index):
		return false

	var target_cup: Node3D = target_rack_state.get_cup(target_cup_index)
	if target_cup == null or not is_instance_valid(target_cup):
		return false

	if _is_ball_aligned_with_plan_target(target_cup, _ball):
		_resolve_computer_attempt(true, target_cup)
		return true

	var contact_summary = _contact_tracker.get_summary()
	for event in contact_summary.contacts:
		if str(event.get("type", "")) != "cup":
			continue
		if int(event.get("cup_index", -1)) != target_cup_index:
			continue

		_resolve_computer_attempt(true, target_cup)
		return true

	return false


func _serialize_throw_plan(throw_plan: Dictionary) -> Dictionary:
	return {
		"shot_type": str(throw_plan.get("shot_type", "direct")),
		"target_cup_index": int(throw_plan.get("target_cup_index", -1)),
		"aim_error": throw_plan.get("aim_error", Vector3.ZERO),
		"angle_error_degrees": float(throw_plan.get("angle_error_degrees", 0.0)),
	}


func _is_perfect_direct_throw_plan(throw_plan: Dictionary) -> bool:
	return (
		str(throw_plan.get("shot_type", "")) == "direct"
		and throw_plan.get("aim_error", Vector3.ZERO).length_squared() <= 0.000001
		and absf(float(throw_plan.get("angle_error_degrees", 0.0))) <= 0.0001
	)


func _is_ball_aligned_with_plan_target(cup: Node3D, ball: Node3D) -> bool:
	if cup == null or ball == null or not is_instance_valid(cup) or not is_instance_valid(ball):
		return false

	var local_ball_position := cup.global_transform.affine_inverse() * ball.global_position
	var horizontal_distance := Vector2(local_ball_position.x, local_ball_position.z).length()
	return horizontal_distance <= 0.045 and local_ball_position.y <= 0.12 and local_ball_position.y >= -0.75


func _build_shot_context(contact_summary, target_rack_state, active_side: StringName, opponent_side: StringName):
	var context = ShotContextScript.new()
	context.mode_id = &"classic_match"
	context.active_side = active_side
	context.opponent_side = opponent_side
	context.active_slot = 0
	context.target_slot = 0
	context.ball = _ball
	context.target_rack_state = target_rack_state
	context.rules_profile = _house_rules_profile
	context.contact_summary = contact_summary
	context.normal_shots_taken = _match_model.shots_taken_this_turn + 1
	context.normal_shots_per_turn = shots_per_turn
	return context


func _read_int_array(values: Variant) -> Array[int]:
	var result: Array[int] = []
	var input: Array = values if values is Array else []
	for value in input:
		result.append(int(value))
	result.sort()
	return result


func _format_rule_triggers(outcome: Dictionary) -> String:
	var triggers: Array = outcome.get("rule_triggers", [])
	if triggers.is_empty():
		return ""
	return " Rules: %s" % [triggers]


func _update_status_label() -> void:
	if _status_label == null:
		return

	var shots_remaining := _match_model.get_shots_remaining()
	if _attempt_active:
		shots_remaining = max(0, shots_remaining - 1)
	var score_line := "You: %d / %d  CPU: %d / %d" % [
		_match_model.get_score(TURN_PLAYER),
		MatchConstants.RACK_SIZE,
		_match_model.get_score(TURN_COMPUTER),
		MatchConstants.RACK_SIZE,
	]
	var cups_line := "Their cups: %d  Your cups: %d" % [_computer_rack_state.remaining_count(), _player_rack_state.remaining_count()]
	if _game_over:
		var result := "You win!" if _match_model.winner_slot == TURN_PLAYER else "Computer wins"
		_status_label.text = "%s\n%s\nReturning to menu..." % [result, score_line]
		return

	if _turn_transition_countdown >= 0.0:
		_status_label.text = "%s\n%s\nNext: %s" % [score_line, cups_line, _format_turn(_pending_turn)]
		return

	if _match_model.active_slot == TURN_PLAYER:
		_status_label.text = "Your turn\nShots left: %d\n%s" % [shots_remaining, score_line]
	else:
		var summary := _last_computer_shot_summary
		if summary.is_empty():
			summary = "Computer is lining up."
		_status_label.text = "Computer turn\nShots left: %d\n%s\n%s" % [shots_remaining, score_line, summary]


func _format_turn(turn: int) -> String:
	return "You" if turn == TURN_PLAYER else "Computer"


func _get_attempt_bounds() -> Dictionary:
	var half_length := table_length_meters * 0.5
	return {
		"miss_height": miss_height,
		"out_of_bounds_x": out_of_bounds_x,
		"out_of_bounds_z_min": table_center_z - half_length - out_of_bounds_padding_z,
		"out_of_bounds_z_max": table_center_z + half_length + out_of_bounds_padding_z,
		"settled_after_seconds": settled_after_seconds,
		"max_attempt_seconds": max_attempt_seconds,
	}


func _get_table_bounds() -> Dictionary:
	var half_length := table_length_meters * 0.5
	return {
		"x_min": -out_of_bounds_x,
		"x_max": out_of_bounds_x,
		"z_min": table_center_z - half_length,
		"z_max": table_center_z + half_length,
		"surface_y": cup_height_y,
		"surface_bounce": 0.04,
		"surface_friction": 0.28,
	}
