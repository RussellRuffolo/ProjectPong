extends Node3D
class_name CupTarget

const PongPhysicsSurfaceScript := preload("res://scripts/pong_physics_surface.gd")
const CupLiquidVisualScript := preload("res://scripts/cup_liquid_visual.gd")
const ShotPhysicsScript := preload("res://scripts/match/shot_physics.gd")
const ContactSummaryScript := preload("res://scripts/house_rules/shot_contact_summary.gd")

const DEFAULT_BALL_RADIUS := 0.02
const SURFACE_CUP_RIM := &"cup_rim"
const SURFACE_CUP_WALL := &"cup_wall"
const EPSILON := 0.0001

@export var visual_scene: PackedScene
@export var collision_scene: PackedScene
@export var math_sensor_enabled := true
@export var legacy_mesh_collision_enabled := false
@export var liquid_enabled := true
@export var liquid_scene: PackedScene
@export_range(0.0, 1.0, 0.01) var liquid_fill_ratio := 0.38
@export var liquid_radius := 0.036
@export var liquid_height := 0.085
@export var liquid_bottom_y := 0.006
@export var cup_bottom_y := 0.006
@export var cup_rim_y := 0.058
@export var cup_bottom_radius := 0.030
@export var cup_rim_radius := 0.046
@export var cup_inner_score_radius := 0.036
@export var rim_tube_radius := 0.012
@export var score_area_radius := 0.032
@export var score_area_height := 0.11
@export var score_area_center_y := 0.058
@export var rim_center_y := 0.058
@export var resting_score_radius := 0.028
@export var resting_score_min_y := 0.018
@export var resting_score_max_y := 0.11
@export_range(0.0, 1.0, 0.01) var score_capture_horizontal_scale := 0.18
@export_range(0.0, 1.0, 0.01) var score_capture_downward_scale := 0.22
@export_range(0.0, 1.0, 0.01) var score_capture_spin_scale := 0.35
@export_range(0.0, 1.0, 0.01) var cup_wall_bounce := 0.06
@export_range(0.0, 1.0, 0.01) var cup_wall_friction := 0.85
@export var interaction_radius_margin := 0.035
@export var interaction_height_margin := 0.05
@export var min_score_downward_speed := 0.15
@export_range(0.0, 2.0, 0.01) var rim_band_ball_radius_scale := 0.6
@export_range(0.0, 1.0, 0.01) var side_deflection_bounce := 0.35
@export_range(0.0, 1.0, 0.01) var side_deflection_tangent_scale := 0.82
@export_range(0.0, 1.0, 0.01) var rim_deflection_bounce := 0.72
@export_range(0.0, 1.0, 0.01) var rim_deflection_tangent_scale := 0.68
@export_range(0.0, 1.0, 0.01) var rim_top_radial_normal_scale := 0.38
@export_range(0.0, 1.0, 0.01) var rim_top_upward_normal_scale := 0.92
@export var side_penetration_correction_scale := 0.85
@export var rim_penetration_correction_scale := 0.35
@export var capture_animation_seconds := 0.18
@export_range(0.0, 1.0, 0.01) var cup_bottom_bounce_absorption := 0.9
@export_range(0.0, 1.0, 0.01) var cup_bottom_friction := 0.96
@export var cup_bottom_absorbs_ball_bounce := true
@export var cup_bottom_rough := true

var _has_scored := false
var _score_bodies: Array[Node3D] = []
var _interaction_bodies: Array[Node3D] = []
var _captured_bodies: Array[Node3D] = []
var _last_local_positions: Dictionary = {}
var _capture_animation_states: Dictionary = {}
var _liquid_visual: Node3D
var _interaction_area: Area3D


func _ready() -> void:
	set_physics_process(false)
	_add_visual()
	_add_liquid_visual()
	if legacy_mesh_collision_enabled:
		_add_collision()
	if math_sensor_enabled:
		_add_interaction_area()
	_add_score_area()


