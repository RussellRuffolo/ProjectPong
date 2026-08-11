extends Node3D
class_name ShotTesterApp

const MatchConstants := preload("res://scripts/match/pong_match_constants.gd")
const ShotPhysicsScript := preload("res://scripts/match/shot_physics.gd")
const ShotAttemptEvaluatorScript := preload("res://scripts/match/shot_attempt_evaluator.gd")
const ShotContactTrackerScript := preload("res://scripts/house_rules/shot_contact_tracker.gd")
const ShotTesterBallLauncherScript := preload("res://scripts/editor/shot_tester/shot_tester_ball_launcher.gd")
const ShotTesterCollisionResponseScript := preload("res://scripts/editor/shot_tester/shot_tester_collision_response.gd")
const ShotTesterLogScript := preload("res://scripts/editor/shot_tester/shot_tester_log.gd")
const ShotTesterUiScript := preload("res://scripts/editor/shot_tester/shot_tester_ui.gd")
const ConicFrustumCollisionScript := preload("res://scripts/match/conic_frustum_collision.gd")

const ACTIVE_SLOT := MatchConstants.PLAYER_ONE_SLOT
const TARGET_SLOT := MatchConstants.PLAYER_TWO_SLOT
const ACTIVE_SIDE := &"shot_tester"
const TARGET_SIDE := &"target"
const MIN_RELEASE_ANGLE_DEGREES := 8.0
const MAX_RELEASE_ANGLE_DEGREES := 88.0

@export var cup_rack_root_path: NodePath
@export var ball_path: NodePath
@export var aim_indicator_path: NodePath
@export var camera_path: NodePath
@export var ui_root_path: NodePath
@export var cup_visual_scene: PackedScene
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
@export var default_release_angle_degrees := 42.0
@export var deterministic_seed := 20260809
@export var log_export_path := "user://shot_tester_log.txt"
@export var bottom_y := 0.006
@export var rim_y := 0.058
@export var bottom_radius := 0.030
@export var rim_radius := 0.046
@export_range(0.05, 2.0, 0.01) var rim_band_ball_radius_scale := 0.6
@export var testing_camera_focus := Vector3(0.0, 0.88, -1.56)
@export_range(0.05, 4.0, 0.05) var testing_camera_move_speed := 1.25
@export_range(0.05, 4.0, 0.05) var testing_camera_zoom_speed := 0.9
@export_range(0.001, 0.02, 0.001) var testing_camera_drag_sensitivity := 0.006

var _rack: Node3D
var _ball: RigidBody3D
var _aim_indicator: Node3D
var _testing_camera: Camera3D
var _ui_root: Control
var _ui = ShotTesterUiScript.new()
var _log = ShotTesterLogScript.new()
var _contact_tracker = ShotContactTrackerScript.new()

var _aim_position := Vector3.ZERO
var _release_angle_degrees := 42.0
var _aim_error_radius := 0.0
var _angle_error_degrees := 0.0
var _seed := 20260809
var _active_cup_indices: Array[int] = []
var _last_launch_plan: Dictionary = {}
var _last_collision: Dictionary = {}
var _export_status := ""

var _attempt_active := false
var _attempt_elapsed := 0.0
var _attempt_initial_conditions: Dictionary = {}
var _attempt_collision_events: Array[Dictionary] = []
var _attempt_collision_count := 0
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
	_configure_rack()
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
	if not _attempt_active:
		return

	_attempt_elapsed += delta
	_contact_tracker.update(_attempt_elapsed)
	var ball_settled := ShotPhysicsScript.is_ball_settled(_ball, settled_speed)
	var miss := ShotAttemptEvaluatorScript.is_miss(
		_ball,
		_attempt_elapsed,
		_get_attempt_bounds(),
		null,
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
		elif key_event.keycode == KEY_C and _rack != null:
			var rack_center: Variant = _rack.call("get_rack_center_position")
			if rack_center is Vector3:
				testing_camera_focus = rack_center
			_update_testing_camera_transform()


func apply_test_configuration(config: Dictionary) -> void:
	if config.has("seed"):
		_seed = int(config["seed"])
	if config.has("release_angle_degrees"):
		_release_angle_degrees = clampf(float(config["release_angle_degrees"]), MIN_RELEASE_ANGLE_DEGREES, MAX_RELEASE_ANGLE_DEGREES)
	if config.has("aim_error_radius"):
		_aim_error_radius = maxf(0.0, float(config["aim_error_radius"]))
	if config.has("angle_error_degrees"):
		_angle_error_degrees = maxf(0.0, float(config["angle_error_degrees"]))
	if config.has("active_cup_indices"):
		_active_cup_indices = _sanitize_cup_indices(config["active_cup_indices"])
		_configure_rack()
	if config.has("aim_position"):
		_set_aim_position(config["aim_position"] as Vector3)
	_reset_ball()
	_update_launch_preview()
	_refresh_ui()


func run_single_shot_test(config := {}) -> Dictionary:
	apply_test_configuration(config)
	_reset_ball()
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
		_resolve_attempt("frame_limit")

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
		"resolved_score": false,
		"was_score": false,
		"scored_cup_index": -1,
		"removed_cup_indices": [],
		"remaining_cup_indices": _active_cup_indices.duplicate(),
		"collision_count": int(result.get("collision_count", 0)),
		"collisions": event.get("collisions", []),
		"event": event,
		"failure_reason": str(event.get("failure_reason", "")),
	}


