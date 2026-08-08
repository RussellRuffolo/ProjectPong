extends Area3D
class_name HouseRuleToggle

signal pressed(menu_button)
signal toggled(rule_id: StringName, is_enabled: bool)

@export var rule_id := &""
@export var label_text := "House Rule"
@export var enabled := true
@export var selectable := true
@export var size := Vector2(1.28, 0.115)
@export var enabled_color := Color(0.0, 0.58, 0.45, 1.0)
@export var disabled_color := Color(0.25, 0.27, 0.28, 1.0)
@export var hover_color := Color(0.08, 0.18, 0.17, 1.0)
@export var row_color := Color(0.07, 0.08, 0.08, 1.0)

var _hovered := false
var _row_material: StandardMaterial3D
var _track_material: StandardMaterial3D
var _knob_material: StandardMaterial3D
var _label: Label3D
var _state_label: Label3D
var _knob: MeshInstance3D
var _collision_shape: CollisionShape3D


func _ready() -> void:
	_build_visuals()
	_apply_visual_state()


func set_rule_state(next_rule_id: StringName, next_label_text: String, next_enabled: bool) -> void:
	rule_id = next_rule_id
	label_text = next_label_text
	enabled = next_enabled
	_apply_visual_state()


func set_enabled(next_enabled: bool) -> void:
	if enabled == next_enabled:
		return
	enabled = next_enabled
	_apply_visual_state()


func set_selectable(is_selectable: bool) -> void:
	selectable = is_selectable
	_apply_visual_state()


func set_hovered(is_hovered: bool) -> void:
	if _hovered == is_hovered:
		return
	_hovered = is_hovered
	_apply_visual_state()


func activate() -> void:
	if not selectable:
		return

	enabled = not enabled
	_apply_visual_state()
	pressed.emit(self)
	toggled.emit(rule_id, enabled)


func _build_visuals() -> void:
	var row := MeshInstance3D.new()
	row.name = "Row"
	var row_mesh := BoxMesh.new()
	row_mesh.size = Vector3(size.x, size.y, 0.026)
	row.mesh = row_mesh
	_row_material = StandardMaterial3D.new()
	_row_material.roughness = 0.72
	row.material_override = _row_material
	add_child(row)

	_collision_shape = CollisionShape3D.new()
	_collision_shape.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, size.y, 0.07)
	_collision_shape.shape = shape
	add_child(_collision_shape)

	_label = Label3D.new()
	_label.name = "Label"
	_label.position = Vector3(-0.21, 0.0, 0.024)
	_label.pixel_size = 0.00135
	_label.font_size = 31
	_label.outline_size = 5
	_label.outline_modulate = Color(0.015, 0.018, 0.018, 1.0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)

	var track := MeshInstance3D.new()
	track.name = "Track"
	track.position = Vector3(0.47, 0.0, 0.034)
	var track_mesh := BoxMesh.new()
	track_mesh.size = Vector3(0.24, 0.07, 0.026)
	track.mesh = track_mesh
	_track_material = StandardMaterial3D.new()
	_track_material.roughness = 0.6
	track.material_override = _track_material
	add_child(track)

	_knob = MeshInstance3D.new()
	_knob.name = "Knob"
	var knob_mesh := BoxMesh.new()
	knob_mesh.size = Vector3(0.078, 0.052, 0.035)
	_knob.mesh = knob_mesh
	_knob_material = StandardMaterial3D.new()
	_knob_material.roughness = 0.5
	_knob.material_override = _knob_material
	add_child(_knob)

	_state_label = Label3D.new()
	_state_label.name = "StateLabel"
	_state_label.position = Vector3(0.47, -0.001, 0.058)
	_state_label.pixel_size = 0.001
	_state_label.font_size = 25
	_state_label.outline_size = 4
	_state_label.outline_modulate = Color(0.015, 0.018, 0.018, 1.0)
	_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_state_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_state_label)


func _apply_visual_state() -> void:
	if _collision_shape != null:
		_collision_shape.disabled = not selectable

	if _row_material == null or _track_material == null or _knob_material == null or _label == null or _state_label == null or _knob == null:
		return

	_row_material.albedo_color = hover_color if _hovered and selectable else row_color
	_track_material.albedo_color = enabled_color if enabled else disabled_color
	_knob_material.albedo_color = Color(0.92, 0.96, 0.88, 1.0) if enabled else Color(0.62, 0.64, 0.64, 1.0)
	_label.text = label_text
	_label.modulate = Color(1.0, 0.96, 0.86, 1.0) if selectable else Color(0.58, 0.6, 0.6, 1.0)
	_state_label.text = "ON" if enabled else "OFF"
	_state_label.modulate = Color(1.0, 0.96, 0.86, 1.0) if selectable else Color(0.58, 0.6, 0.6, 1.0)
	_knob.position = Vector3(0.525 if enabled else 0.415, 0.0, 0.058)
