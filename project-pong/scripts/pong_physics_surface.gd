extends StaticBody3D
class_name PongPhysicsSurface

@export var surface_id := &"default"
@export_range(0.0, 1.0, 0.01) var bounce := 0.1
@export_range(0.0, 1.0, 0.01) var friction := 0.8
@export var absorbs_ball_bounce := false
@export var rough := false


func _ready() -> void:
	apply_physics_material()


func configure(
	new_surface_id: StringName,
	new_bounce: float,
	new_friction: float,
	new_absorbs_ball_bounce: bool,
	new_rough := false
) -> void:
	surface_id = new_surface_id
	bounce = new_bounce
	friction = new_friction
	absorbs_ball_bounce = new_absorbs_ball_bounce
	rough = new_rough
	apply_physics_material()


func apply_physics_material() -> void:
	var material := PhysicsMaterial.new()
	material.bounce = bounce
	material.friction = friction
	material.absorbent = absorbs_ball_bounce
	material.rough = rough
	physics_material_override = material
