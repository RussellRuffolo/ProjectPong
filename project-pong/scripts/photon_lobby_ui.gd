extends Node3D
class_name PhotonLobbyUi

@export var session_path: NodePath
@export var left_controller_path: NodePath
@export var right_controller_path: NodePath
@export var pointer_distance := 3.0
@export_range(0.0, 1.0, 0.01) var trigger_threshold := 0.55
@export var max_room_buttons := 4

var _session: PhotonSession
var _left_controller: XRController3D
var _right_controller: XRController3D
var _buttons: Array[VRMenuButton] = []
var _room_buttons: Array[VRMenuButton] = []
var _hovered_button: VRMenuButton
var _left_select_was_pressed := false
var _right_select_was_pressed := false
var _status_label: Label3D
var _room_list_label: Label3D
var _create_button: VRMenuButton
var _refresh_button: VRMenuButton
var _is_in_room := false
var _is_connected := false


func _ready() -> void:
	_session = get_node_or_null(session_path) as PhotonSession
	_left_controller = get_node_or_null(left_controller_path) as XRController3D
	_right_controller = get_node_or_null(right_controller_path) as XRController3D
	_build_ui()
	_connect_session()
	_set_connected(false)
	_set_status("Connecting to Photon Cloud...")


func _physics_process(_delta: float) -> void:
	if _is_in_room or not visible:
		return

	var left_hit := _get_pointed_button(_left_controller)
	var right_hit := _get_pointed_button(_right_controller)
	var next_hover := right_hit if right_hit != null else left_hit

	_set_hovered_button(next_hover)
	_left_select_was_pressed = _handle_selection(_left_controller, left_hit, _left_select_was_pressed)
	_right_select_was_pressed = _handle_selection(_right_controller, right_hit, _right_select_was_pressed)


func _input(event: InputEvent) -> void:
	if _is_in_room or not _is_connected:
		return

	if event.is_action_pressed("ui_accept"):
		_create_room()


func _build_ui() -> void:
	var title := _make_label("Multiplayer Lobby", Vector3(0.0, 0.42, 0.03), 40, Color(1.0, 0.96, 0.84, 1.0))
	add_child(title)

	_status_label = _make_label("Connecting...", Vector3(0.0, 0.32, 0.03), 22, Color(0.76, 0.84, 0.8, 1.0))
	add_child(_status_label)

	_create_button = _make_button("Create Room", Vector3(-0.255, 0.18, 0.04), Vector2(0.45, 0.14))
	_create_button.pressed.connect(_on_create_pressed)
	add_child(_create_button)
	_buttons.append(_create_button)

	_refresh_button = _make_button("Refresh", Vector3(0.255, 0.18, 0.04), Vector2(0.45, 0.14))
	_refresh_button.pressed.connect(_on_refresh_pressed)
	add_child(_refresh_button)
	_buttons.append(_refresh_button)

	_room_list_label = _make_label("Open Rooms", Vector3(0.0, 0.055, 0.03), 24, Color(1.0, 0.96, 0.84, 1.0))
	add_child(_room_list_label)

	for index in range(max_room_buttons):
		var y := -0.07 - (float(index) * 0.14)
		var button := _make_button("Empty", Vector3(0.0, y, 0.04), Vector2(0.95, 0.115))
		button.pressed.connect(_on_room_pressed)
		button.set_selectable(false)
		add_child(button)
		_buttons.append(button)
		_room_buttons.append(button)


