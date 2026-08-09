# Shot Tester Implementation Plan

## Purpose

Create an editor-only Godot scene for testing a single beer-pong shot against a configurable rack and match-state snapshot. The scene should let a developer manually tune initial shot conditions, reproduce those same conditions from a headless console run, launch a physical ball through the shared shot helpers, resolve the result through the existing House Rules pipeline, and emit human-readable shot logs.

This tool should be built for rapid iteration on shot behavior, computer throw tuning, House Rules interactions, and cup-removal outcomes without disturbing Practice, Classic Match, or Online Arena.

## Proposed Files

- `res://scenes/editor/shot_tester.tscn`
  Editor-only scene containing the test table, one target rack, one launch ball, an aim indicator sphere, a testing camera, and a 2D UI overlay.
- `res://scripts/editor/shot_tester.gd`
  Scene controller that owns UI state, aim tracking, launch calculation, physics stepping, shot resolution, logging, and CLI test entry points.
- Optional later split: `res://scripts/editor/shot_tester_ui.gd`
  Extract only if the UI code starts crowding the physics/resolution controller.

Reuse these existing scripts instead of creating separate scoring or throw logic:

- `res://scripts/match/computer_throw_physics.gd`
- `res://scripts/match/shot_physics.gd`
- `res://scripts/match/shot_score_tracker.gd`
- `res://scripts/match/shot_attempt_evaluator.gd`
- `res://scripts/match/cup_rack_builder.gd`
- `res://scripts/match/rack_state.gd`
- `res://scripts/match/cup_removal_queue.gd`
- `res://scripts/house_rules/shot_context.gd`
- `res://scripts/house_rules/shot_contact_tracker.gd`
- `res://scripts/house_rules/house_rules_profile.gd`
- `res://scripts/house_rules/house_rules_settings_store.gd`
- `res://scripts/house_rules/house_rules_resolver.gd`

## Scene Structure

Recommended node layout:

```text
ShotTester (Node3D, script: shot_tester.gd)
  TableRoot (Node3D)
  TargetCupParent (Node3D)
  BallSpawn (Marker3D)
  AimIndicator (MeshInstance3D, sphere)
  AimIndicatorHitArea (Area3D)
  TestBall (ThrowableBall/RigidBody3D)
  ShotContactTracker (Node or controller-owned helper, depending on current helper shape)
  CameraRig (Node3D)
    TestingCamera (Camera3D)
  CanvasLayer
    RootPanel (Control)
      InitialConditionsPanel
      MatchStatePanel
      HouseRulesPanel
      ShotControlsPanel
      LogPanel
```

Keep the scene under `scenes/editor/` and guard exported builds the same way `ComputerClassicMatchGame` does:

```gdscript
if OS.has_feature("template"):
    push_warning("[ShotTester] Editor-only shot tester is disabled in exported builds.")
    set_process(false)
    set_physics_process(false)
    return
```

## Initial Conditions

### Aim Position

The aim position must be settable in two ways:

1. Manual scene control:
   - Show a visible sphere at the current `aim_position`.
   - Let the user move it with mouse dragging on a table plane plus keyboard nudges.
   - Keep numeric `x`, `y`, and `z` input fields synchronized with the sphere.
   - Use modifier keys for coarse/fine nudging, for example `Shift` for larger steps and `Ctrl` for smaller steps.
   - Snap-to-cup buttons are useful but optional: selected active cup rim, rack center, and last scored cup.

2. Headless console control:
   - Accept explicit coordinates such as `--shot-aim=0.000,0.840,-2.150`.
   - When this argument is present, set the indicator sphere position from the parsed value before launching.
   - Include the parsed aim value in the final JSON and text log.

The indicator sphere is the source of truth for manual testing. On every UI edit or drag event, update:

- `_aim_position`
- `AimIndicator.global_position`
- the aim-position spin boxes/text fields
- the planned launch preview label

### Release Angle

Expose `release_angle_degrees` as a numeric input with a sensible range matching the direct computer planner constraints:

- Minimum: `8.0`
- Maximum: `88.0`
- Default: a stable direct-shot value, for example `42.0`

