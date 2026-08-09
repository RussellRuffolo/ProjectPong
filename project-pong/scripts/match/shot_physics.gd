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


static func get_ball_radius(ball: RigidBody3D, fallback_radius := 0.02) -> float:
	if ball == null or not is_instance_valid(ball):
		return fallback_radius

	for child in ball.get_children():
		var collision_shape := child as CollisionShape3D
		if collision_shape == null or collision_shape.shape == null:
			continue

		var sphere_shape := collision_shape.shape as SphereShape3D
		if sphere_shape != null:
			return sphere_shape.radius

	return fallback_radius
