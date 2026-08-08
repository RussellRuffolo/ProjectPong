extends Node
class_name ClassicMatchGame

const CupTargetScript := preload("res://scripts/cup_target.gd")

const TURN_PLAYER := 0
const TURN_COMPUTER := 1
const RACK_SIZE := 10
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
@export_enum("most_central") var computer_target_heuristic := COMPUTER_TARGET_MOST_CENTRAL
@export_range(0.0, 0.35, 0.005) var computer_accuracy_error_radius := 0 # 0.055
@export var computer_throw_arc_height := 0.42
@export var computer_aim_top_clearance := 0.02
@export var return_to_menu_delay := 3.0
@export var menu_scene_path := "res://scenes/menu.tscn"

var _ball: ThrowableBall
var _player_cup_parent: Node3D
var _computer_cup_parent: Node3D
var _status_label: Label3D
var _player_cups: Array[Node3D] = []
var _computer_cups: Array[Node3D] = []
var _pending_cup_removals: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _active_turn := TURN_PLAYER
var _shots_remaining := 0
var _player_score := 0
var _computer_score := 0
var _attempt_active := false
var _attempt_elapsed := 0.0
var _reset_countdown := -1.0
var _turn_transition_countdown := -1.0
var _pending_turn := TURN_PLAYER
var _computer_shot_countdown := -1.0
var _score_candidate: Node3D
var _score_candidate_settled_elapsed := 0.0
var _game_over := false
var _winner_turn := -1
var _return_countdown := -1.0
var _last_computer_shot_summary := ""


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

	_rng.randomize()
	_ball.released.connect(_on_ball_released)
	_build_starting_racks()
	_start_player_turn()
	print("[ClassicMatch] Ready on a %.2fm table with %d cups per side." % [table_length_meters, RACK_SIZE])


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

	if _active_turn == TURN_PLAYER:
		_update_player_turn(delta)
	else:
		_update_computer_turn(delta)


func _build_starting_racks() -> void:
	_clear_cup_parent(_player_cup_parent)
	_clear_cup_parent(_computer_cup_parent)
	_player_cups.clear()
	_computer_cups.clear()
	_pending_cup_removals.clear()
	_player_score = 0
	_computer_score = 0

	var half_length := table_length_meters * 0.5
	var player_back_row_z := table_center_z + half_length - rack_end_margin
	var computer_back_row_z := table_center_z - half_length + rack_end_margin
	_build_rack(_player_cup_parent, _player_cups, Vector3(0.0, cup_height_y, player_back_row_z), -1.0, "PlayerCup")
	_build_rack(_computer_cup_parent, _computer_cups, Vector3(0.0, cup_height_y, computer_back_row_z), 1.0, "ComputerCup")


func _build_rack(
	parent: Node3D,
	rack: Array[Node3D],
	back_row_origin: Vector3,
	row_direction_z: float,
	name_prefix: String
) -> void:
	var cup_index := 0
	for row in range(4):
		var cups_in_row := 4 - row
		var row_width := float(cups_in_row - 1) * cup_spacing
		var row_z := back_row_origin.z + row_direction_z * float(row) * cup_spacing * 0.92

		for column in range(cups_in_row):
			var cup := CupTargetScript.new()
			cup.name = "%s_%02d" % [name_prefix, cup_index + 1]
			cup.visual_scene = cup_visual_scene
			cup.collision_scene = cup_collision_scene
			cup.position = Vector3(
				back_row_origin.x - row_width * 0.5 + float(column) * cup_spacing,
				back_row_origin.y,
				row_z
			)
			cup.set_meta("cup_index", cup_index)
			cup.set_meta("is_scored", false)
			parent.add_child(cup)
			rack.append(cup)
			cup_index += 1


func _clear_cup_parent(parent: Node3D) -> void:
	if parent == null:
		return

	for child in parent.get_children():
		child.queue_free()


func _start_player_turn() -> void:
	_active_turn = TURN_PLAYER
	_shots_remaining = shots_per_turn
	_reset_countdown = -1.0
	_turn_transition_countdown = -1.0
	_computer_shot_countdown = -1.0
	_last_computer_shot_summary = ""
	_reset_ball_for_player()
	_update_status_label()
	print("[ClassicMatch] Player turn started with %d shots." % _shots_remaining)


