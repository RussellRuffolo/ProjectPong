extends RefCounted
class_name HouseRulesSettingsStore

const RuleIds := preload("res://scripts/house_rules/house_rule_ids.gd")
const ProfileScript := preload("res://scripts/house_rules/house_rules_profile.gd")

const PROFILE_PATH := "user://house_rules_profile.cfg"
const PROFILE_SECTION := "profile"
const RULES_SECTION := "rules"


static func load_profile():
	var profile = ProfileScript.new()
	var config := ConfigFile.new()
	var error := config.load(PROFILE_PATH)
	if error == ERR_FILE_NOT_FOUND:
		return profile
	if error != OK:
		push_warning("[HouseRulesSettingsStore] Could not load %s. Error: %s" % [PROFILE_PATH, error])
		return profile

	for rule_id in RuleIds.all():
		var key := String(rule_id)
		if config.has_section_key(RULES_SECTION, key):
			profile.set_enabled(rule_id, bool(config.get_value(RULES_SECTION, key, true)))

	return profile


static func save_profile(profile) -> Error:
	var config := ConfigFile.new()
	config.set_value(PROFILE_SECTION, "version", ProfileScript.PROFILE_VERSION)
	config.set_value(PROFILE_SECTION, "compact_ruleset_id", profile.get_compact_ruleset_id())

	for rule_id in RuleIds.all():
		config.set_value(RULES_SECTION, String(rule_id), profile.is_enabled(rule_id))

	var error := config.save(PROFILE_PATH)
	if error != OK:
		push_warning("[HouseRulesSettingsStore] Could not save %s. Error: %s" % [PROFILE_PATH, error])
	return error


static func reset_to_defaults():
	var profile = ProfileScript.new()
	save_profile(profile)
	return profile


static func profile_path() -> String:
	return PROFILE_PATH
