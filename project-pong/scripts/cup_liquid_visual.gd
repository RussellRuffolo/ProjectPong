extends Node3D
class_name CupLiquidVisual

const VolumeShader := preload("res://shaders/cup_liquid_volume.gdshader")
const SurfaceShader := preload("res://shaders/cup_liquid_surface.gdshader")

@export_range(0.0, 1.0, 0.01) var fill_ratio := 0.38
@export var liquid_radius := 0.036
@export var liquid_height := 0.085
@export var liquid_bottom_y := 0.006
@export_range(8, 32, 1) var radial_segments := 20
@export_range(0.0, 0.05, 0.001) var sloshing_strength := 0.012
@export_range(0.0, 30.0, 0.1) var sloshing_damping := 8.0
@export_range(0.0, 0.02, 0.001) var wave_strength := 0.003
@export_range(0.0, 8.0, 0.1) var wave_speed := 1.4
@export var liquid_color := Color(0.05, 0.44, 1.0, 0.58)
@export var surface_color := Color(0.25, 0.72, 1.0, 0.74)
@export var enabled_on_quest := true

var _volume_mesh_instance: MeshInstance3D
var _surface_mesh_instance: MeshInstance3D
var _volume_material: ShaderMaterial
var _surface_material: ShaderMaterial
var _previous_gravity_up_local := Vector3.UP
var _slosh_offset := Vector2.ZERO
var _wave_intensity := 0.0
var _time_offset := 0.0


func _ready() -> void:
	_time_offset = float(get_instance_id() % 1000) * 0.037
	_build_visuals()
	_previous_gravity_up_local = _get_gravity_up_local()
	_update_shader_parameters()
	set_process(true)


func configure_fill(value: float) -> void:
	fill_ratio = clampf(value, 0.0, 1.0)
	_update_shader_parameters()


func set_liquid_visible(is_visible: bool) -> void:
	visible = is_visible


func _process(delta: float) -> void:
	if _cup_is_scored():
		visible = false
		return

	var gravity_up_local := _get_gravity_up_local()
	var normal_delta := gravity_up_local - _previous_gravity_up_local
	_previous_gravity_up_local = gravity_up_local

	_update_slosh(normal_delta, delta)
	_update_wave(normal_delta, delta)
	_update_shader_parameters()


func _build_visuals() -> void:
	var volume_mesh := CylinderMesh.new()
	volume_mesh.top_radius = liquid_radius
	volume_mesh.bottom_radius = liquid_radius * 0.78
	volume_mesh.height = liquid_height
	volume_mesh.radial_segments = radial_segments
	volume_mesh.rings = 2
	volume_mesh.cap_top = true
	volume_mesh.cap_bottom = true

	_volume_material = ShaderMaterial.new()
	_volume_material.shader = VolumeShader

	_volume_mesh_instance = MeshInstance3D.new()
	_volume_mesh_instance.name = "LiquidVolume"
	_volume_mesh_instance.mesh = volume_mesh
	_volume_mesh_instance.material_override = _volume_material
	_volume_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_volume_mesh_instance.position.y = liquid_bottom_y + liquid_height * 0.5
	add_child(_volume_mesh_instance)

	_surface_material = ShaderMaterial.new()
	_surface_material.shader = SurfaceShader

	_surface_mesh_instance = MeshInstance3D.new()
	_surface_mesh_instance.name = "LiquidSurface"
	_surface_mesh_instance.mesh = _create_disk_mesh(radial_segments)
	_surface_mesh_instance.material_override = _surface_material
	_surface_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_surface_mesh_instance.position = _volume_mesh_instance.position
	add_child(_surface_mesh_instance)


func _create_disk_mesh(segments: int) -> ArrayMesh:
	var safe_segments := maxi(8, segments)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	vertices.append(Vector3.ZERO)
	normals.append(Vector3.UP)
	uvs.append(Vector2(0.5, 0.5))

	for index in range(safe_segments):
		var angle := TAU * float(index) / float(safe_segments)
		var x := cos(angle) * liquid_radius
		var z := sin(angle) * liquid_radius
		vertices.append(Vector3(x, 0.0, z))
		normals.append(Vector3.UP)
		uvs.append(Vector2(x / liquid_radius * 0.5 + 0.5, z / liquid_radius * 0.5 + 0.5))

	for index in range(safe_segments):
		indices.append(0)
		indices.append(index + 1)
		indices.append((index + 1) % safe_segments + 1)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _update_slosh(normal_delta: Vector3, delta: float) -> void:
	var target_slosh := Vector2(-normal_delta.x, -normal_delta.z) * sloshing_strength * 10.0
	if target_slosh.length() > sloshing_strength:
		target_slosh = target_slosh.normalized() * sloshing_strength

	var smoothing := clampf(delta * sloshing_damping, 0.0, 1.0)
	_slosh_offset = _slosh_offset.lerp(target_slosh, smoothing)


func _update_wave(normal_delta: Vector3, delta: float) -> void:
	var impulse := clampf(normal_delta.length() * 12.0, 0.0, 1.0)
	_wave_intensity = maxf(_wave_intensity, impulse)
	_wave_intensity = lerpf(_wave_intensity, 0.0, clampf(delta * 2.8, 0.0, 1.0))


func _update_shader_parameters() -> void:
	if _volume_material == null or _surface_material == null:
		return

	var gravity_up_local := _get_gravity_up_local()
	var plane_offset := -liquid_height * 0.5 + clampf(fill_ratio, 0.0, 1.0) * liquid_height
	var shared_params := {
		"liquid_normal_local": gravity_up_local,
		"liquid_plane_offset": plane_offset,
		"liquid_radius": liquid_radius,
		"slosh_offset": _slosh_offset,
		"wave_strength": wave_strength,
		"wave_speed": wave_speed,
		"wave_intensity": _wave_intensity,
		"time_offset": _time_offset,
	}

	for key in shared_params:
		_volume_material.set_shader_parameter(key, shared_params[key])
		_surface_material.set_shader_parameter(key, shared_params[key])

	_volume_material.set_shader_parameter("liquid_color", liquid_color)
	_surface_material.set_shader_parameter("surface_color", surface_color)


func _get_gravity_up_local() -> Vector3:
	var cup := get_parent() as Node3D
	if cup == null:
		return Vector3.UP

	var local_up := cup.global_transform.basis.inverse() * Vector3.UP
	if local_up.length_squared() <= 0.0001:
		return Vector3.UP
	return local_up.normalized()


func _cup_is_scored() -> bool:
	var cup := get_parent()
	if cup == null:
		return false
	if cup.has_method("is_scored"):
		return bool(cup.call("is_scored"))
	return bool(cup.get_meta("is_scored", false))
