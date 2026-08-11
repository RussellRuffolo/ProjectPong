extends Node3D
class_name CollisionTester

const FRUSTUM_SHADER := preload("res://shaders/conic_frustum_visual.gdshader")
const ConicFrustumCollisionScript := preload("res://scripts/match/conic_frustum_collision.gd")
const EPSILON := 0.0001
const MIN_SEGMENTS := 8
const MAX_SEGMENTS := 128
const AXIS_X := 0
const AXIS_Y := 1
const AXIS_Z := 2
const CLASS_OUTSIDE := "outside"
const CLASS_SIDE_WALL := "side_wall"
const CLASS_INSIDE_VOLUME := "inside_volume"
const CLASS_TOP_INNER := "top_inner"
const CLASS_TOP_RIM_BAND := "top_rim_band"
const CLASS_BOTTOM_CAP := "bottom_cap"

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
@export var ball_radius := 0.02
@export var ball_intersect_color := Color(0.1, 0.82, 0.28, 1.0)
@export var ball_miss_color := Color(1.0, 0.12, 0.08, 1.0)
@export var ball_top_inner_color := Color(0.1, 0.42, 1.0, 1.0)
@export var ball_rim_band_color := Color(1.0, 0.86, 0.08, 1.0)
@export_range(0.05, 2.0, 0.01) var rim_band_ball_radius_scale := 0.6
@export var axis_gizmo_enabled := true
@export var axis_gizmo_length := 0.11
@export var axis_gizmo_radius := 0.0025
@export var axis_gizmo_cone_length := 0.022
@export var axis_gizmo_pick_radius_pixels := 28.0
@export var normal_vector_enabled := true
@export var normal_vector_color := Color(1.0, 0.68, 0.12, 1.0)
@export var normal_vector_radius := 0.002
@export var normal_vector_cone_length := 0.018

var _cup_model: Node3D
var _ball_model: Node3D
var _ball_mesh: MeshInstance3D
var _frustum_visual: MeshInstance3D
var _testing_camera: Camera3D
var _ui_root: Control
var _frustum_material: ShaderMaterial
var _ball_material: StandardMaterial3D
var _axis_gizmo_root: Node3D
var _normal_vector_root: Node3D
var _normal_vector_shaft: MeshInstance3D
var _normal_vector_tip: MeshInstance3D
var _normal_vector_material: StandardMaterial3D
var _ui_updating := false
var _dragging_axis := -1
var _drag_start_ball_position := Vector3.ZERO
var _drag_start_axis_parameter := 0.0
var _last_ball_position := Vector3.ZERO
var _has_last_ball_position := false
var _last_intersection_snapshot: Dictionary = {}
var _last_normal_snapshot: Dictionary = {}
var _default_bottom_y := 0.0
var _default_rim_y := 0.0
var _default_bottom_radius := 0.0
var _default_rim_radius := 0.0
var _default_radial_segments := 0
var _default_ball_radius := 0.0
var _default_rim_band_ball_radius_scale := 0.0

var _visible_check: CheckBox
var _normal_vector_check: CheckBox
var _ui_panel: PanelContainer
var _bottom_radius_spin: SpinBox
var _rim_radius_spin: SpinBox
var _bottom_y_spin: SpinBox
var _rim_y_spin: SpinBox
var _segments_spin: SpinBox
var _ball_radius_spin: SpinBox
var _rim_band_spin: SpinBox
var _summary_label: Label
var _intersection_label: Label
var _classification_label: Label
var _normal_vector_label: Label
var _ball_position_label: Label


func _ready() -> void:
	if OS.has_feature("template"):
		push_warning("[CollisionTester] Editor-only collision tester is disabled in exported builds.")
		set_process(false)
		return

	_bind_scene_nodes()
	_cache_initial_defaults()
	_create_frustum_material()
	_create_ball_status_material()
	_sync_ball_visual_radius()
	_create_axis_gizmos()
	_create_normal_vector_visual()
	_rebuild_frustum_visual()
	_apply_default_camera()
	_build_ui()
	_update_ball_intersection()
	_refresh_ui()
	set_process(true)


