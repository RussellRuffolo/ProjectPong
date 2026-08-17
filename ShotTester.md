# Native Cup Shot Tester

`res://scenes/editor/shot_tester.tscn` is an editor-only manual and headless shot tester for the simplified native cup physics. It builds its rack with the shared `CupRackBuilder`, instantiates the shared `cup_target.tscn`, launches the gameplay `ThrowableBall`, and resolves scores through the ball's native contact and capture signals.

The tester UI supports deterministic aim and angle variation, active-cup toggles, repeat/reset controls, native score-contact details, and log export. Rejected contacts use Godot/Jolt's ordinary response; the tester does not calculate cup volumes or apply a custom bounce.

Run a deterministic headless shot from the repository root:

```powershell
.\Godot_v4.7.1-stable_win64_console.exe --headless --xr-mode off --path project-pong --scene res://scenes/editor/shot_tester.tscn --log-file codex-shot-tester.log -- --shot-test --shot-angle=88 --shot-expect-score=true
```

Optional arguments include `--shot-aim=x,y,z`, `--shot-aim-error=meters`, `--shot-angle-error=degrees`, `--shot-seed=integer`, `--shot-active-cups=0,1,2`, `--shot-expect-contact=true|false`, and `--shot-max-physics-frames=count`.

The smaller `res://scenes/editor/native_cup_physics_test.tscn` remains the focused contact/capture/removal regression test. Final tuning still requires clustered throws on Quest 2 and Quest 3 hardware.
