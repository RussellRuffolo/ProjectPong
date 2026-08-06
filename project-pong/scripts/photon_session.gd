extends Node
class_name PhotonSession

signal status_changed(message: String)
signal connected_to_photon()
signal room_joined(room_name: String, local_player_id: int)
signal room_left()
signal player_joined(player_id: int, player_name: String)
signal player_left(player_id: int, is_inactive: bool)
signal connection_failed(reason: String)

@export var auto_connect := true
@export var app_id_project_setting := "fusion/connection/app_id"
@export var room_name_project_setting := "fusion/connection/default_room"
@export var region_project_setting := "fusion/connection/region"
@export var default_room_name := "project-pong-dev-room"
@export var app_version := "project-pong-multiplayer-prototype-0.1"
@export_range(2, 4, 1) var max_players := 2
@export var visible_room := false

var _fusion: Object
var _room_name := ""
var _local_player_id := 0
var _last_status := ""


func _ready() -> void:
	if auto_connect:
		start()


func start() -> void:
	if not Engine.has_singleton("Fusion"):
		_set_status("Photon Fusion singleton is unavailable. Check addons/fusion installation.")
		return

	_fusion = Engine.get_singleton("Fusion")
	_connect_fusion_signals()

	var app_id := _resolve_app_id()
	if app_id.is_empty():
		_set_status("Photon app ID is not configured. Set PHOTON_FUSION_APP_ID or fusion/connection/app_id locally.")
		return

	_fusion.call("set_app_id", app_id)
	_room_name = _resolve_room_name()

	if bool(_fusion.call("is_in_room")):
		_on_room_joined()
		return

	if bool(_fusion.call("is_connected_to_photon")):
		_join_or_create_room()
		return

	_set_status("Connecting to Photon Cloud for room '%s'." % _room_name)
	_fusion.call("connect_to_photon", _make_user_id(), _resolve_region(), app_version)


func leave_room() -> void:
	if _fusion == null or not bool(_fusion.call("is_in_room")):
		return

	_fusion.call("leave_room")


func is_in_room() -> bool:
	return _fusion != null and bool(_fusion.call("is_in_room"))


func get_local_player_id() -> int:
	if _fusion != null and bool(_fusion.call("is_in_room")):
		return int(_fusion.call("get_local_player_id"))
	return _local_player_id


func get_room_name() -> String:
	return _room_name


func get_player_ids() -> Array[int]:
	var player_ids: Array[int] = []
	var room := _get_room()
	if room == null:
		return player_ids

	var players: Array = room.call("get_players")
	for player in players:
		if player != null:
			player_ids.append(int(player.call("get_number")))

	return player_ids


func register_current_scene() -> void:
	if _fusion == null or not _fusion.has_method("register_current_scene"):
		return

	_fusion.call("register_current_scene")


func get_status() -> String:
	return _last_status


func _connect_fusion_signals() -> void:
	_connect_fusion_signal(&"connected_to_photon", &"_on_connected_to_photon")
	_connect_fusion_signal(&"connection_failed", &"_on_connection_failed")
	_connect_fusion_signal(&"connection_status_changed", &"_on_connection_status_changed")
	_connect_fusion_signal(&"room_joined", &"_on_room_joined")
	_connect_fusion_signal(&"room_left", &"_on_room_left")
	_connect_fusion_signal(&"player_joined", &"_on_player_joined")
	_connect_fusion_signal(&"player_left", &"_on_player_left")
	_connect_fusion_signal(&"master_client_changed", &"_on_master_client_changed")


func _connect_fusion_signal(signal_name: StringName, method_name: StringName) -> void:
	if not _fusion.has_signal(signal_name):
		return

	var callback := Callable(self, method_name)
	if not _fusion.is_connected(signal_name, callback):
		_fusion.connect(signal_name, callback)