func _process(_delta: float) -> void:
	if _ball_model == null:
		return

	if not _has_last_ball_position or _ball_model.global_position.distance_squared_to(_last_ball_position) > EPSILON * EPSILON:
		_update_ball_intersection()


func _input(event: InputEvent) -> void:
	var mouse_button := event as InputEventMouseButton
	if mouse_button != null:
		_handle_mouse_button(mouse_button)
		return

	var mouse_motion := event as InputEventMouseMotion
	if mouse_motion != null:
		_handle_mouse_motion(mouse_motion)
		return


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
	if rim_y <= bottom_y + EPSILON:
		rim_y = bottom_y + EPSILON

	_rebuild_frustum_visual()
	_refresh_ui()


func set_visualization_enabled(is_enabled: bool) -> void:
	visualization_enabled = is_enabled
	if _frustum_visual != null:
		_frustum_visual.visible = visualization_enabled
	_refresh_ui()


func get_ball_frustum_intersection_snapshot() -> Dictionary:
	if _ball_model == null:
		return {}
	return calculate_ball_frustum_intersection(_ball_model.global_position, ball_radius)


func calculate_ball_frustum_intersection(ball_world_position: Vector3, radius: float) -> Dictionary:
	var local_position := global_transform.affine_inverse() * ball_world_position
	return calculate_local_sphere_frustum_intersection(local_position, radius)


func calculate_local_sphere_frustum_intersection(local_position: Vector3, radius: float) -> Dictionary:
	return ConicFrustumCollisionScript.calculate_local_sphere_frustum_intersection(
		local_position,
		radius,
		_get_collision_parameters(),
		global_transform
	)


func classify_local_sphere_frustum_overlap(
	local_position: Vector3,
	radius: float,
	intersects: bool,
	closest_feature: String
) -> Dictionary:
	return ConicFrustumCollisionScript.classify_local_sphere_frustum_overlap(
		local_position,
		radius,
		intersects,
		closest_feature,
		_get_collision_parameters()
	)


func calculate_local_nearest_surface_snapshot(local_position: Vector3) -> Dictionary:
	return ConicFrustumCollisionScript.calculate_local_nearest_surface_snapshot(
		local_position,
		_get_collision_parameters(),
		global_transform
	)


func get_radius_at_y(local_y: float) -> float:
	return ConicFrustumCollisionScript.get_radius_at_y(local_y, _get_collision_parameters())


func is_local_point_inside_frustum(local_position: Vector3) -> bool:
	return ConicFrustumCollisionScript.is_local_point_inside_frustum(local_position, _get_collision_parameters())


func get_side_normal_at_local_position(local_position: Vector3) -> Vector3:
	return ConicFrustumCollisionScript.get_side_normal_at_local_position(local_position, _get_collision_parameters())


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
	_ball_mesh = _ball_model as MeshInstance3D
	_frustum_visual = get_node_or_null(frustum_visual_path) as MeshInstance3D
	_testing_camera = get_node_or_null(camera_path) as Camera3D
	_ui_root = get_node_or_null(ui_root_path) as Control

	if _cup_model == null:
		push_warning("[CollisionTester] Cup model path is not configured.")
	if _ball_model == null:
		push_warning("[CollisionTester] Ball model path is not configured.")
	elif _ball_mesh == null:
		push_warning("[CollisionTester] Ball model should be a MeshInstance3D to support status coloring.")
	if _frustum_visual == null:
		push_error("[CollisionTester] Frustum visual MeshInstance3D is not configured.")


func _create_frustum_material() -> void:
	_frustum_material = ShaderMaterial.new()
	_frustum_material.shader = FRUSTUM_SHADER
	_frustum_material.set_shader_parameter("volume_color", volume_color)
	_frustum_material.set_shader_parameter("line_color", line_color)
	_frustum_material.set_shader_parameter("vertical_line_count", float(radial_segments) / 2.0)


func _cache_initial_defaults() -> void:
	_default_bottom_y = bottom_y
	_default_rim_y = rim_y
	_default_bottom_radius = bottom_radius
	_default_rim_radius = rim_radius
	_default_radial_segments = radial_segments
	_default_ball_radius = ball_radius
	_default_rim_band_ball_radius_scale = rim_band_ball_radius_scale