When launching a direct test shot, calculate the velocity using logic equivalent to `ComputerThrowPlanner._build_direct_plan`:

```gdscript
var launch_velocity := ComputerThrowPhysicsScript.calculate_launch_velocity_for_ball_angle(
    ball,
    launch_transform.origin,
    aim_position_with_error,
    release_angle_degrees_with_error
)
```

If the angle solver returns an invalid velocity, log `fallback_reason = "angle_solver_invalid"` and optionally fall back to `ComputerThrowPhysicsScript.calculate_launch_velocity_for_ball()` with the same `DIRECT_FALLBACK_ARC_HEIGHT` used by `computer_throw_planner.gd`. The UI should clearly show whether the current planned launch is valid before the user presses Test Shot.

### Aim Position Error

Add input UI for a horizontal aim-position error radius in meters.

- Default: `0.0`
- Range: `0.0` to at least `0.35`
- Interpretation: sample a random horizontal offset in the X/Z plane and add it to the indicator position before computing launch velocity.
- Seed: use a visible deterministic seed field so failed shots can be reproduced.

For single-shot manual testing, log both the configured radius and the sampled vector:

- `aim_error_radius`
- `sampled_aim_error`
- `effective_aim_position`

### Release Angle Error

Add input UI for a signed release-angle error range in degrees.

- Default: `0.0`
- Range: `0.0` to at least `30.0`
- Interpretation: sample a random value from `[-angle_error_degrees, angle_error_degrees]`.
- Clamp the final release angle to `8.0` through `88.0`.

For each shot, log:

- `release_angle_degrees`
- `angle_error_degrees`
- `sampled_angle_error_degrees`
- `effective_release_angle_degrees`

## Match State Inputs

### Remaining Cups

Implement a skeuomorphic cup-pyramid UI showing the 10-cup rack from the shooter-facing perspective. Each cup control should:

- Display the stable `cup_index`.
- Toggle active/inactive on click.
- Grey out inactive cups.
- Update the physical rack and `RackState` immediately.
- Prevent a disabled cup from being scored or selected as an Island cup.

The physical rack should continue to be built through `CupRackBuilder` so cup positions, indices, owner metadata, and collision behavior match Classic Match. The UI is only an editor control surface over the rack state.

Recommended first-pass mapping:

```text
Back row:     6  7  8  9
Third row:      3  4  5
Second row:       1  2
Front cup:          0
```

Confirm this mapping against the actual `CupRackBuilder` row/column metadata during implementation. If the current rack assigns indices differently, the UI should use the real metadata rather than a hard-coded visual guess.

### Island Call

Track Island declaration state, but do not implement Island scoring behavior in this scene until the shared resolver supports it.

UI fields:

- `Island called` checkbox or toggle.
- `Island cup index` selector, enabled only when Island is called.
- Optional visual highlight around the selected active cup.

When building `ShotContext`, set:

- `selected_rule_id = &"island"` if Island has been called.
- `selected_cup_index = island_cup_index`.

The shot log should include Island state even though the current resolver may ignore it:

- `island_called`
- `island_cup_index`
- `island_rule_enabled`

### House Rules File

Add a text input for a House Rules file path or profile identifier.

Supported first-pass sources:

- Empty value: use `HouseRulesSettingsStore.load_profile()`.
- `default`: use `HouseRulesProfile.default_profile()`.
- `disabled`: create a profile with all known rules disabled.
- `res://...`, `user://...`, or an absolute editor-local path: load a `ConfigFile` or dictionary-style profile if supported by the implementation.

The initial implementation should favor the existing `HouseRulesProfile` dictionary shape:

```gdscript
{
    "version": 1,
    "enabled_rules": {
        "bouncing": true,
        "chain_lightning": true
    }
}
```

Add a popout panel that displays the in-play House Rules after a file/profile is loaded:

- Compact ruleset id, such as `hr1-11111111`.
- Each known rule name.
- Enabled/disabled state.
- Scoring summary.
- Authority summary.

This popout is informational for the tester. It should not mutate the saved global House Rules settings unless the user explicitly loads from or saves to the normal settings store in a future pass.

## Shot Execution Flow

