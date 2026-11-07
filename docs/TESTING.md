# Testing guide

AuraSOS is a safety-sensitive app, so tests encode its promises (see [CLAUDE.md](../CLAUDE.md)) and every one runs
headless, with no device. Last full run: **208 Dart tests + the C++ engine harness, all passing**, `flutter analyze` clean.

## 1. Running
```bash
flutter analyze                  # static analysis (must report "No issues found")
flutter test                     # all Dart tests
flutter test test/<file>_test.dart
native/build_and_test.sh         # C++ engine harness (builds with clang++ -std=c++17 and runs it)
tool/build_web.sh                # also verifies the web output (tool/check_web_build.py)
flutter build ios --simulator --debug --no-codesign   # compiles Swift, shaders (Metal) and the iOS project
```
Run all of the above before a release. For a quick loop use `flutter analyze` and the one test file you are changing.

## 2. What the automated tests prove

| Area | File (tests) | It proves |
|---|---|---|
| **Audio safety** | `dsp_safety_test.dart` (13) | Peak never exceeds −3 dBFS (also under tap spam and preset cycling); no NaN/Inf; no click across start, stop and switch (max sample step < 0.005); fades are about 4 s and log-shaped; Brownian −6 dB/oct and pink −3 dB/oct (±1 dB, measured with a self-written FFT/Welch); SOS low-pass leaves > 30 dB less energy above 2 kHz; every touch note lands on its pentatonic pitch |
| | `voice_weave_test.dart` (4) | Phrases play on schedule and pause between; cleared or disabled slots stay silent; hostile input (NaN, huge values, bad slots) cannot break the ceiling |
| | `native/test/dsp_test.cpp` | The same properties on the real C++ engine, plus determinism and kalimba attack |
| **Protocol** | `iso_principle_test.dart` (14) | Exact BPM / cutoff / speed / dimmer at the phase boundaries; monotonic ramps; determinism; deep-crisis behaviour; the stateful runner |
| **Kiosk** | `kiosk_lock_test.dart` (14) | Unlock needs both corners for 3000 ms (2999 fails); one corner never works; release resets; 50 random taps per second for 60 s never unlock or throw; the widget version too |
| **Data** | `data_layer_test.dart` (22) | Profile and session round-trips, ordering, reports (CSV quoting, Markdown sections), and **migrations from hand-built v1, v2 and v3 databases** |
| | `json_database_test.dart` (8) | The browser store behaves like SQLite for everything the repository uses; survives reloads; recovers from a corrupt store; rejects unsupported queries |
| | `session_insights_test.dart` (7), `insights_screen_test.dart` (3) | The "What helps" maths (rates, best mode needs 3 ratings, time of day, triggers) and the screen, including tagging a session |
| | `profile_limits_test.dart` (5) | The strictest of high-cut slider, "soften high tones" and `Block frequencies > N Hz` wins |
| | `voice_library_test.dart` (6), `wav_codec_test.dart` (7) | WAV encode/decode/resample and malformed input; phrase storage and bounds |
| **UI** | `home_labels_test.dart` (10) | Mode names, SOS naming the chosen mode, **no overflow at six screen sizes** (320×568 up to 1180×820), session mode chip fades |
| | `launch_and_about_test.dart` (8) | Shortcut launches start the right session; About section |
| | `visual_picker_test.dart` (9) | Catalogue completeness, one shader per animation, selection, preview open/close, small-phone layout |
| | `shader_safety_test.dart` (19) | Every shader has the shared header and uniforms, no fast oscillation, lanterns background is pure black, all registered |
| **Offline & publishing** | `offline_invariants_test.dart` (9) | No network packages, APIs or URLs in `lib/`; dependency allow-list; no `INTERNET` permission; no external host in `web/` |
| | `pwa_shell_test.dart` (7), `publish_readiness_test.dart` (21) | Manifest, icons, no inline scripts, strict CSP consistent across `index.html`, `_headers` and every hosting config, privacy page, favicon, version matches `pubspec.yaml` |
| **Cross-platform shell** | `native_shell_test.dart` (22) | Icons exist at every required size on iOS and Android; the iOS icon has no alpha; the web, Android and iOS long-press menus match in modes, order and names; dark launch screens; native channel code agrees with Dart; the shortcut channel works both ways and never interrupts a running session |

### Reading a failure
- A **safety test** failing means a promise was broken. Fix the code, not the threshold.
- A **drift test** (`native_shell_test`, `publish_readiness_test`) fails when two copies of a fact disagree; it tells you which files to align.
- Widget tests that need a real database use `tester.runAsync`; give each test its own store.

## 3. Build-time checks that are not unit tests
- `tool/check_web_build.py`: required files, a stamped service worker whose every precached file exists, manifest icons and shortcuts,
  no inline scripts, CSP equals `_headers`, no external URL in shipped text files, the version compiled in.
- The shader compiler runs at build time; a bad shader fails `flutter build`.
- `tool/test_audio_worklet.mjs`: runs the compiled Dart DSP and real worklet processor without browser UI globals;
  checks every preset, rapid touches, sample steps < 0.005, the -3 dBFS ceiling, stop fades, voice commands and disposal.
  `tool/build_web.sh` runs it automatically (Node.js required).

## 4. Manual checks (what machines cannot judge)
Do these on a **physical phone and tablet**, volume low, before giving the app to a child.

**Sound**
1. Tap SOS: the sound fades in over about 4 seconds, with no click or pop. Let it run past 3 and 8 minutes: tempo and brightness should ease.
2. Switch modes, then unlock and stop: the sound fades out, never cuts.
3. Spam-tap the canvas: no harshness or clipping. (Very fast tapping is smoothed by design.)
4. Check the maximum volume cap at a low and a high setting.
5. iPhone: silent switch on mutes web audio but not the native app.
   Web: tap and drag repeatedly with each animation active; playback should remain continuous. Repeat offline after installation.

**Kiosk and screen**
6. The back gesture and swipes do nothing during a session; unlocking needs both top corners for 3 seconds.
7. The screen stays awake during a session (phone apps).
8. Each animation: no flicker, no sudden brightness change. The black-screen mode is fully black.

**Offline**
9. Airplane mode, fresh launch: everything works. (Web: install first over HTTPS, see PUBLISHING.md.)

**Voice (phone apps)**
10. Record a phrase, enable weaving, run a session: the voice appears quietly, then the calm sound is intact afterwards (iOS audio-session switch).

**Menu and icons**
11. Long-press the icon: four entries; each starts the right session. With the app already open on its home screen, a tap starts it too.
12. The icon and launch screen are the dark heart design, not white or the Flutter logo.

**Caregiver**
13. Change each setting, save, and confirm the next session honours it; copy a report and read it.

## 5. Known gaps
- **Android has never been compiled or run** (no SDK on the original machine): speaker output (AAudio + CMake), keep-awake, microphone
  capture, the shortcut menu and the adaptive icon are reviewed by hand and XML-validated only. Build and run checks 1 to 13 on Android first.
- No physical-device or release-build testing yet on iOS or Android.
- Web audio runs in an AudioWorklet; physical-device listening under heavy animation and touch load still needs checking.
- No automated test can judge whether sound and visuals are actually *calming*; that needs real children, caregivers and clinicians.

## 6. Suggested CI
```bash
flutter pub get
flutter analyze && flutter test
native/build_and_test.sh          # on a macOS or Linux runner with clang
tool/build_web.sh                 # fails on any publishability problem
```
