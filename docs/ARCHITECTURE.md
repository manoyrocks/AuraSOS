# AuraSOS architecture

How the app is put together. For the rules it must obey, see [CLAUDE.md](../CLAUDE.md); for how to work on it,
[DEVELOPMENT.md](DEVELOPMENT.md).

## 1. Shape of the system

```
                       ┌─────────────────────────── lib/ui ───────────────────────────┐
                       │ HomeSosScreen ─▶ SessionScreen ─▶ ChildTouchLockKiosk         │
                       │ ParentScreen · InsightsScreen · VisualPicker/Preview          │
                       └──────┬───────────────────────┬──────────────────────┬─────────┘
                              │                       │                      │
              AudioEngine (contract)           ShaderKind / shaders     SensoryProfileRepository
        ┌─────────┼───────────────┐                                              │
   NativeDsp   PureDartDsp   WebAudioEngine                          ┌──────────────┴────────────┐
 (FFI → C++)   (pure Dart)   (Dart + Web Audio)                LocalDatabase (SQLite)    JsonDatabase
   │ AAudio / AudioQueue                                       iOS · Android              (web localStorage)
```

One Flutter codebase; one audio engine design implemented twice (C++ and Dart) that must stay behaviourally
identical; one set of fragment shaders; one data model with two storage backends.

## 2. Code map

| Area | Key files | Responsibility |
|---|---|---|
| Shared contracts | `lib/core/models/sensory_state.dart`, `lib/core/audio/audio_engine.dart`, `voice_weave.dart` | `SessionPreset`, `IsoPhase`, `IsoSnapshot`, `ShaderKind`, `EfficacyRating`; the `AudioEngine` and `VoiceWeaveEngine` interfaces |
| Audio (native) | `native/dsp_engine.{h,cpp}`, `native/audio_output_*` | Real-time synthesis and the platform speaker callbacks |
| Audio (Dart) | `lib/core/audio/dsp_bridge.dart` (`PureDartDsp`), `native_dsp.dart` (FFI), `web_audio_engine.dart`, `engine_factory*.dart` | Dart twin of the engine; FFI binding; browser output; choosing the backend |
| Protocol | `lib/core/engine/iso_principle_controller.dart` | The three-stage calm-down as a pure function of elapsed time |
| Data | `lib/data/*` | Profile and session storage, insights, reports, voice files |
| UI | `lib/ui/*` | Screens and widgets |
| Visuals | `shaders/*.frag`, `lib/ui/widgets/sensory_shader_view.dart`, `lib/ui/visual_catalog.dart` | The eight animations, their Canvas fallbacks, and the caregiver catalogue |
| Platform glue | `android/…/MainActivity.kt`, `ios/Runner/AppDelegate.swift`, `SceneDelegate.swift` | Method channels (see §8) |
| Web shell | `web/*`, `tool/build_web.sh`, `tool/check_web_build.py`, `deploy/*` | PWA, offline service worker, security headers, publishing |

`lib/main.dart` wires everything: opens the database, creates the engine (`DspBridge.create()`), loads saved voice
phrases, attaches the launch channel, and shows `HomeSosScreen`.

## 3. The audio engine

### Why a custom engine
Children with auditory hypersensitivity need guarantees a generic player cannot give: no sudden starts or stops, a hard
level ceiling, no high-frequency transients, and notes that can never clash. So audio is synthesised in real time
rather than played from files, which also keeps the app tiny and fully offline.

