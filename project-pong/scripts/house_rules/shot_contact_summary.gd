extends RefCounted
class_name ShotContactSummary

const TYPE_TABLE := &"table"
const TYPE_CUP := &"cup"
const TYPE_HAND := &"hand"
const TYPE_BODY := &"body"
const TYPE_NON_PLAYABLE := &"non_playable"
const SELF_PATH := "res://scripts/house_rules/shot_contact_summary.gd"

var contacts: Array[Dictionary] = []


func clear() -> void:
	contacts.clear()


func record_table(surface_id := &"", time_seconds := 0.0) -> void:
	record_contact(TYPE_TABLE, {
		"surface_id": String(surface_id),
		"time_seconds": time_seconds,
		"playable_bounce": true,
	})


func record_cup(cup_index: int, owner_slot := 0, owner_side := &"", time_seconds := 0.0, playable_bounce := true) -> void:
	record_contact(TYPE_CUP, {
		"cup_index": cup_index,
		"owner_slot": owner_slot,
		"owner_side": String(owner_side),
		"time_seconds": time_seconds,
		"playable_bounce": playable_bounce,
	})


func record_hand(owner_slot := 0, owner_side := &"", time_seconds := 0.0, playable_bounce := true) -> void:
	record_contact(TYPE_HAND, {
		"owner_slot": owner_slot,
		"owner_side": String(owner_side),
		"time_seconds": time_seconds,
		"playable_bounce": playable_bounce,
	})


func record_body(owner_slot := 0, owner_side := &"", time_seconds := 0.0, playable_bounce := true) -> void:
	record_contact(TYPE_BODY, {
		"owner_slot": owner_slot,
		"owner_side": String(owner_side),
		"time_seconds": time_seconds,
		"playable_bounce": playable_bounce,
	})


func record_non_playable(surface_id := &"", time_seconds := 0.0) -> void:
	record_contact(TYPE_NON_PLAYABLE, {
		"surface_id": String(surface_id),
		"time_seconds": time_seconds,
		"playable_bounce": false,
	})


func record_contact(contact_type: StringName, details := {}) -> void:
	var event: Dictionary = details.duplicate()
	event["type"] = String(contact_type)
	if not event.has("time_seconds"):
		event["time_seconds"] = 0.0
	if not event.has("playable_bounce"):
		event["playable_bounce"] = contact_type != TYPE_NON_PLAYABLE
	contacts.append(event)


func has_playable_bounce_excluding_scored(scored_cup_index: int, target_owner_slot := 0, target_owner_side := &"") -> bool:
	for event in contacts:
		if not bool(event.get("playable_bounce", false)):
			continue

		var event_type := StringName(str(event.get("type", "")))
		if event_type == TYPE_CUP:
			if int(event.get("cup_index", -1)) == scored_cup_index:
				continue
			if not _matches_owner(event, target_owner_slot, target_owner_side):
				continue
		return true

	return false


func get_distinct_touched_target_cup_indices(target_owner_slot := 0, target_owner_side := &"", scored_cup_index := -1) -> Array[int]:
	var indices: Array[int] = []
	for event in contacts:
		if StringName(str(event.get("type", ""))) != TYPE_CUP:
			continue
		if not _matches_owner(event, target_owner_slot, target_owner_side):
			continue

		var cup_index := int(event.get("cup_index", -1))
		if cup_index < 0 or cup_index == scored_cup_index or indices.has(cup_index):
			continue
		indices.append(cup_index)

	indices.sort()
	return indices


func to_dictionary() -> Dictionary:
	return {
		"contacts": contacts.duplicate(true),
	}


static func from_dictionary(data: Dictionary):
	var summary = load(SELF_PATH).new()
	var input: Array = data.get("contacts", []) if data.get("contacts", []) is Array else []
	for value in input:
		if value is Dictionary:
			summary.contacts.append(value.duplicate(true))
	return summary


func _matches_owner(event: Dictionary, target_owner_slot: int, target_owner_side: StringName) -> bool:
	if target_owner_slot > 0 and int(event.get("owner_slot", 0)) != target_owner_slot:
		return false
	if target_owner_side != &"" and StringName(str(event.get("owner_side", ""))) != target_owner_side:
		return false
	return true
