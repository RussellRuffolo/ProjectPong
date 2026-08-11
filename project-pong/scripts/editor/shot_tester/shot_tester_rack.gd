extends Node3D
class_name ShotTesterRack

signal cup_ball_entered_frustum(cup: Node3D, ball: RigidBody3D, collision_snapshot: Dictionary)

const MatchConstants := preload("res://scripts/match/pong_match_constants.gd")
const CupSensorScript := preload("res://scripts/editor/shot_tester/shot_tester_cup_sensor.gd")
const ConicFrustumCollisionScript := preload("res://scripts/match/conic_frustum_collision.gd")

var _cup_visual_scene: PackedScene
var _tracked_ball: RigidBody3D
var _cups: Array[Node3D] = []
var _active_cup_indices: Array[int] = []
var _owner_slot := 2
var _owner_side := &"target"
var _parameters := ConicFrustumCollisionScript.build_parameters({})


func configure(cup_visual_scene: PackedScene, tracked_ball: RigidBody3D, config := {}) -> void:
	_cup_visual_scene = cup_visual_scene
	_tracked_ball = tracked_ball
	_owner_slot = int(config.get("owner_slot", _owner_slot))
	_owner_side = StringName(str(config.get("owner_side", _owner_side)))
	_parameters = ConicFrustumCollisionScript.build_parameters(config.get("frustum_parameters", {}))
	_active_cup_indices = _sanitize_cup_indices(config.get("active_cup_indices", _default_active_indices()))
	_rebuild(config)


func rebuild_with_active_indices(active_cup_indices: Array[int]) -> void:
	_active_cup_indices = _sanitize_cup_indices(active_cup_indices)
	for cup in _cups:
		var is_active := _active_cup_indices.has(int(cup.get("cup_index")))
		cup.visible = is_active
		cup.call("set_sensor_enabled", is_active)
		if is_active and _tracked_ball != null:
			cup.call("track_ball", _tracked_ball)


func get_active_cup_indices() -> Array[int]:
	return _active_cup_indices.duplicate()


func get_cups() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for cup in _cups:
		if cup != null and is_instance_valid(cup):
			result.append(cup)
	return result


func get_available_cups() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for cup in _cups:
		if cup != null and is_instance_valid(cup) and _active_cup_indices.has(int(cup.get("cup_index"))):
			result.append(cup)
	return result


func get_cup(cup_index: int) -> Node3D:
	for cup in _cups:
		if cup != null and is_instance_valid(cup) and int(cup.get("cup_index")) == cup_index:
			return cup
	return null


func get_rack_center_position() -> Vector3:
	var available := get_available_cups()
	if available.is_empty():
		return global_position

	var center := Vector3.ZERO
	for cup in available:
		if cup.has_method("get_rim_center_position"):
			center += cup.call("get_rim_center_position")
		else:
			center += cup.global_position
	return center / float(available.size())


func clear_sensor_states() -> void:
	for cup in _cups:
		if cup != null and is_instance_valid(cup):
			cup.call("clear_tracking_state")
			if _tracked_ball != null:
				cup.call("track_ball", _tracked_ball)


func _rebuild(config: Dictionary) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_cups.clear()

	var back_row_origin: Vector3 = config.get("back_row_origin", Vector3.ZERO)
	var row_direction_z := float(config.get("row_direction_z", 1.0))
	var cup_spacing := float(config.get("cup_spacing", 0.105))
	var row_depth_factor := float(config.get("row_depth_factor", MatchConstants.RACK_ROW_DEPTH_FACTOR))
	var name_prefix := str(config.get("name_prefix", "ShotTesterCup"))

	var cup_index := 0
	for row in range(MatchConstants.RACK_ROWS):
		var cups_in_row := MatchConstants.RACK_ROWS - row
		var row_width := float(cups_in_row - 1) * cup_spacing
		var row_z := back_row_origin.z + row_direction_z * float(row) * cup_spacing * row_depth_factor

		for column in range(cups_in_row):
			var cup := CupSensorScript.new() as Node3D
			cup.name = "%s_%02d" % [name_prefix, cup_index]
			cup.position = Vector3(
				back_row_origin.x - row_width * 0.5 + float(column) * cup_spacing,
				back_row_origin.y,
				row_z
			)
			cup.call("configure", cup_index, _owner_slot, _owner_side, _parameters)
			cup.set_meta("rack_row", row)
			cup.set_meta("rack_column", column)
			cup.connect("ball_entered_frustum", Callable(self, "_on_cup_ball_entered_frustum"))
			add_child(cup)
			_add_cup_visual(cup)
			if _tracked_ball != null:
				cup.call("track_ball", _tracked_ball)
			_cups.append(cup)
			cup_index += 1

	rebuild_with_active_indices(_active_cup_indices)


func _add_cup_visual(cup: Node3D) -> void:
	if _cup_visual_scene == null:
		return

	var visual := _cup_visual_scene.instantiate() as Node3D
	if visual == null:
		return
	visual.name = "Visual"
	cup.add_child(visual)


func _on_cup_ball_entered_frustum(cup: Node3D, ball: RigidBody3D, collision_snapshot: Dictionary) -> void:
	if not _active_cup_indices.has(int(cup.get_meta("cup_index", -1))):
		return
	cup_ball_entered_frustum.emit(cup, ball, collision_snapshot)


func _default_active_indices() -> Array[int]:
	var result: Array[int] = []
	for cup_index in range(MatchConstants.RACK_SIZE):
		result.append(cup_index)
	return result


func _sanitize_cup_indices(values: Variant) -> Array[int]:
	var result: Array[int] = []
	var input: Array = values if values is Array else []
	for value in input:
		var cup_index := int(value)
		if cup_index < 0 or cup_index >= MatchConstants.RACK_SIZE or result.has(cup_index):
			continue
		result.append(cup_index)
	result.sort()
	return result
