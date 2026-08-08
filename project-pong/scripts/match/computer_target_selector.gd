extends RefCounted
class_name ComputerTargetSelector

const PongMatchConstants := preload("res://scripts/match/pong_match_constants.gd")

const TARGET_MOST_CENTRAL := "most_central"
const TARGET_CLOSEST := "closest"


static func select_target(rack_state, heuristic: String, origin: Vector3 = Vector3.ZERO) -> Node3D:
	if rack_state == null:
		return null

	var available_cups: Array[Node3D] = rack_state.get_available_cups()
	if available_cups.is_empty():
		return null

	match heuristic:
		TARGET_CLOSEST:
			return select_closest_cup(available_cups, origin)
		TARGET_MOST_CENTRAL:
			return select_most_central_cup(available_cups)
		_:
			return select_most_central_cup(available_cups)


static func select_most_central_cup(cups: Array[Node3D]) -> Node3D:
	if cups.is_empty():
		return null

	var rack_center := Vector3.ZERO
	for cup in cups:
		rack_center += cup.global_position
	rack_center /= float(cups.size())

	var selected_cup := cups[0]
	var selected_distance := INF
	var selected_index := PongMatchConstants.RACK_SIZE
	for cup in cups:
		var offset := cup.global_position - rack_center
		var distance := Vector2(offset.x, offset.z).length_squared()
		var cup_index := _get_cup_index(cup)
		if distance < selected_distance or (is_equal_approx(distance, selected_distance) and cup_index < selected_index):
			selected_cup = cup
			selected_distance = distance
			selected_index = cup_index

	return selected_cup


static func select_closest_cup(cups: Array[Node3D], origin: Vector3) -> Node3D:
	if cups.is_empty():
		return null

	var selected_cup := cups[0]
	var selected_distance := INF
	var selected_index := PongMatchConstants.RACK_SIZE
	for cup in cups:
		var offset := cup.global_position - origin
		var distance := Vector2(offset.x, offset.z).length_squared()
		var cup_index := _get_cup_index(cup)
		if distance < selected_distance or (is_equal_approx(distance, selected_distance) and cup_index < selected_index):
			selected_cup = cup
			selected_distance = distance
			selected_index = cup_index

	return selected_cup


static func _get_cup_index(cup: Node3D) -> int:
	return int(cup.get_meta("cup_index", PongMatchConstants.RACK_SIZE))
