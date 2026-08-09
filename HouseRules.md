# House Rules Implementation Guide

## Purpose

House Rules are optional gameplay modifiers that extend the baseline rule: a made shot removes the cup the ball comes to rest in. They must work across Practice, Classic Match, and Online Arena by building on the shared match helpers now used by all three modes.

The first implementation pass added the local data model, saved settings profile, in-menu UI, and rule-ready shot outcome fields. The architecture pass is now in place: Practice, Classic Match, and Online Arena route shot resolution through a shared resolver, track per-shot contacts, and apply multi-cup outcomes from a single `ShotOutcome` dictionary.

## Current Implementation Snapshot

Implemented House Rules foundation:

- `res://scripts/house_rules/house_rule_ids.gd`
  Defines stable `StringName` ids, display names, short scoring summaries, and authority summaries for the initial rules:
  `bouncing`, `chain_lightning`, `ring_of_fire`, `reracks`, `gentlemans`, `balls_back`, `heating_up_fire`, and `island`.
- `res://scripts/house_rules/house_rules_profile.gd`
  Stores enabled/disabled rule state. Fresh profiles default every initial rule to enabled and expose a compact ruleset id such as `hr1-11111111`.
- `res://scripts/house_rules/house_rules_settings_store.gd`
  Loads and saves the local profile at `user://house_rules_profile.cfg` using `ConfigFile`.
- `res://scripts/house_rules/shot_context.gd`
  Provides a rule-ready context object with mode id, active side/player, opponent side/player, slot ids, target rack state, declaration fields, turn fields, rules profile, and contact summary.
- `res://scripts/house_rules/shot_contact_summary.gd`
  Provides a serializable contact summary model for table, cup, hand, body, and non-playable contacts. It has helpers for playable-bounce checks and distinct touched target cup indices.
- `res://scripts/house_rules/shot_contact_tracker.gd`
  Records distinct contacts from the active ball during a released shot and classifies cup, table, hand, body, and non-playable contacts into a `ShotContactSummary`.
- `res://scripts/house_rules/house_rules_resolver.gd`
  Resolves baseline outcomes through the shared `ShotOutcome` helper and applies deterministic Bouncing and Chain Lightning cup-removal rules when enabled.
- `res://scripts/house_rules/house_rule_toggle.gd`
  Provides 3D toggle rows for the VR menu panel.
- `res://scripts/house_rules/house_rules_menu_panel.gd`
  Builds the in-world House Rules panel, loads the saved profile, saves toggle changes, supports Defaults, and closes via Done.

Implemented integration points:

- `res://scenes/menu.tscn`
  The old disabled House Rules button now opens the in-world rules panel.
- `res://scripts/gamemode_menu.gd`
  Now discovers menu controls recursively, supports command buttons, ignores hidden/disabled controls during raycasts, and opens the House Rules panel.
- `res://scripts/vr_menu_button.gd`
  Now supports `command_id` and disables its collision shape when not selectable.
- `res://scripts/match/shot_outcome.gd`
  Still returns the baseline dictionary used by existing callers, but now also supports `ignored_cup_indices`, `bonus_shots`, `extra_turns`, `same_side_next_turn`, `ui_messages`, `rule_triggers`, and `ruleset_id`.
- `res://scripts/single_player_game.gd`
  Loads the saved House Rules profile on entry, records contacts for each released practice shot, resolves attempts through `HouseRulesResolver`, and applies every cup index in `removed_cup_indices`.
- `res://scripts/classic_match_game.gd`
  Loads the saved House Rules profile on entry, records contacts for player and computer shots, resolves both sides through `HouseRulesResolver`, and applies multi-cup outcomes to the correct target rack.
- `res://scripts/network_match_state.gd`
  Loads the local profile on entry, seeds authoritative room snapshots with that profile, applies replicated room profiles on peers, records authoritative shot contacts, resolves attempts through `HouseRulesResolver`, publishes scored cup arrays, and serializes the last shot outcome without node references.

