# AGENTS.md

## Project Goal

Build toward a paid VR "beer pong" style multiplayer game for release on the Meta Quest store. The long-term product should support online multiplayer, stylized arenas, arena-specific "House Rules", responsive VR interactions, and visual effects that make each venue feel distinct.

The current playable milestone is intentionally small: when launched on a headset, the user loads into an otherwise empty immersive VR scene with working head tracking.

Prioritize a real on-device Quest experience over desktop-only simulation. Editor previews are useful, but they are not a substitute for testing on hardware.

## Target Runtime

- Engine: Godot 4.7.1.
- XR runtime: OpenXR.
- Devices: Meta Quest 2 and Meta Quest 3.
- Platform: Android export for Quest.
- Planned networking layer: Photon.

If a dependency, SDK, or plugin version is not yet present in the repo, document the expected version and setup steps before wiring code against it.

## Product Direction

- Design the codebase for a commercial Quest release, with attention to performance, comfort, store-readiness, deterministic behavior, and maintainable content pipelines.
- Treat multiplayer as a core architectural constraint, even before networking is implemented.
- Prefer gameplay systems that can run under an authoritative or host-authoritative model rather than local-only assumptions.
- Keep player identity, matchmaking, lobbies, entitlement checks, voice/social features, and platform services isolated behind explicit interfaces until the final Quest Store and Photon integration choices are confirmed.
- Plan for multiple arenas as data-driven or scene-driven content modules, not hard-coded variants.
- Model "House Rules" as composable rule sets that can be enabled per arena, lobby, match, or playlist.
- Keep cosmetic visual effects separate from gameplay state so network synchronization stays small, clear, and reliable.

## Current Milestone

Current stage: launching into an immersive OpenXR scene on a Meta Quest headset has been achieved. Preserve that working Quest baseline while beginning the next playable milestone.

Next milestone: create a minimal single-player pong game that can run inside the established VR scene.

The first step for this milestone is ball physics:

1. Add a simple ball with predictable motion.
2. Keep ball behavior deterministic enough to support future multiplayer authority and replication.
3. Use Godot physics in a small, inspectable setup before adding scoring, cups, throws, arenas, or effects.
4. Verify that the ball simulation runs in the editor and does not break OpenXR startup on Quest.

Avoid adding menus, multiplayer, locomotion, platform identity flows, arena polish, or House Rules until the minimal single-player ball behavior is reliable.

Even during single-player prototyping, avoid choices that would make later multiplayer support difficult. Scene ownership, player rigs, input handling, ball state, and future gameplay scripts should be structured so they can be cleanly separated into local-player, remote-player, and shared match-state responsibilities.

## Repository Expectations

Use conventional Godot structure:

- `project.godot` at the repo root.
- `scenes/` for `.tscn` files.
- `scripts/` for GDScript or C# source.
- `addons/` only for checked-in Godot plugins that are intended to be part of the project.
- `export_presets.cfg` only when export configuration is intentionally tracked and contains no local secrets.
- `docs/` for setup notes, SDK version notes, and hardware test checklists.

Keep generated Godot cache folders, Android build outputs, keystores, and local editor metadata out of source control unless the user explicitly asks otherwise.

## Development Guidelines

- Prefer Godot-native XR nodes and established plugin APIs over custom XR plumbing.
- Keep the boot scene boring and reliable. A clean empty world with working OpenXR tracking is the deliverable.
- Use clear node names such as `XROrigin3D`, `XRCamera3D`, `LeftController`, and `RightController`.
- Put XR startup in a small, obvious script rather than scattering it across scene nodes.
- Log startup state: OpenXR availability, initialization result, session request, primary interface, and fallback mode.
- Do not hard-code personal account IDs, app IDs, tokens, signing passwords, or machine-specific Android paths.
- Gate Quest-only code so the project can still open in the Godot editor without crashing.
- Prefer small scenes and scripts that can be inspected quickly.
- Keep systems multiplayer-ready: separate local input capture from replicated state, keep authoritative match decisions centralized, and avoid direct scene lookups that assume only one player exists.
- Do not introduce Photon code, SDK calls, app IDs, regions, or matchmaking assumptions until the Photon plugin/package version and setup path are documented.
- When Photon is introduced, wrap it behind project-owned networking interfaces so gameplay code is not tightly coupled to vendor APIs.
- Keep future arena content modular. Arena geometry, lighting, ambience, VFX, spawn points, cup layouts, and House Rules should be replaceable without rewriting core match logic.
- Make rule behavior explicit and testable. House Rules should describe what they change, how they replicate, and which side has authority.
- Budget VR visuals for Quest hardware first. Stylish arenas and effects are encouraged later, but they must respect frame-rate, comfort, memory, and thermal limits.
- Keep paid-release concerns in mind: no checked-in secrets, no local signing credentials, no placeholder third-party assets with unclear licenses, and no store-only assumptions that break editor workflows.

## Quest OpenXR Setup Notes

The checked-in Godot OpenXR Vendors plugin provides vendor-specific OpenXR features and Quest export support. It should remain focused on the Android OpenXR launch path.

Useful sources to re-check when changing deployment setup:

- Godot OpenXR Vendors plugin update notes: `https://godotengine.org/article/godot-xr-update-may-2026/`
- Godot Android OpenXR deployment: `https://docs.godotengine.org/en/stable/tutorials/xr/deploying_to_android.html`

## Verification

Before declaring the milestone done, verify as much of this checklist as the available hardware and SDK setup allow:

- Godot project opens without import errors.
- Main scene runs in the editor without script crashes.
- Android export preset targets Quest-compatible OpenXR.
- Build installs on Meta Quest 2 or Meta Quest 3.
- App launches into VR without a flat-window fallback.
- Head pose updates correctly.
- Startup logs clearly identify whether OpenXR was found, initialized, and enabled.

If hardware testing is not possible, say so explicitly and list what was verified locally.

For future multiplayer and commercial-release work, also verify the relevant parts of this checklist:

- Local and remote player responsibilities are clearly separated.
- Networked gameplay state has an identified authority.
- Photon setup, versions, app configuration, and secrets handling are documented before use.
- Arena-specific content can be loaded or swapped without changing core match logic.
- House Rules can be enabled, disabled, and tested independently.
- Quest performance remains within the target comfort budget on real hardware.

## Coding Style

- Follow the style already present in the repo once source files exist.
- For GDScript, use typed variables and functions where practical.
- Keep scripts short and purpose-specific for this prototype.
- Add comments only where they clarify SDK setup, platform assumptions, or non-obvious XR behavior.
- Avoid broad refactors unrelated to the current milestone.

## Agent Workflow

When working in this repo:

1. Inspect existing Godot files before making assumptions.
2. Preserve user changes and unrelated work.
3. Make narrowly scoped edits tied to the Quest OpenXR baseline.
4. Keep new code multiplayer-aware, even when implementing local-only scaffolding.
5. Update setup documentation whenever SDK, export, networking, store, or deployment configuration changes.
6. Document expected versions and setup steps before adding Photon, platform services, or other external dependencies.
7. Run available validation commands before finishing.
8. Report clearly what was changed, what was tested, and what still requires headset verification.