func _create_ball_status_material() -> void:
	if _ball_mesh == null:
		return

	var existing_material := _ball_mesh.material_override as StandardMaterial3D
	if existing_material != null:
		_ball_material = existing_material.duplicate() as StandardMaterial3D
	else:
		_ball_material = StandardMaterial3D.new()
		_ball_material.roughness = 0.72
	_ball_material.emission_enabled = true
	_ball_material.emission_energy_multiplier = 0.22
	_ball_mesh.material_override = _ball_material


func _sync_ball_visual_radius() -> void:
	if _ball_mesh == null:
		return

	var sphere := _ball_mesh.mesh as SphereMesh
	if sphere == null:
		return

	sphere.radius = maxf(ball_radius, EPSILON)
	sphere.height = maxf(ball_radius * 2.0, EPSILON)


func _create_axis_gizmos() -> void:
	if _ball_model == null:
		return

	if _axis_gizmo_root != null and is_instance_valid(_axis_gizmo_root):
		_axis_gizmo_root.queue_free()

	_axis_gizmo_root = Node3D.new()
	_axis_gizmo_root.name = "AxisGizmos"
	_axis_gizmo_root.visible = axis_gizmo_enabled
	_ball_model.add_child(_axis_gizmo_root)

	_add_axis_gizmo("XAxis", Vector3.RIGHT, Color(1.0, 0.08, 0.06, 1.0))
	_add_axis_gizmo("YAxis", Vector3.UP, Color(0.1, 0.85, 0.22, 1.0))
	_add_axis_gizmo("ZAxis", Vector3.BACK, Color(0.16, 0.42, 1.0, 1.0))


func _add_axis_gizmo(axis_name: String, local_axis: Vector3, axis_color: Color) -> void:
	if _axis_gizmo_root == null:
		return

	var axis_root := Node3D.new()
	axis_root.name = axis_name
	_axis_gizmo_root.add_child(axis_root)

	var shaft_length := maxf(axis_gizmo_length - axis_gizmo_cone_length, EPSILON)
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = axis_gizmo_radius
	shaft_mesh.bottom_radius = axis_gizmo_radius
	shaft_mesh.height = shaft_length
	shaft_mesh.radial_segments = 12

	var shaft := MeshInstance3D.new()
	shaft.name = "Shaft"
	shaft.mesh = shaft_mesh
	shaft.material_override = _create_axis_material(axis_color)
	shaft.transform = Transform3D(_get_basis_with_local_y(local_axis), local_axis.normalized() * shaft_length * 0.5)
	axis_root.add_child(shaft)

	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.0
	cone_mesh.bottom_radius = axis_gizmo_radius * 3.4
	cone_mesh.height = axis_gizmo_cone_length
	cone_mesh.radial_segments = 16

	var cone := MeshInstance3D.new()
	cone.name = "Arrow"
	cone.mesh = cone_mesh
	cone.material_override = _create_axis_material(axis_color)
	cone.transform = Transform3D(
		_get_basis_with_local_y(local_axis),
		local_axis.normalized() * (shaft_length + axis_gizmo_cone_length * 0.5)
	)
	axis_root.add_child(cone)


