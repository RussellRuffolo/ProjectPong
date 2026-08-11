# Fixed Convex Cup Collision And Contact Scoring Overhaul

## Purpose

Replace the current mathematical cup-frustum system with a small, self-contained Godot physics design focused only on cup collision, score detection, and score presentation.

The first pass uses:

- One fixed cup body with one very-low-poly convex truncated-cone collider.
- Native Godot/Jolt collision and bounce behavior for every non-scoring hit.
- Score detection from the ball's real contact point and contact normal on the convex cup collider.
- A short score-capture presentation that disables the ball collider and animates the ball to the cup bottom.
- Cup removal `0.1` seconds after the ball reaches the bottom.
- The existing centralized match, rack, and House Rules resolution paths.

No cup pickup, cup movement, dynamic cup simulation, thin trigger volume, mathematical frustum, custom bounce, or penetration correction belongs in this pass.

## Locked First-Pass Decisions

1. Cups never move and are never grabbable.
2. The cup collider is one solid convex truncated cone.
3. Native physics handles side, edge, and rejected top contacts.
4. A top-cap collision is a scoring candidate when its normal is nearly vertical and its contact point is inset from the cup edge by at least half the ball radius.
5. The maximum throw speed remains high. Scoring does not depend on a ball overlapping a thin `Area3D` for one physics tick.
6. Once match authority accepts the score, the ball collider is disabled and the ball is animated to the cup bottom.
7. The scored cup disappears `0.1` seconds after that animation finishes.

## Why Contact-Based Scoring

A thin `Area3D` disc can be skipped by a fast ball when the ball crosses the entire detection volume between physics ticks. Making the trigger thicker or raising the physics tick rate would work against the lightweight goal.

The solid convex cup already provides the reliable physical event we need. With continuous collision detection enabled on the ball, a centered shot contacts the convex hull's top cap. The contact provides:

- the cup that was hit;
- the contact point;
- the contact normal;
- the ball's incoming velocity; and
- the ball radius already represented by its sphere collider.

The top cap therefore acts as both the physical backstop and the scoring surface. Only accepted scores leave native physics; all rejected contacts use the ordinary bounce response.

## Godot Body Choice

Use a `StaticBody3D` for the first pass. It is the lightest and clearest body type for a cup that never moves.

Godot 4 does not require an old-style "kinematic" body for an immovable object. If cups later need authored transform motion without full rigid-body simulation, the scene can move to `AnimatableBody3D`. If cups later need to be knocked over or thrown, that is a separate milestone using `RigidBody3D` plus explicit multiplayer authority.

Do not add the cup to `grabbable`, and do not add cup-specific methods to `HandGrabber`.

## Target Cup Scene

Create one reusable scene, recommended as `res://scenes/gameplay/cup_target.tscn`:

```text
CupTarget (StaticBody3D, CupTarget script)
|- Visual (red_solo_cup.glb instance)
|- Liquid (optional cosmetic child)
`- CupCollision (CollisionShape3D)
   `- ConvexPolygonShape3D: solid low-poly truncated cone
```

There is no score `Area3D` and no interaction broad-phase volume.

Keep existing gameplay metadata on the `CupTarget` root:

- `cup_index`
- `owner_slot`
- `owner_side`
- `rack_row`
- `rack_column`
- `is_scored`

`CupRackBuilder` should instantiate this scene rather than assemble cup visuals and collision behavior in code.

## Convex Collider

Use an eight-sided solid truncated cone for the first pass:

- 8 vertices around the bottom ring.
- 8 vertices around the top ring.
- 16 points total in one `ConvexPolygonShape3D`.
- One generated convex hull with side faces, bottom cap, and top cap.

The shape is deliberately much simpler than the visual model. One convex shape has no seams between wall panels and is cheap for Jolt to collide against.

Begin with the dimensions already used by `CupTarget`, then align them with the visual in the editor:

| Property | Starting value |
| --- | ---: |
| Bottom Y | `0.006 m` |
| Top-cap Y | `0.058 m` |
| Bottom radius | `0.030 m` |
| Top radius | `0.046 m` |
| Side count | `8` |

