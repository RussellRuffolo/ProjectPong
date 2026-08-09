extends Node3D
class_name ShotTester

const MatchConstants := preload("res://scripts/match/pong_match_constants.gd")
const CupRackBuilderScript := preload("res://scripts/match/cup_rack_builder.gd")
const RackStateScript := preload("res://scripts/match/rack_state.gd")
const ShotPhysicsScript := preload("res://scripts/match/shot_physics.gd")
const ShotScoreTrackerScript := preload("res://scripts/match/shot_score_tracker.gd")
const ShotAttemptEvaluatorScript := preload("res://scripts/match/shot_attempt_evaluator.gd")
const ComputerThrowPhysicsScript := preload("res://scripts/match/computer_throw_physics.gd")
const HouseRuleIdsScript := preload("res://scripts/house_rules/house_rule_ids.gd")
const HouseRulesProfileScript := preload("res://scripts/house_rules/house_rules_profile.gd")
const HouseRulesSettingsStoreScript := preload("res://scripts/house_rules/house_rules_settings_store.gd")
const ShotContextScript := preload("res://scripts/house_rules/shot_context.gd")
const ShotContactTrackerScript := preload("res://scripts/house_rules/shot_contact_tracker.gd")
const HouseRulesResolverScript := preload("res://scripts/house_rules/house_rules_resolver.gd")

const ACTIVE_SLOT := MatchConstants.PLAYER_ONE_SLOT
const TARGET_SLOT := MatchConstants.PLAYER_TWO_SLOT
const ACTIVE_SIDE := &"shot_tester"
const TARGET_SIDE := &"target"
const DIRECT_FALLBACK_ARC_HEIGHT := 0.42
const MIN_RELEASE_ANGLE_DEGREES := 8.0
const MAX_RELEASE_ANGLE_DEGREES := 88.0

@export var target_cup_parent_path: NodePath
@export var ball_path: NodePath
@export var aim_indicator_path: NodePath
@export var camera_path: NodePath
@export var ui_root_path: NodePath
@export var cup_visual_scene: PackedScene
@export var cup_collision_scene: PackedScene
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
@export var scoring_settle_seconds := 0.35
@export var max_attempt_seconds := 5.0
@export var reset_delay := 0.15
@export var scored_reset_delay := 0.25
@export var default_release_angle_degrees := 42.0
@export var deterministic_seed := 20260809
@export var log_export_path := "user://shot_tester_log.txt"
@export var testing_camera_focus := Vector3(0.0, 0.88, -1.56)
@export_range(0.05, 4.0, 0.05) var testing_camera_move_speed := 1.25
@export_range(0.05, 4.0, 0.05) var testing_camera_zoom_speed := 0.9
@export_range(0.001, 0.02, 0.001) var testing_camera_drag_sensitivity := 0.006

var _target_cup_parent: Node3D
var _ball: ThrowableBall
var _aim_indicator: Node3D
var _testing_camera: Camera3D
var _ui_root: Control
var _rack_state = RackStateScript.new()
var _house_rules_profile
var _house_rules_source := "saved"
var _rng := RandomNumberGenerator.new()
var _score_tracker := ShotScoreTrackerScript.new()
var _contact_tracker := ShotContactTrackerScript.new()

var _aim_position := Vector3.ZERO
var _release_angle_degrees := 42.0
var _aim_error_radius := 0.0
var _angle_error_degrees := 0.0
var _seed := 20260809
var _active_cup_indices: Array[int] = []
var _island_called := false
var _island_cup_index := -1
var _shot_log: Array[Dictionary] = []
var _shots_simulated := 0
var _last_resolved_event: Dictionary = {}

var _attempt_active := false
var _attempt_elapsed := 0.0
var _attempt_initial_conditions: Dictionary = {}
var _attempt_launch_velocity := Vector3.ZERO
var _attempt_sampled_aim_error := Vector3.ZERO
var _attempt_sampled_angle_error := 0.0
var _attempt_effective_aim_position := Vector3.ZERO
var _attempt_effective_release_angle := 0.0
var _attempt_fallback_reason := ""
var _attempt_active_cup_indices: Array[int] = []

var _cli_auto_test_running := false
var _camera_dragging := false
var _aim_dragging := false
var _camera_yaw := 0.0
var _camera_pitch := deg_to_rad(38.0)
var _camera_distance := 3.45
var _ui_updating := false

var _aim_x_spin: SpinBox
var _aim_y_spin: SpinBox
var _aim_z_spin: SpinBox
var _release_angle_spin: SpinBox
var _aim_error_spin: SpinBox
var _angle_error_spin: SpinBox
var _seed_spin: SpinBox
var _house_rules_line: LineEdit
var _island_check: CheckBox
var _island_option: OptionButton
var _planned_label: Label
var _status_label: Label
var _log_export_status_label: Label
var _test_button: Button
var _repeat_button: Button
var _next_variation_button: Button
var _reset_ball_button: Button
var _reset_rack_button: Button
var _export_log_button: Button
var _cup_pyramid_container: VBoxContainer
var _shot_log_list: VBoxContainer
var _rules_popup: PopupPanel
var _rules_list: VBoxContainer
var _cup_buttons: Dictionary = {}


func _ready() -> void:
	if OS.has_feature("template"):
		push_warning("[ShotTester] Editor-only shot tester is disabled in exported builds.")
		set_process(false)
		set_physics_process(false)
		return

	_bind_scene_nodes()
	_reset_model_defaults()
	_build_target_rack()
	_load_house_rules_source("saved")
	_reset_ball()
	_set_aim_position(_get_default_aim_position())
	_build_ui()
	_initialize_testing_camera()
	_refresh_all_ui()

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
	if _attempt_active:
		_update_active_attempt(delta)


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


func apply_test_configuration(config: Dictionary) -> void:
	if config.has("seed"):
		_seed = int(config["seed"])
		deterministic_seed = _seed
	if config.has("release_angle_degrees"):
		_release_angle_degrees = clampf(float(config["release_angle_degrees"]), MIN_RELEASE_ANGLE_DEGREES, MAX_RELEASE_ANGLE_DEGREES)
	if config.has("aim_error_radius"):
		_aim_error_radius = maxf(0.0, float(config["aim_error_radius"]))
	if config.has("angle_error_degrees"):
		_angle_error_degrees = maxf(0.0, float(config["angle_error_degrees"]))
	if config.has("active_cup_indices"):
		_active_cup_indices = _sanitize_cup_indices(config["active_cup_indices"])
		_build_target_rack()
	if config.has("house_rules_source"):
		_load_house_rules_source(str(config["house_rules_source"]))
	if config.has("aim_position"):
		_set_aim_position(config["aim_position"] as Vector3)
	if config.has("island_cup_index"):
		_island_called = true
		_island_cup_index = int(config["island_cup_index"])
	elif config.has("island_called"):
		_island_called = bool(config["island_called"])

	if not _active_cup_indices.has(_island_cup_index):
		_island_cup_index = _active_cup_indices[0] if not _active_cup_indices.is_empty() else -1

	_reset_ball()
	_refresh_all_ui()