Not implemented yet:

- Actual behavior for Ring of Fire, Reracks, Gentleman's, Balls Back, Heating Up / Fire, or Island.
- Pre-shot declaration UI/resources for Island, Reracks, Gentleman's, or Heating Up acknowledgement.
- Ring of Fire center-gap score detection.
- Rerack shape data or cup-moving logic.
- Focused tests/validation scenes for individual rule behavior.
- Photon room-property publication for the compact ruleset id before gameplay starts.

## Existing Shared Match Baseline

- Practice mode is driven by `res://scripts/single_player_game.gd`. It owns local lifecycle, score display, ball reset, and fast single-rack practice flow while using shared helpers for rack creation, rack state, scoring confirmation, miss detection, ball-settle checks, cup removal, and baseline shot outcomes.
- Classic Match is driven by `res://scripts/classic_match_game.gd`. It owns turns, two shots per turn, player/computer racks, computer throw execution, match end, and menu return while using shared helpers for rack construction/state, score confirmation, miss detection, delayed cup removal, and baseline shot outcomes.
- Online Arena uses `res://scripts/network_match_state.gd` as the centralized networked match authority. It uses shared helpers for rack construction/state, score confirmation, miss detection, ball-settle checks, delayed cup removal, and baseline shot outcomes while publishing compact authoritative snapshots.
- `res://scripts/cup_target.gd` owns per-cup score detection through `is_ball_resting_inside()`, exposes `cup_index` metadata in match modes, and marks/removes cups.
- `res://scripts/pong_physics_surface.gd` carries a `surface_id`, which should be used as the starting point for bounce/contact classification.
- `res://scripts/match/pong_match_constants.gd` defines shared rack constants, settle tuning defaults, local side names, and network player slot constants.
- `res://scripts/match/cup_rack_builder.gd` builds the standard triangular 10-cup rack, clears rack parents, names cups, and assigns stable `cup_index`, owner, row, and column metadata.
- `res://scripts/match/rack_state.gd` tracks cups by stable index, available/scored state, remaining count, and resting-cup lookup.
- `res://scripts/match/shot_physics.gd` owns the shared settled-ball check.
- `res://scripts/match/shot_score_tracker.gd` owns score-candidate confirmation after the configured settle delay.
- `res://scripts/match/shot_attempt_evaluator.gd` owns shared miss/out-of-bounds/timeout detection through explicit per-mode bounds.
- `res://scripts/match/cup_removal_queue.gd` owns delayed visual removal for local cup references and network slot/index lookups.
- `res://scripts/match/computer_target_selector.gd` provides swappable computer target selection using `most_central` and `closest` heuristics. Classic Match exposes this via `computer_target_heuristic`; computer throw execution and accuracy offset remain in `classic_match_game.gd`.
- `res://scripts/match/classic_match_model.gd` owns shared classic-match logical state: active slot, shots taken, scores, scored cup indices, turn advancement, and winner detection. Classic Match, Online Arena, and the editor-only computer-vs-computer simulation use it so shot outcomes mutate match state consistently.
- `res://scenes/editor/computer_classic_match.tscn` is an editor-only CPU-vs-CPU classic match simulation. It builds real cup racks, launches visible `ThrowableBall` rigid bodies through the same shared computer throw helper used by Classic Match, resolves physics-confirmed scores/misses through `HouseRulesResolver`, exposes custom House Rules profile controls, and provides `run_automatic_test()`, `step_simulation()`, and `get_test_snapshot()` for Codex validation.

## Design Goals

- One shared rules pipeline should evaluate every rule-aware shot outcome for Practice, Classic Match, and Online Arena.
- Game modes should provide context and apply the returned result; they should not each implement Bouncing, Chain Lightning, Island, or future rules.
- Rules should be composable. Any subset of rules can be enabled.
- Rules should be deterministic enough for multiplayer. The active authority resolves the shot once, then replicates the compact result.
- Rules should separate gameplay state from presentation. VFX, labels, and sounds should react to a resolved outcome but never decide scoring.
- Rules should be data-oriented where practical: enabled flags, per-side resources, per-player streaks, touched cups, scoring cup, bonus shots, winner, and rerack state should serialize cleanly.

