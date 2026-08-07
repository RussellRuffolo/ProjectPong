extends Node
class_name NetworkMatchState

signal players_changed(player_ids: Array[int])
signal ball_authority_changed(player_id: int)
signal match_state_changed(summary: String)

const CupTargetScript := preload("res://scripts/cup_target.gd")

const PHASE_WAITING := "waiting"
const PHASE_PLAYING := "playing"
const PHASE_COMPLETE := "complete"
const PLAYER_ONE_SLOT := 1
const PLAYER_TWO_SLOT := 2

@export var session_path: NodePath
@export var ball_path: NodePath
@export var player_one_cup_parent_path: NodePath
@export var player_two_cup_parent_path: NodePath
@export var score_label_path: NodePath
@export var cup_visual_scene: PackedScene
@export var cup_collision_scene: PackedScene
@export var table_center_z := -1.35
@export var table_length_meters := 2.7432
@export var rack_back_row_offset_from_table_end := 0.28
@export var cup_height_y := 0.78
@export var cup_spacing := 0.105
@export var ball_spawn_height := 1.18
@export var ball_spawn_offset_from_table_end := 0.32
@export var shots_per_turn := 2
@export var miss_height := 0.45
@export var out_of_bounds_x := 1.55
@export var out_of_bounds_z_min := -3.55
@export var out_of_bounds_z_max := 0.85
@export var settled_speed := 0.08
@export var settled_after_seconds := 1.25
@export var scoring_settle_seconds := 0.35
@export var max_attempt_seconds := 7.0
@export var reset_delay := 0.45
@export var scored_reset_delay := 0.8
@export var cup_remove_delay := 0.65

var player_ids: Array[int] = []
var ball_authority_player_id := 0
var player_one_id := 0
var player_two_id := 0
var active_player_id := 0
var winner_player_id := 0
var match_phase := PHASE_WAITING

var _session
var _ball: ThrowableBall
var _player_one_cup_parent: Node3D
var _player_two_cup_parent: Node3D
var _score_label: Label3D
var _local_player_id := 0
var _scores_by_slot: Array[int] = [0, 0]
var _scored_cups_by_slot: Dictionary = {PLAYER_ONE_SLOT: [], PLAYER_TWO_SLOT: []}
var _rack_cups: Dictionary = {PLAYER_ONE_SLOT: [], PLAYER_TWO_SLOT: []}
var _scored_visual_keys: Dictionary = {}
var _pending_cup_removals: Array[Dictionary] = []
var _last_applied_version := 0
var _next_state_version := 0
var _shots_taken_this_turn := 0
var _attempt_active := false
var _attempt_elapsed := 0.0
var _reset_countdown := -1.0
var _ball_available := false
var _score_candidate: Node3D
var _score_candidate_settled_elapsed := 0.0


func _ready() -> void:
	_session = get_node_or_null(session_path)
	_ball = get_node_or_null(ball_path) as ThrowableBall
	_player_one_cup_parent = get_node_or_null(player_one_cup_parent_path) as Node3D
	_player_two_cup_parent = get_node_or_null(player_two_cup_parent_path) as Node3D
	_score_label = get_node_or_null(score_label_path) as Label3D

	_connect_ball()
	_build_starting_racks()
	_update_score_label()
	_update_ball_turn_configuration()

	if _session == null:
		push_warning("[MatchState] PhotonSession was not found; match state will stay local.")
		return

	_session.room_joined.connect(_on_room_joined)
	_session.player_joined.connect(_on_player_joined)
	_session.player_left.connect(_on_player_left)
	_session.room_left.connect(_on_room_left)


func _exit_tree() -> void:
	if _session != null and _session.has_method("unregister_broadcast_receiver"):
		_session.call("unregister_broadcast_receiver", self)


