extends Node
class_name PhotonSession

signal status_changed(message: String)
signal connected_to_photon()
signal room_list_changed(rooms: Array[Dictionary])
signal room_joined(room_name: String, local_player_id: int)
signal room_left()
signal player_joined(player_id: int, player_name: String)
signal player_left(player_id: int, is_inactive: bool)
signal connection_failed(reason: String)

@export var auto_connect := true
@export var join_default_room_on_start := true
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
var _should_join_default_room := false


func _ready() -> void:
	if auto_connect:
		start()


func start() -> void:
	connect_to_photon(join_default_room_on_start)


func connect_to_photon(join_default_room := false) -> void:
	if not Engine.has_singleton("Fusion"):
		_set_status("Photon Fusion singleton is unavailable. Check addons/fusion installation.")
		return

	_fusion = Engine.get_singleton("Fusion")
	_connect_fusion_signals()
	_should_join_default_room = join_default_room

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
		_on_connected_to_photon()
		return

	_set_status("Connecting to Photon Cloud.")
	_fusion.call("connect_to_photon", _make_user_id(), _resolve_region(), app_version)


func create_room(room_name := "") -> void:
	if not _can_join_room():
		return

	_room_name = _make_room_name() if room_name.strip_edges().is_empty() else room_name.strip_edges()
	_set_status("Creating visible private Photon room '%s'." % _room_name)
	_fusion.call("create_room", _room_name, _build_room_options())


func join_room(room_name: String) -> void:
	if not _can_join_room():
		return

	_room_name = room_name.strip_edges()
	if _room_name.is_empty():
		_set_status("Cannot join a Photon room without a room name.")
		return

	_set_status("Joining Photon room '%s'." % _room_name)
	_fusion.call("join_room", _room_name, _build_room_options())


func join_or_create_default_room() -> void:
	if not _can_join_room():
		return

	_room_name = _resolve_room_name()
	_join_or_create_room()


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


func refresh_room_list() -> void:
	if _fusion == null or not bool(_fusion.call("is_connected_to_photon")):
		room_list_changed.emit([])
		return

	_emit_room_list(_fusion.call("get_room_list"))


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


func register_broadcast_receiver(receiver: Node) -> void:
	if _fusion == null or receiver == null or not _fusion.has_method("register_broadcast_receiver"):
		return

	_fusion.call("register_broadcast_receiver", receiver)


func unregister_broadcast_receiver(receiver: Node) -> void:
	if _fusion == null or receiver == null or not _fusion.has_method("unregister_broadcast_receiver"):
		return

	_fusion.call("unregister_broadcast_receiver", receiver)


func broadcast_rpc(receiver: Object, method_name: StringName, args: Array = []) -> bool:
	if _fusion == null or receiver == null or not _fusion.has_method("rpc"):
		return false
	if not bool(_fusion.call("is_in_room")):
		return false

	var rpc_args: Array = [Callable(receiver, method_name)]
	rpc_args.append_array(args)
	_fusion.callv("rpc", rpc_args)
	return true


func is_master_client() -> bool:
	return _fusion != null and bool(_fusion.call("is_master_client"))


func get_status() -> String:
	return _last_status


func _connect_fusion_signals() -> void:
	_connect_fusion_signal(&"connected_to_photon", &"_on_connected_to_photon")
	_connect_fusion_signal(&"connection_failed", &"_on_connection_failed")
	_connect_fusion_signal(&"connection_status_changed", &"_on_connection_status_changed")
	_connect_fusion_signal(&"room_list_updated", &"_on_room_list_updated")
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


func _make_room_name() -> String:
	var random_suffix := "%04d" % randi_range(0, 9999)
	var time_suffix := str(Time.get_unix_time_from_system()).right(5)
	return "pong-%s-%s" % [time_suffix, random_suffix]


func _make_user_id() -> String:
	var stable_id := OS.get_unique_id().strip_edges()
	if stable_id.is_empty():
		stable_id = str(Time.get_unix_time_from_system())

	return "quest-%s" % stable_id.sha256_text().substr(0, 12)


func _can_join_room() -> bool:
	if _fusion == null:
		_set_status("Photon Fusion is not initialized yet.")
		return false

	if bool(_fusion.call("is_in_room")):
		_set_status("Already in Photon room '%s'." % _room_name)
		return false

	if not bool(_fusion.call("is_connected_to_photon")):
		_set_status("Photon Cloud is not connected yet.")
		return false

	return true


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
	options.set("custom_properties", {
		"mode": "project_pong_private",
		"ruleset": "classic",
	})
	options.set("lobby_properties", ["mode", "ruleset"])
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
	_set_status("Connected to Photon Cloud.")
	connected_to_photon.emit()
	refresh_room_list()
	if _should_join_default_room:
		_join_or_create_room()


func _on_connection_failed(reason: String) -> void:
	var message := "Photon connection failed: %s" % reason
	_set_status(message)
	connection_failed.emit(reason)


func _on_connection_status_changed(status: int) -> void:
	_set_status("Photon connection status changed: %d." % status)


func _on_room_list_updated(_raw_rooms: Array) -> void:
	refresh_room_list()


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
	refresh_room_list()
	player_joined.emit(player_id, player_name)
	_set_status("Player %d joined '%s'." % [player_id, _room_name])


func _on_player_left(player_id: int, is_inactive: bool) -> void:
	_refresh_room_visibility()
	refresh_room_list()
	player_left.emit(player_id, is_inactive)
	_set_status("Player %d left '%s'." % [player_id, _room_name])


func _on_master_client_changed(_previous_player_id: int, next_player_id: int) -> void:
	_set_status("Photon master client is now player %d." % next_player_id)


func _set_status(message: String) -> void:
	_last_status = message
	print("[Photon] %s" % message)
	status_changed.emit(message)


func _emit_room_list(raw_rooms: Variant) -> void:
	var rooms: Array[Dictionary] = []
	var listings: Array = raw_rooms if raw_rooms is Array else []
	for listing in listings:
		var room := _room_listing_to_dict(listing)
		if room.is_empty():
			continue

		rooms.append(room)

	room_list_changed.emit(rooms)


func _room_listing_to_dict(listing: Variant) -> Dictionary:
	if listing == null:
		return {}

	var room_name := str(listing.call("get_name"))
	var player_count := int(listing.call("get_player_count"))
	var listing_max_players := int(listing.call("get_max_players"))
	var is_open := bool(listing.call("get_is_open"))
	var properties: Dictionary = {}
	if listing.has_method("get_custom_properties"):
		properties = listing.call("get_custom_properties")

	return {
		"name": room_name,
		"player_count": player_count,
		"max_players": listing_max_players,
		"is_open": is_open,
		"is_joinable": is_open and player_count < listing_max_players and listing_max_players == max_players,
		"mode": str(properties.get("mode", "")),
		"ruleset": str(properties.get("ruleset", "")),
	}
