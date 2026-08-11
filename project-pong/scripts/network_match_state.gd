extends Node
class_name NetworkMatchState

signal players_changed(player_ids: Array[int])
signal ball_authority_changed(player_id: int)
signal match_state_changed(summary: String)

const MatchConstants := preload("res://scripts/match/pong_match_constants.gd")
const ClassicMatchModelScript := preload("res://scripts/match/classic_match_model.gd")
const CupRackBuilderScript := preload("res://scripts/match/cup_rack_builder.gd")
const RackStateScript := preload("res://scripts/match/rack_state.gd")
const ShotPhysicsScript := preload("res://scripts/match/shot_physics.gd")
const ShotScoreTrackerScript := preload("res://scripts/match/shot_score_tracker.gd")
const ShotAttemptEvaluatorScript := preload("res://scripts/match/shot_attempt_evaluator.gd")
const CupRemovalQueueScript := preload("res://scripts/match/cup_removal_queue.gd")
const HouseRulesProfileScript := preload("res://scripts/house_rules/house_rules_profile.gd")
const HouseRulesSettingsStoreScript := preload("res://scripts/house_rules/house_rules_settings_store.gd")
const ShotContextScript := preload("res://scripts/house_rules/shot_context.gd")
const ShotContactTrackerScript := preload("res://scripts/house_rules/shot_contact_tracker.gd")
const HouseRulesResolverScript := preload("res://scripts/house_rules/house_rules_resolver.gd")

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
var _match_model := ClassicMatchModelScript.new()
var _scores_by_slot: Array[int] = [0, 0]
var _scored_cups_by_slot: Dictionary = {PLAYER_ONE_SLOT: [], PLAYER_TWO_SLOT: []}
var _rack_state_by_slot: Dictionary = {}
var _scored_visual_keys: Dictionary = {}
var _pending_cup_removals := CupRemovalQueueScript.new()
var _house_rules_profile
var _contact_tracker := ShotContactTrackerScript.new()
var _last_shot_outcome: Dictionary = {}
var _last_applied_version := 0
var _next_state_version := 0
var _shots_taken_this_turn := 0
var _attempt_active := false
var _attempt_elapsed := 0.0
var _reset_countdown := -1.0
var _ball_available := false
var _score_tracker := ShotScoreTrackerScript.new()


func _ready() -> void:
	_session = get_node_or_null(session_path)
	_ball = get_node_or_null(ball_path) as ThrowableBall
	_player_one_cup_parent = get_node_or_null(player_one_cup_parent_path) as Node3D
	_player_two_cup_parent = get_node_or_null(player_two_cup_parent_path) as Node3D
	_score_label = get_node_or_null(score_label_path) as Label3D
	_house_rules_profile = HouseRulesSettingsStoreScript.load_profile()
	print("[MatchState] Loaded House Rules profile %s." % _house_rules_profile.get_compact_ruleset_id())
	_match_model.configure({
		"shots_per_turn": shots_per_turn,
		"rack_size": MatchConstants.RACK_SIZE,
	})
	_match_model.set_waiting()

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
	_contact_tracker.update(_attempt_elapsed)
	if _try_confirm_score():
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

	return _match_model.get_shots_remaining()


func get_status_text() -> String:
	if match_phase == PHASE_COMPLETE:
		return "%s wins\n%s: %d / %d  %s: %d / %d" % [
			_format_player(winner_player_id),
			_format_player(player_one_id),
			_scores_by_slot[0],
			MatchConstants.RACK_SIZE,
			_format_player(player_two_id),
			_scores_by_slot[1],
			MatchConstants.RACK_SIZE,
		]

	if match_phase == PHASE_PLAYING:
		return "%s turn: %d throws\n%s: %d / %d  %s: %d / %d" % [
			_format_player(active_player_id),
			get_turn_shots_remaining(),
			_format_player(player_one_id),
			_scores_by_slot[0],
			MatchConstants.RACK_SIZE,
			_format_player(player_two_id),
			_scores_by_slot[1],
			MatchConstants.RACK_SIZE,
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
	_update_ball_turn_configuration()


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
		_update_ball_turn_configuration()
		match_state_changed.emit(get_status_text())


func _publish_start_match(first_player_id: int, second_player_id: int) -> void:
	_match_model.reset_for_match(PLAYER_TWO_SLOT)
	var scored_cups := _match_model.get_scored_cups_by_slot()
	_publish_snapshot({
		"phase": PHASE_PLAYING,
		"player_one_id": first_player_id,
		"player_two_id": second_player_id,
		"active_player_id": second_player_id,
		"winner_player_id": 0,
		"shots_taken_this_turn": _match_model.shots_taken_this_turn,
		"scores_by_slot": _match_model.get_scores_by_slot(),
		"scored_cups_slot_1": scored_cups[PLAYER_ONE_SLOT],
		"scored_cups_slot_2": scored_cups[PLAYER_TWO_SLOT],
		"reset_racks": true,
		"ball_reset_delay": 0.0,
		"last_shot_outcome": {},
	})
	print("[MatchState] Starting network match. Player %d throws first." % second_player_id)


func _publish_waiting_snapshot() -> void:
	_match_model.set_waiting()
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
		"last_shot_outcome": {},
	})


