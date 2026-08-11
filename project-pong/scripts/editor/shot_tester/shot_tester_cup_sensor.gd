extends Node3D
class_name ShotTesterCupSensor

signal ball_entered_frustum(cup: Node3D, ball: RigidBody3D, collision_snapshot: Dictionary)

const ConicFrustumCollisionScript := preload("res://scripts/match/conic_frustum_collision.gd")
const ShotPhysicsScript := preload("res://scripts/match/shot_physics.gd")

const DEFAULT_BALL_RADIUS := 0.02

@export var cup_index := -1
@export var owner_slot := 0
@export var owner_side := &""
@export var bottom_y := 0.006
@export var rim_y := 0.058
@export var bottom_radius := 0.030
@export var rim_radius := 0.046
@export_range(0.05, 2.0, 0.01) var rim_band_ball_radius_scale := 0.6
@export var sensor_enabled := true

var _tracked_balls: Array[RigidBody3D] = []
var _previous_local_positions: Dictionary = {}
var _overlap_states: Dictionary = {}


func _ready() -> void:
	_sync_metadata()
	set_physics_process(sensor_enabled)


func configure(index: int, slot: int, side: StringName, parameters: Dictionary) -> void:
	cup_index = index
	owner_slot = slot
	owner_side = side
	bottom_y = float(parameters.get("bottom_y", bottom_y))
	rim_y = float(parameters.get("rim_y", rim_y))
	bottom_radius = float(parameters.get("bottom_radius", bottom_radius))
	rim_radius = float(parameters.get("rim_radius", rim_radius))
	rim_band_ball_radius_scale = float(parameters.get("rim_band_ball_radius_scale", rim_band_ball_radius_scale))
	_sync_metadata()


func set_sensor_enabled(is_enabled: bool) -> void:
	sensor_enabled = is_enabled
	set_physics_process(sensor_enabled)
	if not sensor_enabled:
		clear_tracking_state()


func track_ball(ball: RigidBody3D) -> void:
	if ball == null or not is_instance_valid(ball):
		return
	if not _tracked_balls.has(ball):
		_tracked_balls.append(ball)
		var ball_id := ball.get_instance_id()
		_previous_local_positions[ball_id] = _to_local_position(ball.global_position)
		_overlap_states[ball_id] = false
	set_physics_process(sensor_enabled)


func clear_tracking_state() -> void:
	_previous_local_positions.clear()
	_overlap_states.clear()


func get_parameters() -> Dictionary:
	return ConicFrustumCollisionScript.build_parameters({
		"bottom_y": bottom_y,
		"rim_y": rim_y,
		"bottom_radius": bottom_radius,
		"rim_radius": rim_radius,
		"rim_band_ball_radius_scale": rim_band_ball_radius_scale,
	})


func get_rim_center_position() -> Vector3:
	return global_transform * Vector3(0.0, rim_y, 0.0)


func get_top_center_position() -> Vector3:
	return get_rim_center_position()


func classify_ball(ball: RigidBody3D) -> Dictionary:
	if ball == null or not is_instance_valid(ball):
		return {}

	var ball_radius := ShotPhysicsScript.get_ball_radius(ball, DEFAULT_BALL_RADIUS)
	return ConicFrustumCollisionScript.calculate_world_sphere_frustum_intersection(
		global_transform,
		ball.global_position,
		ball_radius,
		get_parameters()
	)


func _physics_process(_delta: float) -> void:
	if not sensor_enabled:
		return

	_prune_tracked_balls()
	for ball in _tracked_balls:
		_update_ball_overlap(ball)


func _update_ball_overlap(ball: RigidBody3D) -> void:
	if ball == null or not is_instance_valid(ball):
		return

	var ball_id := ball.get_instance_id()
	var snapshot := classify_ball(ball)
	var intersects := bool(snapshot.get("intersects", false))
	var was_intersecting := bool(_overlap_states.get(ball_id, false))
	snapshot["cup_index"] = cup_index
	snapshot["owner_slot"] = owner_slot
	snapshot["owner_side"] = owner_side
	snapshot["cup_global_transform"] = global_transform
	snapshot["ball_world_position"] = ball.global_position
	snapshot["previous_ball_local_position"] = _previous_local_positions.get(
		ball_id,
		snapshot.get("ball_local_position", Vector3.ZERO)
	)

	if intersects and not was_intersecting:
		ball_entered_frustum.emit(self, ball, snapshot.duplicate(true))

	_overlap_states[ball_id] = intersects
	_previous_local_positions[ball_id] = snapshot.get("ball_local_position", _to_local_position(ball.global_position))


func _prune_tracked_balls() -> void:
	for ball in _tracked_balls.duplicate():
		if ball == null or not is_instance_valid(ball) or ball.is_queued_for_deletion():
			_tracked_balls.erase(ball)
			continue

	var live_ids := {}
	for ball in _tracked_balls:
		live_ids[ball.get_instance_id()] = true
	for ball_id in _previous_local_positions.keys():
		if not live_ids.has(ball_id):
			_previous_local_positions.erase(ball_id)
			_overlap_states.erase(ball_id)


func _to_local_position(world_position: Vector3) -> Vector3:
	return global_transform.affine_inverse() * world_position


func _sync_metadata() -> void:
	set_meta("cup_index", cup_index)
	set_meta("is_scored", false)
	set_meta("owner_slot", owner_slot)
	if owner_side != &"":
		set_meta("owner_side", owner_side)