func run_single_shot_test(config: Dictionary = {}) -> Dictionary:
	apply_test_configuration(config)
	_reset_ball()
	if not _start_test_shot():
		return {
			"passed": false,
			"failure_reason": "Could not start shot.",
		}

	var frame_limit := maxi(1, int(config.get("max_physics_frames", 6000)))
	var frames_simulated := 0
	while _attempt_active and frames_simulated < frame_limit:
		await get_tree().physics_frame
		frames_simulated += 1

	var result := get_test_snapshot()
	result["physics_frames_simulated"] = frames_simulated
	if _attempt_active:
		_resolve_attempt(false, null, "frame_limit")
		result = get_test_snapshot()
		result["physics_frames_simulated"] = frames_simulated

	var passed := _evaluate_expectations(result, config)
	result["passed"] = passed
	if not passed and str(result.get("failure_reason", "")).is_empty():
		result["failure_reason"] = "Shot result did not match expectations."
	return result


func get_test_snapshot() -> Dictionary:
	var event := _last_resolved_event.duplicate(true)
	var result: Dictionary = event.get("result", {}) if event.get("result", {}) is Dictionary else {}
	return {
		"resolved": not event.is_empty(),
		"shot_count": _shots_simulated,
		"resolved_score": bool(result.get("resolved_score", false)),
		"was_score": bool(result.get("was_score", false)),
		"scored_cup_index": int(result.get("scored_cup_index", -1)),
		"removed_cup_indices": _read_int_array(result.get("removed_cup_indices", [])),
		"ignored_cup_indices": _read_int_array(result.get("ignored_cup_indices", [])),
		"rule_triggers": result.get("rule_triggers", []),
		"ruleset_id": _house_rules_profile.get_compact_ruleset_id() if _house_rules_profile != null else "",
		"remaining_cup_indices": _active_cup_indices.duplicate(),
		"event": event,
		"failure_reason": str(event.get("failure_reason", "")),
	}


func _bind_scene_nodes() -> void:
	_target_cup_parent = get_node_or_null(target_cup_parent_path) as Node3D
	_ball = get_node_or_null(ball_path) as ThrowableBall
	_aim_indicator = get_node_or_null(aim_indicator_path) as Node3D
	_testing_camera = get_node_or_null(camera_path) as Camera3D
	_ui_root = get_node_or_null(ui_root_path) as Control

	if _target_cup_parent == null:
		push_error("[ShotTester] Target cup parent is not configured.")
	if _ball == null:
		push_error("[ShotTester] ThrowableBall is not configured.")
	if _aim_indicator == null:
		push_error("[ShotTester] Aim indicator is not configured.")
	if _ui_root == null:
		push_warning("[ShotTester] UI root is not configured; headless shot tests can still run.")

	if _ball != null:
		_ball.set_grabbable(false)


func _reset_model_defaults() -> void:
	_release_angle_degrees = clampf(default_release_angle_degrees, MIN_RELEASE_ANGLE_DEGREES, MAX_RELEASE_ANGLE_DEGREES)
	_aim_error_radius = 0.0
	_angle_error_degrees = 0.0
	_seed = deterministic_seed
	_active_cup_indices.clear()
	for cup_index in range(MatchConstants.RACK_SIZE):
		_active_cup_indices.append(cup_index)
	_island_called = false
	_island_cup_index = -1


func _build_target_rack() -> void:
	if _target_cup_parent == null:
		return

	for child in _target_cup_parent.get_children():
		_target_cup_parent.remove_child(child)
		child.queue_free()

	var half_length := table_length_meters * 0.5
	var target_back_row_z := table_center_z - half_length + rack_end_margin
	var cups := CupRackBuilderScript.build_triangular_rack(_target_cup_parent, {
		"cup_visual_scene": cup_visual_scene,
		"cup_collision_scene": cup_collision_scene,
		"back_row_origin": Vector3(0.0, cup_height_y, target_back_row_z),
		"row_direction_z": 1.0,
		"cup_spacing": cup_spacing,
		"name_prefix": "ShotTesterCup",
		"owner_slot": TARGET_SLOT,
		"owner_side": TARGET_SIDE,
	})
	_rack_state = RackStateScript.new()
	_rack_state.configure(cups, TARGET_SLOT, TARGET_SIDE)

	for cup_index in range(MatchConstants.RACK_SIZE):
		if not _active_cup_indices.has(cup_index):
			var cup: Node3D = _rack_state.mark_scored(cup_index)
			if cup != null and is_instance_valid(cup):
				cup.visible = false

	_refresh_cup_pyramid()
	_refresh_island_options()


func _reset_ball() -> void:
	if _ball == null:
		return
	ComputerThrowPhysicsScript.reset_ball(_ball, _get_ball_spawn_transform(), true)
	_score_tracker.reset()
	_contact_tracker.clear()
	_attempt_active = false
	_attempt_elapsed = 0.0


