extends Node3D
class_name ShotTesterApp

const MatchConstants := preload("res://scripts/match/pong_match_constants.gd")
const CupRackBuilderScript := preload("res://scripts/match/cup_rack_builder.gd")
const CupRemovalQueueScript := preload("res://scripts/match/cup_removal_queue.gd")
const ShotPhysicsScript := preload("res://scripts/match/shot_physics.gd")
const ShotAttemptEvaluatorScript := preload("res://scripts/match/shot_attempt_evaluator.gd")
const ShotContactTrackerScript := preload("res://scripts/house_rules/shot_contact_tracker.gd")
const ShotTesterBallLauncherScript := preload("res://scripts/editor/shot_tester/shot_tester_ball_launcher.gd")
const ShotTesterLogScript := preload("res://scripts/editor/shot_tester/shot_tester_log.gd")
const ShotTesterUiScript := preload("res://scripts/editor/shot_tester/shot_tester_ui.gd")
const CupTargetScene := preload("res://scenes/gameplay/cup_target.tscn")

const TARGET_SLOT := MatchConstants.PLAYER_TWO_SLOT
const TARGET_SIDE := &"target"
const MIN_RELEASE_ANGLE_DEGREES := 8.0
const MAX_RELEASE_ANGLE_DEGREES := 88.0
const CAPTURED_CUP_REMOVE_DELAY := 0.1

@export var cup_rack_root_path: NodePath
@export var ball_path: NodePath
@export var aim_indicator_path: NodePath
@export var camera_path: NodePath
@export var ui_root_path: NodePath
@export var cup_scene: PackedScene = CupTargetScene
@export var table_center_z := -1.56
@export var table_length_meters := 2.7432
@export var rack_end_margin := 0.14
@export var cup_height_y := 0.78
@export var cup_spacing := 0.105
@export var ball_spawn_height := 1.18
@export var miss_height := 0.45
@export var out_of_bounds_x := 1.45
@export var out_of_bounds_padding_z := 0.45
@export var settled_speed := 0.08
@export var settled_after_seconds := 1.25
@export var max_attempt_seconds := 5.0
@export var default_release_angle_degrees := 88.0
@export var deterministic_seed := 20260809
@export var log_export_path := "user://shot_tester_log.txt"
@export var testing_camera_focus := Vector3(0.0, 0.88, -1.56)
@export_range(0.05, 4.0, 0.05) var testing_camera_move_speed := 1.25
@export_range(0.05, 4.0, 0.05) var testing_camera_zoom_speed := 0.9
@export_range(0.001, 0.02, 0.001) var testing_camera_drag_sensitivity := 0.006

var _rack_root: Node3D
var _ball: RigidBody3D
var _aim_indicator: Node3D
var _testing_camera: Camera3D
var _ui_root: Control
var _cups: Array[Node3D] = []
var _ui = ShotTesterUiScript.new()
var _log = ShotTesterLogScript.new()
var _contact_tracker = ShotContactTrackerScript.new()
var _pending_cup_removals = CupRemovalQueueScript.new()

var _aim_position := Vector3.ZERO
var _release_angle_degrees := 88.0
var _aim_error_radius := 0.0
var _angle_error_degrees := 0.0
var _seed := 20260809
var _active_cup_indices: Array[int] = []
var _last_launch_plan: Dictionary = {}
var _last_native_score_contact: Dictionary = {}
var _export_status := ""

var _attempt_active := false
var _attempt_elapsed := 0.0
var _attempt_initial_conditions: Dictionary = {}
var _attempt_native_score_contact_count := 0
var _pending_score_cup: Node3D
var _last_resolved_event: Dictionary = {}

var _cli_auto_test_running := false
var _camera_dragging := false
var _aim_dragging := false
var _camera_yaw := 0.0
var _camera_pitch := deg_to_rad(38.0)
var _camera_distance := 3.45


func _ready() -> void:
	if OS.has_feature("template"):
		push_warning("[ShotTester] Editor-only shot tester is disabled in exported builds.")
		set_process(false)
		set_physics_process(false)
		return

	_bind_scene_nodes()
	_reset_defaults()
	_rebuild_rack()
	_reset_ball()
	_set_aim_position(_get_default_aim_position())
	_initialize_testing_camera()
	_build_ui()
	_update_launch_preview()
	_refresh_ui()

	if _try_run_cli_shot_test():
		set_process(false)
		set_physics_process(true)
		return

	set_process(true)
	set_physics_process(true)


