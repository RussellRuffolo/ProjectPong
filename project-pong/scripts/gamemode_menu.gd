extends Node3D
class_name GamemodeMenu

@export var left_controller_path: NodePath
@export var right_controller_path: NodePath
@export var button_parent_path: NodePath
@export var house_rules_panel_path: NodePath
@export var pointer_distance := 3.0
@export_range(0.0, 1.0, 0.01) var trigger_threshold := 0.55

var _left_controller: XRController3D
var _right_controller: XRController3D
var _buttons: Array[Area3D] = []
var _hovered_button: Area3D
var _house_rules_panel: Node
var _left_select_was_pressed := false
var _right_select_was_pressed := false


func _ready() -> void:
	_left_controller = get_node_or_null(left_controller_path) as XRController3D
	_right_controller = get_node_or_null(right_controller_path) as XRController3D
	_house_rules_panel = get_node_or_null(house_rules_panel_path)
	_collect_buttons()
	print("[Menu] Gamemode menu ready with %d options." % _buttons.size())


func _physics_process(_delta: float) -> void:
	var left_hit: Area3D = _get_pointed_button(_left_controller)
	var right_hit: Area3D = _get_pointed_button(_right_controller)
	var next_hover: Area3D = right_hit if right_hit != null else left_hit

	_set_hovered_button(next_hover)
	_left_select_was_pressed = _handle_selection(_left_controller, left_hit, _left_select_was_pressed)
	_right_select_was_pressed = _handle_selection(_right_controller, right_hit, _right_select_was_pressed)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		var default_button := _get_first_interactive_button()
		if default_button != null:
			default_button.call("activate")


func _collect_buttons() -> void:
	var button_parent := get_node_or_null(button_parent_path)
	if button_parent == null:
		push_error("[Menu] Gamemode menu could not find its button parent.")
		return

	_collect_buttons_recursive(button_parent)


func _collect_buttons_recursive(root: Node) -> void:
	for child in root.get_children():
		var menu_button := child as Area3D
		if menu_button != null and menu_button.has_method("activate") and menu_button.has_signal("pressed"):
			if bool(menu_button.get_meta("menu_handles_pressed", true)):
				menu_button.pressed.connect(_on_menu_button_pressed)
			_buttons.append(menu_button)

		_collect_buttons_recursive(child)


func _get_pointed_button(controller: XRController3D) -> Area3D:
	if controller == null or not controller.get_is_active():
		return null

	var query := PhysicsRayQueryParameters3D.create(
		controller.global_position,
		controller.global_position + (-controller.global_basis.z * pointer_distance)
	)
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return null

	var menu_button := result.get("collider") as Area3D
	if menu_button == null or not _buttons.has(menu_button):
		return null
	if not _is_button_interactive(menu_button):
		return null

	return menu_button


func _handle_selection(controller: XRController3D, pointed_button: Area3D, was_pressed: bool) -> bool:
	if controller == null or not controller.get_is_active():
		return false

	var is_pressed := (
		controller.is_button_pressed(&"trigger_click")
		or controller.get_float(&"trigger") >= trigger_threshold
	)
	if is_pressed and not was_pressed and pointed_button != null:
		pointed_button.call("activate")

	return is_pressed


func _set_hovered_button(next_hover: Area3D) -> void:
	if _hovered_button == next_hover:
		return

	if _hovered_button != null and is_instance_valid(_hovered_button):
		_hovered_button.call("set_hovered", false)

	_hovered_button = next_hover

	if _hovered_button != null:
		_hovered_button.call("set_hovered", true)


func _on_menu_button_pressed(menu_button: Area3D) -> void:
	var label_text: String = menu_button.get("label_text")
	var target_scene_path: String = menu_button.get("target_scene_path")
	var command_id: String = menu_button.get("command_id")

	if command_id == "house_rules":
		_open_house_rules_panel()
		return

	if target_scene_path.is_empty():
		print("[Menu] %s is a placeholder option." % label_text)
		return

	print("[Menu] Loading %s from %s." % [label_text, target_scene_path])
	var error := get_tree().change_scene_to_file(target_scene_path)
	if error != OK:
		push_error("[Menu] Could not load %s. Error: %s." % [target_scene_path, error])


func _open_house_rules_panel() -> void:
	if _house_rules_panel == null or not _house_rules_panel.has_method("open_panel"):
		push_warning("[Menu] House Rules panel is not configured.")
		return

	print("[Menu] Opening House Rules panel.")
	_house_rules_panel.call("open_panel")


func _get_first_interactive_button() -> Area3D:
	for menu_button in _buttons:
		if _is_button_interactive(menu_button):
			return menu_button
	return null


func _is_button_interactive(menu_button: Area3D) -> bool:
	if menu_button == null or not menu_button.is_visible_in_tree():
		return false

	var selectable_value: Variant = menu_button.get("selectable")
	if selectable_value is bool and not bool(selectable_value):
		return false

	return true
