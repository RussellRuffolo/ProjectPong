extends RefCounted
class_name ShotContactTracker

const ContactSummaryScript := preload("res://scripts/house_rules/shot_contact_summary.gd")

const SURFACE_TABLE := &"table"
const SURFACE_FLOOR := &"floor"
const SURFACE_CUP_WALL := &"cup_wall"
const SURFACE_CUP_BOTTOM := &"cup_bottom_liquid"

var _ball: RigidBody3D
var _summary = ContactSummaryScript.new()
var _active := false
var _seen_contact_keys: Dictionary = {}


func start_attempt(ball: RigidBody3D) -> void:
	_ball = ball
	_summary = ContactSummaryScript.new()
	_seen_contact_keys.clear()
	_active = _ball != null and is_instance_valid(_ball)


func update(time_seconds: float) -> void:
	if not _active or _ball == null or not is_instance_valid(_ball):
		return
	if not _ball.has_method("get_colliding_bodies"):
		return

	for body in _ball.get_colliding_bodies():
		var body_3d := body as Node3D
		if body_3d != null and is_instance_valid(body_3d):
			_record_body_contact(body_3d, time_seconds)


func stop_and_get_summary(time_seconds: float):
	update(time_seconds)
	_active = false
	return ContactSummaryScript.from_dictionary(_summary.to_dictionary())


func clear() -> void:
	_ball = null
	_summary = ContactSummaryScript.new()
	_seen_contact_keys.clear()
	_active = false


func get_summary():
	return ContactSummaryScript.from_dictionary(_summary.to_dictionary())


func _record_body_contact(body: Node3D, time_seconds: float) -> void:
	var cup_node := _find_ancestor_with_meta(body, &"cup_index")
	if cup_node != null:
		var cup_index := int(cup_node.get_meta("cup_index", -1))
		var owner_slot := int(cup_node.get_meta("owner_slot", 0))
		var owner_side := StringName(str(cup_node.get_meta("owner_side", "")))
		var cup_key := "cup:%d:%s:%d" % [owner_slot, String(owner_side), cup_index]
		if _remember_contact(cup_key):
			_summary.record_cup(cup_index, owner_slot, owner_side, time_seconds, true)
		return

	var surface_id := _get_surface_id(body)
	if surface_id == SURFACE_TABLE:
		if _remember_contact("surface:table:%d" % body.get_instance_id()):
			_summary.record_table(surface_id, time_seconds)
		return

	if _is_hand_contact(body):
		var hand_key := "hand:%d" % body.get_instance_id()
		if _remember_contact(hand_key):
			_summary.record_hand(_get_owner_slot(body), _get_owner_side(body), time_seconds, true)
		return

	if _is_body_contact(body):
		var body_key := "body:%d" % body.get_instance_id()
		if _remember_contact(body_key):
			_summary.record_body(_get_owner_slot(body), _get_owner_side(body), time_seconds, true)
		return

	var non_playable_key := "non_playable:%s:%d" % [String(surface_id), body.get_instance_id()]
	if _remember_contact(non_playable_key):
		_summary.record_non_playable(surface_id, time_seconds)


func _remember_contact(contact_key: String) -> bool:
	if _seen_contact_keys.has(contact_key):
		return false

	_seen_contact_keys[contact_key] = true
	return true


func _find_ancestor_with_meta(node: Node, meta_key: StringName) -> Node:
	var current := node
	while current != null:
		if current.has_meta(meta_key):
			return current
		current = current.get_parent()
	return null


func _get_surface_id(node: Node) -> StringName:
	var current := node
	while current != null:
		var value: Variant = current.get("surface_id")
		if value != null:
			return StringName(str(value))
		current = current.get_parent()
	return &""


func _is_hand_contact(node: Node) -> bool:
	if node is XRController3D:
		return true
	if node.is_in_group("player_hand") or node.is_in_group("network_hand"):
		return true
	return node.name.to_lower().contains("hand")


func _is_body_contact(node: Node) -> bool:
	return node.is_in_group("player_body") or node.name.to_lower().contains("body")


func _get_owner_slot(node: Node) -> int:
	var owner_node := _find_ancestor_with_meta(node, &"owner_slot")
	return int(owner_node.get_meta("owner_slot", 0)) if owner_node != null else 0


func _get_owner_side(node: Node) -> StringName:
	var owner_node := _find_ancestor_with_meta(node, &"owner_side")
	return StringName(str(owner_node.get_meta("owner_side", ""))) if owner_node != null else &""