Store the convex points in the scene or a `.tres` resource. Do not generate the shape at runtime and do not derive gameplay collision from `red_solo_cup.glb` at startup.

The top cap is intentionally solid. It creates the dependable native collision from which scoring is classified. A valid score transitions into the capture presentation before the native bounce becomes visible. A rejected hit simply bounces.

Do not use `red_solo_cup_collision.glb` for gameplay collision.

## Physics Material

Use a shared `PhysicsMaterial` on the cup body. Tune bounce and friction in the inspector rather than rewriting velocity in script.

The ball remains responsible for its own existing bounce, friction, gravity, and continuous collision detection. Keep its current high maximum throw speed.

No cup code may:

- reflect or replace ball velocity;
- move the ball out of penetration;
- calculate a frustum or torus response;
- apply a collision impulse; or
- override a rejected collision.

## Native Contact Reporting

Per-contact point and normal data should be read from the ball's `PhysicsDirectBodyState3D` during `ThrowableBall._integrate_forces(state)`. `body_entered` and `get_colliding_bodies()` identify bodies but do not provide all information required to distinguish the top cap from a side hit.

Keep this addition narrow:

1. Ignore contacts when no released shot is active or the ball is already captured.
2. Iterate the ball's reported contacts for the current physics step.
3. Keep only contacts whose collider is an active `CupTarget` in the current target rack.
4. Read the collider-side contact position, not the point on the ball sphere, and convert it to world space if the API returns it locally.
5. Convert the reported normal into one documented world-space convention.
6. Pass the world contact point, world contact normal, ball radius, and incoming velocity to the cup's score-classification method.
7. Latch at most one score candidate for the shot.
8. Defer the gameplay signal until the physics callback finishes; do not disable shapes or mutate match state inside `_integrate_forces()`.

Set the ball's `max_contacts_reported` high enough for clustered cup contacts. Begin at `16` and reduce only after stress testing proves a lower value cannot hide a valid top-cap contact.

The exact position and normal conventions returned by the Godot 4.7.1 direct body state must be verified once in the collision tester. In particular, the top-height and edge-clearance tests must use the contact point on the cup collider rather than the corresponding point on the ball. Normalize or flip the normal in one adapter before passing it to `CupTarget`; do not scatter contact-convention guesses through multiple scripts.

## Score Contact Classification

`CupTarget` should expose one small, pure classification method. It examines a real native collision snapshot and returns a score candidate without changing physics or match state.

Recommended interface:

```gdscript
func classify_score_contact(
	world_contact_point: Vector3,
	world_contact_normal: Vector3,
	world_ball_velocity: Vector3,
	ball_radius: float
) -> Dictionary
```

An empty dictionary means the collision is not a score. A valid result includes stable cup identity and useful diagnostics such as local contact point, local normal, edge clearance, and entry speed.

### Acceptance conditions

A contact is a scoring candidate only when all of the following are true:

1. The cup is active and not already scored.
2. The contact point is at the top-cap height within a small tolerance.
3. The contact normal is nearly parallel to the cup's local up axis.
4. The ball was moving downward into the cap before collision response.
5. The contact point is at least half a ball radius inward from the top edge.

Recommended calculations in cup-local space:

```gdscript
var local_point := to_local(world_contact_point)
var local_normal := (global_basis.inverse() * world_contact_normal).normalized()
var local_velocity := global_basis.inverse() * world_ball_velocity

var at_top_cap := absf(local_point.y - cup_top_y) <= top_height_tolerance
var is_vertical := absf(local_normal.dot(Vector3.UP)) >= minimum_vertical_normal_dot
var is_entering := local_velocity.y <= -minimum_entry_speed
var radial_distance := Vector2(local_point.x, local_point.z).length()
var edge_clearance := cup_top_radius - radial_distance
var is_inside_score_region := edge_clearance >= ball_radius * 0.5
```

Return a valid candidate only when every condition is true.

Use a dot-product threshold rather than exact equality for the vertical normal. Start around the equivalent of `15` degrees from vertical, then tighten it in the collision tester if side or bevel contacts are incorrectly accepted. The top-height test prevents the bottom cap from qualifying even if the contact-normal convention is reversed.