func _create_axis_material(axis_color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = axis_color
	material.emission_enabled = true
	material.emission = axis_color
	material.emission_energy_multiplier = 0.35
	material.roughness = 0.42
	return material


func _create_normal_vector_visual() -> void:
	if _normal_vector_root != null and is_instance_valid(_normal_vector_root):
		_normal_vector_root.queue_free()

	_normal_vector_material = StandardMaterial3D.new()
	_normal_vector_material.albedo_color = normal_vector_color
	_normal_vector_material.emission_enabled = true
	_normal_vector_material.emission = normal_vector_color
	_normal_vector_material.emission_energy_multiplier = 0.45
	_normal_vector_material.roughness = 0.38

	_normal_vector_root = Node3D.new()
	_normal_vector_root.name = "NormalVector"
	_normal_vector_root.visible = normal_vector_enabled
	add_child(_normal_vector_root)

	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = normal_vector_radius
	shaft_mesh.bottom_radius = normal_vector_radius
	shaft_mesh.height = 1.0
	shaft_mesh.radial_segments = 12
	_normal_vector_shaft = MeshInstance3D.new()
	_normal_vector_shaft.name = "Shaft"
	_normal_vector_shaft.mesh = shaft_mesh
	_normal_vector_shaft.material_override = _normal_vector_material
	_normal_vector_root.add_child(_normal_vector_shaft)

	var tip_mesh := CylinderMesh.new()
	tip_mesh.top_radius = 0.0
	tip_mesh.bottom_radius = normal_vector_radius * 3.5
	tip_mesh.height = 1.0
	tip_mesh.radial_segments = 16
	_normal_vector_tip = MeshInstance3D.new()
	_normal_vector_tip.name = "Arrow"
	_normal_vector_tip.mesh = tip_mesh
	_normal_vector_tip.material_override = _normal_vector_material
	_normal_vector_root.add_child(_normal_vector_tip)


func _rebuild_frustum_visual() -> void:
	if _frustum_visual == null:
		return

	_frustum_visual.mesh = _build_conic_frustum_mesh()
	_frustum_visual.material_override = _frustum_material
	_frustum_visual.visible = visualization_enabled
	if _frustum_material != null:
		_frustum_material.set_shader_parameter("vertical_line_count", float(radial_segments) / 2.0)
	_update_ball_intersection()


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
	panel.anchor_right = 0.42
	panel.anchor_bottom = 0.84
	_ui_root.add_child(panel)
	_ui_panel = panel

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

	_normal_vector_check = CheckBox.new()
	_normal_vector_check.text = "Show normal vector"
	_normal_vector_check.toggled.connect(_on_normal_vector_visibility_toggled)
	main_vbox.add_child(_normal_vector_check)

	_bottom_radius_spin = _add_spin_row(main_vbox, "Bottom Radius", bottom_radius, 0.001, 0.12, 0.001, _on_bottom_radius_changed)
	_rim_radius_spin = _add_spin_row(main_vbox, "Rim Radius", rim_radius, 0.001, 0.14, 0.001, _on_rim_radius_changed)
	_bottom_y_spin = _add_spin_row(main_vbox, "Bottom Y", bottom_y, -0.05, 0.2, 0.001, _on_bottom_y_changed)
	_rim_y_spin = _add_spin_row(main_vbox, "Rim Y", rim_y, -0.05, 0.24, 0.001, _on_rim_y_changed)
	_segments_spin = _add_spin_row(main_vbox, "Segments", float(radial_segments), float(MIN_SEGMENTS), float(MAX_SEGMENTS), 1.0, _on_segments_changed)
	_ball_radius_spin = _add_spin_row(main_vbox, "Ball Radius", ball_radius, 0.001, 0.08, 0.001, _on_ball_radius_changed)
	_rim_band_spin = _add_spin_row(main_vbox, "Rim Band Scale", rim_band_ball_radius_scale, 0.05, 2.0, 0.01, _on_rim_band_scale_changed)

	_intersection_label = Label.new()
	_intersection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_vbox.add_child(_intersection_label)

	_classification_label = Label.new()
	_classification_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_vbox.add_child(_classification_label)

	_normal_vector_label = Label.new()
	_normal_vector_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_vbox.add_child(_normal_vector_label)

	_ball_position_label = Label.new()
	_ball_position_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_vbox.add_child(_ball_position_label)

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
	if _normal_vector_check != null:
		_normal_vector_check.button_pressed = normal_vector_enabled
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
	if _ball_radius_spin != null:
		_ball_radius_spin.value = ball_radius
	if _rim_band_spin != null:
		_rim_band_spin.value = rim_band_ball_radius_scale
	if _summary_label != null:
		_summary_label.text = "r(y) %.3f to %.3f, height %.3f m" % [bottom_radius, rim_radius, _get_height()]
	if _intersection_label != null:
		_intersection_label.text = _format_intersection_status()
	if _classification_label != null:
		_classification_label.text = _format_classification_status()
	if _normal_vector_label != null:
		_normal_vector_label.text = _format_normal_vector_status()
	if _ball_position_label != null:
		_ball_position_label.text = _format_ball_position_status()
	_ui_updating = false


func _on_visibility_toggled(is_enabled: bool) -> void:
	if _ui_updating:
		return
	set_visualization_enabled(is_enabled)


func _on_normal_vector_visibility_toggled(is_enabled: bool) -> void:
	if _ui_updating:
		return
	normal_vector_enabled = is_enabled
	_update_normal_vector_visual()
	_refresh_ui()


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


func _on_ball_radius_changed(value: float) -> void:
	if _ui_updating:
		return
	ball_radius = maxf(value, EPSILON)
	_sync_ball_visual_radius()
	_update_ball_intersection()
	_refresh_ui()


func _on_rim_band_scale_changed(value: float) -> void:
	if _ui_updating:
		return
	rim_band_ball_radius_scale = maxf(value, 0.0)
	_update_ball_intersection()
	_refresh_ui()


func _on_reset_defaults_pressed() -> void:
	ball_radius = maxf(_default_ball_radius, EPSILON)
	rim_band_ball_radius_scale = maxf(_default_rim_band_ball_radius_scale, 0.0)
	_sync_ball_visual_radius()
	configure_frustum(
		_default_bottom_radius,
		_default_rim_radius,
		_default_bottom_y,
		_default_rim_y,
		_default_radial_segments
	)


func _ensure_positive_height() -> void:
	if rim_y <= bottom_y + EPSILON:
		rim_y = bottom_y + EPSILON


func _get_height() -> float:
	return maxf(rim_y - bottom_y, EPSILON)


func _get_collision_parameters() -> Dictionary:
	return ConicFrustumCollisionScript.build_parameters({
		"bottom_y": bottom_y,
		"rim_y": rim_y,
		"bottom_radius": bottom_radius,
		"rim_radius": rim_radius,
		"rim_band_ball_radius_scale": rim_band_ball_radius_scale,
	})


func _get_rim_band_width(radius: float) -> float:
	return ConicFrustumCollisionScript.get_rim_band_width(radius, _get_collision_parameters())


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	if event.pressed:
		if _is_screen_position_over_ui_panel(event.position):
			return

		var picked_axis := _pick_axis_at_screen_position(event.position)
		if picked_axis < 0:
			return

		_begin_axis_drag(picked_axis, event.position)
		get_viewport().set_input_as_handled()
	else:
		if _dragging_axis >= 0:
			_dragging_axis = -1
			get_viewport().set_input_as_handled()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _dragging_axis < 0 or _ball_model == null:
		return

	var current_parameter := _get_axis_parameter_from_screen_position(
		event.position,
		_dragging_axis,
		_drag_start_ball_position
	)
	var axis_direction := _get_world_axis_direction(_dragging_axis)
	_ball_model.global_position = _drag_start_ball_position + axis_direction * (current_parameter - _drag_start_axis_parameter)
	_update_ball_intersection()
	get_viewport().set_input_as_handled()


func _is_screen_position_over_ui_panel(screen_position: Vector2) -> bool:
	if _ui_panel == null or not is_instance_valid(_ui_panel) or not _ui_panel.visible:
		return false

	return _ui_panel.get_global_rect().has_point(screen_position)


func _begin_axis_drag(axis_index: int, screen_position: Vector2) -> void:
	if _ball_model == null:
		return

	_dragging_axis = axis_index
	_drag_start_ball_position = _ball_model.global_position
	_drag_start_axis_parameter = _get_axis_parameter_from_screen_position(
		screen_position,
		axis_index,
		_drag_start_ball_position
	)


func _pick_axis_at_screen_position(screen_position: Vector2) -> int:
	if not axis_gizmo_enabled or _testing_camera == null or _ball_model == null:
		return -1

	var ball_position := _ball_model.global_position
	if _testing_camera.is_position_behind(ball_position):
		return -1

	var center_screen := _testing_camera.unproject_position(ball_position)
	var best_axis := -1
	var best_distance := axis_gizmo_pick_radius_pixels
	for axis_index in [AXIS_X, AXIS_Y, AXIS_Z]:
		var endpoint := ball_position + _get_world_axis_direction(axis_index) * axis_gizmo_length
		if _testing_camera.is_position_behind(endpoint):
			continue

		var endpoint_screen := _testing_camera.unproject_position(endpoint)
		var distance := _get_point_to_segment_distance_2d(screen_position, center_screen, endpoint_screen)
		if distance <= best_distance:
			best_axis = axis_index
			best_distance = distance
	return best_axis


func _get_axis_parameter_from_screen_position(screen_position: Vector2, axis_index: int, axis_origin: Vector3) -> float:
	if _testing_camera == null:
		return 0.0

	var ray_origin := _testing_camera.project_ray_origin(screen_position)
	var ray_direction := _testing_camera.project_ray_normal(screen_position).normalized()
	var axis_direction := _get_world_axis_direction(axis_index)
	var origin_delta := axis_origin - ray_origin
	var axis_dot_ray := axis_direction.dot(ray_direction)
	var axis_dot_delta := axis_direction.dot(origin_delta)
	var ray_dot_delta := ray_direction.dot(origin_delta)
	var denominator := 1.0 - axis_dot_ray * axis_dot_ray
	if absf(denominator) <= EPSILON:
		return _drag_start_axis_parameter

	return (axis_dot_ray * ray_dot_delta - axis_dot_delta) / denominator


func _get_world_axis_direction(axis_index: int) -> Vector3:
	return (global_transform.basis * _get_local_axis_direction(axis_index)).normalized()


func _to_world_normal(local_normal: Vector3) -> Vector3:
	return (global_transform.basis * local_normal).normalized()


func _get_local_axis_direction(axis_index: int) -> Vector3:
	match axis_index:
		AXIS_X:
			return Vector3.RIGHT
		AXIS_Y:
			return Vector3.UP
		AXIS_Z:
			return Vector3.BACK
	return Vector3.ZERO


func _get_basis_with_local_y(direction: Vector3) -> Basis:
	var y_axis := direction.normalized()
	var helper := Vector3.RIGHT if absf(y_axis.dot(Vector3.UP)) > 0.96 else Vector3.UP
	var x_axis := helper.cross(y_axis).normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)


