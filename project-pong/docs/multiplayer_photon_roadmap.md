# Multiplayer Photon Roadmap

## First Implementation Pass

- Added `res://scenes/networked_arena.tscn` as the online multiplayer workbench.
- Wired the menu's `Online Arena` button to load the networked scene.
- Added `PhotonSession` as the project-owned wrapper around the checked-in Fusion singleton.
- Added `NetworkedArena` to join a 2-player private Photon room and spawn locally owned hand avatars.
- Added `NetworkHandAvatar` with a `FusionSharedReplicator` child so each spawned hand can request shared-authority ownership and replicate its root transform.
- Added `NetworkMatchState` as the centralized place for match decisions, starting with a ball-authority placeholder.

## Photon SDK Baseline

- Current expected SDK: Photon Fusion Godot 3 preview, checked in under `res://addons/fusion`.
- The checked-in `fusion.gdextension` declares Godot compatibility minimum `4.6` and includes Windows editor plus Android arm64 libraries required by the Quest prototype.
- The local package does not expose a precise preview build number in its manifest. Before production hardening or SDK upgrades, record the exact Photon download/version/build hash in this document.

## Local Configuration

- Do not commit real Photon App IDs, Meta App IDs, tokens, signing credentials, or invite target IDs.
- `PhotonSession` first reads `PHOTON_FUSION_APP_ID` for local editor testing, then falls back to `ProjectSettings` key `fusion/connection/app_id`.
- The default room is `fusion/connection/default_room`, currently `project-pong-dev-room`; override it at launch with `--pong-room <room-name>` or `--pong-room=<room-name>`.
- Optional Photon region can be set with `fusion/connection/region`, `--photon-region <region>`, or `--photon-region=<region>`.
- The Android export preset already has `permissions/internet=true`, which is required for Photon Cloud.

## Two-Headset Smoke Test

1. Configure the same Photon Fusion App ID on both Quest builds without committing the ID.
2. Install the same Android build on both Quest 2/Quest 3 devices.
3. Launch both devices into the menu and select `Online Arena`.
4. Confirm both devices join the same room name and report distinct local player IDs.
5. Move each controller and confirm the other headset sees two spawned hand markers moving.
6. Confirm the room closes to additional players after two players have joined.
7. Return to the single-player `Practice` scene and verify the existing throw/cup baseline still works.

## Next Steps

1. Confirm the exact Photon Fusion Godot 3 preview package version and update this document with the source package identifier.
2. Validate `FusionSharedReplicator` spawn/ownership behavior on two physical Quest devices.
3. Add a networked ball scene with explicit authority transfer and a documented fallback owner when a player leaves.
4. Move score/reset decisions into `NetworkMatchState` and keep player scripts free of authoritative match decisions.
5. Add a small in-VR private-room affordance or Meta Group Presence handoff so players do not rely on the default dev room.
6. Add Meta invite/roster flow through Godot Meta Toolkit after the private Photon room flow is reliable.
7. Add automated local validation for the online scene loading path, while keeping final multiplayer verification on hardware.
