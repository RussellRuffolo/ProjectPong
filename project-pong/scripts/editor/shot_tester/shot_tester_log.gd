extends RefCounted
class_name ShotTesterLog

var events: Array[Dictionary] = []


func add_event(event: Dictionary) -> void:
	events.append(event.duplicate(true))


func clear() -> void:
	events.clear()


func get_events() -> Array[Dictionary]:
	return events.duplicate(true)


func get_last_event() -> Dictionary:
	if events.is_empty():
		return {}
	return events[events.size() - 1].duplicate(true)


func build_export_text() -> String:
	var lines: Array[String] = [
		"Shot Tester Log",
		"Shots: %d" % events.size(),
		"",
	]
	for event in events:
		lines.append(format_event_summary(event))
		lines.append("  Raw: %s" % JSON.stringify(json_safe_variant(event)))
		lines.append("")
	return "\n".join(lines)


func export_to_path(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(build_export_text())
	file.close()
	return true


func format_event_summary(event: Dictionary) -> String:
	var result: Dictionary = event.get("result", {}) if event.get("result", {}) is Dictionary else {}
	var collision_count := int(result.get("collision_count", 0))
	var reason := str(event.get("resolve_reason", ""))
	var first_cup := -1
	var collisions: Array = event.get("collisions", []) if event.get("collisions", []) is Array else []
	if not collisions.is_empty() and collisions[0] is Dictionary:
		first_cup = int((collisions[0] as Dictionary).get("cup_index", -1))

	return "Shot %d: %d collision(s), first cup %d, reason %s" % [
		int(event.get("shot", 0)),
		collision_count,
		first_cup,
		reason,
	]


func json_safe_variant(value: Variant) -> Variant:
	if value is Vector3:
		var vector: Vector3 = value
		return {
			"x": vector.x,
			"y": vector.y,
			"z": vector.z,
		}
	if value is Transform3D:
		var transform: Transform3D = value
		return {
			"origin": json_safe_variant(transform.origin),
			"basis_x": json_safe_variant(transform.basis.x),
			"basis_y": json_safe_variant(transform.basis.y),
			"basis_z": json_safe_variant(transform.basis.z),
		}
	if value is StringName:
		return String(value)
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value.keys():
			result[str(key)] = json_safe_variant(value[key])
		return result
	if value is Array:
		var result_array: Array = []
		for item in value:
			result_array.append(json_safe_variant(item))
		return result_array
	return value
