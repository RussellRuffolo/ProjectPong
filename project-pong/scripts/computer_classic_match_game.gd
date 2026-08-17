extends Node3D
class_name ComputerClassicMatchGame

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
const HouseRuleIdsScript := preload("res://scripts/house_rules/house_rule_ids.gd")
const HouseRulesProfileScript := preload("res://scripts/house_rules/house_rules_profile.gd")
const HouseRulesSettingsStoreScript := preload("res://scripts/house_rules/house_rules_settings_store.gd")
const ShotContextScript := preload("res://scripts/house_rules/shot_context.gd")
const ShotContactTrackerScript := preload("res://scripts/house_rules/shot_contact_tracker.gd")
const HouseRulesResolverScript := preload("res://scripts/house_rules/house_rules_resolver.gd")

const SIDE_ONE := MatchConstants.PLAYER_ONE_SLOT
const SIDE_TWO := MatchConstants.PLAYER_TWO_SLOT
const SIDE_ONE_ID := &"computer_one"
const SIDE_TWO_ID := &"computer_two"

@export var side_one_cup_parent_path: NodePath
@export var side_two_cup_parent_path: NodePath
@export var side_one_ball_path: NodePath
@export var side_two_ball_path: NodePath
@export var status_label_path: NodePath
@export var shot_log_label_path: NodePath
@export var next_shot_button_path: NodePath
@export var reset_match_button_path: NodePath
@export var export_log_button_path: NodePath
@export var shot_log_list_path: NodePath
@export var log_export_status_label_path: NodePath
@export var camera_path: NodePath
@export var table_center_z := -1.56
@export var table_length_meters := 2.7432
@export var rack_end_margin := 0.14
@export var cup_height_y := 0.78
@export var cup_spacing := 0.105
@export var shots_per_turn := 2
@export var ball_spawn_height := 1.18
@export var miss_height := 0.45
@export var out_of_bounds_x := 1.45
@export var out_of_bounds_padding_z := 0.45
@export var settled_speed := 0.08
@export var settled_after_seconds := 1.25
@export var max_attempt_seconds := 5.0
@export var reset_delay := 0.15
@export var scored_reset_delay := 0.25
@export var cup_remove_delay := 0.10
@export var captured_cup_remove_delay := 0.1
@export var computer_throw_arc_height := 0.42
@export var computer_aim_top_clearance := -0.10
@export var autoplay_on_ready := true
@export_range(0.1, 20.0, 0.1) var shots_per_second := 4.0
@export_range(1, 500, 1) var max_automatic_shots := 160
@export_range(60, 60000, 60) var max_automatic_physics_frames := 30000
@export_range(0.1, 4.0, 0.1) var automatic_test_time_scale := 1.0
@export_range(1, 20, 1) var automatic_min_resolved_shots := 4
@export_range(0, 10, 1) var automatic_min_scores := 1
@export var automatic_require_complete_match := false
@export var deterministic_seed := 20260808
@export_enum("saved_profile", "default_profile", "custom_list") var house_rules_source := "custom_list"
@export var custom_enabled_house_rules := PackedStringArray([
	"bouncing",
	"chain_lightning",
])
@export var side_one_computer_player_profile: Resource
@export var side_two_computer_player_profile: Resource
@export_enum("most_central", "closest") var side_one_target_heuristic := "most_central"
@export_enum("most_central", "closest") var side_two_target_heuristic := "most_central"
@export_range(0.0, 0.35, 0.005) var side_one_accuracy_error_radius := 0.025
@export_range(0.0, 0.35, 0.005) var side_two_accuracy_error_radius := 0.035
@export var hide_removed_cups := true
@export var log_export_path := "user://computer_classic_match_shot_log.txt"
@export var testing_camera_focus := Vector3(0.0, 0.82, -1.56)
@export_range(0.05, 4.0, 0.05) var testing_camera_move_speed := 1.25
@export_range(0.05, 4.0, 0.05) var testing_camera_zoom_speed := 0.9
@export_range(0.001, 0.02, 0.001) var testing_camera_drag_sensitivity := 0.006

var _side_one_cup_parent: Node3D
var _side_two_cup_parent: Node3D
var _side_one_ball: ThrowableBall
var _side_two_ball: ThrowableBall
var _status_label: Label3D
var _shot_log_label: Label3D
var _next_shot_button: Button
var _reset_match_button: Button
var _export_log_button: Button
var _shot_log_list: VBoxContainer
var _log_export_status_label: Label
var _testing_camera: Camera3D
var _ball_by_slot: Dictionary = {}
var _rack_state_by_slot: Dictionary = {}
var _match_model = ClassicMatchModelScript.new()
var _house_rules_profile
var _house_rules_profile_override = null
var _profile_by_slot: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _shot_countdown := 0.0
var _shots_simulated := 0
var _shot_log: Array[Dictionary] = []
var _initialized := false
var _attempt_active := false
var _attempt_elapsed := 0.0
var _attempt_active_slot := 0
var _attempt_target_slot := 0
var _attempt_target_cup_index := -1
var _attempt_launch_velocity := Vector3.ZERO
var _attempt_throw_plan: Dictionary = {}
var _attempt_ball: ThrowableBall
var _score_tracker := ShotScoreTrackerScript.new()
var _contact_tracker := ShotContactTrackerScript.new()
var _pending_cup_removals := CupRemovalQueueScript.new()
var _last_resolved_event: Dictionary = {}
var _cli_auto_test_running := false
var _manual_shot_requested := false
var _camera_dragging := false
var _camera_yaw := 0.0
var _camera_pitch := 0.0
var _camera_distance := 3.45


func _ready() -> void:
	if OS.has_feature("template"):
		push_warning("[ComputerClassicMatch] Editor-only simulation scene is disabled in exported builds.")
		set_physics_process(false)
		return

	_initialize_if_needed()
	if _try_run_cli_automatic_test():
		set_physics_process(false)
		return

	set_process(_testing_camera != null)
	set_physics_process(autoplay_on_ready)


func _process(delta: float) -> void:
	if _testing_camera == null or _cli_auto_test_running:
		return

	_update_testing_camera_input(delta)


func _physics_process(delta: float) -> void:
	if not _initialized:
		return

	_update_pending_cup_removals(delta)
	if _attempt_active or autoplay_on_ready or _cli_auto_test_running or _manual_shot_requested:
		_update_physical_simulation(delta, autoplay_on_ready or _cli_auto_test_running or _manual_shot_requested)


func _unhandled_input(event: InputEvent) -> void:
	if _testing_camera == null or _cli_auto_test_running:
		return

	var mouse_button := event as InputEventMouseButton
	if mouse_button != null:
		if mouse_button.button_index == MOUSE_BUTTON_RIGHT:
			_camera_dragging = mouse_button.pressed
			get_viewport().set_input_as_handled()
		elif mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera_distance = maxf(1.0, _camera_distance - testing_camera_zoom_speed * 0.2)
			_apply_testing_camera_transform()
			get_viewport().set_input_as_handled()
		elif mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera_distance = minf(7.0, _camera_distance + testing_camera_zoom_speed * 0.2)
			_apply_testing_camera_transform()
			get_viewport().set_input_as_handled()
		return

	var mouse_motion := event as InputEventMouseMotion
	if mouse_motion != null and _camera_dragging:
		_camera_yaw -= mouse_motion.relative.x * testing_camera_drag_sensitivity
		_camera_pitch = clampf(_camera_pitch - mouse_motion.relative.y * testing_camera_drag_sensitivity, deg_to_rad(8.0), deg_to_rad(78.0))
		_apply_testing_camera_transform()
		get_viewport().set_input_as_handled()


