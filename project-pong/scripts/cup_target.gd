extends StaticBody3D
class_name CupTarget

const CupLiquidVisualScript := preload("res://scripts/cup_liquid_visual.gd")

@export var liquid_enabled := true
@export var liquid_scene: PackedScene
@export_range(0.0, 1.0, 0.01) var liquid_fill_ratio := 0.38
@export var liquid_radius := 0.036
@export var liquid_height := 0.085
@export var liquid_bottom_y := 0.006
@export var cup_bottom_y := 0.006
@export var cup_top_y := 0.058
@export var cup_top_radius := 0.046
@export var top_height_tolerance := 0.003
@export_range(0.0, 1.0, 0.001) var minimum_vertical_normal_dot := 0.966
@export var minimum_entry_speed := 0.15
@export_range(0.0, 2.0, 0.05) var score_edge_inset_ball_radius_scale := 0.5

var surface_id := &"cup"
var _has_scored := false
var _liquid_visual: Node3D


func _ready() -> void:
	add_to_group("cup_target")
	_has_scored = bool(get_meta("is_scored", false))
	_add_liquid_visual()


func classify_score_contact(
	world_contact_point: Vector3,
	world_contact_normal: Vector3,
	world_ball_velocity: Vector3,
	ball_radius: float
) -> Dictionary:
	if _has_scored or bool(get_meta("is_scored", false)):
		return {}
	if world_contact_normal.length_squared() <= 0.000001:
		return {}

	var local_point := to_local(world_contact_point)
	var local_normal := (global_basis.inverse() * world_contact_normal).normalized()
	var local_velocity := global_basis.inverse() * world_ball_velocity
	var radial_distance := Vector2(local_point.x, local_point.z).length()
	var edge_clearance := cup_top_radius - radial_distance
	var at_top_cap := absf(local_point.y - cup_top_y) <= top_height_tolerance
	var is_vertical := absf(local_normal.dot(Vector3.UP)) >= minimum_vertical_normal_dot
	var is_entering := local_velocity.y <= -minimum_entry_speed
	var is_inside_score_region := edge_clearance >= ball_radius * score_edge_inset_ball_radius_scale

	if not (at_top_cap and is_vertical and is_entering and is_inside_score_region):
		return {}

	return {
		"cup_index": int(get_meta("cup_index", -1)),
		"owner_slot": int(get_meta("owner_slot", 0)),
		"owner_side": str(get_meta("owner_side", "")),
		"world_contact_point": world_contact_point,
		"world_contact_normal": world_contact_normal.normalized(),
		"local_contact_point": local_point,
		"local_contact_normal": local_normal,
		"edge_clearance": edge_clearance,
		"entry_speed": -local_velocity.y,
	}


func mark_scored() -> void:
	_has_scored = true
	set_meta("is_scored", true)


func is_scored() -> bool:
	return _has_scored


func remove_from_game() -> void:
	mark_scored()
	_set_liquid_visible(false)
	queue_free()


func get_rim_center_position() -> Vector3:
	return to_global(Vector3(0.0, cup_top_y, 0.0))


func get_top_center_position() -> Vector3:
	return get_rim_center_position()


func get_capture_target_position(ball_radius: float) -> Vector3:
	return to_global(Vector3(0.0, cup_bottom_y + ball_radius, 0.0))


func _add_liquid_visual() -> void:
	if not liquid_enabled:
		return

	var liquid := liquid_scene.instantiate() as Node3D if liquid_scene != null else CupLiquidVisualScript.new() as Node3D
	if liquid == null:
		return

	liquid.name = "Liquid"
	liquid.set("fill_ratio", liquid_fill_ratio)
	liquid.set("liquid_radius", liquid_radius)
	liquid.set("liquid_height", liquid_height)
	liquid.set("liquid_bottom_y", liquid_bottom_y)
	_liquid_visual = liquid
	add_child(liquid)


func _set_liquid_visible(is_visible: bool) -> void:
	if _liquid_visual == null or not is_instance_valid(_liquid_visual):
		return
	if _liquid_visual.has_method("set_liquid_visible"):
		_liquid_visual.call("set_liquid_visible", is_visible)
	else:
		_liquid_visual.visible = is_visible