func _bind_scene_nodes() -> void:
	_rack = get_node_or_null(cup_rack_root_path) as Node3D
	_ball = get_node_or_null(ball_path) as RigidBody3D
	_aim_indicator = get_node_or_null(aim_indicator_path) as Node3D
	_testing_camera = get_node_or_null(camera_path) as Camera3D
	_ui_root = get_node_or_null(ui_root_path) as Control

	if _rack == null:
		push_error("[ShotTester] CupRackRoot is not configured.")
	else:
		_rack.connect("cup_ball_entered_frustum", Callable(self, "_on_cup_ball_entered_frustum"))
	if _ball == null:
		push_error("[ShotTester] SimulationBall is not configured.")
	elif _ball.has_method("set_grabbable"):
		_ball.call("set_grabbable", false)
	if _aim_indicator == null:
		push_error("[ShotTester] AimIndicator is not configured.")
	if _ui_root == null:
		push_warning("[ShotTester] UI root is not configured; headless shot tests can still run.")


func _reset_defaults() -> void:
	_release_angle_degrees = clampf(default_release_angle_degrees, MIN_RELEASE_ANGLE_DEGREES, MAX_RELEASE_ANGLE_DEGREES)
	_aim_error_radius = 0.0
	_angle_error_degrees = 0.0
	_seed = deterministic_seed
	_active_cup_indices.clear()
	for cup_index in range(MatchConstants.RACK_SIZE):
		_active_cup_indices.append(cup_index)


func _configure_rack() -> void:
	if _rack == null:
		return

	var half_length := table_length_meters * 0.5
	_rack.call("configure", cup_visual_scene, _ball, {
		"back_row_origin": Vector3(0.0, cup_height_y, table_center_z - half_length + rack_end_margin),
		"row_direction_z": 1.0,
		"cup_spacing": cup_spacing,
		"name_prefix": "ShotTesterCup",
		"owner_slot": TARGET_SLOT,
		"owner_side": TARGET_SIDE,
		"active_cup_indices": _active_cup_indices,
		"frustum_parameters": _get_frustum_parameters(),
	})


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

	_attempt_active = false
	_attempt_elapsed = 0.0
	_attempt_collision_events.clear()
	_attempt_collision_count = 0
	_last_collision.clear()
	_contact_tracker.start_attempt(_ball)
	if _rack != null:
		_rack.call("clear_sensor_states")

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
	_attempt_active = false
	_attempt_elapsed = 0.0
	_attempt_collision_events.clear()
	_attempt_collision_count = 0
	_last_collision.clear()
	_contact_tracker.clear()
	if _rack != null:
		_rack.call("clear_sensor_states")


func _resolve_attempt(resolve_reason: String) -> void:
	if not _attempt_active:
		return

	_contact_tracker.update(_attempt_elapsed)
	var contact_summary = _contact_tracker.stop_and_get_summary(_attempt_elapsed)
	_attempt_active = false
	var event := {
		"shot": _log.events.size() + 1,
		"seed": _seed,
		"initial_conditions": _attempt_initial_conditions.duplicate(true),
		"active_cup_indices": _active_cup_indices.duplicate(),
		"result": {
			"resolved_score": false,
			"was_score": false,
			"scored_cup_index": -1,
			"removed_cup_indices": [],
			"collision_count": _attempt_collision_count,
		},
		"collisions": _attempt_collision_events.duplicate(true),
		"contact_summary": contact_summary.to_dictionary(),
		"attempt_seconds": _attempt_elapsed,
		"ball_position": _ball.global_position if _ball != null else Vector3.ZERO,
		"resolve_reason": resolve_reason,
		"failure_reason": "",
	}
	_last_resolved_event = event.duplicate(true)
	_log.add_event(event)
	print("[ShotTester] %s" % _log.format_event_summary(event))
	_refresh_ui()


func _resolve_failed_start(reason: String) -> void:
	var event := {
		"shot": _log.events.size() + 1,
		"seed": _seed,
		"initial_conditions": _last_launch_plan.duplicate(true),
		"active_cup_indices": _active_cup_indices.duplicate(),
		"result": {
			"resolved_score": false,
			"was_score": false,
			"scored_cup_index": -1,
			"removed_cup_indices": [],
			"collision_count": 0,
		},
		"collisions": [],
		"contact_summary": {"contacts": []},
		"attempt_seconds": 0.0,
		"ball_position": _ball.global_position if _ball != null else Vector3.ZERO,
		"resolve_reason": "failed_start",
		"failure_reason": reason,
	}
	_last_resolved_event = event.duplicate(true)
	_log.add_event(event)
	push_warning("[ShotTester] %s" % reason)