func reset_simulation(seed_override := -1) -> void:
	_initialize_if_needed()
	if not _initialized:
		return

	_rng.seed = deterministic_seed if int(seed_override) < 0 else int(seed_override)
	_shot_countdown = 0.0
	_shots_simulated = 0
	_shot_log.clear()
	_last_resolved_event.clear()
	_manual_shot_requested = false
	_attempt_active = false
	_attempt_elapsed = 0.0
	_attempt_active_slot = 0
	_attempt_target_slot = 0
	_attempt_target_cup_index = -1
	_attempt_launch_velocity = Vector3.ZERO
	_attempt_throw_plan.clear()
	_attempt_ball = null
	_score_tracker.reset()
	_contact_tracker.clear()
	_pending_cup_removals.clear()
	_house_rules_profile = _build_house_rules_profile()
	_profile_by_slot = {
		SIDE_ONE: _build_computer_profile(SIDE_ONE),
		SIDE_TWO: _build_computer_profile(SIDE_TWO),
	}
	_match_model.configure({
		"shots_per_turn": shots_per_turn,
		"rack_size": MatchConstants.RACK_SIZE,
	})
	_build_starting_racks()
	_match_model.reset_for_match(SIDE_ONE)
	_reset_all_balls()
	_update_labels()
	_refresh_log_list()
	print("[ComputerClassicMatch] Reset physical simulation with ruleset %s." % _house_rules_profile.get_compact_ruleset_id())


func step_simulation(delta := 1.0 / 60.0) -> Dictionary:
	_initialize_if_needed()
	if not _initialized or _match_model.match_phase != ClassicMatchModelScript.PHASE_PLAYING:
		return get_test_snapshot()

	var previous_shot_count := _shots_simulated
	_update_pending_cup_removals(delta)
	_update_physical_simulation(delta, true)
	if _shots_simulated > previous_shot_count:
		return _last_resolved_event.duplicate(true)
	return get_test_snapshot()


func run_automatic_test(config: Dictionary = {}) -> Dictionary:
	apply_test_configuration(config)
	_cli_auto_test_running = true
	reset_simulation(int(config.get("seed", deterministic_seed)))

	var shot_limit := maxi(1, int(config.get("max_shots", max_automatic_shots)))
	var frame_limit := maxi(1, int(config.get("max_physics_frames", max_automatic_physics_frames)))
	var min_resolved_shots := maxi(1, int(config.get("min_resolved_shots", automatic_min_resolved_shots)))
	var min_scores := maxi(0, int(config.get("min_scores", automatic_min_scores)))
	var require_complete := bool(config.get("require_complete", automatic_require_complete_match))
	var previous_time_scale := Engine.time_scale
	var frames_simulated := 0

	set_physics_process(true)
	Engine.time_scale = maxf(0.1, float(config.get("time_scale", automatic_test_time_scale)))
	while (
		_match_model.match_phase == ClassicMatchModelScript.PHASE_PLAYING
		and _shots_simulated < shot_limit
		and frames_simulated < frame_limit
		and not _is_automatic_success_ready(require_complete, min_resolved_shots, min_scores)
	):
		await get_tree().physics_frame
		frames_simulated += 1

	Engine.time_scale = previous_time_scale
	_cli_auto_test_running = false
	set_physics_process(autoplay_on_ready)

	var snapshot := get_test_snapshot()
	var passed := (
		_is_test_snapshot_consistent(snapshot)
		and _shots_simulated >= min_resolved_shots
		and _get_resolved_score_count() >= min_scores
		and (not require_complete or _match_model.is_complete())
	)
	snapshot["passed"] = passed
	snapshot["physics_frames_simulated"] = frames_simulated
	snapshot["required_complete_match"] = require_complete
	snapshot["required_resolved_shots"] = min_resolved_shots
	snapshot["required_scores"] = min_scores
	snapshot["resolved_score_events"] = _get_resolved_score_count()
	snapshot["failure_reason"] = "" if passed else _get_failure_reason(snapshot, shot_limit, frame_limit, min_resolved_shots, min_scores, require_complete)
	return snapshot


func run_direct_zero_error_test(config: Dictionary = {}) -> Dictionary:
	var run_config := config.duplicate(true)
	run_config.erase("direct_zero_test")
	run_config["max_shots"] = int(run_config.get("max_shots", 24))
	run_config["max_physics_frames"] = int(run_config.get("max_physics_frames", 12000))
	run_config["min_resolved_shots"] = int(run_config.get("min_resolved_shots", 6))
	run_config["min_scores"] = int(run_config.get("min_scores", 6))
	run_config["require_complete"] = bool(run_config.get("require_complete", false))

	side_one_computer_player_profile = _build_direct_zero_error_profile(SIDE_ONE)
	side_two_computer_player_profile = _build_direct_zero_error_profile(SIDE_TWO)
	_house_rules_profile_override = _build_disabled_house_rules_profile()

	var result := await run_automatic_test(run_config)
	result["direct_zero_error_test"] = true
	result["expected_behavior"] = "Zero direct aim and angle error should produce repeatable scoring shots."
	return result


func run_seeded_profile_smoke_test(config: Dictionary = {}) -> Dictionary:
	var profile_ids: Array[String] = [
		"rookie_arc",
		"steady_classic",
		"line_drive",
		"bounce_artist",
		"chaotic_party",
	]
	var results: Array[Dictionary] = []
	var all_passed := true
	var base_seed := int(config.get("seed", deterministic_seed))

	for index in range(profile_ids.size()):
		var profile = _load_computer_profile(profile_ids[index])
		side_one_computer_player_profile = profile
		side_two_computer_player_profile = profile

		var run_config := config.duplicate(true)
		run_config.erase("profile_smoke_test")
		run_config.erase("side_one_profile")
		run_config.erase("side_two_profile")
		run_config["seed"] = base_seed + index
		run_config["max_shots"] = int(run_config.get("max_shots", 20))
		run_config["max_physics_frames"] = int(run_config.get("max_physics_frames", 9000))
		run_config["min_resolved_shots"] = int(run_config.get("min_resolved_shots", 3))
		run_config["min_scores"] = int(run_config.get("min_scores", 0))
		run_config["require_complete"] = false

		var result := await run_automatic_test(run_config)
		result["profile_id"] = profile_ids[index]
		results.append(result)
		all_passed = all_passed and bool(result.get("passed", false))

	return {
		"passed": all_passed,
		"profile_smoke_test": true,
		"profile_count": profile_ids.size(),
		"results": results,
	}