func _build_ui() -> void:
	if _ui_root == null:
		return

	for child in _ui_root.get_children():
		_ui_root.remove_child(child)
		child.queue_free()

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.anchor_left = 0.01
	panel.anchor_top = 0.02
	panel.anchor_right = 0.45
	panel.anchor_bottom = 0.98
	panel.offset_left = 0.0
	panel.offset_top = 0.0
	panel.offset_right = 0.0
	panel.offset_bottom = 0.0
	_ui_root.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var main_vbox := VBoxContainer.new()
	main_vbox.name = "VBox"
	margin.add_child(main_vbox)

	var title := Label.new()
	title.text = "Shot Tester"
	title.add_theme_font_size_override("font_size", 18)
	main_vbox.add_child(title)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_vbox.add_child(_status_label)

	_add_separator(main_vbox)
	_add_section_label(main_vbox, "Initial Conditions")
	_aim_x_spin = _add_spin_row(main_vbox, "Aim X", _aim_position.x, -2.0, 2.0, 0.005, _on_aim_x_changed)
	_aim_y_spin = _add_spin_row(main_vbox, "Aim Y", _aim_position.y, 0.05, 2.0, 0.005, _on_aim_y_changed)
	_aim_z_spin = _add_spin_row(main_vbox, "Aim Z", _aim_position.z, -4.5, 1.0, 0.005, _on_aim_z_changed)
	_release_angle_spin = _add_spin_row(main_vbox, "Release Angle", _release_angle_degrees, MIN_RELEASE_ANGLE_DEGREES, MAX_RELEASE_ANGLE_DEGREES, 0.1, _on_release_angle_changed)
	_aim_error_spin = _add_spin_row(main_vbox, "Aim Error Radius", _aim_error_radius, 0.0, 0.5, 0.005, _on_aim_error_changed)
	_angle_error_spin = _add_spin_row(main_vbox, "Angle Error", _angle_error_degrees, 0.0, 45.0, 0.1, _on_angle_error_changed)
	_seed_spin = _add_spin_row(main_vbox, "Seed", float(_seed), 0.0, 999999999.0, 1.0, _on_seed_changed)

	var snap_row := HBoxContainer.new()
	main_vbox.add_child(snap_row)
	snap_row.add_child(_make_button("Snap Rack", _on_snap_rack_pressed))
	snap_row.add_child(_make_button("Snap Lowest Cup", _on_snap_lowest_cup_pressed))

	_planned_label = Label.new()
	_planned_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_vbox.add_child(_planned_label)

	var right_panel := PanelContainer.new()
	right_panel.name = "RightPanel"
	right_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right_panel.anchor_left = 0.55
	right_panel.anchor_top = 0.02
	right_panel.anchor_right = 0.99
	right_panel.anchor_bottom = 0.98
	right_panel.offset_left = 0.0
	right_panel.offset_top = 0.0
	right_panel.offset_right = 0.0
	right_panel.offset_bottom = 0.0
	_ui_root.add_child(right_panel)

	var right_margin := MarginContainer.new()
	right_margin.add_theme_constant_override("margin_left", 10)
	right_margin.add_theme_constant_override("margin_top", 10)
	right_margin.add_theme_constant_override("margin_right", 10)
	right_margin.add_theme_constant_override("margin_bottom", 10)
	right_panel.add_child(right_margin)

	var right_vbox := VBoxContainer.new()
	right_vbox.name = "VBox"
	right_margin.add_child(right_vbox)

	_add_section_label(right_vbox, "Match State")
	_cup_pyramid_container = VBoxContainer.new()
	right_vbox.add_child(_cup_pyramid_container)
	_refresh_cup_pyramid()

	_island_check = CheckBox.new()
	_island_check.text = "Island called"
	_island_check.toggled.connect(_on_island_toggled)
	right_vbox.add_child(_island_check)

	_island_option = OptionButton.new()
	_island_option.item_selected.connect(_on_island_option_selected)
	right_vbox.add_child(_island_option)
	_refresh_island_options()

	_add_separator(right_vbox)
	_add_section_label(right_vbox, "House Rules")
	var rules_row := HBoxContainer.new()
	right_vbox.add_child(rules_row)
	_house_rules_line = LineEdit.new()
	_house_rules_line.placeholder_text = "saved, default, disabled, or file path"
	_house_rules_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_house_rules_line.text = _house_rules_source
	_house_rules_line.text_submitted.connect(_on_house_rules_submitted)
	rules_row.add_child(_house_rules_line)
	rules_row.add_child(_make_button("Load", _on_load_house_rules_pressed))
	rules_row.add_child(_make_button("Show", _on_show_house_rules_pressed))
	_build_rules_popup()

	_add_separator(right_vbox)
	_add_section_label(right_vbox, "Shot Controls")
	var controls := HBoxContainer.new()
	right_vbox.add_child(controls)
	_test_button = _make_button("Test Shot", _on_test_shot_pressed)
	_repeat_button = _make_button("Repeat Shot", _on_repeat_shot_pressed)
	_next_variation_button = _make_button("Next Variation", _on_next_variation_pressed)
	controls.add_child(_test_button)
	controls.add_child(_repeat_button)
	controls.add_child(_next_variation_button)

	var reset_controls := HBoxContainer.new()
	right_vbox.add_child(reset_controls)
	_reset_ball_button = _make_button("Reset Ball", _on_reset_ball_pressed)
	_reset_rack_button = _make_button("Reset Rack", _on_reset_rack_pressed)
	_export_log_button = _make_button("Export Log", _on_export_log_pressed)
	reset_controls.add_child(_reset_ball_button)
	reset_controls.add_child(_reset_rack_button)
	reset_controls.add_child(_export_log_button)

	_log_export_status_label = Label.new()
	_log_export_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_vbox.add_child(_log_export_status_label)

	_add_separator(right_vbox)
	_add_section_label(right_vbox, "Shot Log")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, 190.0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_vbox.add_child(scroll)
	_shot_log_list = VBoxContainer.new()
	_shot_log_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_shot_log_list)
	_refresh_log_list()


func _build_rules_popup() -> void:
	if _ui_root == null:
		return

	_rules_popup = PopupPanel.new()
	_rules_popup.name = "HouseRulesPopup"
	_ui_root.add_child(_rules_popup)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_rules_popup.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520.0, 430.0)
	margin.add_child(scroll)
	_rules_list = VBoxContainer.new()
	_rules_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rules_list)
	_refresh_rules_popup()


