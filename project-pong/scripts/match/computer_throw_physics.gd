extends RefCounted
class_name ComputerThrowPhysics

const ComputerTargetSelectorScript := preload("res://scripts/match/computer_target_selector.gd")
const ShotPhysicsScript := preload("res://scripts/match/shot_physics.gd")


static func select_target_cup(target_rack_state, heuristic: String, origin: Vector3, rng: RandomNumberGenerator = null) -> Node3D:
	return ComputerTargetSelectorScript.select_target(target_rack_state, heuristic, origin, rng)


static func calculate_aim_position(
	target_cup: Node3D,
	accuracy_error_radius: float,
	rng: RandomNumberGenerator,
	aim_top_clearance: float
) -> Vector3:
	var aim_position := get_cup_rim_center_position(target_cup) + Vector3.UP * aim_top_clearance
	if accuracy_error_radius <= 0.0 or rng == null:
		return aim_position

	var miss_angle := rng.randf_range(0.0, TAU)
	var miss_distance := sqrt(rng.randf()) * accuracy_error_radius
	aim_position.x += cos(miss_angle) * miss_distance
	aim_position.z += sin(miss_angle) * miss_distance
	return aim_position


static func calculate_launch_velocity_for_ball(
	ball: RigidBody3D,
	start_position: Vector3,
	target_position: Vector3,
	arc_height: float
) -> Vector3:
	return calculate_launch_velocity(
		start_position,
		target_position,
		_get_ball_flight_gravity_scale(ball),
		arc_height
	)


static func calculate_launch_velocity_for_ball_angle(
	ball: RigidBody3D,
	start_position: Vector3,
	target_position: Vector3,
	release_angle_degrees: float
) -> Vector3:
	var launch_velocity := calculate_launch_velocity_with_release_angle(
		start_position,
		target_position,
		_get_ball_flight_gravity_scale(ball),
		release_angle_degrees
	)
	return _apply_linear_damp_compensation(ball, start_position, target_position, launch_velocity)


static func calculate_bounce_launch_velocity(
	ball: RigidBody3D,
	start_position: Vector3,
	bounce_position: Vector3,
	_target_position: Vector3,
	release_angle_degrees: float,
	_bounce_target_height: float
) -> Vector3:
	return calculate_launch_velocity_for_ball_angle(
		ball,
		start_position,
		bounce_position,
		release_angle_degrees
	)


static func find_bounce_aim_point(
	ball: RigidBody3D,
	start_position: Vector3,
	target_position: Vector3,
	table_bounds: Dictionary,
	profile: Resource,
	release_angle_degrees := -1.0
) -> Dictionary:
	var surface_y := float(table_bounds.get("surface_y", minf(start_position.y, target_position.y)))
	var ball_radius := get_ball_radius(ball)
	var bounce_y := surface_y + ball_radius
	var angle_degrees := release_angle_degrees
	if angle_degrees <= 0.0 and profile != null:
		angle_degrees = float(profile.get("bounce_release_angle_degrees"))
	if angle_degrees <= 0.0:
		angle_degrees = 28.0

	var best_solution: Dictionary = {}
	var best_score := INF
	var sample_count := 18
	for sample_index in range(sample_count):
		var ratio := lerpf(0.38, 0.82, float(sample_index) / float(sample_count - 1))
		var bounce_position := start_position.lerp(target_position, ratio)
		bounce_position.y = bounce_y
		if not _is_bounce_position_in_bounds(bounce_position, table_bounds):
			continue

		var launch_velocity := calculate_launch_velocity_for_ball_angle(
			ball,
			start_position,
			bounce_position,
			angle_degrees
		)
		if not is_valid_launch_velocity(launch_velocity):
			continue

		var prediction := _predict_post_bounce_target(
			ball,
			start_position,
			bounce_position,
			target_position,
			launch_velocity,
			table_bounds,
			profile
		)
		if not bool(prediction.get("success", false)):
			continue

		var score := float(prediction.get("score", INF))
		if score < best_score:
			best_score = score
			best_solution = {
				"success": true,
				"bounce_position": bounce_position,
				"launch_velocity": launch_velocity,
				"predicted_position": prediction.get("predicted_position", Vector3.ZERO),
				"predicted_error": float(prediction.get("horizontal_error", INF)),
				"predicted_apex_height": float(prediction.get("apex_height", 0.0)),
				"score": score,
				"candidate_index": sample_index,
			}

	if best_solution.is_empty():
		return {
			"success": false,
			"failure_reason": "no_valid_bounce_candidate",
		}

	return best_solution


