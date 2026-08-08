extends Node3D
class_name HouseRulesMenuPanel

const RuleIds := preload("res://scripts/house_rules/house_rule_ids.gd")
const SettingsStore := preload("res://scripts/house_rules/house_rules_settings_store.gd")
const ToggleScript := preload("res://scripts/house_rules/house_rule_toggle.gd")
const MenuButtonScript := preload("res://scripts/vr_menu_button.gd")

@export var main_buttons_path: NodePath
@export var panel_size := Vector2(1.56, 1.34)
@export var row_spacing := 0.122

var _profile
var _main_buttons_root: Node
var _toggles: Dictionary = {}
var _status_label: Label3D
var _close_button
var _defaults_button


func _ready() -> void:
	_main_buttons_root = get_node_or_null(main_buttons_path)
	_profile = SettingsStore.load_profile()
	_build_panel()
	_set_panel_open(false)
	print("[HouseRulesMenu] Loaded %s from %s." % [_profile.get_compact_ruleset_id(), SettingsStore.profile_path()])


func open_panel() -> void:
	_profile = SettingsStore.load_profile()
	_apply_profile_to_toggles()
	_set_panel_open(true)
	_update_status_label()


func close_panel() -> void:
	_set_panel_open(false)


func get_profile():
	return _profile.duplicate_profile()


func _build_panel() -> void:
	var back_panel := MeshInstance3D.new()
	back_panel.name = "BackPanel"
	var back_mesh := BoxMesh.new()
	back_mesh.size = Vector3(panel_size.x, panel_size.y, 0.035)
	back_panel.mesh = back_mesh
	var back_material := StandardMaterial3D.new()
	back_material.albedo_color = Color(0.045, 0.055, 0.055, 1.0)
	back_material.roughness = 0.82
	back_panel.material_override = back_material
	add_child(back_panel)

	var title := Label3D.new()
	title.name = "Title"
	title.position = Vector3(0.0, 0.58, 0.03)
	title.pixel_size = 0.00175
	title.font_size = 42
	title.outline_size = 6
	title.outline_modulate = Color(0.015, 0.018, 0.018, 1.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.text = "House Rules"
	add_child(title)

	var y := 0.43
	for rule_id in RuleIds.all():
		var toggle = ToggleScript.new()
		toggle.name = "%sToggle" % String(rule_id).to_pascal_case()
		toggle.position = Vector3(0.0, y, 0.045)
		toggle.set_rule_state(rule_id, RuleIds.display_name(rule_id), _profile.is_enabled(rule_id))
		toggle.set_meta("menu_handles_pressed", false)
		toggle.toggled.connect(_on_rule_toggled)
		add_child(toggle)
		_toggles[rule_id] = toggle
		y -= row_spacing

	_defaults_button = _create_panel_button("Defaults", Vector3(-0.25, -0.55, 0.045), Vector2(0.48, 0.12))
	_defaults_button.pressed.connect(_on_defaults_pressed)

	_close_button = _create_panel_button("Done", Vector3(0.32, -0.55, 0.045), Vector2(0.38, 0.12))
	_close_button.pressed.connect(_on_close_pressed)

	_status_label = Label3D.new()
	_status_label.name = "Status"
	_status_label.position = Vector3(0.0, -0.645, 0.03)
	_status_label.pixel_size = 0.001
	_status_label.font_size = 23
	_status_label.outline_size = 4
	_status_label.outline_modulate = Color(0.015, 0.018, 0.018, 1.0)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_status_label)
	_update_status_label()


func _create_panel_button(button_label: String, button_position: Vector3, button_size: Vector2):
	var button = MenuButtonScript.new()
	button.name = "%sButton" % button_label
	button.position = button_position
	button.label_text = button_label
	button.size = button_size
	button.enabled_color = Color(0.1, 0.31, 0.29, 1.0)
	button.hovered_color = Color(0.0, 0.6, 0.5, 1.0)
	button.set_meta("menu_handles_pressed", false)
	add_child(button)
	return button


func _set_panel_open(is_open: bool) -> void:
	visible = is_open
	for toggle in _toggles.values():
		if toggle != null and is_instance_valid(toggle):
			toggle.set_selectable(is_open)

	if _close_button != null:
		_close_button.set_selectable(is_open)
	if _defaults_button != null:
		_defaults_button.set_selectable(is_open)

	_set_main_buttons_enabled(not is_open)


func _set_main_buttons_enabled(is_enabled_value: bool) -> void:
	if _main_buttons_root == null:
		return

	for child in _main_buttons_root.get_children():
		if child != null and child.has_method("set_selectable"):
			child.call("set_selectable", is_enabled_value)


func _apply_profile_to_toggles() -> void:
	for rule_id in RuleIds.all():
		var toggle = _toggles.get(rule_id, null)
		if toggle != null and is_instance_valid(toggle):
			toggle.set_rule_state(rule_id, RuleIds.display_name(rule_id), _profile.is_enabled(rule_id))


func _on_rule_toggled(rule_id: StringName, is_enabled_value: bool) -> void:
	_profile.set_enabled(rule_id, is_enabled_value)
	var error := SettingsStore.save_profile(_profile)
	if error == OK:
		print("[HouseRulesMenu] Saved %s." % _profile.get_compact_ruleset_id())
	_update_status_label(error)


func _on_defaults_pressed(_menu_button) -> void:
	_profile = SettingsStore.reset_to_defaults()
	_apply_profile_to_toggles()
	_update_status_label()
	print("[HouseRulesMenu] Reset to default profile %s." % _profile.get_compact_ruleset_id())


func _on_close_pressed(_menu_button) -> void:
	close_panel()


func _update_status_label(error := OK) -> void:
	if _status_label == null or _profile == null:
		return

	if error == OK:
		_status_label.text = "Saved %s" % _profile.get_compact_ruleset_id()
	else:
		_status_label.text = "Save error %s" % error
