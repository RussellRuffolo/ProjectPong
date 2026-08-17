extends RefCounted
class_name ShotAttemptEvaluator


static func is_miss(
	ball: RigidBody3D,
	attempt_elapsed: float,
	config: Dictionary,
	score_contact_candidate: Node3D,
	ball_is_settled: bool
) -> bool:
	if ball == null or not is_instance_valid(ball):
		return true

	var position := ball.global_position
	if position.y < float(config.get("miss_height", -INF)):
		return true
	if absf(position.x) > float(config.get("out_of_bounds_x", INF)):
		return true
	if position.z < float(config.get("out_of_bounds_z_min", -INF)):
		return true
	if position.z > float(config.get("out_of_bounds_z_max", INF)):
		return true
	if attempt_elapsed >= float(config.get("max_attempt_seconds", INF)):
		return true
	if (
		attempt_elapsed >= float(config.get("settled_after_seconds", INF))
		and ball_is_settled
		and score_contact_candidate == null
	):
		return true

	return false