static func calculate_launch_velocity_with_release_angle(
	start_position: Vector3,
	target_position: Vector3,
	gravity_scale: float,
	release_angle_degrees: float
) -> Vector3:
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * gravity_scale
	gravity = maxf(gravity, 0.01)

	var horizontal_delta := target_position - start_position
	horizontal_delta.y = 0.0
	var horizontal_distance := horizontal_delta.length()
	if horizontal_distance <= 0.001:
		return Vector3.ZERO

	var angle_radians := deg_to_rad(clampf(release_angle_degrees, 1.0, 89.0))
	var cos_theta := cos(angle_radians)
	var tan_theta := tan(angle_radians)
	var delta_y := target_position.y - start_position.y
	var denominator := 2.0 * cos_theta * cos_theta * (horizontal_distance * tan_theta - delta_y)
	if denominator <= 0.0001:
		return Vector3.ZERO

	var speed_squared := gravity * horizontal_distance * horizontal_distance / denominator
	if speed_squared <= 0.0 or not _is_finite_float(speed_squared):
		return Vector3.ZERO

	var speed := sqrt(speed_squared)
	var horizontal_direction := horizontal_delta / horizontal_distance
	return (
		horizontal_direction * speed * cos_theta
		+ Vector3.UP * speed * sin(angle_radians)
	)


static func calculate_launch_velocity(
	start_position: Vector3,
	target_position: Vector3,
	gravity_scale: float,
	arc_height: float
) -> Vector3:
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * gravity_scale
	gravity = maxf(gravity, 0.01)
	var peak_y := maxf(start_position.y, target_position.y) + maxf(0.01, arc_height)
	var vertical_speed := sqrt(2.0 * gravity * maxf(0.01, peak_y - start_position.y))
	var time_up := vertical_speed / gravity
	var time_down := sqrt(2.0 * maxf(0.01, peak_y - target_position.y) / gravity)
	var travel_time := maxf(0.1, time_up + time_down)
	var horizontal_delta := target_position - start_position
	horizontal_delta.y = 0.0
	return Vector3(
		horizontal_delta.x / travel_time,
		vertical_speed,
		horizontal_delta.z / travel_time
	)


static func reset_ball(ball: RigidBody3D, reset_transform: Transform3D, suspend_physics := true) -> void:
	if ball == null or not is_instance_valid(ball):
		return

	if ball.has_method("reset_to_transform"):
		ball.call("reset_to_transform", reset_transform, suspend_physics)
	else:
		ball.freeze = false
		ball.global_transform = reset_transform
		ball.linear_velocity = Vector3.ZERO
		ball.angular_velocity = Vector3.ZERO
		ball.sleeping = false
		ball.gravity_scale = 0.0 if suspend_physics else maxf(ball.gravity_scale, 1.0)


static func launch_ball(ball: RigidBody3D, launch_transform: Transform3D, launch_velocity: Vector3) -> void:
	if ball == null or not is_instance_valid(ball):
		return

	reset_ball(ball, launch_transform, false)
	ball.linear_velocity = launch_velocity
	ball.angular_velocity = _get_ball_release_spin(ball)
	ball.sleeping = false


static func get_cup_rim_center_position(cup: Node3D) -> Vector3:
	if cup != null and cup.has_method("get_rim_center_position"):
		var rim_position: Variant = cup.call("get_rim_center_position")
		if rim_position is Vector3:
			return rim_position
	return get_cup_top_center_position(cup)