## Target Runtime Flow

Mode scripts should move toward this shape:

1. Mode owns lifecycle: start match, start turn, release shot, advance/reset, update labels.
2. Mode asks existing shared helpers for rack creation/state and score detection.
3. Mode builds a `ShotContext` with active side/player, target rack, current turn state, selected declaration, enabled rules, and contact summary.
4. Mode sends the context and baseline made/miss information to `HouseRulesResolver`.
5. Mode applies the returned `ShotOutcome` through existing rack-state and cup-removal paths.
6. Online Arena serializes only the authoritative outcome and resulting state changes, not every cosmetic effect.

The next pass should avoid moving authority back into individual mode scripts. If a rule needs extra state, add that state to the shared context/outcome/match-state path first.

## Menu and Persistence State

Current behavior:

- The House Rules option in `res://scenes/menu.tscn` is selectable and opens an in-world panel.
- The panel lists each rule name with an ON/OFF toggle.
- Fresh profiles default all listed House Rules to enabled.
- Toggle changes and Defaults save through `user://house_rules_profile.cfg`.
- Practice, Classic Match, and Online Arena load the saved profile on entry.
- Online Arena match snapshots carry an authoritative `house_rules_profile` dictionary once snapshots are published.

Remaining work:

- Future Photon room creation should expose a compact ruleset identifier/hash in room properties before gameplay starts.
- The lobby/room browser UI should display the room ruleset once Photon room properties are available.

## Next Pass Scope

The next pass should continue implementing rule behavior in small, reversible steps. The resolver/routing/contact-tracking path already exists.

Recommended order:

1. Add focused validation coverage for Bouncing and Chain Lightning using synthetic `ShotContext` and `ShotContactSummary` inputs.
2. Add a small in-scene or headless validation path for rule-driven multi-cup removal in Practice and Classic Match.
3. Add turn/resource state for Balls Back, Heating Up / Fire, Reracks, Gentleman's, and Island.
4. Add pre-shot UI affordances for Reracks, Gentleman's, Heating Up acknowledgement, and Island calls.
5. Add data-driven rerack shape definitions and cup-moving logic that preserves stable cup indices.
6. Add Photon room-property publication for the compact ruleset id.
7. Add Ring of Fire after rack role metadata and center-gap detection are reliable.

## Shot Contact Model

Several rules depend on what the ball touched before scoring. The data model exists in `ShotContactSummary`, and released shots now use `ShotContactTracker` to capture distinct contacts from the ball's reported collisions.

Track these event types per released shot:

- `table`: playable table surface.
- `cup`: any active cup, including cup index and owning side or slot.
- `hand`: opponent hand/controller avatar.
- `body`: opponent body/avatar hit zone when body avatars exist.
- `non_playable`: floor, walls, local player's own body/hand, or other surfaces that do not count for bounce rewards.

Playable bounce surfaces for the initial rules:

- The table.
- Cups other than the cup that was ultimately scored in.
- Opponent player bodies and hands.

Explicit non-counting case:

- If the ball bounces off the rim/body of a cup and lands in that same cup, that contact does not count as a Bouncing bonus.

For Online Arena, the active ball authority collects contacts for the active throw and resolves the shot once. Peers apply the resulting scored cup arrays and serialized shot outcome rather than inferring their own separate rule result.

## Rule Definitions

### Bouncing

If a throw touches at least one playable bounce surface and then scores in a cup, remove one additional opponent cup.

Implementation notes:

- The scored cup is always removed first.
- The additional cup selection must be deterministic. Use `lowest active cup index excluding already removed cups` for the first implementation unless a better UX is added.
- Contact with the scored cup itself does not satisfy the bounce condition.
- Resolve Chain Lightning first if both rules are enabled. Bouncing may then add one deterministic extra cup only if an eligible active cup remains.
- Record a `rule_triggers` entry with the rule id and extra cup index.