The half-ball-radius inset is the first-pass scoring rule requested here:

```text
radial contact distance <= cup top radius - (ball radius * 0.5)
```

Keep the multiplier exported so the tester can establish whether `0.5` is visually fair without changing the algorithm.

### Multiple contacts in one physics step

Never award two cups for one ball. Gather all valid cup candidates from the physics step and select one deterministically:

1. Prefer the candidate with the greatest edge clearance.
2. Break an exact tie with the lowest stable `cup_index`.

Latch the selected cup until the attempt is resolved or reset. Native contact ordering must not decide the score.

## Authoritative Score Flow

The cup and ball detect a physical candidate; they do not increment the score directly.

Recommended flow:

1. The released ball finds and latches the best valid top-cap contact.
2. The ball emits a deferred `score_contact_detected(ball, cup, snapshot)` signal.
3. The active mode verifies that the cup belongs to the target rack and remains available.
4. `ShotScoreTracker` immediately confirms the contact-latched candidate. A settle delay is not used.
5. The mode builds the existing `ShotContext` and resolves it through `HouseRulesResolver`.
6. Match authority applies the resulting `ShotOutcome` and marks the appropriate cup indices scored.
7. The accepted physical scoring cup begins the ball capture presentation.
8. Cup removal begins only after capture completion.

This preserves the shared Practice, Classic Match, Computer Classic Match, and Online Arena score architecture. `CupTarget` must never mutate a score, turn, winner, or House Rules state.

If a House Rule invalidates an otherwise physical make, match authority decides whether the capture presentation still plays. Keep that policy in the resolver/mode handoff rather than inside collision classification.

## Ball Capture Presentation

Once match authority accepts the score, temporarily remove the ball from physics and animate it to the cup bottom.

Recommended sequence:

1. Save enough of the ball's collision and physics state for the existing reset path.
2. Zero linear and angular velocity.
3. Disable the ball's `CollisionShape3D` using a deferred property change.
4. Freeze the ball and make it non-grabbable.
5. Animate the ball root from its current transform to the cup's local bottom-center target.
6. Emit `score_capture_finished(ball, cup)` when the animation reaches the target.
7. Keep the ball frozen and collision-disabled until the normal shot-reset path relocates it.
8. On reset, restore the collision shape, physics state, CCD setting, and grabbable state.

The recommended target is:

```gdscript
var target_world_position := cup.to_global(
	Vector3(0.0, cup_bottom_y + ball_radius, 0.0)
)
```

Use the existing `0.18` second capture duration as a starting point, exposed as one presentation tuning value. The animation may ease smoothly but must not feed back into collision, scoring, or House Rules.

Do not restore ball collision while it is sitting inside the solid convex cup. The normal reset should occur immediately after the short post-capture removal delay; otherwise the restored ball would be expelled from the solid hull or fall when the cup disappears.

## Cup Removal Timing

The scored physical cup disappears exactly `0.1` seconds after the ball reaches the bottom of that cup.

The timer begins from `score_capture_finished`, not from initial score contact and not from match resolution:

```text
top-cap contact
-> authoritative score accepted
-> capture animation
-> ball reaches cup bottom
-> wait 0.1 seconds
-> remove/hide scored cup
-> reset ball through the existing mode flow
```

Update `CupRemovalQueue` or its caller so it can be triggered by capture completion. Avoid independent mode timers that can drift from the animation.

For House Rules that remove additional cups, only the physical scoring cup waits for ball capture. Extra cups may use the existing removal presentation because the ball is not animated into them.

## Native Contacts And House Rules

The cup is a real `StaticBody3D`, so the existing ball contact monitor can report ordinary cup hits through `get_colliding_bodies()`. Keep identity metadata on the cup root so `ShotContactTracker` continues to classify native contacts.

Once the new cup is used everywhere, remove synthetic cup-contact production and draining:

- Remove `_record_synthetic_cup_contact()` from `CupTarget`.
- Remove math-driven calls to `ThrowableBall.record_synthetic_contact()`.
- Remove the synthetic queue from `ThrowableBall` if no other feature uses it.
- Remove synthetic draining from `ShotContactTracker` if no other surface uses it.