func remove_from_game() -> void:
	_has_scored = true
	_clear_tracked_bodies()
	_set_liquid_visible(false)
	queue_free()


func is_ball_resting_inside(ball: Node3D) -> bool:
	if _has_scored or ball == null or not is_instance_valid(ball):
		return false
	if _captured_bodies.has(ball):
		return true
	if not _score_bodies.has(ball):
		return false

	return _is_ball_inside_resting_volume(ball)


func is_score_capture_confirmed() -> bool:
	return not _captured_bodies.is_empty()


func _physics_process(delta: float) -> void:
	_prune_tracked_bodies()
	for body in _captured_bodies.duplicate():
		var captured_ball := body as RigidBody3D
		if captured_ball == null or not is_instance_valid(captured_ball):
			continue

		var captured_ball_radius := ShotPhysicsScript.get_ball_radius(captured_ball, DEFAULT_BALL_RADIUS)
		_update_captured_ball(captured_ball, captured_ball_radius, delta)

	if _has_scored:
		if _capture_animation_states.is_empty():
			set_physics_process(false)
		return

	if _interaction_bodies.is_empty():
		set_physics_process(false)
		return

	for body in _interaction_bodies.duplicate():
		var ball := body as RigidBody3D
		if ball == null or not is_instance_valid(ball):
			continue

		var ball_id := ball.get_instance_id()
		var current_local := _to_local_position(ball.global_position)
		var previous_local: Vector3 = _last_local_positions.get(ball_id, current_local)
		var ball_radius := ShotPhysicsScript.get_ball_radius(ball, DEFAULT_BALL_RADIUS)
		if _captured_bodies.has(ball):
			continue
		else:
			var handled_top := _try_handle_top_crossing(ball, previous_local, current_local, ball_radius)
			if not handled_top and not _try_handle_score_capture(ball, current_local, ball_radius):
				_try_handle_side_deflection(ball, previous_local, current_local, ball_radius)

		_last_local_positions[ball_id] = _to_local_position(ball.global_position)


func mark_scored() -> void:
	_has_scored = true
	set_physics_process(not _captured_bodies.is_empty())
	_set_liquid_visible(false)


func is_scored() -> bool:
	return _has_scored


func get_rim_center_position() -> Vector3:
	var local_top_center := Vector3(0.0, cup_rim_y, 0.0)
	return global_transform * local_top_center


func get_top_center_position() -> Vector3:
	return get_rim_center_position()


func _is_ball_inside_resting_volume(ball: Node3D) -> bool:
	var local_ball_position := global_transform.affine_inverse() * ball.global_position
	var horizontal_distance := Vector2(local_ball_position.x, local_ball_position.z).length()
	return (
		horizontal_distance <= resting_score_radius
		and local_ball_position.y >= resting_score_min_y
		and local_ball_position.y <= resting_score_max_y
	)


func _add_visual() -> void:
	if visual_scene == null:
		push_warning("[Cup] No cup visual scene assigned.")
		return

	var visual := visual_scene.instantiate()
	visual.name = "Visual"
	add_child(visual)


func _add_liquid_visual() -> void:
	if not liquid_enabled:
		return

	var liquid := _create_liquid_visual()
	if liquid == null:
		return

	liquid.name = "Liquid"
	liquid.set("fill_ratio", liquid_fill_ratio)
	liquid.set("liquid_radius", liquid_radius)
	liquid.set("liquid_height", liquid_height)
	liquid.set("liquid_bottom_y", liquid_bottom_y)

	_liquid_visual = liquid
	add_child(liquid)


func _create_liquid_visual() -> Node3D:
	if liquid_scene != null:
		return liquid_scene.instantiate() as Node3D
	return CupLiquidVisualScript.new() as Node3D