1. Initialize the scene:
   - Build one target rack through `CupRackBuilder`.
   - Create a `RackState` for the target rack.
   - Reset the ball to `BallSpawn`.
   - Load the selected House Rules profile.
   - Set the aim indicator to the rack center or selected cup rim center.

2. User edits initial conditions and match state:
   - Aim indicator and numeric aim fields stay synchronized.
   - Cup pyramid UI updates active cup state.
   - Island selection updates `ShotContext` declaration fields.
   - House Rules popout reflects the active profile.

3. User presses `Test Shot`, or the headless run starts:
   - Sample aim and angle errors with the deterministic RNG.
   - Compute launch velocity with `calculate_launch_velocity_for_ball_angle`.
   - Reset contact and score trackers.
   - Launch the ball with `ComputerThrowPhysics.launch_ball`.
   - Store an immutable `initial_conditions` dictionary for the log.

4. During physics:
   - Track contacts through `ShotContactTracker`.
   - Ask `RackState.find_resting_cup(ball)` for a candidate score.
   - Confirm scoring through `ShotScoreTracker`.
   - Detect misses/timeouts through `ShotAttemptEvaluator`.

5. Resolve:
   - Build `ShotContext` with active side/player, target rack, selected Island fields, current rules profile, and contact summary.
   - Call `HouseRulesResolver.resolve_attempt(context, was_score, scored_cup, reset_delay)`.
   - Apply `removed_cup_indices` to `RackState`.
   - Update the cup-pyramid UI to grey out removed cups.
   - Append a detailed result entry to the shot log.

6. Reset:
   - Provide `Reset Ball`, `Reset Rack`, and `Repeat Shot` buttons.
   - `Repeat Shot` should reuse the same seed and initial inputs.
   - `Next Variation` should advance the seed and resample configured error.

## UI Requirements

Manual testing should be fast and responsive. Recommended controls:

- Aim position:
  - `x`, `y`, `z` numeric fields.
  - Visible draggable aim sphere.
  - Reset/snap buttons.
- Release:
  - Release angle numeric field.
  - Aim error radius numeric field.
  - Angle error range numeric field.
  - Seed numeric field.
- Match state:
  - Clickable 10-cup pyramid with visible indices.
  - Active/inactive visual state.
  - Island toggle and cup selector.
  - House Rules file field, Load button, and popout rule summary.
- Shot controls:
  - Test Shot.
  - Repeat Shot.
  - Reset Ball.
  - Reset Rack.
  - Export Log.
- Readouts:
  - Planned launch velocity.
  - Effective aim position.
  - Effective release angle.
  - Last scored cup.
  - Cups removed by baseline scoring and House Rules.

Use ordinary Godot `Control` nodes for the editor UI. This scene is an editor/test tool, not a VR menu, so 2D controls are acceptable and faster to iterate on.

## Camera Controls

Use the same style as `ComputerClassicMatchGame`:

- `WASD` or arrow keys move the camera focus.
- `Q/E` lower and raise the focus point.
- Mouse wheel zooms.
- Right mouse drag orbits around the focus.
- Optional `F` focuses the camera on the aim indicator.
- Optional `C` focuses the camera on the scoring rack.

The camera should default to a clear view of the ball launch, aim indicator, table, and rack. Avoid XR startup in this scene; it should run in the editor and headless validation paths.

## Headless Console Run

Add a CLI mode similar to `ComputerClassicMatchGame`:

```powershell
.\Godot_v4.7.1-stable_win64_console.exe --headless --xr-mode off --path project-pong --scene res://scenes/editor/shot_tester.tscn --log-file codex-shot-tester.log -- --shot-test --shot-aim=0.000,0.840,-2.150 --shot-angle=42 --shot-aim-error=0 --shot-angle-error=0 --shot-active-cups=0,1,2,3,4,5,6,7,8,9 --shot-house-rules=default
```

Suggested command-line arguments:

- `--shot-test`
- `--shot-aim=x,y,z`
- `--shot-angle=degrees`
- `--shot-aim-error=meters`
- `--shot-angle-error=degrees`
- `--shot-seed=integer`
- `--shot-active-cups=0,1,2`
- `--shot-island-cup=index`
- `--shot-house-rules=default|disabled|saved|path`
- `--shot-max-physics-frames=6000`
- `--shot-expect-score=true|false`
- `--shot-expect-removed=0,1`

