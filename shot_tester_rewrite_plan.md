# Shot Tester Rewrite Plan

## Goal

Completely rewrite `shot_tester` around the conic frustum collision math proven in `collision_tester`, especially `classify_local_sphere_frustum_overlap`.

The rewrite should be modular, mathematical, and cup-local. Each cup should own a collision script that emits an event whenever a ball enters the calculated conic frustum volume. For the first pass, any frustum intersection counts as a collision event, and the ball should bounce off the calculated cup volume. Cups must not use Godot physics colliders.

## Scope

Replace these files wholesale:

- `res://scenes/editor/shot_tester.tscn`
- `res://scripts/editor/shot_tester.gd`

Do not preserve the current monolithic implementation. Rebuild the tester as a small set of cooperating scripts and scene nodes.

## Shared Collision Math

Extract the reusable frustum math from:

- `res://scripts/editor/collision_tester.gd`

Into a shared helper, likely:

- `res://scripts/match/conic_frustum_collision.gd`

The shared helper should preserve the behavior of `classify_local_sphere_frustum_overlap` and include the helper math needed to support it:

- nearest frustum surface point
- local nearest-surface normal
- radius at height
- rim band calculation
- side wall, inside volume, top inner, top rim band, bottom cap, and outside classifications

`collision_tester` should be updated to call this shared helper after extraction so both tester scenes use the same math.

## Proposed File Layout

Create a folder for the new shot tester implementation:

- `res://scripts/editor/shot_tester/`

Suggested modules:

- `shot_tester_app.gd`
  - Main scene coordinator.
  - Owns setup, reset, simulation lifecycle, UI wiring, and high-level shot state.

- `shot_tester_ball_launcher.gd`
  - Calculates launch velocity.
  - Applies aim error, angle error, and deterministic seed behavior.

- `shot_tester_rack.gd`
  - Builds and removes cup instances.
  - Tracks active cup indices.
  - Keeps rack layout concerns separate from shot simulation.

- `shot_tester_cup_sensor.gd`
  - Attached once per cup.
  - Contains no Godot physics colliders.
  - Converts ball positions into cup-local space.
  - Calls the shared frustum classification helper.
  - Emits a collision event when a ball first enters the calculated frustum volume.

- `shot_tester_collision_response.gd`
  - Converts collision snapshots into bounce response.
  - Reflects ball velocity using the calculated contact normal.
  - Moves the ball to a non-penetrating clear position.

- `shot_tester_ui.gd`
  - Builds and refreshes UI only.
  - Does not contain simulation or collision math.

- `shot_tester_log.gd`
  - Stores shot and collision events.
  - Exports logs.

## Cup Sensor Behavior

Each cup should own its own mathematical sensor script.

The sensor should store:

- cup index
- cup transform
- frustum parameters
- previous local ball position per tracked ball
- current overlap state per tracked ball

Every physics tick:

1. Read the ball world position.
2. Convert it into cup-local space.
3. Get the ball radius.
4. Call the shared frustum classification helper.
5. If `intersects == true` and this ball was not already intersecting this cup, emit:

```gdscript
signal ball_entered_frustum(cup: Node3D, ball: RigidBody3D, collision_snapshot: Dictionary)
```

For the first pass, all intersection classes count as collision events:

- `side_wall`
- `inside_volume`
- `top_inner`
- `top_rim_band`
- `bottom_cap`

## No Cup Physics Colliders

Cup nodes in the new `shot_tester` scene must not contain:

- `Area3D`
- `StaticBody3D`
- `RigidBody3D`
- `CollisionShape3D`
- imported collision meshes

Cup visuals may still use `red_solo_cup.glb`.

The simulation ball may remain a `RigidBody3D` with its own sphere collider so it can still interact with the table and floor. Table and floor physics colliders may remain because the no-collider requirement applies to cups.

Do not use `red_solo_cup_collision.glb` in the rewritten shot tester.

## Bounce Response

When a cup sensor emits a collision event:

1. Read the nearest surface normal from the collision snapshot.
2. Convert the normal from cup-local to world space.
3. Reflect the ball velocity using a restitution-based bounce:

```gdscript
var normal_speed := velocity.dot(normal)
var reflected_velocity := velocity - normal * ((1.0 + restitution) * normal_speed)
```

4. Apply tangential damping/friction separately.
5. Move the ball to a non-penetrating clear position using the nearest point plus normal times ball radius.
6. Wake the ball.
7. Record a synthetic contact on the ball so contact summaries and later House Rules work can observe the event.

The response should be deterministic for the same ball transform, previous transform, velocity, radius, and cup parameters.

## First-Pass Scoring Policy

Do not implement nuanced scoring in the first pass.

For this rewrite pass:

- Any frustum intersection is a collision event.
- Any collision event bounces the ball.
- The tester logs the event.
- No special capture behavior is required yet.

Scoring can be added back after the mathematical bounce model is stable.

## New Scene Structure

The rebuilt `res://scenes/editor/shot_tester.tscn` should contain:

- root `ShotTesterApp`
- camera
- world light/environment
- table and floor physics
- `SimulationBall`
- `AimIndicator`
- `CupRackRoot`
- `TestingUi`

Cup instances should be generated by code at runtime. Each generated cup should include:

- visual cup model
- per-cup mathematical sensor script
- cup metadata such as `cup_index`, `owner_slot`, and `owner_side`

## Validation

After implementation, run:

- `.\tools\validate_codex.cmd`

Also verify:

- `res://scenes/editor/shot_tester.tscn` opens or launches headlessly.
- The new shot tester scene contains no cup collider nodes.
- A launched ball triggers per-cup sensor events.
- Ball velocity changes after mathematical frustum intersection.
- `collision_tester` and `shot_tester` agree for matching frustum dimensions and ball positions.
- Practice mode, Classic Match, Online Arena, and existing multiplayer scenes are not modified by this editor-only rewrite.

## Later Promotion Path

Once the rewritten shot tester feels correct:

1. Add crossing-aware scoring and rim behavior.
2. Feed collision/contact events into House Rules contact summaries.
3. Promote the shared helper into `CupTarget` or a replacement runtime cup sensor.
4. Keep match authority and score mutation in match-state scripts.
5. Verify on Quest hardware before replacing gameplay cup behavior broadly.
