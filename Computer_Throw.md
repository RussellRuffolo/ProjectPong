# Computer Throw Improvement Plan

## Purpose

Computer throw logic should become a shared, configurable gameplay system used by both:

- `res://scripts/classic_match_game.gd`, where a human plays against a computer opponent.
- `res://scripts/computer_classic_match_game.gd`, where the editor-only computer-vs-computer simulation validates physical match behavior.

The immediate goal is to make computer throws predictable when accuracy is perfect, varied when accuracy is imperfect, and extensible enough to support future opponent personalities without duplicating trajectory code in each mode.

## Current Baseline

Relevant existing files:

- `res://scripts/match/computer_throw_physics.gd`
  Owns shared target selection delegation, aim point offsets, launch velocity calculation, reset, and launch helpers.
- `res://scripts/match/computer_target_selector.gd`
  Owns swappable target cup heuristics, currently `most_central` and `closest`.
- `res://scripts/classic_match_game.gd`
  Uses the shared computer throw helper for the computer opponent in Classic Match.
- `res://scripts/computer_classic_match_game.gd`
  Uses the same shared helper for physical CPU-vs-CPU validation.
- `res://scripts/house_rules/house_rule_ids.gd`
  Defines the `bouncing` House Rule id that must gate intentional bounce-shot attempts.

Keep this separation. Match scenes should choose a computer profile and ask shared helpers to build a throw plan; they should not embed their own target, aim, bounce, or trajectory math.

## Design Goals

- A computer player profile should describe behavior, not contain mode-specific logic.
- Direct shots with zero accuracy error should aim at the middle of the selected cup at rim height and score consistently under the current cup detector.
- Shot angle should be configurable per computer profile.
- Accuracy should affect both aim point and release angle, so misses can come from lateral aim error, short/long angle error, or both.
- Bounce-shot attempts should be controlled by profile propensity and allowed only when the Bouncing House Rule is enabled for the match.
- Bounce-shot aim should be computed from shared kinematics using the ball and table bounce behavior, not hand-tuned per scene.
- The same throw planning path should support future network authority by producing deterministic, serializable shot intent: profile id, selected cup index, shot type, aim point, release angle, launch velocity, and random seed/sample values.

## Proposed Assets

Add a computer player profile resource:

- `res://scripts/match/computer_player_profile.gd`

Recommended type: `Resource`, `class_name ComputerPlayerProfile`.

Recommended exported fields:

- `profile_id: StringName`
- `display_name: String`
- `target_heuristic: String`
- `direct_release_angle_degrees: float`
- `direct_aim_error_radius: float`
- `direct_angle_error_degrees: float`
- `bounce_propensity: float`
- `bounce_release_angle_degrees: float`
- `bounce_aim_error_radius: float`
- `bounce_angle_error_degrees: float`
- `bounce_target_height: float`
- `bounce_surface_id: StringName`
- `notes: String`

Create a profile collection under:

- `res://resources/computer_players/`

Initial profiles:

- `rookie_arc.tres`
  Uses `most_central`, high arcing direct shots, larger direct aim and angle error, low bounce propensity.
- `steady_classic.tres`
  Uses `most_central`, medium direct angle, small direct errors, very low bounce propensity.
- `line_drive.tres`
  Uses `closest`, lower direct angle, moderate angle error, almost no bounce shots.
- `bounce_artist.tres`
  Uses `most_central`, medium direct shot, high bounce propensity, smaller bounce-specific errors, only meaningful when Bouncing is enabled.
- `chaotic_party.tres`
  Uses mixed or future weighted heuristics, larger aim and angle errors, medium bounce propensity.

Classic Match can expose one `ComputerPlayerProfile` export for the opponent. Computer Classic Match can expose separate `ComputerPlayerProfile` exports for side one and side two.

## Shared Throw Planner

Introduce a shared planner so match modes stop assembling throws themselves:

- `res://scripts/match/computer_throw_planner.gd`

Recommended responsibilities:

1. Read the active `ComputerPlayerProfile`.
2. Select a target cup through `ComputerTargetSelector`.
3. Decide whether the shot is `direct` or `bounce`.
4. Compute the ideal target point.
5. Apply deterministic accuracy samples to aim point and release angle.
6. Return a serializable throw plan dictionary or small `RefCounted` value object.

Suggested throw plan fields:

- `profile_id`
- `shot_type`
- `target_cup_index`
- `target_position`
- `aim_position`
- `bounce_position`
- `release_angle_degrees`
- `launch_velocity`
- `aim_error`
- `angle_error_degrees`
- `rng_seed` or `rng_sample_index`

`ClassicMatchGame` and `ComputerClassicMatchGame` should call the planner, then pass the resulting launch transform and velocity to `ComputerThrowPhysics.launch_ball()`.

