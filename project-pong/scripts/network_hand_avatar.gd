extends Node3D
class_name NetworkHandAvatar

@export var source_controller_path: NodePath
@export var follow_source := false
@export var request_authority_on_ready := false
@export var authority_send_interval := 1
@export var hand_label := "Network Hand"
@export var hand_color := Color(0.95, 0.78, 0.24, 1.0)

@onready var _replicator: Node = get_node_or_null("FusionSharedReplicator")
@onready var _hand_marker: MeshInstance3D = $HandMarker
@onready var _aim_marker: MeshInstance3D = $AimMarker
@onready var _label: Label3D = $Label3D

var _source_controller: Node3D


func _ready() -> void:
	_source_controller = get_node_or_null(source_controller_path) as Node3D
	_apply_visuals()
	_connect_replicator_signals()

	if request_authority_on_ready:
		call_deferred("_request_authority")


func _physics_process(_delta: float) -> void:
	if follow_source and _source_controller != null:
		global_transform = _source_controller.global_transform


func configure_local(controller: Node3D, label_text: String, color: Color) -> void:
	_source_controller = controller
	source_controller_path = get_path_to(controller)
	follow_source = true
	request_authority_on_ready = true
	hand_label = label_text
	hand_color = color
	_apply_visuals()
	_request_authority()


func _connect_replicator_signals() -> void:
	if _replicator == null:
		push_warning("[NetworkHand] Missing FusionSharedReplicator child.")
		return

	_connect_replicator_signal(&"authority_changed", &"_on_authority_changed")
	_connect_replicator_signal(&"spawned", &"_on_spawned")


func _connect_replicator_signal(signal_name: StringName, method_name: StringName) -> void:
	if not _replicator.has_signal(signal_name):
		return

	var callback := Callable(self, method_name)
	if not _replicator.is_connected(signal_name, callback):
		_replicator.connect(signal_name, callback)


func _request_authority() -> void:
	if _replicator == null or not _replicator.has_method("want_authority"):
		return

	_replicator.call("want_authority", true, authority_send_interval)


func _apply_visuals() -> void:
	if _hand_marker == null or _aim_marker == null or _label == null:
		return

	var material := StandardMaterial3D.new()
	material.albedo_color = hand_color
	material.roughness = 0.55
	_hand_marker.material_override = material
	_aim_marker.material_override = material
	_label.text = hand_label


func _on_spawned() -> void:
	if request_authority_on_ready:
		_request_authority()


func _on_authority_changed(has_authority: bool) -> void:
	print("[NetworkHand] %s authority: %s" % [hand_label, has_authority])