func _physics_process(delta: float) -> void:
	_update_pending_cup_removals(delta)
	_update_ball_reset(delta)

	if not _attempt_active or not _local_player_has_turn_authority():
		return

	_attempt_elapsed += delta
	if _try_confirm_score(delta):
		return

	if _is_miss():
		_resolve_attempt(false, null)


func get_ball_authority_player_id() -> int:
	return ball_authority_player_id


func get_local_player_slot() -> int:
	return _get_player_slot(_local_player_id)


func get_turn_shots_remaining() -> int:
	if match_phase != PHASE_PLAYING:
		return 0

	return max(0, shots_per_turn - _shots_taken_this_turn)


func get_status_text() -> String:
	if match_phase == PHASE_COMPLETE:
		return "%s wins\n%s: %d / 10  %s: %d / 10" % [
			_format_player(winner_player_id),
			_format_player(player_one_id),
			_scores_by_slot[0],
			_format_player(player_two_id),
			_scores_by_slot[1],
		]

	if match_phase == PHASE_PLAYING:
		return "%s turn: %d throws\n%s: %d / 10  %s: %d / 10" % [
			_format_player(active_player_id),
			get_turn_shots_remaining(),
			_format_player(player_one_id),
			_scores_by_slot[0],
			_format_player(player_two_id),
			_scores_by_slot[1],
		]

	return "Waiting for second player\nPlayers: %s" % [player_ids]


func _connect_ball() -> void:
	if _ball == null:
		push_warning("[MatchState] Networked ball is missing.")
		return

	_ball.released.connect(_on_ball_released)
	if _ball.has_signal("authority_changed"):
		_ball.connect("authority_changed", Callable(self, "_on_ball_authority_changed"))


func _on_room_joined(_room_name: String, local_player_id: int) -> void:
	_local_player_id = local_player_id
	if _session != null and _session.has_method("register_broadcast_receiver"):
		_session.call("register_broadcast_receiver", self)

	_refresh_players()


func _on_player_joined(_player_id: int, _player_name: String) -> void:
	_refresh_players()


func _on_player_left(player_id: int, _is_inactive: bool) -> void:
	_refresh_players()
	if player_id == active_player_id or player_ids.size() < 2:
		_publish_waiting_snapshot()


func _on_room_left() -> void:
	if _session != null and _session.has_method("unregister_broadcast_receiver"):
		_session.call("unregister_broadcast_receiver", self)

	_local_player_id = 0
	player_ids.clear()
	_publish_waiting_snapshot()
	players_changed.emit(player_ids)


func _refresh_players() -> void:
	if _session == null:
		return

	player_ids = _session.get_player_ids()
	player_ids.sort()
	players_changed.emit(player_ids)
	print("[MatchState] Players in room: %s" % [player_ids])

	if player_ids.size() == 2 and match_phase != PHASE_PLAYING and match_phase != PHASE_COMPLETE:
		_publish_start_match(player_ids[0], player_ids[1])
	elif player_ids.size() < 2 and match_phase != PHASE_WAITING:
		_publish_waiting_snapshot()
	else:
		_update_score_label()
		match_state_changed.emit(get_status_text())


func _publish_start_match(first_player_id: int, second_player_id: int) -> void:
	var scored_cups: Dictionary = {PLAYER_ONE_SLOT: [], PLAYER_TWO_SLOT: []}
	_publish_snapshot({
		"phase": PHASE_PLAYING,
		"player_one_id": first_player_id,
		"player_two_id": second_player_id,
		"active_player_id": second_player_id,
		"winner_player_id": 0,
		"shots_taken_this_turn": 0,
		"scores_by_slot": [0, 0],
		"scored_cups_slot_1": scored_cups[PLAYER_ONE_SLOT],
		"scored_cups_slot_2": scored_cups[PLAYER_TWO_SLOT],
		"reset_racks": true,
		"ball_reset_delay": 0.0,
	})
	print("[MatchState] Starting network match. Player %d throws first." % second_player_id)


