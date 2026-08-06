extends Node3D
class_name CupTarget

signal scored(cup: Node3D)

@export var visual_scene: PackedScene
@export var collision_scene: PackedScene
@export var score_area_radius := 0.032
@export var score_area_height := 0.11
@export var score_area_center_y := 0.058
@export_range(0.0, 1.0, 0.01) var cup_bounce := 0.12
@export_range(0.0, 1.0, 0.01) var cup_friction := 0.85

var _has_scored := false


func _ready() -> void:
	_add_visual()
	_add_collision()
	_add_score_area()


func remove_from_game() -> void:
	_has_scored = true
	queue_free()


func _add_visual() -> void:
	if visual_scene == null:
		push_warning("[Cup] No cup visual scene assigned.")
		return

	var visual := visual_scene.instantiate()
	visual.name = "Visual"
	add_child(visual)


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
			var body := StaticBody3D.new()
			body.name = "%sBody" % mesh_instance.name
			body.transform = local_transform
			body.physics_material_override = _create_cup_material()
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

	_has_scored = true
	scored.emit(self)


func _is_score_body(body: Node3D) -> bool:
	return body is ThrowableBall or body.is_in_group("game_ball")


func _create_cup_material() -> PhysicsMaterial:
	var material := PhysicsMaterial.new()
	material.bounce = cup_bounce
	material.friction = cup_friction
	return material