### Signal flow (per sample, 48 kHz stereo float32)
```
 stems (gain per preset, crossfaded)                           caregiver voice phrase (optional)
 ├ Brownian noise  (−6 dB/oct, 20 Hz DC block)                        │ 250 ms raised-cosine edges
 ├ Pink noise      (−3 dB/oct, Paul Kellet; band-passed 500–2500 Hz)  │
 ├ Marimba/cello pulse   (4 + 2 voices, at the Iso BPM)               │
 ├ Pad                   (5 detuned pentatonic partials)              │
 ├ Heartbeat             (60–120 Hz lub-dub)                          │
 ├ 110 Hz drone                                                       │
 ├ Water texture                                                      │
 └ Kalimba touch synth   (8 voices, ≥ 45 ms cosine attack)            │
          └───────────────────────── sum ◀────────────────────────────┘
   → master low-pass (smoothed cutoff set by the preset and the Iso controller, never above the caregiver's high-cut)
   → master fade (4 s logarithmic) × volume cap
   → soft-knee compressor (−9 dB, 8 dB knee, 4:1)
   → brickwall at 0.7079457 (−3 dBFS)  →  slew guard (max step 0.0045/sample)  →  output
```
Design points:
- **4-second logarithmic fades** (192 000 samples) for start, stop and preset switches; fades are symmetric so a reversal
  mid-fade stays continuous.
- **Smoothed everything.** Filter cutoffs, stem gains and iso parameters glide; there is no zipper noise.
- **The slew guard** is the last line of defence: whatever happens upstream, no sample may differ from the previous by more
  than 0.0045, so a click or pop is mathematically excluded (and tested).
- **Pentatonic lock.** The touch instrument has exactly ten pitches (C-major pentatonic over two octaves); a touch's
  horizontal position picks the degree. The velocity is capped; eight voices with voice stealing cannot clip.
- **Presets** (`SessionPreset`): `isoDownRegulator`, `deepCrisisAnchor`, `focusClassroom`, `calmStim`. Each defines stem
  targets and a base low-pass; the Iso controller then drives tempo, cutoff and stem weights over time.

### Threading and the command queue (no allocation, no locks in `render`)
Control calls (`start`, `stop`, `switchPreset`, `applyIso`, `setProfileLimits`, `triggerNote`, voice commands) are pushed
into a 1024-entry **lock-free ring buffer**. `render()` drains it at the top of each block and then advances time in
16-sample control steps (`kCtl`). The platform audio thread calls `render` directly; Dart never sits on the real-time path.
`render` handles any block size, so Android's AAudio callback, iOS's AudioQueue buffers and test code all use it unchanged.

### Familiar voice layer
Up to four 6-second phrases (mono, 48 kHz). Phrases are copied into a **double buffer** on the calling thread and
published to the render thread by a queue command, so `render` never allocates. A scheduler counts down only while the sound
is fully audible, then plays the next phrase round-robin with 250 ms edges and waits the chosen interval. The voice passes
through the same master filter, fade, compressor and limiter as everything else. Phrases are de-essed and normalised in Dart
(`FamiliarVoiceProcessor`) before loading; load them while no session is running.

### Three backends, one behaviour
| Backend | Used on | Notes |
|---|---|---|
| `NativeDsp` | iOS, Android, desktop | FFI to the C++ library; the library also opens the speaker (`aura_audio_open`). The only file importing `dart:ffi` is `native_dsp.dart` |
| `PureDartDsp` | Tests, fallback | A faithful port of the C++ engine; deterministic and headless; the reference for most tests |
| `WebAudioEngine` | Browser | Runs the separately compiled `PureDartDsp` inside an `AudioWorkletNode`, off the UI thread. Created after the first user gesture; commands queue in order while the module loads. `playback: false` supports synchronous headless renders |

`DspBridge.create()` picks the backend through conditional imports (`engine_factory*.dart`). **The C++ and Dart engines must
be changed together** (see DEVELOPMENT.md); `test/dsp_safety_test.dart`, `voice_weave_test.dart` and `native/test/dsp_test.cpp`
assert the same properties on both.

## 4. The Iso-Principle controller
`IsoPrincipleController.snapshotAt(elapsedMs)` is a **pure function** returning an `IsoSnapshot`: phase, BPM, low-pass
cutoff, shader speed, dimmer alpha and stem weights.

| Phase | Time | BPM | Cutoff | Shader speed | Dimmer |
|---|---|---|---|---|---|
| Match | 0–180 s | 104 | 2000 Hz | 1.0× | 0 |
| Thinning | 180–480 s | 104→72 | 2000→900 Hz | 1.0→0.5× | ramps 0→0.40 over the last 60 s |
| Baseline | 480 s + | 58 | 500 Hz | 0.25× | 0.40 |

