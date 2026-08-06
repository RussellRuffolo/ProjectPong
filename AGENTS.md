# AGENTS.md

## Project Goal

Build a prototype Godot project for Meta Quest 2 and Meta Quest 3. The current playable milestone is intentionally small: when launched on a headset, the user loads into an otherwise empty immersive VR scene with working head tracking.

Prioritize a real on-device Quest experience over desktop-only simulation. Editor previews are useful, but they are not a substitute for testing on hardware.

## Target Runtime

- Engine: Godot 4.7.1.
- XR runtime: OpenXR.
- Devices: Meta Quest 2 and Meta Quest 3.
- Platform: Android export for Quest.

If a dependency, SDK, or plugin version is not yet present in the repo, document the expected version and setup steps before wiring code against it.

## Current Milestone

Current stage: the basic empty OpenXR scene has been successfully deployed to and viewed on a Meta Quest 2. Preserve and harden that baseline.

Create the smallest viable scene that:

1. Starts an OpenXR session on Quest.
2. Uses the headset pose as the player camera.
3. Leaves the surrounding world empty except for minimal lighting or origin helpers required for orientation.
4. Logs OpenXR startup state and any non-crashing fallback reason.

Avoid adding gameplay, menus, multiplayer, locomotion, physics toys, platform identity flows, or visual polish until this baseline remains reliable on hardware.

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
4. Update setup documentation whenever SDK, export, or deployment configuration changes.
5. Run available validation commands before finishing.
6. Report clearly what was changed, what was tested, and what still requires headset verification.