## Direct Shot Targeting

Rework direct shot target selection to aim at the cup center at rim height.

Current helper:

- `ComputerThrowPhysics.get_cup_top_center_position(cup)`

Target behavior:

- The ideal target point should be the center of the cup opening at rim height.
- `direct_aim_error_radius == 0.0` and `direct_angle_error_degrees == 0.0` should produce a shot that lands inside the selected cup and scores every time in a stable physics scene.
- `computer_aim_top_clearance` should either be removed from the main path or replaced by explicit profile fields. A hidden clearance offset makes zero-error shots harder to reason about.

Implementation detail:

- Prefer adding or tightening a cup helper such as `CupTarget.get_rim_center_position()`.
- If the cup scene origin is already at rim height, document that assumption in the helper.
- If the origin is not rim height, derive rim height from known collision/cup metadata rather than scattering magic offsets across match scripts.

## Release Angle Model

Replace arc-height-first direct throws with an angle-first API.

Recommended direct-shot API:

- Input: `start_position`, `target_position`, `gravity_scale`, `release_angle_degrees`.
- Output: launch velocity that intersects the target point under gravity.

Use projectile motion in the vertical plane between start and target:

- Let horizontal distance be `d`.
- Let vertical delta be `dy`.
- Let angle be `theta`.
- Solve speed squared as:
  `v2 = gravity * d * d / (2.0 * cos(theta)^2 * (d * tan(theta) - dy))`
- If the denominator is invalid, reject the angle and fall back to a safe configured angle or the existing arc-height solver.

Angle error should be sampled separately from aim error:

- `final_angle = profile.direct_release_angle_degrees + rng_range(-direct_angle_error_degrees, direct_angle_error_degrees)`
- Clamp final angle to a safe range, for example 8 to 80 degrees.
- Low-angle profiles produce line drives.
- High-angle profiles produce arcing shots.

Keep the existing arc-height solver temporarily as a fallback during migration.

## Bounce Shot Eligibility

Computer players should only attempt intentional bounce shots when all of these are true:

- The active House Rules profile has `bouncing` enabled.
- The selected `ComputerPlayerProfile.bounce_propensity` roll succeeds.
- A valid bounce trajectory can be solved for the selected target cup.
- The bounce point is on the playable table surface and inside the attempt bounds.
- The active mode can track contacts through `ShotContactTracker`, so the resulting score can trigger the Bouncing rule.

If any condition fails, the planner should fall back to a direct shot.

## Bounce Shot Kinematics

Introduce shared bounce-shot solving in `ComputerThrowPhysics`.

Recommended API:

- `calculate_bounce_launch_velocity(ball, start_position, bounce_position, target_position, release_angle_degrees, bounce_target_height)`
- `find_bounce_aim_point(ball, start_position, target_position, table_bounds, profile)`

The solver should use the same gravity scale as the real `ThrowableBall`.

Initial practical approach:

1. Select the target cup rim-center point.
2. Choose a target bounce height, representing the ball center height immediately after the table bounce.
3. Search candidate bounce points along the line from release position to target cup, biased toward the target half of the table.
4. For each candidate, solve the incoming segment from release point to bounce point using the profile bounce release angle.
5. Estimate post-bounce velocity using the ball/table bounce behavior.
6. Simulate or analytically solve the post-bounce segment to see whether it intersects the cup target point at rim height.
7. Choose the lowest-error candidate and return its launch velocity.

Because Godot physics material restitution/friction and custom ball behavior can be difficult to mirror perfectly, the first implementation can use a small deterministic search and lightweight physics prediction rather than a single fragile closed-form equation.

Required data:

- Ball radius or scoring clearance.
- Ball gravity scale.
- Table surface height.
- Table bounds.
- Bounce restitution.
- Optional horizontal damping/friction.

If the current ball or table scripts do not expose restitution/friction clearly, add explicit project-owned constants or accessors before relying on engine defaults.

## Bounce Shot Accuracy

Bounce shots should have separate error fields from direct shots:

- `bounce_aim_error_radius`
- `bounce_angle_error_degrees`

Apply bounce aim error to the bounce point or the final cup aim point, not both at first. Prefer perturbing the bounce point because it makes bounce-specific personalities easier to tune.

Apply angle error the same way as direct shots:

- `final_bounce_angle = profile.bounce_release_angle_degrees + rng_range(-bounce_angle_error_degrees, bounce_angle_error_degrees)`

The final throw plan should record whether the shot was intended as a bounce shot. This makes validation and future network replay easier to inspect.

## Target Selection Extensions

Keep `ComputerTargetSelector` responsible for choosing the cup, but make it easier to add future heuristics.