func _set_liquid_visible(is_visible: bool) -> void:
	if _liquid_visual == null or not is_instance_valid(_liquid_visual):
		return
	if _liquid_visual.has_method("set_liquid_visible"):
		_liquid_visual.call("set_liquid_visible", is_visible)
	else:
		_liquid_visual.visible = is_visible


func _add_collision() -> void:
	if collision_scene == null:
		push_warning("[Cup] No cup collision scene assigned.")
		return

	var collision_source := collision_scene.instantiate()
	var collision_root := Node3D.new()
	collision_root.name = "Collision"
	add_child(collision_root)
	_add_collision_meshes(collision_source, Transform3D.IDENTITY, collision_root)
	collision_source.free()


func _add_collision_meshes(node: Node, parent_transform: Transform3D, collision_root: Node3D) -> void:
	var local_transform := parent_transform
	var node_3d := node as Node3D
	if node_3d != null:
		local_transform = parent_transform * node_3d.transform

	var mesh_instance := node as MeshInstance3D
	if mesh_instance != null and mesh_instance.mesh != null:
		var shape := mesh_instance.mesh.create_trimesh_shape()
		if shape != null:
			var body := PongPhysicsSurfaceScript.new()
			body.name = "%sBody" % mesh_instance.name
			body.transform = local_transform
			_configure_collision_surface(body, mesh_instance.name)
			collision_root.add_child(body)

			var collision_shape := CollisionShape3D.new()
			collision_shape.name = "CollisionShape3D"
			collision_shape.shape = shape
			body.add_child(collision_shape)

	for child in node.get_children():
		_add_collision_meshes(child, local_transform, collision_root)


func _add_interaction_area() -> void:
	var interaction_area := Area3D.new()
	interaction_area.name = "InteractionArea"
	interaction_area.collision_layer = 0
	interaction_area.collision_mask = 1
	interaction_area.monitoring = true
	interaction_area.body_entered.connect(_on_interaction_body_entered)
	interaction_area.body_exited.connect(_on_interaction_body_exited)
	add_child(interaction_area)

	var interaction_shape := CollisionShape3D.new()
	interaction_shape.name = "CollisionShape3D"
	interaction_shape.position.y = (cup_bottom_y + cup_rim_y) * 0.5

	var cylinder := CylinderShape3D.new()
	cylinder.radius = cup_rim_radius + DEFAULT_BALL_RADIUS + interaction_radius_margin
	cylinder.height = maxf(cup_rim_y - cup_bottom_y + interaction_height_margin, 0.01)
	interaction_shape.shape = cylinder
	interaction_area.add_child(interaction_shape)
	_interaction_area = interaction_area


func _add_score_area() -> void:
	var score_area := Area3D.new()
	score_area.name = "ScoreArea"
	score_area.collision_layer = 0
	score_area.collision_mask = 1
	score_area.monitoring = true
	score_area.body_entered.connect(_on_score_area_body_entered)
	score_area.body_exited.connect(_on_score_area_body_exited)
	add_child(score_area)

	var score_shape := CollisionShape3D.new()
	score_shape.name = "CollisionShape3D"
	score_shape.position.y = score_area_center_y
	var cylinder := CylinderShape3D.new()
	cylinder.radius = score_area_radius
	cylinder.height = score_area_height
	score_shape.shape = cylinder
	score_area.add_child(score_shape)


func _on_score_area_body_entered(body: Node3D) -> void:
	if _has_scored or not _is_score_body(body):
		return

	if not _score_bodies.has(body):
		_score_bodies.append(body)
	if math_sensor_enabled:
		_on_interaction_body_entered(body)
		var ball := body as RigidBody3D
		if ball != null:
			_try_handle_score_capture(
				ball,
				_to_local_position(ball.global_position),
				ShotPhysicsScript.get_ball_radius(ball, DEFAULT_BALL_RADIUS)
			)
		return

	_apply_score_capture(body)


func _on_score_area_body_exited(body: Node3D) -> void:
	_score_bodies.erase(body)


