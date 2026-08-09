extends RefCounted
class_name ShotScoreTracker


var _candidate: Node3D
var _settled_elapsed := 0.0


func reset() -> void:
	_candidate = null
	_settled_elapsed = 0.0


func update(delta: float, resting_cup: Node3D, ball_is_settled: bool, scoring_settle_seconds: float) -> Node3D:
	if resting_cup == null:
		reset()
		return null

	if resting_cup.has_method("is_score_capture_confirmed") and bool(resting_cup.call("is_score_capture_confirmed")):
		return resting_cup

	if not ball_is_settled:
		reset()
		return null

	if resting_cup != _candidate:
		_candidate = resting_cup
		_settled_elapsed = 0.0

	_settled_elapsed += delta
	if _settled_elapsed < scoring_settle_seconds:
		return null

	return resting_cup


func get_candidate() -> Node3D:
	return _candidate