func run_bounce_shot_validation(config: Dictionary = {}) -> Dictionary:
	var run_config := config.duplicate(true)
	run_config.erase("bounce_smoke_test")
	run_config["max_shots"] = int(run_config.get("max_shots", 6))
	run_config["max_physics_frames"] = int(run_config.get("max_physics_frames", 9000))
	run_config["min_resolved_shots"] = int(run_config.get("min_resolved_shots", 2))
	run_config["min_scores"] = int(run_config.get("min_scores", 0))
	run_config["require_complete"] = false

	side_one_computer_player_profile = _build_bounce_validation_profile()
	side_two_computer_player_profile = _build_bounce_validation_profile()
	_house_rules_profile_override = _build_disabled_house_rules_profile()
	var disabled_result := await run_automatic_test(run_config)
	var disabled_attempts := _count_bounce_attempts(disabled_result)

	side_one_computer_player_profile = _build_bounce_validation_profile()
	side_two_computer_player_profile = _build_bounce_validation_profile()
	_house_rules_profile_override = _build_bouncing_only_house_rules_profile()
	var enabled_result := await run_automatic_test(run_config)
	var enabled_attempts := _count_bounce_attempts(enabled_result)
	var enabled_plans := _count_bounce_plans(enabled_result)

	var passed := (
		bool(disabled_result.get("passed", false))
		and bool(enabled_result.get("passed", false))
		and disabled_attempts == 0
		and enabled_attempts > 0
		and enabled_plans > 0
	)
	return {
		"passed": passed,
		"bounce_smoke_test": true,
		"disabled_bounce_attempts": disabled_attempts,
		"enabled_bounce_attempts": enabled_attempts,
		"enabled_bounce_plans": enabled_plans,
		"disabled_result": disabled_result,
		"enabled_result": enabled_result,
		"failure_reason": "" if passed else "Bounce gating or bounce planning did not meet expectations.",
	}


func _try_run_cli_automatic_test() -> bool:
	var user_args := OS.get_cmdline_user_args()
	if not user_args.has("--codex-auto-test"):
		return false

	var config: Dictionary = {}
	for arg in user_args:
		if arg == "--codex-direct-zero-test":
			config["direct_zero_test"] = true
		elif arg == "--codex-profile-smoke-test":
			config["profile_smoke_test"] = true
		elif arg == "--codex-bounce-smoke-test":
			config["bounce_smoke_test"] = true
		elif arg.begins_with("--codex-seed="):
			config["seed"] = int(arg.trim_prefix("--codex-seed="))
		elif arg.begins_with("--codex-max-shots="):
			config["max_shots"] = int(arg.trim_prefix("--codex-max-shots="))
		elif arg.begins_with("--codex-max-physics-frames="):
			config["max_physics_frames"] = int(arg.trim_prefix("--codex-max-physics-frames="))
		elif arg.begins_with("--codex-min-resolved-shots="):
			config["min_resolved_shots"] = int(arg.trim_prefix("--codex-min-resolved-shots="))
		elif arg.begins_with("--codex-min-scores="):
			config["min_scores"] = int(arg.trim_prefix("--codex-min-scores="))
		elif arg.begins_with("--codex-side-one-profile="):
			config["side_one_profile"] = arg.trim_prefix("--codex-side-one-profile=")
		elif arg.begins_with("--codex-side-two-profile="):
			config["side_two_profile"] = arg.trim_prefix("--codex-side-two-profile=")
		elif arg == "--codex-require-complete":
			config["require_complete"] = true

	call_deferred("_run_cli_automatic_test", config)
	return true


func _run_cli_automatic_test(config: Dictionary) -> void:
	var result: Dictionary
	if bool(config.get("direct_zero_test", false)):
		result = await run_direct_zero_error_test(config)
	elif bool(config.get("profile_smoke_test", false)):
		result = await run_seeded_profile_smoke_test(config)
	elif bool(config.get("bounce_smoke_test", false)):
		result = await run_bounce_shot_validation(config)
	else:
		result = await run_automatic_test(config)
	print("[ComputerClassicMatchAutoTest] %s" % JSON.stringify(result))
	get_tree().quit(0 if bool(result.get("passed", false)) else 1)


func apply_test_configuration(config: Dictionary) -> void:
	if config.has("max_shots"):
		max_automatic_shots = max(1, int(config["max_shots"]))
	if config.has("max_physics_frames"):
		max_automatic_physics_frames = max(1, int(config["max_physics_frames"]))
	if config.has("min_resolved_shots"):
		automatic_min_resolved_shots = max(1, int(config["min_resolved_shots"]))
	if config.has("min_scores"):
		automatic_min_scores = max(0, int(config["min_scores"]))
	if config.has("require_complete"):
		automatic_require_complete_match = bool(config["require_complete"])
	if config.has("seed"):
		deterministic_seed = int(config["seed"])
	if config.has("side_one_target_heuristic"):
		side_one_target_heuristic = str(config["side_one_target_heuristic"])
	if config.has("side_two_target_heuristic"):
		side_two_target_heuristic = str(config["side_two_target_heuristic"])
	if config.has("side_one_profile"):
		side_one_computer_player_profile = _load_computer_profile(str(config["side_one_profile"]))
	if config.has("side_two_profile"):
		side_two_computer_player_profile = _load_computer_profile(str(config["side_two_profile"]))
	if config.has("side_one_accuracy_error_radius"):
		side_one_accuracy_error_radius = maxf(0.0, float(config["side_one_accuracy_error_radius"]))
	if config.has("side_two_accuracy_error_radius"):
		side_two_accuracy_error_radius = maxf(0.0, float(config["side_two_accuracy_error_radius"]))
	if config.has("time_scale"):
		automatic_test_time_scale = maxf(0.1, float(config["time_scale"]))
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
	snapshot["attempt_active"] = _attempt_active
	snapshot["attempt_elapsed"] = _attempt_elapsed
	snapshot["ruleset_id"] = _house_rules_profile.get_compact_ruleset_id() if _house_rules_profile != null else ""
	snapshot["house_rules"] = _house_rules_profile.to_dictionary() if _house_rules_profile != null else {}
	snapshot["remaining_by_slot"] = {
		SIDE_ONE: _match_model.get_remaining_count(SIDE_ONE),
		SIDE_TWO: _match_model.get_remaining_count(SIDE_TWO),
	}
	snapshot["computer_profiles"] = {
		SIDE_ONE: _get_profile_id(SIDE_ONE),
		SIDE_TWO: _get_profile_id(SIDE_TWO),
	}
	snapshot["state_consistent"] = _is_test_snapshot_consistent(snapshot)
	snapshot["shot_log"] = _shot_log.duplicate(true)
	snapshot["last_resolved_event"] = _last_resolved_event.duplicate(true)
	return snapshot


