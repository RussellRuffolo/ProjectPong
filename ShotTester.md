# Native Cup Physics Test

The old custom-collision Shot Tester has been retired. Cup collision and scoring now use the same native Godot physics path in gameplay and automated editor validation.

## Current Test

Run the focused native cup test from the repository root:

```powershell
.\Godot_v4.7.1-stable_win64_console.exe --headless --xr-mode off --path project-pong --scene res://scenes/editor/native_cup_physics_test.tscn --log-file codex-native-cup-physics.log
```

The test creates the shared `res://scenes/gameplay/cup_target.tscn`, drops a real `ThrowableBall` onto its top cap, waits for `PhysicsDirectBodyState3D` contact classification, and verifies the score-capture animation plus the post-capture removal delay. A successful run prints:

```text
[NativeCupPhysicsTest] PASS: native contact, capture, and delayed removal completed.
```

This is a local regression check only. Final tuning still requires throws against clustered cups on Quest 2 and Quest 3 hardware.
