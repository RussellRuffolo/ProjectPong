# AGENTS.md

## Project Goal

Build toward a paid VR "beer pong" style multiplayer game for release on the Meta Quest store. The long-term product should support online multiplayer, stylized arenas, arena-specific "House Rules", responsive VR interactions, and visual effects that make each venue feel distinct.

The current playable baseline includes an immersive OpenXR scene on Quest and a minimal single-player pong prototype. Preserve that working Quest baseline while building the first multiplayer demo.

Prioritize a real on-device Quest experience over desktop-only simulation. Editor previews are useful, but they are not a substitute for testing on hardware.

## Target Runtime

- Engine: Godot 4.7.1.
- XR runtime: OpenXR.
- Devices: Meta Quest 2 and Meta Quest 3.
- Platform: Android export for Quest.
- Planned networking layer: Photon Fusion Godot.

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

Current stage: launching into an immersive OpenXR scene on a Meta Quest headset has been achieved, and the minimal single-player pong game has been achieved.

Next milestone: create a minimal 2-player multiplayer demo that can run inside the established VR scene.

The first multiplayer milestone should prove the smallest useful loop:

1. Two Quest headsets can join the same private multiplayer room.
2. Each headset owns and replicates its local player rig or controller pose.
3. The ball has explicit network authority and replicates predictably.
4. Match state and scoring decisions are centralized behind a small match-state script, even if scoring stays minimal.
5. The demo works without developer-hosted servers by using Photon Cloud.
6. OpenXR startup, head tracking, and the single-player baseline are not broken.

Avoid adding public matchmaking, locomotion, arena polish, House Rules, Photon custom server plugins, paid platform flows, or broad social features until the private 2-player room works reliably.

Keep the multiplayer prototype structured so local-player, remote-player, ball authority, and shared match-state responsibilities are visibly separate.

## Multiplayer Implementation Guidance

Use this stack for the first multiplayer prototype:

- Godot 4.7.1.
- OpenXR Vendors plugin for the existing Quest OpenXR baseline.
- Godot Meta Toolkit for Meta Platform SDK features: entitlement, friends, Group Presence, invite panel, and roster panel.
- Photon Fusion Godot 3 preview for room connection, spawning, replication, RPCs, and shared-authority networking.
- Photon Dashboard App ID and Meta Developer Dashboard App ID, configured outside source control.
- Android export with the `INTERNET` permission enabled.

Start with 2-player private rooms using Photon Fusion Shared-Authority. Meta friends and invites should be a social/session handoff layer, not the core gameplay transport.

The intended private-room flow is:

1. Host creates or joins a Photon room.
2. Store the Photon room/session identifier in Meta Group Presence as the lobby or match session ID.
3. Mark the Meta Group Presence as joinable only when the room can accept another player.
4. Launch the Meta invite or roster panel from Godot Meta Toolkit.
5. When an invited player accepts, read the Meta join intent/deeplink and join the matching Photon room.

Networking rules for the prototype:

- Player rigs and controller poses are locally owned by the player controlling them.
- The ball has one explicit authority at a time. Start with master-client or room-creator authority if that is simplest, but keep transfer to another player possible.
- Shared match decisions, including scoring and reset behavior, belong in a match-state script rather than player scripts.
- Cosmetic effects must not drive gameplay state.
- Do not hard-code Photon App IDs, Meta App IDs, regions, user IDs, invite targets, signing credentials, or secrets.
- Photon Fusion Godot 3 is a preview SDK. It is acceptable for this prototype, but document the exact version before adding it and treat production readiness as a release risk.
- Do not introduce dedicated server hosting for this milestone. Photon Cloud should provide the required no-developer-hosting multiplayer path.

## Current Multiplayer First Pass

The online multiplayer workbench is `res://scenes/networked_arena.tscn`, reached from the menu's `Online Arena` button. Keep this scene focused on proving two-player Photon room connection, local hand ownership, remote hand visibility, ball authority, and centralized match-state behavior before adding arena polish.

Photon-facing runtime calls should start in `res://scripts/photon_session.gd`. Gameplay scripts should depend on project-owned scripts such as `PhotonSession`, `NetworkedArena`, `NetworkHandAvatar`, and `NetworkMatchState` rather than scattering raw Fusion singleton calls through gameplay code.

The first pass uses `FusionSpawner` plus `FusionSharedReplicator` hand avatars in `res://scenes/network_hand_avatar.tscn`. Each local hand requests Shared-Authority ownership and drives its replicated root transform from the local XR controller. Validate this exact behavior on two Quest headsets before building ball authority on top of it.

Configuration rules for this pass:

- `PhotonSession` reads `PHOTON_FUSION_APP_ID` first, then `fusion/connection/app_id`; keep real values out of source control.
- The default private room is `fusion/connection/default_room`, and can be overridden with `--pong-room`.
- Keep rooms capped at two players and invisible to public matchmaking until the private room loop is reliable.
- The current Photon package is the checked-in `res://addons/fusion` Photon Fusion Godot 3 preview package. Its manifest does not expose a precise build number, so record the source package version/build hash in `docs/multiplayer_photon_roadmap.md` before upgrading or hardening the integration.

Current roadmap lives in `docs/multiplayer_photon_roadmap.md`. Update it whenever Photon setup, Meta handoff, room flow, authority ownership, or hardware verification changes.

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
- Before changing Photon SDK usage, package contents, app ID setup, regions, or room flow, update `docs/multiplayer_photon_roadmap.md` with the expected version and setup path.
- Keep Photon wrapped behind project-owned networking interfaces so gameplay code is not tightly coupled to vendor APIs.
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
- `.\tools\validate_codex.cmd` runs successfully for local Codex validation without a headset.
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