func _process(delta: float) -> void:
	if _cli_auto_test_running:
		return
	_update_testing_camera_input(delta)
	_update_aim_keyboard_input(delta)


func _physics_process(delta: float) -> void:
	_pending_cup_removals.update(delta)
	if not _attempt_active:
		return

	_attempt_elapsed += delta
	_contact_tracker.update(_attempt_elapsed)
	var score_candidate: Node3D = _get_score_contact_candidate()
	var ball_settled := ShotPhysicsScript.is_ball_settled(_ball, settled_speed)
	var miss := ShotAttemptEvaluatorScript.is_miss(
		_ball,
		_attempt_elapsed,
		_get_attempt_bounds(),
		score_candidate,
		ball_settled
	)
	if miss:
		_resolve_attempt("miss_or_timeout")


func _unhandled_input(event: InputEvent) -> void:
	if _cli_auto_test_running:
		return

	var mouse_button := event as InputEventMouseButton
	if mouse_button != null:
		_handle_mouse_button(mouse_button)
		return

	var mouse_motion := event as InputEventMouseMotion
	if mouse_motion != null:
		_handle_mouse_motion(mouse_motion)
		return

	var key_event := event as InputEventKey
	if key_event != null and key_event.pressed and not key_event.echo:
		if key_event.keycode == KEY_F and _aim_indicator != null:
			testing_camera_focus = _aim_indicator.global_position
			_update_testing_camera_transform()
		elif key_event.keycode == KEY_C and _rack_root != null:
			testing_camera_focus = _get_rack_center_position()
			_update_testing_camera_transform()


func apply_test_configuration(config: Dictionary) -> void:
	if config.has("seed"):
		_seed = int(config["seed"])
	if config.has("release_angle_degrees"):
		_release_angle_degrees = clampf(
			float(config["release_angle_degrees"]),
			MIN_RELEASE_ANGLE_DEGREES,
			MAX_RELEASE_ANGLE_DEGREES
		)
	if config.has("aim_error_radius"):
		_aim_error_radius = maxf(0.0, float(config["aim_error_radius"]))
	if config.has("angle_error_degrees"):
		_angle_error_degrees = maxf(0.0, float(config["angle_error_degrees"]))
	if config.has("active_cup_indices"):
		_active_cup_indices = _sanitize_cup_indices(config["active_cup_indices"])
		_rebuild_rack()
	if config.has("aim_position"):
		var configured_aim: Variant = config["aim_position"]
		if configured_aim is Vector3:
			_set_aim_position(configured_aim)
	_reset_ball()
	_update_launch_preview()
	_refresh_ui()


func run_single_shot_test(config := {}) -> Dictionary:
	apply_test_configuration(config)
	if not _start_test_shot():
		var failed := get_test_snapshot()
		failed["passed"] = false
		if str(failed.get("failure_reason", "")).is_empty():
			failed["failure_reason"] = "Could not start shot."
		return failed

	var frame_limit := maxi(1, int(config.get("max_physics_frames", 6000)))
	var frames_simulated := 0
	while _attempt_active and frames_simulated < frame_limit:
		await get_tree().physics_frame
		frames_simulated += 1

	if _attempt_active:
		_resolve_attempt("frame_limit", "Shot exceeded the configured physics frame limit.")

	var result := get_test_snapshot()
	result["physics_frames_simulated"] = frames_simulated
	result["passed"] = _evaluate_expectations(result, config)
	return result


func get_test_snapshot() -> Dictionary:
	var event := _last_resolved_event.duplicate(true)
	var result: Dictionary = event.get("result", {}) if event.get("result", {}) is Dictionary else {}
	return {
		"resolved": not event.is_empty(),
		"shot_count": _log.events.size(),
		"resolved_score": bool(result.get("resolved_score", false)),
		"was_score": bool(result.get("was_score", false)),
		"scored_cup_index": int(result.get("scored_cup_index", -1)),
		"removed_cup_indices": result.get("removed_cup_indices", []),
		"remaining_cup_indices": _active_cup_indices.duplicate(),
		"native_contact_count": int(result.get("native_contact_count", 0)),
		"native_score_contact": event.get("native_score_contact", {}),
		"event": event,
		"failure_reason": str(event.get("failure_reason", "")),
	}


