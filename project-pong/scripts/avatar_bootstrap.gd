extends Node3D

const LOG_PREFIX := "[Avatar]"

@onready var xr_camera: XRCamera3D = %XRCamera3D
@onready var left_controller: XRController3D = %LeftController
@onready var right_controller: XRController3D = %RightController
@onready var platform_bootstrap: Node = %MetaPlatformBootstrap

var _avatar_manager: Object
var _avatar_initialized := false


func _ready() -> void:
	call_deferred("_start")


func _process(_delta: float) -> void:
	if not _avatar_initialized:
		return

	_update_avatar_tracking()


func _start() -> void:
	print("%s Bootstrap starting." % LOG_PREFIX)

	if not OS.has_feature("android"):
		print("%s Editor/non-Android run: leaving AvatarRoot empty." % LOG_PREFIX)
		return

	await _wait_for_openxr()

	if not _has_avatar_runtime_bridge():
		_report_missing_avatar_runtime()
		return

	if platform_bootstrap.has_signal("platform_ready"):
		var context: Dictionary = await platform_bootstrap.platform_ready
		await _initialize_avatar_runtime(context)
	else:
		push_warning("%s MetaPlatformBootstrap does not expose platform_ready; cannot initialize avatars." % LOG_PREFIX)


func _wait_for_openxr() -> void:
	if get_viewport().use_xr:
		return

	var main_scene := get_tree().current_scene
	if main_scene == null or not main_scene.has_signal("openxr_ready"):
		return

	print("%s Waiting for OpenXR session before avatar initialization." % LOG_PREFIX)
	await main_scene.openxr_ready


func _has_avatar_runtime_bridge() -> bool:
	if Engine.has_singleton("MetaAvatarManager"):
		_avatar_manager = Engine.get_singleton("MetaAvatarManager")
		return true

	return false


func _report_missing_avatar_runtime() -> void:
	var message := (
		"%s No official Meta Avatar runtime bridge is installed for Godot. "
		+ "Meta's public Avatars SDK docs remain Unity-focused, so this project cannot render "
		+ "the signed-in user's Meta Avatar until a redistributable Godot/native Android avatar "
		+ "bridge is added."
	) % LOG_PREFIX
	push_warning(message)


func _initialize_avatar_runtime(context: Dictionary) -> void:
	var user_id := String(context.get("user_id", ""))
	var access_token := String(context.get("access_token", ""))
	if user_id.is_empty() or access_token.is_empty():
		push_warning("%s Missing user ID or access token; cannot initialize avatar runtime." % LOG_PREFIX)
		return

	if not _avatar_manager.has_method("initialize"):
		push_warning("%s Installed avatar runtime does not expose initialize(access_token)." % LOG_PREFIX)
		return

	print("%s Initializing avatar runtime." % LOG_PREFIX)
	var init_result: Variant = _avatar_manager.call("initialize", access_token)
	if init_result is bool and not init_result:
		push_warning("%s Avatar runtime initialization returned false." % LOG_PREFIX)
		return

	if not _avatar_manager.has_method("load_logged_in_user"):
		push_warning("%s Installed avatar runtime does not expose load_logged_in_user(user_id)." % LOG_PREFIX)
		return

	print("%s Loading signed-in user's Meta Avatar." % LOG_PREFIX)
	var load_result: Variant = _avatar_manager.call("load_logged_in_user", user_id)
	if load_result is bool and not load_result:
		push_warning("%s Avatar load request returned false." % LOG_PREFIX)
		return

	_avatar_initialized = true
	print("%s Avatar runtime accepted the signed-in user load request." % LOG_PREFIX)


func _update_avatar_tracking() -> void:
	if _avatar_manager == null or not _avatar_manager.has_method("set_tracking"):
		return

	_avatar_manager.call(
		"set_tracking",
		xr_camera.global_transform,
		left_controller.global_transform,
		right_controller.global_transform
	)
