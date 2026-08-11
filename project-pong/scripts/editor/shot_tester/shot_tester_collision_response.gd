extends RefCounted
class_name ShotTesterCollisionResponse

const ShotPhysicsScript := preload("res://scripts/match/shot_physics.gd")
const ContactSummaryScript := preload("res://scripts/house_rules/shot_contact_summary.gd")

const DEFAULT_BALL_RADIUS := 0.02
const EPSILON := 0.0001
const SURFACE_CUP_RIM := &"cup_rim"
const SURFACE_CUP_WALL := &"cup_wall"
const SURFACE_CUP_BOTTOM := &"cup_bottom"


static func apply_bounce(ball: RigidBody3D, cup: Node3D, collision_snapshot: Dictionary, config := {}) -> Dictionary:
	if ball == null or cup == null or not is_instance_valid(ball) or not is_instance_valid(cup):
		return {}

	var restitution := clampf(float(config.get("restitution", 0.68)), 0.0, 1.0)
	var tangential_damping := clampf(float(config.get("tangential_damping", 0.84)), 0.0, 1.0)
	var angular_damping := clampf(float(config.get("angular_damping", 0.82)), 0.0, 1.0)
	var clearance := maxf(float(config.get("clearance", 0.0015)), 0.0)
	var ball_radius := ShotPhysicsScript.get_ball_radius(ball, DEFAULT_BALL_RADIUS)
	var local_normal: Vector3 = collision_snapshot.get("normal_local", Vector3.UP)
	if local_normal.length_squared() <= EPSILON:
		local_normal = Vector3.UP
	local_normal = local_normal.normalized()

	var world_normal := (cup.global_transform.basis * local_normal).normalized()
	var incoming_velocity := ball.linear_velocity
	var normal_speed := incoming_velocity.dot(world_normal)
	if normal_speed > 0.0:
		world_normal = -world_normal
		local_normal = -local_normal
		normal_speed = incoming_velocity.dot(world_normal)

	var reflected_velocity := incoming_velocity
	if normal_speed < 0.0:
		reflected_velocity = incoming_velocity - world_normal * ((1.0 + restitution) * normal_speed)

	var normal_component := world_normal * reflected_velocity.dot(world_normal)
	var tangential_component := reflected_velocity - normal_component
	var final_velocity := normal_component + tangential_component * tangential_damping
	var nearest_local: Vector3 = collision_snapshot.get("nearest_local_point", Vector3.ZERO)
	var clear_local := nearest_local + local_normal * (ball_radius + clearance)
	var previous_position := ball.global_position

	ball.freeze = false
	ball.global_position = cup.global_transform * clear_local
	ball.linear_velocity = final_velocity
	ball.angular_velocity *= angular_damping
	ball.sleeping = false
	_record_synthetic_contact(ball, cup, collision_snapshot)

	return {
		"previous_position": previous_position,
		"clear_position": ball.global_position,
		"incoming_velocity": incoming_velocity,
		"reflected_velocity": final_velocity,
		"normal_world": world_normal,
		"normal_local": local_normal,
		"normal_speed": normal_speed,
		"restitution": restitution,
		"tangential_damping": tangential_damping,
	}


static func _record_synthetic_contact(ball: RigidBody3D, cup: Node3D, collision_snapshot: Dictionary) -> void:
	if not ball.has_method("record_synthetic_contact"):
		return

	ball.call("record_synthetic_contact", {
		"type": String(ContactSummaryScript.TYPE_CUP),
		"cup_index": int(cup.get_meta("cup_index", collision_snapshot.get("cup_index", -1))),
		"owner_slot": int(cup.get_meta("owner_slot", collision_snapshot.get("owner_slot", 0))),
		"owner_side": StringName(str(cup.get_meta("owner_side", collision_snapshot.get("owner_side", "")))),
		"surface_id": String(_get_surface_id(collision_snapshot)),
		"playable_bounce": true,
	})


static func _get_surface_id(collision_snapshot: Dictionary) -> StringName:
	match str(collision_snapshot.get("classification", "")):
		"top_inner", "top_rim_band":
			return SURFACE_CUP_RIM
		"bottom_cap":
			return SURFACE_CUP_BOTTOM
	return SURFACE_CUP_WALL
