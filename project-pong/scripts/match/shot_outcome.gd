extends RefCounted
class_name ShotOutcome


static func for_attempt(did_score: bool, cup: Node3D, delay_seconds: float, winner_value: Variant = null) -> Dictionary:
	var outcome := {
		"was_score": did_score,
		"scored_cup": cup,
		"scored_cup_index": -1,
		"removed_cup_indices": [],
		"reset_delay": delay_seconds,
		"winner": winner_value,
	}

	if cup != null and is_instance_valid(cup):
		outcome["scored_cup_index"] = int(cup.get_meta("cup_index", -1))
		if int(outcome["scored_cup_index"]) >= 0:
			outcome["removed_cup_indices"].append(int(outcome["scored_cup_index"]))

	return outcome
