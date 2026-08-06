extends Node
class_name SinglePlayerGame

const CupTargetScript := preload("res://scripts/cup_target.gd")

@export var ball_path: NodePath
@export var cup_parent_path: NodePath
@export var score_label_path: NodePath
@export var cup_visual_scene: PackedScene
@export var cup_collision_scene: PackedScene
@export var rack_origin := Vector3(0.0, 0.78, -1.56)
@export var cup_spacing := 0.105
@export var miss_height := 0.45
@export var out_of_bounds_x := 1.45
@export var out_of_bounds_z_min := -2.45
@export var out_of_bounds_z_max := 0.35
@export var settled_speed := 0.08
@export var settled_after_seconds := 1.25
@export var scoring_settle_seconds := 0.35
@export var max_attempt_seconds := 6.0
@export var reset_delay := 0.45
@export var scored_reset_delay := 0.8
@export var cup_remove_delay := 0.65

var _ball: ThrowableBall
var _cup_parent: Node3D
var _score_label: Label3D
var _ball_start_transform := Transform3D.IDENTITY
var _attempt_active := false
var _attempt_elapsed := 0.0
var _reset_countdown := -1.0
var _score_candidate: Node3D
var _score_candidate_settled_elapsed := 0.0
var _pending_scored_cup: Node3D
var _cup_remove_countdown := -1.0
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
	if _try_confirm_score(delta):
		return

	if _is_miss():
		_resolve_attempt(false, null)


func _build_starting_rack() -> void:
	for child in _cup_parent.get_children():
		child.queue_free()

	_score = 0
	_cups_remaining = 0

	for row in range(4):
		var cups_in_row := 4 - row
		var row_width := float(cups_in_row - 1) * cup_spacing
		var row_z := rack_origin.z + float(row) * cup_spacing * 0.92

		for column in range(cups_in_row):
			var cup := CupTargetScript.new()
			cup.name = "Cup_%02d" % (_cups_remaining + 1)
			cup.visual_scene = cup_visual_scene
			cup.collision_scene = cup_collision_scene
			cup.position = Vector3(
				rack_origin.x - row_width * 0.5 + float(column) * cup_spacing,
				rack_origin.y,
				row_z
			)
			_cup_parent.add_child(cup)
			_cups_remaining += 1


func _on_ball_released(_grabber: Node3D, _release_linear_velocity: Vector3, _release_angular_velocity: Vector3) -> void:
	_attempt_active = true
	_attempt_elapsed = 0.0
	_clear_score_candidate()


func _resolve_attempt(was_score: bool, scored_cup: Node3D) -> void:
	_attempt_active = false
	_reset_countdown = scored_reset_delay if was_score else reset_delay
	_clear_score_candidate()

	if was_score and scored_cup != null and is_instance_valid(scored_cup):
		_score += 1
		_cups_remaining = max(0, _cups_remaining - 1)
		if scored_cup.has_method("mark_scored"):
			scored_cup.call("mark_scored")
		_pending_scored_cup = scored_cup
		_cup_remove_countdown = cup_remove_delay
		print("[Game] Score. %d cups remaining." % _cups_remaining)
	else:
		print("[Game] Miss. Resetting ball.")

	_update_score_label()


func _is_miss() -> bool:
	var position := _ball.global_position
	if position.y < miss_height:
		return true
	if absf(position.x) > out_of_bounds_x:
		return true
	if position.z < out_of_bounds_z_min or position.z > out_of_bounds_z_max:
		return true
	if _attempt_elapsed >= max_attempt_seconds:
		return true
	if _attempt_elapsed >= settled_after_seconds and _is_ball_settled() and _get_ball_resting_cup() == null:
		return true
	return false


func _reset_ball() -> void:
	_reset_countdown = -1.0
	_attempt_active = false
	_attempt_elapsed = 0.0
	_clear_score_candidate()
	_ball.reset_to_transform(_ball_start_transform, true)


func _update_score_label() -> void:
	if _score_label == null:
		return

	_score_label.text = "Score: %d / 10\nCups: %d" % [_score, _cups_remaining]


func _try_confirm_score(delta: float) -> bool:
	var resting_cup := _get_ball_resting_cup()
	if resting_cup == null or not _is_ball_settled():
		_clear_score_candidate()
		return false

	if resting_cup != _score_candidate:
		_score_candidate = resting_cup
		_score_candidate_settled_elapsed = 0.0

	_score_candidate_settled_elapsed += delta
	if _score_candidate_settled_elapsed < scoring_settle_seconds:
		return false

	_resolve_attempt(true, resting_cup)
	return true


func _get_ball_resting_cup() -> Node3D:
	if _cup_parent == null:
		return null

	for child in _cup_parent.get_children():
		if child.has_method("is_ball_resting_inside") and child.call("is_ball_resting_inside", _ball):
			return child as Node3D

	return null


func _is_ball_settled() -> bool:
	return (
		_ball.linear_velocity.length() <= settled_speed
		and _ball.angular_velocity.length() <= settled_speed * 8.0
	)


func _clear_score_candidate() -> void:
	_score_candidate = null
	_score_candidate_settled_elapsed = 0.0


func _update_pending_cup_removal(delta: float) -> void:
	if _cup_remove_countdown < 0.0:
		return

	_cup_remove_countdown -= delta
	if _cup_remove_countdown > 0.0:
		return

	_cup_remove_countdown = -1.0
	if _pending_scored_cup != null and is_instance_valid(_pending_scored_cup):
		if _pending_scored_cup.has_method("remove_from_game"):
			_pending_scored_cup.call("remove_from_game")
	_pending_scored_cup = null