Current state:

- Implemented in `HouseRulesResolver`.
- Driven by `ShotContactTracker` table/cup/hand/body contacts.

### Chain Lightning

If the ball hits one or more other active opponent cups and ends up scoring in a cup, each touched opponent cup is removed.

Implementation notes:

- Count distinct active opponent cups touched during the shot.
- Remove the scored cup plus each distinct touched opponent cup.
- Exclude cups already scored/removed.
- Recommended behavior: Chain Lightning triggers only when at least one other active opponent cup was touched before the final score.
- Do not remove the same cup twice.
- Record touched cup indices in `rule_triggers`.

Current state:

- Implemented in `HouseRulesResolver`.
- Uses distinct touched target cup indices from `ShotContactSummary`.

### Ring of Fire

If a side has removed the opponent's three corner cups and center cup, leaving a ring of six cups, Ring of Fire becomes active for that target rack. A ball coming to rest in the center gap of the ring wins the match immediately.

Implementation notes:

- This requires stable cup identity. Define starting rack roles for `corner` and `center` cups in shared rack metadata instead of relying on scene order guesses.
- Add an alternate scoring detector for the ring center gap. It should confirm the ball has settled inside a target area between the remaining six cups, not inside a cup.
- Ring of Fire is an alternate win condition, not a cup removal bonus.
- The resolver should report `winner_side` or `winner_player_id` through `ShotOutcome`.
- Network snapshots must carry this as a resolved win state.

### Reracks

Each side has one rerack resource. Spending it rearranges that side's target cups into a selected allowed pattern for the current number of remaining cups.

Implementation notes:

- Rerack is a per-side match resource, not a per-player local preference.
- Rerack should be requested before a shot, not during a released throw.
- Rerack shapes should be data-driven and can land after the resolver path is stable.
- The initial implementation can define the resource and request/apply flow before adding the full shape list.
- Rerack application should move existing cup nodes and update `RackState`; it should not destroy/recreate scored cups in a way that loses stable indices.
- Online Arena should make rerack requests authoritative through `NetworkMatchState`.

Examples to support later:

- Straight line of 3 cups when 3 remain.
- Diamond shape when 4 cups remain.

### Gentleman's

An extra rerack available whenever a team has two target cups left. It arranges those cups at the back of the table in a vertical line.

Implementation notes:

- This should not consume the normal one-rerack resource.
- Track it as a separate per-side resource.
- It is available only when exactly two active target cups remain.
- It should use the same rerack request/apply pipeline as standard Reracks.
- Online Arena should replicate whether the Gentleman's resource has been used per side.

### Balls Back

If a side makes both of its two shots in a normal turn, that side receives another consecutive two-shot turn.

Implementation notes:

- Track made shots within the current normal turn.
- Award another turn only when both normal turn shots were made.
- Heating Up / Fire bonus shots should not count as the two normal shots needed for Balls Back unless explicitly represented as a new normal turn.
- `ShotOutcome.same_side_next_turn` is available for this turn-flow directive.

### Heating Up / Fire

If a player makes two shots in a row, they must acknowledge they are heating up. If acknowledged and they make a third consecutive shot, they are On Fire and receive a bonus shot. While On Fire, every made bonus shot grants another bonus shot until they miss.

Implementation notes:

- Track streaks per player, not just per side, so multiplayer and future team modes stay clear.
- Add a player acknowledgement state after the second consecutive make. In VR, this should likely be an in-world prompt/action before the next throw.
- If the player fails to acknowledge before the third throw, the third make should count as a normal make but should not award On Fire.
- Bonus shots should be represented separately from normal shots remaining so they do not corrupt two-shot turn logic.
- A miss resets that player's make streak and On Fire state.
- Online Arena should replicate acknowledgement and streak state through match snapshots or dedicated reliable RPCs.