func _on_interaction_body_entered(body: Node3D) -> void:
	if _has_scored or not _is_score_body(body):
		return

	if not _interaction_bodies.has(body):
		_interaction_bodies.append(body)
	_last_local_positions[body.get_instance_id()] = _to_local_position(body.global_position)
	set_physics_process(true)


func _on_interaction_body_exited(body: Node3D) -> void:
	if _captured_bodies.has(body):
		set_physics_process(true)
		return

	_interaction_bodies.erase(body)
	_captured_bodies.erase(body)
	_capture_animation_states.erase(body.get_instance_id())
	_last_local_positions.erase(body.get_instance_id())
	if _interaction_bodies.is_empty():
		set_physics_process(false)


func _exit_tree() -> void:
	_clear_tracked_bodies()


func _is_score_body(body: Node3D) -> bool:
	return body is ThrowableBall or body.is_in_group("game_ball")


func _apply_score_capture(body: Node3D) -> void:
	var ball := body as RigidBody3D
	if ball == null:
		return

	var velocity := ball.linear_velocity
	velocity.x *= score_capture_horizontal_scale
	velocity.z *= score_capture_horizontal_scale
	if velocity.y < 0.0:
		velocity.y *= score_capture_downward_scale
	ball.linear_velocity = velocity
	ball.angular_velocity *= score_capture_spin_scale


func _try_handle_top_crossing(
	ball: RigidBody3D,
	previous_local: Vector3,
	current_local: Vector3,
	ball_radius: float
) -> bool:
	if not _is_downward_top_crossing(ball, previous_local, current_local):
		return false

	var crossing_local := _get_y_crossing(previous_local, current_local, cup_rim_y)
	var crossing_radius := Vector2(crossing_local.x, crossing_local.z).length()
	var rim_band := _get_rim_band(ball_radius)
	if absf(crossing_radius - cup_rim_radius) <= rim_band:
		_apply_rim_deflection(ball, crossing_local, ball_radius)
		_record_synthetic_cup_contact(ball, SURFACE_CUP_RIM)
		return true

	if crossing_radius <= _get_score_crossing_radius(ball_radius):
		_capture_ball(ball, current_local, ball_radius)
		return true

	return false


func _try_handle_score_capture(ball: RigidBody3D, current_local: Vector3, ball_radius: float) -> bool:
	if current_local.y > cup_rim_y:
		return false

	var horizontal_radius := Vector2(current_local.x, current_local.z).length()
	if horizontal_radius > _get_score_crossing_radius(ball_radius):
		return false

	_capture_ball(ball, current_local, ball_radius)
	return true


func _try_handle_side_deflection(
	ball: RigidBody3D,
	previous_local: Vector3,
	current_local: Vector3,
	ball_radius: float
) -> bool:
	if current_local.y < cup_bottom_y - ball_radius or current_local.y > cup_rim_y + ball_radius:
		return false

	var current_radial := Vector2(current_local.x, current_local.z).length()
	if current_radial <= EPSILON:
		return false

	var current_signed_distance := _get_side_signed_distance(current_local)
	var previous_signed_distance := _get_side_signed_distance(previous_local)
	var near_wall := absf(current_signed_distance) <= ball_radius
	var crossed_wall := (
		previous_signed_distance > ball_radius and current_signed_distance < -ball_radius
	) or (
		previous_signed_distance < -ball_radius and current_signed_distance > ball_radius
	)
	if not near_wall and not crossed_wall:
		return false

	var reference_signed_distance := previous_signed_distance if crossed_wall else current_signed_distance
	var side_normal_local := _get_side_outward_normal(current_local)
	var collision_normal_local := side_normal_local if reference_signed_distance >= 0.0 else -side_normal_local
	var velocity_local := _to_local_vector(ball.linear_velocity)
	if velocity_local.dot(collision_normal_local) >= -0.01 and not crossed_wall:
		return false

	var normal_world := _to_world_normal(collision_normal_local)
	_apply_velocity_deflection(ball, normal_world, side_deflection_bounce, side_deflection_tangent_scale)
	_apply_side_position_correction(ball, current_local, reference_signed_distance, ball_radius)
	_record_synthetic_cup_contact(ball, SURFACE_CUP_WALL)
	return true