func _add_section_label(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	parent.add_child(label)


func _add_separator(parent: Control) -> void:
	var separator := HSeparator.new()
	parent.add_child(separator)


func _add_spin_row(
	parent: Control,
	label_text: String,
	value: float,
	min_value: float,
	max_value: float,
	step: float,
	callback: Callable
) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(120.0, 0.0)
	row.add_child(label)

	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.value = value
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(callback)
	row.add_child(spin)
	return spin


func _make_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	return button


func _initialize_testing_camera() -> void:
	if _testing_camera == null:
		return

	var offset := _testing_camera.global_position - testing_camera_focus
	_camera_distance = clampf(offset.length(), 1.0, 7.0)
	if _camera_distance <= 0.001:
		return

	_camera_pitch = asin(clampf(offset.y / _camera_distance, -0.95, 0.95))
	_camera_yaw = atan2(offset.x, offset.z)
	_apply_testing_camera_transform()


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _is_pointer_near_aim_indicator(event.position):
			_aim_dragging = true
			get_viewport().set_input_as_handled()
		elif not event.pressed:
			_aim_dragging = false
		return

	if event.button_index == MOUSE_BUTTON_RIGHT:
		_camera_dragging = event.pressed
		get_viewport().set_input_as_handled()
		return

	if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_camera_distance = maxf(1.0, _camera_distance - testing_camera_zoom_speed * 0.2)
		_apply_testing_camera_transform()
		get_viewport().set_input_as_handled()
	elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_camera_distance = minf(7.0, _camera_distance + testing_camera_zoom_speed * 0.2)
		_apply_testing_camera_transform()
		get_viewport().set_input_as_handled()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _aim_dragging:
		var plane_position: Variant = _get_mouse_table_plane_position(event.position, _aim_position.y)
		if plane_position != null:
			var next_position: Vector3 = plane_position
			next_position.y = _aim_position.y
			_set_aim_position(next_position)
			get_viewport().set_input_as_handled()
		return

	if _camera_dragging:
		_camera_yaw -= event.relative.x * testing_camera_drag_sensitivity
		_camera_pitch = clampf(_camera_pitch - event.relative.y * testing_camera_drag_sensitivity, deg_to_rad(8.0), deg_to_rad(78.0))
		_apply_testing_camera_transform()
		get_viewport().set_input_as_handled()


func _update_testing_camera_input(delta: float) -> void:
	if _testing_camera == null:
		return

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


func _update_aim_keyboard_input(delta: float) -> void:
	if _attempt_active:
		return

	var movement := Vector3.ZERO
	if Input.is_key_pressed(KEY_J):
		movement.x -= 1.0
	if Input.is_key_pressed(KEY_L):
		movement.x += 1.0
	if Input.is_key_pressed(KEY_I):
		movement.z -= 1.0
	if Input.is_key_pressed(KEY_K):
		movement.z += 1.0
	if Input.is_key_pressed(KEY_U):
		movement.y += 1.0
	if Input.is_key_pressed(KEY_O):
		movement.y -= 1.0
	if movement.length_squared() <= 0.001:
		return

	var speed := 0.35
	if Input.is_key_pressed(KEY_SHIFT):
		speed = 0.9
	elif Input.is_key_pressed(KEY_CTRL):
		speed = 0.08
	_set_aim_position(_aim_position + movement.normalized() * speed * delta)


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


func _is_pointer_near_aim_indicator(screen_position: Vector2) -> bool:
	var plane_position: Variant = _get_mouse_table_plane_position(screen_position, _aim_position.y)
	if plane_position == null:
		return false
	var pointer_world: Vector3 = plane_position
	return pointer_world.distance_to(_aim_position) <= 0.12


func _get_mouse_table_plane_position(screen_position: Vector2, plane_y: float) -> Variant:
	if _testing_camera == null:
		return null

	var ray_origin := _testing_camera.project_ray_origin(screen_position)
	var ray_direction := _testing_camera.project_ray_normal(screen_position)
	if absf(ray_direction.y) <= 0.0001:
		return null

	var amount := (plane_y - ray_origin.y) / ray_direction.y
	if amount < 0.0:
		return null
	return ray_origin + ray_direction * amount


func _set_aim_position(position: Vector3) -> void:
	_aim_position = position
	if _aim_indicator != null:
		_aim_indicator.global_position = _aim_position
	_sync_aim_spins()
	_update_launch_preview()


func _sync_aim_spins() -> void:
	if _ui_updating:
		return
	_ui_updating = true
	if _aim_x_spin != null:
		_aim_x_spin.value = _aim_position.x
	if _aim_y_spin != null:
		_aim_y_spin.value = _aim_position.y
	if _aim_z_spin != null:
		_aim_z_spin.value = _aim_position.z
	_ui_updating = false


func _refresh_all_ui() -> void:
	_ui_updating = true
	if _aim_x_spin != null:
		_aim_x_spin.value = _aim_position.x
	if _aim_y_spin != null:
		_aim_y_spin.value = _aim_position.y
	if _aim_z_spin != null:
		_aim_z_spin.value = _aim_position.z
	if _release_angle_spin != null:
		_release_angle_spin.value = _release_angle_degrees
	if _aim_error_spin != null:
		_aim_error_spin.value = _aim_error_radius
	if _angle_error_spin != null:
		_angle_error_spin.value = _angle_error_degrees
	if _seed_spin != null:
		_seed_spin.value = _seed
	if _house_rules_line != null:
		_house_rules_line.text = _house_rules_source
	if _island_check != null:
		_island_check.button_pressed = _island_called
	_ui_updating = false

	_refresh_cup_pyramid()
	_refresh_island_options()
	_refresh_rules_popup()
	_refresh_log_list()
	_update_launch_preview()
	_update_status()


func _refresh_cup_pyramid() -> void:
	if _cup_pyramid_container == null:
		return

	for child in _cup_pyramid_container.get_children():
		_cup_pyramid_container.remove_child(child)
		child.queue_free()
	_cup_buttons.clear()

	var rows := _get_cup_indices_by_row()
	for row in rows:
		var row_box := HBoxContainer.new()
		row_box.alignment = BoxContainer.ALIGNMENT_CENTER
		_cup_pyramid_container.add_child(row_box)

		for cup_index in row:
			var button := Button.new()
			button.custom_minimum_size = Vector2(38.0, 32.0)
			button.toggle_mode = true
			button.button_pressed = _active_cup_indices.has(cup_index)
			button.text = str(cup_index)
			button.tooltip_text = "Cup %d" % cup_index
			button.disabled = _attempt_active
			button.modulate = Color(1.0, 1.0, 1.0, 1.0) if _active_cup_indices.has(cup_index) else Color(0.45, 0.45, 0.45, 0.72)
			button.pressed.connect(_on_cup_button_pressed.bind(cup_index))
			row_box.add_child(button)
			_cup_buttons[cup_index] = button


func _get_cup_indices_by_row() -> Array[Array]:
	var by_row: Dictionary = {}
	for cup in _rack_state.get_cups():
		var row := int(cup.get_meta("rack_row", 0))
		var column := int(cup.get_meta("rack_column", 0))
		var cup_index := int(cup.get_meta("cup_index", -1))
		if cup_index < 0:
			continue
		if not by_row.has(row):
			by_row[row] = []
		by_row[row].append({
			"column": column,
			"cup_index": cup_index,
		})

	var rows: Array[Array] = []
	var row_ids := by_row.keys()
	row_ids.sort()
	for row_id in row_ids:
		var row_entries: Array = by_row[row_id]
		row_entries.sort_custom(_sort_cup_row_entries)
		var row_indices: Array = []
		for entry in row_entries:
			row_indices.append(int(entry.get("cup_index", -1)))
		rows.append(row_indices)
	return rows


func _sort_cup_row_entries(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("column", 0)) < int(b.get("column", 0))


func _refresh_island_options() -> void:
	if _island_option == null:
		return

	_island_option.clear()
	var sorted_indices := _active_cup_indices.duplicate()
	sorted_indices.sort()
	for cup_index in sorted_indices:
		_island_option.add_item("Island cup %d" % cup_index, cup_index)

	if sorted_indices.is_empty():
		_island_cup_index = -1
	else:
		if not sorted_indices.has(_island_cup_index):
			_island_cup_index = sorted_indices[0]
		for index in range(_island_option.item_count):
			if _island_option.get_item_id(index) == _island_cup_index:
				_island_option.select(index)
				break

	_island_option.disabled = not _island_called or sorted_indices.is_empty()


func _refresh_rules_popup() -> void:
	if _rules_list == null:
		return

	for child in _rules_list.get_children():
		_rules_list.remove_child(child)
		child.queue_free()

	var title := Label.new()
	title.text = "In-Play House Rules: %s" % (_house_rules_profile.get_compact_ruleset_id() if _house_rules_profile != null else "none")
	title.add_theme_font_size_override("font_size", 16)
	_rules_list.add_child(title)

	var source := Label.new()
	source.text = "Source: %s" % _house_rules_source
	source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rules_list.add_child(source)

	if _house_rules_profile == null:
		return

	for state in _house_rules_profile.get_rule_states():
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = "%s: %s\n  %s\n  %s" % [
			str(state.get("name", "")),
			"ON" if bool(state.get("enabled", false)) else "OFF",
			str(state.get("scoring_summary", "")),
			str(state.get("authority_summary", "")),
		]
		_rules_list.add_child(label)


func _update_launch_preview() -> void:
	if _planned_label == null or _ball == null:
		return

	var launch_velocity := ComputerThrowPhysicsScript.calculate_launch_velocity_for_ball_angle(
		_ball,
		_get_ball_spawn_transform().origin,
		_aim_position,
		_release_angle_degrees
	)
	var valid := ComputerThrowPhysicsScript.is_valid_launch_velocity(launch_velocity)
	var fallback := ""
	if not valid:
		var fallback_velocity := ComputerThrowPhysicsScript.calculate_launch_velocity_for_ball(
			_ball,
			_get_ball_spawn_transform().origin,
			_aim_position,
			DIRECT_FALLBACK_ARC_HEIGHT
		)
		if ComputerThrowPhysicsScript.is_valid_launch_velocity(fallback_velocity):
			launch_velocity = fallback_velocity
			valid = true
			fallback = " fallback arc"
	_planned_label.text = "Plan:%s %s velocity %s" % [
		fallback,
		"valid" if valid else "invalid",
		_format_vector3(launch_velocity),
	]


func _update_status() -> void:
	if _status_label == null:
		return

	var status := "Shot in flight" if _attempt_active else "Ready"
	var last := "No shots yet."
	if not _last_resolved_event.is_empty():
		last = _format_event_summary(_last_resolved_event)
	_status_label.text = "%s\nCups remaining: %s\nRules: %s\n%s" % [
		status,
		_active_cup_indices,
		_house_rules_profile.get_compact_ruleset_id() if _house_rules_profile != null else "",
		last,
	]

	if _test_button != null:
		_test_button.disabled = _attempt_active
	if _repeat_button != null:
		_repeat_button.disabled = _attempt_active
	if _next_variation_button != null:
		_next_variation_button.disabled = _attempt_active
	if _reset_ball_button != null:
		_reset_ball_button.disabled = _attempt_active
	if _reset_rack_button != null:
		_reset_rack_button.disabled = _attempt_active
	if _export_log_button != null:
		_export_log_button.disabled = _shot_log.is_empty()


func _refresh_log_list() -> void:
	if _shot_log_list == null:
		return

	for child in _shot_log_list.get_children():
		_shot_log_list.remove_child(child)
		child.queue_free()

	if _shot_log.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No shots yet."
		_shot_log_list.add_child(empty_label)
		return

	for event in _shot_log:
		var label := Label.new()
		label.text = _format_event_detail(event)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 13)
		_shot_log_list.add_child(label)

	call_deferred("_scroll_log_to_bottom")