func _publish_snapshot(snapshot: Dictionary) -> void:
	if _house_rules_profile != null and not snapshot.has("house_rules_profile"):
		snapshot["house_rules_profile"] = _house_rules_profile.to_dictionary()
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
	_sync_model_from_network_state()
	var profile_value: Variant = snapshot.get("house_rules_profile", {})
	if profile_value is Dictionary:
		_house_rules_profile = HouseRulesProfileScript.from_dictionary(profile_value)
	var last_outcome_value: Variant = snapshot.get("last_shot_outcome", {})
	_last_shot_outcome = last_outcome_value.duplicate(true) if last_outcome_value is Dictionary else {}

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
	_update_ball_turn_configuration()
	match_state_changed.emit(get_status_text())
	print("[MatchState] Applied match snapshot v%d: %s" % [version, get_status_text().replace("\n", " | ")])


func _on_ball_released(_grabber: Node3D, _release_linear_velocity: Vector3, _release_angular_velocity: Vector3) -> void:
	if not _local_player_has_turn_authority() or not _ball_available:
		return

	_attempt_active = true
	_attempt_elapsed = 0.0
	_ball_available = false
	_clear_score_candidate()
	_contact_tracker.start_attempt(_ball)
	_update_ball_turn_configuration()
	print("[MatchState] Player %d released shot %d of %d." % [
		active_player_id,
		_shots_taken_this_turn + 1,
		shots_per_turn,
	])


func _try_confirm_score() -> bool:
	var contact_candidate := _get_ball_score_contact_candidate()
	var confirmed_cup := _score_tracker.confirm_contact_candidate(contact_candidate)
	if confirmed_cup == null:
		return false

	_resolve_attempt(true, confirmed_cup)
	return true


func _resolve_attempt(was_score: bool, scored_cup: Node3D) -> void:
	if match_phase != PHASE_PLAYING:
		return

	var active_slot := _get_player_slot(active_player_id)
	var opponent_slot := _get_opponent_slot(active_slot)
	if active_slot <= 0 or opponent_slot <= 0:
		return

	var target_rack_state = _get_rack_state(opponent_slot)
	var contact_summary = _contact_tracker.stop_and_get_summary(_attempt_elapsed)
	var context = _build_shot_context(contact_summary, target_rack_state, active_slot, opponent_slot)
	var valid_score := false
	if was_score and scored_cup != null and is_instance_valid(scored_cup):
		var scored_owner_slot := int(scored_cup.get_meta("owner_slot", 0))
		var cup_index := int(scored_cup.get_meta("cup_index", -1))
		var opponent_scored_cups := _read_int_array(_scored_cups_by_slot.get(opponent_slot, []))
		valid_score = scored_owner_slot == opponent_slot and cup_index >= 0 and not opponent_scored_cups.has(cup_index)

	var outcome := HouseRulesResolverScript.resolve_attempt(
		context,
		valid_score,
		scored_cup if valid_score else null,
		scored_reset_delay if valid_score else reset_delay,
		0
	)
	_sync_model_from_network_state()
	var transition := _match_model.apply_shot_outcome(active_slot, opponent_slot, outcome)
	if bool(transition.get("resolved_score", false)) and valid_score:
		_ball.begin_score_capture(scored_cup)
	var next_scored_cups: Dictionary = transition.get("scored_cups_by_slot", _match_model.get_scored_cups_by_slot())
	var next_scores := _read_two_ints(transition.get("scores_by_slot", _match_model.get_scores_by_slot()))
	var next_winner_slot := int(transition.get("winner_slot", 0))
	var next_winner := _get_player_id_for_slot(next_winner_slot)
	var next_active_slot := int(transition.get("active_slot", 0))
	var next_active_player := _get_player_id_for_slot(next_active_slot)
	var next_phase := str(transition.get("phase", PHASE_PLAYING))
	outcome["winner"] = next_winner

	_publish_snapshot({
		"phase": next_phase,
		"player_one_id": player_one_id,
		"player_two_id": player_two_id,
		"active_player_id": next_active_player if next_phase == PHASE_PLAYING else 0,
		"winner_player_id": next_winner,
		"shots_taken_this_turn": int(transition.get("shots_taken_this_turn", 0)),
		"scores_by_slot": next_scores,
		"scored_cups_slot_1": next_scored_cups[PLAYER_ONE_SLOT],
		"scored_cups_slot_2": next_scored_cups[PLAYER_TWO_SLOT],
		"reset_racks": false,
		"ball_reset_delay": float(outcome.get("reset_delay", reset_delay)),
		"last_shot_outcome": _snapshot_outcome(outcome),
	})

	if bool(transition.get("resolved_score", false)):
		print("[MatchState] Player %d scored. Scores: %s.%s" % [
			active_player_id,
			next_scores,
			_format_rule_triggers(outcome),
		])
	else:
		print("[MatchState] Player %d missed." % active_player_id)


