extends RefCounted
class_name ShotScoreTracker

var _candidate: Node3D


func reset() -> void:
	_candidate = null


func confirm_contact_candidate(candidate: Node3D) -> Node3D:
	if candidate == null or not is_instance_valid(candidate):
		_candidate = null
		return null

	_candidate = candidate
	return _candidate


func get_candidate() -> Node3D:
	return _candidate
