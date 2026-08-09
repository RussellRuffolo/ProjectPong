extends Resource
class_name ComputerPlayerProfile

const DEFAULT_PROFILE_PATH := "res://resources/computer_players/steady_classic.tres"

@export var profile_id := &"steady_classic"
@export var display_name := "Steady Classic"
@export_enum("most_central", "closest", "least_central", "front_cup", "back_cup", "weighted_random") var target_heuristic := "most_central"
@export_range(8.0, 80.0, 0.5) var direct_release_angle_degrees := 42.0
@export_range(0.0, 0.35, 0.005) var direct_aim_error_radius := 0.025
@export_range(0.0, 10.0, 0.1) var direct_angle_error_degrees := 1.5
@export_range(0.0, 1.0, 0.01) var bounce_propensity := 0.05
@export_range(8.0, 80.0, 0.5) var bounce_release_angle_degrees := 28.0
@export_range(0.0, 0.35, 0.005) var bounce_aim_error_radius := 0.035
@export_range(0.0, 12.0, 0.1) var bounce_angle_error_degrees := 2.0
@export_range(0.0, 0.5, 0.005) var bounce_target_height := 0.06
@export var bounce_surface_id := &"table"
@export_multiline var notes := ""


static func default_profile():
	var loaded_profile = load(DEFAULT_PROFILE_PATH)
	if loaded_profile != null:
		return loaded_profile
	return load("res://scripts/match/computer_player_profile.gd").new()


func duplicate_profile():
	return duplicate(true)


func get_profile_id_string() -> String:
	return String(profile_id)
