extends RefCounted
class_name ShotTesterBallLauncher

const ComputerThrowPhysicsScript := preload("res://scripts/match/computer_throw_physics.gd")

const DIRECT_FALLBACK_ARC_HEIGHT := 0.42
const MIN_RELEASE_ANGLE_DEGREES := 8.0
const MAX_RELEASE_ANGLE_DEGREES := 88.0


static func build_launch_plan(
	ball: RigidBody3D,
	launch_transform: Transform3D,
	aim_position: Vector3,
	release_angle_degrees: float,
	aim_error_radius: float,
	angle_error_degrees: float,
	seed: int
) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var sampled_aim_error := _sample_horizontal_error(maxf(0.0, aim_error_radius), rng)
	var sampled_angle_error := _sample_signed_error(maxf(0.0, angle_error_degrees), rng)
	var effective_aim_position := aim_position + sampled_aim_error
	var effective_release_angle := clampf(
		release_angle_degrees + sampled_angle_error,
		MIN_RELEASE_ANGLE_DEGREES,
		MAX_RELEASE_ANGLE_DEGREES
	)
	var launch_velocity := ComputerThrowPhysicsScript.calculate_launch_velocity_for_ball_angle(
		ball,
		launch_transform.origin,
		effective_aim_position,
		effective_release_angle
	)
	var fallback_reason := ""
	if not ComputerThrowPhysicsScript.is_valid_launch_velocity(launch_velocity):
		fallback_reason = "angle_solver_invalid"
		launch_velocity = ComputerThrowPhysicsScript.calculate_launch_velocity_for_ball(
			ball,
			launch_transform.origin,
			effective_aim_position,
			DIRECT_FALLBACK_ARC_HEIGHT
		)

	var success := ComputerThrowPhysicsScript.is_valid_launch_velocity(launch_velocity)
	if not success and fallback_reason.is_empty():
		fallback_reason = "launch_velocity_invalid"

	return {
		"success": success,
		"seed": seed,
		"launch_transform": launch_transform,
		"aim_position": aim_position,
		"aim_error_radius": maxf(0.0, aim_error_radius),
		"sampled_aim_error": sampled_aim_error,
		"effective_aim_position": effective_aim_position,
		"release_angle_degrees": release_angle_degrees,
		"angle_error_degrees": maxf(0.0, angle_error_degrees),
		"sampled_angle_error_degrees": sampled_angle_error,
		"effective_release_angle_degrees": effective_release_angle,
		"launch_velocity": launch_velocity,
		"fallback_reason": fallback_reason,
	}


static func launch_ball(ball: RigidBody3D, launch_plan: Dictionary) -> void:
	if ball == null or not is_instance_valid(ball):
		return
	if not bool(launch_plan.get("success", false)):
		return

	ComputerThrowPhysicsScript.launch_ball(
		ball,
		launch_plan.get("launch_transform", Transform3D.IDENTITY),
		launch_plan.get("launch_velocity", Vector3.ZERO)
	)


static func reset_ball(ball: RigidBody3D, reset_transform: Transform3D, suspend_physics := true) -> void:
	ComputerThrowPhysicsScript.reset_ball(ball, reset_transform, suspend_physics)


static func _sample_horizontal_error(error_radius: float, rng: RandomNumberGenerator) -> Vector3:
	if error_radius <= 0.0:
		return Vector3.ZERO

	var miss_angle := rng.randf_range(0.0, TAU)
	var miss_distance := sqrt(rng.randf()) * error_radius
	return Vector3(cos(miss_angle) * miss_distance, 0.0, sin(miss_angle) * miss_distance)


static func _sample_signed_error(max_abs_error: float, rng: RandomNumberGenerator) -> float:
	if max_abs_error <= 0.0:
		return 0.0
	return rng.randf_range(-max_abs_error, max_abs_error)
