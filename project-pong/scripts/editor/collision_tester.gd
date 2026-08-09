extends Node3D
class_name CollisionTester

const FRUSTUM_SHADER := preload("res://shaders/conic_frustum_visual.gdshader")
const EPSILON := 0.0001
const MIN_SEGMENTS := 8
const MAX_SEGMENTS := 128

@export var cup_model_path: NodePath
@export var ball_model_path: NodePath
@export var frustum_visual_path: NodePath
@export var camera_path: NodePath
@export var ui_root_path: NodePath
@export var visualization_enabled := true
@export var bottom_y := 0.006
@export var rim_y := 0.058
@export var bottom_radius := 0.030
@export var rim_radius := 0.046
@export_range(8, 128, 1) var radial_segments := 48
@export var volume_color := Color(0.18, 0.78, 1.0, 0.2)
@export var line_color := Color(1.0, 0.94, 0.38, 0.85)

var _cup_model: Node3D
var _ball_model: Node3D
var _frustum_visual: MeshInstance3D
var _testing_camera: Camera3D
var _ui_root: Control
var _frustum_material: ShaderMaterial
var _ui_updating := false

var _visible_check: CheckBox
var _bottom_radius_spin: SpinBox
var _rim_radius_spin: SpinBox
var _bottom_y_spin: SpinBox
var _rim_y_spin: SpinBox
var _segments_spin: SpinBox
var _summary_label: Label


func _ready() -> void:
	if OS.has_feature("template"):
		push_warning("[CollisionTester] Editor-only collision tester is disabled in exported builds.")
		set_process(false)
		return

	_bind_scene_nodes()
	_create_frustum_material()
	_rebuild_frustum_visual()
	_apply_default_camera()
	_build_ui()
	_refresh_ui()


func _unhandled_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return

	if key_event.keycode == KEY_V:
		set_visualization_enabled(not visualization_enabled)
		get_viewport().set_input_as_handled()


func configure_frustum(
	new_bottom_radius: float,
	new_rim_radius: float,
	new_bottom_y: float,
	new_rim_y: float,
	new_radial_segments: int
) -> void:
	bottom_radius = maxf(new_bottom_radius, EPSILON)
	rim_radius = maxf(new_rim_radius, EPSILON)
	bottom_y = new_bottom_y
	rim_y = new_rim_y
	radial_segments = clampi(new_radial_segments, MIN_SEGMENTS, MAX_SEGMENTS)
	if absf(rim_y - bottom_y) <= EPSILON:
		rim_y = bottom_y + EPSILON

	_rebuild_frustum_visual()
	_refresh_ui()


func set_visualization_enabled(is_enabled: bool) -> void:
	visualization_enabled = is_enabled
	if _frustum_visual != null:
		_frustum_visual.visible = visualization_enabled
	_refresh_ui()


func get_radius_at_y(local_y: float) -> float:
	var height := _get_height()
	var y_ratio := clampf((local_y - bottom_y) / height, 0.0, 1.0)
	return lerpf(bottom_radius, rim_radius, y_ratio)


func is_local_point_inside_frustum(local_position: Vector3) -> bool:
	var min_y := minf(bottom_y, rim_y)
	var max_y := maxf(bottom_y, rim_y)
	if local_position.y < min_y or local_position.y > max_y:
		return false

	var horizontal_radius := Vector2(local_position.x, local_position.z).length()
	return horizontal_radius <= get_radius_at_y(local_position.y)


func get_side_normal_at_local_position(local_position: Vector3) -> Vector3:
	var radial := Vector2(local_position.x, local_position.z)
	if radial.length_squared() <= EPSILON:
		return Vector3.UP

	var slope := (rim_radius - bottom_radius) / _get_height()
	var radial_direction := radial.normalized()
	return Vector3(radial_direction.x, -slope, radial_direction.y).normalized()