func _publish_waiting_snapshot() -> void:
	var first_player_id := player_ids[0] if not player_ids.is_empty() else 0
	var second_player_id := player_ids[1] if player_ids.size() > 1 else 0
	_publish_snapshot({
		"phase": PHASE_WAITING,
		"player_one_id": first_player_id,
		"player_two_id": second_player_id,
		"active_player_id": 0,
		"winner_player_id": 0,
		"shots_taken_this_turn": 0,
		"scores_by_slot": [0, 0],
		"scored_cups_slot_1": [],
		"scored_cups_slot_2": [],
		"reset_racks": true,
		"ball_reset_delay": 0.0,
	})


func _publish_snapshot(snapshot: Dictionary) -> void:
	_next_state_version = max(_next_state_version + 1, _last_applied_version + 1)
	snapshot["version"] = _next_state_version
	_apply_match_snapshot(snapshot)

	if _session != null and _session.has_method("broadcast_rpc"):
		_session.call("broadcast_rpc", self, &"_rpc_apply_match_snapshot", [snapshot])


@rpc("any_peer", "call_local", "reliable")
func _rpc_apply_match_snapshot(snapshot: Dictionary) -> void:
	_apply_match_snapshot(snapshot)


func _apply_match_snapshot(snapshot: Dictionary) -> void:
	var version := int(snapshot.get("version", 0))
	if version > 0 and version <= _last_applied_version:
		return

	if version > 0:
		_last_applied_version = version
		_next_state_version = max(_next_state_version, version)

	match_phase = str(snapshot.get("phase", PHASE_WAITING))
	player_one_id = int(snapshot.get("player_one_id", 0))
	player_two_id = int(snapshot.get("player_two_id", 0))
	active_player_id = int(snapshot.get("active_player_id", 0))
	winner_player_id = int(snapshot.get("winner_player_id", 0))
	_shots_taken_this_turn = int(snapshot.get("shots_taken_this_turn", 0))
	_scores_by_slot = _read_two_ints(snapshot.get("scores_by_slot", [0, 0]))
	_scored_cups_by_slot = {
		PLAYER_ONE_SLOT: _read_int_array(snapshot.get("scored_cups_slot_1", [])),
		PLAYER_TWO_SLOT: _read_int_array(snapshot.get("scored_cups_slot_2", [])),
	}

	if bool(snapshot.get("reset_racks", false)):
		_build_starting_racks()

	_attempt_active = false
	_attempt_elapsed = 0.0
	_clear_score_candidate()
	_apply_scored_cups_to_racks()
	_set_ball_authority(active_player_id if match_phase == PHASE_PLAYING else 0)

	var reset_seconds := float(snapshot.get("ball_reset_delay", 0.0))
	if match_phase == PHASE_PLAYING:
		_schedule_ball_reset(reset_seconds)
	else:
		_reset_countdown = -1.0
		_ball_available = false
		_update_ball_turn_configuration()

	_update_score_label()
	match_state_changed.emit(get_status_text())
	print("[MatchState] Applied match snapshot v%d: %s" % [version, get_status_text().replace("\n", " | ")])


func _on_ball_released(_grabber: Node3D, _release_linear_velocity: Vector3, _release_angular_velocity: Vector3) -> void:
	if not _local_player_has_turn_authority() or not _ball_available:
		return

	_attempt_active = true
	_attempt_elapsed = 0.0
	_ball_available = false
	_clear_score_candidate()
	_update_ball_turn_configuration()
	print("[MatchState] Player %d released shot %d of %d." % [
		active_player_id,
		_shots_taken_this_turn + 1,
		shots_per_turn,
	])


func _try_confirm_score(delta: float) -> bool:
	var resting_cup := _get_ball_resting_opponent_cup()
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


