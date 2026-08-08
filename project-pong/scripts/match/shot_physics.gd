extends RefCounted
class_name ShotPhysics

const MatchConstants := preload("res://scripts/match/pong_match_constants.gd")


static func is_ball_settled(
	ball: RigidBody3D,
	settled_speed: float,
	angular_multiplier := MatchConstants.DEFAULT_ANGULAR_SETTLE_MULTIPLIER
) -> bool:
	if ball == null or not is_instance_valid(ball):
		return false

	return (
		ball.linear_velocity.length() <= settled_speed
		and ball.angular_velocity.length() <= settled_speed * angular_multiplier
	)
