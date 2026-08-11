extends Node
class_name SinglePlayerGame

const MatchConstants := preload("res://scripts/match/pong_match_constants.gd")
const CupRackBuilderScript := preload("res://scripts/match/cup_rack_builder.gd")
const RackStateScript := preload("res://scripts/match/rack_state.gd")
const ShotPhysicsScript := preload("res://scripts/match/shot_physics.gd")
const ShotScoreTrackerScript := preload("res://scripts/match/shot_score_tracker.gd")
const ShotAttemptEvaluatorScript := preload("res://scripts/match/shot_attempt_evaluator.gd")
const CupRemovalQueueScript := preload("res://scripts/match/cup_removal_queue.gd")
const HouseRulesSettingsStoreScript := preload("res://scripts/house_rules/house_rules_settings_store.gd")
const ShotContextScript := preload("res://scripts/house_rules/shot_context.gd")
const ShotContactTrackerScript := preload("res://scripts/house_rules/shot_contact_tracker.gd")
const HouseRulesResolverScript := preload("res://scripts/house_rules/house_rules_resolver.gd")

@export var ball_path: NodePath
@export var cup_parent_path: NodePath
@export var score_label_path: NodePath
@export var rack_origin := Vector3(0.0, 0.78, -1.56)
@export var cup_spacing := 0.105
@export var miss_height := 0.45
@export var out_of_bounds_x := 1.45
@export var out_of_bounds_z_min := -2.45
@export var out_of_bounds_z_max := 0.35
@export var settled_speed := 0.08
@export var settled_after_seconds := 1.25
@export var max_attempt_seconds := 6.0
@export var reset_delay := 0.45
@export var scored_reset_delay := 0.8
@export var cup_remove_delay := 0.65
@export var captured_cup_remove_delay := 0.1

var _ball: ThrowableBall
var _cup_parent: Node3D
var _score_label: Label3D
var _ball_start_transform := Transform3D.IDENTITY
var _attempt_active := false
var _attempt_elapsed := 0.0
var _reset_countdown := -1.0
var _rack_state := RackStateScript.new()
var _score_tracker := ShotScoreTrackerScript.new()
var _pending_cup_removals := CupRemovalQueueScript.new()
var _house_rules_profile
var _contact_tracker := ShotContactTrackerScript.new()
var _score := 0
var _cups_remaining := 0


func _ready() -> void:
	_ball = get_node_or_null(ball_path) as ThrowableBall
	_cup_parent = get_node_or_null(cup_parent_path) as Node3D
	_score_label = get_node_or_null(score_label_path) as Label3D

	if _ball == null:
		push_error("[Game] Single-player game could not find the throwable ball.")
		return
	if _cup_parent == null:
		push_error("[Game] Single-player game could not find the cup parent.")
		return

	_house_rules_profile = HouseRulesSettingsStoreScript.load_profile()
	print("[Game] Loaded House Rules profile %s." % _house_rules_profile.get_compact_ruleset_id())
	_ball_start_transform = _ball.global_transform
	_ball.released.connect(_on_ball_released)
	_build_starting_rack()
	_reset_ball()
	_update_score_label()
	print("[Game] Single-player pong loop ready with %d cups." % _cups_remaining)


func _physics_process(delta: float) -> void:
	if _ball == null:
		return

	_update_pending_cup_removal(delta)

	if _reset_countdown >= 0.0:
		_reset_countdown -= delta
		if _reset_countdown <= 0.0:
			_reset_ball()
		return

	if not _attempt_active:
		return

	_attempt_elapsed += delta
	_contact_tracker.update(_attempt_elapsed)
	if _try_confirm_score():
		return

	if _is_miss():
		_resolve_attempt(false, null)


func _build_starting_rack() -> void:
	CupRackBuilderScript.clear_cup_parent(_cup_parent)
	_score = 0
	_pending_cup_removals.clear()
	_contact_tracker.clear()

	var cups := CupRackBuilderScript.build_triangular_rack(_cup_parent, {
		"back_row_origin": rack_origin,
		"row_direction_z": 1.0,
		"cup_spacing": cup_spacing,
		"name_prefix": "Cup",
		"owner_side": MatchConstants.PRACTICE_SIDE,
	})
	_rack_state.configure(cups, 0, MatchConstants.PRACTICE_SIDE)
	_cups_remaining = _rack_state.remaining_count()