func _bind_scene_nodes() -> void:
	_rack_root = get_node_or_null(cup_rack_root_path) as Node3D
	_ball = get_node_or_null(ball_path) as RigidBody3D
	_aim_indicator = get_node_or_null(aim_indicator_path) as Node3D
	_testing_camera = get_node_or_null(camera_path) as Camera3D
	_ui_root = get_node_or_null(ui_root_path) as Control

	if _rack_root == null:
		push_error("[ShotTester] CupRackRoot is not configured.")
	if _ball == null:
		push_error("[ShotTester] SimulationBall is not configured.")
	else:
		if _ball.has_method("set_grabbable"):
			_ball.call("set_grabbable", false)
		_ball.connect("score_contact_detected", Callable(self, "_on_ball_score_contact_detected"))
		_ball.connect("score_capture_finished", Callable(self, "_on_ball_score_capture_finished"))
	if _aim_indicator == null:
		push_error("[ShotTester] AimIndicator is not configured.")
	if _ui_root == null:
		push_warning("[ShotTester] UI root is not configured; headless shot tests can still run.")


func _reset_defaults() -> void:
	_release_angle_degrees = clampf(
		default_release_angle_degrees,
		MIN_RELEASE_ANGLE_DEGREES,
		MAX_RELEASE_ANGLE_DEGREES
	)
	_aim_error_radius = 0.0
	_angle_error_degrees = 0.0
	_seed = deterministic_seed
	_active_cup_indices.clear()
	for cup_index in range(MatchConstants.RACK_SIZE):
		_active_cup_indices.append(cup_index)


func _rebuild_rack() -> void:
	if _rack_root == null:
		return

	for child in _rack_root.get_children():
		child.free()
	_cups.clear()
	_pending_cup_removals.clear()

	var half_length := table_length_meters * 0.5
	var scene_to_use: PackedScene = cup_scene if cup_scene != null else CupTargetScene
	_cups = CupRackBuilderScript.build_triangular_rack(_rack_root, {
		"cup_scene": scene_to_use,
		"back_row_origin": Vector3(0.0, cup_height_y, table_center_z - half_length + rack_end_margin),
		"row_direction_z": 1.0,
		"cup_spacing": cup_spacing,
		"name_prefix": "ShotTesterCup",
		"name_start_index": 0,
		"owner_slot": TARGET_SLOT,
		"owner_side": TARGET_SIDE,
	})
	for cup in _cups:
		var cup_index := int(cup.get_meta("cup_index", -1))
		if not _active_cup_indices.has(cup_index):
			_disable_inactive_cup(cup)


func _disable_inactive_cup(cup: Node3D) -> void:
	if cup == null or not is_instance_valid(cup):
		return
	cup.visible = false
	if cup is CollisionObject3D:
		var collision_object := cup as CollisionObject3D
		collision_object.collision_layer = 0
		collision_object.collision_mask = 0
	cup.set_meta("is_scored", true)
	if cup.has_method("mark_scored"):
		cup.call("mark_scored")


func _build_ui() -> void:
	if _ui_root == null:
		return

	_ui.build(_ui_root)
	_ui.aim_position_changed.connect(_on_ui_aim_position_changed)
	_ui.release_angle_changed.connect(_on_ui_release_angle_changed)
	_ui.aim_error_changed.connect(_on_ui_aim_error_changed)
	_ui.angle_error_changed.connect(_on_ui_angle_error_changed)
	_ui.seed_changed.connect(_on_ui_seed_changed)
	_ui.cup_toggled.connect(_on_ui_cup_toggled)
	_ui.test_shot_requested.connect(_on_ui_test_shot_requested)
	_ui.repeat_shot_requested.connect(_on_ui_repeat_shot_requested)
	_ui.next_variation_requested.connect(_on_ui_next_variation_requested)
	_ui.reset_ball_requested.connect(_on_ui_reset_ball_requested)
	_ui.reset_rack_requested.connect(_on_ui_reset_rack_requested)
	_ui.export_log_requested.connect(_on_ui_export_log_requested)