func _resolve_attempt(was_score: bool, scored_cup: Node3D) -> void:
	if match_phase != PHASE_PLAYING:
		return

	var next_scores := _scores_by_slot.duplicate()
	var next_scored_cups := _copy_scored_cups_by_slot()
	var next_winner := 0
	var active_slot := _get_player_slot(active_player_id)
	var opponent_slot := _get_opponent_slot(active_slot)
	var resolved_score := false

	if was_score and scored_cup != null and is_instance_valid(scored_cup):
		var scored_owner_slot := int(scored_cup.get_meta("owner_slot", 0))
		var cup_index := int(scored_cup.get_meta("cup_index", -1))
		var opponent_scored_cups: Array = next_scored_cups.get(opponent_slot, [])
		if scored_owner_slot == opponent_slot and cup_index >= 0 and not opponent_scored_cups.has(cup_index):
			opponent_scored_cups.append(cup_index)
			opponent_scored_cups.sort()
			next_scored_cups[opponent_slot] = opponent_scored_cups
			next_scores[active_slot - 1] = min(10, int(next_scores[active_slot - 1]) + 1)
			resolved_score = true
			if opponent_scored_cups.size() >= 10:
				next_winner = active_player_id

	var next_shots_taken := _shots_taken_this_turn + 1
	var next_active_player := active_player_id
	var next_phase := PHASE_PLAYING
	if next_winner > 0:
		next_phase = PHASE_COMPLETE
	elif next_shots_taken >= shots_per_turn:
		next_active_player = _get_opponent_player_id(active_player_id)
		next_shots_taken = 0

	_publish_snapshot({
		"phase": next_phase,
		"player_one_id": player_one_id,
		"player_two_id": player_two_id,
		"active_player_id": next_active_player if next_phase == PHASE_PLAYING else 0,
		"winner_player_id": next_winner,
		"shots_taken_this_turn": next_shots_taken,
		"scores_by_slot": next_scores,
		"scored_cups_slot_1": next_scored_cups[PLAYER_ONE_SLOT],
		"scored_cups_slot_2": next_scored_cups[PLAYER_TWO_SLOT],
		"reset_racks": false,
		"ball_reset_delay": scored_reset_delay if resolved_score else reset_delay,
	})

	if resolved_score:
		print("[MatchState] Player %d scored. Scores: %s" % [active_player_id, next_scores])
	else:
		print("[MatchState] Player %d missed." % active_player_id)


func _is_miss() -> bool:
	if _ball == null:
		return true

	var position := _ball.global_position
	if position.y < miss_height:
		return true
	if absf(position.x) > out_of_bounds_x:
		return true
	if position.z < out_of_bounds_z_min or position.z > out_of_bounds_z_max:
		return true
	if _attempt_elapsed >= max_attempt_seconds:
		return true
	if _attempt_elapsed >= settled_after_seconds and _is_ball_settled() and _get_ball_resting_opponent_cup() == null:
		return true

	return false


func _get_ball_resting_opponent_cup() -> Node3D:
	if _ball == null:
		return null

	var active_slot := _get_player_slot(active_player_id)
	var opponent_slot := _get_opponent_slot(active_slot)
	var cups: Array = _rack_cups.get(opponent_slot, [])
	for cup in cups:
		if cup == null or not is_instance_valid(cup):
			continue
		if cup.has_method("is_ball_resting_inside") and cup.call("is_ball_resting_inside", _ball):
			return cup as Node3D

	return null


func _is_ball_settled() -> bool:
	if _ball == null:
		return false

	return (
		_ball.linear_velocity.length() <= settled_speed
		and _ball.angular_velocity.length() <= settled_speed * 8.0
	)


func _schedule_ball_reset(delay_seconds: float) -> void:
	_ball_available = false
	_update_ball_turn_configuration()
	if delay_seconds <= 0.0:
		_reset_ball_for_active_turn()
	else:
		_reset_countdown = delay_seconds


func _update_ball_reset(delta: float) -> void:
	if _reset_countdown < 0.0:
		return

	_reset_countdown -= delta
	if _reset_countdown <= 0.0:
		_reset_ball_for_active_turn()


