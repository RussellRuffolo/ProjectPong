extends RefCounted
class_name ComputerTargetSelector

const PongMatchConstants := preload("res://scripts/match/pong_match_constants.gd")

const TARGET_MOST_CENTRAL := "most_central"
const TARGET_CLOSEST := "closest"
const TARGET_LEAST_CENTRAL := "least_central"
const TARGET_FRONT_CUP := "front_cup"
const TARGET_BACK_CUP := "back_cup"
const TARGET_HIGHEST_VALUE_HOUSE_RULE := "highest_value_house_rule_target"
const TARGET_WEIGHTED_RANDOM := "weighted_random"


static func select_target(rack_state, heuristic: String, origin: Vector3 = Vector3.ZERO, rng: RandomNumberGenerator = null) -> Node3D:
	if rack_state == null:
		return null

	var available_cups: Array[Node3D] = rack_state.get_available_cups()
	if available_cups.is_empty():
		return null

	match heuristic:
		TARGET_CLOSEST:
			return select_closest_cup(available_cups, origin)
		TARGET_LEAST_CENTRAL:
			return select_least_central_cup(available_cups)
		TARGET_FRONT_CUP:
			return select_closest_cup(available_cups, origin)
		TARGET_BACK_CUP:
			return select_farthest_cup(available_cups, origin)
		TARGET_HIGHEST_VALUE_HOUSE_RULE:
			return select_most_central_cup(available_cups)
		TARGET_WEIGHTED_RANDOM:
			return select_weighted_random_cup(available_cups, origin, rng)
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


static func select_least_central_cup(cups: Array[Node3D]) -> Node3D:
	if cups.is_empty():
		return null

	var rack_center := Vector3.ZERO
	for cup in cups:
		rack_center += cup.global_position
	rack_center /= float(cups.size())

	var selected_cup := cups[0]
	var selected_distance := -INF
	var selected_index := PongMatchConstants.RACK_SIZE
	for cup in cups:
		var offset := cup.global_position - rack_center
		var distance := Vector2(offset.x, offset.z).length_squared()
		var cup_index := _get_cup_index(cup)
		if distance > selected_distance or (is_equal_approx(distance, selected_distance) and cup_index < selected_index):
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


static func select_farthest_cup(cups: Array[Node3D], origin: Vector3) -> Node3D:
	if cups.is_empty():
		return null

	var selected_cup := cups[0]
	var selected_distance := -INF
	var selected_index := PongMatchConstants.RACK_SIZE
	for cup in cups:
		var offset := cup.global_position - origin
		var distance := Vector2(offset.x, offset.z).length_squared()
		var cup_index := _get_cup_index(cup)
		if distance > selected_distance or (is_equal_approx(distance, selected_distance) and cup_index < selected_index):
			selected_cup = cup
			selected_distance = distance
			selected_index = cup_index

	return selected_cup


static func select_weighted_random_cup(cups: Array[Node3D], origin: Vector3, rng: RandomNumberGenerator = null) -> Node3D:
	if cups.is_empty():
		return null
	if rng == null:
		return select_most_central_cup(cups)

	var weighted_cups: Array[Node3D] = cups.duplicate()
	weighted_cups.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return _get_cup_index(a) < _get_cup_index(b)
	)

	var total_weight := 0.0
	var weights: Array[float] = []
	for cup in weighted_cups:
		var offset := cup.global_position - origin
		var distance := maxf(0.05, Vector2(offset.x, offset.z).length())
		var weight := 1.0 / distance
		weights.append(weight)
		total_weight += weight

	var roll := rng.randf_range(0.0, total_weight)
	for index in range(weighted_cups.size()):
		roll -= weights[index]
		if roll <= 0.0:
			return weighted_cups[index]

	return weighted_cups.back()


static func _get_cup_index(cup: Node3D) -> int:
	return int(cup.get_meta("cup_index", PongMatchConstants.RACK_SIZE))
