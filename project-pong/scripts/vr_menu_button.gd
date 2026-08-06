extends Area3D
class_name VRMenuButton

signal pressed(menu_button: VRMenuButton)

@export var label_text := "Menu Button"
@export var target_scene_path := ""
@export var selectable := true
@export var size := Vector2(0.95, 0.18)
@export var enabled_color := Color(0.08, 0.38, 0.32, 1.0)
@export var hovered_color := Color(0.0, 0.68, 0.56, 1.0)
@export var disabled_color := Color(0.16, 0.17, 0.18, 1.0)
@export var text_color := Color(1.0, 0.96, 0.86, 1.0)
@export var disabled_text_color := Color(0.58, 0.6, 0.6, 1.0)

var _hovered := false
var _panel_material: StandardMaterial3D
var _label: Label3D


func _ready() -> void:
	_build_visuals()
	_apply_visual_state()


func set_hovered(is_hovered: bool) -> void:
	if _hovered == is_hovered:
		return

	_hovered = is_hovered
	_apply_visual_state()


func activate() -> void:
	if not selectable:
		return

	pressed.emit(self)


func _build_visuals() -> void:
	var panel := MeshInstance3D.new()
	panel.name = "Panel"
	var panel_mesh := BoxMesh.new()
	panel_mesh.size = Vector3(size.x, size.y, 0.035)
	panel.mesh = panel_mesh

	_panel_material = StandardMaterial3D.new()
	_panel_material.roughness = 0.68
	_panel_material.metallic = 0.0
	panel.material_override = _panel_material
	add_child(panel)

	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "CollisionShape3D"
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(size.x, size.y, 0.06)
	collision_shape.shape = box_shape
	add_child(collision_shape)

	_label = Label3D.new()
	_label.name = "Label"
	_label.position = Vector3(0.0, 0.0, 0.026)
	_label.pixel_size = 0.00165
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.text = label_text

	_label.font_size = 42
	_label.outline_size = 6
	_label.outline_modulate = Color(0.02, 0.025, 0.025, 1.0)
	add_child(_label)


func _apply_visual_state() -> void:
	if _panel_material == null or _label == null:
		return

	if not selectable:
		_panel_material.albedo_color = disabled_color
		_label.modulate = disabled_text_color
	elif _hovered:
		_panel_material.albedo_color = hovered_color
		_label.modulate = text_color
	else:
		_panel_material.albedo_color = enabled_color
		_label.modulate = text_color
