# House Rules Implementation Guide

## Purpose

House Rules are optional gameplay modifiers that extend the standard scoring rule: a made shot removes the cup the ball comes to rest in. They must work across Practice, Classic Match, and Online Arena without duplicating scoring logic inside each mode script.

This file is planning guidance only. Do not implement code from this document until a focused House Rules implementation pass begins.

## Current Code Observations

- Practice mode is driven by `res://scripts/single_player_game.gd`. It owns rack creation, score confirmation, miss detection, cup removal, and ball reset locally.
- Classic Match is driven by `res://scripts/classic_match_game.gd`. It duplicates much of the Practice scoring loop and adds turns, two shots per turn, player/computer racks, computer aiming, match end, and menu return.
- Online Arena uses `res://scripts/network_match_state.gd` as the centralized networked match authority. It builds both racks, tracks scored cup indices, resolves shots for the active player, broadcasts compact snapshots, and applies cup removal visuals on each peer.
- `res://scripts/cup_target.gd` owns per-cup score detection through `is_ball_resting_inside()`, exposes `cup_index` metadata in match modes, and marks/removes cups.
- `res://scripts/pong_physics_surface.gd` already carries a `surface_id`, which is a good starting point for bounce/contact classification.
- `res://scenes/menu.tscn` already contains a disabled `House Rules` menu button. The implementation pass should make this open a rules settings panel instead of adding a separate menu style.

The important architectural issue: scoring, removal, turn advancement, and reset timing are currently repeated in mode-specific scripts. House Rules should be implemented as a shared rules evaluation system that all modes call.

## Design Goals

- One shared rules pipeline should evaluate every shot outcome for Practice, Classic Match, and Online Arena.
- Game modes should provide context and apply the returned result; they should not each re-implement Bouncing, Chain Lightning, Island, or future rules.
- Rules should be composable. Any subset of rules can be enabled.
- Rules should be deterministic enough for multiplayer. The active authority resolves the shot once, then replicates the compact result.
- Rules should separate gameplay state from presentation. VFX, labels, and sounds should react to a resolved outcome but never decide scoring.
- Rules should be data-oriented where practical: enabled flags, per-side resources, per-player streaks, touched cups, scoring cup, bonus shots, winner, and rerack state should serialize cleanly.

## Recommended Architecture

Implement House Rules as a small shared gameplay layer under `res://scripts/house_rules/` or equivalent:

- `HouseRuleIds`: stable string or `StringName` constants for each rule.
- `HouseRulesProfile`: enabled/disabled settings for all rules. Defaults every initial rule to enabled.
- `HouseRulesSettingsStore`: loads and saves the local user's preferred enabled rules between sessions.
- `ShotContext`: immutable input describing the active mode, active side/player, opponent side, ball, rack state, contacts, selected shot declaration, and currently enabled rules.
- `ShotContactTracker`: per-shot tracker attached to or fed by the ball that records contacts with playable surfaces, cups, hands, and bodies after release.
- `ShotOutcome`: shared result object containing made/missed state, scored cup, extra cups to remove, ignored cups, bonus shots, extra turns, winner, reset timing hints, UI messages, and rule trigger metadata.
- `HouseRulesResolver`: evaluates standard scoring plus enabled rules and returns a `ShotOutcome`.
- `RackState`: shared rack representation for both local and networked modes, including cup indices, owner side, active/scored status, positions, and current arrangement.

Mode scripts should move toward this shape:

1. Mode owns lifecycle: start match, start turn, release shot, advance/reset, update labels.
2. Mode asks shared helpers for rack creation/state and score detection.
3. Mode sends `ShotContext` to `HouseRulesResolver`.
4. Mode applies `ShotOutcome` through one shared cup-removal path.
5. Online Arena serializes only the authoritative outcome and state changes, not every cosmetic effect.

## Menu and Persistence