Rhythm weight crosses over to pads through Thinning; heartbeat and Brownian gain ramp in over its last minute. The stateful
runner ticks at 60 Hz, calls `applyIso` on the engine and reports snapshots to the UI (shader speed, dimmer, the mode chip).
*Deep crisis* mode uses a fixed snapshot: no rhythm, Brownian noise, 650 Hz cutoff. Because the function is pure, tests can check
any instant without waiting.

## 5. Session flow
1. **Home** (`HomeSosScreen`): buttons launch `SessionScreen` synchronously (no awaits before the first frame; the SOS mode
   choice is read in the background). It also handles shortcut launches (`?mode=`, native menus) via `LaunchMode`.
2. **Session** (`SessionScreen`): starts audio (4 s fade-in), starts the controller, loads the caregiver profile in the
   background (volume cap, high-cut, brightness cap, animation, focus length, voice settings), logs a session row, and shows
   the chosen animation inside the kiosk with the sub-OS dimmer on top. It keeps the screen awake where supported.
3. **Kiosk** (`ChildTouchLockKiosk`): hides system UI, blocks back, turns touches into ripples and throttled plucks
   (≈ 8 per second, ≤ 12 ripples). The unlock logic (`KioskLockLogic`) is separate and fully testable: both corner zones
   (96 px) held simultaneously and continuously for 3000 ms; either release resets.
4. **Unlock → rating:** a one-tap 🙂/😐/😣 prompt. Choosing stops audio with the 4 s fade, finishes the session row (duration,
   phase reached) and stores the rating.

## 6. Visuals
- **Eight fragment shaders** in `shaders/`, all Impeller-compatible GLSL with the same uniforms in a fixed float order:
  `uSize.x, uSize.y, uTime, uSpeed, uDim, uTouch.x, uTouch.y, uTouch.z`. Every shader uses every uniform so the compiler
  cannot strip one and shift the order. Luminance motion is far below 0.2 Hz; nothing strobes.
- `SensoryShaderView` loads the shader and advances time scaled by the protocol speed. If loading fails it draws a **Canvas
  fallback** (`FallbackSensoryPainter`), so the child never sees an error. The same painter produces the picker thumbnails.
- `VisualMode` (stored per child) maps to a `ShaderKind` through `SessionScreen.visualFor`; `kVisualOptions`
  (`lib/ui/visual_catalog.dart`) is the caregiver catalogue; `VisualPicker` and `VisualPreviewScreen` are the UI.
- The 3D-style animations (`crystal_polygons` ray-marches three low-poly solids; `starfield_3d`, `aurora_ribbons`,
  `mandala_polygons`) are tuned for a low-arousal, pastel look.

## 7. Data

### Schema (SQLite, version 4; additive migrations)
`sensory_profiles`: `id, child_name, master_volume_cap, brightness_cap, high_cut_hz, disable_water, disable_high_piano,
blacklist (JSON), preferred_preset, voice_enabled, voice_gain, voice_interval_sec, visual_mode, focus_minutes`
`meltdown_logs`: `id, started_at, duration_sec, preset, reached_phase, rating, note, trigger_tags (JSON)`

| Version | Added |
|---|---|
| 1 | Profiles and session logs |
| 2 | Familiar-voice settings |
| 3 | `visual_mode`, `focus_minutes` |
| 4 | Session `note` and `trigger_tags` |

Every migration has a hand-built old-database test in `test/data_layer_test.dart`.

### Layers
- `SensoryProfileRepository`: `activeProfile`, `saveProfile`, `startSessionLog`, `finishSessionLog`, `rateSession`,
  `annotateSession`, `sessions`.
- `LocalDatabase` wraps SQLite. In the browser, `LocalDatabase.openJson` wraps **`JsonDatabase`**, a tiny `Database`
  implementation backed by one JSON document in `localStorage`. It supports only what the repository uses (`query` with
  `orderBy`/`limit`, `insert` with replace, `update … where id = ?`) and throws on anything else, rather than misbehave.