### Island

If one active target cup is isolated from all other cups and there is a mainland of at least three contiguous active cups, Island is in play. A player may call Island once per game. If they hit the island cup, one extra cup is removed. If they hit any other cup, that cup does not count and is not removed.

Implementation notes:

- Track one Island resource per player for the match.
- Add a pre-shot declaration flow when Island is available.
- Compute isolated and mainland cups from current cup positions and a configurable adjacency threshold based on cup spacing.
- A valid Island call should lock the selected island cup for that shot.
- If the shot scores in the island cup, remove the island cup plus one deterministic extra opponent cup.
- If the shot scores in any other cup, ignore the score for cup-removal purposes and treat the shot as spent.
- If the shot misses entirely, no cup is removed and the Island resource is consumed.
- Online Arena must include Island declaration and selected target cup in authoritative state before the throw is released.

## Multiplayer Authority

Online Arena should keep `NetworkMatchState` as the centralized owner of match decisions. House Rules should not scatter Photon calls through individual rule scripts.

Recommended flow:

1. Host creates or joins the Photon room and seeds room rules from the local `HouseRulesProfile`.
2. Room rules are published in match snapshots before gameplay starts.
3. Active local player releases the ball.
4. Ball authority records contact summary until score/miss resolution.
5. `NetworkMatchState` builds `ShotContext`.
6. Shared resolver returns `ShotOutcome`.
7. `NetworkMatchState` publishes one snapshot containing updated scores, scored cup indices, active player, shots/bonus state, rerack resources, player streaks, enabled rules, winner, and reset delay.
8. Peers apply that snapshot and play local presentation.

Do not rely on every peer independently detecting Bouncing, Chain Lightning, Ring of Fire, or Island. Small physics differences can desync results.

## Validation Notes

First-pass local validation:

- `.\tools\validate_codex.cmd` reached the menu scene in Godot 4.7.1 and loaded the non-XR fallback camera without script crashes.
- Practice smoke validation loaded with 10 cups and logged the default `hr1-11111111` House Rules profile.
- Classic Match smoke validation loaded with 10 cups per side, started the player's two-shot turn, and logged the default `hr1-11111111` House Rules profile.
- Online Arena smoke validation loaded the networked scene, initialized Photon Fusion Godot SDK `3.0.0.2787`, began connecting, then disconnected during local validation. This remains a local networking validation caveat, not evidence of rule behavior.
- Computer Classic Match automatic validation runs with `.\Godot_v4.7.1-stable_win64_console.exe --headless --xr-mode off --path project-pong --scene res://scenes/editor/computer_classic_match.tscn --log-file codex-computer-classic-auto.log -- --codex-auto-test`. The current deterministic smoke resolves physical CPU-vs-CPU shots, requires at least one real score by default, and reports a JSON snapshot with `passed: true` when shared-model scores and scored cup indices stay consistent. Add `--codex-require-complete` to require a full physical match completion.

Known local environment warnings:

- Godot logs `Property not found: 'xr/openxr/extensions/hand_tracking'`.
- Godot logs a Windows root certificate store warning during startup.

Quest hardware verification was not captured in the first House Rules pass. Any future House Rules milestone still needs on-device Quest 2 or Quest 3 testing before it is considered complete.

## Completion Expectations

Before declaring House Rules complete:

- Practice mode still supports fast local throw/cup/reset testing.
- Classic Match still handles player turn, computer turn, score, win, and return-to-menu.
- Online Arena still separates local player input, remote hand visibility, ball authority, and shared match state.
- Each rule can be enabled or disabled independently.
- The default fresh profile enables every initial rule.
- Disabled rules produce baseline scoring.
- Enabled rules cannot remove the same cup twice.
- Multiplayer resolves each shot once and all peers apply the same cup removals, turn state, resources, and winner.
- Hardware verification on Quest remains required for final confidence. If unavailable, report which local validations were run instead.