func _start_computer_turn() -> void:
	_active_turn = TURN_COMPUTER
	_shots_remaining = shots_per_turn
	_attempt_active = false
	_reset_countdown = -1.0
	_turn_transition_countdown = -1.0
	_computer_shot_countdown = computer_shot_delay
	_clear_score_candidate()
	_set_ball_grabbable(false)
	_ball.reset_to_transform(_get_computer_ball_spawn_transform(), true)
	_update_status_label()
	print("[ClassicMatch] Computer turn started with %d shots." % _shots_remaining)


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
	if _try_confirm_player_score(delta):
		return

	if _is_player_miss():
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
	if _try_confirm_computer_score(delta):
		return

	if _is_computer_miss():
		_resolve_computer_attempt(false, null)


func _on_ball_released(_grabber: Node3D, _release_linear_velocity: Vector3, _release_angular_velocity: Vector3) -> void:
	if _game_over or _active_turn != TURN_PLAYER or _shots_remaining <= 0:
		return
	if _attempt_active or _reset_countdown >= 0.0 or _turn_transition_countdown >= 0.0:
		return

	_attempt_active = true
	_attempt_elapsed = 0.0
	_shots_remaining = max(0, _shots_remaining - 1)
	_clear_score_candidate()
	_set_ball_grabbable(false)
	_update_status_label()
	print("[ClassicMatch] Player released shot. %d shots remaining." % _shots_remaining)


func _try_confirm_player_score(delta: float) -> bool:
	var resting_cup := _get_ball_resting_cup(_computer_cup_parent)
	if resting_cup == null or not _is_ball_settled():
		_clear_score_candidate()
		return false

	if resting_cup != _score_candidate:
		_score_candidate = resting_cup
		_score_candidate_settled_elapsed = 0.0

	_score_candidate_settled_elapsed += delta
	if _score_candidate_settled_elapsed < scoring_settle_seconds:
		return false

	_resolve_player_attempt(true, resting_cup)
	return true


func _resolve_player_attempt(was_score: bool, scored_cup: Node3D) -> void:
	_attempt_active = false
	_clear_score_candidate()

	if was_score and scored_cup != null and is_instance_valid(scored_cup):
		_player_score += 1
		_remove_computer_cup(scored_cup)
		print("[ClassicMatch] Player scored. Computer cups remaining: %d." % _computer_cups.size())
	else:
		print("[ClassicMatch] Player missed.")

	_update_status_label()

	if _computer_cups.is_empty():
		_finish_match(TURN_PLAYER)
		return

	if _shots_remaining > 0:
		_reset_countdown = scored_reset_delay if was_score else reset_delay
	else:
		_schedule_turn(TURN_COMPUTER, scored_reset_delay if was_score else turn_transition_delay)


func _execute_computer_throw() -> void:
	if _shots_remaining <= 0:
		_schedule_turn(TURN_PLAYER, turn_transition_delay)
		return

	var target_cup := _select_computer_target_cup()
	if target_cup == null:
		_schedule_turn(TURN_PLAYER, turn_transition_delay)
		return

	_attempt_active = true
	_attempt_elapsed = 0.0
	_shots_remaining = max(0, _shots_remaining - 1)
	_clear_score_candidate()

	var target_position := _get_computer_aim_position(target_cup)
	var release_velocity := _calculate_computer_throw_velocity(_get_computer_ball_spawn_transform().origin, target_position)
	_ball.reset_to_transform(_get_computer_ball_spawn_transform(), false)
	_ball.linear_velocity = release_velocity
	_ball.angular_velocity = _ball.release_spin
	_ball.sleeping = false
	_last_computer_shot_summary = "Computer aimed at %s." % target_cup.name
	_update_status_label()
	print("[ClassicMatch] Computer threw at %s with velocity %s. %d shots remaining." % [
		target_cup.name,
		release_velocity,
		_shots_remaining,
	])


func _try_confirm_computer_score(delta: float) -> bool:
	var resting_cup := _get_ball_resting_cup(_player_cup_parent)
	if resting_cup == null or not _is_ball_settled():
		_clear_score_candidate()
		return false

	if resting_cup != _score_candidate:
		_score_candidate = resting_cup
		_score_candidate_settled_elapsed = 0.0

	_score_candidate_settled_elapsed += delta
	if _score_candidate_settled_elapsed < scoring_settle_seconds:
		return false

	_resolve_computer_attempt(true, resting_cup)
	return true


func _resolve_computer_attempt(was_score: bool, scored_cup: Node3D) -> void:
	_attempt_active = false
	_clear_score_candidate()

	if was_score and scored_cup != null and is_instance_valid(scored_cup):
		_computer_score += 1
		_remove_player_cup(scored_cup)
		_last_computer_shot_summary = "Computer hit %s." % scored_cup.name
		print("[ClassicMatch] Computer scored. Player cups remaining: %d." % _player_cups.size())
	else:
		_last_computer_shot_summary = "Computer missed."
		print("[ClassicMatch] Computer missed.")

	_update_status_label()

	if _player_cups.is_empty():
		_finish_match(TURN_COMPUTER)
		return

	if _shots_remaining > 0:
		_reset_countdown = scored_reset_delay if was_score else reset_delay
	else:
		_computer_shot_countdown = -1.0
		_schedule_turn(TURN_PLAYER, turn_transition_delay)