func _capture_ball(ball: RigidBody3D, current_local: Vector3, ball_radius: float) -> void:
	if not _captured_bodies.has(ball):
		_captured_bodies.append(ball)
	if not _score_bodies.has(ball):
		_score_bodies.append(ball)

	var start_local := _clamp_capture_start(current_local, ball_radius)
	var target_local := Vector3(0.0, cup_bottom_y + ball_radius, 0.0)
	ball.global_position = global_transform * start_local
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	if ball.has_method("suspend_physics_for_capture"):
		ball.call("suspend_physics_for_capture")
	else:
		ball.freeze = true
		ball.sleeping = true
	_capture_animation_states[ball.get_instance_id()] = {
		"start_local": start_local,
		"target_local": target_local,
		"elapsed": 0.0,
		"duration": maxf(capture_animation_seconds, 0.01),
	}


func _update_captured_ball(ball: RigidBody3D, ball_radius: float, delta: float) -> void:
	var ball_id := ball.get_instance_id()
	var state: Dictionary = _capture_animation_states.get(ball_id, {})
	if state.is_empty():
		ball.global_position = global_transform * Vector3(0.0, cup_bottom_y + ball_radius, 0.0)
		return

	var elapsed := float(state.get("elapsed", 0.0)) + delta
	var duration := maxf(float(state.get("duration", capture_animation_seconds)), 0.01)
	var amount := clampf(elapsed / duration, 0.0, 1.0)
	var eased_amount := amount * amount * (3.0 - 2.0 * amount)
	var start_local: Vector3 = state.get("start_local", Vector3.ZERO)
	var target_local: Vector3 = state.get("target_local", Vector3(0.0, cup_bottom_y + ball_radius, 0.0))
	ball.global_position = global_transform * start_local.lerp(target_local, eased_amount)
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	ball.sleeping = true

	if amount >= 1.0:
		_capture_animation_states.erase(ball_id)
	else:
		state["elapsed"] = elapsed
		_capture_animation_states[ball_id] = state


func _apply_rim_deflection(ball: RigidBody3D, crossing_local: Vector3, ball_radius: float) -> void:
	var sample_local := crossing_local
	sample_local.y = cup_rim_y + maxf(rim_tube_radius, ball_radius * 0.25)
	var rim_normal_world := _to_world_normal(_get_flat_top_rim_normal(sample_local))
	_apply_velocity_deflection(ball, rim_normal_world, rim_deflection_bounce, rim_deflection_tangent_scale)
	ball.global_position += rim_normal_world * ball_radius * rim_penetration_correction_scale


func _apply_velocity_deflection(
	ball: RigidBody3D,
	normal_world: Vector3,
	bounce_scale: float,
	tangent_scale: float
) -> void:
	if normal_world.length_squared() <= EPSILON:
		return

	var normal := normal_world.normalized()
	var velocity := ball.linear_velocity
	var normal_speed := velocity.dot(normal)
	if normal_speed >= 0.0:
		return

	var normal_velocity := normal * normal_speed
	var tangent_velocity := velocity - normal_velocity
	ball.linear_velocity = tangent_velocity * tangent_scale - normal_velocity * bounce_scale
	ball.angular_velocity *= maxf(0.0, tangent_scale)
	ball.sleeping = false