func _start_test_shot() -> bool:
	if _ball == null:
		return false

	_pending_cup_removals.clear()
	for cup in _cups:
		if (
			cup != null
			and is_instance_valid(cup)
			and not _active_cup_indices.has(int(cup.get_meta("cup_index", -1)))
		):
			_disable_inactive_cup(cup)
	_reset_attempt_state()
	_contact_tracker.start_attempt(_ball)
	_last_launch_plan = ShotTesterBallLauncherScript.build_launch_plan(
		_ball,
		_get_ball_spawn_transform(),
		_aim_position,
		_release_angle_degrees,
		_aim_error_radius,
		_angle_error_degrees,
		_seed
	)
	if not bool(_last_launch_plan.get("success", false)):
		_resolve_failed_start("launch_velocity_invalid")
		_refresh_ui()
		return false

	_attempt_initial_conditions = _last_launch_plan.duplicate(true)
	ShotTesterBallLauncherScript.launch_ball(_ball, _last_launch_plan)
	_attempt_active = true
	_export_status = ""
	print("[ShotTester] Test shot launched with velocity %s toward %s." % [
		_last_launch_plan.get("launch_velocity", Vector3.ZERO),
		_last_launch_plan.get("effective_aim_position", _aim_position),
	])
	_refresh_ui()
	return true


func _reset_ball() -> void:
	if _ball == null:
		return
	ShotTesterBallLauncherScript.reset_ball(_ball, _get_ball_spawn_transform(), true)
	_pending_cup_removals.clear()
	_reset_attempt_state()
	_contact_tracker.clear()
	for cup in _cups:
		if cup == null or not is_instance_valid(cup):
			continue
		if not _active_cup_indices.has(int(cup.get_meta("cup_index", -1))):
			_disable_inactive_cup(cup)


func _reset_attempt_state() -> void:
	_attempt_active = false
	_attempt_elapsed = 0.0
	_attempt_native_score_contact_count = 0
	_last_native_score_contact.clear()
	_pending_score_cup = null


func _resolve_attempt(resolve_reason: String, failure_reason := "") -> void:
	if not _attempt_active:
		return

	var scored_cup_index := -1
	if _pending_score_cup != null and is_instance_valid(_pending_score_cup):
		scored_cup_index = int(_pending_score_cup.get_meta("cup_index", -1))
	var was_score := scored_cup_index >= 0
	var contact_summary = _contact_tracker.stop_and_get_summary(_attempt_elapsed)
	var contact_summary_data: Dictionary = contact_summary.to_dictionary()
	var contacts: Array = contact_summary_data.get("contacts", [])
	var native_contact_count := maxi(contacts.size(), _attempt_native_score_contact_count)

	_attempt_active = false
	var event := {
		"shot": _log.events.size() + 1,
		"seed": _seed,
		"initial_conditions": _attempt_initial_conditions.duplicate(true),
		"active_cup_indices_before_shot": _get_active_indices_before_result(scored_cup_index),
		"result": {
			"resolved_score": was_score,
			"was_score": was_score,
			"scored_cup_index": scored_cup_index,
			"removed_cup_indices": [scored_cup_index] if was_score else [],
			"remaining_cup_indices": _active_cup_indices.duplicate(),
			"native_contact_count": native_contact_count,
		},
		"native_score_contact": _last_native_score_contact.duplicate(true),
		"contact_summary": contact_summary_data,
		"attempt_seconds": _attempt_elapsed,
		"ball_position": _ball.global_position if _ball != null else Vector3.ZERO,
		"resolve_reason": resolve_reason,
		"failure_reason": failure_reason,
	}
	_last_resolved_event = event.duplicate(true)
	_log.add_event(event)
	_pending_score_cup = null
	print("[ShotTester] %s" % _log.format_event_summary(event))
	_reset_ball_after_attempt()
	_refresh_ui()


func _reset_ball_after_attempt() -> void:
	if _ball == null:
		return
	ShotTesterBallLauncherScript.reset_ball(_ball, _get_ball_spawn_transform(), true)


