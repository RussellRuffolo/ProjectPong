# Multiplayer Photon Roadmap

## First Implementation Pass

- Added `res://scenes/networked_arena.tscn` as the online multiplayer workbench.
- Wired the menu's `Online Arena` button to load the networked scene.
- Added `PhotonSession` as the project-owned wrapper around the checked-in Fusion singleton.
- Added `NetworkedArena` to join a 2-player private Photon room and spawn locally owned hand avatars.
- Added `NetworkHandAvatar` with a `FusionSharedReplicator` child so each spawned hand can request shared-authority ownership and replicate its root transform.
- Added `NetworkMatchState` as the centralized place for match decisions, starting with a ball-authority placeholder.
- Added an in-world Photon lobby UI to the online arena. Players now connect to Photon first, then explicitly create a visible 2-player room or join an open room from the Photon room list.
- Expanded the online arena into a minimal two-player pong loop: a 9-foot table, ten-cup racks at both ends, a shared networked ball, turn ownership, two throws per turn, score tracking, cup removal, and game-over detection.
- The second Photon player in the room starts with the ball. The match state broadcasts compact RPC snapshots for turn, score, cup, and winner state while the active local player owns scoring resolution for the current throw.
- Added `NetworkedPongBall` with a `FusionSharedReplicator` child in the scene so the active player can request shared-authority ownership of the ball for their turn.

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
- `res://scenes/networked_arena.tscn` sets `PhotonSession.join_default_room_on_start=false` and `visible_room=true` so created rooms appear in the Photon lobby list until the second player joins.

## Two-Headset Smoke Test

1. Configure the same Photon Fusion App ID on both Quest builds without committing the ID.
2. Install the same Android build on both Quest 2/Quest 3 devices.
3. Launch both devices into the menu and select `Online Arena`.
4. On the first headset, select `Create Room` and confirm the new room appears with `1/2` players.
5. On the second headset, select the created room from the open room list.
6. Confirm both devices report distinct local player IDs and the lobby UI hides after joining.
7. Move each controller and confirm the other headset sees two spawned hand markers moving.
8. Confirm each headset is placed on an opposite side of the 9-foot table and sees both ten-cup racks.
9. Confirm the second joined player starts with the ball and the first player cannot pick it up during that opening turn.
10. Throw twice from the second headset and confirm the turn changes to the first player.
11. Score into an opponent cup and confirm the same cup is marked/removed and the same score appears on both headsets.
12. Finish a rack, or force the last cup state during testing, and confirm both headsets show the same winner.
13. Confirm the room disappears from the open room list after the second player joins.
14. Return to the single-player `Practice` scene and verify the existing throw/cup baseline still works.

## Next Steps

1. Confirm the exact Photon Fusion Godot 3 preview package version and update this document with the source package identifier.
2. Validate `FusionSharedReplicator` spawn/ownership behavior on two physical Quest devices.
3. Validate the `NetworkedPongBall` shared-authority handoff, RPC match snapshots, score resolution, and cup removal on two physical Quest devices.
4. Add a documented fallback owner and match pause behavior when a player leaves mid-turn or before cup-removal/reset delays finish.
5. Add room configuration for selected House Rules before `Create Room`, storing a compact ruleset identifier/hash in Photon room properties.
6. Add Meta invite/roster flow through Godot Meta Toolkit after the private Photon room flow is reliable.
7. Add automated local validation for the online scene loading path, while keeping final multiplayer verification on hardware.
