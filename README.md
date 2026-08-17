# ProjectPong Meta Quest Deployment Guide

This repository contains a Godot/OpenXR prototype for a Meta Quest beer pong style VR game. The Godot project lives in `project-pong/`; open that folder in Godot, not the repository root.

These instructions are for local development deployment to a Meta Quest headset. They do not cover Meta Horizon Store submission, production signing, entitlement checks, or paid-release channel management.

Source instructions were checked on August 11, 2026.

## Native Cup Physics Overhaul Progress

- [x] Audited the existing cup collision paths and identified the runtime math-volume system, synthetic cup contacts, math-only editor testers, and imported combined collision model as the legacy implementation to remove.
- [x] Added `res://scenes/gameplay/cup_target.tscn`, a fixed `StaticBody3D` with one authored 16-point native convex shape and a shared physics material.
- [x] Routed score detection through `PhysicsDirectBodyState3D` contact point/normal data, with deterministic candidate selection and contact-based score confirmation.
- [x] Migrated Practice, Classic Match, Computer Classic Match, and Online Arena rack construction to the shared native cup scene.
- [x] Removed the mathematical collider code, synthetic cup-contact path, score-by-planned-trajectory shortcuts, obsolete math-only collision/shot testers, and imported combined collision model.
- [x] Passed `tools/validate_codex.cmd`, direct scene-load checks for Practice, Classic Match, Computer Classic Match, and Online Arena, the focused native contact/capture/removal test, and the CPU direct-zero scoring smoke (6/6 physical scores).
- [ ] Tune edge fairness, clustered-cup bounce, and performance on Quest 2/Quest 3; repeat Online Arena validation on two headsets because local headless tests do not verify device physics or replicated presentation timing.

## Target Environment

Use these versions unless the project maintainers intentionally upgrade the repo:

| Component | Required version or setting | Notes |
| --- | --- | --- |
| Godot | 4.7.1 stable, Standard build | The project uses GDScript; the .NET editor is not required. |
| Renderer | Compatibility / OpenGL | Recommended by Godot for Android-based XR at this stage. |
| XR runtime | OpenXR | Enabled in `project-pong/project.godot`. |
| Android CPU architecture | `arm64-v8a` only | Required for Quest deployment. |
| Android export | Gradle build | Required/recommended for Android XR and vendor-specific OpenXR support. |
| Headsets | Meta Quest 2, Quest 3, Quest 3S, Quest Pro | Quest 2 and Quest 3 support are enabled in the export preset. |
| OpenXR Vendors plugin | v5.1.0 stable, checked in | Present at `project-pong/addons/godotopenxrvendors`. |
| Photon Fusion Godot | Godot 3 preview package, checked in | Present at `project-pong/addons/fusion`. |

## Official Downloads

Install these before opening or exporting the project:

| Tool | Download link | What to install |
| --- | --- | --- |
| Godot editor | [Godot 4.7.1 stable archive](https://godotengine.org/download/archive/4.7.1-stable/) | Download the Standard editor for your OS. On Windows, choose `Windows - x86_64`. |
| Godot export templates | [Godot 4.7.1 export templates](https://godotengine.org/download/archive/4.7.1-stable/) | Install from Godot with `Editor > Manage Export Templates`, or download the Standard export templates from the archive page. |
| OpenJDK | [OpenJDK 17 from Adoptium](https://adoptium.net/temurin/releases/) or [Microsoft Build of OpenJDK 17](https://learn.microsoft.com/en-us/java/openjdk/download) | Godot recommends JDK 17 for Android export compatibility. |
| Android Studio | [Android Studio downloads](https://developer.android.com/studio) | The Android Studio page listed Android Studio Quail 3, 2026.1.3 Patch 1 when checked. Use latest stable Android Studio unless Godot changes its Android requirements. |
| Android SDK command-line tools | [Android Studio command-line tools](https://developer.android.com/studio#command-line-tools-only) | Needed only if you install SDK packages without Android Studio. Android Studio includes these tools. |
| Meta Horizon mobile app | [Meta Horizon app](https://www.meta.com/quest/setup/) | Required to pair the headset and enable Developer Mode. |
| Meta Quest Developer Hub | [MQDH for Windows](https://developers.meta.com/horizon/downloads/package/oculus-developer-hub-win/) or [MQDH for Mac](https://developers.meta.com/horizon/downloads/package/oculus-developer-hub-mac/) | Optional but recommended for device management, logs, APK install, and headset verification. Version 6.4.1 was current when checked. |
| Oculus ADB Drivers | [Oculus ADB Drivers](https://developers.meta.com/horizon/downloads/package/oculus-adb-drivers/) | Windows only. Install if `adb devices` does not recognize the headset. |
| OpenXR Vendors plugin | [Godot OpenXR Vendors Plugin](https://store.godotengine.org/asset/godot-xr/godot-openxr-vendors-plugin/) | Already checked in. Download only if the addon is missing or intentionally being upgraded. |

## 1. Clone and Open the Project

Clone the repository, then open `project-pong/` in Godot 4.7.1.

```powershell
git clone <repo-url> ProjectPong
cd ProjectPong
```

In Godot:

1. Open the Project Manager.
2. Choose `Import`.
3. Select `project-pong/project.godot`.
4. Let Godot import resources before exporting or running.

The repository root includes `tools/validate_codex.cmd`, but the Godot project root is `project-pong/`.

## 2. Install Godot and Export Templates

1. Download Godot 4.7.1 stable from the official archive.
2. Run the Standard editor for your OS.
3. In Godot, open `Editor > Manage Export Templates`.
4. Install templates for the current Godot version.

The export templates must match the exact editor version. A Godot 4.7.1 project should use Godot 4.7.1 export templates.

## 3. Install Android Build Dependencies

Godot's Android export documentation requires OpenJDK 17, Android Studio or Android SDK command-line tools, and specific Android SDK packages.

Install OpenJDK 17 first. Then install Android Studio, run it once, and use `Tools > SDK Manager` to install:

| Android SDK package | Required version |
| --- | --- |
| Android SDK Platform-Tools | 35.0.0 or newer |
| Android SDK Build-Tools | 35.0.1 |
| Android SDK Platform | `android-35` |
| Android SDK Command-line Tools | Latest |
| Android NDK | r28b, `28.1.13356709` |
| CMake | `3.10.2.4988404` |

In Android Studio:

1. Open `Tools > SDK Manager`.
2. On `SDK Platforms`, install Android SDK Platform 35.
3. On `SDK Tools`, enable `Show Package Details`.
4. Select the package versions listed above.
5. Apply the changes and accept the licenses.

Command-line alternative:

```powershell
sdkmanager --sdk_root=<android_sdk_path> "platform-tools" "build-tools;35.0.1" "platforms;android-35" "cmdline-tools;latest" "cmake;3.10.2.4988404" "ndk;28.1.13356709"
sdkmanager --licenses
```

On Windows, the Android SDK is commonly installed at:

```text
C:\Users\<your-user-name>\AppData\Local\Android\Sdk
```

Add SDK Platform-Tools to your user `Path` so `adb` is available in new terminals:

```text
C:\Users\<your-user-name>\AppData\Local\Android\Sdk\platform-tools
```

Verify:

```powershell
adb version
```

## 4. Configure Godot's Android Paths

In Godot:

1. Open `Editor > Editor Settings`.
2. Go to `Export > Android`.
3. Set `Java SDK Path` to your OpenJDK 17 installation.
4. Set `Android SDK Path` to your Android SDK directory.
5. If the debug keystore path is empty, let Godot create one or choose a local debug keystore.

Common Windows paths:

```text
Java SDK Path: C:\Program Files\Microsoft\jdk-17...
Android SDK Path: C:\Users\<your-user-name>\AppData\Local\Android\Sdk
```

Do not commit keystores, signing passwords, local SDK paths, `.apk`, or `.aab` files. The repository `.gitignore` already excludes those.

## 5. Prepare the Quest Headset

Meta requires Developer Mode before you can install local builds.

1. Create or join a team in the [Meta Horizon Developer Dashboard](https://developers.meta.com/horizon/).
2. Verify the Meta developer account that will be used on the headset.
3. Install the Meta Horizon mobile app on an Android or iOS device.
4. Pair the headset with the mobile app.
5. In the mobile app, open the headset item, then `Headset Settings > Developer Mode`.
6. Toggle Developer Mode on.
7. Connect the headset to the computer with a USB-C data cable.
8. Put on the headset.
9. Open Quick Controls, then Settings, then the Developer tab.
10. Enable `MTP Notification`.
11. When the USB debugging prompt appears, choose `Always allow from this computer`.

Verify ADB can see the headset:

```powershell
adb devices -l
```

Expected state:

```text
<device-id>    device
```

If the state is `unauthorized`, put the headset on and accept the USB debugging prompt. If no device appears on Windows, install the Oculus ADB Drivers, unzip the package, then right-click `android_winusb.inf` and choose `Install`.

## 6. Verify the Project Export Preset

Open `Project > Export` in Godot. This repo already includes an Android preset named `Meta Quest`. Confirm these settings before deploying:

| Export setting | Expected value |
| --- | --- |
| Preset name | `Meta Quest` |
| Runnable | Enabled |
| Gradle Build / Use Gradle Build | Enabled |
| Export Format | APK for local headset testing |
| Package / Unique Name | A reverse-DNS package ID, currently `com.ruffo.projectpong` |
| Architectures | `arm64-v8a` enabled; other architectures disabled |
| XR Features / XR Mode | OpenXR |
| XR Features / Enable Meta Plugin | Enabled |
| Meta XR Features / Quest 2 support | Enabled |
| Meta XR Features / Quest 3 support | Enabled |
| Permissions / Internet | Enabled |

The checked-in OpenXR Vendors addon adds the Meta-specific export options. If the Meta XR feature section is missing, confirm `project-pong/addons/godotopenxrvendors` exists and that the project was opened in Godot 4.7.1 or newer.

Install the Android build template if `project-pong/android/` is missing:

1. Open `Project > Install Android Build Template`.
2. Click `Install`.
3. Leave the generated `project-pong/android/` directory untracked; it is local build output.

## 7. Configure Multiplayer Credentials When Needed

Practice mode and local Classic Match do not need Photon configuration. The `Online Arena` scene does.

For local editor testing, set the Photon Fusion App ID in the shell before launching Godot:

```powershell
$env:PHOTON_FUSION_APP_ID = "<your-photon-fusion-app-id>"
```

For headset builds, coordinate with the project maintainer before changing `fusion/connection/app_id` in `project-pong/project.godot`. Do not commit personal Photon App IDs, Meta App IDs, tokens, signing credentials, or invite target IDs.

The default private room is `project-pong-dev-room`. In editor or command-line launches, you can override it with:

```text
--pong-room=<room-name>
```

## 8. Deploy from Godot

This is the fastest path for iteration.

1. Connect the headset and confirm `adb devices -l` shows the device.
2. Open `project-pong/` in Godot.
3. Select the `Meta Quest` Android export preset.
4. Use Godot's one-click deploy/run button for Android.
5. Put on the headset when the app launches.

Pass criteria:

1. The app opens as immersive VR, not a flat Android window.
2. Head pose updates correctly.
3. Controller or hand markers follow tracked input.
4. Practice mode can grab, throw, and reset the ball.
5. `Online Arena` connects only when Photon credentials are configured.

## 9. Export an APK and Install It Manually

Create a local build output folder:

```powershell
New-Item -ItemType Directory -Force project-pong\builds
```

In Godot:

1. Open `Project > Export`.
2. Select `Meta Quest`.
3. Click `Export Project`.
4. Save a debug APK to `project-pong/builds/project-pong-debug.apk`.
5. Keep `Export With Debug` enabled for local development.

Install with ADB:

```powershell
adb install -r "project-pong\builds\project-pong-debug.apk"
```

Or install with Meta Quest Developer Hub:

1. Open MQDH.
2. Open `Device Manager`.
3. Confirm the headset is active.
4. Drag the APK into MQDH, or choose `Add Build`.
5. In the headset, open Library, then `Unknown Sources`, then launch ProjectPong.

## 10. Export from the Command Line

Godot supports headless command-line export. The target directory must already exist.

If `godot` is on your `Path`:

```powershell
New-Item -ItemType Directory -Force project-pong\builds
godot --headless --path project-pong --export-debug "Meta Quest" builds/project-pong-debug.apk
adb install -r "project-pong\builds\project-pong-debug.apk"
```

If you keep the Windows console editor in the repository root or another local tools folder, replace `godot` with that executable path:

```powershell
.\Godot_v4.7.1-stable_win64_console.exe --headless --path project-pong --export-debug "Meta Quest" builds/project-pong-debug.apk
```

Godot resolves the relative export path from the folder that contains `project.godot`, so `builds/project-pong-debug.apk` lands in `project-pong/builds/`.

## 11. Local Validation Without a Headset

From the repository root:

```powershell
.\tools\validate_codex.cmd
```

This runs Godot headlessly with XR disabled. It verifies that the project, scripts, and main scene load without requiring a headset. It does not verify Android export, Quest installation, OpenXR startup, tracking, or multiplayer hardware behavior.

## 12. Useful Debug Commands

List connected devices:

```powershell
adb devices -l
```

Watch Godot/OpenXR logs:

```powershell
adb logcat | Select-String "\[XR\]|godot|OpenXR|Photon"
```

Reinstall a local APK:

```powershell
adb install -r "project-pong\builds\project-pong-debug.apk"
```

Uninstall the debug package if signing keys conflict:

```powershell
adb uninstall com.ruffo.projectpong
```

## Troubleshooting

### `adb devices` shows no headset

- Confirm the USB cable supports data, not only charging.
- Put on the headset and accept the USB debugging prompt.
- On Windows, install the Oculus ADB Drivers.
- Restart ADB with `adb kill-server`, then run `adb devices -l`.
- If using MQDH, make sure MQDH and your terminal are using the same `adb` path.

### `adb devices` shows `unauthorized`

- Unlock and wear the headset.
- Accept the RSA/USB debugging dialog.
- Choose `Always allow from this computer`.
- Disconnect and reconnect USB if the prompt does not appear.

### Godot cannot export Android

- Confirm Godot 4.7.1 export templates are installed.
- Confirm `Java SDK Path` points to OpenJDK 17.
- Confirm `Android SDK Path` contains `platform-tools/adb`.
- Confirm Build-Tools 35.0.1, Platform 35, Command-line Tools latest, NDK 28.1.13356709, and CMake 3.10.2.4988404 are installed.
- Reopen Godot after changing environment variables or `Path`.

### App launches as a flat Android window

- Confirm the `Meta Quest` preset has XR Mode set to OpenXR.
- Confirm Use Gradle Build is enabled.
- Confirm the OpenXR Vendors addon exists in `project-pong/addons/godotopenxrvendors`.
- Confirm the Meta plugin is enabled in the export preset.
- Confirm Quest support is enabled in the Meta XR feature options.

### One-click deploy fails with a signing conflict

Uninstall the existing package from the headset and deploy again:

```powershell
adb uninstall com.ruffo.projectpong
```

This usually happens when an APK with the same package name was installed with a different debug or release key.

## Source References

- [Godot 4.7.1 stable downloads](https://godotengine.org/download/archive/4.7.1-stable/)
- [Godot 4.7 exporting for Android](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_android.html)
- [Godot 4.7 deploying OpenXR to Android](https://docs.godotengine.org/en/4.7/tutorials/xr/deploying_to_android.html)
- [Godot 4.7 command-line export](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html)
- [Android Studio downloads](https://developer.android.com/studio)
- [Android SDK Manager](https://developer.android.com/tools/sdkmanager)
- [Android NDK and CMake setup](https://developer.android.com/studio/projects/install-ndk)
- [Android Debug Bridge](https://developer.android.com/tools/adb)
- [Meta Quest device setup](https://developers.meta.com/horizon/documentation/native/android/mobile-device-setup/)
- [Getting started with Meta Quest Developer Hub](https://developers.meta.com/horizon/documentation/native/android/ts-mqdh-getting-started/)
- [Deploy APK builds with MQDH](https://developers.meta.com/horizon/documentation/native/android/ts-mqdh-deploy-build/)
- [Oculus ADB Drivers](https://developers.meta.com/horizon/downloads/package/oculus-adb-drivers/)
- [Godot OpenXR Vendors Plugin](https://store.godotengine.org/asset/godot-xr/godot-openxr-vendors-plugin/)
