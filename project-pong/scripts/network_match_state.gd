extends Node
class_name NetworkMatchState

signal players_changed(player_ids: Array[int])
signal ball_authority_changed(player_id: int)

@export var session_path: NodePath

var player_ids: Array[int] = []
var ball_authority_player_id := 0

var _session


func _ready() -> void:
	_session = get_node_or_null(session_path)
	if _session == null:
		push_warning("[MatchState] PhotonSession was not found; match state is idle.")
		return

	_session.room_joined.connect(_on_room_joined)
	_session.player_joined.connect(_on_player_joined)
	_session.player_left.connect(_on_player_left)
	_session.room_left.connect(_on_room_left)


func get_ball_authority_player_id() -> int:
	return ball_authority_player_id


func _on_room_joined(_room_name: String, local_player_id: int) -> void:
	_refresh_players()
	if ball_authority_player_id == 0:
		_set_ball_authority(local_player_id)


func _on_player_joined(_player_id: int, _player_name: String) -> void:
	_refresh_players()


func _on_player_left(player_id: int, _is_inactive: bool) -> void:
	_refresh_players()
	if ball_authority_player_id == player_id:
		_set_ball_authority(player_ids[0] if not player_ids.is_empty() else 0)


func _on_room_left() -> void:
	player_ids.clear()
	_set_ball_authority(0)
	players_changed.emit(player_ids)


func _refresh_players() -> void:
	if _session == null:
		return

	player_ids = _session.get_player_ids()
	player_ids.sort()
	players_changed.emit(player_ids)
	print("[MatchState] Players in room: %s" % [player_ids])


func _set_ball_authority(player_id: int) -> void:
	if ball_authority_player_id == player_id:
		return

	ball_authority_player_id = player_id
	ball_authority_changed.emit(ball_authority_player_id)
	print("[MatchState] Ball authority placeholder set to player %d." % ball_authority_player_id)
