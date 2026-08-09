# Cup Target Math-Volume Rework

## Goal

Replace the current seam-prone cup wall collision with a Quest-friendly math-volume interaction model. The current cup collision source is split into twelve wall panels plus a bottom. Each panel becomes a separate static physics body, which lets the ball wedge between side-panel edges. The new implementation should keep Practice, Classic Match, Computer Classic Match, and Online Arena using the existing shared score-resolution flow while making the core cup interaction deterministic and physically believable.

## Architecture

`CupTarget` remains the owner of per-cup interaction because it already owns cup visuals, score detection, liquid presentation, and scored state. Match modes should continue to ask `RackState.find_resting_cup(ball)` and then let `ShotScoreTracker` resolve the score through the existing shared path.

The new cup model is:

- A cheap `Area3D` broad-phase interaction volume around each cup.
- A math frustum for side-wall detection and deflection.
- A math torus for rim detection and deflection.
- A score-capture state that removes ball physics and animates the ball to the cup bottom.
- A legacy mesh-collision toggle kept as an escape hatch while tuning.
- Synthetic cup-contact events so House Rules keep receiving cup/rim/wall contacts even when no physical cup wall collider is involved.

The math sensor should influence ball motion, but final scoring remains centralized in the existing match helpers and resolver path.

## CupTarget Tuning

Add exports for:

- `math_sensor_enabled`
- `legacy_mesh_collision_enabled`
- `cup_bottom_y`
- `cup_rim_y`
- `cup_bottom_radius`
- `cup_rim_radius`
- `cup_inner_score_radius`
- `rim_tube_radius`
- `interaction_radius_margin`
- `interaction_height_margin`
- `min_score_downward_speed`
- `rim_band_ball_radius_scale`
- `side_deflection_bounce`
- `side_deflection_tangent_scale`
- `rim_deflection_bounce`
- `rim_deflection_tangent_scale`
- `rim_top_radial_normal_scale`
- `rim_top_upward_normal_scale`
- `capture_animation_seconds`

Defaults should match the current cup scale: ball radius is about `0.02`, rim center is about `0.058`, and existing score/resting radii are around `0.032` and `0.028`.

## Broad-Phase Sensor

Create an `InteractionArea` with a `CylinderShape3D`. The radius is:

```gdscript
cup_rim_radius + ball_radius + interaction_radius_margin
```

The height covers the cup from bottom to rim plus a small margin. This keeps per-frame math limited to balls currently near a cup. `CupTarget` should only run `_physics_process()` while there is at least one tracked interaction body.

## Top Crossing And Scoring

Store the previous local-space ball center for each tracked ball. A top-plane hit occurs when the previous center was above `cup_rim_y`, the current center is at or below `cup_rim_y`, and the ball has enough downward velocity.

Interpolate the crossing point at the rim plane. If the ball center crosses well inside the rim, or is later entirely below the rim center height while still inside the score radius, enter score-capture state immediately. Capture should zero the ball velocity, suspend its collision/physics participation, and let `ShotScoreTracker` confirm the score immediately through the existing shared resolver path.

## Rim Torus

If the ball center is within half a ball radius of the rim edge during a top crossing, treat it as a rim hit:

```gdscript
abs(crossing_radius - cup_rim_radius) <= ball_radius * rim_band_ball_radius_scale
```

Compute the nearest point on the torus centerline at the cup rim radius, then use that to classify the hit. Top rim hits should use a wider, flatter, upward-biased normal so balls have a higher chance of popping generally upward instead of being pushed sideways through the virtual side wall.

## Frustum Side Deflection

Represent the side wall as a conic frustum:

```gdscript
var t := clampf((p.y - cup_bottom_y) / (cup_rim_y - cup_bottom_y), 0.0, 1.0)
var wall_radius := lerpf(cup_bottom_radius, cup_rim_radius, t)
var signed_distance := Vector2(p.x, p.z).length() - wall_radius
```

Use the gradient of the frustum surface as the normal. When the ball center is within one radius of the wall and its velocity is moving into the wall, rewrite velocity into normal and tangent components. The tangent component is damped, and the normal component is bounced away. Apply a small positional correction so the ball cannot remain embedded in the virtual wall.

## Capture State

Captured balls should stop being simulated by physics. This state should:

- Zero linear and angular velocity.
- Suspend ball collision layers/masks and freeze the rigid body.
- Report as a confirmed score immediately.
- Animate the visible ball from its captured position to `cup_bottom_y + ball_radius`.
- Restore normal ball physics on the existing reset/grab paths.

`is_ball_resting_inside()` should return true for captured balls immediately, even before the visual animation reaches the bottom. The animation is presentation; the score decision has already crossed the geometric threshold.

## House Rules Contacts

Because math-only wall and rim hits do not necessarily appear in `RigidBody3D.get_colliding_bodies()`, the ball needs a small synthetic contact queue. `CupTarget` records synthetic cup contacts when side or rim deflection occurs. `ShotContactTracker` drains those events during active shot tracking and records them into the existing `ShotContactSummary`.

This preserves Bouncing and Chain Lightning behavior without requiring fake wall bodies.

## Rollout

1. Add a shared ball-radius helper to `ShotPhysics`.
2. Add synthetic contact queue methods to `ThrowableBall`.
3. Update `ShotContactTracker` to merge synthetic contacts with physics contacts.
4. Implement `CupTarget` math sensor, rim torus deflection, frustum side deflection, and capture state.
5. Keep the legacy mesh collider disabled by default but available for debugging.
6. Run local validation and then tune on Quest hardware.

## Risks

- Rim feel will need headset tuning because tiny velocity differences are noticeable in VR.
- Math-driven contacts must remain authoritative only where the active match authority owns shot resolution.
- Capture should confirm through `ShotScoreTracker`, not by mutating mode score directly, so House Rules and multiplayer state stay centralized.
- If the interaction area is too small, fast shots may miss math handling. If it is too large, more cups run math per frame. Start conservative and tune.