A direct top-cap score still produces a native contact with the scored cup. Existing Bouncing logic already excludes contact with the final scored cup from its bonus condition.

## Multiplayer Authority

Fixed cups require no transform replication or grab authority.

For Online Arena:

- Only the active ball/match authority inspects and accepts scoring contacts.
- Peers do not independently infer a score from their local physics contacts.
- The authority publishes the resolved scored cup indices through the existing match snapshot.
- The authoritative capture start and cup index should be included in replicated match presentation state so both peers animate the same ball/cup result.
- The authoritative capture-complete/removal timing drives logical removal. Cosmetic interpolation on peers must not decide state.
- Cup pickup and cup transform replication remain explicitly out of scope.

Keep Photon-facing changes behind `PhotonSession` and `NetworkMatchState`, and update `docs/multiplayer_photon_roadmap.md` before changing replicated match fields.

## File-Level Changes

### `res://scenes/gameplay/cup_target.tscn`

Add the reusable fixed cup scene with its visual, optional liquid, one convex collision shape, shared material, and short `CupTarget` script.

### `res://scripts/cup_target.gd`

Rewrite as a short `StaticBody3D` script responsible for:

- active/scored state;
- cup identity helpers;
- top-cap score-contact classification;
- visual/liquid visibility; and
- capture target position.

Remove:

- score and interaction `Area3D` construction;
- frustum and torus calculations;
- custom velocity reflection;
- positional correction;
- per-frame ball tracking;
- direct ball capture logic;
- runtime mesh-to-trimesh conversion;
- synthetic contacts; and
- legacy collision-model toggles.

### `res://scripts/throwable_ball.gd`

Keep ball material, gravity, CCD, grabbing, release, and reset behavior. Add only:

- narrow native-contact inspection in `_integrate_forces()`;
- deterministic score-candidate latching;
- a deferred score-contact signal;
- score-capture start/animation/finish behavior; and
- complete restoration through the existing reset path.

Delete the old synthetic-contact queue after all callers are gone. Replace the old math-capture entry points with one authoritative `begin_score_capture(cup)` method.

### `res://scripts/match/cup_collision_model.gd`

Delete after all runtime and editor references have been removed. It must not remain as a second gameplay collision truth.

### `res://scripts/match/cup_rack_builder.gd`

Instantiate the reusable cup scene and assign stable metadata. Do not build visual or collision children procedurally.

### `res://scripts/match/rack_state.gd`

Replace resting-volume lookup with validation of the ball's latched contact candidate while preserving stable cup indices and authoritative scored state.

### `res://scripts/match/shot_score_tracker.gd`

Treat a valid contact latch as immediately confirmed. Remove resting/settle and capture-specific scoring shortcuts from this path.

### `res://scripts/match/cup_removal_queue.gd`

Support starting the physical scoring cup's `0.1` second removal delay from ball capture completion. Preserve ordinary delayed removal for additional House Rules cups.

### `res://scripts/house_rules/shot_contact_tracker.gd`

Continue using native colliding bodies for cup contacts. Remove synthetic cup handling when migration is complete.

### Editor testers and existing plans

Update the shot tester to use the exact same cup scene and ball contact path as gameplay. Mark `cup_target_rework.md` and `shot_tester_rewrite_plan.md` as superseded by this document rather than leaving math-frustum collision presented as the active direction.

## Rollout Plan

### Phase 1: Prove one cup in the shot tester

1. Create the fixed reusable cup scene and 16-point convex resource.
2. Reuse the gameplay ball with CCD and native contact reporting.
3. Log contact point, contact normal, top-height delta, edge clearance, and decision.
4. Tune only the normal threshold, top-height tolerance, and edge-clearance multiplier.
5. Prove high-speed collision and scoring before integrating match state.

### Phase 2: Add capture and removal presentation

1. Add authoritative score-capture start to `ThrowableBall`.
2. Disable/freeze the ball and animate it to the cup bottom.
3. Emit capture completion.
4. Remove the scored cup after `0.1` seconds.
5. Restore the ball only through the normal shot-reset path.