func _initialize_if_needed() -> void:
	if _initialized:
		return

	_side_one_cup_parent = get_node_or_null(side_one_cup_parent_path) as Node3D
	_side_two_cup_parent = get_node_or_null(side_two_cup_parent_path) as Node3D
	_side_one_ball = get_node_or_null(side_one_ball_path) as ThrowableBall
	_side_two_ball = get_node_or_null(side_two_ball_path) as ThrowableBall
	_status_label = get_node_or_null(status_label_path) as Label3D
	_shot_log_label = get_node_or_null(shot_log_label_path) as Label3D
	_next_shot_button = get_node_or_null(next_shot_button_path) as Button
	_reset_match_button = get_node_or_null(reset_match_button_path) as Button
	_export_log_button = get_node_or_null(export_log_button_path) as Button
	_shot_log_list = get_node_or_null(shot_log_list_path) as VBoxContainer
	_log_export_status_label = get_node_or_null(log_export_status_label_path) as Label
	_testing_camera = get_node_or_null(camera_path) as Camera3D
	if _side_one_cup_parent == null or _side_two_cup_parent == null:
		push_error("[ComputerClassicMatch] Cup rack parents are required.")
		return
	if _side_one_ball == null and _side_two_ball == null:
		push_error("[ComputerClassicMatch] At least one ThrowableBall is required.")
		return

	_ball_by_slot = {
		SIDE_ONE: _side_one_ball if _side_one_ball != null else _side_two_ball,
		SIDE_TWO: _side_two_ball if _side_two_ball != null else _side_one_ball,
	}
	_configure_balls()
	_configure_testing_ui()
	_initialize_testing_camera()

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
		"back_row_origin": Vector3(0.0, cup_height_y, side_one_back_row_z),
		"row_direction_z": -1.0,
		"cup_spacing": cup_spacing,
		"name_prefix": "ComputerOneCup",
		"owner_slot": SIDE_ONE,
		"owner_side": SIDE_ONE_ID,
	})
	var side_two_cups := CupRackBuilderScript.build_triangular_rack(_side_two_cup_parent, {
		"back_row_origin": Vector3(0.0, cup_height_y, side_two_back_row_z),
		"row_direction_z": 1.0,
		"cup_spacing": cup_spacing,
		"name_prefix": "ComputerTwoCup",
		"owner_slot": SIDE_TWO,
		"owner_side": SIDE_TWO_ID,
	})
	_get_rack_state(SIDE_ONE).configure(side_one_cups, SIDE_ONE, SIDE_ONE_ID)
	_get_rack_state(SIDE_TWO).configure(side_two_cups, SIDE_TWO, SIDE_TWO_ID)
	_add_cup_index_labels(side_one_cups)
	_add_cup_index_labels(side_two_cups)


func _configure_testing_ui() -> void:
	if _next_shot_button != null:
		_next_shot_button.pressed.connect(_on_next_shot_pressed)
	if _reset_match_button != null:
		_reset_match_button.pressed.connect(_on_reset_match_pressed)
	if _export_log_button != null:
		_export_log_button.pressed.connect(_on_export_log_pressed)
	if _log_export_status_label != null:
		_log_export_status_label.text = ""


func _initialize_testing_camera() -> void:
	if _testing_camera == null:
		return

	var offset := _testing_camera.global_position - testing_camera_focus
	_camera_distance = clampf(offset.length(), 1.0, 7.0)
	if _camera_distance <= 0.001:
		_camera_distance = 3.45
	_camera_yaw = atan2(offset.x, offset.z)
	_camera_pitch = clampf(asin(clampf(offset.y / _camera_distance, -1.0, 1.0)), deg_to_rad(8.0), deg_to_rad(78.0))
	_apply_testing_camera_transform()


func _add_cup_index_labels(cups: Array[Node3D]) -> void:
	for cup in cups:
		if cup == null or not is_instance_valid(cup):
			continue

		var label := Label3D.new()
		label.name = "CupIndexLabel"
		label.text = str(_get_cup_index(cup))
		label.position = Vector3(0.0, 0.135, 0.0)
		label.pixel_size = 0.0018
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color(1.0, 0.94, 0.28, 1.0)
		label.outline_modulate = Color(0.02, 0.02, 0.02, 1.0)
		label.outline_size = 10
		cup.add_child(label)


func _on_next_shot_pressed() -> void:
	_initialize_if_needed()
	if not _initialized or _attempt_active or _match_model.match_phase != ClassicMatchModelScript.PHASE_PLAYING:
		_update_labels()
		return

	_manual_shot_requested = true
	_shot_countdown = 0.0
	set_physics_process(true)
	_update_labels()


func _on_reset_match_pressed() -> void:
	reset_simulation(deterministic_seed)
	set_physics_process(autoplay_on_ready)


func _on_export_log_pressed() -> void:
	var file := FileAccess.open(log_export_path, FileAccess.WRITE)
	if file == null:
		if _log_export_status_label != null:
			_log_export_status_label.text = "Export failed: %s" % error_string(FileAccess.get_open_error())
		return

	file.store_string(_build_log_export_text())
	file.close()
	var absolute_path := ProjectSettings.globalize_path(log_export_path)
	if _log_export_status_label != null:
		_log_export_status_label.text = "Exported %d shots to %s" % [_shot_log.size(), absolute_path]
	print("[ComputerClassicMatch] Exported shot log to %s." % absolute_path)


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


func _build_computer_profile(slot: int):
	var source_profile = side_one_computer_player_profile if slot == SIDE_ONE else side_two_computer_player_profile
	if source_profile != null:
		return source_profile.duplicate_profile()

	var profile = ComputerPlayerProfileScript.default_profile().duplicate_profile()
	profile.target_heuristic = _get_target_heuristic(slot)
	profile.direct_aim_error_radius = _get_accuracy_error_radius(slot)
	if is_zero_approx(profile.direct_aim_error_radius):
		profile.target_heuristic = "front_cup"
		profile.direct_release_angle_degrees = 88.0
		profile.direct_angle_error_degrees = 0.0
	return profile


func _build_direct_zero_error_profile(slot: int):
	var profile = ComputerPlayerProfileScript.default_profile().duplicate_profile()
	profile.profile_id = &"direct_zero_error"
	profile.display_name = "Direct Zero Error"
	profile.target_heuristic = "front_cup"
	profile.direct_release_angle_degrees = 88.0
	profile.direct_aim_error_radius = 0.0
	profile.direct_angle_error_degrees = 0.0
	profile.bounce_propensity = 0.0
	return profile


func _build_bounce_validation_profile():
	var profile = _load_computer_profile("bounce_artist")
	if profile == null:
		profile = ComputerPlayerProfileScript.default_profile()
	profile = profile.duplicate_profile()
	profile.profile_id = &"bounce_validation"
	profile.display_name = "Bounce Validation"
	profile.target_heuristic = "most_central"
	profile.direct_aim_error_radius = 0.0
	profile.direct_angle_error_degrees = 0.0
	profile.bounce_propensity = 1.0
	profile.bounce_aim_error_radius = 0.0
	profile.bounce_angle_error_degrees = 0.0
	return profile


func _build_disabled_house_rules_profile():
	var profile = HouseRulesProfileScript.default_profile()
	for rule_id in HouseRuleIdsScript.all():
		profile.set_enabled(rule_id, false)
	return profile


func _build_bouncing_only_house_rules_profile():
	var profile = _build_disabled_house_rules_profile()
	profile.set_enabled(HouseRuleIdsScript.BOUNCING, true)
	return profile


func _get_computer_profile(slot: int):
	var profile = _profile_by_slot.get(slot, null)
	if profile != null:
		return profile
	return ComputerPlayerProfileScript.default_profile()


func _get_profile_id(slot: int) -> String:
	var profile = _get_computer_profile(slot)
	return profile.get_profile_id_string() if profile != null else ""


func _load_computer_profile(profile_value: String):
	var profile_path := profile_value.strip_edges()
	if profile_path.is_empty():
		return null
	if not profile_path.begins_with("res://"):
		if not profile_path.ends_with(".tres"):
			profile_path += ".tres"
		profile_path = "res://resources/computer_players/%s" % profile_path

	var loaded_profile = load(profile_path)
	if loaded_profile == null:
		push_warning("[ComputerClassicMatch] Could not load computer profile %s." % profile_path)
	return loaded_profile


func _update_physical_simulation(delta: float, allow_new_attempt := true) -> void:
	if _match_model.is_complete() or _shots_simulated >= max_automatic_shots:
		_update_labels()
		set_physics_process(_cli_auto_test_running)
		return

	if _attempt_active:
		_update_active_attempt(delta)
		return

	if not allow_new_attempt:
		return

	_shot_countdown -= delta
	if _shot_countdown > 0.0:
		return

	if _begin_physical_attempt():
		_manual_shot_requested = false
	else:
		_manual_shot_requested = false