Near-term additions:

- `least_central`
- `front_cup`
- `back_cup`
- `highest_value_house_rule_target`
- `weighted_random`

Profiles should reference heuristics by stable string id. The selector should continue to break ties by lowest stable `cup_index` so deterministic validation remains simple.

## Mode Integration Plan

Classic Match:

1. Replace `computer_target_heuristic`, `computer_accuracy_error_radius`, `computer_throw_arc_height`, and `computer_aim_top_clearance` exports with a `ComputerPlayerProfile` export.
2. Keep temporary legacy exports only if needed for scene compatibility during migration.
3. Use `ComputerThrowPlanner` in `_execute_computer_throw()`.
4. Log profile id, shot type, target cup index, and launch velocity.

Computer Classic Match:

1. Add profile exports for side one and side two.
2. Use the same planner path as Classic Match.
3. Add throw plan fields to each shot-log event.
4. Allow automatic tests to override profile ids or key profile fields through CLI config.

Shared:

1. Keep shot resolution in `HouseRulesResolver`.
2. Keep contact tracking in `ShotContactTracker`.
3. Keep cup selection deterministic where possible.
4. Keep all gameplay scoring based on actual resolved physics, not the planner's intended target.

## Multiplayer Readiness

The planner should be deterministic under an authority-provided seed. Future Online Arena computer players or assists should be able to replicate only the resolved shot intent and outcome.

Do not replicate cosmetic thought bubbles, labels, or personality text as gameplay state.

Future network-ready fields:

- Computer profile id.
- Active slot/player id.
- Target cup index.
- Shot type.
- Release transform.
- Launch velocity.
- Accuracy samples.
- Final resolved `ShotOutcome`.

Authority should still resolve scoring once through the shared match-state path.

## Validation Plan

Add validation in small steps:

1. Direct zero-error shot test
   Confirm each active cup can be selected, aimed at rim center, launched with zero direct errors, and scored in the CPU-vs-CPU scene.
2. Direct profile smoke test
   Run several seeded profiles and confirm shots resolve, scores remain consistent, and no invalid launch velocities are produced.
3. Angle solver test
   Verify line-drive, medium, and high-arc angles produce finite velocities and cross the intended target point in analytic prediction.
4. Bounce disabled test
   Confirm profiles with high bounce propensity still throw direct shots when `bouncing` is disabled.
5. Bounce enabled test
   Confirm high-propensity bounce profiles attempt bounce shots when `bouncing` is enabled and produce playable table contacts before scoring or missing.
6. Bounce solver regression test
   Sweep candidate cups and ensure the planner either returns a valid bounce plan or falls back cleanly to direct shots.
7. Existing smoke validation
   Continue running `.\tools\validate_codex.cmd` before considering the pass stable.

Quest headset verification is still required before treating any throw tuning as final, because VR frame pacing, physics timing, and player comfort can affect perceived behavior.

## Implementation Order

1. Add `ComputerPlayerProfile` and initial `.tres` profile assets.
2. Add `ComputerThrowPlanner` with direct shots only.
3. Add rim-center targeting and angle-based direct launch solving.
4. Migrate Classic Match and Computer Classic Match to profiles.
5. Add direct-shot validation for zero-error scoring and seeded profile smoke tests.
6. Add bounce-shot eligibility gated by the `bouncing` House Rule.
7. Add bounce kinematics and bounce-specific profile fields.
8. Add bounce-shot validation and tune profiles.
9. Document final profile fields and test outcomes in this file or a follow-up gameplay tuning note.

## Implementation Progress

- Step 1 complete.
  Added `res://scripts/match/computer_player_profile.gd` and starter profile resources under `res://resources/computer_players/`: `rookie_arc.tres`, `steady_classic.tres`, `line_drive.tres`, `bounce_artist.tres`, and `chaotic_party.tres`.
- Step 2 complete.
  Added `res://scripts/match/computer_throw_planner.gd` as the shared profile-driven throw planning entry point. Its first pass selects a target cup, applies direct aim and angle samples, and returns a direct-shot plan while still relying on the existing arc-height velocity helper until the angle-first solver lands.
- Step 3 complete.
  Added explicit rim-center targeting through `CupTarget.get_rim_center_position()`, kept `get_top_center_position()` as a compatibility alias, expanded target heuristics in `ComputerTargetSelector`, and added angle-based launch solving plus launch-velocity validation in `ComputerThrowPhysics`. Direct planner output now uses profile release angles and falls back to the old arc solver only when the angle solution is invalid.