func _is_miss() -> bool:
	return ShotAttemptEvaluatorScript.is_miss(
		_ball,
		_attempt_elapsed,
		_get_attempt_bounds(),
		_get_ball_score_contact_candidate(),
		_is_ball_settled()
	)


func _get_ball_score_contact_candidate() -> Node3D:
	if _ball == null:
		return null

	var active_slot := _get_player_slot(active_player_id)
	var opponent_slot := _get_opponent_slot(active_slot)
	var rack_state = _get_rack_state(opponent_slot)
	return rack_state.find_score_contact_candidate(_ball) if rack_state != null else null


func _is_ball_settled() -> bool:
	return ShotPhysicsScript.is_ball_settled(_ball, settled_speed)


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
	_contact_tracker.clear()

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
	CupRackBuilderScript.clear_cup_parent(_player_one_cup_parent)
	CupRackBuilderScript.clear_cup_parent(_player_two_cup_parent)
	_contact_tracker.clear()
	_rack_state_by_slot = {
		PLAYER_ONE_SLOT: RackStateScript.new(),
		PLAYER_TWO_SLOT: RackStateScript.new(),
	}
	_scored_visual_keys.clear()
	_pending_cup_removals.clear()

	if _player_one_cup_parent == null or _player_two_cup_parent == null:
		push_warning("[MatchState] Cup rack parent nodes are missing.")
		return

	var half_length := table_length_meters * 0.5
	var player_one_back_z := table_center_z + half_length - rack_back_row_offset_from_table_end
	var player_two_back_z := table_center_z - half_length + rack_back_row_offset_from_table_end
	var player_one_cups := CupRackBuilderScript.build_triangular_rack(_player_one_cup_parent, {
		"back_row_origin": Vector3(0.0, cup_height_y, player_one_back_z),
		"row_direction_z": -1.0,
		"cup_spacing": cup_spacing,
		"name_prefix": "P%dCup" % PLAYER_ONE_SLOT,
		"owner_slot": PLAYER_ONE_SLOT,
	})
	var player_two_cups := CupRackBuilderScript.build_triangular_rack(_player_two_cup_parent, {
		"back_row_origin": Vector3(0.0, cup_height_y, player_two_back_z),
		"row_direction_z": 1.0,
		"cup_spacing": cup_spacing,
		"name_prefix": "P%dCup" % PLAYER_TWO_SLOT,
		"owner_slot": PLAYER_TWO_SLOT,
	})
	_get_rack_state(PLAYER_ONE_SLOT).configure(player_one_cups, PLAYER_ONE_SLOT)
	_get_rack_state(PLAYER_TWO_SLOT).configure(player_two_cups, PLAYER_TWO_SLOT)