func _scroll_log_to_bottom() -> void:
	if _shot_log_list == null:
		return

	var scroll := _shot_log_list.get_parent() as ScrollContainer
	if scroll == null:
		return
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


func _start_test_shot() -> bool:
	if _attempt_active or _ball == null:
		return false
	if _active_cup_indices.is_empty():
		_record_start_failure("No active target cups.")
		return false

	_rng.seed = _seed
	_attempt_sampled_aim_error = _sample_horizontal_error(_aim_error_radius)
	_attempt_sampled_angle_error = _sample_signed_error(_angle_error_degrees)
	_attempt_effective_aim_position = _aim_position + _attempt_sampled_aim_error
	_attempt_effective_release_angle = clampf(
		_release_angle_degrees + _attempt_sampled_angle_error,
		MIN_RELEASE_ANGLE_DEGREES,
		MAX_RELEASE_ANGLE_DEGREES
	)
	_attempt_fallback_reason = ""
	_attempt_launch_velocity = ComputerThrowPhysicsScript.calculate_launch_velocity_for_ball_angle(
		_ball,
		_get_ball_spawn_transform().origin,
		_attempt_effective_aim_position,
		_attempt_effective_release_angle
	)
	if not ComputerThrowPhysicsScript.is_valid_launch_velocity(_attempt_launch_velocity):
		_attempt_launch_velocity = ComputerThrowPhysicsScript.calculate_launch_velocity_for_ball(
			_ball,
			_get_ball_spawn_transform().origin,
			_attempt_effective_aim_position,
			DIRECT_FALLBACK_ARC_HEIGHT
		)
		_attempt_fallback_reason = "angle_solver_invalid"

	if not ComputerThrowPhysicsScript.is_valid_launch_velocity(_attempt_launch_velocity):
		_record_start_failure("Launch velocity is invalid.")
		return false

	_attempt_active_cup_indices = _active_cup_indices.duplicate()
	_attempt_initial_conditions = _build_initial_conditions()
	_reset_ball()
	_attempt_active = true
	_attempt_elapsed = 0.0
	_score_tracker.reset()
	_contact_tracker.clear()
	ComputerThrowPhysicsScript.launch_ball(_ball, _get_ball_spawn_transform(), _attempt_launch_velocity)
	_contact_tracker.start_attempt(_ball)
	_update_status()
	_refresh_cup_pyramid()
	print("[ShotTester] Test shot launched with velocity %s toward %s." % [
		_attempt_launch_velocity,
		_attempt_effective_aim_position,
	])
	return true