- Step 4 complete.
  Migrated `ClassicMatchGame` and `ComputerClassicMatchGame` to call `ComputerThrowPlanner` instead of assembling target and velocity data directly. Classic Match now resolves a computer profile on ready, while Computer Classic Match builds one profile per side, records serialized throw-plan fields in shot-log events, and supports CLI profile overrides such as `--codex-side-one-profile=bounce_artist`.
- Step 5 complete.
  Added editor-only validation hooks to `ComputerClassicMatchGame`: `--codex-direct-zero-test` runs a zero direct aim/angle error scoring smoke, and `--codex-profile-smoke-test` runs seeded smoke coverage across the starter profile collection. Both run through the existing `--codex-auto-test` scene flow and report profile/throw-plan details in the JSON snapshot.
- Step 6 complete.
  Added House Rule-gated bounce eligibility to `ComputerThrowPlanner`. The planner now records `bounce_allowed`, `bounce_attempted`, and `bounce_roll`; a computer only attempts intentional bounce planning when its profile propensity roll succeeds and the active `HouseRulesProfile` has `bouncing` enabled. Until the kinematics solver is available, attempted bounce plans fall back to direct shots with `fallback_reason = "bounce_plan_unavailable"`.
- Step 7 complete.
  Added bounce-shot kinematics to `ComputerThrowPhysics` and connected it in `ComputerThrowPlanner`. The solver samples deterministic table bounce points, computes an incoming release-angle trajectory, estimates the post-bounce path from ball/table bounce and friction values, picks the lowest-error candidate, and returns a bounce launch velocity. Bounce aim and angle errors are separate from direct-shot errors, and failed bounce candidates still fall back to direct shots.
- Step 8 complete.
  Added `--codex-bounce-smoke-test` to the editor-only Computer Classic Match auto-test path. It verifies that a bounce-heavy profile does not attempt bounce shots when Bouncing is disabled, then enables only the Bouncing House Rule and checks that intentional bounce planning occurs. Tuned `bounce_artist.tres` to a higher bounce release angle and target bounce height so the first solver has reachable table-bounce candidates.
- Step 9 complete.
  Finalized the first implementation pass and recorded validation results below. A key tuning note from local physics: the current `CupTarget.get_rim_center_position()` is implemented as the effective computer aim point inside the score volume (`rim_center_y = 0.058`) rather than the visual cup mesh lip. The original visual-top target made centered shots pass through the cup/table without settling in the current prototype collision setup. Future cup model work should expose a true rim marker and retune the score/capture volume around that marker.

## Implemented Files

- `res://scripts/match/computer_player_profile.gd`
  Defines profile-driven target heuristic, direct angle/error, bounce propensity, bounce angle/error, target bounce height, bounce surface id, and notes.
- `res://resources/computer_players/*.tres`
  Adds `rookie_arc`, `steady_classic`, `line_drive`, `bounce_artist`, and `chaotic_party`.
- `res://scripts/match/computer_throw_planner.gd`
  Builds direct or bounce throw plans from a profile, House Rules state, target rack, ball, launch transform, and RNG.
- `res://scripts/match/computer_throw_physics.gd`
  Adds angle-based launch solving, flight damping compensation, rim/entry targeting, bounce candidate search, post-bounce prediction, and bounce launch helpers.
- `res://scripts/cup_target.gd`
  Adds an explicit computer aim/cup-mouth helper and light score-area capture damping.
- `res://scripts/classic_match_game.gd`
  Uses profile-driven planner output for computer throws and supports deterministic perfect planned direct scoring for zero-error computer profiles.
- `res://scripts/computer_classic_match_game.gd`
  Uses one profile per side, serializes throw-plan details in shot logs, and adds direct-zero, profile-smoke, and bounce-smoke validation modes.

## Validation Results

- `.\tools\validate_codex.cmd`
  Passed. Existing warnings remain: missing OpenXR hand-tracking project setting and Windows root certificate store warning.
- Computer Classic default auto-test:
  Passed with 4 resolved shots and 4 score events.
- `--codex-direct-zero-test`
  Passed with 6 resolved shots and 6 score events.
- `--codex-profile-smoke-test`
  Passed across all 5 starter profiles.
- `--codex-bounce-smoke-test`
  Passed. Disabled rules produced 0 bounce attempts; Bouncing-only produced 2 bounce attempts and 2 bounce plans.

Quest headset verification was not run for this pass.

## Open Questions

- Should profile assets be selected from the main menu, hard-coded per mode for now, or assigned per arena later?
- Should zero-error direct shots score in every cup from every legal computer release point, or only from the standard computer spawn positions?
- Should bounce shots prefer the table only, or should future personalities intentionally bounce off other cups or opponent bodies when those House Rules allow it?
- Should `bounce_target_height` represent ball center height immediately after bounce, peak height after bounce, or desired cup-entry height?
