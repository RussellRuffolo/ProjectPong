extends RigidBody3D
class_name ThrowableBall

signal grabbed(grabber: Node3D)
signal released(grabber: Node3D, release_linear_velocity: Vector3, release_angular_velocity: Vector3)
signal score_contact_detected(ball: Node3D, cup: Node3D, snapshot: Dictionary)
signal score_capture_finished(ball: Node3D, cup: Node3D)

const DEFAULT_BALL_RADIUS := 0.02
const SCORE_CANDIDATE_TIE_EPSILON := 0.000001

@export_range(0.0, 1.0, 0.01) var bounce := 0.55
@export_range(0.0, 1.0, 0.01) var friction := 0.12
@export var held_gravity_scale := 0.0
@export var flight_gravity_scale := 1.0
@export var held_linear_damp := 0.0
@export var flight_linear_damp := 0.03
@export var flight_angular_damp := 0.08
@export var release_spin := Vector3(0.0, 0.0, 8.0)
@export var starts_suspended := true
@export var can_be_grabbed := true
@export var continuous_collision_detection := true
@export var score_capture_seconds := 0.18

var _default_collision_layer := 1
var _default_collision_mask := 1
var _capture_physics_suspended := false
var _score_contacts_enabled := false
var _latched_score_cup: Node3D
var _latched_score_snapshot: Dictionary = {}
var _candidate_emit_queued := false
var _previous_physics_velocity := Vector3.ZERO
var _capture_cup: Node3D
var _capture_finished := false
var _capture_tween: Tween
var _pre_capture_grabbable := true


func _ready() -> void:
	_default_collision_layer = collision_layer
	_default_collision_mask = collision_mask
	physics_material_override = _create_ball_material()
	contact_monitor = true
	max_contacts_reported = max(max_contacts_reported, 16)
	continuous_cd = continuous_collision_detection
	if starts_suspended:
		_set_held_physics()
	else:
		_set_flight_physics()
	print("[Ball] Throwable ball ready with bounce %.2f and friction %.2f." % [bounce, friction])


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _score_contacts_enabled and not _capture_physics_suspended and _latched_score_cup == null:
		_inspect_native_cup_contacts(state)
	_previous_physics_velocity = state.linear_velocity


func on_grabbed(_grabber: Node3D) -> void:
	restore_capture_physics()
	clear_score_contact_candidate()
	_set_held_physics()
	sleeping = false
	grabbed.emit(_grabber)


func on_released(_grabber: Node3D, release_linear_velocity: Vector3, _release_angular_velocity: Vector3) -> void:
	_set_flight_physics()
	linear_velocity = release_linear_velocity
	_previous_physics_velocity = release_linear_velocity
	angular_velocity = release_spin
	sleeping = false
	released.emit(_grabber, release_linear_velocity, angular_velocity)
	print("[Ball] Released with velocity %s." % linear_velocity)


func reset_to_transform(reset_transform: Transform3D, suspend_physics := true) -> void:
	restore_capture_physics()
	clear_score_contact_candidate()
	freeze = false
	global_transform = reset_transform
	linear_velocity = Vector3.ZERO
	_previous_physics_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	sleeping = false

	if suspend_physics:
		_set_held_physics()
	else:
		_set_flight_physics()


func set_grabbable(is_grabbable: bool) -> void:
	can_be_grabbed = is_grabbable


func can_be_grabbed_by(_grabber: Node3D) -> bool:
	return can_be_grabbed


func get_score_contact_candidate() -> Node3D:
	if _latched_score_cup == null or not is_instance_valid(_latched_score_cup):
		clear_score_contact_candidate()
		return null
	return _latched_score_cup


func get_score_contact_snapshot() -> Dictionary:
	return _latched_score_snapshot.duplicate(true)


func reject_score_contact_candidate(cup: Node3D) -> void:
	if cup == _latched_score_cup:
		clear_score_contact_candidate()


func clear_score_contact_candidate() -> void:
	_latched_score_cup = null
	_latched_score_snapshot.clear()
	_candidate_emit_queued = false


func begin_score_capture(cup: Node3D) -> bool:
	if cup == null or not is_instance_valid(cup) or not cup.has_method("get_capture_target_position"):
		return false
	if _capture_physics_suspended:
		return cup == _capture_cup

	var target_value: Variant = cup.call("get_capture_target_position", _get_ball_radius())
	if not target_value is Vector3:
		return false

	_capture_cup = cup
	_capture_finished = false
	_pre_capture_grabbable = can_be_grabbed
	can_be_grabbed = false
	_score_contacts_enabled = false
	suspend_physics_for_capture()
	_set_collision_shapes_disabled(true)

	_capture_tween = create_tween()
	_capture_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_capture_tween.set_trans(Tween.TRANS_QUAD)
	_capture_tween.set_ease(Tween.EASE_IN_OUT)
	_capture_tween.tween_property(self, "global_position", target_value, maxf(score_capture_seconds, 0.01))
	_capture_tween.finished.connect(_on_score_capture_tween_finished)
	return true


