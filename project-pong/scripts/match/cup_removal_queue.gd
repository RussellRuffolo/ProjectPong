extends RefCounted
class_name CupRemovalQueue


var _items: Array[Dictionary] = []


func clear() -> void:
	_items.clear()


func size() -> int:
	return _items.size()


func queue_scored_cup(cup: Node3D, delay_seconds: float, capture_ball: Node3D = null) -> void:
	if cup == null or not is_instance_valid(cup):
		return
	if _has_cup(cup):
		return

	_mark_cup_scored(cup)
	var item := {
		"cup": cup,
		"countdown": delay_seconds,
	}
	if capture_ball != null and is_instance_valid(capture_ball):
		item["capture_ball"] = capture_ball
	_items.append(item)


func queue_scored_cup_key(slot: int, cup_index: int, cup: Node3D, delay_seconds: float) -> void:
	if cup == null or not is_instance_valid(cup):
		return
	if _has_key(slot, cup_index):
		return

	_mark_cup_scored(cup)
	_items.append({
		"slot": slot,
		"cup_index": cup_index,
		"countdown": delay_seconds,
	})


func update(delta: float, resolver := Callable()) -> void:
	for index in range(_items.size() - 1, -1, -1):
		if not _is_capture_ready(_items[index]):
			continue
		_items[index]["countdown"] = float(_items[index]["countdown"]) - delta
		if float(_items[index]["countdown"]) > 0.0:
			continue

		var cup := _resolve_cup(_items[index], resolver)
		if cup != null and is_instance_valid(cup):
			if cup.has_method("remove_from_game"):
				cup.call("remove_from_game")
			else:
				cup.queue_free()
		_items.remove_at(index)


func _is_capture_ready(item: Dictionary) -> bool:
	var capture_ball = item.get("capture_ball", null)
	if capture_ball == null:
		return true
	if not is_instance_valid(capture_ball):
		item.erase("capture_ball")
		return true

	var cup := item.get("cup", null) as Node3D
	if cup == null or not is_instance_valid(cup):
		item.erase("capture_ball")
		return true
	if not capture_ball.has_method("is_score_capture_finished_for"):
		item.erase("capture_ball")
		return true
	if not bool(capture_ball.call("is_score_capture_finished_for", cup)):
		return false

	item.erase("capture_ball")
	return true


func _resolve_cup(item: Dictionary, resolver: Callable) -> Node3D:
	var direct_cup = item.get("cup", null)
	if direct_cup != null and is_instance_valid(direct_cup) and direct_cup is Node3D:
		return direct_cup

	if not resolver.is_valid():
		return null

	var resolved_cup = resolver.call(int(item.get("slot", 0)), int(item.get("cup_index", -1)))
	if resolved_cup != null and is_instance_valid(resolved_cup) and resolved_cup is Node3D:
		return resolved_cup
	return null


func _has_cup(cup: Node3D) -> bool:
	for item in _items:
		if item.get("cup", null) == cup:
			return true
	return false


func _has_key(slot: int, cup_index: int) -> bool:
	for item in _items:
		if int(item.get("slot", 0)) == slot and int(item.get("cup_index", -1)) == cup_index:
			return true
	return false


func _mark_cup_scored(cup: Node3D) -> void:
	cup.set_meta("is_scored", true)
	if cup.has_method("mark_scored"):
		cup.call("mark_scored")
