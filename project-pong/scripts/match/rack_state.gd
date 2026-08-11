extends RefCounted
class_name RackState


var owner_slot := 0
var owner_side := &""

var _cups: Array = []
var _scored_indices: Array[int] = []


func configure(cups: Array[Node3D], slot := 0, side := &"") -> void:
	owner_slot = slot
	owner_side = side
	_cups = cups.duplicate()
	_scored_indices.clear()

	for cup in _cups:
		if not _is_live_cup(cup):
			continue

		var cup_index := _get_cup_index(cup)
		cup.set_meta("owner_slot", owner_slot)
		if owner_side != &"":
			cup.set_meta("owner_side", owner_side)
		if bool(cup.get_meta("is_scored", false)):
			_add_scored_index(cup_index)


func clear() -> void:
	_cups.clear()
	_scored_indices.clear()


func get_cups() -> Array[Node3D]:
	var live_cups: Array[Node3D] = []
	for cup in _cups:
		if _is_live_cup(cup):
			live_cups.append(cup)
	return live_cups


func get_available_cups() -> Array[Node3D]:
	var available_cups: Array[Node3D] = []
	for cup in _cups:
		if is_available_cup(cup):
			available_cups.append(cup)
	return available_cups


func get_cup(cup_index: int) -> Node3D:
	for cup in _cups:
		if not _is_live_cup(cup):
			continue
		if _get_cup_index(cup) == cup_index:
			return cup
	return null


func remaining_count() -> int:
	return get_available_cups().size()


func mark_scored(cup_index: int) -> Node3D:
	_add_scored_index(cup_index)
	var cup := get_cup(cup_index)
	if cup != null and is_instance_valid(cup):
		cup.set_meta("is_scored", true)
		if cup.has_method("mark_scored"):
			cup.call("mark_scored")
	return cup


func mark_cup_scored(cup) -> int:
	if not _is_live_cup(cup):
		return -1

	var cup_index := _get_cup_index(cup)
	if cup_index < 0:
		return -1

	mark_scored(cup_index)
	return cup_index


func is_scored(cup_index: int) -> bool:
	if _scored_indices.has(cup_index):
		return true

	var cup := get_cup(cup_index)
	if cup == null or not is_instance_valid(cup):
		return false
	return _cup_reports_scored(cup)


func set_scored_indices(indices: Array) -> void:
	_scored_indices.clear()
	for value in indices:
		_add_scored_index(int(value))


func get_scored_indices() -> Array[int]:
	return _scored_indices.duplicate()


func find_score_contact_candidate(ball: Node3D) -> Node3D:
	if ball == null or not is_instance_valid(ball):
		return null
	if not ball.has_method("get_score_contact_candidate"):
		return null

	var candidate := ball.call("get_score_contact_candidate") as Node3D
	if candidate == null or not is_instance_valid(candidate):
		return null
	if is_available_cup(candidate) and _cups.has(candidate):
		return candidate

	if ball.has_method("reject_score_contact_candidate"):
		ball.call("reject_score_contact_candidate", candidate)

	return null


func is_available_cup(cup) -> bool:
	if not _is_live_cup(cup):
		return false
	if bool(cup.get_meta("is_scored", false)):
		return false
	return not _cup_reports_scored(cup)


func _cup_reports_scored(cup) -> bool:
	return cup.has_method("is_scored") and bool(cup.call("is_scored"))


func _add_scored_index(cup_index: int) -> void:
	if cup_index < 0 or _scored_indices.has(cup_index):
		return

	_scored_indices.append(cup_index)
	_scored_indices.sort()


func _get_cup_index(cup) -> int:
	return int(cup.get_meta("cup_index", -1))


func _is_live_cup(cup) -> bool:
	return cup != null and is_instance_valid(cup) and cup is Node3D and not cup.is_queued_for_deletion()