func _resolve_failed_start(reason: String) -> void:
	var event := {
		"shot": _log.events.size() + 1,
		"seed": _seed,
		"initial_conditions": _last_launch_plan.duplicate(true),
		"active_cup_indices_before_shot": _active_cup_indices.duplicate(),
		"result": {
			"resolved_score": false,
			"was_score": false,
			"scored_cup_index": -1,
			"removed_cup_indices": [],
			"remaining_cup_indices": _active_cup_indices.duplicate(),
			"native_contact_count": 0,
		},
		"native_score_contact": {},
		"contact_summary": {"contacts": []},
		"attempt_seconds": 0.0,
		"ball_position": _ball.global_position if _ball != null else Vector3.ZERO,
		"resolve_reason": "failed_start",
		"failure_reason": reason,
	}
	_last_resolved_event = event.duplicate(true)
	_log.add_event(event)
	push_warning("[ShotTester] %s" % reason)


func _on_ball_score_contact_detected(ball: Node3D, cup: Node3D, snapshot: Dictionary) -> void:
	if not _attempt_active or ball != _ball or cup == null or not is_instance_valid(cup):
		return

	var cup_index := int(cup.get_meta("cup_index", -1))
	if not _active_cup_indices.has(cup_index):
		if _ball.has_method("reject_score_contact_candidate"):
			_ball.call("reject_score_contact_candidate", cup)
		return

	_attempt_native_score_contact_count += 1
	_last_native_score_contact = snapshot.duplicate(true)
	_last_native_score_contact["time_seconds"] = _attempt_elapsed
	_last_native_score_contact["cup_index"] = cup_index
	_contact_tracker.update(_attempt_elapsed)

	if not bool(_ball.call("begin_score_capture", cup)):
		if _ball.has_method("reject_score_contact_candidate"):
			_ball.call("reject_score_contact_candidate", cup)
		_resolve_attempt("score_capture_failed", "Native score contact could not start ball capture.")
		return

	_pending_score_cup = cup
	_active_cup_indices.erase(cup_index)
	print("[ShotTester] Native score contact accepted for cup %d at %s." % [
		cup_index,
		snapshot.get("world_contact_point", Vector3.ZERO),
	])
	_refresh_ui()


func _on_ball_score_capture_finished(ball: Node3D, cup: Node3D) -> void:
	if not _attempt_active or ball != _ball or cup != _pending_score_cup:
		return
	_pending_cup_removals.queue_scored_cup(cup, CAPTURED_CUP_REMOVE_DELAY)
	_resolve_attempt("score_capture_finished")


func _update_launch_preview() -> void:
	if _ball == null:
		_last_launch_plan = {}
		return

	_last_launch_plan = ShotTesterBallLauncherScript.build_launch_plan(
		_ball,
		_get_ball_spawn_transform(),
		_aim_position,
		_release_angle_degrees,
		_aim_error_radius,
		_angle_error_degrees,
		_seed
	)


func _refresh_ui() -> void:
	if _ui_root == null:
		return
	_ui.refresh({
		"aim_position": _aim_position,
		"release_angle_degrees": _release_angle_degrees,
		"aim_error_radius": _aim_error_radius,
		"angle_error_degrees": _angle_error_degrees,
		"seed": _seed,
		"active_cup_indices": _active_cup_indices.duplicate(),
		"launch_plan": _last_launch_plan,
		"last_native_score_contact": _last_native_score_contact,
		"attempt_native_contact_count": _get_current_native_contact_count(),
		"attempt_active": _attempt_active,
		"status_text": _get_status_text(),
		"export_status": _export_status,
		"events": _log.get_events(),
	})


func _get_status_text() -> String:
	if _attempt_active and _pending_score_cup != null:
		return "Capturing native score in cup %d" % int(_pending_score_cup.get_meta("cup_index", -1))
	if _attempt_active:
		return "Simulating %.2f s | native contacts %d" % [
			_attempt_elapsed,
			_get_current_native_contact_count(),
		]
	var last_event := _log.get_last_event()
	if not last_event.is_empty():
		return _log.format_event_summary(last_event)
	return "Ready. Shared native cup physics is active."


