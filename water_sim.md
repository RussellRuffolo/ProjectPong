# Red Cup Water Sim Plan

## Goal

Add a simple Half-Life: Alyx-inspired liquid visual to the red cups. The liquid should look like blue fluid resting inside each cup and should visibly respond when a player tips, rotates, or jostles a cup. This should be a shader-based visual effect, not a gameplay physics simulation.

The first version should prioritize a convincing Quest-friendly illusion:

- The water surface stays approximately level with world gravity while the cup tilts.
- The visible fill volume clips against that level surface.
- Small waves, ripples, and slosh lag make the water feel alive.
- The effect remains cosmetic and does not drive scoring, ball collision, or match state.

## Design Constraints

- Target Godot 4.7.1 and Meta Quest 2/3.
- Keep the implementation cheap enough for up to 20 cups in Classic Match and Online Arena.
- Avoid CPU particle simulation, fluid physics, or per-frame mesh rebuilding.
- Do not add network traffic for liquid state. Remote clients should derive the same visual from replicated cup transforms.
- Keep all gameplay behavior in the existing cup, rack, score, and House Rules systems.
- Blue liquid visuals should be easy to disable for performance testing or comfort tuning.

## Proposed Technique

Use a shader-based fake fluid made from two child meshes inside each `CupTarget`:

1. `LiquidVolume`
   - A low-poly cylinder or tapered cup-interior mesh.
   - Uses a shader that discards fragments above a liquid plane.
   - Provides blue transparent body color, fresnel, and subtle depth tint.

2. `LiquidSurface`
   - A small circular disk or shallow cap mesh.
   - Rotates or deforms so its normal follows world up in cup-local space.
   - Uses a shader with animated normal noise and a subtle rim highlight.

The core trick is to compute the gravity-up vector in the cup's local space every frame:

```gdscript
var gravity_up_local := cup.global_transform.basis.inverse() * Vector3.UP
```

That vector becomes a shader uniform. The shader treats it as the liquid plane normal, so when the cup tilts, the water appears to remain level rather than glued to the cup.

## Runtime Components

### `res://scripts/cup_liquid_visual.gd`

Attach this script to a `Node3D` child under each `CupTarget`.

Responsibilities:

- Cache the parent cup transform.
- Smooth cup angular velocity into a slosh offset.
- Compute `liquid_normal_local` from world up.
- Compute a damped `liquid_plane_offset` from fill amount and slosh.
- Pass uniforms to the volume and surface shader materials.
- Hide or reset the liquid when the cup is marked scored or removed.

Suggested exported properties:

- `fill_ratio := 0.38`
- `liquid_radius := 0.036`
- `liquid_height := 0.075`
- `sloshing_strength := 0.012`
- `sloshing_damping := 8.0`
- `wave_strength := 0.004`
- `wave_speed := 1.4`
- `enabled_on_quest := true`

### `res://shaders/cup_liquid_volume.gdshader`

Responsibilities:

- Render only the portion of the interior mesh below the shader liquid plane.
- Tint the volume translucent blue.
- Add mild fresnel on grazing angles.
- Fade near the upper plane so the clipped edge is less harsh.
- Avoid expensive screen-space refraction in the first pass.

Important uniforms:

- `uniform vec3 liquid_normal_local;`
- `uniform float liquid_plane_offset;`
- `uniform vec4 liquid_color;`
- `uniform float edge_softness;`
- `uniform float time_offset;`

### `res://shaders/cup_liquid_surface.gdshader`

Responsibilities:

- Draw the visible top surface.
- Use procedural noise or sine waves for a cheap ripple.
- Bias the surface normal toward `liquid_normal_local`.
- Add a brighter rim/foam line where the surface meets the cup.
- Keep alpha and specular restrained for mobile VR readability.

Important uniforms:

- `uniform vec3 liquid_normal_local;`
- `uniform float liquid_plane_offset;`
- `uniform float wave_strength;`
- `uniform float wave_speed;`
- `uniform vec4 surface_color;`

## Integration Points

### `res://scripts/cup_target.gd`

Add optional exports:

- `@export var liquid_enabled := true`
- `@export var liquid_scene: PackedScene`
- `@export_range(0.0, 1.0, 0.01) var liquid_fill_ratio := 0.38`

Then instantiate the liquid child in `_ready()` after `_add_visual()` and before or after `_add_collision()`:

```gdscript
func _ready() -> void:
	_add_visual()
	_add_liquid_visual()
	_add_collision()
	_add_score_area()
```

The liquid child should not add collision shapes or areas.

### Cup Scenes and Rack Builder

The project currently builds cups through `CupRackBuilder.build_triangular_rack()` using `CupTargetScript.new()`, then assigns `visual_scene`, `collision_scene`, and cup metadata.

