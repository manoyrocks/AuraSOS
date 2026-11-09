# Publishing AuraSOS

Two routes: the **PWA** (a static site, any HTTPS host) and the **native apps** (App Store, Google Play). They share one
codebase and one set of icons and menus, so you can ship either or both.

> Nothing here has been run against a real host or store account. Treat the steps as a checked recipe, and do the pre-launch
> checklist (section 5) before sharing anything with families.

---
## Part A. The web app (PWA)

AuraSOS's web build has no server code, database or third-party service. Publishing means putting the contents of
`build/web` on any HTTPS static host.

### A1. Build
```bash
tool/build_web.sh                          # site served from the domain root
tool/build_web.sh --base-href /aurasos/    # site served from a sub-path (e.g. a GitHub Pages project site)
```
The script builds a release bundle with the renderer and fonts included (no CDN), stamps the app version, writes the offline
service worker's file list and a content-hash cache version, then runs `tool/check_web_build.py`, which **fails the build** on
missing files, an unstamped service worker, inline scripts, a CSP that disagrees with `_headers`, or any external URL.
`build/web` is what you publish (about 40 MB, 25 MB of it the CanvasKit renderer cached on first load).

### A2. Choose a host
HTTPS is **required**: browsers enable the service worker (offline, install) only on a secure origin. All of these provide it.

| Host | What to do |
|---|---|
| **Netlify** | `netlify deploy --prod --dir=build/web`. `_headers` is picked up automatically (`deploy/netlify.toml` sets the publish dir) |
| **Cloudflare Pages** | Upload `build/web` (Wrangler or dashboard). `_headers` is picked up automatically |
| **Firebase Hosting** | Copy `deploy/firebase.json` to the project root, then `firebase deploy --only hosting` |
| **Vercel** | Copy `deploy/vercel.json` into `build/web`, then `vercel deploy --prod build/web` |
| **GitHub Pages** | **Set up for this repository** (see A2a). Pages cannot send headers, so the policy is enforced by the `<meta>` CSP in `index.html` (same rules, minus `frame-ancestors`). Project sites need `--base-href` (the workflow sets it) |
| **nginx / Apache** | `deploy/nginx.conf` or `deploy/apache.htaccess`. nginx must serve `.wasm` as `application/wasm` |

Every config carries the same headers, generated from `web/_headers`; `test/publish_readiness_test.dart` fails if one drifts.
Test locally with the production headers: `python3 tool/serve_web.py`.

#### A2a. GitHub Pages for this repository
The workflow `.github/workflows/pages.yml` (a copy of `deploy/github-pages.yml`; a test keeps them identical) runs on every push to `main` and on
demand: `flutter analyze`, `flutter test`, then `tool/build_web.sh --base-href /AuraSOS/` (which fails on any publishability problem), then
publishes `build/web`. A failing test or check stops the deploy, so the live site is always a build that passed.

**One-time setup:** repository **Settings → Pages → Build and deployment → Source: GitHub Actions**. After that, every push deploys.
The site is served at **https://manoyrocks.github.io/AuraSOS/**. Pages is HTTPS, so installing the app and offline use work.

Pushing the workflow file itself needs a token with the **`workflow`** scope (classic tokens) or the *Workflows: read and write* permission
(fine-grained tokens); a token with only `repo` is refused.

To redeploy without a code change, run the workflow from the **Actions** tab (*Run workflow*). To roll back, revert the commit on `main`.

### A3. Verify the live site
```bash
curl -sI https://YOUR-DOMAIN/ | grep -i -E "content-security|x-frame|nosniff|referrer|permissions|cache-control"
```
In Chrome DevTools → Application: no manifest warnings; the service worker is **activated and running**; the cache `aurasync-<version>`
(an internal name) holds about 40 files. Run Lighthouse's PWA and best-practices audits.

Real-device pass:
1. **Install.** Android Chrome: menu → *Install app*. iPhone/iPad Safari: Share → *Add to Home Screen*.
2. **Airplane mode.** Open the installed app with networking off: it must load and run a session.
3. **Sound.** SOS: 4-second fade-in, no clicks. iPhone: silent switch off (Safari mutes web audio).
4. **Shortcuts (Android).** Long-press the icon → *SOS: calm down* opens the session. iOS does not support web manifest
   shortcuts. Browsers need a touch before sound can start, so a shortcut-launched session becomes audible on the first touch.
5. **Caregiver area.** Hold the gear 3 s; *About* shows *Ready to use offline*.

