extends RefCounted
class_name CupRemovalQueue


var _items: Array[Dictionary] = []


func clear() -> void:
	_items.clear()


func size() -> int:
	return _items.size()


func queue_scored_cup(cup: Node3D, delay_seconds: float) -> void:
	if cup == null or not is_instance_valid(cup):
		return
	if _has_cup(cup):
		return

	_mark_cup_scored(cup)
	_items.append({
		"cup": cup,
		"countdown": delay_seconds,
	})


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


func _resolve_cup(item: Dictionary, resolver: Callable) -> Node3D:
	var direct_cup := item.get("cup", null) as Node3D
	if direct_cup != null:
		return direct_cup

	if not resolver.is_valid():
		return null

	return resolver.call(int(item.get("slot", 0)), int(item.get("cup_index", -1))) as Node3D


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
