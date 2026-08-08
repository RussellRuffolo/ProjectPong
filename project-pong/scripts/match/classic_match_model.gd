extends RefCounted
class_name ClassicMatchModel

const MatchConstants := preload("res://scripts/match/pong_match_constants.gd")

const PHASE_WAITING := "waiting"
const PHASE_PLAYING := "playing"
const PHASE_COMPLETE := "complete"

var shots_per_turn := 2
var rack_size := MatchConstants.RACK_SIZE
var match_phase := PHASE_WAITING
var active_slot := 0
var winner_slot := 0
var shots_taken_this_turn := 0
var scores_by_slot: Array[int] = [0, 0]
var scored_cups_by_slot: Dictionary = {
	MatchConstants.PLAYER_ONE_SLOT: [],
	MatchConstants.PLAYER_TWO_SLOT: [],
}


func configure(config: Dictionary = {}) -> void:
	shots_per_turn = max(1, int(config.get("shots_per_turn", shots_per_turn)))
	rack_size = max(1, int(config.get("rack_size", rack_size)))


func reset_for_match(first_active_slot := MatchConstants.PLAYER_ONE_SLOT) -> void:
	match_phase = PHASE_PLAYING
	active_slot = first_active_slot if _is_valid_slot(first_active_slot) else MatchConstants.PLAYER_ONE_SLOT
	winner_slot = 0
	shots_taken_this_turn = 0
	scores_by_slot = [0, 0]
	scored_cups_by_slot = {
		MatchConstants.PLAYER_ONE_SLOT: [],
		MatchConstants.PLAYER_TWO_SLOT: [],
	}


func set_waiting() -> void:
	match_phase = PHASE_WAITING
	active_slot = 0
	winner_slot = 0
	shots_taken_this_turn = 0
	scores_by_slot = [0, 0]
	scored_cups_by_slot = {
		MatchConstants.PLAYER_ONE_SLOT: [],
		MatchConstants.PLAYER_TWO_SLOT: [],
	}


func load_state(phase: String, next_active_slot: int, next_winner_slot: int, shots_taken: int, score_values: Variant, scored_cups: Dictionary) -> void:
	match_phase = phase
	active_slot = next_active_slot if _is_valid_slot(next_active_slot) else 0
	winner_slot = next_winner_slot if _is_valid_slot(next_winner_slot) else 0
	shots_taken_this_turn = clampi(shots_taken, 0, shots_per_turn)
	scores_by_slot = _read_two_ints(score_values)
	scored_cups_by_slot = {
		MatchConstants.PLAYER_ONE_SLOT: _read_int_array(_get_slot_value(scored_cups, MatchConstants.PLAYER_ONE_SLOT)),
		MatchConstants.PLAYER_TWO_SLOT: _read_int_array(_get_slot_value(scored_cups, MatchConstants.PLAYER_TWO_SLOT)),
	}


func apply_shot_outcome(shooting_slot: int, target_slot: int, outcome: Dictionary) -> Dictionary:
	var previous_active_slot := active_slot
	var previous_shots_taken := shots_taken_this_turn
	var applied_active_slot := shooting_slot if _is_valid_slot(shooting_slot) else active_slot
	var applied_target_slot := target_slot if _is_valid_slot(target_slot) else get_opponent_slot(applied_active_slot)
	var new_removed_indices: Array[int] = []
	var turn_advanced := false

	if match_phase != PHASE_PLAYING or not _is_valid_slot(applied_active_slot) or not _is_valid_slot(applied_target_slot):
		return _build_transition(previous_active_slot, applied_target_slot, new_removed_indices, false, false, previous_shots_taken, turn_advanced, outcome)

	active_slot = applied_active_slot
	var scored_indices := get_scored_cup_indices(applied_target_slot)
	for cup_index in _read_int_array(outcome.get("removed_cup_indices", [])):
		if cup_index < 0 or cup_index >= rack_size:
			continue
		if scored_indices.has(cup_index) or new_removed_indices.has(cup_index):
			continue
		new_removed_indices.append(cup_index)

	if not new_removed_indices.is_empty():
		var target_scored := get_scored_cup_indices(applied_target_slot)
		for cup_index in new_removed_indices:
			target_scored.append(cup_index)
		target_scored.sort()
		scored_cups_by_slot[applied_target_slot] = target_scored
		_increment_score(applied_active_slot, new_removed_indices.size())

	var resolved_score := not new_removed_indices.is_empty()
	var explicit_winner_slot := _read_winner_slot(outcome.get("winner", 0))
	if explicit_winner_slot > 0:
		winner_slot = explicit_winner_slot
	elif get_remaining_count(applied_target_slot) <= 0:
		winner_slot = applied_active_slot

	var same_side_next_turn := bool(outcome.get("same_side_next_turn", false))
	if winner_slot > 0:
		match_phase = PHASE_COMPLETE
		active_slot = 0
		shots_taken_this_turn = 0
	else:
		shots_taken_this_turn = min(shots_taken_this_turn + 1, shots_per_turn)
		if shots_taken_this_turn >= shots_per_turn:
			turn_advanced = true
			shots_taken_this_turn = 0
			if not same_side_next_turn:
				active_slot = get_opponent_slot(applied_active_slot)

	return _build_transition(previous_active_slot, applied_target_slot, new_removed_indices, resolved_score, same_side_next_turn, previous_shots_taken, turn_advanced, outcome)