func _begin_physical_attempt() -> bool:
	if _match_model.match_phase != ClassicMatchModelScript.PHASE_PLAYING:
		return false

	var active_slot: int = int(_match_model.active_slot)
	var target_slot: int = _match_model.get_opponent_slot(active_slot)
	var target_rack_state = _get_rack_state(target_slot)
	var ball := _get_ball(active_slot)
	if target_rack_state == null or ball == null:
		return false

	var throw_transform := _get_ball_spawn_transform(active_slot)
	var throw_plan := ComputerThrowPlannerScript.build_throw_plan({
		"profile": _get_computer_profile(active_slot),
		"target_rack_state": target_rack_state,
		"ball": ball,
		"launch_transform": throw_transform,
		"rng": _rng,
		"house_rules_profile": _house_rules_profile,
		"attempt_bounds": _get_attempt_bounds(),
		"table_bounds": _get_table_bounds(),
	})
	if not bool(throw_plan.get("success", false)):
		return false

	var target_cup := throw_plan.get("target_cup", null) as Node3D
	var launch_velocity: Vector3 = throw_plan.get("launch_velocity", Vector3.ZERO)

	_attempt_active = true
	_attempt_elapsed = 0.0
	_attempt_active_slot = active_slot
	_attempt_target_slot = target_slot
	_attempt_target_cup_index = int(throw_plan.get("target_cup_index", _get_cup_index(target_cup)))
	_attempt_launch_velocity = launch_velocity
	_attempt_throw_plan = _serialize_throw_plan(throw_plan)
	_attempt_ball = ball
	_score_tracker.reset()
	_contact_tracker.clear()
	_reset_inactive_balls(active_slot)
	ComputerThrowPhysicsScript.launch_ball(ball, throw_transform, launch_velocity)
	_contact_tracker.start_attempt(ball)
	_update_labels()
	print("[ComputerClassicMatch] %s profile %s threw a %s shot at cup %d with velocity %s." % [
		_format_slot(active_slot),
		str(throw_plan.get("profile_id", "")),
		str(throw_plan.get("shot_type", "direct")),
		_attempt_target_cup_index,
		launch_velocity,
	])
	return true


func _update_active_attempt(delta: float) -> void:
	_attempt_elapsed += delta
	_contact_tracker.update(_attempt_elapsed)

	var target_rack_state = _get_rack_state(_attempt_target_slot)
	if _try_confirm_score(target_rack_state):
		return

	if _is_miss(target_rack_state):
		_resolve_physical_attempt(false, null)


func _try_confirm_score(target_rack_state) -> bool:
	if target_rack_state == null:
		return false

	var contact_candidate: Node3D = target_rack_state.find_score_contact_candidate(_attempt_ball)
	var confirmed_cup: Node3D = _score_tracker.confirm_contact_candidate(contact_candidate)
	if confirmed_cup == null:
		return false

	_resolve_physical_attempt(true, confirmed_cup)
	return true


func _resolve_physical_attempt(was_score: bool, scored_cup: Node3D) -> Dictionary:
	if not _attempt_active:
		return {}

	var active_slot := _attempt_active_slot
	var target_slot := _attempt_target_slot
	var target_rack_state = _get_rack_state(target_slot)
	var valid_score := was_score and _is_valid_scored_cup(scored_cup, target_rack_state, target_slot)
	var contact_summary = _contact_tracker.stop_and_get_summary(_attempt_elapsed)
	var context = _build_shot_context(active_slot, target_slot, target_rack_state, contact_summary, _attempt_ball)
	var outcome := HouseRulesResolverScript.resolve_attempt(
		context,
		valid_score,
		scored_cup if valid_score else null,
		scored_reset_delay if valid_score else reset_delay,
		0
	)
	var transition := _match_model.apply_shot_outcome(active_slot, target_slot, outcome)
	if bool(transition.get("resolved_score", false)) and _attempt_ball != null:
		_attempt_ball.begin_score_capture(scored_cup)
	_apply_removed_cup_indices(target_slot, transition.get("new_removed_cup_indices", []), scored_cup if valid_score else null)
	_shots_simulated += 1
	var removed_cup_indices := _read_int_array(transition.get("new_removed_cup_indices", []))
	var scored_cup_index := _get_cup_index(scored_cup) if valid_score else -1
	var hit_cups := _get_hit_cup_events(contact_summary)
	var removed_cup_causes := _build_removed_cup_causes(scored_cup_index, removed_cup_indices, outcome)
	var extra_removed_cups := _get_extra_removed_cup_causes(scored_cup_index, removed_cup_causes)
	var initial_conditions := _build_initial_conditions(active_slot, target_slot)
	var result := {
		"hit_cups": hit_cups,
		"was_score": valid_score,
		"resolved_score": bool(transition.get("resolved_score", false)),
		"scored_cup_index": scored_cup_index,
		"new_removed_cup_indices": removed_cup_indices,
		"removed_cup_causes": removed_cup_causes,
		"extra_removed_cups": extra_removed_cups,
	}

	var event := {
		"shot": _shots_simulated,
		"active_slot": active_slot,
		"target_slot": target_slot,
		"target_cup_index": _attempt_target_cup_index,
		"player": _format_slot(active_slot),
		"target_player": _format_slot(target_slot),
		"scored_cup_index": scored_cup_index,
		"was_score": valid_score,
		"resolved_score": bool(transition.get("resolved_score", false)),
		"new_removed_cup_indices": removed_cup_indices,
		"hit_cups": hit_cups,
		"removed_cup_causes": removed_cup_causes,
		"extra_removed_cups": extra_removed_cups,
		"initial_conditions": initial_conditions,
		"result": result,
		"rule_triggers": outcome.get("rule_triggers", []),
		"turn_advanced": bool(transition.get("turn_advanced", false)),
		"phase": str(transition.get("phase", "")),
		"winner_slot": int(transition.get("winner_slot", 0)),
		"attempt_seconds": _attempt_elapsed,
		"launch_velocity": _attempt_launch_velocity,
		"ball_position": _attempt_ball.global_position if _attempt_ball != null and is_instance_valid(_attempt_ball) else Vector3.ZERO,
		"throw_plan": _attempt_throw_plan.duplicate(true),
		"contact_summary": contact_summary.to_dictionary(),
	}
	_shot_log.append(event)
	_last_resolved_event = event.duplicate(true)

	_attempt_active = false
	_attempt_elapsed = 0.0
	_attempt_active_slot = 0
	_attempt_target_slot = 0
	_attempt_target_cup_index = -1
	_attempt_launch_velocity = Vector3.ZERO
	_attempt_throw_plan.clear()
	_attempt_ball = null
	_score_tracker.reset()
	_contact_tracker.clear()
	_shot_countdown = maxf(1.0 / maxf(0.1, shots_per_second), cup_remove_delay)

	_update_labels()
	_refresh_log_list()
	print("[ComputerClassicMatch] %s" % _format_event_summary(event))
	return event