The headless run should print one final JSON line:

```text
[ShotTester] {"passed":true,"resolved_score":true,"scored_cup_index":0,"removed_cup_indices":[0],"ruleset_id":"hr1-11111111"}
```

## Logging

Every shot should produce both a concise summary and a detailed entry.

Summary example:

```text
Shot 3: scored cup 4, removed [4, 1], rules hr1-11000000, triggers [chain_lightning], island none
```

Detailed entry fields:

- Shot number.
- Seed.
- Initial aim position.
- Sampled aim error.
- Effective aim position.
- Release angle.
- Sampled angle error.
- Effective release angle.
- Launch transform.
- Launch velocity.
- Active cup indices before the shot.
- Island called/cup index.
- House Rules source and compact ruleset id.
- Enabled House Rules list.
- Contact summary.
- Was score.
- Scored cup index.
- Removed cup indices.
- Ignored cup indices.
- Rule triggers.
- Cups remaining after the shot.
- Failure/fallback reason, if any.

Add an `Export Log` button that writes a text file under `user://shot_tester_log.txt` by default. The export should include readable text and a JSON-safe raw dictionary for each shot.

## Validation Plan

Add validation in small slices:

1. Scene smoke:
   - Open `res://scenes/editor/shot_tester.tscn` in headless mode.
   - Confirm the scene initializes, builds 10 cups, and loads a House Rules profile.

2. Zero-error direct shot:
   - Aim at an active cup rim center.
   - Use `aim_error = 0` and `angle_error = 0`.
   - Confirm at least one reproducible score with a fixed seed.

3. Cup-state control:
   - Disable a cup through CLI and UI.
   - Confirm it cannot be scored or removed.
   - Confirm cup indices remain stable in logs.

4. House Rules profile:
   - Run with `disabled` profile and confirm baseline one-cup removal.
   - Run with Bouncing/Chain Lightning profiles after contact conditions can be produced or injected.
   - Confirm `ruleset_id`, enabled rules, and triggers appear in logs.

5. Island tracking:
   - Set Island called on an active cup.
   - Confirm `ShotContext.selected_rule_id` and `selected_cup_index` are logged.
   - Confirm no Island scoring behavior is claimed until resolver support exists.

6. Existing baseline safety:
   - Run `.\tools\validate_codex.cmd`.
   - Run the existing computer classic scene automatic validation if shot helper behavior changes.
   - Note that Quest headset verification is not required for this editor-only tool, but Practice, Classic Match, and Online Arena still need their usual validation after shared helper changes.

## Implementation Order

1. Add `shot_tester.tscn` with table, target rack parent, ball spawn, test ball, aim indicator, camera, and placeholder UI panels.
2. Implement initialization, rack building, ball reset, and saved/default House Rules loading.
3. Implement aim indicator synchronization between numeric fields, mouse/keyboard scene controls, and CLI arguments.
4. Implement direct launch calculation through `ComputerThrowPhysics.calculate_launch_velocity_for_ball_angle`.
5. Implement shot lifecycle using shared score, miss, contact, and resolver helpers.
6. Implement the cup-pyramid UI and keep it synchronized with `RackState`.
7. Implement Island declaration tracking.
8. Implement House Rules file/profile loading and popout display.
9. Implement log list, log export, and final headless JSON output.
10. Add focused validation commands to `tools/validate_codex.ps1` only after the scene is stable.

## Open Questions

- Should the first scene use the existing `ThrowableBall` from Practice/Classic, or a stripped test-only rigid body with the same exported flight properties?
- Should contact summaries support synthetic injection from the UI so Bouncing and Chain Lightning can be tested without physically causing a bounce or cup touch?
- Should House Rules file loading support only `ConfigFile` in the first pass, or also JSON dictionaries for easier generated test fixtures?
- Should the cup pyramid represent the target rack from the shooter viewpoint or the table/world viewpoint? The recommendation is shooter viewpoint, but implementation should label the orientation clearly in the UI.