func is_score_capture_finished_for(cup: Node3D) -> bool:
	return _capture_finished and cup == _capture_cup


func suspend_physics_for_capture() -> void:
	if _capture_physics_suspended:
		return

	_capture_physics_suspended = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	continuous_cd = false
	freeze = true
	sleeping = true


func restore_capture_physics() -> void:
	var was_captured := _capture_physics_suspended or _capture_cup != null
	if _capture_tween != null and _capture_tween.is_valid():
		_capture_tween.kill()
	_capture_tween = null
	_set_collision_shapes_disabled(false)

	if _capture_physics_suspended:
		_capture_physics_suspended = false
		collision_layer = _default_collision_layer
		collision_mask = _default_collision_mask
		continuous_cd = continuous_collision_detection
		freeze = false
		sleeping = false

	if was_captured:
		can_be_grabbed = _pre_capture_grabbable
	_capture_cup = null
	_capture_finished = false


func _inspect_native_cup_contacts(state: PhysicsDirectBodyState3D) -> void:
	var best_cup: Node3D
	var best_snapshot: Dictionary = {}
	var incoming_velocity := state.linear_velocity
	if _previous_physics_velocity.y < incoming_velocity.y:
		incoming_velocity = _previous_physics_velocity

	for contact_index in range(state.get_contact_count()):
		var collider := state.get_contact_collider_object(contact_index) as Node3D
		if collider == null or not is_instance_valid(collider):
			continue
		if not collider.has_method("classify_score_contact"):
			continue

		var result: Variant = collider.call(
			"classify_score_contact",
			state.get_contact_collider_position(contact_index),
			# Direct-body contact vectors are already world-space; "local" identifies this body.
			state.get_contact_local_normal(contact_index),
			incoming_velocity,
			_get_ball_radius()
		)
		if not result is Dictionary or result.is_empty():
			continue

		var snapshot: Dictionary = result.duplicate(true)
		snapshot["contact_index"] = contact_index
		if _is_better_score_candidate(collider, snapshot, best_cup, best_snapshot):
			best_cup = collider
			best_snapshot = snapshot

	if best_cup != null:
		_latch_score_contact(best_cup, best_snapshot)


func _is_better_score_candidate(
	cup: Node3D,
	snapshot: Dictionary,
	current_cup: Node3D,
	current_snapshot: Dictionary
) -> bool:
	if current_cup == null:
		return true

	var edge_clearance := float(snapshot.get("edge_clearance", 0.0))
	var current_clearance := float(current_snapshot.get("edge_clearance", 0.0))
	if edge_clearance > current_clearance + SCORE_CANDIDATE_TIE_EPSILON:
		return true
	if absf(edge_clearance - current_clearance) > SCORE_CANDIDATE_TIE_EPSILON:
		return false
	return int(cup.get_meta("cup_index", 2147483647)) < int(current_cup.get_meta("cup_index", 2147483647))


func _latch_score_contact(cup: Node3D, snapshot: Dictionary) -> void:
	_latched_score_cup = cup
	_latched_score_snapshot = snapshot.duplicate(true)
	if _candidate_emit_queued:
		return

	_candidate_emit_queued = true
	call_deferred("_emit_latched_score_contact", cup.get_instance_id())


func _emit_latched_score_contact(expected_cup_id: int) -> void:
	_candidate_emit_queued = false
	var cup := get_score_contact_candidate()
	if cup == null or cup.get_instance_id() != expected_cup_id:
		return
	score_contact_detected.emit(self, cup, get_score_contact_snapshot())


func _on_score_capture_tween_finished() -> void:
	_capture_tween = null
	if _capture_cup == null or not is_instance_valid(_capture_cup):
		return
	_capture_finished = true
	score_capture_finished.emit(self, _capture_cup)


func _set_collision_shapes_disabled(is_disabled: bool) -> void:
	for child in get_children():
		var collision_shape := child as CollisionShape3D
		if collision_shape != null:
			collision_shape.set_deferred("disabled", is_disabled)


func _get_ball_radius() -> float:
	for child in get_children():
		var collision_shape := child as CollisionShape3D
		if collision_shape == null:
			continue
		var sphere_shape := collision_shape.shape as SphereShape3D
		if sphere_shape != null:
			return sphere_shape.radius
	return DEFAULT_BALL_RADIUS


func _create_ball_material() -> PhysicsMaterial:
	var material := PhysicsMaterial.new()
	material.bounce = bounce
	material.friction = friction
	return material


func _set_held_physics() -> void:
	_score_contacts_enabled = false
	gravity_scale = held_gravity_scale
	linear_damp = held_linear_damp
	angular_damp = 0.0


func _set_flight_physics() -> void:
	_score_contacts_enabled = true
	gravity_scale = flight_gravity_scale
	linear_damp = flight_linear_damp
	angular_damp = flight_angular_damp