func _build_shot_context(active_slot: int, target_slot: int, target_rack_state, contact_summary, ball: ThrowableBall):
	var context = ShotContextScript.new()
	context.mode_id = &"computer_classic_match"
	context.active_side = _get_side_id(active_slot)
	context.opponent_side = _get_side_id(target_slot)
	context.active_player_id = active_slot
	context.opponent_player_id = target_slot
	context.active_slot = active_slot
	context.target_slot = target_slot
	context.ball = ball
	context.target_rack_state = target_rack_state
	context.rules_profile = _house_rules_profile
	context.contact_summary = contact_summary
	context.normal_shots_taken = _match_model.shots_taken_this_turn + 1
	context.normal_shots_per_turn = shots_per_turn
	return context


func _build_initial_conditions(active_slot: int, target_slot: int) -> Dictionary:
	var throw_transform := _get_ball_spawn_transform(active_slot)
	return {
		"player": _format_slot(active_slot),
		"active_slot": active_slot,
		"target_player": _format_slot(target_slot),
		"target_slot": target_slot,
		"target_cup_index": _attempt_target_cup_index,
		"profile_id": str(_attempt_throw_plan.get("profile_id", "")),
		"profile_display_name": str(_attempt_throw_plan.get("display_name", "")),
		"shot_type": str(_attempt_throw_plan.get("shot_type", "direct")),
		"spawn_position": throw_transform.origin,
		"launch_velocity": _attempt_launch_velocity,
		"release_angle_degrees": float(_attempt_throw_plan.get("release_angle_degrees", 0.0)),
		"target_position": _attempt_throw_plan.get("target_position", Vector3.ZERO),
		"aim_position": _attempt_throw_plan.get("aim_position", Vector3.ZERO),
		"bounce_position": _attempt_throw_plan.get("bounce_position", Vector3.ZERO),
		"aim_error": _attempt_throw_plan.get("aim_error", Vector3.ZERO),
		"angle_error_degrees": float(_attempt_throw_plan.get("angle_error_degrees", 0.0)),
	}


func _get_hit_cup_events(contact_summary) -> Array[Dictionary]:
	var hit_cups: Array[Dictionary] = []
	var seen: Dictionary = {}
	if contact_summary == null:
		return hit_cups

	for contact in contact_summary.contacts:
		if str(contact.get("type", "")) != "cup":
			continue

		var owner_slot := int(contact.get("owner_slot", 0))
		var cup_index := int(contact.get("cup_index", -1))
		var key := "%d:%d" % [owner_slot, cup_index]
		if cup_index < 0 or seen.has(key):
			continue

		seen[key] = true
		hit_cups.append({
			"player": _format_slot(owner_slot),
			"owner_slot": owner_slot,
			"owner_side": str(contact.get("owner_side", "")),
			"cup_index": cup_index,
			"time_seconds": float(contact.get("time_seconds", 0.0)),
		})
	return hit_cups


func _build_removed_cup_causes(scored_cup_index: int, removed_cup_indices: Array[int], outcome: Dictionary) -> Array[Dictionary]:
	var causes: Array[Dictionary] = []
	var cause_by_index: Dictionary = {}
	if scored_cup_index >= 0 and removed_cup_indices.has(scored_cup_index):
		cause_by_index[scored_cup_index] = "score"

	for trigger in _read_dictionary_array(outcome.get("rule_triggers", [])):
		var rule_id := str(trigger.get("rule_id", ""))
		if rule_id == String(HouseRuleIdsScript.CHAIN_LIGHTNING):
			for cup_index in _read_int_array(trigger.get("touched_cup_indices", [])):
				cause_by_index[cup_index] = "chain lightning"
		elif rule_id == String(HouseRuleIdsScript.BOUNCING):
			var extra_cup_index := int(trigger.get("extra_cup_index", -1))
			if extra_cup_index >= 0:
				cause_by_index[extra_cup_index] = "bounce"

	for cup_index in removed_cup_indices:
		causes.append({
			"cup_index": cup_index,
			"cause": str(cause_by_index.get(cup_index, "score" if cup_index == scored_cup_index else "unknown")),
		})
	return causes


func _get_extra_removed_cup_causes(scored_cup_index: int, removed_cup_causes: Array[Dictionary]) -> Array[Dictionary]:
	var extras: Array[Dictionary] = []
	for removal in removed_cup_causes:
		if int(removal.get("cup_index", -1)) == scored_cup_index:
			continue
		extras.append(removal.duplicate(true))
	return extras


func _serialize_throw_plan(throw_plan: Dictionary) -> Dictionary:
	return {
		"success": bool(throw_plan.get("success", false)),
		"profile_id": str(throw_plan.get("profile_id", "")),
		"display_name": str(throw_plan.get("display_name", "")),
		"shot_type": str(throw_plan.get("shot_type", "direct")),
		"target_cup_index": int(throw_plan.get("target_cup_index", -1)),
		"target_position": throw_plan.get("target_position", Vector3.ZERO),
		"aim_position": throw_plan.get("aim_position", Vector3.ZERO),
		"bounce_position": throw_plan.get("bounce_position", Vector3.ZERO),
		"release_angle_degrees": float(throw_plan.get("release_angle_degrees", 0.0)),
		"launch_velocity": throw_plan.get("launch_velocity", Vector3.ZERO),
		"aim_error": throw_plan.get("aim_error", Vector3.ZERO),
		"angle_error_degrees": float(throw_plan.get("angle_error_degrees", 0.0)),
		"bounce_allowed": bool(throw_plan.get("bounce_allowed", false)),
		"bounce_attempted": bool(throw_plan.get("bounce_attempted", false)),
		"bounce_roll": float(throw_plan.get("bounce_roll", 1.0)),
		"predicted_bounce_error": float(throw_plan.get("predicted_bounce_error", -1.0)),
		"predicted_bounce_apex_height": float(throw_plan.get("predicted_bounce_apex_height", 0.0)),
		"fallback_reason": str(throw_plan.get("fallback_reason", "")),
		"failure_reason": str(throw_plan.get("failure_reason", "")),
	}


func _apply_removed_cup_indices(slot: int, values: Variant, physical_scoring_cup: Node3D = null) -> void:
	var rack_state = _get_rack_state(slot)
	if rack_state == null:
		return

	for cup_index in _read_int_array(values):
		if rack_state.is_scored(cup_index):
			continue

		var cup: Node3D = rack_state.mark_scored(cup_index)
		if cup != null and is_instance_valid(cup) and hide_removed_cups:
			if cup == physical_scoring_cup:
				_pending_cup_removals.queue_scored_cup(cup, captured_cup_remove_delay, _attempt_ball)
			else:
				_pending_cup_removals.queue_scored_cup(cup, cup_remove_delay)


func _update_pending_cup_removals(delta: float) -> void:
	_pending_cup_removals.update(delta)


func _update_labels() -> void:
	if _status_label != null:
		var status := "%s turn" % _format_slot(_match_model.active_slot)
		if _attempt_active:
			status = "%s shot in flight" % _format_slot(_attempt_active_slot)
		elif _match_model.is_complete():
			status = "%s wins" % _format_slot(_match_model.winner_slot)
		var manual_hint: String = "Press Next Shot" if not autoplay_on_ready and not _cli_auto_test_running and not _attempt_active else ""
		_status_label.text = "%s\nCPU 1: %d / %d  CPU 2: %d / %d\nCups: %d - %d\nRules: %s\n%s" % [
			status,
			_match_model.get_score(SIDE_ONE),
			MatchConstants.RACK_SIZE,
			_match_model.get_score(SIDE_TWO),
			MatchConstants.RACK_SIZE,
			_match_model.get_remaining_count(SIDE_ONE),
			_match_model.get_remaining_count(SIDE_TWO),
			_house_rules_profile.get_compact_ruleset_id() if _house_rules_profile != null else "",
			manual_hint,
		]

	if _shot_log_label != null:
		var lines: Array[String] = []
		var start_index := maxi(0, _shot_log.size() - 5)
		for index in range(start_index, _shot_log.size()):
			var event: Dictionary = _shot_log[index]
			lines.append(_format_event_summary(event))
		_shot_log_label.text = "\n".join(lines)

	_update_controls()