- The `House Rules` option in `res://scenes/menu.tscn` should become selectable and open an in-world panel.
- The panel should list each rule name with a toggle switch.
- Default state: all listed House Rules are enabled for a fresh profile.
- Toggle changes should be saved immediately or when closing the panel using `user://` storage, not project settings committed to source control.
- The saved profile should be loaded before entering Practice, Classic Match, or Online Arena.
- Online Arena should treat the host or room creator's selected rules as the room rules. Persisted local preferences should seed room creation, but once in a room all players use the room's replicated rules profile.
- Future Photon room creation should expose a compact ruleset identifier/hash in room properties before gameplay starts.

## Shot Contact Model

Several rules depend on what the ball touched before scoring. Add contact tracking before implementing those rules.

Track these event types per released shot:

- `table`: playable table surface.
- `cup`: any active cup, including cup index and owning side.
- `hand`: opponent hand/controller avatar.
- `body`: opponent body/avatar hit zone when body avatars exist.
- `non_playable`: floor, walls, local player's own body/hand, or other surfaces that do not count for bounce rewards.

Playable bounce surfaces for the initial rules:

- The table.
- Cups other than the cup that was ultimately scored in.
- Opponent player bodies and hands.

Explicit non-counting case:

- If the ball bounces off the rim/body of a cup and lands in that same cup, that contact does not count as a Bouncing bonus.

For Online Arena, the active ball authority should collect contacts for the active throw and include the resolved contact summary in the authoritative shot resolution. Peers should apply the summary rather than infer their own separate rule result.

## Rule Definitions

### Bouncing

If a throw touches at least one playable bounce surface and then scores in a cup, remove one additional opponent cup.

Implementation notes:

- The scored cup is always removed first.
- The additional cup selection must be deterministic. Prefer an explicit rule policy such as "nearest active cup to the scored cup" or "lowest active cup index excluding the scored cup" until a better UX is designed.
- Contact with the scored cup itself does not satisfy the bounce condition.
- If Chain Lightning is also enabled and removes cups from touched cup contacts, do not remove the same cup twice.

### Chain Lightning

If the ball hits multiple cups and ends up scoring in a cup, each touched opponent cup is removed.

Implementation notes:

- Count distinct active opponent cups touched during the shot.
- Remove the scored cup plus each distinct touched opponent cup.
- Exclude cups already scored/removed.
- Decide in the implementation pass whether the scored cup must be included in the "multiple cups" count. Recommended behavior: Chain Lightning triggers only when at least one other active opponent cup was touched before the final score.
- If Bouncing is also enabled, resolve Chain Lightning first, then let Bouncing add one deterministic extra cup only if there is still an active eligible cup.

### Ring of Fire

If a side has removed the opponent's three corner cups and center cup, leaving a ring of six cups, Ring of Fire becomes active for that target rack. A ball coming to rest in the center gap of the ring wins the match immediately.

Implementation notes:

- This requires stable cup identity. Define starting rack indices for `corner` and `center` cups in shared rack metadata instead of relying on scene order guesses.
- Add an alternate scoring detector for the ring center gap. It should confirm the ball has settled inside a target area between the remaining six cups, not inside a cup.
- Ring of Fire is an alternate win condition, not a cup removal bonus.
- The resolver should report `winner_side` or `winner_player_id` directly in `ShotOutcome`.
- Network snapshots must carry this as a resolved win state.

### Reracks

Each side has one rerack resource. Spending it rearranges that side's target cups into a selected allowed pattern for the current number of remaining cups.

Implementation notes:

- Rerack is a per-side match resource, not a per-player local preference.
- Rerack should be requested before a shot, not during a released throw.
- Rerack shapes should be data-driven and implemented in a focused later pass.
- The initial implementation can define the resource and request/apply flow before adding the full shape list.
- Rerack application should move existing cup nodes and update `RackState`; it should not destroy/recreate scored cups in a way that loses stable indices.
- Online Arena should make rerack requests authoritative through `NetworkMatchState`.