static func get_cup_top_center_position(cup: Node3D) -> Vector3:
	if cup != null and cup.has_method("get_top_center_position"):
		var top_position: Variant = cup.call("get_top_center_position")
		if top_position is Vector3:
			return top_position
	return cup.global_position if cup != null else Vector3.ZERO


static func is_valid_launch_velocity(launch_velocity: Vector3) -> bool:
	return (
		_is_finite_float(launch_velocity.x)
		and _is_finite_float(launch_velocity.y)
		and _is_finite_float(launch_velocity.z)
		and launch_velocity.length_squared() > 0.0001
		and launch_velocity.length_squared() < 900.0
	)


static func get_ball_radius(ball: RigidBody3D) -> float:
	return ShotPhysicsScript.get_ball_radius(ball)


static func _get_ball_flight_gravity_scale(ball: RigidBody3D) -> float:
	if ball == null or not is_instance_valid(ball):
		return 1.0

	var gravity_scale_value: Variant = ball.get("flight_gravity_scale")
	if gravity_scale_value is float or gravity_scale_value is int:
		return float(gravity_scale_value)
	return maxf(ball.gravity_scale, 1.0)


static func _get_ball_flight_linear_damp(ball: RigidBody3D) -> float:
	if ball == null or not is_instance_valid(ball):
		return 0.0

	var damp_value: Variant = ball.get("flight_linear_damp")
	if damp_value is float or damp_value is int:
		return maxf(0.0, float(damp_value))
	return maxf(0.0, ball.linear_damp)


static func _get_ball_release_spin(ball: RigidBody3D) -> Vector3:
	if ball == null or not is_instance_valid(ball):
		return Vector3.ZERO

	var release_spin_value: Variant = ball.get("release_spin")
	if release_spin_value is Vector3:
		return release_spin_value
	return Vector3.ZERO


static func _apply_linear_damp_compensation(
	ball: RigidBody3D,
	start_position: Vector3,
	target_position: Vector3,
	launch_velocity: Vector3
) -> Vector3:
	if not is_valid_launch_velocity(launch_velocity):
		return launch_velocity

	var linear_damp := _get_ball_flight_linear_damp(ball)
	if linear_damp <= 0.0:
		return launch_velocity

	var horizontal_delta := target_position - start_position
	horizontal_delta.y = 0.0
	var horizontal_speed := Vector2(launch_velocity.x, launch_velocity.z).length()
	if horizontal_delta.length() <= 0.001 or horizontal_speed <= 0.001:
		return launch_velocity

	var travel_time := horizontal_delta.length() / horizontal_speed
	var compensation := clampf(exp(linear_damp * travel_time * 2.5), 1.0, 2.0)
	var compensated_velocity := launch_velocity
	compensated_velocity.x *= compensation
	compensated_velocity.z *= compensation
	return compensated_velocity