func _get_current_native_contact_count() -> int:
	if not _attempt_active:
		var last_result: Dictionary = _last_resolved_event.get("result", {}) if _last_resolved_event.get("result", {}) is Dictionary else {}
		return int(last_result.get("native_contact_count", 0))
	var summary = _contact_tracker.get_summary()
	var summary_data: Dictionary = summary.to_dictionary()
	var contacts: Array = summary_data.get("contacts", [])
	return maxi(contacts.size(), _attempt_native_score_contact_count)


func _set_aim_position(position: Vector3) -> void:
	_aim_position = position
	if _aim_indicator != null:
		_aim_indicator.global_position = _aim_position
	_update_launch_preview()
	_refresh_ui()


func _get_default_aim_position() -> Vector3:
	var available_cups := _get_available_cups()
	if available_cups.is_empty():
		return Vector3(0.0, cup_height_y + 0.058, table_center_z)
	var spawn_position := _get_ball_spawn_transform().origin
	var closest_cup: Node3D
	var closest_distance_squared := INF
	for cup in available_cups:
		var horizontal_offset := cup.global_position - spawn_position
		horizontal_offset.y = 0.0
		var distance_squared := horizontal_offset.length_squared()
		if distance_squared < closest_distance_squared:
			closest_distance_squared = distance_squared
			closest_cup = cup
	if closest_cup != null and closest_cup.has_method("get_rim_center_position"):
		return closest_cup.call("get_rim_center_position") as Vector3
	return closest_cup.global_position if closest_cup != null else Vector3(0.0, cup_height_y + 0.058, table_center_z)


func _get_rack_center_position() -> Vector3:
	var available_cups := _get_available_cups()
	if available_cups.is_empty():
		return Vector3(0.0, cup_height_y + 0.058, table_center_z)
	var center := Vector3.ZERO
	for cup in available_cups:
		if cup.has_method("get_rim_center_position"):
			center += cup.call("get_rim_center_position") as Vector3
		else:
			center += cup.global_position
	return center / float(available_cups.size())


func _get_available_cups() -> Array[Node3D]:
	var available: Array[Node3D] = []
	for cup in _cups:
		if (
			cup != null
			and is_instance_valid(cup)
			and _active_cup_indices.has(int(cup.get_meta("cup_index", -1)))
		):
			available.append(cup)
	return available


func _get_score_contact_candidate() -> Node3D:
	if _ball == null or not _ball.has_method("get_score_contact_candidate"):
		return null
	return _ball.call("get_score_contact_candidate") as Node3D


func _get_active_indices_before_result(scored_cup_index: int) -> Array[int]:
	var indices := _active_cup_indices.duplicate()
	if scored_cup_index >= 0 and not indices.has(scored_cup_index):
		indices.append(scored_cup_index)
		indices.sort()
	return indices


func _get_ball_spawn_transform() -> Transform3D:
	var half_length := table_length_meters * 0.5
	var spawn_z := table_center_z + half_length + rack_end_margin
	return Transform3D(Basis.IDENTITY, Vector3(0.0, ball_spawn_height, spawn_z))


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


func _initialize_testing_camera() -> void:
	_camera_yaw = 0.0
	_camera_pitch = deg_to_rad(38.0)
	_camera_distance = 3.45
	_update_testing_camera_transform()


func _update_testing_camera_input(delta: float) -> void:
	if _testing_camera == null:
		return

	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move.z -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move.z += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move.x += 1.0
	if Input.is_key_pressed(KEY_Q):
		move.y -= 1.0
	if Input.is_key_pressed(KEY_E):
		move.y += 1.0

	if move.length_squared() > 0.0:
		var basis := Basis(Vector3.UP, _camera_yaw)
		var world_move := basis * move.normalized()
		testing_camera_focus += world_move * testing_camera_move_speed * delta
		_update_testing_camera_transform()


func _update_aim_keyboard_input(delta: float) -> void:
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_J):
		move.x -= 1.0
	if Input.is_key_pressed(KEY_L):
		move.x += 1.0
	if Input.is_key_pressed(KEY_I):
		move.z -= 1.0
	if Input.is_key_pressed(KEY_K):
		move.z += 1.0
	if Input.is_key_pressed(KEY_U):
		move.y += 1.0
	if Input.is_key_pressed(KEY_O):
		move.y -= 1.0
	if move.length_squared() <= 0.0:
		return

	var speed := 0.35
	if Input.is_key_pressed(KEY_SHIFT):
		speed = 0.9
	elif Input.is_key_pressed(KEY_CTRL):
		speed = 0.08
	_set_aim_position(_aim_position + move.normalized() * speed * delta)