func _update_controls() -> void:
	var can_step: bool = (
		_initialized
		and not _attempt_active
		and _match_model.match_phase == ClassicMatchModelScript.PHASE_PLAYING
		and _shots_simulated < max_automatic_shots
	)
	if _next_shot_button != null:
		_next_shot_button.disabled = not can_step
		_next_shot_button.text = "Next Shot" if can_step else "Shot In Flight" if _attempt_active else "Match Complete"
	if _export_log_button != null:
		_export_log_button.disabled = _shot_log.is_empty()


func _refresh_log_list() -> void:
	if _cli_auto_test_running or _shot_log_list == null:
		return

	for child in _shot_log_list.get_children():
		_shot_log_list.remove_child(child)
		child.queue_free()

	if _shot_log.is_empty():
		var empty_label := _make_log_entry_label("No shots yet.")
		_shot_log_list.add_child(empty_label)
		return

	for event in _shot_log:
		_shot_log_list.add_child(_make_log_entry_label(_format_event_detail(event)))

	call_deferred("_scroll_log_to_bottom")


func _make_log_entry_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 13)
	return label


func _scroll_log_to_bottom() -> void:
	if _shot_log_list == null:
		return

	var scroll := _shot_log_list.get_parent() as ScrollContainer
	if scroll == null:
		return
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


func _is_test_snapshot_consistent(snapshot: Dictionary) -> bool:
	var scores := _read_two_int_array(snapshot.get("scores_by_slot", [0, 0]))
	var side_one_scored := _read_int_array(snapshot.get("scored_cups_slot_1", []))
	var side_two_scored := _read_int_array(snapshot.get("scored_cups_slot_2", []))
	return scores[0] == side_two_scored.size() and scores[1] == side_one_scored.size()


func _get_failure_reason(
	snapshot: Dictionary,
	shot_limit: int,
	frame_limit: int,
	min_resolved_shots: int,
	min_scores: int,
	require_complete: bool
) -> String:
	if not bool(snapshot.get("state_consistent", false)):
		return "Shared model score and cup state diverged."
	if _shots_simulated < min_resolved_shots:
		return "Only resolved %d of %d required physical shots." % [_shots_simulated, min_resolved_shots]
	if _get_resolved_score_count() < min_scores:
		return "Only resolved %d of %d required physical scores." % [_get_resolved_score_count(), min_scores]
	if str(snapshot.get("phase", "")) != ClassicMatchModelScript.PHASE_COMPLETE:
		if not require_complete:
			return "Unknown physical smoke failure."
		if _shots_simulated >= shot_limit:
			return "Match did not complete within %d resolved shots." % shot_limit
		return "Match did not complete within %d physics frames." % frame_limit
	return "Unknown automatic test failure."


func _is_automatic_success_ready(require_complete: bool, min_resolved_shots: int, min_scores: int) -> bool:
	if require_complete:
		return _match_model.is_complete()
	return _shots_simulated >= min_resolved_shots and _get_resolved_score_count() >= min_scores


func _get_resolved_score_count() -> int:
	var score_count := 0
	for event in _shot_log:
		if bool(event.get("resolved_score", false)):
			score_count += 1
	return score_count


func _count_bounce_attempts(snapshot: Dictionary) -> int:
	var count := 0
	for event in _get_snapshot_shot_log(snapshot):
		var throw_plan: Dictionary = event.get("throw_plan", {})
		if bool(throw_plan.get("bounce_attempted", false)):
			count += 1
	return count


func _count_bounce_plans(snapshot: Dictionary) -> int:
	var count := 0
	for event in _get_snapshot_shot_log(snapshot):
		var throw_plan: Dictionary = event.get("throw_plan", {})
		if str(throw_plan.get("shot_type", "")) == "bounce":
			count += 1
	return count


func _get_snapshot_shot_log(snapshot: Dictionary) -> Array:
	var shot_log_value: Variant = snapshot.get("shot_log", [])
	return shot_log_value if shot_log_value is Array else []


func _is_valid_scored_cup(scored_cup: Node3D, target_rack_state, target_slot: int) -> bool:
	if scored_cup == null or not is_instance_valid(scored_cup) or target_rack_state == null:
		return false

	var scored_owner_slot := int(scored_cup.get_meta("owner_slot", 0))
	var cup_index := _get_cup_index(scored_cup)
	return scored_owner_slot == target_slot and cup_index >= 0 and not target_rack_state.is_scored(cup_index)


func _is_miss(target_rack_state) -> bool:
	var contact_candidate: Node3D = target_rack_state.find_score_contact_candidate(_attempt_ball) if target_rack_state != null else null
	return ShotAttemptEvaluatorScript.is_miss(
		_attempt_ball,
		_attempt_elapsed,
		_get_attempt_bounds(),
		contact_candidate,
		_is_attempt_ball_settled()
	)


func _is_attempt_ball_settled() -> bool:
	return ShotPhysicsScript.is_ball_settled(_attempt_ball, settled_speed)


func _configure_balls() -> void:
	var configured_ids: Dictionary = {}
	for slot in [SIDE_ONE, SIDE_TWO]:
		var ball := _get_ball(slot)
		if ball == null:
			continue

		var instance_id := int(ball.get_instance_id())
		if configured_ids.has(instance_id):
			continue

		configured_ids[instance_id] = true
		_set_ball_grabbable(ball, false)


func _reset_all_balls() -> void:
	var reset_ids: Dictionary = {}
	for slot in [SIDE_ONE, SIDE_TWO]:
		var ball := _get_ball(slot)
		if ball == null:
			continue

		var instance_id := int(ball.get_instance_id())
		if reset_ids.has(instance_id):
			continue

		reset_ids[instance_id] = true
		ComputerThrowPhysicsScript.reset_ball(ball, _get_ball_spawn_transform(slot), true)
		_set_ball_grabbable(ball, false)


func _reset_inactive_balls(active_slot: int) -> void:
	for slot in [SIDE_ONE, SIDE_TWO]:
		if slot == active_slot:
			continue

		var ball := _get_ball(slot)
		if ball != null and ball != _get_ball(active_slot):
			ComputerThrowPhysicsScript.reset_ball(ball, _get_ball_spawn_transform(slot), true)


func _set_ball_grabbable(ball: ThrowableBall, is_grabbable: bool) -> void:
	if ball != null and ball.has_method("set_grabbable"):
		ball.call("set_grabbable", is_grabbable)


func _get_ball(slot: int) -> ThrowableBall:
	return _ball_by_slot.get(slot, null) as ThrowableBall


func _get_rack_state(slot: int):
	return _rack_state_by_slot.get(slot, null)


func _get_target_heuristic(slot: int) -> String:
	return side_one_target_heuristic if slot == SIDE_ONE else side_two_target_heuristic


func _get_accuracy_error_radius(slot: int) -> float:
	return side_one_accuracy_error_radius if slot == SIDE_ONE else side_two_accuracy_error_radius