func _record_start_failure(reason: String) -> void:
	var event := {
		"shot": _shots_simulated + 1,
		"failure_reason": reason,
		"initial_conditions": _build_initial_conditions(),
		"result": {
			"resolved_score": false,
			"was_score": false,
			"scored_cup_index": -1,
			"removed_cup_indices": [],
			"ignored_cup_indices": [],
			"rule_triggers": [],
		},
	}
	_last_resolved_event = event
	_shot_log.append(event)
	_refresh_log_list()
	_update_status()
	push_warning("[ShotTester] %s" % reason)


func _update_active_attempt(delta: float) -> void:
	_attempt_elapsed += delta
	_contact_tracker.update(_attempt_elapsed)

	var resting_cup: Node3D = _rack_state.find_resting_cup(_ball)
	var ball_settled := ShotPhysicsScript.is_ball_settled(_ball, settled_speed)
	var confirmed_cup: Node3D = _score_tracker.update(delta, resting_cup, ball_settled, scoring_settle_seconds)
	if confirmed_cup != null:
		_resolve_attempt(true, confirmed_cup, "")
		return

	if ShotAttemptEvaluatorScript.is_miss(_ball, _attempt_elapsed, _get_attempt_bounds(), resting_cup, ball_settled):
		_resolve_attempt(false, null, "")


func _resolve_attempt(was_score: bool, scored_cup: Node3D, failure_reason: String = "") -> Dictionary:
	if not _attempt_active and failure_reason != "frame_limit":
		return {}

	var valid_score := was_score and _is_valid_scored_cup(scored_cup)
	var contact_summary = _contact_tracker.stop_and_get_summary(_attempt_elapsed)
	var context = _build_shot_context(contact_summary)
	var outcome := HouseRulesResolverScript.resolve_attempt(
		context,
		valid_score,
		scored_cup if valid_score else null,
		scored_reset_delay if valid_score else reset_delay
	)
	var removed_cup_indices := _read_int_array(outcome.get("removed_cup_indices", []))
	_apply_removed_cup_indices(removed_cup_indices)
	_shots_simulated += 1

	var result := {
		"was_score": valid_score,
		"resolved_score": valid_score,
		"scored_cup_index": _get_cup_index(scored_cup) if valid_score else -1,
		"removed_cup_indices": removed_cup_indices,
		"ignored_cup_indices": _read_int_array(outcome.get("ignored_cup_indices", [])),
		"rule_triggers": outcome.get("rule_triggers", []),
		"ruleset_id": str(outcome.get("ruleset_id", "")),
		"cups_remaining_after": _active_cup_indices.duplicate(),
	}
	var event := {
		"shot": _shots_simulated,
		"seed": _seed,
		"initial_conditions": _attempt_initial_conditions.duplicate(true),
		"match_state": {
			"active_cup_indices_before": _attempt_active_cup_indices.duplicate(),
			"island_called": _island_called,
			"island_cup_index": _island_cup_index if _island_called else -1,
		},
		"house_rules": _build_house_rules_log_dictionary(),
		"result": result,
		"contact_summary": contact_summary.to_dictionary(),
		"attempt_seconds": _attempt_elapsed,
		"ball_position": _ball.global_position if _ball != null and is_instance_valid(_ball) else Vector3.ZERO,
		"fallback_reason": _attempt_fallback_reason,
		"failure_reason": failure_reason,
	}

	_last_resolved_event = event.duplicate(true)
	_shot_log.append(event)
	_attempt_active = false
	_attempt_elapsed = 0.0
	_attempt_initial_conditions.clear()
	_attempt_active_cup_indices.clear()
	_score_tracker.reset()
	_contact_tracker.clear()
	_refresh_all_ui()
	print("[ShotTester] %s" % _format_event_summary(event))
	return event


func _build_shot_context(contact_summary):
	var context = ShotContextScript.new()
	context.mode_id = &"shot_tester"
	context.active_side = ACTIVE_SIDE
	context.opponent_side = TARGET_SIDE
	context.active_player_id = ACTIVE_SLOT
	context.opponent_player_id = TARGET_SLOT
	context.active_slot = ACTIVE_SLOT
	context.target_slot = TARGET_SLOT
	context.selected_rule_id = HouseRuleIdsScript.ISLAND if _island_called else &""
	context.selected_cup_index = _island_cup_index if _island_called else -1
	context.ball = _ball
	context.target_rack_state = _rack_state
	context.rules_profile = _house_rules_profile
	context.contact_summary = contact_summary
	context.normal_shots_taken = 1
	context.normal_shots_per_turn = 1
	return context


func _build_initial_conditions() -> Dictionary:
	return {
		"shot_type": "direct",
		"spawn_position": _get_ball_spawn_transform().origin,
		"aim_position": _aim_position,
		"aim_error_radius": _aim_error_radius,
		"sampled_aim_error": _attempt_sampled_aim_error,
		"effective_aim_position": _attempt_effective_aim_position,
		"release_angle_degrees": _release_angle_degrees,
		"angle_error_degrees": _angle_error_degrees,
		"sampled_angle_error_degrees": _attempt_sampled_angle_error,
		"effective_release_angle_degrees": _attempt_effective_release_angle,
		"launch_velocity": _attempt_launch_velocity,
		"fallback_reason": _attempt_fallback_reason,
	}


func _build_house_rules_log_dictionary() -> Dictionary:
	return {
		"source": _house_rules_source,
		"ruleset_id": _house_rules_profile.get_compact_ruleset_id() if _house_rules_profile != null else "",
		"enabled_rule_ids": _get_enabled_rule_id_strings(),
		"island_rule_enabled": _house_rules_profile.is_enabled(HouseRuleIdsScript.ISLAND) if _house_rules_profile != null else false,
	}


func _apply_removed_cup_indices(removed_cup_indices: Array[int]) -> void:
	for cup_index in removed_cup_indices:
		var cup := _rack_state.mark_scored(cup_index)
		if cup != null and is_instance_valid(cup):
			cup.visible = false
		_active_cup_indices.erase(cup_index)
	_active_cup_indices.sort()


func _is_valid_scored_cup(cup: Node3D) -> bool:
	if cup == null or not is_instance_valid(cup):
		return false

	var cup_index := _get_cup_index(cup)
	if cup_index < 0 or not _active_cup_indices.has(cup_index):
		return false
	if int(cup.get_meta("owner_slot", 0)) != TARGET_SLOT:
		return false
	if StringName(str(cup.get_meta("owner_side", ""))) != TARGET_SIDE:
		return false
	return not _rack_state.is_scored(cup_index)


