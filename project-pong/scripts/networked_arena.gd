extends Node
class_name NetworkedArena

@export var session_path: NodePath
@export var hand_spawner_path: NodePath
@export var match_state_path: NodePath
@export var left_controller_path: NodePath
@export var right_controller_path: NodePath
@export var status_label_path: NodePath
@export var network_hand_scene: PackedScene

var _session
var _hand_spawner: Node
var _match_state
var _left_controller: XRController3D
var _right_controller: XRController3D
var _status_label: Label3D
var _local_player_id := 0
var _spawned_local_hands := false


func _ready() -> void:
	_session = get_node_or_null(session_path)
	_hand_spawner = get_node_or_null(hand_spawner_path)
	_match_state = get_node_or_null(match_state_path)
	_left_controller = get_node_or_null(left_controller_path) as XRController3D
	_right_controller = get_node_or_null(right_controller_path) as XRController3D
	_status_label = get_node_or_null(status_label_path) as Label3D

	_configure_spawner()
	_connect_session()
	_set_status("Online Arena ready. Waiting for Photon room.")
	call_deferred("_start_session")


func _configure_spawner() -> void:
	if _hand_spawner == null:
		push_warning("[NetworkArena] FusionSpawner node is missing.")
		return

	if network_hand_scene != null and _hand_spawner.has_method("add_spawnable_scene"):
		_hand_spawner.call("add_spawnable_scene", network_hand_scene)


func _connect_session() -> void:
	if _session == null:
		_set_status("PhotonSession is missing from the online scene.")
		return

	_session.status_changed.connect(_on_session_status_changed)
	_session.room_joined.connect(_on_room_joined)
	_session.room_left.connect(_on_room_left)
	_session.player_joined.connect(_on_player_joined)
	_session.player_left.connect(_on_player_left)
	_session.connection_failed.connect(_on_connection_failed)


func _start_session() -> void:
	if _session != null and _session.has_method("start"):
		_session.start()


func _on_session_status_changed(message: String) -> void:
	_set_status(message)


func _on_room_joined(room_name: String, local_player_id: int) -> void:
	_local_player_id = local_player_id
	_session.register_current_scene()
	_set_status("Room '%s' joined as player %d. Spawning local hands." % [room_name, _local_player_id])
	_spawn_local_hands()


func _on_room_left() -> void:
	_local_player_id = 0
	_spawned_local_hands = false
	_set_status("Left online room.")


func _on_player_joined(player_id: int, _player_name: String) -> void:
	if player_id != _local_player_id:
		_set_status("Remote player %d joined. Their hands should appear when their rig spawns." % player_id)


func _on_player_left(player_id: int, _is_inactive: bool) -> void:
	_set_status("Player %d left the online room." % player_id)


func _on_connection_failed(reason: String) -> void:
	_set_status("Photon connection failed: %s" % reason)


func _spawn_local_hands() -> void:
	if _spawned_local_hands:
		return

	if network_hand_scene == null:
		_set_status("Network hand scene is not assigned.")
		return

	if _hand_spawner == null or not _hand_spawner.has_method("spawn"):
		_set_status("FusionSpawner is unavailable; cannot spawn network hands.")
		return

	_spawn_network_hand(_left_controller, "P%d Left" % _local_player_id, Color(0.2, 0.85, 1.0, 1.0))
	_spawn_network_hand(_right_controller, "P%d Right" % _local_player_id, Color(1.0, 0.42, 0.28, 1.0))
	_spawned_local_hands = true


func _spawn_network_hand(controller: XRController3D, label_text: String, color: Color) -> void:
	if controller == null:
		push_warning("[NetworkArena] Cannot spawn %s because its source controller is missing." % label_text)
		return

	var spawned := _hand_spawner.call("spawn", network_hand_scene) as Node
	if spawned == null:
		push_warning("[NetworkArena] FusionSpawner returned no node for %s." % label_text)
		return

	spawned.name = "%sNetworkHand" % label_text.replace(" ", "")
	if spawned.has_method("configure_local"):
		spawned.call("configure_local", controller, label_text, color)


func _set_status(message: String) -> void:
	print("[NetworkArena] %s" % message)
	if _status_label != null:
		var match_suffix := ""
		if _match_state != null and _match_state.ball_authority_player_id > 0:
			match_suffix = "\nBall authority placeholder: P%d" % _match_state.ball_authority_player_id
		_status_label.text = "%s%s" % [message, match_suffix]