Examples to support later:

- Straight line of 3 cups when 3 remain.
- Diamond shape when 4 cups remain.

### Gentleman's

An extra rerack available whenever a team has two target cups left. It arranges those cups at the back of the table in a vertical line.

Implementation notes:

- This does not consume the normal one-rerack resource unless the rule implementation explicitly chooses to do so. Recommended behavior: track it as a separate per-side resource.
- It is available only when exactly two active target cups remain.
- It should use the same rerack request/apply pipeline as standard Reracks.
- Online Arena should replicate whether the Gentleman's resource has been used per side.

### Balls Back

If a side makes both of its two shots in a normal turn, that side receives another consecutive two-shot turn.

Implementation notes:

- Track made shots within the current turn.
- Award another turn only when both normal turn shots were made.
- Decide how bonus shots interact with this rule. Recommended behavior: Heating up/Fire bonus shots do not count as the two normal shots needed for Balls Back unless explicitly represented as a new normal turn.
- `ShotOutcome` should include a turn-flow directive such as `same_side_next_turn`.

### Heating Up / Fire

If a player makes two shots in a row, they must acknowledge they are heating up. If acknowledged and they make a third consecutive shot, they are On Fire and receive a bonus shot. While On Fire, every made bonus shot grants another bonus shot until they miss.

Implementation notes:

- Track streaks per player, not just per side, so multiplayer and future team modes stay clear.
- Add a player acknowledgement state after the second consecutive make. In VR, this should likely be an in-world prompt/action before the next throw.
- If the player fails to acknowledge before the third throw, the third make should count as a normal make but should not award On Fire.
- Bonus shots should be represented separately from normal shots remaining so they do not corrupt two-shot turn logic.
- A miss resets that player's make streak and On Fire state.
- Online Arena should replicate the acknowledgement and streak state through match snapshots or dedicated reliable RPCs.

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

1. Active local player releases the ball.
2. Ball authority records contact summary until score/miss resolution.
3. `NetworkMatchState` builds `ShotContext`.
4. Shared resolver returns `ShotOutcome`.
5. `NetworkMatchState` publishes one snapshot containing updated scores, scored cup indices, active player, shots/bonus state, rerack resources, player streaks, enabled rules, winner, and reset delay.
6. Peers apply that snapshot and play local presentation.

Do not rely on every peer independently detecting Bouncing, Chain Lightning, Ring of Fire, or Island. Small physics differences can desync results.

## Integration Order

Implement in small passes:

1. Add shared data types for rules profile, rack state, shot context, contact summary, and shot outcome.
2. Add settings persistence and turn the menu's `House Rules` button into a toggle panel.
3. Refactor Practice and Classic Match to call the shared standard scoring resolver with all House Rules disabled internally, proving behavior stays identical.
4. Refactor Online Arena to serialize/apply shared `ShotOutcome` without changing gameplay behavior.
5. Add contact tracking and enable Bouncing and Chain Lightning.
6. Add per-side/per-player resources for Reracks, Gentleman's, Balls Back, Heating Up/Fire, and Island declarations.
7. Add Ring of Fire alternate score detection after rack metadata and center-gap detection are reliable.
8. Add focused validation scenes or tests for each rule.

## Validation Expectations

Before declaring House Rules complete:

- Practice mode still supports fast local throw/cup/reset testing.
- Classic Match still handles player turn, computer turn, score, win, and return-to-menu.
- Online Arena still separates local player input, remote hand visibility, ball authority, and shared match state.
- Each rule can be enabled or disabled independently.
- The default saved profile enables every initial rule.
- Disabled rules produce baseline scoring.
- Two enabled rules cannot remove the same cup twice.
- Multiplayer resolves each shot once and all peers apply the same cup removals, turn state, resources, and winner.
- Hardware verification on Quest remains required for final confidence. If unavailable, report which local validations were run instead.