func _make_label(label_text: String, position: Vector3, font_size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = label_text
	label.position = position
	label.pixel_size = 0.00165
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.font_size = font_size
	label.modulate = color
	label.outline_size = 5
	label.outline_modulate = Color(0.02, 0.025, 0.025, 1.0)
	return label


func _make_button(label_text: String, position: Vector3, size: Vector2) -> VRMenuButton:
	var button := VRMenuButton.new()
	button.label_text = label_text
	button.position = position
	button.size = size
	return button


func _connect_session() -> void:
	if _session == null:
		_set_status("PhotonSession is missing.")
		_set_connected(false)
		return

	_session.status_changed.connect(_on_session_status_changed)
	_session.connected_to_photon.connect(_on_connected_to_photon)
	_session.room_list_changed.connect(_on_room_list_changed)
	_session.room_joined.connect(_on_room_joined)
	_session.room_left.connect(_on_room_left)
	_session.connection_failed.connect(_on_connection_failed)


func _set_connected(is_connected: bool) -> void:
	_is_connected = is_connected
	if _create_button != null:
		_create_button.set_selectable(_is_connected)
	if _refresh_button != null:
		_refresh_button.set_selectable(_is_connected)

	for button in _room_buttons:
		button.set_selectable(false)


func _get_pointed_button(controller: XRController3D) -> VRMenuButton:
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

	var button := result.get("collider") as VRMenuButton
	if button == null or not _buttons.has(button):
		return null

	return button


func _handle_selection(controller: XRController3D, pointed_button: VRMenuButton, was_pressed: bool) -> bool:
	if controller == null or not controller.get_is_active():
		return false

	var is_pressed := (
		controller.is_button_pressed(&"trigger_click")
		or controller.get_float(&"trigger") >= trigger_threshold
	)
	if is_pressed and not was_pressed and pointed_button != null:
		pointed_button.activate()

	return is_pressed


func _set_hovered_button(next_hover: VRMenuButton) -> void:
	if _hovered_button == next_hover:
		return

	if _hovered_button != null and is_instance_valid(_hovered_button):
		_hovered_button.set_hovered(false)

	_hovered_button = next_hover

	if _hovered_button != null:
		_hovered_button.set_hovered(true)


func _on_create_pressed(_button: VRMenuButton) -> void:
	_create_room()


func _on_refresh_pressed(_button: VRMenuButton) -> void:
	if _session != null:
		_session.refresh_room_list()


func _on_room_pressed(button: VRMenuButton) -> void:
	if _session == null:
		return

	var room_name := str(button.get_meta("room_name", "")).strip_edges()
	if room_name.is_empty():
		return

	_set_status("Joining %s..." % room_name)
	_session.join_room(room_name)


func _create_room() -> void:
	if _session == null or not _is_connected:
		return

	_set_status("Creating room...")
	_session.create_room()


func _on_session_status_changed(message: String) -> void:
	_set_status(message)


func _on_connected_to_photon() -> void:
	_set_connected(true)
	_set_status("Create a room or join an open room.")
	if _session != null:
		_session.refresh_room_list()


func _on_room_list_changed(rooms: Array[Dictionary]) -> void:
	var joinable_rooms: Array[Dictionary] = []
	for room in rooms:
		if bool(room.get("is_joinable", false)):
			joinable_rooms.append(room)

	for index in range(_room_buttons.size()):
		var button := _room_buttons[index]
		if index >= joinable_rooms.size():
			button.set_label_text("No open room" if index == 0 and joinable_rooms.is_empty() else "")
			button.set_meta("room_name", "")
			button.set_selectable(false)
			continue

		var room := joinable_rooms[index]
		var player_count := int(room.get("player_count", 0))
		var max_players := int(room.get("max_players", 2))
		var ruleset := str(room.get("ruleset", "classic"))
		var room_name := str(room.get("name", ""))
		button.set_label_text("%s  %d/%d  %s" % [room_name, player_count, max_players, ruleset.capitalize()])
		button.set_meta("room_name", room_name)
		button.set_selectable(true)


func _on_room_joined(room_name: String, _local_player_id: int) -> void:
	_is_in_room = true
	visible = false
	_set_status("Joined %s." % room_name)


func _on_room_left() -> void:
	_is_in_room = false
	visible = true
	if _session != null:
		_session.refresh_room_list()


func _on_connection_failed(reason: String) -> void:
	_set_connected(false)
	_set_status("Photon connection failed: %s" % reason)


func _set_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message