### A4. Browser limits (disclose in your listing)
No voice recording, no report file saving (copy buttons work), no keep-screen-awake; audio renders on the page's main thread.

---
## Part B. Native apps (iOS and Android)

Build with Flutter as usual; the icon, launch screen, long-press menu, microphone permission text and name are already set.

### B1. Identity (decide before the first release)
| | Current value | Notes |
|---|---|---|
| Product name | **AuraSOS** | iOS `CFBundleDisplayName`, Android `strings.xml` (`app_name`) |
| Android `applicationId` / iOS bundle id | `com.aurasync.aurasync` | Kept from the original name so installs and saved data survive the rename. **Cannot be changed after release without publishing a new app.** If the app has never shipped, change it now (`android/app/build.gradle.kts`, the Kotlin package folder and `AndroidManifest`/`MainActivity.kt`, and the iOS bundle id in Xcode) |
| Version | `pubspec.yaml` `version:` (`1.0.0+1`) | `name+build`; the build number must rise on every store upload. Keep `lib/core/app_info.dart` in step |

### B2. iOS (App Store)
1. Open `ios/Runner.xcworkspace` in Xcode; set your **Team** and a unique **bundle id**; keep automatic signing.
2. `flutter build ipa` (or Product → Archive) and upload with Xcode / Transporter.
3. Listing: age rating, a privacy policy URL (publish `web/privacy.html` somewhere stable), and App Privacy answers: **data not collected**.
4. The microphone permission text is in `Info.plist`; recording is optional and on-device only.
5. If you target the **Kids** category, review Apple's rules on third-party code and parental gates (the app has no third-party SDKs; the caregiver area is behind a 3-second hold).

### B3. Android (Google Play)
1. Set your final `applicationId` (B1).
2. **Create an upload key and a release signing config.** The project currently signs release builds with the debug key so that
   `flutter run --release` works; a store upload needs your own key (`keytool -genkey …`, a `key.properties` file kept out of source
   control, and a `signingConfigs.release` block in `android/app/build.gradle.kts`).
3. `flutter build appbundle` and upload the `.aab`.
4. Listing: content rating, a privacy policy URL, and the Data safety form: **no data collected or shared**. `RECORD_AUDIO` is requested
   only when a caregiver records a phrase; there is no `INTERNET` permission (a test enforces this).
5. If you target **Families**, review Google's Families policy.
6. **Android has never been built or run here.** Do the full manual checklist in [TESTING.md](TESTING.md) on a real device first.

### B4. What the native builds include
Native C++ audio engine with direct speaker output, voice recording, keep-screen-awake, background audio on iOS, adaptive and
themed (monochrome) Android icons, iOS quick actions and Android static shortcuts.

---
## 5. Pre-launch checklist
- **Contact details.** `web/privacy.html` has none. Add a support address (and your legal name if you operate as a business), rebuild.
- **Wording review.** The app and pages say *calming aid, not a medical device*; avoid therapeutic or diagnostic claims in listings and
  marketing, and have the wording reviewed for your regions (COPPA, GDPR-K, health-claims rules).
- **Name check.** Search the app stores and trademark registers for "AuraSOS".
- **Play Store icon.** Upload `android/store/ic_launcher_512.png` (512 × 512, 32-bit PNG) as the store listing icon. It is regenerated with the other icons.
- **Artwork.** Replace the icon by editing `tool/generate_icons.py`, rerunning it, and running the tests.
- **Real-device testing** of everything in [TESTING.md](TESTING.md), especially Android and the sound checks, with an adult at low volume first.
- **Clinical input.** Have an occupational therapist or BCBA review the defaults (volume cap 80%, the calm-down timings) for your audience.

## 6. Shipping updates
1. Bump the version (`pubspec.yaml` and `lib/core/app_info.dart` together; a test enforces they match) and add a [CHANGELOG](CHANGELOG.md) entry.
2. `flutter analyze && flutter test && native/build_and_test.sh`.
3. **Web:** `tool/build_web.sh`, deploy `build/web`. A new version installs in the background and **waits until every tab or the installed app is
   closed**, so a running session is never swapped. Caregivers can also use *Caregiver area → About → Reload app*.
   **Roll back** by redeploying the previous build (its cache name differs, so devices switch back cleanly). Never add `skipWaiting` to the service worker (a test forbids it).
4. **Native:** build and upload with a higher build number.

## 7. Store listings via the PWA
A PWA can be wrapped for Google Play (Trusted Web Activity, for example through PWABuilder; it needs a Digital Asset Links file on your
domain). The Apple App Store does not accept PWAs; use the Flutter iOS build.
