extends RefCounted
class_name ComputerThrowPlanner

const ComputerPlayerProfileScript := preload("res://scripts/match/computer_player_profile.gd")
const ComputerThrowPhysicsScript := preload("res://scripts/match/computer_throw_physics.gd")
const HouseRuleIdsScript := preload("res://scripts/house_rules/house_rule_ids.gd")

const SHOT_TYPE_DIRECT := "direct"
const SHOT_TYPE_BOUNCE := "bounce"
const DIRECT_FALLBACK_ARC_HEIGHT := 0.42
const MIN_RELEASE_ANGLE_DEGREES := 8.0
const MAX_RELEASE_ANGLE_DEGREES := 88.0


static func build_throw_plan(config: Dictionary) -> Dictionary:
	var profile = _get_profile(config)
	var target_rack_state = config.get("target_rack_state", null)
	var ball := config.get("ball", null) as RigidBody3D
	var launch_transform: Transform3D = config.get("launch_transform", Transform3D.IDENTITY)
	var rng := config.get("rng", null) as RandomNumberGenerator
	if rng == null:
		rng = RandomNumberGenerator.new()

	var target_cup := ComputerThrowPhysicsScript.select_target_cup(
		target_rack_state,
		profile.target_heuristic,
		launch_transform.origin,
		rng
	)
	if target_cup == null:
		return {
			"success": false,
			"failure_reason": "no_target_cup",
			"profile_id": profile.get_profile_id_string(),
			"shot_type": SHOT_TYPE_DIRECT,
		}

	var bounce_decision := _get_bounce_decision(profile, config, rng)
	if bool(bounce_decision.get("attempt", false)):
		var bounce_plan := _build_bounce_plan(profile, ball, launch_transform, target_cup, rng, config, bounce_decision)
		if bool(bounce_plan.get("success", false)):
			return bounce_plan

	var direct_plan := _build_direct_plan(profile, ball, launch_transform, target_cup, rng)
	direct_plan["bounce_allowed"] = bool(bounce_decision.get("allowed", false))
	direct_plan["bounce_attempted"] = bool(bounce_decision.get("attempt", false))
	direct_plan["bounce_roll"] = float(bounce_decision.get("roll", 1.0))
	if bool(bounce_decision.get("attempt", false)) and str(direct_plan.get("fallback_reason", "")).is_empty():
		direct_plan["fallback_reason"] = "bounce_plan_unavailable"
	return direct_plan


static func _build_direct_plan(
	profile,
	ball: RigidBody3D,
	launch_transform: Transform3D,
	target_cup: Node3D,
	rng: RandomNumberGenerator
) -> Dictionary:
	var target_position := ComputerThrowPhysicsScript.get_cup_rim_center_position(target_cup)
	var aim_error := _sample_horizontal_error(profile.direct_aim_error_radius, rng)
	var aim_position := target_position + aim_error
	var angle_error_degrees := _sample_signed_error(profile.direct_angle_error_degrees, rng)
	var release_angle_degrees := clampf(
		profile.direct_release_angle_degrees + angle_error_degrees,
		MIN_RELEASE_ANGLE_DEGREES,
		MAX_RELEASE_ANGLE_DEGREES
	)
	var launch_velocity := ComputerThrowPhysicsScript.calculate_launch_velocity_for_ball_angle(
		ball,
		launch_transform.origin,
		aim_position,
		release_angle_degrees
	)
	var fallback_reason := ""
	if not ComputerThrowPhysicsScript.is_valid_launch_velocity(launch_velocity):
		launch_velocity = ComputerThrowPhysicsScript.calculate_launch_velocity_for_ball(
			ball,
			launch_transform.origin,
			aim_position,
			DIRECT_FALLBACK_ARC_HEIGHT
		)
		fallback_reason = "angle_solver_invalid"

	return {
		"success": true,
		"profile_id": profile.get_profile_id_string(),
		"display_name": profile.display_name,
		"shot_type": SHOT_TYPE_DIRECT,
		"target_cup": target_cup,
		"target_cup_index": _get_cup_index(target_cup),
		"target_position": target_position,
		"aim_position": aim_position,
		"bounce_position": Vector3.ZERO,
		"release_angle_degrees": release_angle_degrees,
		"launch_velocity": launch_velocity,
		"aim_error": aim_error,
		"angle_error_degrees": angle_error_degrees,
		"bounce_allowed": false,
		"bounce_attempted": false,
		"bounce_roll": 1.0,
		"fallback_reason": fallback_reason,
	}


