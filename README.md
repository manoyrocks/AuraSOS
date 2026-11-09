# AuraSOS

A calming aid for children with autism: sensory-safe sound and slow, gentle visuals, with a one-tap
**SOS** for meltdowns. It works **fully offline** (no accounts, ads, analytics or network access)
and runs on **iOS, Android and the web (installable PWA)** from one Flutter codebase, with a native
C++ audio engine.

> **Not a medical device.** AuraSOS is a calming aid. It does not diagnose or treat anything, and
> its reports are caregiver observations for discussion with a qualified professional.

## Highlights
- **One-tap SOS.** A gradual, three-stage calm-down (the Iso-Principle): it first matches the child's
  elevated state, then slows tempo, softens tone and dims the screen over about 12 minutes. A
  *Deep calm* mode skips rhythm entirely (low brown noise and a soft drone).
- **Focus** with a vanishing rainbow timer, and **Play & calm**, a safe stimming canvas where touches
  make ripples and soft pentatonic notes (it is impossible to play a wrong note).
- **Sensory safety built in.** Every start, stop and switch fades over 4 seconds; output is limited
  to −3 dBFS; calming sound is low-passed (2 kHz at most, narrowing to 500 Hz as the calm-down
  progresses and 650 Hz in Deep calm); all visuals move far slower than 0.2 Hz (no flicker).
- **Child touch-lock.** A session cannot be left by tapping or swiping; a parent holds both top
  corners for 3 seconds to unlock.
- **Caregiver area** (hold the faint gear for 3 seconds): volume and brightness caps, high-frequency
  cut, trigger rules, ten animations with full-screen previews (including 3D crystal polygons, a
  polygon mandala, starfield and aurora, or a black screen with sound only), focus length, a recorded
  familiar voice woven in quietly, and **What helps** insights with per-session triggers and notes.
- **Reports for therapists.** Copy or save a CSV and Markdown summary for a BCBA / OT.
- **Same icon and long-press menu everywhere:** SOS, Focus, Play & calm, Deep calm.

**Web app:** https://manoyrocks.github.io/AuraSOS/ (GitHub Pages, deployed by the workflow in `.github/workflows/pages.yml`; see
[docs/PUBLISHING.md](docs/PUBLISHING.md)).

## Documentation
| Document | For | What is in it |
|---|---|---|
| [docs/USER_GUIDE.md](docs/USER_GUIDE.md) | Parents, caregivers, teachers | Using every mode and setting, reading the insights, troubleshooting |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Developers | How the app is built: audio engine, data, visuals, platforms, web build |
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | Developers | Setup, commands, recipes (add an animation, a menu entry, a migration), conventions |
| [docs/TESTING.md](docs/TESTING.md) | Developers, QA | What the automated tests prove, and the manual device checklist |
| [docs/PUBLISHING.md](docs/PUBLISHING.md) | Whoever ships it | Publishing the PWA and the native apps, headers, updates, pre-launch checklist |
| [docs/CHANGELOG.md](docs/CHANGELOG.md) | Everyone | What changed in each version |
| [CLAUDE.md](CLAUDE.md) | Developers and AI assistants | The non-negotiable clinical, safety and code rules |
| `aurasync_complete_research_prd_*.md` | Product | The original research, PRD and prompts the app was built from |

## Quick start
```bash
export PATH="$HOME/develop/flutter/bin:$PATH"   # wherever Flutter is installed
flutter pub get
flutter analyze && flutter test                  # static analysis + the Dart test suite
native/build_and_test.sh                         # C++ audio engine tests (needs Xcode CLT / clang)
flutter run                                      # iOS simulator or a connected device

tool/build_web.sh                                # production PWA into build/web (verified)
python3 tool/serve_web.py                        # serve it, with a Wi-Fi URL for phones and tablets
```
Android builds need the Android SDK + NDK (`flutter build apk --debug`). See
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for details.

## Platforms
| | iOS | Android | Web (PWA) |
|---|---|---|---|
| Audio engine | Native C++ (AudioQueue) | Native C++ (OpenSL ES) | Same engine in Dart, Web Audio |
| Data | SQLite | SQLite | `localStorage` (JSON) |
| Offline | Yes | Yes | Yes, once installed / cached (needs HTTPS or localhost) |
| Voice recording | Yes | Yes | No (no microphone capture) |
| Keep screen awake | Yes | Yes | No |
| Long-press icon menu | Yes (quick actions) | Yes (static shortcuts) | Yes on Android (manifest shortcuts) |
| Verified here | Simulator | **Not built** (no SDK) | Browser, production headers |

## Project layout
| Path | Purpose |
|---|---|
| `lib/core/` | Audio contracts, the engine in Dart, FFI binding, Web Audio engine, Iso-Principle controller, WAV codec, platform channels |
| `lib/data/` | SQLite and browser stores, profile / session repository, insights, report exporter, voice library |
| `lib/ui/` | Home, session, kiosk, caregiver settings, insights, animation picker and widgets |
| `native/` | C++17 audio engine, platform speaker output, engine test harness |
| `shaders/` | The eight fragment-shader animations |
| `web/`, `deploy/`, `tool/` | PWA shell and offline service worker; hosting configs; build, verify, serve and icon scripts |
| `android/`, `ios/` | Native projects (icons, shortcut menus, microphone and launch channels) |
| `test/` | Headless Dart tests |
| `docs/` | The documentation set above |

## Naming
The product is **AuraSOS**. Internal identifiers (the Dart package `aurasync`, bundle id
`com.aurasync.aurasync`, channel names, the `aurasync.db` storage key) keep their original name so
existing installs and saved data are unaffected.

## Known limitations
- Android code (speaker output, keep-awake, microphone, shortcuts) has not been compiled or run.
- Not yet exercised on physical iOS or Android devices, or in a release build.
- The web build renders audio on the main thread; an audio worklet would be better for production.
- Under extremely fast tapping (50+ per second) the output limiter smooths the kalimba. It is safe, not crisp.
- Android background audio would need a foreground service (iOS is configured).

## License and use
Add your licence here before distributing. Clinical wording in the app and docs is deliberately
cautious; have it reviewed for your region before public release (see
[docs/PUBLISHING.md](docs/PUBLISHING.md)).
