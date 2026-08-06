extends Node3D

signal openxr_ready(openxr: XRInterface)
signal openxr_unavailable(reason: String)

@onready var xr_origin: XROrigin3D = %XROrigin3D
@onready var xr_camera: XRCamera3D = %XRCamera3D
@onready var left_controller: XRController3D = %LeftController
@onready var right_controller: XRController3D = %RightController

var _openxr: XRInterface


func _ready() -> void:
	print("[XR] Boot scene loaded.")
	_configure_xr_nodes()
	_start_openxr()


func _configure_xr_nodes() -> void:
	xr_camera.current = true
	left_controller.tracker = &"left_hand"
	right_controller.tracker = &"right_hand"
	print("[XR] XR origin, camera, and controller trackers configured.")


func _start_openxr() -> void:
	if _should_use_non_xr_fallback():
		var reason := "OpenXR startup skipped for local non-XR validation."
		print("[XR] %s" % reason)
		openxr_unavailable.emit(reason)
		_enable_editor_fallback()
		return

	_openxr = XRServer.find_interface("OpenXR")
	if _openxr == null:
		var reason := "OpenXR interface was not found. Running the scene in non-XR editor fallback mode."
		push_warning("[XR] %s" % reason)
		openxr_unavailable.emit(reason)
		_enable_editor_fallback()
		return

	print("[XR] OpenXR interface found. Initialized before boot: %s." % _openxr.is_initialized())
	if not _openxr.is_initialized():
		var initialized := _openxr.initialize()
		print("[XR] OpenXR initialize() returned: %s." % initialized)
		if not initialized:
			var reason := "OpenXR could not initialize. Check the active XR runtime, Android export preset, and Quest headset connection."
			push_warning("[XR] %s" % reason)
			openxr_unavailable.emit(reason)
			_enable_editor_fallback()
			return

	XRServer.primary_interface = _openxr
	get_viewport().use_xr = true
	Engine.max_fps = 0

	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	print("[XR] OpenXR session requested. Viewport XR is enabled: %s." % get_viewport().use_xr)
	print("[XR] Primary XR interface: %s." % XRServer.primary_interface.get_name())
	openxr_ready.emit(_openxr)


func _should_use_non_xr_fallback() -> bool:
	return DisplayServer.get_name() == "headless" or _cmdline_has_xr_mode_off()


func _cmdline_has_xr_mode_off() -> bool:
	var args := OS.get_cmdline_args()
	for index in range(args.size()):
		if args[index] == "--xr-mode" and index + 1 < args.size():
			return args[index + 1] == "off"
	return false


func _enable_editor_fallback() -> void:
	get_viewport().use_xr = false
	xr_origin.position = Vector3.ZERO
	xr_camera.position = Vector3(0.0, 1.6, 3.0)
	xr_camera.rotation_degrees = Vector3(-12.0, 0.0, 0.0)
	print("[XR] Non-XR fallback camera enabled so the scene can still be inspected in the editor.")