func _remove_player_cup(cup: Node3D) -> void:
	_player_cups.erase(cup)
	_mark_cup_for_removal(cup)


func _remove_computer_cup(cup: Node3D) -> void:
	_computer_cups.erase(cup)
	_mark_cup_for_removal(cup)


func _mark_cup_for_removal(cup: Node3D) -> void:
	if cup == null or not is_instance_valid(cup):
		return

	cup.set_meta("is_scored", true)
	if cup.has_method("mark_scored"):
		cup.call("mark_scored")
	_pending_cup_removals.append({
		"cup": cup,
		"countdown": cup_remove_delay,
	})


func _update_pending_cup_removals(delta: float) -> void:
	for index in range(_pending_cup_removals.size() - 1, -1, -1):
		_pending_cup_removals[index]["countdown"] = float(_pending_cup_removals[index]["countdown"]) - delta
		if float(_pending_cup_removals[index]["countdown"]) > 0.0:
			continue

		var cup := _pending_cup_removals[index].get("cup") as Node3D
		if cup != null and is_instance_valid(cup):
			if cup.has_method("remove_from_game"):
				cup.call("remove_from_game")
			else:
				cup.queue_free()
		_pending_cup_removals.remove_at(index)


func _get_ball_resting_cup(parent: Node3D) -> Node3D:
	if parent == null:
		return null

	for child in parent.get_children():
		if child.has_method("is_ball_resting_inside") and child.call("is_ball_resting_inside", _ball):
			return child as Node3D

	return null


func _select_computer_target_cup() -> Node3D:
	_player_cups = _get_available_cups(_player_cups)
	if _player_cups.is_empty():
		return null

	match computer_target_heuristic:
		COMPUTER_TARGET_MOST_CENTRAL:
			return _select_most_central_cup(_player_cups)
		_:
			return _select_most_central_cup(_player_cups)


func _select_most_central_cup(cups: Array[Node3D]) -> Node3D:
	var available_cups := _get_available_cups(cups)
	if available_cups.is_empty():
		return null

	var rack_center := Vector3.ZERO
	for cup in available_cups:
		rack_center += cup.global_position
	rack_center /= float(available_cups.size())

	var selected_cup := available_cups[0]
	var selected_distance := INF
	var selected_index := RACK_SIZE
	for cup in available_cups:
		var offset := cup.global_position - rack_center
		var distance := Vector2(offset.x, offset.z).length_squared()
		var cup_index := int(cup.get_meta("cup_index", RACK_SIZE))
		if distance < selected_distance or (is_equal_approx(distance, selected_distance) and cup_index < selected_index):
			selected_cup = cup
			selected_distance = distance
			selected_index = cup_index

	return selected_cup


func _get_computer_aim_position(target_cup: Node3D) -> Vector3:
	var aim_position := _get_cup_top_center_position(target_cup) + Vector3.UP * computer_aim_top_clearance
	if computer_accuracy_error_radius <= 0.0:
		return aim_position

	var miss_angle := _rng.randf_range(0.0, TAU)
	var miss_distance := sqrt(_rng.randf()) * computer_accuracy_error_radius
	aim_position.x += cos(miss_angle) * miss_distance
	aim_position.z += sin(miss_angle) * miss_distance
	return aim_position


func _get_cup_top_center_position(cup: Node3D) -> Vector3:
	if cup.has_method("get_top_center_position"):
		var top_position = cup.call("get_top_center_position")
		if top_position is Vector3:
			return top_position
	return cup.global_position


func _calculate_computer_throw_velocity(start_position: Vector3, target_position: Vector3) -> Vector3:
	var gravity_scale := _ball.flight_gravity_scale if _ball != null else 1.0
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * gravity_scale
	gravity = maxf(gravity, 0.01)
	var peak_y := maxf(start_position.y, target_position.y) + maxf(0.01, computer_throw_arc_height)
	var vertical_speed := sqrt(2.0 * gravity * maxf(0.01, peak_y - start_position.y))
	var time_up := vertical_speed / gravity
	var time_down := sqrt(2.0 * maxf(0.01, peak_y - target_position.y) / gravity)
	var travel_time := maxf(0.1, time_up + time_down)
	var horizontal_delta := target_position - start_position
	horizontal_delta.y = 0.0
	return Vector3(
		horizontal_delta.x / travel_time,
		vertical_speed,
		horizontal_delta.z / travel_time
	)


