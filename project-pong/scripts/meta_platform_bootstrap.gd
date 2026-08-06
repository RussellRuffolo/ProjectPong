extends Node

signal platform_ready(context: Dictionary)
signal platform_failed(reason: String)
signal platform_skipped(reason: String)

const LOG_PREFIX := "[MetaPlatform]"
const APP_ID_SETTING := "meta/platform/app_id"

var _platform: Object
var _context: Dictionary = {}


func _ready() -> void:
	call_deferred("_start")


func get_context() -> Dictionary:
	return _context.duplicate()


func _start() -> void:
	print("%s Bootstrap starting." % LOG_PREFIX)

	if not OS.has_feature("android"):
		_skip("Meta Platform SDK bootstrap is Quest-only for this prototype.")
		return

	if not Engine.has_singleton("MetaPlatformSDK"):
		_fail("Godot Meta Toolkit is not installed or its MetaPlatformSDK singleton is unavailable.")
		return

	var app_id := String(ProjectSettings.get_setting(APP_ID_SETTING, ""))
	if app_id.is_empty():
		_fail("Project setting '%s' is empty. Set it to the Quest App ID from the Meta Developer Dashboard." % APP_ID_SETTING)
		return

	_platform = Engine.get_singleton("MetaPlatformSDK")
	await _initialize_platform(app_id)


func _initialize_platform(app_id: String) -> void:
	print("%s Initializing Platform SDK." % LOG_PREFIX)
	var result := await _call_platform_async("initialize_platform_async", [app_id])
	if _message_is_error(result):
		_fail("Platform initialization failed: %s" % _message_error(result))
		return

	print("%s Platform initialized." % LOG_PREFIX)
	await _check_entitlement()


func _check_entitlement() -> void:
	print("%s Checking viewer entitlement." % LOG_PREFIX)
	var result := await _call_platform_async("entitlement_get_is_viewer_entitled_async")
	if _message_is_error(result):
		_fail("Entitlement check failed: %s" % _message_error(result))
		return

	print("%s Entitlement check succeeded." % LOG_PREFIX)
	await _get_logged_in_user()


func _get_logged_in_user() -> void:
	print("%s Requesting logged-in user." % LOG_PREFIX)
	var result := await _call_platform_async("user_get_logged_in_user_async")
	if _message_is_error(result):
		_fail("Logged-in user request failed: %s" % _message_error(result))
		return

	var user_data: Variant = _message_data(result)
	var user_id := _extract_field(user_data, ["id", "user_id", "oculus_id"])
	if user_id.is_empty():
		_fail("Logged-in user response did not include a recognizable user ID.")
		return

	_context["user_id"] = user_id
	print("%s Logged-in user ID retrieved." % LOG_PREFIX)
	await _get_access_token()


func _get_access_token() -> void:
	print("%s Requesting avatar access token." % LOG_PREFIX)
	var result := await _call_platform_async("user_get_access_token_async")
	if _message_is_error(result):
		_fail("Access token request failed: %s" % _message_error(result))
		return

	var access_token := String(_message_data(result))
	if access_token.is_empty():
		_fail("Access token response was empty.")
		return

	_context["access_token"] = access_token
	print("%s Access token retrieved for avatar initialization." % LOG_PREFIX)
	platform_ready.emit(get_context())


func _call_platform_async(method_name: String, args: Array = []) -> Variant:
	if _platform == null:
		return {"error": "MetaPlatformSDK singleton is not available."}

	if not _platform.has_method(method_name):
		return {"error": "MetaPlatformSDK.%s is unavailable in the installed plugin." % method_name}

	var request: Variant = _platform.callv(method_name, args)
	if request == null:
		return {"error": "MetaPlatformSDK.%s returned null." % method_name}

	if not request is Object:
		return {"error": "MetaPlatformSDK.%s returned a non-object async request." % method_name}

	if not request.has_signal("completed"):
		return {"error": "MetaPlatformSDK.%s did not return an async request with a completed signal." % method_name}

	return await request.completed


func _message_is_error(message: Variant) -> bool:
	if message == null:
		return true

	if message is Dictionary:
		return message.has("error")

	if message is Object and message.has_method("is_error"):
		return bool(message.call("is_error"))

	return false


func _message_error(message: Variant) -> String:
	if message == null:
		return "No message returned."

	if message is Dictionary:
		return String(message.get("error", "Unknown error."))

	if message is Object:
		var error_value: Variant = null
		if message.has_method("get_error"):
			error_value = message.call("get_error")
		elif _object_has_property(message, "error"):
			error_value = message.get("error")
		return str(error_value)

	return str(message)


func _message_data(message: Variant) -> Variant:
	if message == null:
		return null

	if message is Dictionary:
		return message.get("data")

	if message is Object:
		if message.has_method("get_data"):
			return message.call("get_data")
		if _object_has_property(message, "data"):
			return message.get("data")

	return null


func _extract_field(value: Variant, candidate_names: Array[String]) -> String:
	if value == null:
		return ""

	if value is Dictionary:
		for candidate in candidate_names:
			if value.has(candidate):
				return String(value[candidate])
		return ""

	if value is Object:
		for candidate in candidate_names:
			if _object_has_property(value, candidate):
				return String(value.get(candidate))
			var getter := "get_%s" % candidate
			if value.has_method(getter):
				return String(value.call(getter))

	return ""


func _object_has_property(value: Object, property_name: String) -> bool:
	for property in value.get_property_list():
		if String(property.get("name", "")) == property_name:
			return true

	return false


func _skip(reason: String) -> void:
	print("%s %s" % [LOG_PREFIX, reason])
	platform_skipped.emit(reason)


func _fail(reason: String) -> void:
	push_warning("%s %s" % [LOG_PREFIX, reason])
	platform_failed.emit(reason)