func _reset_ball_for_active_turn() -> void:
	_reset_countdown = -1.0
	_attempt_active = false
	_attempt_elapsed = 0.0
	_clear_score_candidate()

	if _ball == null or match_phase != PHASE_PLAYING or active_player_id == 0:
		_ball_available = false
		_update_ball_turn_configuration()
		return

	_ball_available = true
	var reset_transform := _get_ball_spawn_transform(active_player_id)
	if _ball.has_method("reset_for_turn"):
		_ball.call("reset_for_turn", reset_transform, true)
	else:
		_ball.reset_to_transform(reset_transform, true)

	_update_ball_turn_configuration()


func _update_ball_turn_configuration() -> void:
	if _ball == null or not _ball.has_method("configure_turn"):
		return

	var available_shots := get_turn_shots_remaining() if _ball_available else 0
	_ball.call("configure_turn", _local_player_id, active_player_id, match_phase == PHASE_PLAYING, available_shots)


func _get_ball_spawn_transform(player_id: int) -> Transform3D:
	var slot := _get_player_slot(player_id)
	var half_length := table_length_meters * 0.5
	var spawn_z := table_center_z + half_length + ball_spawn_offset_from_table_end
	var rotation_y := 0.0
	if slot == PLAYER_TWO_SLOT:
		spawn_z = table_center_z - half_length - ball_spawn_offset_from_table_end
		rotation_y = PI

	return Transform3D(Basis(Vector3.UP, rotation_y), Vector3(0.0, ball_spawn_height, spawn_z))


func _build_starting_racks() -> void:
	_clear_cup_parent(_player_one_cup_parent)
	_clear_cup_parent(_player_two_cup_parent)
	_rack_cups = {PLAYER_ONE_SLOT: [], PLAYER_TWO_SLOT: []}
	_scored_visual_keys.clear()
	_pending_cup_removals.clear()

	if _player_one_cup_parent == null or _player_two_cup_parent == null:
		push_warning("[MatchState] Cup rack parent nodes are missing.")
		return

	var half_length := table_length_meters * 0.5
	var player_one_back_z := table_center_z + half_length - rack_back_row_offset_from_table_end
	var player_two_back_z := table_center_z - half_length + rack_back_row_offset_from_table_end
	_build_rack(PLAYER_ONE_SLOT, _player_one_cup_parent, Vector3(0.0, cup_height_y, player_one_back_z), -1.0)
	_build_rack(PLAYER_TWO_SLOT, _player_two_cup_parent, Vector3(0.0, cup_height_y, player_two_back_z), 1.0)


func _clear_cup_parent(parent: Node3D) -> void:
	if parent == null:
		return

	for child in parent.get_children():
		child.queue_free()


func _build_rack(slot: int, parent: Node3D, back_row_origin: Vector3, row_direction_z: float) -> void:
	var cup_index := 0
	for row in range(4):
		var cups_in_row := 4 - row
		var row_width := float(cups_in_row - 1) * cup_spacing
		var row_z := back_row_origin.z + row_direction_z * float(row) * cup_spacing * 0.92

		for column in range(cups_in_row):
			var cup := CupTargetScript.new()
			cup.name = "P%dCup_%02d" % [slot, cup_index]
			cup.visual_scene = cup_visual_scene
			cup.collision_scene = cup_collision_scene
			cup.position = Vector3(
				back_row_origin.x - row_width * 0.5 + float(column) * cup_spacing,
				back_row_origin.y,
				row_z
			)
			cup.set_meta("owner_slot", slot)
			cup.set_meta("cup_index", cup_index)
			parent.add_child(cup)
			_rack_cups[slot].append(cup)
			cup_index += 1