func _update_testing_camera_transform() -> void:
	if _testing_camera == null:
		return

	_camera_pitch = clampf(_camera_pitch, deg_to_rad(-10.0), deg_to_rad(78.0))
	_camera_distance = clampf(_camera_distance, 0.7, 8.0)
	var offset := Vector3(
		sin(_camera_yaw) * cos(_camera_pitch),
		sin(_camera_pitch),
		cos(_camera_yaw) * cos(_camera_pitch)
	) * _camera_distance
	_testing_camera.global_position = testing_camera_focus + offset
	_testing_camera.look_at(testing_camera_focus, Vector3.UP)
	_testing_camera.current = true


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		_camera_distance = maxf(0.7, _camera_distance - testing_camera_zoom_speed * 0.2)
		_update_testing_camera_transform()
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		_camera_distance = minf(8.0, _camera_distance + testing_camera_zoom_speed * 0.2)
		_update_testing_camera_transform()
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		_camera_dragging = event.pressed
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		_aim_dragging = event.pressed and _is_screen_position_near_aim(event.position)
		if _aim_dragging:
			get_viewport().set_input_as_handled()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _camera_dragging:
		_camera_yaw -= event.relative.x * testing_camera_drag_sensitivity
		_camera_pitch -= event.relative.y * testing_camera_drag_sensitivity
		_update_testing_camera_transform()
		get_viewport().set_input_as_handled()
		return

	if _aim_dragging:
		var position: Variant = _get_aim_drag_position(event.position)
		if position is Vector3:
			_set_aim_position(position)
			get_viewport().set_input_as_handled()


func _is_screen_position_near_aim(screen_position: Vector2) -> bool:
	if _testing_camera == null or _aim_indicator == null:
		return false
	if _testing_camera.is_position_behind(_aim_indicator.global_position):
		return false
	return screen_position.distance_to(_testing_camera.unproject_position(_aim_indicator.global_position)) <= 32.0


func _get_aim_drag_position(screen_position: Vector2) -> Variant:
	if _testing_camera == null:
		return null

	var ray_origin := _testing_camera.project_ray_origin(screen_position)
	var ray_direction := _testing_camera.project_ray_normal(screen_position)
	if absf(ray_direction.y) <= 0.0001:
		return null

	var distance := (_aim_position.y - ray_origin.y) / ray_direction.y
	if distance < 0.0:
		return null
	var hit := ray_origin + ray_direction * distance
	return Vector3(hit.x, _aim_position.y, hit.z)


func _try_run_cli_shot_test() -> bool:
	var user_args := OS.get_cmdline_user_args()
	if not user_args.has("--shot-test"):
		return false

	var config: Dictionary = {}
	for arg in user_args:
		if arg.begins_with("--shot-aim="):
			var parsed_aim: Variant = _parse_vector3(arg.trim_prefix("--shot-aim="))
			if parsed_aim is Vector3:
				config["aim_position"] = parsed_aim
		elif arg.begins_with("--shot-angle="):
			config["release_angle_degrees"] = float(arg.trim_prefix("--shot-angle="))
		elif arg.begins_with("--shot-aim-error="):
			config["aim_error_radius"] = float(arg.trim_prefix("--shot-aim-error="))
		elif arg.begins_with("--shot-angle-error="):
			config["angle_error_degrees"] = float(arg.trim_prefix("--shot-angle-error="))
		elif arg.begins_with("--shot-seed="):
			config["seed"] = int(arg.trim_prefix("--shot-seed="))
		elif arg.begins_with("--shot-active-cups="):
			config["active_cup_indices"] = _parse_int_list(arg.trim_prefix("--shot-active-cups="))
		elif arg.begins_with("--shot-max-physics-frames="):
			config["max_physics_frames"] = int(arg.trim_prefix("--shot-max-physics-frames="))
		elif arg.begins_with("--shot-expect-contact="):
			config["expect_contact"] = _parse_bool(arg.trim_prefix("--shot-expect-contact="))
		elif arg.begins_with("--shot-expect-score="):
			config["expect_score"] = _parse_bool(arg.trim_prefix("--shot-expect-score="))

	call_deferred("_run_cli_shot_test", config)
	return true