func _apply_side_position_correction(
	ball: RigidBody3D,
	current_local: Vector3,
	signed_distance: float,
	ball_radius: float
) -> void:
	var radial := Vector2(current_local.x, current_local.z)
	var radial_length := radial.length()
	if radial_length <= EPSILON:
		return

	var wall_radius := _get_wall_radius_at_y(clampf(current_local.y, cup_bottom_y, cup_rim_y))
	var target_signed := ball_radius if signed_distance >= 0.0 else -ball_radius
	var target_radius := maxf(0.0, wall_radius + target_signed)
	var correction_amount := clampf(side_penetration_correction_scale, 0.0, 1.0)
	var corrected_radius := lerpf(radial_length, target_radius, correction_amount)
	var direction := radial / radial_length
	var corrected_local := Vector3(
		direction.x * corrected_radius,
		current_local.y,
		direction.y * corrected_radius
	)
	ball.global_position = global_transform * corrected_local


func _record_synthetic_cup_contact(ball: RigidBody3D, surface_id: StringName) -> void:
	if ball == null or not ball.has_method("record_synthetic_contact"):
		return

	ball.call("record_synthetic_contact", {
		"type": String(ContactSummaryScript.TYPE_CUP),
		"cup_index": int(get_meta("cup_index", -1)),
		"owner_slot": int(get_meta("owner_slot", 0)),
		"owner_side": StringName(str(get_meta("owner_side", ""))),
		"surface_id": String(surface_id),
		"playable_bounce": true,
	})


func _is_downward_top_crossing(ball: RigidBody3D, previous_local: Vector3, current_local: Vector3) -> bool:
	if previous_local.y <= cup_rim_y or current_local.y > cup_rim_y:
		return false

	return _to_local_vector(ball.linear_velocity).y <= -min_score_downward_speed


func _get_y_crossing(previous_local: Vector3, current_local: Vector3, y_value: float) -> Vector3:
	var delta_y := current_local.y - previous_local.y
	if absf(delta_y) <= EPSILON:
		return current_local

	var ratio := clampf((y_value - previous_local.y) / delta_y, 0.0, 1.0)
	return previous_local.lerp(current_local, ratio)


func _get_score_crossing_radius(ball_radius: float) -> float:
	var rim_inner_limit := cup_rim_radius - _get_rim_band(ball_radius)
	return maxf(0.0, minf(cup_inner_score_radius, rim_inner_limit))


func _get_rim_band(ball_radius: float) -> float:
	return maxf(rim_tube_radius, ball_radius * rim_band_ball_radius_scale)


func _get_side_signed_distance(local_position: Vector3) -> float:
	var y := clampf(local_position.y, cup_bottom_y, cup_rim_y)
	var radial := Vector2(local_position.x, local_position.z).length()
	return radial - _get_wall_radius_at_y(y)


func _get_wall_radius_at_y(y: float) -> float:
	var height := maxf(cup_rim_y - cup_bottom_y, EPSILON)
	var ratio := clampf((y - cup_bottom_y) / height, 0.0, 1.0)
	return lerpf(cup_bottom_radius, cup_rim_radius, ratio)


func _get_side_outward_normal(local_position: Vector3) -> Vector3:
	var radial := Vector2(local_position.x, local_position.z)
	if radial.length_squared() <= EPSILON:
		return Vector3.UP

	var height := maxf(cup_rim_y - cup_bottom_y, EPSILON)
	var slope := (cup_rim_radius - cup_bottom_radius) / height
	var radial_direction := radial.normalized()
	return Vector3(radial_direction.x, -slope, radial_direction.y).normalized()


func _get_rim_torus_normal(sample_local: Vector3) -> Vector3:
	var radial := Vector2(sample_local.x, sample_local.z)
	if radial.length_squared() <= EPSILON:
		return Vector3.UP

	var radial_direction := radial.normalized()
	var rim_centerline_point := Vector3(
		radial_direction.x * cup_rim_radius,
		cup_rim_y,
		radial_direction.y * cup_rim_radius
	)
	var normal := sample_local - rim_centerline_point
	if normal.length_squared() <= EPSILON:
		return Vector3(radial_direction.x, 1.0, radial_direction.y).normalized()
	return normal.normalized()