### Phase 3: Replace local gameplay racks

1. Change `CupRackBuilder` to instantiate the fixed cup scene.
2. Route the ball's latched candidate through shared score resolution.
3. Verify Practice, Classic Match, and Computer Classic Match.
4. Confirm Bouncing and Chain Lightning receive native contacts.

### Phase 4: Delete obsolete runtime paths

1. Remove math collision and interaction areas from `CupTarget`.
2. Remove `cup_collision_model.gd` after reference checks pass.
3. Remove synthetic cup contacts.
4. Remove the legacy imported collision model from runtime references.
5. Mark the older math-overhaul documents superseded.

### Phase 5: Online Arena

1. Keep cups fixed and non-grabbable.
2. Resolve contact scoring only on authority.
3. Replicate the accepted cup and capture/removal presentation state.
4. Verify identical score and removal timing on two Quest headsets.

## Validation Matrix

### Native collision

- Fire at every side face, every face boundary, the top edge, and the top center.
- Repeat at shallow and steep angles up to the supported maximum throw speed.
- Verify zero pass-throughs in an automated high-volume run with ball CCD enabled.
- Verify no panel seams or wedging because the cup has one convex shape.
- Verify rejected contacts use only native bounce and friction.
- Verify the cup never moves, tips, or becomes grabbable.

### Contact classification

- A centered downward top-cap hit scores exactly once.
- A top hit with at least `0.5 * ball_radius` edge clearance scores.
- A hit closer to the edge than that threshold does not score.
- A side-face normal does not score.
- A bottom-cap contact does not score.
- Upward or non-entering motion does not score.
- Multiple contacts in one physics step resolve deterministically to one cup.
- A stale latch cannot survive ball reset.
- Logging confirms the selected contact normal convention on Jolt.

### Capture and removal

- An accepted score disables the ball collider before a visible bounce develops.
- The ball freezes and animates smoothly from contact position to cup bottom.
- The animation does not create physics contacts or extra House Rules events.
- The cup remains visible during capture.
- The cup disappears `0.1` seconds after capture completion.
- The ball remains collision-disabled until reset.
- Reset restores collision, CCD, physics, and grabbability exactly once.
- Additional House Rules removals do not wait for unrelated capture animations.

### Regression

- `\.\tools\validate_codex.cmd` succeeds.
- Practice scores, captures, removes the correct cup, and resets the ball.
- Classic Match advances turns and applies the authoritative score.
- Computer Classic Match automatic validation keeps model score and cup state consistent.
- Bouncing and Chain Lightning observe distinct native cup contacts.
- Online Arena room creation/join remains stable.
- Authoritative score, capture, and removal agree on two Quest headsets.

## Completion Criteria

The overhaul is complete when:

- Every gameplay cup uses one fixed 16-point convex collider.
- Cups contain no grab, movement, or rigid-body simulation behavior.
- Valid scores come from real native top-cap contact data, not an `Area3D` crossing.
- The half-ball-radius edge rule is tested and documented with final dimensions.
- Rejected contacts use only Godot/Jolt collision response.
- Accepted scores disable the ball collider and animate the ball to the cup bottom.
- The physical scoring cup disappears `0.1` seconds after capture completion.
- Match authority resolves each contact candidate exactly once through the shared outcome path.
- Mathematical frustum, torus, custom reflection, penetration correction, and synthetic cup-contact code are removed.
- Maximum-speed automated tests produce zero cup pass-throughs and zero missed valid top-cap scores for the agreed test count.
- Practice, Classic Match, Computer Classic Match, and Online Arena retain their established centralized score and House Rules behavior.
- Quest hardware verification is complete before the overhaul is considered release-ready.

## Remaining Tuning Values

These are implementation tuning values, not unresolved architecture decisions:

- `minimum_vertical_normal_dot`
- `top_height_tolerance`
- `minimum_entry_speed`
- `score_edge_clearance_ball_radius_multiplier`, initially `0.5`
- `score_capture_seconds`, initially `0.18`
- ball `max_contacts_reported`, initially `16`

Record the final values and maximum-speed test results in this document after the tester pass.