static func _predict_post_bounce_target(
	ball: RigidBody3D,
	start_position: Vector3,
	bounce_position: Vector3,
	target_position: Vector3,
	launch_velocity: Vector3,
	table_bounds: Dictionary,
	profile: Resource
) -> Dictionary:
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * _get_ball_flight_gravity_scale(ball)
	gravity = maxf(gravity, 0.01)

	var horizontal_to_bounce := bounce_position - start_position
	horizontal_to_bounce.y = 0.0
	var horizontal_speed := Vector2(launch_velocity.x, launch_velocity.z).length()
	if horizontal_to_bounce.length() <= 0.001 or horizontal_speed <= 0.001:
		return {"success": false}

	var time_to_bounce := horizontal_to_bounce.length() / horizontal_speed
	var incoming_y_velocity := launch_velocity.y - gravity * time_to_bounce
	if incoming_y_velocity >= -0.01:
		return {"success": false}

	var restitution := _get_effective_table_bounce(ball, table_bounds)
	var friction := _get_effective_table_friction(ball, table_bounds)
	var horizontal_damping := clampf(1.0 - friction * 0.12, 0.65, 1.0)
	var post_bounce_y_velocity := -incoming_y_velocity * restitution
	var post_bounce_horizontal_velocity := Vector3(launch_velocity.x, 0.0, launch_velocity.z) * horizontal_damping
	var time_to_target_height := _solve_time_for_height(
		bounce_position.y,
		target_position.y,
		post_bounce_y_velocity,
		gravity
	)
	if time_to_target_height <= 0.0:
		return {"success": false}

	var predicted_position := bounce_position + post_bounce_horizontal_velocity * time_to_target_height
	predicted_position.y = target_position.y
	var horizontal_error := Vector2(
		predicted_position.x - target_position.x,
		predicted_position.z - target_position.z
	).length()
	var apex_height := bounce_position.y + post_bounce_y_velocity * post_bounce_y_velocity / (2.0 * gravity)
	var desired_height := _get_profile_bounce_target_height(profile, get_ball_radius(ball))
	var height_error := absf((apex_height - float(table_bounds.get("surface_y", bounce_position.y))) - desired_height)

	return {
		"success": true,
		"predicted_position": predicted_position,
		"horizontal_error": horizontal_error,
		"apex_height": apex_height,
		"score": horizontal_error + height_error * 0.2,
	}


static func _is_bounce_position_in_bounds(bounce_position: Vector3, table_bounds: Dictionary) -> bool:
	return (
		bounce_position.x >= float(table_bounds.get("x_min", -INF))
		and bounce_position.x <= float(table_bounds.get("x_max", INF))
		and bounce_position.z >= float(table_bounds.get("z_min", -INF))
		and bounce_position.z <= float(table_bounds.get("z_max", INF))
	)


static func _solve_time_for_height(start_y: float, target_y: float, start_y_velocity: float, gravity: float) -> float:
	var discriminant := start_y_velocity * start_y_velocity - 2.0 * gravity * (target_y - start_y)
	if discriminant < 0.0:
		return -1.0

	var sqrt_discriminant := sqrt(discriminant)
	var first_time := (start_y_velocity - sqrt_discriminant) / gravity
	var second_time := (start_y_velocity + sqrt_discriminant) / gravity
	var best_time := INF
	if first_time > 0.001:
		best_time = first_time
	if second_time > 0.001 and second_time < best_time:
		best_time = second_time
	return best_time if best_time < INF else -1.0


static func _get_effective_table_bounce(ball: RigidBody3D, table_bounds: Dictionary) -> float:
	var ball_bounce := 0.55
	if ball != null and is_instance_valid(ball):
		var bounce_value: Variant = ball.get("bounce")
		if bounce_value is float or bounce_value is int:
			ball_bounce = float(bounce_value)

	var surface_bounce := float(table_bounds.get("surface_bounce", 0.04))
	return clampf(maxf(ball_bounce, surface_bounce), 0.05, 0.95)


static func _get_effective_table_friction(ball: RigidBody3D, table_bounds: Dictionary) -> float:
	var ball_friction := 0.12
	if ball != null and is_instance_valid(ball):
		var friction_value: Variant = ball.get("friction")
		if friction_value is float or friction_value is int:
			ball_friction = float(friction_value)

	var surface_friction := float(table_bounds.get("surface_friction", 0.28))
	return clampf((ball_friction + surface_friction) * 0.5, 0.0, 1.0)


static func _get_profile_bounce_target_height(profile: Resource, ball_radius: float) -> float:
	if profile == null:
		return maxf(ball_radius, 0.06)

	var height_value: Variant = profile.get("bounce_target_height")
	if height_value is float or height_value is int:
		return maxf(ball_radius, float(height_value))
	return maxf(ball_radius, 0.06)


static func _is_finite_float(value: float) -> bool:
	return value == value and absf(value) < 100000.0
