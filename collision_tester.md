# Collision Tester Agent Guide

## Purpose

`Collision_Tester` is an editor-only Godot scene for tuning custom cup collision math before that behavior is promoted into the shared gameplay systems. Use it to inspect one cup, one ball, and a configurable conic frustum volume without relying on physics colliders.

The scene should stay small, visual, and fast to iterate on. It is a proving ground for cup scoring/collision geometry, not a replacement for Practice, Classic Match, Computer Classic Match, or Online Arena.

## Current Files

- `res://scenes/editor/collision_tester.tscn`
  Contains one visual cup model, one visual ball model, one generated frustum visualization mesh, a camera, lighting, and a 2D editor UI.
- `res://scripts/editor/collision_tester.gd`
  Builds the conic frustum mesh, manages UI controls, calculates ball/frustum intersection, colors the ball, and creates draggable axis gizmos.
- `res://shaders/conic_frustum_visual.gdshader`
  Transparent grid shader used to visualize the generated frustum volume.

## Current Functionality

- The scene is guarded from exported builds with `OS.has_feature("template")`.
- The cup uses the visual-only `red_solo_cup.glb` model.
- The ball is a `MeshInstance3D` sphere, not a `RigidBody3D`.
- The tester scene should not contain `CollisionShape3D`, `Area3D`, `RigidBody3D`, `StaticBody3D`, or other physics collision nodes.
- The conic frustum is generated mathematically from:
  - `bottom_y`
  - `rim_y`
  - `bottom_radius`
  - `rim_radius`
  - `radial_segments`
- The frustum visualization can be toggled from the UI or with the `V` key.
- The ball radius is configurable and the visible sphere is resized to match.
- Ball/frustum intersection is calculated from the ball center point plus `ball_radius`.
- The current intersection test reduces the rotationally symmetric frustum to a 2D radial/Y cross-section and compares the sphere radius against the closest point on the closed frustum profile.
- The ball turns green when it intersects the frustum and red when it does not.
- The ball turns blue for `top_inner` diagnostic overlap and yellow for `top_rim_band` overlap.
- Rim-band size is adjustable with the `Rim Band Scale` UI field, interpreted as a multiple of the current ball radius.
- The tester reports a diagnostic classification:
  - `outside`
  - `side_wall`
  - `inside_volume`
  - `top_inner`
  - `top_rim_band`
  - `bottom_cap`
- A toggleable normal vector visualization draws a fixed-length visual-only arrow from the ball center along the nearest-surface normal.
- The normal vector readout shows nearest local point, local direction, and signed center distance.
- Runtime axis gizmos are parented to the ball:
  - Red axis: local/world X.
  - Green axis: local/world Y.
  - Blue axis: local/world Z.
- Mouse dragging is implemented without colliders. The script projects each axis to screen space for picking, then moves the ball by solving the closest point between the camera ray and the selected world axis.
- UI readouts show frustum dimensions, intersection status, nearest feature, clearance, and ball local position.
- `Reset Defaults` should restore the values loaded from the scene file, including any tuned frustum values.

## Usage

1. Open or run `res://scenes/editor/collision_tester.tscn`.
2. Use the left-side UI to tune frustum dimensions and ball radius.
3. Click and hold a colored axis attached to the ball.
4. Drag to move the ball along that axis.
5. Watch the ball color:
   - Green means the ball intersects the current frustum volume.
   - Red means the ball does not intersect.
6. Use the status readouts to inspect the ball's local position, nearest frustum feature, and clearance.
7. Press `V` to toggle the frustum visualization.

## Implementation Rules

- Keep this scene editor-only.
- Preserve the no-colliders constraint in the tester scene.
- Do not add physics bodies just to make gizmo picking easier; use camera-ray and screen-space math.
- Keep all geometry calculations in local cup/tester space.
- Keep the current tuned scene values intact unless the user explicitly asks to change them.
- Prefer adding small, named math helpers over burying collision formulas in UI code.
- When adding logic intended for future gameplay use, keep it portable enough to move into a shared helper later.
- Do not wire experimental tester logic directly into Practice, Classic Match, Online Arena, or `CupTarget` until the model has been tuned and explicitly promoted.
- Separate diagnostic visualization from collision decisions. Runtime gameplay should be able to run the math without drawing vectors, bands, labels, or debug meshes.
- Keep formulas allocation-free where practical. Future Quest runtime code may evaluate cup/ball interactions every physics tick, so avoid per-frame mesh rebuilds, dictionaries, string classifications, or temporary arrays in the eventual shared helper.
- Treat the tester as a source of tuned parameters and expected behavior, not as final gameplay architecture. The final implementation should have a compact math API that can be called from `CupTarget` and multiplayer-aware match code.
- Preserve deterministic behavior. Given the same ball transform, previous transform, velocity, radius, and cup parameters, classification should return the same result in editor, desktop validation, and Quest builds.

