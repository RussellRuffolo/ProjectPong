extends Node3D
class_name CupTarget

const PongPhysicsSurfaceScript := preload("res://scripts/pong_physics_surface.gd")
const CupLiquidVisualScript := preload("res://scripts/cup_liquid_visual.gd")

@export var visual_scene: PackedScene
@export var collision_scene: PackedScene
@export var liquid_enabled := true
@export var liquid_scene: PackedScene
@export_range(0.0, 1.0, 0.01) var liquid_fill_ratio := 0.38
@export var liquid_radius := 0.036
@export var liquid_height := 0.085
@export var liquid_bottom_y := 0.006
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
@export_range(0.0, 1.0, 0.01) var cup_bottom_bounce_absorption := 0.9
@export_range(0.0, 1.0, 0.01) var cup_bottom_friction := 0.96
@export var cup_bottom_absorbs_ball_bounce := true
@export var cup_bottom_rough := true

var _has_scored := false
var _score_bodies: Array[Node3D] = []
var _liquid_visual: Node3D


func _ready() -> void:
	_add_visual()
	_add_liquid_visual()
	_add_collision()
	_add_score_area()


func remove_from_game() -> void:
	_has_scored = true
	_set_liquid_visible(false)
	queue_free()


func is_ball_resting_inside(ball: Node3D) -> bool:
	if _has_scored or ball == null or not is_instance_valid(ball):
		return false
	if not _score_bodies.has(ball):
		return false

	var local_ball_position := global_transform.affine_inverse() * ball.global_position
	var horizontal_distance := Vector2(local_ball_position.x, local_ball_position.z).length()
	return (
		horizontal_distance <= resting_score_radius
		and local_ball_position.y >= resting_score_min_y
		and local_ball_position.y <= resting_score_max_y
	)


func mark_scored() -> void:
	_has_scored = true
	_set_liquid_visible(false)


func is_scored() -> bool:
	return _has_scored


func get_rim_center_position() -> Vector3:
	var local_top_center := Vector3(0.0, rim_center_y, 0.0)
	return global_transform * local_top_center


func get_top_center_position() -> Vector3:
	return get_rim_center_position()


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
	_apply_score_capture(body)


func _on_score_area_body_exited(body: Node3D) -> void:
	_score_bodies.erase(body)


func _exit_tree() -> void:
	_score_bodies.clear()


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
