# AuraSOS — Clinical & Architectural Constitution

100% offline Flutter app (+ native C++17 DSP, GLSL fragment shaders, SQLite) for children with ASD:
Meltdown SOS, Focus/Classroom, Calm/Stim canvas. Source research/PRD: `aurasync_complete_research_prd_multi_agent_prompts_gemini_codex_claude_code.md`.
**Docs:** `README.md` (overview and index), `docs/USER_GUIDE.md`, `docs/ARCHITECTURE.md`, `docs/DEVELOPMENT.md`, `docs/TESTING.md`,
`docs/PUBLISHING.md`, `docs/CHANGELOG.md`. Keep them in step with the code; update the relevant one in the same change.
**Naming:** the product is **AuraSOS**; internal identifiers (package `aurasync`, bundle id `com.aurasync.aurasync`, channels `aurasync/*`, storage key
`aurasync.db`) deliberately keep the original name so installs and saved data survive. Do not rename them without a migration plan.

## 1. Offline / air-gapped (non-negotiable)
- No network packages (`http`, `dio`, `webview_flutter`, analytics, remote fonts). No `android.permission.INTERNET`. No ads, telemetry, CDNs.
- Allowed deps only: `sqflite`, `path`, `path_provider`, `ffi`, `web` (+ dev: `sqflite_common_ffi`, `flutter_test`).
  `web` is only the browser-API binding (localStorage, Web Audio) for the PWA build; it must never be used for networking.
  No `fetch` / `XMLHttpRequest` / beacons in `lib/` (enforced by `test/offline_invariants_test.dart`).

## 2. Acoustic safety laws
- Sample rate 48 000 Hz, stereo float32. Every Play / Pause(stop) / SOS interrupt / preset switch passes through a 4.0 s
  (192 000-sample) logarithmic crossfade. Max sample-to-sample delta across transitions < 0.005.
- Master brickwall limiter ceiling −3.0 dBFS = 0.70794578 linear. Nothing may exceed it, ever.
- Meltdown SOS default low-pass ceiling 650 Hz (Q 0.7071). Nothing > 2 000 Hz audible in SOS.
- Brownian noise −6 dB/oct (leaky integrator, DC-blocked 20 Hz); Pink −3 dB/oct (Paul Kellet 7-state). Prosody band-pass 500–2 500 Hz; trigger notch.
- Stim instrument: C-Major Pentatonic only, `[130.81,146.83,164.81,196.00,220.00,261.63,293.66,329.63,392.00,440.00]` Hz
  (degree index 0..9), 8-voice polyphony with voice stealing, >= 45 ms cosine attack, velocity-capped.
- Filter coefficient changes are smoothed (no zipper noise).

## 3. Iso-Principle engine (deterministic, pure function of elapsed ms)
| Phase | Time | BPM | LPF | Shader speed | Other |
|---|---|---|---|---|---|
| 1 Match | 0–180 s | 104 | 2000 Hz | 1.0x | marimba/cello rhythmic stem |
| 2 Thinning | 180–480 s | 104→72 linear | 2000→900 linear | 1.0→0.5x (reach 0.5x) | rhythm stem crossfades into pads |
| 3 Baseline | 480 s+ | 58 | 500 Hz | 0.25x | sub-bass lub-dub heartbeat 60–120 Hz + Brownian noise, dimmer 0.40 |
Deep-Crisis preset bypasses rhythm: Brownian + 110 Hz drone, LPF 650 Hz.

