extends Node3D

const CupTargetScene := preload("res://scenes/gameplay/cup_target.tscn")
const ThrowableBallScript := preload("res://scripts/throwable_ball.gd")
const CupRemovalQueueScript := preload("res://scripts/match/cup_removal_queue.gd")

const TEST_TIMEOUT_SECONDS := 2.0

var _ball: RigidBody3D
var _cup: Node3D
var _elapsed := 0.0
var _score_detected := false
var _capture_finished_at := -1.0
var _removal_queue := CupRemovalQueueScript.new()


func _ready() -> void:
	if OS.has_feature("template"):
		push_warning("[NativeCupPhysicsTest] Editor-only test disabled in exported builds.")
		set_physics_process(false)
		return

	_cup = CupTargetScene.instantiate() as Node3D
	_cup.set_meta("cup_index", 0)
	_cup.set_meta("owner_slot", 2)
	add_child(_cup)

	_ball = ThrowableBallScript.new() as RigidBody3D
	_ball.name = "NativeContactTestBall"
	_ball.mass = 0.0027
	_ball.set("starts_suspended", false)
	_ball.set("can_be_grabbed", false)
	_ball.position = Vector3(0.0, 0.32, 0.0)
	_ball.rotation = Vector3(0.4, 0.7, 0.2)

	var shape_node := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.02
	shape_node.shape = sphere
	_ball.add_child(shape_node)
	add_child(_ball)

	_ball.connect("score_contact_detected", _on_score_contact_detected)
	_ball.connect("score_capture_finished", _on_score_capture_finished)
	_ball.linear_velocity = Vector3(0.0, -1.5, 0.0)
	print("[NativeCupPhysicsTest] Dropping centered ball onto the native cup collider.")


func _physics_process(delta: float) -> void:
	_elapsed += delta
	_removal_queue.update(delta)
	if _capture_finished_at >= 0.0 and not is_instance_valid(_cup):
		var removal_delay := _elapsed - _capture_finished_at
		if removal_delay < 0.09:
			push_error("[NativeCupPhysicsTest] Cup was removed before the post-capture delay elapsed.")
			get_tree().quit(1)
			return
		print("[NativeCupPhysicsTest] PASS: native contact, capture, and delayed removal completed.")
		get_tree().quit(0)
		return
	if _elapsed < TEST_TIMEOUT_SECONDS:
		return

	push_error("[NativeCupPhysicsTest] Timed out before native score capture completed (contact=%s)." % _score_detected)
	get_tree().quit(1)


func _on_score_contact_detected(ball: Node3D, cup: Node3D, snapshot: Dictionary) -> void:
	if ball != _ball or cup != _cup:
		return

	_score_detected = true
	print("[NativeCupPhysicsTest] Native score contact: edge_clearance=%.4f entry_speed=%.3f." % [
		float(snapshot.get("edge_clearance", 0.0)),
		float(snapshot.get("entry_speed", 0.0)),
	])
	if not _ball.call("begin_score_capture", _cup):
		push_error("[NativeCupPhysicsTest] Score contact was detected but capture could not start.")
		get_tree().quit(1)
		return
	_cup.call("mark_scored")
	_removal_queue.queue_scored_cup(_cup, 0.1, _ball)


func _on_score_capture_finished(ball: Node3D, cup: Node3D) -> void:
	if ball != _ball or cup != _cup:
		return

	_capture_finished_at = _elapsed
	print("[NativeCupPhysicsTest] Capture finished; starting the 0.1 second removal delay.")