static func _build_bounce_plan(
	profile,
	ball: RigidBody3D,
	launch_transform: Transform3D,
	target_cup: Node3D,
	rng: RandomNumberGenerator,
	config: Dictionary,
	bounce_decision: Dictionary
) -> Dictionary:
	var target_position := ComputerThrowPhysicsScript.get_cup_rim_center_position(target_cup)
	var angle_error_degrees := _sample_signed_error(profile.bounce_angle_error_degrees, rng)
	var release_angle_degrees := clampf(
		profile.bounce_release_angle_degrees + angle_error_degrees,
		MIN_RELEASE_ANGLE_DEGREES,
		MAX_RELEASE_ANGLE_DEGREES
	)
	var bounce_solution := ComputerThrowPhysicsScript.find_bounce_aim_point(
		ball,
		launch_transform.origin,
		target_position,
		config.get("table_bounds", {}),
		profile,
		release_angle_degrees
	)
	if not bool(bounce_solution.get("success", false)):
		return {
			"success": false,
			"profile_id": profile.get_profile_id_string(),
			"shot_type": SHOT_TYPE_BOUNCE,
			"failure_reason": str(bounce_solution.get("failure_reason", "no_valid_bounce_candidate")),
			"bounce_allowed": bool(bounce_decision.get("allowed", false)),
			"bounce_attempted": bool(bounce_decision.get("attempt", false)),
			"bounce_roll": float(bounce_decision.get("roll", 1.0)),
		}

	var ideal_bounce_position: Vector3 = bounce_solution.get("bounce_position", Vector3.ZERO)
	var aim_error := _sample_horizontal_error(profile.bounce_aim_error_radius, rng)
	var bounce_position := ideal_bounce_position + aim_error
	var launch_velocity := ComputerThrowPhysicsScript.calculate_bounce_launch_velocity(
		ball,
		launch_transform.origin,
		bounce_position,
		target_position,
		release_angle_degrees,
		profile.bounce_target_height
	)
	if not ComputerThrowPhysicsScript.is_valid_launch_velocity(launch_velocity):
		return {
			"success": false,
			"profile_id": profile.get_profile_id_string(),
			"shot_type": SHOT_TYPE_BOUNCE,
			"failure_reason": "invalid_bounce_launch_velocity",
			"bounce_allowed": bool(bounce_decision.get("allowed", false)),
			"bounce_attempted": bool(bounce_decision.get("attempt", false)),
			"bounce_roll": float(bounce_decision.get("roll", 1.0)),
		}

	return {
		"success": true,
		"profile_id": profile.get_profile_id_string(),
		"display_name": profile.display_name,
		"shot_type": SHOT_TYPE_BOUNCE,
		"target_cup": target_cup,
		"target_cup_index": _get_cup_index(target_cup),
		"target_position": target_position,
		"aim_position": target_position,
		"bounce_position": bounce_position,
		"release_angle_degrees": release_angle_degrees,
		"launch_velocity": launch_velocity,
		"aim_error": aim_error,
		"angle_error_degrees": angle_error_degrees,
		"bounce_allowed": bool(bounce_decision.get("allowed", false)),
		"bounce_attempted": bool(bounce_decision.get("attempt", false)),
		"bounce_roll": float(bounce_decision.get("roll", 1.0)),
		"predicted_bounce_error": float(bounce_solution.get("predicted_error", 0.0)),
		"predicted_bounce_apex_height": float(bounce_solution.get("predicted_apex_height", 0.0)),
		"fallback_reason": "",
	}


static func _get_bounce_decision(profile, config: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var allowed := _is_bouncing_rule_enabled(config)
	var roll := 1.0
	var attempt := false
	if allowed and profile.bounce_propensity > 0.0:
		roll = rng.randf() if rng != null else 1.0
		attempt = roll <= profile.bounce_propensity

	return {
		"allowed": allowed,
		"attempt": attempt,
		"roll": roll,
	}


static func _is_bouncing_rule_enabled(config: Dictionary) -> bool:
	var rules_profile = config.get("house_rules_profile", null)
	if rules_profile == null or not rules_profile.has_method("is_enabled"):
		return false
	return bool(rules_profile.call("is_enabled", HouseRuleIdsScript.BOUNCING))


static func _get_profile(config: Dictionary):
	var profile = config.get("profile", null)
	if profile != null:
		return profile
	return ComputerPlayerProfileScript.default_profile()


static func _sample_horizontal_error(error_radius: float, rng: RandomNumberGenerator) -> Vector3:
	if error_radius <= 0.0 or rng == null:
		return Vector3.ZERO

	var miss_angle := rng.randf_range(0.0, TAU)
	var miss_distance := sqrt(rng.randf()) * error_radius
	return Vector3(cos(miss_angle) * miss_distance, 0.0, sin(miss_angle) * miss_distance)


static func _sample_signed_error(max_abs_error: float, rng: RandomNumberGenerator) -> float:
	if max_abs_error <= 0.0 or rng == null:
		return 0.0
	return rng.randf_range(-max_abs_error, max_abs_error)


static func _get_cup_index(cup: Node3D) -> int:
	return int(cup.get_meta("cup_index", -1)) if cup != null and is_instance_valid(cup) else -1