## 4. Shaders (all `< 0.2 Hz` luminance oscillation, no strobing; uniforms: `uSize(vec2) uTime uSpeed uDim (+ uTouch)`)
`shaders/bioluminescent_tunnel.frag`, `classroom_bubbles.frag`, `oled_lanterns.frag` (pure #000000 bg), `breathing_orb.frag` (4 s inhale, 6 s exhale).
Caregiver-selectable 3D-style animations (same uniforms and the same < 0.2 Hz rule): `crystal_polygons.frag` (raymarched low-poly solids),
`starfield_3d.frag`, `aurora_ribbons.frag`, `mandala_polygons.frag` (polygon rings in perspective). Each uses every uniform so the float order
stays stable, is soft and pastel (never neon), and has a Canvas fallback painter in `FallbackSensoryPainter` that doubles as the picker thumbnail.
Adding an animation = shader + `ShaderKind` + `VisualMode` + `kVisualOptions` entry + `pubspec.yaml` + `test/shader_safety_test.dart`.
Impeller-compatible GLSL: `#version 460 core`, `#include <flutter/runtime_effect.glsl>`, `out vec4 fragColor`.

## 5. Child touch-lock kiosk
- Engages on session start; no visible close/settings; system UI hidden. Touch → water ripple + kalimba pluck (throttled).
- Unlock: BOTH top-left (x<96,y<96) and top-right (x>w-96,y<96) held simultaneously, continuously, 3000 ms. Releasing either resets. Random tapping can never unlock.
- Sub-OS dimmer overlay 2 %–100 % luminance (0–98 % black alpha).

## 6. Code rules
- No stubs, no `TODO`, no placeholder comments. Match surrounding style; comments only where non-obvious.
- Shared contracts (do not change signatures without the orchestrator): `lib/core/models/sensory_state.dart`, `lib/core/audio/audio_engine.dart`.
- Dart: null-safe, `flutter_lints`. Native: C++17, zero allocation in the audio callback, extern "C" API.
- Tests must be headless (no device): DSP via pure-Dart fallback (`PureDartDsp`) and via a C++ test harness in `native/test/`.

## 7. Architecture notes (current)
- **Audio path:** `DspBridge.create()` returns `NativeDsp` (FFI to `native/dsp_engine.cpp`, platform thread pulls audio
  via `native/audio_output_*`) or the pure-Dart twin `PureDartDsp`. Both implement `AudioEngine` and `VoiceWeaveEngine`.
  The twin must stay behaviourally identical to the C++ engine; change both and their tests together.
- **No plugins for platform features.** Keep-awake (`aurasync/screen`), microphone capture (`aurasync/voice`) and app-icon shortcut launches
  (`aurasync/launch`) are small MethodChannels in `AppDelegate.swift` / `MainActivity.kt`. Do not add pub packages for them (offline allow-list in §1).
- **Real-time rule:** nothing allocates or locks in `render`. Control calls go through the lock-free command queue; the voice
  layer double-buffers phrases and publishes them by queue command.
- **Data:** SQLite schema is versioned (`LocalDatabase.schemaVersion`, now 4). Migrations are additive and each has a
  hand-built old-database test in `test/data_layer_test.dart`; add one for every bump.
- **Caregiver gate:** 3 s hold on the home screen gear. Child-facing screens contain no text and no settings.
- **Tests:** headless; widget tests that touch SQLite must use their own database file (a shared in-memory database leaks
  rows between tests).
- **Unverified here:** all Android native code, and any physical-device behaviour. See `docs/TESTING.md` (manual checklist and known gaps).
- **Web (PWA) build:** `dart:ffi` and `dart:io` code is behind conditional imports (`engine_factory.dart`, `app_database.dart`);
  `native_dsp.dart` is the only FFI file. In the browser `WebAudioEngine` wraps `PureDartDsp` and `JsonDatabase` replaces SQLite
  (it supports only what the repository calls and throws on anything else). Build with `tool/build_web.sh` (bundled CanvasKit
  and fonts, no CDN). Flutter's own service worker is deprecated, so `web/aura_sw.js` provides offline caching; it is stamped
  with a content-hash version at build time and must never call `skipWaiting`.
- **Publishing:** `docs/PUBLISHING.md`. The CSP is defined once in `web/_headers`; `index.html` carries the same policy in a `<meta>`
  and `deploy/*` repeat it (all checked by `test/publish_readiness_test.dart`). Keep `index.html` free of inline scripts/styles (put
  them in `web/pwa_init.js` / `web/splash.css`). `tool/build_web.sh` must pass `tool/check_web_build.py` before anything is published.
  Bump the version in `pubspec.yaml` and `lib/core/app_info.dart` together.
- **Icons and app-icon menu are shared across web, Android and iOS.** Edit the artwork in `tool/generate_icons.py` and rerun it; never
  hand-edit generated PNGs. A new menu entry must be added to `web/manifest.json`, `res/xml/shortcuts.xml` (+ `strings.xml`, a vector
  icon), `Info.plist`, `LaunchMode`/`launchModeFrom`, and the home screen switch together (`test/native_shell_test.dart` enforces it).
  Shortcuts start sessions only from the home screen; they must never interrupt a running session.

