extends RefCounted
class_name HouseRuleIds

const BOUNCING := &"bouncing"
const CHAIN_LIGHTNING := &"chain_lightning"
const RING_OF_FIRE := &"ring_of_fire"
const RERACKS := &"reracks"
const GENTLEMANS := &"gentlemans"
const BALLS_BACK := &"balls_back"
const HEATING_UP_FIRE := &"heating_up_fire"
const ISLAND := &"island"


static func all() -> Array[StringName]:
	var rule_ids: Array[StringName] = [
		BOUNCING,
		CHAIN_LIGHTNING,
		RING_OF_FIRE,
		RERACKS,
		GENTLEMANS,
		BALLS_BACK,
		HEATING_UP_FIRE,
		ISLAND,
	]
	return rule_ids


static func is_valid(rule_id: StringName) -> bool:
	return all().has(rule_id)


static func display_name(rule_id: StringName) -> String:
	match rule_id:
		BOUNCING:
			return "Bouncing"
		CHAIN_LIGHTNING:
			return "Chain Lightning"
		RING_OF_FIRE:
			return "Ring of Fire"
		RERACKS:
			return "Reracks"
		GENTLEMANS:
			return "Gentleman's"
		BALLS_BACK:
			return "Balls Back"
		HEATING_UP_FIRE:
			return "Heating Up / Fire"
		ISLAND:
			return "Island"
		_:
			return "Unknown Rule"


static func scoring_summary(rule_id: StringName) -> String:
	match rule_id:
		BOUNCING:
			return "Made bounce shot removes one extra target cup."
		CHAIN_LIGHTNING:
			return "Made multi-cup contact removes touched target cups."
		RING_OF_FIRE:
			return "Center-gap make can end the match when the ring is live."
		RERACKS:
			return "Each side can spend one standard target-cup rearrange."
		GENTLEMANS:
			return "Two-cup line rearrange is available once per side."
		BALLS_BACK:
			return "Two made normal shots keep the same side up."
		HEATING_UP_FIRE:
			return "Acknowledged streaks can grant bonus shots."
		ISLAND:
			return "Called isolated-cup makes remove an extra cup."
		_:
			return ""


static func authority_summary(rule_id: StringName) -> String:
	match rule_id:
		BOUNCING, CHAIN_LIGHTNING, RING_OF_FIRE:
			return "Shot authority resolves once and publishes the result."
		RERACKS, GENTLEMANS, ISLAND:
			return "Pre-shot request is accepted by match authority."
		BALLS_BACK, HEATING_UP_FIRE:
			return "Turn authority tracks streaks and next-turn flow."
		_:
			return "Match authority resolves this rule."
