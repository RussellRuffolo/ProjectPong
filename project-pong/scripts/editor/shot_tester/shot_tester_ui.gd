extends RefCounted
class_name ShotTesterUi

signal aim_position_changed(position: Vector3)
signal release_angle_changed(value: float)
signal aim_error_changed(value: float)
signal angle_error_changed(value: float)
signal seed_changed(value: int)
signal cup_toggled(cup_index: int)
signal test_shot_requested
signal repeat_shot_requested
signal next_variation_requested
signal reset_ball_requested
signal reset_rack_requested
signal export_log_requested

var _root: Control
var _ui_updating := false
var _status_label: Label
var _planned_label: Label
var _native_contact_label: Label
var _export_status_label: Label
var _shot_log_list: VBoxContainer
var _aim_x_spin: SpinBox
var _aim_y_spin: SpinBox
var _aim_z_spin: SpinBox
var _release_angle_spin: SpinBox
var _aim_error_spin: SpinBox
var _angle_error_spin: SpinBox
var _seed_spin: SpinBox
var _cup_buttons: Dictionary = {}


func build(root: Control) -> void:
	_root = root
	if _root == null:
		return

	for child in _root.get_children():
		child.free()
	_build_left_panel()
	_build_right_panel()


func refresh(state: Dictionary) -> void:
	if _root == null:
		return

	_ui_updating = true
	var aim_position: Vector3 = state.get("aim_position", Vector3.ZERO)
	if _aim_x_spin != null:
		_aim_x_spin.value = aim_position.x
	if _aim_y_spin != null:
		_aim_y_spin.value = aim_position.y
	if _aim_z_spin != null:
		_aim_z_spin.value = aim_position.z
	if _release_angle_spin != null:
		_release_angle_spin.value = float(state.get("release_angle_degrees", 88.0))
	if _aim_error_spin != null:
		_aim_error_spin.value = float(state.get("aim_error_radius", 0.0))
	if _angle_error_spin != null:
		_angle_error_spin.value = float(state.get("angle_error_degrees", 0.0))
	if _seed_spin != null:
		_seed_spin.value = int(state.get("seed", 0))

	var active_cups: Array = state.get("active_cup_indices", []) if state.get("active_cup_indices", []) is Array else []
	for cup_index in _cup_buttons.keys():
		var button := _cup_buttons[cup_index] as Button
		if button == null:
			continue
		var is_active := active_cups.has(cup_index)
		button.button_pressed = is_active
		button.modulate = Color.WHITE if is_active else Color(0.45, 0.45, 0.45, 0.75)

	if _status_label != null:
		_status_label.text = str(state.get("status_text", "Ready."))
	if _planned_label != null:
		_planned_label.text = _format_launch_plan(state.get("launch_plan", {}))
	if _native_contact_label != null:
		_native_contact_label.text = _format_native_contact_status(state)
	if _export_status_label != null:
		_export_status_label.text = str(state.get("export_status", ""))
	_refresh_log_list(state.get("events", []))
	_ui_updating = false


func _build_left_panel() -> void:
	var panel := _make_panel("InitialConditions", 0.01, 0.02, 0.42, 0.98)
	var vbox := _make_panel_vbox(panel)

	var title := Label.new()
	title.text = "Native Cup Shot Tester"
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_status_label)

	_add_separator(vbox)
	_add_section_label(vbox, "Initial Conditions")
	_aim_x_spin = _add_spin_row(vbox, "Aim X", 0.0, -2.0, 2.0, 0.005, _on_aim_x_changed)
	_aim_y_spin = _add_spin_row(vbox, "Aim Y", 0.84, 0.02, 2.0, 0.005, _on_aim_y_changed)
	_aim_z_spin = _add_spin_row(vbox, "Aim Z", -2.6, -4.0, 1.0, 0.005, _on_aim_z_changed)
	_release_angle_spin = _add_spin_row(vbox, "Release Angle", 88.0, 8.0, 88.0, 0.1, _on_release_angle_changed)
	_aim_error_spin = _add_spin_row(vbox, "Aim Error", 0.0, 0.0, 0.5, 0.005, _on_aim_error_changed)
	_angle_error_spin = _add_spin_row(vbox, "Angle Error", 0.0, 0.0, 45.0, 0.1, _on_angle_error_changed)
	_seed_spin = _add_spin_row(vbox, "Seed", 0.0, 0.0, 999999999.0, 1.0, _on_seed_changed)

	_planned_label = Label.new()
	_planned_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_planned_label)

	_add_separator(vbox)
	_add_section_label(vbox, "Shot Controls")
	var controls := HBoxContainer.new()
	vbox.add_child(controls)
	controls.add_child(_make_button("Test Shot", _on_test_shot_pressed))
	controls.add_child(_make_button("Repeat", _on_repeat_shot_pressed))
	controls.add_child(_make_button("Next Variation", _on_next_variation_pressed))

	var reset_controls := HBoxContainer.new()
	vbox.add_child(reset_controls)
	reset_controls.add_child(_make_button("Reset Ball", _on_reset_ball_pressed))
	reset_controls.add_child(_make_button("Reset Rack", _on_reset_rack_pressed))
	reset_controls.add_child(_make_button("Export Log", _on_export_log_pressed))

	_export_status_label = Label.new()
	_export_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_export_status_label)


func _build_right_panel() -> void:
	var panel := _make_panel("RackAndLog", 0.58, 0.02, 0.99, 0.98)
	var vbox := _make_panel_vbox(panel)

	_add_section_label(vbox, "Active Cups")
	_build_cup_pyramid(vbox)

	_add_separator(vbox)
	_native_contact_label = Label.new()
	_native_contact_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_native_contact_label)

	_add_separator(vbox)
	_add_section_label(vbox, "Shot Log")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, 360.0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	_shot_log_list = VBoxContainer.new()
	_shot_log_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_shot_log_list)


