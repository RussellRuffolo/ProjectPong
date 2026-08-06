extends RigidBody3D
class_name ThrowableBall

@export_range(0.0, 1.0, 0.01) var bounce := 0.82
@export_range(0.0, 1.0, 0.01) var friction := 0.06
@export var held_gravity_scale := 0.0
@export var flight_gravity_scale := 1.0
@export var held_linear_damp := 0.0
@export var flight_linear_damp := 0.03
@export var flight_angular_damp := 0.08
@export var release_spin := Vector3(0.0, 0.0, 8.0)
@export var starts_suspended := true


func _ready() -> void:
	physics_material_override = _create_ball_material()
	contact_monitor = true
	max_contacts_reported = max(max_contacts_reported, 4)
	if starts_suspended:
		_set_held_physics()
	else:
		_set_flight_physics()
	print("[Ball] Throwable ball ready with bounce %.2f and friction %.2f." % [bounce, friction])


func on_grabbed(_grabber: Node3D) -> void:
	_set_held_physics()
	sleeping = false


func on_released(_grabber: Node3D, release_linear_velocity: Vector3, _release_angular_velocity: Vector3) -> void:
	_set_flight_physics()
	linear_velocity = release_linear_velocity
	angular_velocity = release_spin
	sleeping = false
	print("[Ball] Released with velocity %s." % linear_velocity)


func _create_ball_material() -> PhysicsMaterial:
	var material := PhysicsMaterial.new()
	material.bounce = bounce
	material.friction = friction
	return material


func _set_held_physics() -> void:
	gravity_scale = held_gravity_scale
	linear_damp = held_linear_damp
	angular_damp = 0.0


func _set_flight_physics() -> void:
	gravity_scale = flight_gravity_scale
	linear_damp = flight_linear_damp
	angular_damp = flight_angular_damp