Keep that path intact. The first implementation can let `CupTarget` instantiate a default liquid scene internally. If per-arena liquid styles are needed later, extend the rack builder config with optional cosmetic fields such as:

- `liquid_enabled`
- `liquid_fill_ratio`
- `liquid_color`
- `liquid_scene`

### Match Modes

Practice, Classic Match, and Online Arena should not need gameplay changes. They already mark and remove cups through `CupTarget.mark_scored()` and `CupTarget.remove_from_game()`. The liquid visual should simply disappear with the cup node.

For multiplayer, do not replicate liquid wave state. Replicate cup transforms and scored cup state as usual; every client can compute local liquid motion from the visible transform.

## Visual Behavior

### Cup At Rest

- The fluid sits near the lower third of the red cup.
- Top surface is flat, blue, and faintly glossy.
- Volume tint is visible through the cup opening, not through the opaque red cup wall unless the model later gains translucent plastic.

### Cup Tipping

- The liquid plane remains level relative to world up.
- The clipped volume rises on the low side of the cup and lowers on the high side.
- A damped slosh offset trails the cup motion by a few frames.
- Small ripples become stronger during quick rotation and fade at rest.

### Cup Removed

- No spill simulation in the first version.
- When a cup is scored and removed, its liquid disappears with it.
- Optional later polish: a tiny blue splash decal or particle burst triggered as cosmetic-only VFX.

## Shader Plane Model

In the volume shader, use local vertex position against a plane:

```glsl
float plane_distance = dot(VERTEX, liquid_normal_local) - liquid_plane_offset;
if (plane_distance > 0.0) {
	discard;
}
```

For a cup standing upright, `liquid_normal_local` is close to `(0, 1, 0)`, so the plane behaves like a normal horizontal fill height. When the cup tilts, the normal changes in cup space and the clipped water line tilts through the cup volume.

The surface mesh can either:

- Stay as a disk and let the vertex shader project points onto the same plane, or
- Be rotated by `cup_liquid_visual.gd` so its local Y axis aligns with `liquid_normal_local`.

Prefer shader projection first so the effect remains mostly material-driven and does not require per-frame transform gymnastics.

## Quest Performance Notes

- Use simple cylinder/disk meshes with low segment counts, around 16 to 24 radial segments.
- Prefer opaque or alpha-scissor styling if transparent sorting becomes noisy in VR.
- Avoid screen-space refraction, high-frequency noise, and multiple texture lookups.
- Use one shared `ShaderMaterial` resource duplicated per cup only when per-cup uniforms are required.
- Consider updating slosh uniforms at 30 Hz if 20 cups become expensive.
- Add a global project setting or debug toggle to disable cup liquid for profiling.

## Implementation Phases

### Phase 1: Static Shader Prototype

- Add `cup_liquid_visual.gd`.
- Add volume and surface shader files.
- Add a simple generated `cup_liquid.tscn` with two mesh children.
- Instantiate the liquid child from `CupTarget`.
- Verify all cups show blue liquid in Practice mode.

### Phase 2: Tilt Response

- Compute `liquid_normal_local` from the cup transform.
- Feed the normal and fill offset into both shader materials.
- Rotate or shader-project the surface so it visually stays level.
- Test by rotating a cup in the editor and during VR hand interaction once cup tipping/grabbing is available.

### Phase 3: Slosh and Ripple

- Track previous cup orientation and approximate angular velocity.
- Add a damped slosh vector in cup-local X/Z.
- Increase wave amplitude briefly after quick cup movement.
- Clamp slosh so the water remains contained inside the cup.

### Phase 4: Mode and Multiplayer Validation

- Confirm Practice, Classic Match, and Online Arena still build cup racks normally.
- Confirm scoring and cup removal are unchanged.
- Confirm remote cup transforms produce acceptable local liquid visuals without replicated liquid state.
- Run `.\tools\validate_codex.cmd`.
- Hardware-test on Quest 2 or Quest 3 before declaring the effect release-ready.

## Acceptance Criteria

- Every active red cup contains a simple blue liquid visual.
- Tipping a cup changes the apparent water line direction.
- Fast cup movement creates subtle damped waves or slosh.
- The liquid effect has no collision and does not affect scoring.
- Practice, Classic Match, and Online Arena continue to run without script errors.
- No Photon, Meta, app ID, or platform-service changes are required.
- The implementation is documented as cosmetic-only and locally derived for multiplayer.

## Future Polish

- Arena-specific liquid colors or emissive effects.
- Cosmetic splash burst when a ball lands in a cup.
- Tiny droplets on the ball after scoring, purely visual.
- Different liquid fill levels for House Rules or arena variants.
- Cup plastic material pass that makes the blue fill faintly visible through the rim.
- Audio cue tied to slosh intensity when cups are handheld.