func _build_cup_pyramid(parent: Control) -> void:
	_cup_buttons.clear()
	var rows := [[0, 1, 2, 3], [4, 5, 6], [7, 8], [9]]
	for row in rows:
		var row_container := HBoxContainer.new()
		row_container.alignment = BoxContainer.ALIGNMENT_CENTER
		parent.add_child(row_container)
		for cup_index in row:
			var button := Button.new()
			button.text = str(cup_index)
			button.toggle_mode = true
			button.custom_minimum_size = Vector2(42.0, 34.0)
			button.pressed.connect(_on_cup_button_pressed.bind(cup_index))
			row_container.add_child(button)
			_cup_buttons[cup_index] = button


func _make_panel(name: String, left: float, top: float, right: float, bottom: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = name
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = left
	panel.anchor_top = top
	panel.anchor_right = right
	panel.anchor_bottom = bottom
	panel.offset_left = 0.0
	panel.offset_top = 0.0
	panel.offset_right = 0.0
	panel.offset_bottom = 0.0
	_root.add_child(panel)
	return panel


func _make_panel_vbox(panel: PanelContainer) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	margin.add_child(vbox)
	return vbox


func _add_section_label(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	parent.add_child(label)


func _add_separator(parent: Control) -> void:
	parent.add_child(HSeparator.new())


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
	label.custom_minimum_size = Vector2(116.0, 0.0)
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


func _refresh_log_list(events_value: Variant) -> void:
	if _shot_log_list == null:
		return
	for child in _shot_log_list.get_children():
		child.free()

	var events: Array = events_value if events_value is Array else []
	if events.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No shots logged."
		_shot_log_list.add_child(empty_label)
		return

	for event in events:
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = _format_event_summary(event if event is Dictionary else {})
		_shot_log_list.add_child(label)


func _format_launch_plan(plan_value: Variant) -> String:
	var plan: Dictionary = plan_value if plan_value is Dictionary else {}
	if plan.is_empty():
		return "Launch: unavailable"
	var velocity: Vector3 = plan.get("launch_velocity", Vector3.ZERO)
	var aim: Vector3 = plan.get("effective_aim_position", Vector3.ZERO)
	var fallback := str(plan.get("fallback_reason", ""))
	return "Launch: %s | velocity (%.2f, %.2f, %.2f) | aim (%.3f, %.3f, %.3f)%s" % [
		"valid" if bool(plan.get("success", false)) else "invalid",
		velocity.x,
		velocity.y,
		velocity.z,
		aim.x,
		aim.y,
		aim.z,
		" | %s" % fallback if not fallback.is_empty() else "",
	]


func _format_native_contact_status(state: Dictionary) -> String:
	var contact: Dictionary = state.get("last_native_score_contact", {}) if state.get("last_native_score_contact", {}) is Dictionary else {}
	if contact.is_empty():
		return "Native score contact: none | observed contacts %d" % int(state.get("attempt_native_contact_count", 0))
	var world_point: Vector3 = contact.get("world_contact_point", Vector3.ZERO)
	return "Native score contact: cup %d | point (%.3f, %.3f, %.3f) | edge %.4f m | entry %.3f m/s" % [
		int(contact.get("cup_index", -1)),
		world_point.x,
		world_point.y,
		world_point.z,
		float(contact.get("edge_clearance", 0.0)),
		float(contact.get("entry_speed", 0.0)),
	]


func _format_event_summary(event: Dictionary) -> String:
	var result: Dictionary = event.get("result", {}) if event.get("result", {}) is Dictionary else {}
	if bool(result.get("was_score", false)):
		return "Shot %d: scored cup %d, %d native contact(s)" % [
			int(event.get("shot", 0)),
			int(result.get("scored_cup_index", -1)),
			int(result.get("native_contact_count", 0)),
		]
	return "Shot %d: no score, %d native contact(s), %s" % [
		int(event.get("shot", 0)),
		int(result.get("native_contact_count", 0)),
		str(event.get("resolve_reason", "")),
	]


func _on_aim_x_changed(value: float) -> void:
	if not _ui_updating:
		aim_position_changed.emit(Vector3(value, _aim_y_spin.value, _aim_z_spin.value))


func _on_aim_y_changed(value: float) -> void:
	if not _ui_updating:
		aim_position_changed.emit(Vector3(_aim_x_spin.value, value, _aim_z_spin.value))


func _on_aim_z_changed(value: float) -> void:
	if not _ui_updating:
		aim_position_changed.emit(Vector3(_aim_x_spin.value, _aim_y_spin.value, value))


func _on_release_angle_changed(value: float) -> void:
	if not _ui_updating:
		release_angle_changed.emit(value)


func _on_aim_error_changed(value: float) -> void:
	if not _ui_updating:
		aim_error_changed.emit(value)


func _on_angle_error_changed(value: float) -> void:
	if not _ui_updating:
		angle_error_changed.emit(value)


func _on_seed_changed(value: float) -> void:
	if not _ui_updating:
		seed_changed.emit(int(value))


func _on_cup_button_pressed(cup_index: int) -> void:
	if not _ui_updating:
		cup_toggled.emit(cup_index)


func _on_test_shot_pressed() -> void:
	test_shot_requested.emit()


func _on_repeat_shot_pressed() -> void:
	repeat_shot_requested.emit()


func _on_next_variation_pressed() -> void:
	next_variation_requested.emit()


func _on_reset_ball_pressed() -> void:
	reset_ball_requested.emit()


func _on_reset_rack_pressed() -> void:
	reset_rack_requested.emit()


func _on_export_log_pressed() -> void:
	export_log_requested.emit()