func _get_available_cups(cups: Array[Node3D]) -> Array[Node3D]:
	var available_cups: Array[Node3D] = []
	for cup in cups:
		if _is_available_cup(cup):
			available_cups.append(cup)
	return available_cups


func _is_available_cup(cup: Node3D) -> bool:
	if cup == null or not is_instance_valid(cup) or cup.is_queued_for_deletion():
		return false
	if bool(cup.get_meta("is_scored", false)):
		return false
	if cup.has_method("is_scored") and bool(cup.call("is_scored")):
		return false
	return true


func _is_player_miss() -> bool:
	var position := _ball.global_position
	if position.y < miss_height:
		return true
	if absf(position.x) > out_of_bounds_x:
		return true

	var half_length := table_length_meters * 0.5
	if position.z < table_center_z - half_length - out_of_bounds_padding_z:
		return true
	if position.z > table_center_z + half_length + out_of_bounds_padding_z:
		return true
	if _attempt_elapsed >= max_attempt_seconds:
		return true
	if _attempt_elapsed >= settled_after_seconds and _is_ball_settled() and _get_ball_resting_cup(_computer_cup_parent) == null:
		return true
	return false


func _is_computer_miss() -> bool:
	var position := _ball.global_position
	if position.y < miss_height:
		return true
	if absf(position.x) > out_of_bounds_x:
		return true

	var half_length := table_length_meters * 0.5
	if position.z < table_center_z - half_length - out_of_bounds_padding_z:
		return true
	if position.z > table_center_z + half_length + out_of_bounds_padding_z:
		return true
	if _attempt_elapsed >= max_attempt_seconds:
		return true
	if _attempt_elapsed >= settled_after_seconds and _is_ball_settled() and _get_ball_resting_cup(_player_cup_parent) == null:
		return true
	return false


func _is_ball_settled() -> bool:
	return (
		_ball.linear_velocity.length() <= settled_speed
		and _ball.angular_velocity.length() <= settled_speed * 8.0
	)


func _reset_ball_for_player() -> void:
	_reset_countdown = -1.0
	_attempt_active = false
	_attempt_elapsed = 0.0
	_clear_score_candidate()
	_ball.reset_to_transform(_get_player_ball_spawn_transform(), true)
	_set_ball_grabbable(_active_turn == TURN_PLAYER and _shots_remaining > 0 and not _game_over)
	_update_status_label()


func _reset_ball_for_computer() -> void:
	_reset_countdown = -1.0
	_attempt_active = false
	_attempt_elapsed = 0.0
	_clear_score_candidate()
	_ball.reset_to_transform(_get_computer_ball_spawn_transform(), true)
	_computer_shot_countdown = computer_shot_delay if _shots_remaining > 0 and not _game_over else -1.0
	_update_status_label()


func _get_player_ball_spawn_transform() -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(0.0, ball_spawn_height, player_ball_spawn_z))


func _get_computer_ball_spawn_transform() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, ball_spawn_height, computer_ball_spawn_z))


func _set_ball_grabbable(is_grabbable: bool) -> void:
	if _ball != null and _ball.has_method("set_grabbable"):
		_ball.call("set_grabbable", is_grabbable)


func _finish_match(winner_turn: int) -> void:
	_game_over = true
	_winner_turn = winner_turn
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
	_score_candidate = null
	_score_candidate_settled_elapsed = 0.0


func _update_status_label() -> void:
	if _status_label == null:
		return

	var score_line := "You: %d / %d  CPU: %d / %d" % [_player_score, RACK_SIZE, _computer_score, RACK_SIZE]
	var cups_line := "Their cups: %d  Your cups: %d" % [_computer_cups.size(), _player_cups.size()]
	if _game_over:
		var result := "You win!" if _winner_turn == TURN_PLAYER else "Computer wins"
		_status_label.text = "%s\n%s\nReturning to menu..." % [result, score_line]
		return

	if _turn_transition_countdown >= 0.0:
		_status_label.text = "%s\n%s\nNext: %s" % [score_line, cups_line, _format_turn(_pending_turn)]
		return

	if _active_turn == TURN_PLAYER:
		_status_label.text = "Your turn\nShots left: %d\n%s" % [_shots_remaining, score_line]
	else:
		var summary := _last_computer_shot_summary
		if summary.is_empty():
			summary = "Computer is lining up."
		_status_label.text = "Computer turn\nShots left: %d\n%s\n%s" % [_shots_remaining, score_line, summary]


func _format_turn(turn: int) -> String:
	return "You" if turn == TURN_PLAYER else "Computer"
