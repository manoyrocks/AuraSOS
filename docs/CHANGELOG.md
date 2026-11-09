# Changelog

Format: newest first. Versions follow `pubspec.yaml`. Keep entries in plain language.

## Unreleased
- **Sound is 30% louder.** A fixed make-up gain of 1.3 sits after the volume cap and before the compressor, so it applies at every volume setting. The −3 dBFS ceiling, compressor and click-free guard are unchanged.
- **Android 7 and newer.** Speaker output moved from AAudio (API 26+) to OpenSL ES, so the app now installs on Android 7.0 (API 24) and up.
- **Android icon set completed.** Added round launcher icons (`ic_launcher_round`, all densities plus the adaptive-round XML) with `android:roundIcon` in the manifest, and the 512 × 512 Google Play listing icon at `android/store/ic_launcher_512.png`. All are produced by `tool/generate_icons.py`.
- **Loader icon.** A soft breathing heart (4 s in, 6 s out, still when the device asks for reduced motion) replaces the stock spinner in the caregiver area and Insights (`AuraLoader`), the web start-up splash, and the Android 12+ launch splash (`ic_splash_animated`, under 1 s).
- **More reliable sound in the browser.** The web app now unlocks audio on every kind of touch (including tap release), keeps listening so sound recovers after a call or switching apps, asks iPhone Safari to play as media so the silent switch no longer mutes it (iOS 16.4+), and shows **"Tap the screen to turn on sound"** while the browser is still holding sound back.
- The default **maximum volume** is now 80% (was 60%) for new profiles. Saved profiles keep their own value. The −3 dBFS output limit is unchanged.

## 1.0.0 (2026-10-22): first release
The first complete version of **AuraSOS** (originally built under the working name AuraSync).

### Calming sessions
- One-tap **SOS** with the three-stage Iso-Principle calm-down (match, ease, settle over about 12 minutes), **Deep calm**
  (brown noise and a low drone, no rhythm), **Focus** with a vanishing rainbow timer, and **Play & calm** touch canvas.
- Real-time sound engine: Brownian and pink noise, rhythm, pads, heartbeat, drone, water texture, and a pentatonic kalimba
  that can never play a wrong note.
- Sensory safety: 4-second fades on every start, stop and switch; −3 dBFS limiter; click-free output; low-pass limits; visuals far
  below 0.2 Hz.
- **Child touch-lock** kiosk (unlock by holding both top corners for 3 seconds) and a sub-OS screen dimmer.
- A quiet mode and stage label during sessions that fades away.

### Visuals
- Ten animations selectable per child, with a full-screen preview: crystal polygons (3D), polygon mandala, starfield, aurora,
  light tunnel, rising bubbles, lanterns (pure black background), breathing orb, automatic, and black screen (sound only).
- Redesigned home screen with custom-drawn icons, gradient buttons, mode names, and portrait and landscape layouts.

### Caregiver tools
- Caregiver area behind a 3-second hold: volume and brightness caps, high-frequency cut, water and high-tone switches,
  custom rules, SOS mode, focus length, animation.
- **Familiar voice:** record up to four phrases (phone apps) and weave them in quietly during sessions.
- **What helps:** efficacy per mode, time of day, common triggers, and per-session trigger tags and notes.
- **Reports** for a BCBA or OT: CSV and Markdown, copy or save.
- About section: version, offline status (web), privacy summary.

### Platforms
- iOS and Android apps with a native C++ audio engine, speaker output, keep-screen-awake and background audio (iOS).
- **Installable offline PWA**: Web Audio engine, `localStorage` storage, offline service worker, strict Content-Security-Policy and security
  headers, privacy page, `?mode=` shortcuts, hosting configs (Netlify, Cloudflare, Firebase, Vercel, GitHub Pages, nginx, Apache) and a
  verified build script.
- One icon and one long-press menu (SOS, Focus, Play & calm, Deep calm) on web, Android and iOS; dark launch screens.

### Quality
- 208 automated tests plus a C++ engine harness; static analysis clean. Tests cover audio safety, the protocol, the kiosk, data migrations, UI at
  many screen sizes, offline invariants, publishing readiness and cross-platform consistency.

### Known limitations
- Android code has not been compiled or run; no physical-device or release-build testing yet.
- Web audio renders on the main thread; no voice recording, report file saving or keep-awake on the web.

### Fixed during development (notable)
- The light-tunnel animation had a visible seam where its angle wraps; its noise now tiles around the circle.
- The stacked rating bars in What helps collapsed to zero height; fixed and covered by a test.
- Kiosk hold timing used a wall clock and was untestable; it now follows frame time.