func _apply_scored_cups_to_racks() -> void:
	for slot in [PLAYER_ONE_SLOT, PLAYER_TWO_SLOT]:
		var scored_indices: Array = _scored_cups_by_slot.get(slot, [])
		var cups: Array = _rack_cups.get(slot, [])
		for cup in cups:
			if cup == null or not is_instance_valid(cup):
				continue

			var cup_index := int(cup.get_meta("cup_index", -1))
			if cup_index < 0 or not scored_indices.has(cup_index):
				continue

			_mark_cup_scored(slot, cup_index, cup)


func _mark_cup_scored(slot: int, cup_index: int, cup: Node3D) -> void:
	var key := _cup_key(slot, cup_index)
	if _scored_visual_keys.has(key):
		return

	_scored_visual_keys[key] = true
	if cup.has_method("mark_scored"):
		cup.call("mark_scored")

	_pending_cup_removals.append({
		"slot": slot,
		"cup_index": cup_index,
		"countdown": cup_remove_delay,
	})


func _update_pending_cup_removals(delta: float) -> void:
	for index in range(_pending_cup_removals.size() - 1, -1, -1):
		_pending_cup_removals[index]["countdown"] = float(_pending_cup_removals[index]["countdown"]) - delta
		if float(_pending_cup_removals[index]["countdown"]) > 0.0:
			continue

		var slot := int(_pending_cup_removals[index]["slot"])
		var cup_index := int(_pending_cup_removals[index]["cup_index"])
		var cup := _get_cup(slot, cup_index)
		if cup != null and is_instance_valid(cup):
			if cup.has_method("remove_from_game"):
				cup.call("remove_from_game")
			else:
				cup.queue_free()
		_pending_cup_removals.remove_at(index)


func _get_cup(slot: int, cup_index: int) -> Node3D:
	var cups: Array = _rack_cups.get(slot, [])
	for cup in cups:
		if cup == null or not is_instance_valid(cup):
			continue
		if int(cup.get_meta("cup_index", -1)) == cup_index:
			return cup as Node3D

	return null


func _set_ball_authority(player_id: int) -> void:
	if ball_authority_player_id == player_id:
		return

	ball_authority_player_id = player_id
	ball_authority_changed.emit(ball_authority_player_id)
	print("[MatchState] Ball authority target set to player %d." % ball_authority_player_id)


func _on_ball_authority_changed(player_id: int) -> void:
	if player_id > 0:
		ball_authority_player_id = player_id
		ball_authority_changed.emit(ball_authority_player_id)


func _local_player_has_turn_authority() -> bool:
	return match_phase == PHASE_PLAYING and _local_player_id > 0 and _local_player_id == active_player_id


func _get_player_slot(player_id: int) -> int:
	if player_id == player_one_id:
		return PLAYER_ONE_SLOT
	if player_id == player_two_id:
		return PLAYER_TWO_SLOT
	return 0


func _get_opponent_slot(slot: int) -> int:
	return PLAYER_TWO_SLOT if slot == PLAYER_ONE_SLOT else PLAYER_ONE_SLOT


func _get_opponent_player_id(player_id: int) -> int:
	if player_id == player_one_id:
		return player_two_id
	if player_id == player_two_id:
		return player_one_id
	return 0


func _copy_scored_cups_by_slot() -> Dictionary:
	return {
		PLAYER_ONE_SLOT: _read_int_array(_scored_cups_by_slot.get(PLAYER_ONE_SLOT, [])),
		PLAYER_TWO_SLOT: _read_int_array(_scored_cups_by_slot.get(PLAYER_TWO_SLOT, [])),
	}


func _read_two_ints(values: Variant) -> Array[int]:
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
		result.append(int(value))
	result.sort()
	return result


func _cup_key(slot: int, cup_index: int) -> String:
	return "%d:%d" % [slot, cup_index]


func _format_player(player_id: int) -> String:
	if player_id <= 0:
		return "P?"
	return "P%d" % player_id


func _clear_score_candidate() -> void:
	_score_candidate = null
	_score_candidate_settled_elapsed = 0.0


func _update_score_label() -> void:
	if _score_label == null:
		return

	_score_label.text = get_status_text()