func _get_flat_top_rim_normal(sample_local: Vector3) -> Vector3:
	var torus_normal := _get_rim_torus_normal(sample_local)
	var radial := Vector2(torus_normal.x, torus_normal.z)
	if radial.length_squared() <= EPSILON:
		return Vector3.UP

	var radial_direction := radial.normalized()
	return Vector3(
		radial_direction.x * rim_top_radial_normal_scale,
		rim_top_upward_normal_scale,
		radial_direction.y * rim_top_radial_normal_scale
	).normalized()


func _clamp_capture_start(local_position: Vector3, ball_radius: float) -> Vector3:
	var clamped_local := local_position
	var max_center_radius := maxf(0.0, _get_score_crossing_radius(ball_radius))
	var horizontal := Vector2(clamped_local.x, clamped_local.z)
	if horizontal.length() > max_center_radius and horizontal.length() > EPSILON:
		var direction := horizontal.normalized()
		clamped_local.x = direction.x * max_center_radius
		clamped_local.z = direction.y * max_center_radius
	clamped_local.y = clampf(clamped_local.y, cup_bottom_y + ball_radius, cup_rim_y - EPSILON)
	return clamped_local


func _to_local_position(world_position: Vector3) -> Vector3:
	return global_transform.affine_inverse() * world_position


func _to_local_vector(world_vector: Vector3) -> Vector3:
	return global_transform.basis.inverse() * world_vector


func _to_world_normal(local_normal: Vector3) -> Vector3:
	return (global_transform.basis * local_normal).normalized()


func _prune_tracked_bodies() -> void:
	for body in _interaction_bodies.duplicate():
		if body == null or not is_instance_valid(body) or body.is_queued_for_deletion():
			var interaction_body_id := 0
			if body != null and is_instance_valid(body):
				interaction_body_id = body.get_instance_id()
			_interaction_bodies.erase(body)
			_captured_bodies.erase(body)
			if interaction_body_id != 0:
				_capture_animation_states.erase(interaction_body_id)

	for body in _score_bodies.duplicate():
		if body == null or not is_instance_valid(body) or body.is_queued_for_deletion():
			_score_bodies.erase(body)

	for body in _captured_bodies.duplicate():
		if body == null or not is_instance_valid(body) or body.is_queued_for_deletion():
			var captured_body_id := 0
			if body != null and is_instance_valid(body):
				captured_body_id = body.get_instance_id()
			_captured_bodies.erase(body)
			if captured_body_id != 0:
				_capture_animation_states.erase(captured_body_id)

	var live_ids := {}
	for body in _interaction_bodies:
		live_ids[body.get_instance_id()] = true
	for ball_id in _last_local_positions.keys():
		if not live_ids.has(ball_id):
			_last_local_positions.erase(ball_id)

	var live_capture_ids := {}
	for body in _captured_bodies:
		if body != null and is_instance_valid(body):
			live_capture_ids[body.get_instance_id()] = true
	for ball_id in _capture_animation_states.keys():
		if not live_capture_ids.has(ball_id):
			_capture_animation_states.erase(ball_id)


func _clear_tracked_bodies() -> void:
	_score_bodies.clear()
	_interaction_bodies.clear()
	_captured_bodies.clear()
	_last_local_positions.clear()
	_capture_animation_states.clear()
	set_physics_process(false)


func _configure_collision_surface(body: StaticBody3D, mesh_name: StringName) -> void:
	if body.has_method("configure"):
		if _is_bottom_collision_mesh(mesh_name):
			body.call(
				"configure",
				&"cup_bottom_liquid",
				cup_bottom_bounce_absorption,
				cup_bottom_friction,
				cup_bottom_absorbs_ball_bounce,
				cup_bottom_rough
			)
		else:
			body.call("configure", &"cup_wall", cup_wall_bounce, cup_wall_friction, false, false)


func _is_bottom_collision_mesh(mesh_name: StringName) -> bool:
	return String(mesh_name).begins_with("COL_Bottom")