func get_frustum_snapshot() -> Dictionary:
	return {
		"bottom_radius": bottom_radius,
		"rim_radius": rim_radius,
		"bottom_y": bottom_y,
		"rim_y": rim_y,
		"height": _get_height(),
		"radial_segments": radial_segments,
		"visualization_enabled": visualization_enabled,
	}


func _bind_scene_nodes() -> void:
	_cup_model = get_node_or_null(cup_model_path) as Node3D
	_ball_model = get_node_or_null(ball_model_path) as Node3D
	_frustum_visual = get_node_or_null(frustum_visual_path) as MeshInstance3D
	_testing_camera = get_node_or_null(camera_path) as Camera3D
	_ui_root = get_node_or_null(ui_root_path) as Control

	if _cup_model == null:
		push_warning("[CollisionTester] Cup model path is not configured.")
	if _ball_model == null:
		push_warning("[CollisionTester] Ball model path is not configured.")
	if _frustum_visual == null:
		push_error("[CollisionTester] Frustum visual MeshInstance3D is not configured.")


func _create_frustum_material() -> void:
	_frustum_material = ShaderMaterial.new()
	_frustum_material.shader = FRUSTUM_SHADER
	_frustum_material.set_shader_parameter("volume_color", volume_color)
	_frustum_material.set_shader_parameter("line_color", line_color)
	_frustum_material.set_shader_parameter("vertical_line_count", float(radial_segments) / 2.0)


func _rebuild_frustum_visual() -> void:
	if _frustum_visual == null:
		return

	_frustum_visual.mesh = _build_conic_frustum_mesh()
	_frustum_visual.material_override = _frustum_material
	_frustum_visual.visible = visualization_enabled
	if _frustum_material != null:
		_frustum_material.set_shader_parameter("vertical_line_count", float(radial_segments) / 2.0)


func _build_conic_frustum_mesh() -> ArrayMesh:
	var safe_segments := clampi(radial_segments, MIN_SEGMENTS, MAX_SEGMENTS)
	var safe_bottom_radius := maxf(bottom_radius, EPSILON)
	var safe_rim_radius := maxf(rim_radius, EPSILON)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var slope := (safe_rim_radius - safe_bottom_radius) / _get_height()

	for segment_index in range(safe_segments + 1):
		var u := float(segment_index) / float(safe_segments)
		var angle := TAU * u
		var angle_cos := cos(angle)
		var angle_sin := sin(angle)
		var side_normal := Vector3(angle_cos, -slope, angle_sin).normalized()

		vertices.append(Vector3(angle_cos * safe_bottom_radius, bottom_y, angle_sin * safe_bottom_radius))
		normals.append(side_normal)
		uvs.append(Vector2(u, 0.0))

		vertices.append(Vector3(angle_cos * safe_rim_radius, rim_y, angle_sin * safe_rim_radius))
		normals.append(side_normal)
		uvs.append(Vector2(u, 1.0))

	for segment_index in range(safe_segments):
		var base_index := segment_index * 2
		indices.append(base_index)
		indices.append(base_index + 1)
		indices.append(base_index + 2)
		indices.append(base_index + 1)
		indices.append(base_index + 3)
		indices.append(base_index + 2)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _apply_default_camera() -> void:
	if _testing_camera == null:
		return

	_testing_camera.global_position = Vector3(0.18, 0.17, 0.26)
	_testing_camera.look_at(Vector3(0.0, 0.045, 0.0), Vector3.UP)
	_testing_camera.current = true