func _apply_scored_cups_to_racks() -> void:
	for slot in [PLAYER_ONE_SLOT, PLAYER_TWO_SLOT]:
		var scored_indices: Array = _scored_cups_by_slot.get(slot, [])
		for value in scored_indices:
			var cup_index := int(value)
			var cup := _get_cup(slot, cup_index)
			_mark_cup_scored(slot, cup_index, cup)


func _mark_cup_scored(slot: int, cup_index: int, cup: Node3D) -> void:
	var rack_state = _get_rack_state(slot)
	if rack_state != null:
		rack_state.mark_scored(cup_index)

	var key := _cup_key(slot, cup_index)
	if _scored_visual_keys.has(key):
		return

	_scored_visual_keys[key] = true
	_pending_cup_removals.queue_scored_cup_key(slot, cup_index, cup, cup_remove_delay)


func _update_pending_cup_removals(delta: float) -> void:
	_pending_cup_removals.update(delta, Callable(self, "_get_cup"))


func _get_cup(slot: int, cup_index: int) -> Node3D:
	var rack_state = _get_rack_state(slot)
	return rack_state.get_cup(cup_index) if rack_state != null else null


func _get_rack_state(slot: int):
	return _rack_state_by_slot.get(slot, null)


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


func _get_player_id_for_slot(slot: int) -> int:
	if slot == PLAYER_ONE_SLOT:
		return player_one_id
	if slot == PLAYER_TWO_SLOT:
		return player_two_id
	return 0


func _sync_model_from_network_state() -> void:
	_match_model.configure({
		"shots_per_turn": shots_per_turn,
		"rack_size": MatchConstants.RACK_SIZE,
	})
	_match_model.load_state(
		match_phase,
		_get_player_slot(active_player_id),
		_get_player_slot(winner_player_id),
		_shots_taken_this_turn,
		_scores_by_slot,
		_scored_cups_by_slot
	)


func _copy_scored_cups_by_slot() -> Dictionary:
	return {
		PLAYER_ONE_SLOT: _read_int_array(_scored_cups_by_slot.get(PLAYER_ONE_SLOT, [])),
		PLAYER_TWO_SLOT: _read_int_array(_scored_cups_by_slot.get(PLAYER_TWO_SLOT, [])),
	}


func _build_shot_context(contact_summary, target_rack_state, active_slot: int, opponent_slot: int):
	var context = ShotContextScript.new()
	context.mode_id = &"online_arena"
	context.active_side = StringName("slot_%d" % active_slot)
	context.opponent_side = &""
	context.active_player_id = active_player_id
	context.opponent_player_id = _get_opponent_player_id(active_player_id)
	context.active_slot = active_slot
	context.target_slot = opponent_slot
	context.ball = _ball
	context.target_rack_state = target_rack_state
	context.rules_profile = _house_rules_profile
	context.contact_summary = contact_summary
	context.normal_shots_taken = _match_model.shots_taken_this_turn + 1
	context.normal_shots_per_turn = shots_per_turn
	return context


func _filter_new_network_cup_indices(slot: int, values: Variant, already_scored: Array) -> Array[int]:
	var result: Array[int] = []
	for cup_index in _read_int_array(values):
		if already_scored.has(cup_index) or result.has(cup_index):
			continue
		var rack_state = _get_rack_state(slot)
		if rack_state == null or rack_state.is_scored(cup_index):
			continue
		if rack_state.get_cup(cup_index) == null:
			continue
		result.append(cup_index)
	result.sort()
	return result


func _snapshot_outcome(outcome: Dictionary) -> Dictionary:
	var snapshot := outcome.duplicate(true)
	snapshot.erase("scored_cup")
	return snapshot


func _format_rule_triggers(outcome: Dictionary) -> String:
	var triggers: Array = outcome.get("rule_triggers", [])
	if triggers.is_empty():
		return ""
	return " Rules: %s" % [triggers]


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
	_score_tracker.reset()


func _update_score_label() -> void:
	if _score_label == null:
		return

	_score_label.text = get_status_text()


func _get_attempt_bounds() -> Dictionary:
	return {
		"miss_height": miss_height,
		"out_of_bounds_x": out_of_bounds_x,
		"out_of_bounds_z_min": out_of_bounds_z_min,
		"out_of_bounds_z_max": out_of_bounds_z_max,
		"settled_after_seconds": settled_after_seconds,
		"max_attempt_seconds": max_attempt_seconds,
	}
