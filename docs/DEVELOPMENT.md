# Development guide

## 1. Setup
| Need | For | Notes |
|---|---|---|
| Flutter (stable, 3.47 or later) | Everything | `export PATH="$HOME/develop/flutter/bin:$PATH"` or wherever it lives |
| Xcode + command-line tools | iOS builds, the C++ harness (`clang++`), icon resizing (`sips`) | `xcode-select --install` |
| Android SDK + NDK, JDK 17 | Android builds | Not available on the original dev machine, so Android code is unverified (see TESTING.md) |
| Python 3 | `tool/*.py`, `tool/serve_web.py` | Standard library only |
| Node.js (18 or later) | Web build's compiled AudioWorklet checks | `tool/test_audio_worklet.mjs` |

First run: `flutter pub get`, then `flutter analyze && flutter test`.

## 2. Everyday commands
```bash
flutter analyze                         # must stay at "No issues found"
flutter test                            # all Dart tests (headless)
flutter test test/dsp_safety_test.dart  # one file
native/build_and_test.sh                # C++ engine harness; add --lib to also build the shared library
flutter run                             # simulator / device
flutter build ios --simulator --debug --no-codesign
flutter build apk --debug               # needs the Android SDK

tool/build_web.sh                       # verified production PWA in build/web  (--base-href /sub/ for a sub-path)
python3 tool/serve_web.py [port]        # serve it with the production headers; prints a Wi-Fi URL
python3 tool/generate_icons.py          # regenerate every icon (web, iOS, Android) from one design
```
`native/build/` and `build/` are generated output; delete them freely.

## 3. Ground rules
Read [CLAUDE.md](../CLAUDE.md) first. In short:
- **Offline, always.** No network packages or APIs; allowed dependencies are `sqflite`, `path`, `path_provider`, `ffi`, `web`.
- **Safety numbers are law** (−3 dBFS ceiling, 4 s fades, 650 Hz Deep-calm cutoff, < 0.2 Hz visuals, pentatonic lock, 3 s two-corner
  unlock). Tests encode them; do not loosen a test to make a change pass.
- **No stubs or `TODO`s**, comments only where non-obvious, match the surrounding style.
- **Real-time code never allocates or locks** (`native/dsp_engine.cpp` `render`, and its Dart twin).
- Format only the files you touch (`dart format <files>`); formatting the whole tree can rewrap code and trip lints.

## 4. Recipes

### Add a new animation
1. Write `shaders/<name>.frag` using the shared header: `#version 460 core`, `#include <flutter/runtime_effect.glsl>`, the five
   uniforms in order (`uSize`, `uTime`, `uSpeed`, `uDim`, `uTouch`) and **use every one**. Keep motion well under 0.2 Hz, soft pastel
   colours, no strobing.
2. Register it in `pubspec.yaml` (`flutter: shaders:`).
3. Add a value to `ShaderKind` (`lib/core/models/sensory_state.dart`) and `VisualMode` (`lib/data/models.dart`).
4. Map them: `SensoryShaderView.assetFor`, `SessionScreen.visualFor`, and a Canvas painter case in `FallbackSensoryPainter`
   (also the picker thumbnail).
5. Add a `VisualOption` to `kVisualOptions` (`lib/ui/visual_catalog.dart`).
6. Add the file name to `test/shader_safety_test.dart`. `visual_picker_test.dart` checks the mapping automatically.
7. Look at it: `tool/build_web.sh`, serve it, and run a session. Check portrait and landscape.

### Add or change a long-press menu entry
It must change in **all** of: `web/manifest.json` (`shortcuts`), `android/…/res/xml/shortcuts.xml` (+ strings and a vector icon),
`ios/Runner/Info.plist` (`UIApplicationShortcutItems`), `LaunchMode` / `launchModeFrom` (`lib/ui/launch_intent.dart`) and the switch in
`HomeSosScreen._launchMode`. `test/native_shell_test.dart` fails until they agree.

### Add a database migration
1. Bump `LocalDatabase.schemaVersion`, add an `_addXxxColumns` step used by both `_onCreate` and `_onUpgrade` (`oldVersion < N`).
2. Extend the model (`toMap` / `fromMap` with safe defaults for old rows) and the repository.
3. Add a **hand-built old-version database** test in `test/data_layer_test.dart` proving existing data survives.
4. If the browser store needs new calls, extend `JsonDatabase` (it throws on anything unsupported) and `json_database_test.dart`.

### Change the audio engine
Change **both** implementations and keep them identical: `native/dsp_engine.{h,cpp}` and `PureDartDsp` in
`lib/core/audio/pure_dart_dsp.dart` (re-exported by `dsp_bridge.dart`). Then run `native/build_and_test.sh`,
`flutter test test/dsp_safety_test.dart test/voice_weave_test.dart` and `tool/build_web.sh` (also exercises the compiled AudioWorklet).
New control calls go through the lock-free queue; if the C API changes, update `native/audio_output_keep.cpp` (keeps symbols alive
in iOS release builds), `NativeDsp` and, if user-facing, the `AudioEngine` contract and `_NullAudio`-style test doubles.

### Add a caregiver setting
Add a field to `SensoryProfile` (+ migration), a control in `ParentScreen`, consume it where the session loads the profile
(`SessionScreen._loadProfile`) and cover it with a model round-trip test.

### Change the app icon
Edit the artwork in `tool/generate_icons.py`, run it, and run the tests. Do not hand-edit generated PNGs.

### Bump the version
`pubspec.yaml` `version:` **and** `lib/core/app_info.dart` default (a test enforces they match); add a `docs/CHANGELOG.md` entry.

## 5. Conventions
- Contracts (`sensory_state.dart`, `audio_engine.dart`, `voice_weave.dart`) are shared by every layer: change signatures
  deliberately and update all implementers and test doubles.
- Widget tests that touch SQLite or `JsonDatabase` should give each test its own store; shared in-memory databases leak rows.
- Prefer pure classes (`SessionInsights`, `IsoPrincipleController.snapshotAt`, `KioskLockLogic`) for logic, so it is unit-testable.
- Child-facing screens: no settings, no destructive actions, short labels, large targets.

## 6. Troubleshooting (development)
| Symptom | Cause / fix |
|---|---|
| `flutter: command not found` | Add the SDK `bin` to `PATH` for the shell |
| Web changes don't show | The service worker caches the old build. Close all tabs, or in DevTools → Application unregister the worker and clear caches |
| Service worker won't register on a LAN IP | Needs a secure origin: use `localhost` or HTTPS |
| `zsh: no matches found: --exclude=*.md` | Quote globs in shell commands |
| iOS icon looks old in the simulator | Uninstall the app, then reinstall (SpringBoard caches icons) |
| `Overriding declaration requires an 'override' keyword` in `SceneDelegate.swift` | Flutter's scene delegate already defines the method: mark it `override` and call `super` |
| Android build fails on `<monochrome>` | `compileSdk` must be 33+ (Flutter's default is) |
| A shader renders black / wrong | Every uniform must be used, in the documented order; check the web console and `flutter build` output (the shader compiler runs at build time) |
| macOS permission errors when a tool serves files from `~/Documents` | Serve a copy from another folder, or run `tool/serve_web.py` from your own terminal |