- `SessionInsights` (pure) computes the "What helps" figures; `ClinicalReportExporter` builds the CSV and Markdown reports;
  `VoiceLibrary` stores processed phrases as WAV files (mobile only).
- Derived settings live with the model: `SensoryProfile.effectiveHighCutHz` combines the slider, the "soften high tones"
  switch and any `Block frequencies > N Hz` rule, taking the strictest.

## 8. Platform integration (no plugins)
All native features use small `MethodChannel`s so no pub package (and no network-capable code) is needed.

| Channel | Methods | Native side |
|---|---|---|
| `aurasync/screen` | `keepAwake(bool)` | `isIdleTimerDisabled` / `FLAG_KEEP_SCREEN_ON` |
| `aurasync/voice` | `start`, `stop`, `cancel` | `AVAudioRecorder` / `AudioRecord`; returns a 16-bit mono WAV path and its sample rate |
| `aurasync/launch` | `initialMode` (Dart→native), `launchMode` (native→Dart) | Android intent extra `aurasync.mode`; iOS quick actions via `SceneDelegate` |

The channel and bundle identifiers keep the original `aurasync` name on purpose: they are internal, and renaming them would
orphan installed apps and saved data. The product name is AuraSOS.

**Icons and menu.** One design (heart and ripples on a dark gradient), generated by `tool/generate_icons.py` for web, iOS
(opaque 1024 master and every size) and Android (legacy, adaptive and themed-monochrome). The long-press menu is declared in
`web/manifest.json`, Android `xml/shortcuts.xml` and iOS `Info.plist`, kept identical by `test/native_shell_test.dart`.
Shortcuts only start a session from the home screen.

## 9. The web build
- **Conditional imports** keep `dart:ffi` and `dart:io` out of the browser: `engine_factory*.dart`, `app_database*.dart`,
  `pwa_status*.dart`. `package:web` provides `localStorage` and Web Audio.
- **Offline.** Flutter's own service worker is deprecated (it only unregisters itself), so `web/aura_sw.js` precaches every
  file (about 41, 25 MB, mostly the CanvasKit renderer), versioned by a content hash that `tool/build_web.sh` stamps in. A new
  version waits until all tabs close, so a running session is never swapped (`skipWaiting` is forbidden by a test).
- **Security.** A strict Content-Security-Policy (same-origin only, no inline script, no `eval`), defined once in
  `web/_headers`, repeated in a `<meta>` for hosts that cannot set headers, and copied into every `deploy/*` config.
  Inline script and style live in `web/pwa_init.js` and `web/splash.css` to keep the policy strict.
- **Verification.** `tool/check_web_build.py` fails the build on missing files, an unstamped service worker, inline scripts,
  a policy mismatch or any external URL.
- **Differences from mobile:** no voice recording, no report file saving, no keep-awake; audio renders on the main thread.

## 10. Invariants and where they are enforced
| Invariant | Enforced by |
|---|---|
| Fully offline: no network packages, APIs or URLs | `test/offline_invariants_test.dart`, `publish_readiness_test.dart`, `tool/check_web_build.py` |
| Peak ≤ −3 dBFS; no clicks; 4 s fades | `test/dsp_safety_test.dart`, `voice_weave_test.dart`, `native/test/dsp_test.cpp` |
| Brown/pink noise slopes; SOS low-pass; pentatonic lock | `test/dsp_safety_test.dart`, `native/test/dsp_test.cpp` |
| Iso-Principle timing and values | `test/iso_principle_test.dart` |
| Kiosk cannot be unlocked by tapping | `test/kiosk_lock_test.dart` |
| Shaders safe and registered | `test/shader_safety_test.dart`, `visual_picker_test.dart` |
| Data migrations and storage backends | `test/data_layer_test.dart`, `json_database_test.dart` |
| Same icons and menu on every platform | `test/native_shell_test.dart`, `pwa_shell_test.dart` |
| Publishable web output | `test/publish_readiness_test.dart`, `tool/check_web_build.py` |