func get_opponent_slot(slot: int) -> int:
	if slot == MatchConstants.PLAYER_ONE_SLOT:
		return MatchConstants.PLAYER_TWO_SLOT
	if slot == MatchConstants.PLAYER_TWO_SLOT:
		return MatchConstants.PLAYER_ONE_SLOT
	return 0


func get_shots_remaining() -> int:
	if match_phase != PHASE_PLAYING:
		return 0
	return max(0, shots_per_turn - shots_taken_this_turn)


func get_score(slot: int) -> int:
	if not _is_valid_slot(slot):
		return 0
	return int(scores_by_slot[slot - 1])


func get_scores_by_slot() -> Array[int]:
	return scores_by_slot.duplicate()


func get_scored_cup_indices(slot: int) -> Array[int]:
	return _read_int_array(scored_cups_by_slot.get(slot, []))


func get_scored_cups_by_slot() -> Dictionary:
	return {
		MatchConstants.PLAYER_ONE_SLOT: get_scored_cup_indices(MatchConstants.PLAYER_ONE_SLOT),
		MatchConstants.PLAYER_TWO_SLOT: get_scored_cup_indices(MatchConstants.PLAYER_TWO_SLOT),
	}


func get_remaining_count(slot: int) -> int:
	if not _is_valid_slot(slot):
		return 0
	return max(0, rack_size - get_scored_cup_indices(slot).size())


func is_complete() -> bool:
	return match_phase == PHASE_COMPLETE


func to_dictionary() -> Dictionary:
	return {
		"phase": match_phase,
		"active_slot": active_slot,
		"winner_slot": winner_slot,
		"shots_taken_this_turn": shots_taken_this_turn,
		"shots_remaining": get_shots_remaining(),
		"scores_by_slot": get_scores_by_slot(),
		"scored_cups_slot_1": get_scored_cup_indices(MatchConstants.PLAYER_ONE_SLOT),
		"scored_cups_slot_2": get_scored_cup_indices(MatchConstants.PLAYER_TWO_SLOT),
		"remaining_slot_1": get_remaining_count(MatchConstants.PLAYER_ONE_SLOT),
		"remaining_slot_2": get_remaining_count(MatchConstants.PLAYER_TWO_SLOT),
	}


func _build_transition(previous_active_slot: int, target_slot: int, new_removed_indices: Array[int], resolved_score: bool, same_side_next_turn: bool, previous_shots_taken: int, turn_advanced: bool, outcome: Dictionary) -> Dictionary:
	return {
		"phase": match_phase,
		"previous_active_slot": previous_active_slot,
		"active_slot": active_slot,
		"target_slot": target_slot,
		"winner_slot": winner_slot,
		"previous_shots_taken_this_turn": previous_shots_taken,
		"shots_taken_this_turn": shots_taken_this_turn,
		"shots_remaining": get_shots_remaining(),
		"turn_advanced": turn_advanced,
		"same_side_next_turn": same_side_next_turn,
		"resolved_score": resolved_score,
		"new_removed_cup_indices": new_removed_indices.duplicate(),
		"scored_cups_by_slot": get_scored_cups_by_slot(),
		"scored_cups_slot_1": get_scored_cup_indices(MatchConstants.PLAYER_ONE_SLOT),
		"scored_cups_slot_2": get_scored_cup_indices(MatchConstants.PLAYER_TWO_SLOT),
		"scores_by_slot": get_scores_by_slot(),
		"outcome": _snapshot_outcome(outcome),
	}


func _increment_score(slot: int, amount: int) -> void:
	if not _is_valid_slot(slot) or amount <= 0:
		return
	scores_by_slot[slot - 1] = min(rack_size, int(scores_by_slot[slot - 1]) + amount)


func _snapshot_outcome(outcome: Dictionary) -> Dictionary:
	var snapshot := outcome.duplicate(true)
	snapshot.erase("scored_cup")
	return snapshot


func _read_winner_slot(value: Variant) -> int:
	var slot := int(value) if value is int or value is float else 0
	return slot if _is_valid_slot(slot) else 0


func _read_two_ints(values: Variant) -> Array[int]:
	var result: Array[int] = [0, 0]
	var input: Array = values if values is Array else []
	if input.size() > 0:
		result[0] = int(input[0])
	if input.size() > 1:
		result[1] = int(input[1])
	return result


func _read_int_array(values: Variant) -> Array[int]:
	var result: Array[int] = []
	var input: Array = values if values is Array else []
	for value in input:
		var cup_index := int(value)
		if not result.has(cup_index):
			result.append(cup_index)
	result.sort()
	return result


func _get_slot_value(values: Dictionary, slot: int) -> Variant:
	if values.has(slot):
		return values[slot]
	var string_key := str(slot)
	if values.has(string_key):
		return values[string_key]
	return []


func _is_valid_slot(slot: int) -> bool:
	return slot == MatchConstants.PLAYER_ONE_SLOT or slot == MatchConstants.PLAYER_TWO_SLOT
