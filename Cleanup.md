# Cleanup Instructions

## Codex Task

Improve code style and reduce duplicate gameplay logic across these scripts:

- `res://scripts/classic_match_game.gd`
- `res://scripts/network_match_state.gd`
- `res://scripts/single_player_game.gd`


Read `AGENTS.md` and `HouseRules.md` before making implementation edits. This cleanup should preserve the existing Practice, Classic Match, and Online Arena behavior while moving shared scoring, rack, shot, and cup-removal mechanics into project-owned helper scripts.

Do not implement new House Rules during this cleanup. The goal is to create the shared gameplay layer that House Rules can use later.

## Review Summary

The three mode scripts currently re-implement the same beer-pong baseline in slightly different forms. That made sense while proving the prototype, but it is now a maintenance risk because future rules, cup metadata, scoring delays, reset timing, and authority decisions will need to be changed in multiple places.

The highest-value cleanup is to move repeated mechanics into shared scripts while leaving each mode script responsible for lifecycle and authority:

- Practice owns fast local shot practice.
- Classic Match owns local player/computer turns and match end.
- Online Arena owns network authority, snapshots, and replicated state.
- Shared helpers own rack construction, cup identity, score confirmation, miss detection, ball-settle checks, and cup removal presentation.

## Duplicate Logic Inventory

| Concern | Current duplication | Risk | Extract to |
| --- | --- | --- | --- |
| Triangular rack construction | `single_player_game.gd:_build_starting_rack()` around line 83, `classic_match_game.gd:_build_starting_racks()` and `_build_rack()` around lines 111 and 127, `network_match_state.gd:_build_starting_racks()` and `_build_rack()` around lines 496 and 522 | Cup naming, indices, owner metadata, and row placement can drift between modes. | `res://scripts/match/cup_rack_builder.gd` plus a small rack-state representation. |
| Cup parent clearing | `classic_match_game.gd:_clear_cup_parent()` around line 157 and `network_match_state.gd:_clear_cup_parent()` around line 514; Practice does the same inline | Different modes can forget cleanup or score-state reset details. | `CupRackBuilder.clear_cup_parent(parent)`. |
| Native score-contact confirmation | Practice, Classic Match, Computer Classic Match, and Online Arena each feed a target-rack-validated contact candidate to the shared tracker. | Match modes still own authoritative outcome resolution, while physical classification remains shared. | `res://scripts/match/shot_score_tracker.gd`. |
| Native score-contact lookup | Practice, Classic Match, and Online Arena ask their target `RackState` to validate the ball's latched contact candidate. | Each mode must still validate that the contacted cup belongs to the authoritative target rack. | Shared `RackState.find_score_contact_candidate(ball)` helper. |
| Ball settled check | `single_player_game.gd:_is_ball_settled()` around line 193, `classic_match_game.gd:_is_ball_settled()` around line 561, `network_match_state.gd:_is_ball_settled()` around line 427 | Physics thresholds can drift between modes. | `res://scripts/match/shot_physics.gd`. |
| Miss and out-of-bounds detection | `single_player_game.gd:_is_miss()` around line 134, Classic player/computer versions around lines 523 and 542, Network around line 392 | Bounds and timeout behavior differ without an explicit reason. | `res://scripts/match/shot_attempt_evaluator.gd` with configurable bounds. |
| Cup removal delay and visual removal | `single_player_game.gd:_update_pending_cup_removal()` around line 205, `classic_match_game.gd:_update_pending_cup_removals()` around line 404, `network_match_state.gd:_update_pending_cup_removals()` around line 577 | Practice only tracks one pending cup; Classic and Network track arrays with different payloads. | `res://scripts/match/cup_removal_queue.gd`. |
| Attempt reset bookkeeping | Practice `_reset_ball()` around line 149, Classic `_reset_ball_for_player()` and `_reset_ball_for_computer()` around lines 568 and 578, Network `_schedule_ball_reset()` and `_reset_ball_for_active_turn()` around lines 437 and 455 | Attempt state, score candidates, and ball availability can desync from turn flow. | Keep mode-owned turn flow, but extract a tiny `ShotAttemptState` or reuse `ShotScoreTracker.reset()`. |
| Cup availability and scored metadata | Classic `_get_available_cups()` around line 505 and Network scored-cup arrays around lines 547-575; Practice does not assign stable cup metadata | Future reracks and House Rules need stable cup identity across all modes. | `RackState` with stable zero-based `cup_index`, owner side/slot, and active/scored status. |