func _build_ui() -> void:
	if _ui_root == null:
		return

	for child in _ui_root.get_children():
		_ui_root.remove_child(child)
		child.queue_free()

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.anchor_left = 0.01
	panel.anchor_top = 0.02
	panel.anchor_right = 0.32
	panel.anchor_bottom = 0.54
	_ui_root.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var main_vbox := VBoxContainer.new()
	main_vbox.name = "VBox"
	margin.add_child(main_vbox)

	var title := Label.new()
	title.text = "Collision Tester"
	title.add_theme_font_size_override("font_size", 18)
	main_vbox.add_child(title)

	_summary_label = Label.new()
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_vbox.add_child(_summary_label)

	_visible_check = CheckBox.new()
	_visible_check.text = "Show frustum"
	_visible_check.toggled.connect(_on_visibility_toggled)
	main_vbox.add_child(_visible_check)

	_bottom_radius_spin = _add_spin_row(main_vbox, "Bottom Radius", bottom_radius, 0.001, 0.12, 0.001, _on_bottom_radius_changed)
	_rim_radius_spin = _add_spin_row(main_vbox, "Rim Radius", rim_radius, 0.001, 0.14, 0.001, _on_rim_radius_changed)
	_bottom_y_spin = _add_spin_row(main_vbox, "Bottom Y", bottom_y, -0.05, 0.2, 0.001, _on_bottom_y_changed)
	_rim_y_spin = _add_spin_row(main_vbox, "Rim Y", rim_y, -0.05, 0.24, 0.001, _on_rim_y_changed)
	_segments_spin = _add_spin_row(main_vbox, "Segments", float(radial_segments), float(MIN_SEGMENTS), float(MAX_SEGMENTS), 1.0, _on_segments_changed)

	var reset_button := Button.new()
	reset_button.text = "Reset Defaults"
	reset_button.pressed.connect(_on_reset_defaults_pressed)
	main_vbox.add_child(reset_button)


func _add_spin_row(
	parent: Control,
	label_text: String,
	value: float,
	min_value: float,
	max_value: float,
	step: float,
	callback: Callable
) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(116.0, 0.0)
	row.add_child(label)

	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.value = value
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(callback)
	row.add_child(spin)
	return spin


func _refresh_ui() -> void:
	if _ui_root == null:
		return

	_ui_updating = true
	if _visible_check != null:
		_visible_check.button_pressed = visualization_enabled
	if _bottom_radius_spin != null:
		_bottom_radius_spin.value = bottom_radius
	if _rim_radius_spin != null:
		_rim_radius_spin.value = rim_radius
	if _bottom_y_spin != null:
		_bottom_y_spin.value = bottom_y
	if _rim_y_spin != null:
		_rim_y_spin.value = rim_y
	if _segments_spin != null:
		_segments_spin.value = radial_segments
	if _summary_label != null:
		_summary_label.text = "r(y) %.3f to %.3f, height %.3f m" % [bottom_radius, rim_radius, _get_height()]
	_ui_updating = false


func _on_visibility_toggled(is_enabled: bool) -> void:
	if _ui_updating:
		return
	set_visualization_enabled(is_enabled)


func _on_bottom_radius_changed(value: float) -> void:
	if _ui_updating:
		return
	bottom_radius = maxf(value, EPSILON)
	_rebuild_frustum_visual()
	_refresh_ui()


func _on_rim_radius_changed(value: float) -> void:
	if _ui_updating:
		return
	rim_radius = maxf(value, EPSILON)
	_rebuild_frustum_visual()
	_refresh_ui()


func _on_bottom_y_changed(value: float) -> void:
	if _ui_updating:
		return
	bottom_y = value
	_ensure_positive_height()
	_rebuild_frustum_visual()
	_refresh_ui()


func _on_rim_y_changed(value: float) -> void:
	if _ui_updating:
		return
	rim_y = value
	_ensure_positive_height()
	_rebuild_frustum_visual()
	_refresh_ui()


func _on_segments_changed(value: float) -> void:
	if _ui_updating:
		return
	radial_segments = clampi(int(round(value)), MIN_SEGMENTS, MAX_SEGMENTS)
	_rebuild_frustum_visual()
	_refresh_ui()


func _on_reset_defaults_pressed() -> void:
	configure_frustum(0.030, 0.046, 0.006, 0.058, 48)


func _ensure_positive_height() -> void:
	if rim_y <= bottom_y + EPSILON:
		rim_y = bottom_y + EPSILON


func _get_height() -> float:
	return maxf(rim_y - bottom_y, EPSILON)
