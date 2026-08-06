extends XRController3D

@export var hand_name := "Hand"
@export var grabbable_group := "grabbable"
@export_range(0.0, 1.0, 0.01) var grab_threshold := 0.55

@onready var grab_area: Area3D = $GrabArea

var _nearby_grabbables: Array[Node3D] = []
var _held_body: RigidBody3D
var _held_parent: Node
var _held_body_was_frozen := false


func _ready() -> void:
	grab_area.body_entered.connect(_on_grab_area_body_entered)
	grab_area.body_exited.connect(_on_grab_area_body_exited)
	print("[XR] %s grabber ready. Hold grip/grasp near a grabbable object to pick it up." % hand_name)


func _physics_process(_delta: float) -> void:
	if _grab_is_pressed():
		if _held_body == null:
			_try_grab_closest()
	elif _held_body != null:
		_release_held_body()


func _grab_is_pressed() -> bool:
	return (
		is_button_pressed(&"grip_click")
		or is_button_pressed(&"trigger_click")
		or get_float(&"grip") >= grab_threshold
		or get_float(&"trigger") >= grab_threshold
	)


func _try_grab_closest() -> void:
	var closest := _get_closest_grabbable()
	if closest == null:
		return

	_held_body = closest
	_held_parent = _held_body.get_parent()
	_held_body_was_frozen = _held_body.freeze
	_held_body.freeze = true
	_held_body.linear_velocity = Vector3.ZERO
	_held_body.angular_velocity = Vector3.ZERO
	_held_body.reparent(self, true)
	print("[XR] %s grabbed %s." % [hand_name, _held_body.name])


func _release_held_body() -> void:
	if _held_parent != null and is_instance_valid(_held_parent):
		_held_body.reparent(_held_parent, true)

	_held_body.freeze = _held_body_was_frozen
	print("[XR] %s released %s." % [hand_name, _held_body.name])
	_held_body = null
	_held_parent = null


func _get_closest_grabbable() -> RigidBody3D:
	var closest: RigidBody3D
	var closest_distance := INF

	for grabbable in _nearby_grabbables:
		if grabbable == null or not is_instance_valid(grabbable):
			continue

		var grabbable_body := grabbable as RigidBody3D
		if grabbable_body == null:
			continue

		var distance := global_position.distance_squared_to(grabbable_body.global_position)
		if distance < closest_distance:
			closest = grabbable_body
			closest_distance = distance

	return closest


func _on_grab_area_body_entered(body: Node3D) -> void:
	if body.is_in_group(grabbable_group) and not _nearby_grabbables.has(body):
		_nearby_grabbables.append(body)


func _on_grab_area_body_exited(body: Node3D) -> void:
	_nearby_grabbables.erase(body)