## Senior Engineer Notes

The main design problem is not just duplication; it is duplicated authority. Practice, Classic Match, and Online Arena each decide what a made shot means. Online Arena must remain the centralized multiplayer authority, but it should call the same standard shot resolver as local modes and then publish the result.

Avoid a large inheritance tree for game modes. These scripts have different responsibilities, especially around multiplayer snapshots and computer turns. Prefer small, focused helper scripts with pure functions or simple state objects.

Do not extract status-label text in the first cleanup. Labels are mode-specific presentation and are not the blocker for House Rules. Standardize naming around status labels, but keep the text close to the mode until gameplay state is unified.

Computer player logic in `classic_match_game.gd` is already separate enough to move later. Its target selection should eventually depend on shared rack state, and throw execution should move into a `ComputerShotPlanner` or `ComputerThrowSolver`, but the first cleanup should prioritize score/rack/reset logic shared by all three modes.

## Target Helper Scripts

Create a small shared gameplay folder when implementation begins:

- `res://scripts/match/pong_match_constants.gd`
  - Own `RACK_SIZE := 10`, row count, default angular settle multiplier, and stable side/slot constants if needed.
- `res://scripts/match/cup_rack_builder.gd`
  - Clear a cup parent.
  - Build a triangular rack from a config object or dictionary.
  - Assign stable metadata: `owner_slot` or `owner_side`, zero-based `cup_index`, and `is_scored := false`.
  - Return `Array[Node3D]` in stable cup-index order.
- `res://scripts/match/rack_state.gd`
  - Track active cups by stable index.
  - Provide `get_available_cups()`, `get_cup(index)`, `mark_scored(index)`, and `find_score_contact_candidate(ball)`.
  - Keep network serialization compact as arrays of scored cup indices.
- `res://scripts/match/shot_physics.gd`
  - Provide `is_ball_settled(ball, settled_speed, angular_multiplier := 8.0)`.
  - Provide shared ballistic helpers only if Classic computer throws are moved.
- `res://scripts/match/shot_score_tracker.gd`
  - Track the current native score-contact candidate.
  - Confirm the target-rack-validated contact immediately; ball settling is only a miss/timeout concern.
  - Return the confirmed cup or `null`; do not mutate mode state directly.
- `res://scripts/match/shot_attempt_evaluator.gd`
  - Evaluate miss conditions using ball position, attempt elapsed time, bounds, settle timing, and the absence of a validated score-contact candidate.
  - Accept explicit bounds so Practice, Classic, and Online Arena can preserve current tuned values.
- `res://scripts/match/cup_removal_queue.gd`
  - Queue scored cups or stable cup references for delayed `remove_from_game()`.
  - Support Network's slot/index lookup so peers can apply authoritative outcomes.

## Unification Plan

1. Baseline the current behavior.
   - Run `.\tools\validate_codex.cmd`.
   - Open the three mode scenes if practical and note any existing script warnings.
   - Do not change tuning values during the first extraction pass.

2. Add shared constants and rack construction.
   - Introduce `PongMatchConstants` and `CupRackBuilder`.
   - Refactor Practice first because it has the smallest lifecycle surface.
   - Refactor Classic Match second and preserve current player/computer rack positions.
   - Refactor Network Match State last and preserve snapshot payloads.

3. Standardize cup identity.
   - Use zero-based `cup_index` internally in every mode.
   - Use one-based numbering only for node names or UI text if desired.
   - Ensure every built cup has owner metadata and an explicit scored/active state.
   - Keep network snapshots serialized as scored cup indices.

4. Extract score confirmation and ball-settle checks.
   - Replace each `_try_confirm_score()` variant with a shared `ShotScoreTracker`.
   - Keep mode-specific `_resolve_attempt()` methods for now.
   - Confirm that score timing and reset timing remain unchanged.

5. Extract miss detection.
   - Add a bounds/config object or dictionary with `miss_height`, `out_of_bounds_x`, `z_min`/`z_max` or table-derived limits, `settled_after_seconds`, and `max_attempt_seconds`.
   - Use explicit mode configs so existing Practice, Classic, and Online Arena bounds do not silently change.
   - Remove Classic's duplicated `_is_player_miss()` and `_is_computer_miss()` logic once the helper accepts the target rack.

