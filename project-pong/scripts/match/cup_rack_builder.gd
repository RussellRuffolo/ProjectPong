extends RefCounted
class_name CupRackBuilder

const CupTargetScript := preload("res://scripts/cup_target.gd")
const MatchConstants := preload("res://scripts/match/pong_match_constants.gd")


static func clear_cup_parent(parent: Node3D) -> void:
	if parent == null:
		return

	for child in parent.get_children():
		child.queue_free()


static func build_triangular_rack(parent: Node3D, config: Dictionary) -> Array[Node3D]:
	var rack: Array[Node3D] = []
	if parent == null:
		return rack

	var cup_visual_scene := config.get("cup_visual_scene", null) as PackedScene
	var cup_collision_scene := config.get("cup_collision_scene", null) as PackedScene
	var back_row_origin: Vector3 = config.get("back_row_origin", Vector3.ZERO)
	var row_direction_z := float(config.get("row_direction_z", 1.0))
	var cup_spacing := float(config.get("cup_spacing", 0.105))
	var name_prefix := str(config.get("name_prefix", "Cup"))
	var name_start_index := int(config.get("name_start_index", 1))
	var owner_slot := int(config.get("owner_slot", 0))
	var owner_side := StringName(str(config.get("owner_side", "")))
	var shared_collision_model_enabled := bool(config.get("shared_collision_model_enabled", false))

	var cup_index := 0
	for row in range(MatchConstants.RACK_ROWS):
		var cups_in_row := MatchConstants.RACK_ROWS - row
		var row_width := float(cups_in_row - 1) * cup_spacing
		var row_z := back_row_origin.z + row_direction_z * float(row) * cup_spacing * MatchConstants.RACK_ROW_DEPTH_FACTOR

		for column in range(cups_in_row):
			var cup := CupTargetScript.new() as Node3D
			cup.name = "%s_%02d" % [name_prefix, cup_index + name_start_index]
			cup.set("visual_scene", cup_visual_scene)
			cup.set("collision_scene", cup_collision_scene)
			cup.set("shared_collision_model_enabled", shared_collision_model_enabled)
			cup.position = Vector3(
				back_row_origin.x - row_width * 0.5 + float(column) * cup_spacing,
				back_row_origin.y,
				row_z
			)
			cup.set_meta("cup_index", cup_index)
			cup.set_meta("is_scored", false)
			cup.set_meta("owner_slot", owner_slot)
			if owner_side != &"":
				cup.set_meta("owner_side", owner_side)
			cup.set_meta("rack_row", row)
			cup.set_meta("rack_column", column)
			parent.add_child(cup)
			rack.append(cup)
			cup_index += 1

	return rack