func _update_ball_intersection() -> void:
	if _ball_model == null:
		return

	_last_intersection_snapshot = calculate_ball_frustum_intersection(_ball_model.global_position, ball_radius)
	_last_normal_snapshot = calculate_local_nearest_surface_snapshot(global_transform.affine_inverse() * _ball_model.global_position)
	_last_ball_position = _ball_model.global_position
	_has_last_ball_position = true
	_apply_ball_status_color(str(_last_intersection_snapshot.get("classification", CLASS_OUTSIDE)))
	_update_normal_vector_visual()
	_refresh_ui()


func _apply_ball_status_color(classification: String) -> void:
	if _ball_material == null:
		return

	var status_color := ball_miss_color
	match classification:
		CLASS_TOP_RIM_BAND:
			status_color = ball_rim_band_color
		CLASS_TOP_INNER:
			status_color = ball_top_inner_color
		CLASS_OUTSIDE:
			status_color = ball_miss_color
		_:
			status_color = ball_intersect_color
	_ball_material.albedo_color = status_color
	_ball_material.emission = status_color


func _is_cross_section_point_inside_frustum(point: Vector2) -> bool:
	return ConicFrustumCollisionScript.is_cross_section_point_inside_frustum(point, _get_collision_parameters())


func _get_closest_cross_section_point(point: Vector2) -> Dictionary:
	return ConicFrustumCollisionScript.get_closest_cross_section_point(point, _get_collision_parameters())


