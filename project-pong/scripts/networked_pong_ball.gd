extends ThrowableBall
class_name NetworkedPongBall

signal authority_changed(player_id: int)

@export var authority_send_interval := 1

@onready var _replicator: Node = get_node_or_null("FusionSharedReplicator")

var _local_player_id := 0
var _active_player_id := 0
var _match_active := false
var _turn_shots_remaining := 0
var _authority_player_id := 0
var _last_denial_log_msec := 0


func _ready() -> void:
	super._ready()
	_connect_replicator_signals()


func configure_turn(local_player_id: int, active_player_id: int, match_active: bool, shots_remaining: int) -> void:
	_local_player_id = local_player_id
	_active_player_id = active_player_id
	_match_active = match_active
	_turn_shots_remaining = shots_remaining

	if can_local_player_control():
		_request_authority()


func prepare_grab_check(_grabber: Node3D) -> void:
	if _match_active and _local_player_id > 0 and _local_player_id == _active_player_id:
		_request_authority()


func can_be_grabbed_by(_grabber: Node3D) -> bool:
	var can_grab := can_local_player_control()
	if not can_grab:
		_log_grab_denied()
	return can_grab


func can_local_player_control() -> bool:
	return (
		_match_active
		and _local_player_id > 0
		and _local_player_id == _active_player_id
		and _turn_shots_remaining > 0
	)


func reset_for_turn(reset_transform: Transform3D, suspend_physics := true) -> void:
	reset_to_transform(reset_transform, suspend_physics)
	if can_local_player_control():
		_request_authority()


func on_grabbed(grabber: Node3D) -> void:
	if not can_be_grabbed_by(grabber):
		return

	_request_authority()
	super.on_grabbed(grabber)


func on_released(grabber: Node3D, release_linear_velocity: Vector3, release_angular_velocity: Vector3) -> void:
	if not can_local_player_control():
		reset_to_transform(global_transform, true)
		return

	super.on_released(grabber, release_linear_velocity, release_angular_velocity)


func _connect_replicator_signals() -> void:
	if _replicator == null:
		push_warning("[NetworkBall] Missing FusionSharedReplicator child; ball will only work locally.")
		return

	_connect_replicator_signal(&"authority_changed", &"_on_authority_changed")
	_connect_replicator_signal(&"authority_requested", &"_on_authority_requested")
	_connect_replicator_signal(&"spawned", &"_on_spawned")


func _connect_replicator_signal(signal_name: StringName, method_name: StringName) -> void:
	if not _replicator.has_signal(signal_name):
		return

	var callback := Callable(self, method_name)
	if not _replicator.is_connected(signal_name, callback):
		_replicator.connect(signal_name, callback)


func _request_authority() -> void:
	if _replicator == null or not _replicator.has_method("want_authority"):
		return

	_replicator.call("want_authority", true, authority_send_interval)


func _log_grab_denied() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_denial_log_msec < 1000:
		return

	_last_denial_log_msec = now
	print("[NetworkBall] Grab denied. local=%d active=%d match=%s shots=%d authority_owner=%d" % [
		_local_player_id,
		_active_player_id,
		_match_active,
		_turn_shots_remaining,
		_authority_player_id,
	])


func _refresh_authority_owner() -> void:
	if _replicator == null or not _replicator.has_method("get_owner_id"):
		return

	_authority_player_id = int(_replicator.call("get_owner_id"))
	authority_changed.emit(_authority_player_id)


func _on_spawned() -> void:
	if can_local_player_control():
		_request_authority()
	_refresh_authority_owner()


func _on_authority_changed(_has_authority: bool) -> void:
	_refresh_authority_owner()
	print("[NetworkBall] Authority owner is player %d." % _authority_player_id)


func _on_authority_requested(requester_player_id: int, _is_locked: bool) -> bool:
	return _match_active and requester_player_id == _active_player_id