6. Extract cup removal queue.
   - Replace Practice's single pending cup with the shared queue.
   - Replace Classic's cup-reference queue with the shared queue.
   - Adapt Network through slot/index lookup so authoritative snapshots still drive removals.

7. Prepare for a shared shot outcome.
   - Add a lightweight result type or dictionary that can represent `was_score`, `scored_cup_index`, `removed_cup_indices`, `reset_delay`, and optional `winner`.
   - Keep House Rules disabled and baseline-only during this cleanup.
   - Once all modes consume the result, future House Rules can extend it without reopening every mode script.

8. Move computer target selection after rack state is shared.
   - Extract most-central target selection from `classic_match_game.gd`.
   - Add the future closest-cup heuristic through the same interface.
   - Keep throw velocity/accuracy tuning unchanged during extraction.

9. Validate after each mode migration.
   - Re-run `.\tools\validate_codex.cmd`.
   - Smoke-test Practice after its refactor.
   - Smoke-test Classic Match after its refactor.
   - Smoke-test Online Arena locally after NetworkMatchState changes.
   - Note that final confidence still requires Quest hardware verification.

## Naming and Convention Plan

Use consistent domain terms:

- Use `Practice` for user-facing mode text, but keep `single_player_game.gd` and `SinglePlayerGame` unless doing a deliberate scene-reference migration.
- Use `status_label_path`, `_status_label`, and `_update_status_label()` for mode status text. Migrate `score_label_path` only with scene updates.
- Use `slot` for network player slots (`PLAYER_ONE_SLOT`, `PLAYER_TWO_SLOT`).
- Use `side` for local logical sides when player/computer terminology is too narrow.
- Use zero-based `cup_index` internally everywhere.
- Use one-based display names, for example `Cup_01`, only for readability.
- Use `shots_taken_this_turn` plus `get_turn_shots_remaining()` for turn modes. Practice can omit turn counters.
- Prefer `rack_back_row_offset_from_table_end` over both `rack_end_margin` and ad hoc rack offsets in new shared code.
- Prefer table-derived z bounds where the mode already has `table_center_z` and `table_length_meters`; preserve existing explicit bounds until they are intentionally retuned.

Use consistent script structure:

1. `extends` and `class_name`
2. signals
3. preload constants
4. gameplay constants
5. exported scene references
6. exported tuning values
7. public state used by other scripts
8. private state
9. lifecycle methods
10. public accessors
11. signal handlers
12. mode flow
13. shared-helper adapters
14. UI/status updates

Use consistent state naming:

- `_attempt_active`
- `_attempt_elapsed`
- `_reset_countdown`
- `_score_tracker` or `_score_candidate` if the helper has not landed yet
- `_pending_cup_removals`
- `_rack_state_by_slot` or `_rack_cups_by_slot`, not both

Use consistent exported tuning names:

- `cup_spacing`
- `cup_height_y`
- `settled_speed`
- `settled_after_seconds`
- `max_attempt_seconds`
- `reset_delay`
- `scored_reset_delay`
- `cup_remove_delay`

When renaming exported variables, update the affected `.tscn` files in the same change and check for lost inspector values. Godot scene files serialize exported property names, so a code-only rename can silently reset tuning.

## Implementation Guardrails

- Keep Photon-facing calls inside `photon_session.gd`, `networked_arena.gd`, `networked_pong_ball.gd`, or `network_match_state.gd`.
- Shared gameplay helpers must not call Photon or assume multiplayer.
- Do not hard-code App IDs, user IDs, room names beyond existing config defaults, or Quest-local paths.
- Do not change physics tuning while extracting helpers.
- Do not change cup layouts unless the task explicitly asks for a gameplay change.
- Do not rely on every network peer independently resolving a shot. Network authority resolves once and peers apply the snapshot.
- Prefer typed GDScript variables and return values where practical.
- Keep comments focused on authority, serialization, or non-obvious gameplay behavior.
- Do not manually invent `.gd.uid` files; let Godot generate them or keep the project validation workflow in charge.

## Suggested First Refactor Commit

The first implementation commit should be intentionally boring:

1. Add `pong_match_constants.gd` and `cup_rack_builder.gd`.
2. Refactor only Practice rack construction to use the builder.
3. Preserve visual layout, cup count, score label behavior, scoring, miss detection, and reset timing.
4. Run validation.

That small pass proves the extraction style before touching Classic Match or network authority.