func _on_cup_ball_entered_frustum(cup: Node3D, ball: RigidBody3D, collision_snapshot: Dictionary) -> void:
	if not _attempt_active or ball != _ball:
		return

	var response := ShotTesterCollisionResponseScript.apply_bounce(ball, cup, collision_snapshot, {})
	_attempt_collision_count += 1
	var collision_event := {
		"time_seconds": _attempt_elapsed,
		"cup_index": int(cup.get_meta("cup_index", -1)),
		"owner_slot": int(cup.get_meta("owner_slot", TARGET_SLOT)),
		"owner_side": StringName(str(cup.get_meta("owner_side", TARGET_SIDE))),
		"classification": str(collision_snapshot.get("classification", "")),
		"ball_local_position": collision_snapshot.get("ball_local_position", Vector3.ZERO),
		"nearest_local_point": collision_snapshot.get("nearest_local_point", Vector3.ZERO),
		"normal_local": collision_snapshot.get("normal_local", Vector3.UP),
		"response": response,
	}
	_attempt_collision_events.append(collision_event)
	_last_collision = collision_event.duplicate(true)
	_contact_tracker.update(_attempt_elapsed)
	_refresh_ui()


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
		"last_collision": _last_collision,
		"attempt_collision_count": _attempt_collision_count,
		"attempt_active": _attempt_active,
		"status_text": _get_status_text(),
		"export_status": _export_status,
		"events": _log.get_events(),
	})


func _get_status_text() -> String:
	if _attempt_active:
		return "Simulating %.2f s | collisions %d" % [_attempt_elapsed, _attempt_collision_count]
	var last_event := _log.get_last_event()
	if not last_event.is_empty():
		return _log.format_event_summary(last_event)
	return "Ready. Mathematical cup sensors are active."


func _set_aim_position(position: Vector3) -> void:
	_aim_position = position
	if _aim_indicator != null:
		_aim_indicator.global_position = _aim_position
	_update_launch_preview()
	_refresh_ui()


func _get_default_aim_position() -> Vector3:
	if _rack == null:
		return Vector3(0.0, cup_height_y + rim_y, table_center_z)
	var rack_center: Variant = _rack.call("get_rack_center_position")
	return rack_center if rack_center is Vector3 else Vector3(0.0, cup_height_y + rim_y, table_center_z)


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


func _get_frustum_parameters() -> Dictionary:
	return ConicFrustumCollisionScript.build_parameters({
		"bottom_y": bottom_y,
		"rim_y": rim_y,
		"bottom_radius": bottom_radius,
		"rim_radius": rim_radius,
		"rim_band_ball_radius_scale": rim_band_ball_radius_scale,
	})


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
		if event.pressed:
			_aim_dragging = _is_screen_position_near_aim(event.position)
			if _aim_dragging:
				get_viewport().set_input_as_handled()
		else:
			_aim_dragging = false


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _camera_dragging:
		_camera_yaw -= event.relative.x * testing_camera_drag_sensitivity
		_camera_pitch -= event.relative.y * testing_camera_drag_sensitivity
		_update_testing_camera_transform()
		get_viewport().set_input_as_handled()
		return

	if _aim_dragging:
		var position: Variant = _get_aim_drag_position(event.position)
		if position != null:
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

	var t := (_aim_position.y - ray_origin.y) / ray_direction.y
	if t < 0.0:
		return null
	var hit := ray_origin + ray_direction * t
	return Vector3(hit.x, _aim_position.y, hit.z)


func _try_run_cli_shot_test() -> bool:
	var user_args := OS.get_cmdline_user_args()
	if not user_args.has("--shot-test"):
		return false

	var config: Dictionary = {}
	for arg in user_args:
		if arg.begins_with("--shot-aim="):
			var parsed_aim: Variant = _parse_vector3(arg.trim_prefix("--shot-aim="))
			if parsed_aim != null:
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
		elif arg.begins_with("--shot-expect-collision="):
			config["expect_collision"] = _parse_bool(arg.trim_prefix("--shot-expect-collision="))
		elif arg.begins_with("--shot-expect-score="):
			config["expect_collision"] = _parse_bool(arg.trim_prefix("--shot-expect-score="))

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

	if config.has("expect_collision"):
		return (int(snapshot.get("collision_count", 0)) > 0) == bool(config["expect_collision"])
	return str(snapshot.get("failure_reason", "")).is_empty()


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
	if _rack != null:
		_rack.call("rebuild_with_active_indices", _active_cup_indices)
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
	if _rack != null:
		_rack.call("rebuild_with_active_indices", _active_cup_indices)
	_reset_ball()
	_set_aim_position(_get_default_aim_position())


func _on_ui_export_log_requested() -> void:
	_export_status = "Exported log to %s." % log_export_path if _log.export_to_path(log_export_path) else "Could not export log to %s." % log_export_path
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