func _sample_horizontal_error(error_radius: float) -> Vector3:
	if error_radius <= 0.0:
		return Vector3.ZERO

	var miss_angle := _rng.randf_range(0.0, TAU)
	var miss_distance := sqrt(_rng.randf()) * error_radius
	return Vector3(cos(miss_angle) * miss_distance, 0.0, sin(miss_angle) * miss_distance)


func _sample_signed_error(max_abs_error: float) -> float:
	if max_abs_error <= 0.0:
		return 0.0
	return _rng.randf_range(-max_abs_error, max_abs_error)


func _load_house_rules_source(source_value: String) -> void:
	var source := source_value.strip_edges()
	if source.is_empty() or source == "saved":
		_house_rules_source = "saved"
		_house_rules_profile = HouseRulesSettingsStoreScript.load_profile()
		_refresh_rules_popup()
		return

	if source == "default":
		_house_rules_source = "default"
		_house_rules_profile = HouseRulesProfileScript.default_profile()
		_refresh_rules_popup()
		return

	if source == "disabled":
		_house_rules_source = "disabled"
		_house_rules_profile = _build_disabled_house_rules_profile()
		_refresh_rules_popup()
		return

	var loaded_profile = _load_house_rules_profile_from_path(source)
	if loaded_profile != null:
		_house_rules_source = source
		_house_rules_profile = loaded_profile
	else:
		push_warning("[ShotTester] Could not load House Rules source %s. Keeping current profile." % source)
	_refresh_rules_popup()


func _load_house_rules_profile_from_path(path: String):
	if path.get_extension().to_lower() == "json":
		var json_text := FileAccess.get_file_as_string(path)
		if json_text.is_empty():
			return null
		var parsed: Variant = JSON.parse_string(json_text)
		if parsed is Dictionary:
			return HouseRulesProfileScript.from_dictionary(parsed)
		return null

	var config := ConfigFile.new()
	var error := config.load(path)
	if error != OK:
		return null

	var profile = HouseRulesProfileScript.default_profile()
	var found_rule := false
	for rule_id in HouseRuleIdsScript.all():
		var key := String(rule_id)
		if config.has_section_key("rules", key):
			profile.set_enabled(rule_id, bool(config.get_value("rules", key, true)))
			found_rule = true
		elif config.has_section_key("enabled_rules", key):
			profile.set_enabled(rule_id, bool(config.get_value("enabled_rules", key, true)))
			found_rule = true
	return profile if found_rule else null


func _build_disabled_house_rules_profile():
	var profile = HouseRulesProfileScript.default_profile()
	for rule_id in HouseRuleIdsScript.all():
		profile.set_enabled(rule_id, false)
	return profile


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
		elif arg.begins_with("--shot-island-cup="):
			config["island_cup_index"] = int(arg.trim_prefix("--shot-island-cup="))
		elif arg.begins_with("--shot-house-rules="):
			config["house_rules_source"] = arg.trim_prefix("--shot-house-rules=")
		elif arg.begins_with("--shot-max-physics-frames="):
			config["max_physics_frames"] = int(arg.trim_prefix("--shot-max-physics-frames="))
		elif arg.begins_with("--shot-expect-score="):
			config["expect_score"] = _parse_bool(arg.trim_prefix("--shot-expect-score="))
		elif arg.begins_with("--shot-expect-removed="):
			config["expect_removed"] = _parse_int_list(arg.trim_prefix("--shot-expect-removed="))

	call_deferred("_run_cli_shot_test", config)
	return true


func _run_cli_shot_test(config: Dictionary) -> void:
	_cli_auto_test_running = true
	var result := await run_single_shot_test(config)
	result["shot_test"] = true
	print("[ShotTester] %s" % JSON.stringify(_json_safe_variant(result)))
	get_tree().quit(0 if bool(result.get("passed", false)) else 1)


func _evaluate_expectations(snapshot: Dictionary, config: Dictionary) -> bool:
	if not bool(snapshot.get("resolved", false)):
		snapshot["failure_reason"] = "Shot was not resolved."
		return false

	var passed := true
	if config.has("expect_score"):
		passed = passed and bool(snapshot.get("resolved_score", false)) == bool(config["expect_score"])
	if config.has("expect_removed"):
		passed = passed and _read_int_array(snapshot.get("removed_cup_indices", [])) == _read_int_array(config["expect_removed"])
	return passed


func _on_aim_x_changed(value: float) -> void:
	if _ui_updating:
		return
	_set_aim_position(Vector3(value, _aim_position.y, _aim_position.z))


func _on_aim_y_changed(value: float) -> void:
	if _ui_updating:
		return
	_set_aim_position(Vector3(_aim_position.x, value, _aim_position.z))


func _on_aim_z_changed(value: float) -> void:
	if _ui_updating:
		return
	_set_aim_position(Vector3(_aim_position.x, _aim_position.y, value))


func _on_release_angle_changed(value: float) -> void:
	if _ui_updating:
		return
	_release_angle_degrees = clampf(value, MIN_RELEASE_ANGLE_DEGREES, MAX_RELEASE_ANGLE_DEGREES)
	_update_launch_preview()


func _on_aim_error_changed(value: float) -> void:
	if _ui_updating:
		return
	_aim_error_radius = maxf(0.0, value)


func _on_angle_error_changed(value: float) -> void:
	if _ui_updating:
		return
	_angle_error_degrees = maxf(0.0, value)


func _on_seed_changed(value: float) -> void:
	if _ui_updating:
		return
	_seed = int(value)


func _on_snap_rack_pressed() -> void:
	_set_aim_position(_get_default_aim_position())


func _on_snap_lowest_cup_pressed() -> void:
	var cup := _get_lowest_active_cup()
	if cup != null:
		_set_aim_position(ComputerThrowPhysicsScript.get_cup_rim_center_position(cup))


func _on_cup_button_pressed(cup_index: int) -> void:
	if _attempt_active:
		return

	if _active_cup_indices.has(cup_index):
		_active_cup_indices.erase(cup_index)
	else:
		_active_cup_indices.append(cup_index)
	_active_cup_indices.sort()
	_build_target_rack()
	_refresh_all_ui()


func _on_island_toggled(is_pressed: bool) -> void:
	if _ui_updating:
		return
	_island_called = is_pressed
	_refresh_island_options()


func _on_island_option_selected(index: int) -> void:
	if _ui_updating or _island_option == null:
		return
	_island_cup_index = _island_option.get_item_id(index)


func _on_house_rules_submitted(text: String) -> void:
	_load_house_rules_source(text)
	_refresh_all_ui()