## Agent Work Protocol

When modifying `Collision_Tester`, Codex agents should:

1. Read this file, `res://scripts/editor/collision_tester.gd`, and `res://scenes/editor/collision_tester.tscn` before editing.
2. Identify whether the task is diagnostic-only, gameplay-math preparation, or project-wide rollout.
3. Keep diagnostic-only changes inside the editor scene/script.
4. Keep reusable collision math in functions that can later move into a shared helper with minimal UI dependencies.
5. After edits, run the validation checklist at the end of this file and report anything that could not be verified locally.

## Milestone Goals

### 1. Normal Vector Visualization

Add a visible vector from the ball center along the nearest-surface normal.

First pass status: implemented in `res://scripts/editor/collision_tester.gd`.

Expected behavior:

- When the ball is outside the frustum, draw the vector from the ball center along the direction from the nearest frustum point through the ball center.
- When the ball intersects or is inside the frustum, still show the relevant normal/contact direction where useful for tuning.
- Use a fixed visual length matching the axis gizmo arrows so the vector remains readable near and far from the surface.
- Show or hide the normal vector from the UI.
- Include readouts for:
  - nearest point
  - normal direction
  - signed or unsigned distance
  - penetration/clearance relative to ball radius

Implementation notes:

- Reuse the existing closest cross-section calculation as the first pass.
- Convert the nearest radial/Y cross-section point back into local 3D using the ball center's radial direction.
- If the ball center lies on the frustum axis, choose a stable fallback radial direction.
- Use a generated mesh, `ImmediateMesh`, or small `MeshInstance3D` arrow. Keep it visual-only.
- Do not rebuild the vector mesh every frame if only endpoints changed. Prefer updating a small node transform/scale or a preallocated `ImmediateMesh`.
- For future gameplay use, expose the nearest-point and normal math separately from the visualization code.

### 2. Top And Rim Intersection Classification

Add detection for balls intersecting the top opening of the frustum and differentiate inner-opening overlap from overlap with a narrow concentric rim band around the cup's outer top edge.

First pass status: implemented in `res://scripts/editor/collision_tester.gd`.

Expected behavior:

- Ball turns blue when it overlaps the inner top opening without touching the rim band.
- Ball turns yellow when it overlaps the rim band.
- Ball remains green for non-rim volume intersections and red when fully outside.
- The rim band size is adjustable in the UI.
- The UI shows the current classification separately from the boolean `intersects` value.

Recommended diagnostic classifications:

- `outside`
- `side_wall`
- `inside_volume`
- `top_inner`
- `top_rim_band`
- `bottom_cap`

Classification guidance:

- Use `rim_y` and `rim_radius` as the top opening reference.
- Define the rim band as an exported parameter. Current first pass uses `rim_band_ball_radius_scale`.
- `top_inner` means the ball sphere overlaps the top plane inside the rim-band threshold. This is a diagnostic state, not an immediate score.
- `top_rim_band` means the ball sphere overlaps the annular band near `rim_radius`. This is the future bounce/deflection candidate.
- Side-wall classification should still work away from the top opening.
- Classification should be stable near boundaries. Add small epsilons or hysteresis only if repeated dragging shows flicker.

First-pass limitations:

- Classification is based on the current static sphere position, not previous/current motion or velocity.
- This is enough for the editor diagnostic pass, but gameplay rollout still needs crossing-aware logic so fast shots do not skip top/rim/capture events.
- Rim-band classification intentionally takes priority over top-inner classification at the boundary.

Future gameplay behavior:

When this collision model is promoted, balls that overlap only the inner top opening should not reflect from the top plane. They should continue until one of these outcomes occurs:

1. The ball intersects the rim band. Calculate a rim contact normal and apply rim deflection.
2. The ball center crosses below `rim_y` while inside the scoring opening. Count this as a score and animate capture into the cup.
3. The ball intersects the side wall from the inside after entering through the opening. Treat this as an inside-wall/capture case unless tuning proves a rebound feels better.

Edge cases to preserve:

- A ball may hit the rim, deflect, and remain over or partly inside the cup. It must still be eligible for later rim contacts.
- A ball that deflects from a rim should still score if its center later drops below `rim_y` inside the scoring opening.
- Do not allow a rim deflection to permanently mark a shot as missed while the ball remains physically near or inside the cup.
- Runtime scoring should use previous and current ball positions plus velocity, not only the instantaneous sphere overlap, so fast shots do not skip top/rim/capture decisions.

VR feasibility and performance notes:

- The final Quest path should use a cheap broad-phase before running cup math. The existing `CupTarget` interaction area is acceptable for gameplay; the tester itself should remain collider-free.
- Avoid debug colors, string classifications, and vector drawing in production code. Convert classifications to integer constants or enums in shared runtime helpers.
- Keep per-cup math small: one ball against a handful of nearby cups per physics frame is fine; checking every ball against every cup with allocation-heavy results is not.
- Rim response will need headset tuning. Desktop editor behavior can validate geometry, but not final throw feel.

### 3. Shared Custom Collision Rollout

After the tester model is tuned, promote the custom collision handling into the gameplay project as a cleanup pass that unifies duplicated collision logic.

Final target:

- Practice, Classic Match, Computer Classic Match, and Online Arena should use one shared cup collision/scoring model.
- The final gameplay implementation should be centralized enough that scene-specific boilerplate is removed rather than copied.
- Scoring and reset behavior must still flow through the existing match-state and House Rules resolution paths.
- Multiplayer authority must remain explicit. Shared match decisions should not be made inside local-only player or visual scripts.

Likely rollout path:

1. Extract the tuned frustum, rim, normal, and classification math into a shared helper script or resource.
2. Update `CupTarget` to use the shared math for score capture, side-wall handling, rim handling, and synthetic contact reporting.
3. Keep cosmetic visualization separate from gameplay state.
4. Remove duplicate cup collision boilerplate from editor and gameplay scenes after the shared helper is stable.
5. Keep a legacy fallback or debug toggle only as long as it is useful for verification.
6. Update editor tools to call the same shared helper rather than maintaining a parallel implementation.
7. Run local validation and then verify on Quest hardware before declaring the collision model complete.

Shared helper requirements:

- Input should be plain values: cup transform or inverse transform, frustum parameters, rim parameters, ball previous/current world position, ball radius, and ball velocity.
- Output should be compact and allocation-light for runtime: classification enum, nearest point, normal, signed distance or penetration, and suggested gameplay event.
- The helper must not depend on UI nodes, debug materials, `CanvasLayer`, editor-only state, or scene-specific child paths.
- `CupTarget` may own broad-phase tracking and capture animation, but collision classification should not be duplicated across scenes.
- Scoring authority should remain in match-state/resolver code. Collision helpers can report "capture candidate" or "rim contact"; they should not directly mutate score.

## Validation Checklist

Use these checks after changing the tester:

- `res://scenes/editor/collision_tester.tscn` launches in headless mode.
- `.\tools\validate_codex.cmd` passes.
- The tester scene/script still contain no physics collision nodes.
- The ball can be moved with X/Y/Z axis gizmos.
- The ball color updates immediately as it crosses the frustum boundary.
- The frustum values saved in the scene are preserved.
- Any newly added normal/rim visualization can be toggled without changing collision results.
- Top-inner and rim-band classifications remain stable while dragging the ball slowly across boundaries.

Use these checks before promoting tester logic into gameplay:

- Practice mode remains stable.
- Basic Classic Match remains stable.
- Computer Classic Match remains stable.
- Online Arena still keeps local-player input, remote-player representation, ball authority, and shared match decisions separate.
- House Rules contact summaries still receive meaningful wall/rim/score information through synthetic contacts or the shared collision path.
- Quest hardware testing confirms the tuned collision feels reliable in VR.
- Runtime profiling on Quest confirms the new math does not create avoidable allocations or frame spikes.

## Open Questions

- What exact width should define the rim band: a fixed meter value, a multiple of ball radius, or both?
- Should `top_inner` represent any overlap with the opening in the tester, while gameplay score capture requires a downward center crossing below `rim_y`?
- Should the normal vector show nearest-surface distance for all cases, or only active collision/penetration cases?
- Once promoted, should the shared collision helper live under `scripts/match/`, `scripts/collision/`, or remain owned by `CupTarget` with a smaller extracted math module?
- Should inside-wall contact after entry always capture, or should shallow inside-wall hits be allowed to rebound if that feels better in headset testing?
