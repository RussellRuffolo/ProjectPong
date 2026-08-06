# AGENTS.md

## Project Goal

Build a prototype Godot project for Meta Quest 2 and Meta Quest 3. The first playable milestone is intentionally small: when launched on a headset, the user loads into an otherwise empty VR scene and can see their Meta Quest Avatar functioning correctly.

Prioritize a real on-device Quest experience over desktop-only simulation. Editor previews are useful, but they are not a substitute for testing on hardware.

## Target Runtime

- Engine: Godot 4.7.1 
- XR runtime: OpenXR.
- Devices: Meta Quest 2 and Meta Quest 3.
- Platform: Android export for Quest.
- Avatar system: Meta Quest Avatars through the official Meta/Oculus avatar integration available for the selected Godot version.

If a dependency, SDK, or plugin version is not yet present in the repo, document the expected version and setup steps before wiring code against it. Do not invent local APIs for Meta Avatars.

## Current Milestone

Current stage: the basic empty OpenXR scene has been successfully deployed to and viewed on a Meta Quest 2. Next work should focus on official Meta Quest Avatar integration.

Create the smallest viable scene that:

1. Starts an OpenXR session on Quest.
2. Uses the headset pose as the player camera.
3. Initializes the Meta avatar system.
4. Displays the signed-in user's Meta Quest Avatar.
5. Leaves the surrounding world empty except for minimal lighting or origin helpers required for orientation.
6. Handles missing permissions, entitlement, login, or avatar data with clear logs and a non-crashing fallback.

Avoid adding gameplay, menus, multiplayer, locomotion, physics toys, or visual polish until this baseline works on hardware.

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
- Keep the boot scene boring and reliable. A clean empty world with a working avatar is the deliverable.
- Use clear node names such as `XROrigin3D`, `XRCamera3D`, `LeftController`, `RightController`, and `AvatarRoot`.
- Put platform or SDK initialization in a small, obvious script rather than scattering it across scene nodes.
- Log startup state: OpenXR availability, session start, platform initialization, entitlement status, avatar initialization, and avatar load result.
- Do not hard-code personal Meta account IDs, app IDs, tokens, signing passwords, or machine-specific Android paths.
- Gate Quest-only code so the project can still open in the Godot editor without crashing.
- Prefer small scenes and scripts that can be inspected quickly.

## Meta Quest Avatar Notes

Meta Avatars usually require correct app configuration, platform entitlement, user authentication, and Android permissions. Treat avatar visibility as an integration milestone, not just a rendering task.

When implementing avatar support:

- Use the official Meta avatar SDK/plugin path selected for this project.
- Document all required Meta developer dashboard settings.
- Document any required Android manifest permissions or features.
- Fail visibly in logs if the user avatar cannot be loaded.
- If editor stubs are needed, name them clearly as stubs and keep them separate from runtime Quest code.

Do not replace the user's Meta Avatar with a generic humanoid and call the milestone complete.

## Meta Avatars Research Status

Research date: 2026-08-06.

Current finding: Meta's official Meta Avatars SDK documentation is for Unity, and Meta marks Meta Avatars SDK `40.0.1` as the final End-of-Feature release. Existing integrations and backend services continue to work, but no further SDK versions or new APIs are planned. The docs describe Unity APIs such as `OvrAvatarEntity`, `OvrAvatarEntitlement`, `OvrAvatarInputManager`, and `Users.GetAccessToken()`. Do not assume these APIs exist in Godot.

For this Godot project, the currently checked-in `Godot OpenXR Vendors` plugin is still useful, but it is not an avatar renderer. It provides vendor-specific OpenXR features and Quest export support. The Godot-side Meta identity, entitlement, logged-in-user, and access-token work should use the official/community Godot Meta Toolkit Platform SDK plugin unless Meta releases a newer official Godot avatar package.

Primary sources to re-check before implementation:

- Meta Avatars SDK overview: `https://developers.meta.com/horizon/documentation/unity/meta-avatars-overview/`
- Meta Avatars app configuration: `https://developers.meta.com/horizon/documentation/unity/meta-avatars-app-config/`
- Meta Avatars Unity project configuration: `https://developers.meta.com/horizon/documentation/unity/meta-avatars-config-project/`
- Meta Avatars loading flow and failure modes: `https://developers.meta.com/horizon/documentation/unity/meta-avatars-load-avatars/`
- Meta Avatars input tracking model: `https://developers.meta.com/horizon/documentation/unity/unity-isdk-avatar-integration-sample/`
- Godot Meta Toolkit Platform SDK setup: `https://godot-sdk-integrations.github.io/godot-meta-toolkit/manual/platform_sdk/getting_started.html`
- Godot OpenXR Vendors plugin update notes: `https://godotengine.org/article/godot-xr-update-may-2026/`
- Godot Android OpenXR deployment: `https://docs.godotengine.org/en/stable/tutorials/xr/deploying_to_android.html`

## Concrete Meta Avatars Implementation Plan

Phase 0: Confirm the supported runtime path before writing avatar code.