func _get_fallback_normal_for_feature(feature: String, nearest_local_point: Vector3, radial_direction: Vector2) -> Vector3:
	return ConicFrustumCollisionScript.get_fallback_normal_for_feature(
		feature,
		nearest_local_point,
		radial_direction,
		_get_collision_parameters()
	)


func _update_normal_vector_visual() -> void:
	if _normal_vector_root == null:
		return

	if not normal_vector_enabled or _last_normal_snapshot.is_empty():
		_normal_vector_root.visible = false
		return

	if _ball_model == null:
		_normal_vector_root.visible = false
		return

	var start_local := global_transform.affine_inverse() * _ball_model.global_position
	var normal_local: Vector3 = _last_normal_snapshot.get("normal_local", Vector3.UP)
	var vector_length := maxf(axis_gizmo_length, normal_vector_cone_length + EPSILON)
	var direction := normal_local.normalized()
	if direction.length_squared() <= EPSILON:
		direction = Vector3.UP

	var cone_length := minf(normal_vector_cone_length, vector_length * 0.45)
	var shaft_length := maxf(vector_length - cone_length, EPSILON)
	_normal_vector_root.visible = true
	_normal_vector_root.transform = Transform3D(_get_basis_with_local_y(direction), start_local)

	if _normal_vector_shaft != null:
		_normal_vector_shaft.position = Vector3(0.0, shaft_length * 0.5, 0.0)
		_normal_vector_shaft.scale = Vector3(1.0, shaft_length, 1.0)
	if _normal_vector_tip != null:
		_normal_vector_tip.position = Vector3(0.0, shaft_length + cone_length * 0.5, 0.0)
		_normal_vector_tip.scale = Vector3(1.0, cone_length, 1.0)