func _run_cli_shot_test(config: Dictionary) -> void:
	_cli_auto_test_running = true
	var result := await run_single_shot_test(config)
	result["shot_test"] = true
	print("[ShotTester] %s" % JSON.stringify(_log.json_safe_variant(result)))
	get_tree().quit(0 if bool(result.get("passed", false)) else 1)


func _evaluate_expectations(snapshot: Dictionary, config: Dictionary) -> bool:
	if not bool(snapshot.get("resolved", false)):
		snapshot["failure_reason"] = "Shot was not resolved."
		return false
	if not str(snapshot.get("failure_reason", "")).is_empty():
		return false
	if config.has("expect_contact"):
		var had_contact := int(snapshot.get("native_contact_count", 0)) > 0
		if had_contact != bool(config["expect_contact"]):
			return false
	if config.has("expect_score"):
		return bool(snapshot.get("was_score", false)) == bool(config["expect_score"])
	return true


func _on_ui_aim_position_changed(position: Vector3) -> void:
	_set_aim_position(position)


func _on_ui_release_angle_changed(value: float) -> void:
	_release_angle_degrees = clampf(value, MIN_RELEASE_ANGLE_DEGREES, MAX_RELEASE_ANGLE_DEGREES)
	_update_launch_preview()
	_refresh_ui()


func _on_ui_aim_error_changed(value: float) -> void:
	_aim_error_radius = maxf(0.0, value)
	_update_launch_preview()
	_refresh_ui()


func _on_ui_angle_error_changed(value: float) -> void:
	_angle_error_degrees = maxf(0.0, value)
	_update_launch_preview()
	_refresh_ui()


func _on_ui_seed_changed(value: int) -> void:
	_seed = value
	_update_launch_preview()
	_refresh_ui()


func _on_ui_cup_toggled(cup_index: int) -> void:
	if _attempt_active:
		return
	if _active_cup_indices.has(cup_index):
		_active_cup_indices.erase(cup_index)
	else:
		_active_cup_indices.append(cup_index)
	_active_cup_indices.sort()
	_rebuild_rack()
	_reset_ball()
	_set_aim_position(_get_default_aim_position())


func _on_ui_test_shot_requested() -> void:
	_start_test_shot()


func _on_ui_repeat_shot_requested() -> void:
	_reset_ball()
	_start_test_shot()


func _on_ui_next_variation_requested() -> void:
	_seed += 1
	_reset_ball()
	_start_test_shot()


func _on_ui_reset_ball_requested() -> void:
	_reset_ball()
	_update_launch_preview()
	_refresh_ui()


func _on_ui_reset_rack_requested() -> void:
	_active_cup_indices.clear()
	for cup_index in range(MatchConstants.RACK_SIZE):
		_active_cup_indices.append(cup_index)
	_rebuild_rack()
	_reset_ball()
	_set_aim_position(_get_default_aim_position())


func _on_ui_export_log_requested() -> void:
	_export_status = (
		"Exported log to %s." % log_export_path
		if _log.export_to_path(log_export_path)
		else "Could not export log to %s." % log_export_path
	)
	_refresh_ui()


func _sanitize_cup_indices(values: Variant) -> Array[int]:
	var result: Array[int] = []
	var input: Array = values if values is Array else []
	for value in input:
		var cup_index := int(value)
		if cup_index < 0 or cup_index >= MatchConstants.RACK_SIZE or result.has(cup_index):
			continue
		result.append(cup_index)
	result.sort()
	return result


func _parse_vector3(text: String) -> Variant:
	var parts := text.split(",", false)
	if parts.size() != 3:
		return null
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))


func _parse_int_list(text: String) -> Array[int]:
	var result: Array[int] = []
	if text.strip_edges().is_empty():
		return result
	for part in text.split(",", false):
		var value := int(part.strip_edges())
		if not result.has(value):
			result.append(value)
	result.sort()
	return result


func _parse_bool(text: String) -> bool:
	var normalized := text.strip_edges().to_lower()
	return normalized == "true" or normalized == "1" or normalized == "yes" or normalized == "on"