1. Verify whether Meta provides a redistributable native Android runtime surface for Meta Avatars SDK `40.0.1` that can legally be called from a Godot GDExtension or Android plugin.
2. Inspect the downloaded Meta Avatars SDK package for Android native libraries, public headers, license terms, sample source, and dependency requirements.
3. If the SDK is Unity-only or does not expose a redistributable native interface, stop and document the blocker. Do not fake this with a humanoid placeholder. The next choice would be to ask Meta support/W4 Games/Godot XR maintainers whether a Godot-compatible avatar bridge exists or is permitted.

Phase 1: Add Meta Platform SDK support in Godot.

1. Add the Godot Meta Toolkit plugin to `addons/` if it is not already present.
2. Enable the plugin in `project.godot`.
3. Store the Meta App ID in a project setting or export-time configuration, never hard-coded in scripts.
4. Update the Android export preset so Quest builds have internet permission and the package name matches the Meta Developer Dashboard app.
5. Add a small `scripts/meta_platform_bootstrap.gd` that runs only on Android/Quest, initializes `MetaPlatformSDK`, checks entitlement, retrieves the logged-in user, and requests an access token.
6. Log each step with a stable prefix such as `[MetaPlatform]`, including failures for initialization, entitlement, user lookup, token lookup, and Data Use Checkup permissions.

Phase 2: Configure the Meta Developer Dashboard.

1. Create or select the Quest App ID for this package name.
2. Upload a signed release build to the Alpha channel before relying on entitlement or user data.
3. Complete Data Use Checkup for the platform data needed by avatars: User ID, User Profile, and Avatars, using "Use Avatars" as the purpose where required.
4. Keep keystores, signing passwords, dashboard app IDs, access tokens, and account IDs out of source control.

Phase 3: Build the Avatar runtime bridge only after Phase 0 passes.

1. Create a narrow Godot-facing API, for example `MetaAvatarManager` and `MetaAvatarEntity`, implemented by a GDExtension and/or Android plugin that wraps the official Meta Avatar runtime.
2. Expose only the milestone surface first: `initialize(access_token)`, `load_logged_in_user(user_id)`, `load_local_preset(preset_id)`, `set_tracking(head, left_hand, right_hand)`, and load/failure signals.
3. Feed tracking from the existing Godot XR nodes: `XRCamera3D`, `LeftController`, and `RightController`. Keep all avatar tracking data derived from the same XR origin so hand/controller lag is not introduced.
4. Place the avatar node under `AvatarRoot` in the existing empty XR scene. Do not add locomotion, menus, networking, or gameplay during this phase.
5. Default avatar quality to the lightest viable mobile setting unless hardware testing shows Quest 2 has frame time headroom.
6. Implement a non-crashing fallback path: if the signed-in user avatar fails because of missing permission, missing avatar, revoked access, bad App ID, network failure, or entitlement failure, log the exact reason and optionally load an official local Meta preset only if the SDK license and package provide one.

Phase 4: Scene and script integration.

1. Add `AvatarRoot` as a child of `XROrigin3D`.
2. Add a small `avatar_bootstrap.gd` that waits for OpenXR startup and successful platform bootstrap before initializing avatars.
3. Keep editor behavior safe: on non-Android or missing plugin classes, print a clear `[Avatar]` message and leave the scene empty.
4. Keep Godot scenes inspectable. Avatar SDK objects should live in one obvious subtree and one or two scripts, not scattered across the boot scene.

Phase 5: Verification.

1. Local editor smoke test: project opens and the main scene runs without missing-class crashes when avatar plugins are absent or disabled.
2. Android export test: APK builds with OpenXR, Meta Quest feature enabled, `arm64-v8a`, internet permission, and no local secrets.
3. On-device Quest test: app launches as immersive VR, head pose updates, platform initialization succeeds, entitlement succeeds, logged-in user ID is retrieved, avatar access token is retrieved, avatar runtime initializes, and the signed-in user's Meta Avatar appears.
4. Capture `adb logcat` showing `[XR]`, `[MetaPlatform]`, and `[Avatar]` startup lines. Add failures and fix notes to `docs/quest_openxr_test.md`.
5. Do not mark the milestone complete until a real signed-in Meta Quest Avatar is visible on Quest 2 or Quest 3 hardware.

## Build And Test

Before declaring the milestone done, verify as much of this checklist as the available hardware and SDK setup allow:

- Godot project opens without import errors.
- Main scene runs in the editor without script crashes.
- Android export preset targets Quest-compatible OpenXR.
- Build installs on Meta Quest 2 or Meta Quest 3.
- App launches into VR without a flat-window fallback.
- Head pose updates correctly.
- User avatar appears and tracks as expected.
- Startup logs clearly identify any missing platform, entitlement, permission, or avatar failures.

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
3. Make narrowly scoped edits tied to the Quest avatar milestone.
4. Update setup documentation whenever SDK, export, or dashboard configuration is required.
5. Run available validation commands before finishing.
6. Report clearly what was changed, what was tested, and what still requires headset or Meta dashboard verification.