func _get_ball_spawn_transform(slot: int) -> Transform3D:
	var half_length := table_length_meters * 0.5
	var spawn_z := table_center_z + half_length + rack_end_margin
	var rotation_y := 0.0
	if slot == SIDE_TWO:
		spawn_z = table_center_z - half_length - rack_end_margin
		rotation_y = PI

	return Transform3D(Basis(Vector3.UP, rotation_y), Vector3(0.0, ball_spawn_height, spawn_z))


func _get_side_id(slot: int) -> StringName:
	return SIDE_ONE_ID if slot == SIDE_ONE else SIDE_TWO_ID


func _format_slot(slot: int) -> String:
	if slot == SIDE_ONE:
		return "CPU 1"
	if slot == SIDE_TWO:
		return "CPU 2"
	return "CPU ?"


func _format_event_summary(event: Dictionary) -> String:
	var result: Dictionary = event.get("result", {})
	var score_text: String = "scored cup %d" % int(result.get("scored_cup_index", -1)) if bool(result.get("resolved_score", false)) else "missed"
	return "Shot %d: %s -> target cup %d, %s, hit %s, removed %s%s" % [
		int(event.get("shot", 0)),
		str(event.get("player", _format_slot(int(event.get("active_slot", 0))))),
		int(event.get("target_cup_index", -1)),
		score_text,
		_format_hit_cups(result.get("hit_cups", [])),
		result.get("new_removed_cup_indices", []),
		_format_extra_removals(result.get("extra_removed_cups", [])),
	]


func _format_event_detail(event: Dictionary) -> String:
	var initial: Dictionary = event.get("initial_conditions", {})
	var result: Dictionary = event.get("result", {})
	var lines: Array[String] = [
		_format_event_summary(event),
		"  Initial: shot=%s profile=%s target=%s spawn=%s velocity=%s angle=%.2f aim=%s aim_error=%s angle_error=%.2f" % [
			str(initial.get("shot_type", "direct")),
			str(initial.get("profile_id", "")),
			_format_vector3(initial.get("target_position", Vector3.ZERO)),
			_format_vector3(initial.get("spawn_position", Vector3.ZERO)),
			_format_vector3(initial.get("launch_velocity", Vector3.ZERO)),
			float(initial.get("release_angle_degrees", 0.0)),
			_format_vector3(initial.get("aim_position", Vector3.ZERO)),
			_format_vector3(initial.get("aim_error", Vector3.ZERO)),
			float(initial.get("angle_error_degrees", 0.0)),
		],
		"  Result: scored=%s scored_cup=%d hit_cups=%s removed=%s extras=%s" % [
			str(bool(result.get("resolved_score", false))),
			int(result.get("scored_cup_index", -1)),
			_format_hit_cups(result.get("hit_cups", [])),
			result.get("new_removed_cup_indices", []),
			_format_extra_removal_list(result.get("extra_removed_cups", [])),
		],
	]
	return "\n".join(lines)


func _format_hit_cups(values: Variant) -> String:
	var hits: Array = values if values is Array else []
	if hits.is_empty():
		return "none"

	var parts: Array[String] = []
	for hit in hits:
		if hit is Dictionary:
			parts.append("%s cup %d" % [
				str(hit.get("player", _format_slot(int(hit.get("owner_slot", 0))))),
				int(hit.get("cup_index", -1)),
			])
	return ", ".join(parts) if not parts.is_empty() else "none"


func _format_extra_removals(values: Variant) -> String:
	var extras := _format_extra_removal_list(values)
	return "" if extras == "none" else ", extras: %s" % extras


func _format_extra_removal_list(values: Variant) -> String:
	var extras: Array = values if values is Array else []
	if extras.is_empty():
		return "none"

	var parts: Array[String] = []
	for extra in extras:
		if extra is Dictionary:
			parts.append("cup %d by %s" % [int(extra.get("cup_index", -1)), str(extra.get("cause", "unknown"))])
	return ", ".join(parts) if not parts.is_empty() else "none"


func _format_vector3(value: Variant) -> String:
	var vector: Vector3 = value if value is Vector3 else Vector3.ZERO
	return "(%.3f, %.3f, %.3f)" % [vector.x, vector.y, vector.z]


func _build_log_export_text() -> String:
	var lines: Array[String] = [
		"Computer Classic Match Shot Log",
		"Rules: %s" % (_house_rules_profile.get_compact_ruleset_id() if _house_rules_profile != null else ""),
		"Shots: %d" % _shot_log.size(),
		"",
	]
	for event in _shot_log:
		lines.append(_format_event_detail(event))
		lines.append("  Raw: %s" % JSON.stringify(_json_safe_variant(event)))
		lines.append("")
	return "\n".join(lines)


func _json_safe_variant(value: Variant) -> Variant:
	if value is Vector3:
		var vector: Vector3 = value
		return {"x": vector.x, "y": vector.y, "z": vector.z}
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value.keys():
			result[str(key)] = _json_safe_variant(value[key])
		return result
	if value is Array:
		var result_array: Array = []
		for item in value:
			result_array.append(_json_safe_variant(item))
		return result_array
	return value


func _update_testing_camera_input(delta: float) -> void:
	var horizontal := Input.get_axis("ui_left", "ui_right")
	var vertical := Input.get_axis("ui_up", "ui_down")
	if Input.is_key_pressed(KEY_A):
		horizontal -= 1.0
	if Input.is_key_pressed(KEY_D):
		horizontal += 1.0
	if Input.is_key_pressed(KEY_W):
		vertical -= 1.0
	if Input.is_key_pressed(KEY_S):
		vertical += 1.0

	var lift := 0.0
	if Input.is_key_pressed(KEY_E):
		lift += 1.0
	if Input.is_key_pressed(KEY_Q):
		lift -= 1.0

	var zoom := 0.0
	if Input.is_key_pressed(KEY_EQUAL) or Input.is_key_pressed(KEY_PLUS):
		zoom -= 1.0
	if Input.is_key_pressed(KEY_MINUS):
		zoom += 1.0

	if is_zero_approx(horizontal) and is_zero_approx(vertical) and is_zero_approx(lift) and is_zero_approx(zoom):
		return

	var basis := _testing_camera.global_transform.basis
	var right := basis.x
	var forward := -basis.z
	right.y = 0.0
	forward.y = 0.0
	right = right.normalized() if right.length_squared() > 0.001 else Vector3.RIGHT
	forward = forward.normalized() if forward.length_squared() > 0.001 else Vector3.FORWARD
	testing_camera_focus += (right * horizontal + forward * vertical + Vector3.UP * lift) * testing_camera_move_speed * delta
	_camera_distance = clampf(_camera_distance + zoom * testing_camera_zoom_speed * delta, 1.0, 7.0)
	_apply_testing_camera_transform()


func _apply_testing_camera_transform() -> void:
	if _testing_camera == null:
		return

	var horizontal_distance := cos(_camera_pitch) * _camera_distance
	var offset := Vector3(
		sin(_camera_yaw) * horizontal_distance,
		sin(_camera_pitch) * _camera_distance,
		cos(_camera_yaw) * horizontal_distance
	)
	_testing_camera.global_position = testing_camera_focus + offset
	_testing_camera.look_at(testing_camera_focus, Vector3.UP)


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


func _read_dictionary_array(values: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var input: Array = values if values is Array else []
	for value in input:
		if value is Dictionary:
			result.append(value.duplicate(true))
	return result


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