func _resolve_app_id() -> String:
	var app_id := OS.get_environment("PHOTON_FUSION_APP_ID").strip_edges()
	if not app_id.is_empty():
		return app_id

	return str(ProjectSettings.get_setting(app_id_project_setting, "")).strip_edges()


func _resolve_room_name() -> String:
	var room_from_args := _get_cmdline_value("--pong-room").strip_edges()
	if not room_from_args.is_empty():
		return room_from_args

	var project_room := str(ProjectSettings.get_setting(room_name_project_setting, default_room_name)).strip_edges()
	if not project_room.is_empty():
		return project_room

	return default_room_name


func _resolve_region() -> String:
	var region_from_args := _get_cmdline_value("--photon-region").strip_edges()
	if not region_from_args.is_empty():
		return region_from_args

	return str(ProjectSettings.get_setting(region_project_setting, "")).strip_edges()


func _get_cmdline_value(flag: String) -> String:
	var args := OS.get_cmdline_args()
	var prefix := flag + "="
	for index in range(args.size()):
		var arg := args[index]
		if arg == flag and index + 1 < args.size():
			return args[index + 1]
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())

	return ""


func _make_user_id() -> String:
	var stable_id := OS.get_unique_id().strip_edges()
	if stable_id.is_empty():
		stable_id = str(Time.get_unix_time_from_system())

	return "quest-%s" % stable_id.sha256_text().substr(0, 12)


func _join_or_create_room() -> void:
	_set_status("Joining or creating private Photon room '%s'." % _room_name)
	_fusion.call("join_or_create_room", _room_name, _build_room_options())


func _build_room_options() -> Object:
	if not ClassDB.class_exists("FusionRoomOptions"):
		push_warning("[Photon] FusionRoomOptions class was not registered; joining with default options.")
		return null

	var options: Object = ClassDB.instantiate("FusionRoomOptions")
	options.set("is_open", true)
	options.set("is_visible", visible_room)
	options.set("max_players", max_players)
	options.set("player_ttl_ms", 0)
	options.set("empty_room_ttl_ms", 0)
	return options


func _get_room() -> Object:
	if _fusion == null or not bool(_fusion.call("is_in_room")):
		return null

	return _fusion.call("get_room")


func _refresh_room_visibility() -> void:
	var room := _get_room()
	if room == null:
		return

	var player_count := int(room.call("get_player_count"))
	room.call("set_open", player_count < max_players)
	room.call("set_visible", visible_room and player_count < max_players)


func _on_connected_to_photon() -> void:
	connected_to_photon.emit()
	_join_or_create_room()


func _on_connection_failed(reason: String) -> void:
	var message := "Photon connection failed: %s" % reason
	_set_status(message)
	connection_failed.emit(reason)


func _on_connection_status_changed(status: int) -> void:
	_set_status("Photon connection status changed: %d." % status)


func _on_room_joined() -> void:
	var room := _get_room()
	if room != null:
		_room_name = str(room.call("get_room_name"))

	_local_player_id = int(_fusion.call("get_local_player_id"))
	_refresh_room_visibility()
	_set_status("Joined Photon room '%s' as player %d." % [_room_name, _local_player_id])
	room_joined.emit(_room_name, _local_player_id)


func _on_room_left() -> void:
	_local_player_id = 0
	_set_status("Left Photon room.")
	room_left.emit()


func _on_player_joined(player_id: int, player_name: String) -> void:
	_refresh_room_visibility()
	player_joined.emit(player_id, player_name)
	_set_status("Player %d joined '%s'." % [player_id, _room_name])


func _on_player_left(player_id: int, is_inactive: bool) -> void:
	_refresh_room_visibility()
	player_left.emit(player_id, is_inactive)
	_set_status("Player %d left '%s'." % [player_id, _room_name])


func _on_master_client_changed(_previous_player_id: int, next_player_id: int) -> void:
	_set_status("Photon master client is now player %d." % next_player_id)


func _set_status(message: String) -> void:
	_last_status = message
	print("[Photon] %s" % message)
	status_changed.emit(message)