func _on_load_house_rules_pressed() -> void:
	if _house_rules_line != null:
		_load_house_rules_source(_house_rules_line.text)
	_refresh_all_ui()


func _on_show_house_rules_pressed() -> void:
	if _rules_popup == null:
		return
	_refresh_rules_popup()
	_rules_popup.popup_centered(Vector2i(560, 480))


func _on_test_shot_pressed() -> void:
	_start_test_shot()


func _on_repeat_shot_pressed() -> void:
	_reset_ball()
	_start_test_shot()


func _on_next_variation_pressed() -> void:
	_seed += 1
	_refresh_all_ui()
	_reset_ball()
	_start_test_shot()


func _on_reset_ball_pressed() -> void:
	_reset_ball()
	_refresh_all_ui()


func _on_reset_rack_pressed() -> void:
	_active_cup_indices.clear()
	for cup_index in range(MatchConstants.RACK_SIZE):
		_active_cup_indices.append(cup_index)
	_build_target_rack()
	_reset_ball()
	_set_aim_position(_get_default_aim_position())
	_refresh_all_ui()


func _on_export_log_pressed() -> void:
	var file := FileAccess.open(log_export_path, FileAccess.WRITE)
	if file == null:
		if _log_export_status_label != null:
			_log_export_status_label.text = "Could not export log to %s." % log_export_path
		return
	file.store_string(_build_log_export_text())
	file.close()
	if _log_export_status_label != null:
		_log_export_status_label.text = "Exported %d shots to %s." % [_shot_log.size(), log_export_path]


func _get_default_aim_position() -> Vector3:
	var available := _rack_state.get_available_cups()
	if available.is_empty():
		return Vector3(0.0, cup_height_y + 0.058, table_center_z)

	var center := Vector3.ZERO
	for cup in available:
		center += ComputerThrowPhysicsScript.get_cup_rim_center_position(cup)
	return center / float(available.size())


func _get_lowest_active_cup() -> Node3D:
	var sorted_indices := _active_cup_indices.duplicate()
	sorted_indices.sort()
	for cup_index in sorted_indices:
		var cup: Node3D = _rack_state.get_cup(cup_index)
		if cup != null and is_instance_valid(cup):
			return cup
	return null


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


func _format_event_summary(event: Dictionary) -> String:
	var result: Dictionary = event.get("result", {}) if event.get("result", {}) is Dictionary else {}
	var match_state: Dictionary = event.get("match_state", {}) if event.get("match_state", {}) is Dictionary else {}
	if not str(event.get("failure_reason", "")).is_empty():
		return "Shot %d: %s" % [int(event.get("shot", 0)), str(event.get("failure_reason", ""))]

	var score_text := "scored cup %d" % int(result.get("scored_cup_index", -1)) if bool(result.get("resolved_score", false)) else "missed"
	var island_text := "cup %d" % int(match_state.get("island_cup_index", -1)) if bool(match_state.get("island_called", false)) else "none"
	return "Shot %d: %s, removed %s, rules %s, triggers %s, island %s" % [
		int(event.get("shot", 0)),
		score_text,
		result.get("removed_cup_indices", []),
		str(result.get("ruleset_id", "")),
		result.get("rule_triggers", []),
		island_text,
	]


func _format_event_detail(event: Dictionary) -> String:
	var initial: Dictionary = event.get("initial_conditions", {}) if event.get("initial_conditions", {}) is Dictionary else {}
	var result: Dictionary = event.get("result", {}) if event.get("result", {}) is Dictionary else {}
	var match_state: Dictionary = event.get("match_state", {}) if event.get("match_state", {}) is Dictionary else {}
	return "%s\n  Initial: seed=%d aim=%s sampled_error=%s effective_aim=%s angle=%.2f sampled_angle_error=%.2f effective_angle=%.2f velocity=%s\n  Match: active_cups=%s island_called=%s island_cup=%d\n  Result: scored=%s scored_cup=%d removed=%s ignored=%s remaining=%s" % [
		_format_event_summary(event),
		int(event.get("seed", _seed)),
		_format_vector3(initial.get("aim_position", Vector3.ZERO)),
		_format_vector3(initial.get("sampled_aim_error", Vector3.ZERO)),
		_format_vector3(initial.get("effective_aim_position", Vector3.ZERO)),
		float(initial.get("release_angle_degrees", 0.0)),
		float(initial.get("sampled_angle_error_degrees", 0.0)),
		float(initial.get("effective_release_angle_degrees", 0.0)),
		_format_vector3(initial.get("launch_velocity", Vector3.ZERO)),
		match_state.get("active_cup_indices_before", []),
		str(bool(match_state.get("island_called", false))),
		int(match_state.get("island_cup_index", -1)),
		str(bool(result.get("resolved_score", false))),
		int(result.get("scored_cup_index", -1)),
		result.get("removed_cup_indices", []),
		result.get("ignored_cup_indices", []),
		result.get("cups_remaining_after", []),
	]


func _build_log_export_text() -> String:
	var lines: Array[String] = [
		"Shot Tester Log",
		"Rules: %s" % (_house_rules_profile.get_compact_ruleset_id() if _house_rules_profile != null else ""),
		"Shots: %d" % _shot_log.size(),
		"",
	]
	for event in _shot_log:
		lines.append(_format_event_detail(event))
		lines.append("  Raw: %s" % JSON.stringify(_json_safe_variant(event)))
		lines.append("")
	return "\n".join(lines)


func _format_vector3(value: Variant) -> String:
	var vector: Vector3 = value if value is Vector3 else Vector3.ZERO
	return "(%.3f, %.3f, %.3f)" % [vector.x, vector.y, vector.z]


func _get_enabled_rule_id_strings() -> Array[String]:
	var result: Array[String] = []
	if _house_rules_profile == null:
		return result
	for rule_id in _house_rules_profile.get_enabled_rule_ids():
		result.append(String(rule_id))
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


func _read_int_array(values: Variant) -> Array[int]:
	var result: Array[int] = []
	var input: Array = values if values is Array else []
	for value in input:
		var cup_index := int(value)
		if not result.has(cup_index):
			result.append(cup_index)
	result.sort()
	return result


func _get_cup_index(cup: Node3D) -> int:
	return int(cup.get_meta("cup_index", -1)) if cup != null and is_instance_valid(cup) else -1


func _json_safe_variant(value: Variant) -> Variant:
	if value is Vector3:
		var vector: Vector3 = value
		return {
			"x": vector.x,
			"y": vector.y,
			"z": vector.z,
		}
	if value is StringName:
		return String(value)
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