func _on_ball_released(_grabber: Node3D, _release_linear_velocity: Vector3, _release_angular_velocity: Vector3) -> void:
	_attempt_active = true
	_attempt_elapsed = 0.0
	_clear_score_candidate()
	_contact_tracker.start_attempt(_ball)


func _resolve_attempt(was_score: bool, scored_cup: Node3D) -> void:
	_attempt_active = false
	var contact_summary = _contact_tracker.stop_and_get_summary(_attempt_elapsed)
	var context = _build_shot_context(contact_summary)
	var outcome := HouseRulesResolverScript.resolve_attempt(
		context,
		was_score,
		scored_cup,
		scored_reset_delay if was_score else reset_delay
	)
	if bool(outcome.get("was_score", false)) and scored_cup != null:
		_ball.begin_score_capture(scored_cup)
	_reset_countdown = float(outcome.get("reset_delay", reset_delay))
	_score_tracker.reset()

	if bool(outcome.get("was_score", false)):
		var removed_count := _apply_removed_cup_indices(outcome.get("removed_cup_indices", []), scored_cup)
		_score += removed_count
		_cups_remaining = _rack_state.remaining_count()
		print("[Game] Score removed %d cup(s). %d cups remaining.%s" % [
			removed_count,
			_cups_remaining,
			_format_rule_triggers(outcome),
		])
	else:
		print("[Game] Miss. Resetting ball.")

	_update_score_label()


func _is_miss() -> bool:
	return ShotAttemptEvaluatorScript.is_miss(
		_ball,
		_attempt_elapsed,
		_get_attempt_bounds(),
		_get_ball_score_contact_candidate(),
		_is_ball_settled()
	)


func _reset_ball() -> void:
	_reset_countdown = -1.0
	_attempt_active = false
	_attempt_elapsed = 0.0
	_clear_score_candidate()
	_contact_tracker.clear()
	_ball.reset_to_transform(_ball_start_transform, true)


func _update_score_label() -> void:
	if _score_label == null:
		return

	_score_label.text = "Score: %d / 10\nCups: %d" % [_score, _cups_remaining]


func _try_confirm_score() -> bool:
	var contact_candidate := _get_ball_score_contact_candidate()
	var confirmed_cup := _score_tracker.confirm_contact_candidate(contact_candidate)
	if confirmed_cup == null:
		return false

	_resolve_attempt(true, confirmed_cup)
	return true


func _get_ball_score_contact_candidate() -> Node3D:
	return _rack_state.find_score_contact_candidate(_ball)


func _is_ball_settled() -> bool:
	return ShotPhysicsScript.is_ball_settled(_ball, settled_speed)


func _clear_score_candidate() -> void:
	_score_tracker.reset()


func _update_pending_cup_removal(delta: float) -> void:
	_pending_cup_removals.update(delta)


func _build_shot_context(contact_summary):
	var context = ShotContextScript.new()
	context.mode_id = &"practice"
	context.active_side = MatchConstants.PRACTICE_SIDE
	context.opponent_side = MatchConstants.PRACTICE_SIDE
	context.active_slot = 0
	context.target_slot = 0
	context.ball = _ball
	context.target_rack_state = _rack_state
	context.rules_profile = _house_rules_profile
	context.contact_summary = contact_summary
	context.normal_shots_taken = 1
	context.normal_shots_per_turn = 1
	return context


func _apply_removed_cup_indices(values: Variant, physical_scoring_cup: Node3D = null) -> int:
	var removed_count := 0
	var cup_indices := _read_int_array(values)
	for cup_index in cup_indices:
		if _rack_state.is_scored(cup_index):
			continue

		var cup := _rack_state.mark_scored(cup_index)
		if cup != null and is_instance_valid(cup):
			if cup == physical_scoring_cup:
				_pending_cup_removals.queue_scored_cup(cup, captured_cup_remove_delay, _ball)
			else:
				_pending_cup_removals.queue_scored_cup(cup, cup_remove_delay)
			removed_count += 1
	return removed_count


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


func _get_attempt_bounds() -> Dictionary:
	return {
		"miss_height": miss_height,
		"out_of_bounds_x": out_of_bounds_x,
		"out_of_bounds_z_min": out_of_bounds_z_min,
		"out_of_bounds_z_max": out_of_bounds_z_max,
		"settled_after_seconds": settled_after_seconds,
		"max_attempt_seconds": max_attempt_seconds,
	}
