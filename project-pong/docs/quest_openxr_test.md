# Meta Quest OpenXR Test

This project implements a basic XR boot scene for Meta Quest. The target is a minimal immersive VR scene with headset pose tracking and no platform or identity bootstrap code.

## What is included

- `res://scenes/main.tscn` is the startup scene.
- The scene contains `XROrigin3D`, `XRCamera3D`, `LeftController`, and `RightController`.
- `res://scripts/xr_bootstrap.gd` finds and initializes the Godot OpenXR interface, enables XR on the viewport, and logs fallback reasons instead of crashing.
- `res://scripts/hand_grabber.gd` shows a small marker at each tracked hand/controller pose and lets either hand grab nearby objects in the `grabbable` group.
- The world is intentionally empty except for lighting, sky, a tiny origin helper, and a floating ping pong ball used to test grabbing.

## Local editor smoke test

1. Open `E:\ProjectPong\project-pong` in Godot 4.7 or the Godot 4.x version that created the project.
2. Run the project.
3. If no desktop OpenXR runtime is active, the scene should still open with a fallback camera.
4. Check the Godot output panel for logs beginning with `[XR]`.
5. In non-XR fallback mode, the hand markers and test ball may overlap near the origin because live controller poses are not available.

Expected desktop fallback log:

```text
[XR] Boot scene loaded.
[XR] XR origin, camera, and controller trackers configured.
[XR] OpenXR interface was not found...
[XR] Non-XR fallback camera enabled...
```

If your PC has an active OpenXR runtime, the log may instead show that the OpenXR interface initialized.

## Required dependencies

Install these before trying to deploy to Quest:

- Godot `4.7.1`.
- Godot Android export templates for Godot `4.7.1`.
- Android Studio.
- OpenJDK 17.
- Android SDK Platform-Tools `35.0.0` or newer. This package contains `adb.exe`.
- Android SDK Build-Tools `35.0.1`.
- Android SDK Platform `android-35`.
- Android SDK Command-line Tools latest.
- Android NDK `28.1.13356709`.
- CMake `3.10.2.4988404`.
- Meta Quest Developer Hub or the Meta Quest/Oculus Windows ADB driver if Windows does not recognize the headset for debugging.
- Godot OpenXR Vendors plugin, installed from Godot's Asset Store by searching for `OpenXR vendors`.

## Find adb on Windows

`adb` is not a separate Godot tool. It is installed by Android SDK Platform-Tools.

If Android Studio installed the SDK in its default Windows location, `adb.exe` is usually here:

```text
C:\Users\<your-user-name>\AppData\Local\Android\Sdk\platform-tools\adb.exe
```

If `adb` is not recognized in PowerShell, either run it with the full path or add the `platform-tools` folder to your user `Path` environment variable.

Example:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" devices
```

After editing `Path`, close and reopen PowerShell before running:

```powershell
adb devices
```

## Quest build setup

1. Install Android build support for the same Godot editor version used to open the project.
2. In Godot, open **Editor > Manage Export Templates** and install the export templates if prompted.
3. In Android Studio, open **Tools > SDK Manager** and confirm that the required SDK packages listed above are installed.
4. Configure **Editor Settings > Export > Android** with your Android SDK and Java SDK paths.
5. Add the SDK's `platform-tools` folder to your Windows user `Path` so `adb` is available in PowerShell.
6. Generate or select a debug keystore in Godot's Android export settings.
7. Enable Developer Mode for the Quest headset in the Meta Horizon mobile app.
8. Connect the Quest by USB and accept the headset's USB debugging prompt.
9. In Godot, install the OpenXR Vendors plugin from the Asset Store if it is not already installed.
10. In Godot, select **Project > Install Android Build Template**. This creates the local Gradle Android build used by Android XR plugins.
11. In Godot, create an **Android** export preset named `Meta Quest`.
12. Enable **Runnable** and **Use Gradle Build**.
13. Set the Android package name to a reverse-DNS identifier you control, for example `com.yourname.projectpong`.
14. Enable only `arm64-v8a` under Android architectures.
15. Set the XR mode to **OpenXR** in the Android export preset.
16. If the OpenXR Vendors plugin exposes XR feature checkboxes, enable the Meta Quest feature for this preset.
17. Use the Compatibility renderer for this early Quest test; this project is configured that way.
18. Leave signing passwords, release keystores, and local SDK paths untracked.

## Run on headset

1. With the headset connected, use Godot's one-click deploy/run button for the Android export preset.
2. Put on the headset when the app launches.
3. Confirm the app enters immersive VR instead of a flat Android window.
4. Move your head and confirm the camera pose updates.
5. Move each controller or tracked hand and confirm the colored hand markers follow the tracked pose.
6. Reach toward the floating ping pong ball in front of the starting position.
7. Hold the grip/grasp input to grab the ball, move it, then release to let go.
8. Look down near your starting position for the small origin helper.
9. Watch `adb logcat` or Godot's deploy output for `[XR]` startup messages.

Useful logcat filter:

```powershell
adb logcat | Select-String "\[XR\]|godot|OpenXR"
```

## OpenXR startup troubleshooting

If the headset shows this alert:

```text
OpenXR was requested but failed to start. HMD was not detected or a required feature was not supported.
```

Check these project settings first:

- `res://addons/godotopenxrvendors` exists.
- `Project > Install Android Build Template...` has created `res://android/build`.
- `Project > Export... > Meta Quest > Gradle Build > Use Gradle Build` is enabled.
- `Project > Export... > Meta Quest > XR Features > XR Mode` is `OpenXR`.
- `Project > Export... > Meta Quest > XR Features > Meta` is enabled.
- Quest 2 and Quest 3 device support are enabled under the Meta XR feature options.

The exported APK should contain these files and manifest entries:

- `lib/arm64-v8a/libgodotopenxrvendors.so`
- `lib/arm64-v8a/libopenxr_loader.so`
- `org.khronos.openxr.permission.OPENXR`
- `com.oculus.intent.category.VR`
- `org.khronos.openxr.intent.category.IMMERSIVE_HMD`
- `com.oculus.supportedDevices` including `quest2`

## Pass criteria for this milestone

- The project opens without import errors.
- The main scene runs in the editor without script crashes.
- The Android export preset targets OpenXR and `arm64-v8a`.
- The app launches on Quest 2 or Quest 3 as an immersive VR app.
- Head pose updates correctly in headset.
- Left and right hand/controller markers follow tracked hand poses.
- The floating ping pong ball can be grabbed with grip/grasp input and released without crashing.
- Startup logs identify whether OpenXR was found, initialized, and enabled.

## Known next step

Keep the next milestone focused on the smallest useful VR interaction or scene requirement while preserving the current on-device OpenXR baseline.