func _get_closest_point_on_segment_2d(point: Vector2, segment_start: Vector2, segment_end: Vector2) -> Vector2:
	return ConicFrustumCollisionScript.get_closest_point_on_segment_2d(point, segment_start, segment_end)


func _get_point_to_segment_distance_2d(point: Vector2, segment_start: Vector2, segment_end: Vector2) -> float:
	return point.distance_to(_get_closest_point_on_segment_2d(point, segment_start, segment_end))


func _format_intersection_status() -> String:
	if _last_intersection_snapshot.is_empty():
		return "Intersection: unavailable"

	var intersects := bool(_last_intersection_snapshot.get("intersects", false))
	var distance := float(_last_intersection_snapshot.get("distance_to_frustum", 0.0))
	var clearance := float(_last_intersection_snapshot.get("clearance", 0.0))
	var feature := str(_last_intersection_snapshot.get("closest_feature", ""))
	return "Intersection: %s | nearest %s | distance %.3f m | clearance %.3f m" % [
		"yes" if intersects else "no",
		feature,
		distance,
		clearance,
	]


func _format_classification_status() -> String:
	if _last_intersection_snapshot.is_empty():
		return "Classification: unavailable"

	var classification := str(_last_intersection_snapshot.get("classification", CLASS_OUTSIDE))
	var rim_band_width := float(_last_intersection_snapshot.get("rim_band_width", 0.0))
	var rim_inner := float(_last_intersection_snapshot.get("rim_band_inner_radius", 0.0))
	var rim_outer := float(_last_intersection_snapshot.get("rim_band_outer_radius", 0.0))
	return "Classification: %s | rim band %.3f m (%.3f to %.3f)" % [
		classification,
		rim_band_width,
		rim_inner,
		rim_outer,
	]


func _format_normal_vector_status() -> String:
	if _last_normal_snapshot.is_empty():
		return "Normal: unavailable"

	var nearest: Vector3 = _last_normal_snapshot.get("nearest_local_point", Vector3.ZERO)
	var normal: Vector3 = _last_normal_snapshot.get("normal_local", Vector3.UP)
	var signed_distance := float(_last_normal_snapshot.get("signed_center_distance", 0.0))
	return "Normal: point (%.3f, %.3f, %.3f) dir (%.2f, %.2f, %.2f) signed %.3f m" % [
		nearest.x,
		nearest.y,
		nearest.z,
		normal.x,
		normal.y,
		normal.z,
		signed_distance,
	]


func _format_ball_position_status() -> String:
	if _ball_model == null:
		return "Ball: unavailable"

	var local_position := global_transform.affine_inverse() * _ball_model.global_position
	return "Ball local: (%.3f, %.3f, %.3f), radius %.3f m" % [
		local_position.x,
		local_position.y,
		local_position.z,
		ball_radius,
	]
