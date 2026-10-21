# AuraSync: Offline ASD Acoustic & Sensory Regulation App
**Complete Research Report, YouTube Benchmark Analysis, Product Requirements Document (PRD), and Multi-Agent Prompts for Gemini, OpenAI Codex, and Claude Code**

---

## Part 1: Deep Research on Behavioral Sound Science & Music Therapy for ASD

Children with Autism Spectrum Disorder (ASD) exhibit distinct neurophysiological responses to auditory stimuli compared to neurotypical peers. Designing an effective digital therapeutic or sensory regulation app requires translating clinical findings in **neuro-acoustics, occupational therapy (sensory integration), and clinical music therapy** into deterministic software parameters.

### 1.1 Auditory Processing Differences in Autism
* **Hyperacusis & Diminished Stapedius Reflex:** Up to 70% of children on the spectrum experience auditory hypersensitivity (hyperacusis). In a regulated nervous system, the stapedius and tensor tympani muscles in the middle ear contract to dampen loud or sudden noises and focus on human speech. In children with ASD experiencing chronic sympathetic ("fight-or-flight") arousal, middle-ear muscle tone is reduced, allowing low-frequency environmental rumble and high-frequency transients (sirens, clattering dishes, fluorescent hums, sharp consonant sounds) to strike the cochlea unattenuated.
* **Delayed Auditory Brainstem Response (ABR) & Cortical Habituation Deficit:** Neuroimaging studies demonstrate that many autistic brains do not habituate to repetitive background clatter. Every unpredictable sound is processed as a novel threat, rapidly filling the child's "sensory bucket" until an autonomic crisis (meltdown or shutdown) occurs.

### 1.2 Core Evidence-Based Acoustic Mechanisms

| Clinical Principle | Scientific Mechanism | App Engineering Translation |
| :--- | :--- | :--- |
| **The Iso-Principle (Clinical Music Therapy)** | Matching the patient's current internal physiological/emotional tempo and harmonic energy first, then gradually shifting musical parameters toward the desired calm state. Playing slow, quiet music abruptly during a high-energy meltdown creates sensory dissonance and rejection. | **3-Stage Automated Pacemaker:** Starts at a grounded 100–110 BPM warm percussive pulse (cello/marimba) matching elevated heart rate, then linearly tapers tempo to 60 BPM while sweeping a low-pass filter from 2,500 Hz down to 400 Hz over 8–15 minutes. |
| **Polyvagal Theory & Safe and Sound Protocol (Dr. Stephen Porges)** | The human nervous system detects safety through vocal prosody in the mid-frequency band (500 Hz–3,000 Hz). Algorithmically modulated music concentrated in this band stimulates cranial nerves VII and X (vagus nerve), engaging the "vagal brake" and improving attention and social readiness. | **Focus & Classroom Mode:** Applies dynamic band-pass modulation centered at 600–2,200 Hz on warm instrumental tracks (acoustic guitar, Rhodes piano, soft strings) to exercise middle-ear listening muscles and filter out background room noise. |
| **Spectral Noise Masking (Brown vs. Pink vs. White Noise)** | Standard White Noise has equal energy per Hertz, making it sound like a harsh, high-frequency hiss that triggers auditory pain in ASD. **Pink Noise** drops 3 dB/octave. **Brownian (Red) Noise** drops 6 dB/octave ($1/f^2$ density), concentrating energy in the 50–500 Hz band. | **Meltdown SOS Anchor:** Real-time procedural Brownian noise generator with an adjustable biquad low-pass filter ceiling (default 650 Hz). Acts as an immediate "acoustic weighted blanket" to mask household or public noise. |
| **Rhythmic Auditory Stimulation (RAS) & Entrainment** | External rhythmic cues organize motor output and autonomic pacing via reticulospinal pathways. Predictable, steady rhythms reduce cortical prediction error—a primary driver of autistic anxiety. | **Transition & Routine Beats:** Strict 4/4 time signature loops with zero syncopation or abrupt tempo shifts, helping children transition between activities (e.g., playtime to bedtime). |
| **Harmonic Predictability (Pentatonic Consonance)** | Semitone intervals (minor 2nds) and tritones create acoustic beating (roughness) in the basilar membrane, perceived as tension or danger during sensory overload. | **Zero-Dissonance Synth Engine:** All interactive touch instruments and ambient generative pads are locked to C-Major or F-Major Pentatonic scales (C-D-E-G-A), making discordant notes mathematically impossible. |

### 1.3 What to Strictly Avoid in ASD Audio Engineering
1. **High-Frequency Transients (> 2,500 Hz):** Flutes, piccolos, high violin registers, metallic wind chimes, sharp birdsong, and electronic beeps can feel physically painful during sensory overload.
2. **Abrupt Envelope Attacks (< 500 ms):** Sudden audio starts, stops, or track changes trigger the acoustic startle reflex. Every state transition must pass through a **3.0-to-4.0 second logarithmic crossfade**.
3. **Uncompressed Dynamic Range:** Classical tracks that shift from whisper-quiet (*pianissimo*) to booming crescendos (*fortissimo*) destabilize regulation. Audio must be compressed within a narrow **4 dB dynamic window** with a hard **-3.0 dBFS brickwall peak limiter**.

---

## Part 2: Comprehensive YouTube Autism Sensory & Audio-Visual Benchmark Analysis

To understand real-world efficacy, we analyzed the highest-viewed autism calming, classroom focus, and meltdown recovery videos on YouTube (ranging from **370,000 to 168+ million views**) alongside caregiver, teacher, and occupational therapist feedback.

### 2.1 Top-Performing Channels & Videos Analyzed

| Channel / Creator | Benchmark Video Title | Views | Visual Architecture | Acoustic Architecture | Why Subscribers Report High Efficacy |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Super Duper Fun Music** | *Autism Calming Sensory Meltdown Remedy Soothing Visuals* | **11M+ views** | Continuous 3D bioluminescent particle light tunnel moving at a slow, constant Z-axis velocity. | Warm, sustained synthesizer pads + low bass drone; zero sharp percussion; slow harmonic shifts. | The forward-moving tunnel gently captures visual hyper-focus ("visual stimming"), interrupting the meltdown loop within 15–30 seconds. |
| **Calming Connections** | *Quiet Classroom Music For Children - Calming Sensory Bubbles* | **22M+ views** | Slow-rising translucent soap/water bubbles over a soft gradient background; predictable upward physics. | Soft harp, muted Rhodes piano, and warm acoustic plucks at ~64 BPM. | Widely used by SEN/SPED teachers; predictable upward drift regulates breathing and lowers classroom vocal volume. |
| **Super Duper Fun Music** | *Best Sensory Music for Autism Sensory Visuals* | **6.3M+ views** | Symmetrical radial kaleidoscopes and slow color-morphing geometric portals. | Ambient downtempo pads layered with subtle sub-bass warmth. | Radial symmetry satisfies visual pattern-seeking without requiring cognitive processing. |
| **Hey Bear Sensory** | *Lanterns - Relaxing Video with Calming Music / Sleep Video* | **40M+ views** | High-contrast glowing warm lanterns floating smoothly across a pure black (`#000000`) background. | Gentle lullaby marimba/celesta with warm low-mid accompaniment. | Pure black background prevents photophobia (light sensitivity) while glowing objects provide clean visual tracking. |
| **Snooze Happy** | *Autism Calming Sensory with Relaxing Music - 8 Hours* | **1M+ views** | Deep underwater jellyfish / bioluminescent drift with ultra-slow sinusoidal motion. | Continuous ambient drone + filtered pink/water noise over an 8-hour uninterrupted loop. | Eliminates loop restarts during sleep or post-meltdown recovery ("sensory hangover"). |
| **Cute Little Heroes** | *Sensory Lights Tunnel & Classroom Music HyperFocus (Jazz/Lo-Fi)* | **379K+ views** | Smooth neon light tunnel paired with low-arousal color waves. | Warm lo-fi / mellow jazz chord progressions with heavily low-passed percussion. | Favored by older autistic children (ages 8–16) and AuDHD youth who dislike babyish lullabies. |

### 2.2 Critical Failure Modes of YouTube Identified in Parent Feedback
While the audiovisual content above works remarkably well, parents and therapists consistently report **five critical failures when relying on YouTube**:
1. **Catastrophic Mid-Roll Ads:** A sudden, loud advertisement interrupting a calming video triggers an immediate, severe meltdown.
2. **Offline Dead Zones:** Meltdowns happen in cars, grocery stores, airplanes, clinics, and parks where Wi-Fi or cellular data is unavailable or buffering.
3. **Accidental Touch Exit & Rabbit Holes:** Autistic children frequently hold or tap the tablet screen during regulation. On YouTube, a single tap pauses the video, brings up UI overlays, or clicks a hyper-stimulating thumbnail.
4. **Inability to Decouple Audio & Visuals:** Sometimes a child needs the *Super Duper Fun Music* light tunnel paired with pure *Brown Noise* rather than music, or needs the screen completely black while keeping the audio running.
5. **Lack of Individual Trigger Filtering:** One child finds rain sounds soothing, while another child has a sensory aversion to rain or high piano notes. Pre-rendered videos cannot filter out specific frequencies on the fly.

---

## Part 3: Full App Development Documentation & PRD (`AuraSync`)

### 3.1 Product Overview
* **App Name:** AuraSync (Offline Acoustic & Visual Regulation System)
* **Target Devices:** iOS (iPhone & iPad) and Android (Phones & Tablets)
* **Network Policy:** **100% Offline-First.** Zero internet permissions required, zero ads, zero external telemetry, zero buffering.
* **Primary Users:**
  * **Child (Ages 2–16, ASD Level 1–3):** Interacts with large, zero-text visual cards and a touch-locked sensory canvas.
  * **Caregiver / Parent / Therapist (OT / BCBA):** Configures the child's Sensory Profile, triggers the 1-Tap SOS Meltdown button, and reviews offline efficacy logs.

### 3.2 Core Functional Modes & User Flows

#### Mode A: 1-Tap Meltdown SOS (Crisis De-escalation)
* **Latency Target:** Audio and visuals must begin fading in within **< 400 ms** of launching the app or tapping the Home Screen OS Widget.
* **Sub-Modes:**
  1. **Iso-Principle Down-Regulator (Early Escalation / Agitation):**
     * *Minute 0–3 (Match):* 104 BPM warm marimba/cello pulse, Low-Pass Filter (LPF) at 2,000 Hz, visual tunnel speed at 1.0x.
     * *Minute 3–8 (Bridge):* Tempo interpolates linearly from 104 BPM down to 72 BPM; melodic stems crossfade into sustained warm pads; LPF sweeps down to 900 Hz; visual tunnel slows to 0.5x.
     * *Minute 8–12+ (Anchor):* Resolves into a 58 BPM sub-bass heartbeat pulse + smoothed Brownian Noise (LPF at 500 Hz); screen luminance automatically dims by 40%.
  2. **Deep Crisis Anchor (Full Meltdown):**
     * Bypasses rhythmic music completely. Fades in **Smoothed Brownian Noise + 110 Hz Warm Drone** over 4.0 seconds paired with a dimmed OLED Floating Lanterns or Breathing Orb shader.

#### Mode B: Focus & Classroom Co-Pilot (Attention & Task Readiness)
* **Acoustic Engine:** Mid-frequency (500–2,500 Hz) prosody-filtered acoustic/lo-fi stems layered over subtle Pink Noise (-18 dB relative to music) to mask classroom or household chatter, plus optional 10 Hz Alpha isochronic pulse modulation.
* **Visual Transitions Timer:** Replaces stressful ticking clocks and jarring school bells with a **Visual Disappearing Rainbow Arc / Flowing Sand Timer**. When time expires, the music plays a gentle, predictable 30-second harmonic resolution cadence so the child anticipates the transition without startle.

#### Mode C: Daily Calm & Safe Stimming Canvas (Self-Regulation)
* **Interactive Cause-and-Effect Pad:** When the child touches or drags across the screen, the shader generates slow bioluminescent water ripples or floating bubbles while triggering soft, velocity-capped **C-Major Pentatonic Kalimba or Handpan notes** paired with gentle device haptics.
* **Spam-Tap Protection:** Even if a child rapidly taps the screen 10 times per second, a polyphonic voice-stealing limiter and attack-smoothing envelope prevent harsh audio clipping or visual flashing.

### 3.3 Non-Negotiable Safety & Accessibility Features
1. **Child Touch-Lock Kiosk Mode:**
   * Automatically engages when any session starts.
   * Hides all close buttons, settings icons, and OS status bars.
   * **Parent Unlock Gesture:** Requires pressing and holding **two opposite corners** (top-left + top-right) simultaneously for **3.0 seconds**, displaying a subtle circular progress ring.
2. **Sub-OS Screen Dimmer:**
   * Renders a full-screen alpha-black pixel shader overlay (`0%` to `90%` opacity) allowing the tablet to glow softly in a pitch-black room below standard hardware brightness minimums.
3. **Sensory Trigger Blacklist (Parent Configuration):**
   * Parents can toggle off specific sound categories (e.g., `[x] Disable Rain/Water`, `[x] Disable High Piano`, `[x] Enforce Hard 800 Hz High-Cut Filter`).
4. **Familiar Voice Co-Regulation Recorder (Offline):**
   * Allows a parent to record soothing phrases ("You are safe, take a deep breath"). The app automatically strips harsh sibilance (de-essing > 4 kHz), normalizes volume, and gently weaves the parent's voice into the background soundscape.
5. **Offline BCBA / OT Meltdown Journal:**
   * Upon unlocking the screen after an SOS session, a non-intrusive 1-tap prompt asks: *"Did this preset help regulate? [👍 Effective] [😐 Neutral] [👎 Escalated]"*.
   * Logs time of day, duration, preset used, and outcome into a local SQLite database with one-click offline PDF/CSV export for therapy teams.

### 3.4 Recommended Technical Stack (100% Offline)
* **Cross-Platform Framework:** **Flutter (Dart)** or **React Native (TypeScript)** configured for strict offline compilation.
* **Real-Time DSP Audio Engine:**
  * Custom C++ audio callback (via **Oboe** on Android and **AVAudioEngine / CoreAudio** on iOS, or **Rust `cpal`/`kira`** via FFI).
  * Procedural generators for White, Pink (-3 dB/oct), and Brownian (-6 dB/oct) noise using Paul Kellet's pinking filter and leaky integrator algorithms.
  * State-Variable Biquad Filter (Low-Pass, Band-Pass, Notch) with smoothed coefficient interpolation to prevent zipper noise.
  * Seamless gapless looping engine for compressed `.ogg` / `.caf` instrumental stems (< 80 MB total bundle size).
* **GPU Visual Engine:**
  * **Impeller / Skia Shading Language (SkSL)** (if Flutter) or **React Native Skia / OpenGL ES** (if React Native) running at a locked 60 fps with zero garbage-collection frame drops.
* **Local Persistence:**
  * **SQLite (`sqflite` / `WatermelonDB`)** for sensory profiles, custom presets, and meltdown telemetry logs.

---

## Part 4: Unified Prompt for a Team of AI Agents in Gemini

Copy and paste the master prompt block below directly into **Gemini** to initialize and coordinate your multi-agent development team.

```text
================================================================================
MASTER SYSTEM PROMPT: MULTI-AGENT ORCHESTRATION FOR "AURASYNC" (GEMINI EDITION)
(100% OFFLINE MOBILE/TABLET APP FOR AUTISM CALM, FOCUS & MELTDOWN DE-ESCALATION)
================================================================================

ROLE & OBJECTIVE:
You are a coordinated team of 5 specialized AI Agents engineering "AuraSync," a production-grade, 100% offline mobile and tablet application (iOS & Android) designed to support children with Autism Spectrum Disorder (ASD) across three core states:
1. Acute Meltdown De-escalation (SOS Mode)
2. Task Focus & Classroom Readiness (Focus Mode)
3. Daily Sensory Regulation & Safe Stimming (Calm Mode)

================================================================================
SECTION 1: CLINICAL & ACOUSTIC GUARDRAILS (MANDATORY FOR ALL AGENTS)
================================================================================
Every line of code, UI component, and audio graph you generate MUST obey these clinical neuro-acoustic rules:
1. ZERO NETWORK DEPENDENCY: The app must function 100% offline in Airplane Mode. Zero external API calls, zero streaming, zero ads, zero external fonts/CDNs.
2. ZERO ACOUSTIC STARTLE (4-SECOND LOGARITHMIC ENVELOPE): Never start, stop, or switch audio abruptly. Every state change must route through a 4.0-second logarithmic amplitude crossfade.
3. HYPERACUSIS PROTECTION & LIMITING: Enforce a master brickwall limiter at -3.0 dBFS. During Meltdown SOS Mode, apply a default biquad low-pass filter at 650 Hz to eliminate painful high-frequency transients.
4. THE ISO-PRINCIPLE ENGINE: Meltdown recovery must implement a 3-stage automated down-regulation state machine:
   - Phase 1 (Match Arousal, Min 0–3): 104 BPM warm marimba/cello pulse, LPF @ 2000 Hz, visual shader speed 1.0x.
   - Phase 2 (Harmonic Thinning, Min 3–8): Linear tempo ramp from 104 BPM -> 72 BPM, crossfade percussive stems into warm pentatonic pads, LPF sweeps 2000 Hz -> 900 Hz, visual speed 0.5x.
   - Phase 3 (Vagal Baseline, Min 8–12+): 58 BPM sub-bass heartbeat pulse + smoothed Brownian Noise (-6 dB/octave), LPF @ 500 Hz, visual speed 0.25x, Sub-OS screen dimmer at 40%.
5. BENCHMARK GPU SHADERS (NO STROBING): Implement 4 GPU fragment shaders inspired by top-performing autism sensory media:
   - Shader A: Bioluminescent 3D Light Tunnel (slow, constant Z-axis drift).
   - Shader B: Rising Translucent Classroom Bubbles (predictable upward buoyancy).
   - Shader C: High-Contrast OLED Floating Lanterns (pure #000000 background).
   - Shader D: Co-Regulation Breathing Orb (4s inhale expand, 6s exhale contract).
   *Constraint:* Luminance oscillation must stay strictly below 0.2 Hz (WCAG 2.1 AAA photosensitive safe).
6. CHILD TOUCH-LOCK KIOSK: While a sensory session is active, standard navigation is locked. If the child taps or drags on the screen, render gentle visual water ripples and trigger velocity-capped C-Major Pentatonic kalimba tones (with polyphonic spam-tap protection). Unlocking requires a parent to press and hold BOTH top-left and top-right screen corners simultaneously for 3.0 seconds.

================================================================================
SECTION 2: MULTI-AGENT TEAM TOPOLOGY & HANDOFF PROTOCOL
================================================================================
You will operate as 5 distinct agents. Clearly prefix every section of your output with the active Agent tag:

[AGENT 1: LEAD ARCHITECT & STATE ORCHESTRATOR]
- Tech Stack Selection: Flutter (Dart + Impeller Shaders + C++/Dart FFI Audio).
- Responsibilities: Define the complete project directory structure, the deterministic Iso-Principle State Machine, and strict Dart interfaces between UI, Audio DSP, Shaders, and SQLite.

[AGENT 2: NEURO-ACOUSTIC DSP ENGINEER]
- Responsibilities: Write the complete, mathematically accurate procedural audio engine:
  1. Real-time Brownian Noise (-6 dB/oct leaky integrator) and Pink Noise (-3 dB/oct Paul Kellet filter) generators.
  2. State-Variable Biquad Filter (Low-Pass, Band-Pass for 500-2500 Hz SSP Prosody Mode, and High-Cut Trigger Blacklist).
  3. 4.0-second logarithmic crossfader and -3.0 dBFS soft-knee compressor/limiter.
  4. Iso-Principle Pacemaker controller that interpolates BPM, filter cutoff, and stem gain over configurable durations.
  5. Pentatonic Synthesizer voice manager with spam-tap envelope smoothing.

[AGENT 3: SENSORY UI & GPU SHADER ENGINEER]
- Responsibilities: Write the production UI and GLSL/SkSL shaders:
  1. Zero-clutter Home Dashboard featuring the oversized "1-TAP MELTDOWN SOS" button (<400ms launch), "Focus & Timer Mode", and "Calm & Stim Canvas".
  2. The 4 GLSL fragment shaders (Bioluminescent Tunnel, Bubbles, OLED Lanterns, Breathing Orb) synced to the Iso-Principle speed multiplier.
  3. The `ChildTouchLockWrapper` component implementing the dual-corner 3-second parent unlock gesture and interactive ripple/kalimba touch feedback.
  4. The `VisualTransitionTimer` (vanishing rainbow arc) and `SubOsDimmerOverlay`.

[AGENT 4: LOCAL DATA & CLINICAL TELEMETRY ENGINEER]
- Responsibilities: Write the offline SQLite persistence layer:
  1. `SensoryProfile` schema storing the child's preferred presets, max volume cap, brightness cap, and Frequency/Timbre Blacklist.
  2. `MeltdownSessionLog` schema capturing timestamp, preset used, Iso-Principle completion, and the 1-tap caregiver efficacy rating (Effective / Neutral / Escalated).
  3. Offline CSV/PDF clinical summary generator for sharing with the child's Occupational Therapist or BCBA.

[AGENT 5: CLINICAL QA & SENSORY SAFETY AUDITOR]
- Responsibilities: Write automated unit/integration tests and perform a strict safety audit:
  1. Verify zero audio clicks/pops on buffer boundaries and state transitions.
  2. Verify the dual-corner parent lock cannot be bypassed by rapid random child tapping.
  3. Verify 100% offline execution with zero network calls.

================================================================================
SECTION 3: STEP-BY-STEP EXECUTION PLAN
================================================================================
Do not summarize or write placeholder comments like "// implement DSP here". Write complete, modular, production-ready code across sequential phases:
- STEP 1: [AGENT 1] outputs the complete System Architecture, Directory Tree, and Core State Machine Contracts.
- STEP 2: [AGENT 2] implements the complete Procedural DSP Audio Engine (Brown/Pink Noise, Biquad Filters, 4s Crossfader, Iso-Principle Controller).
- STEP 3: [AGENT 3] implements the GLSL Visual Shaders, 1-Tap SOS Screen, and Child Touch-Lock Kiosk Wrapper.
- STEP 4: [AGENT 4] & [AGENT 5] implement the SQLite Sensory Profile/Logger and the Clinical Safety Test Suite.

Acknowledge these instructions and immediately execute STEP 1 ([AGENT 1]) and STEP 2 ([AGENT 2]) in full detail.
```

---

## Part 5: Unified Prompt for a Team of AI Agents in OpenAI Codex

OpenAI **Codex** (including the **Codex CLI**, **OpenAI Agents SDK**, and **ChatGPT Codex Cloud Sandbox**) operates on an **autonomous file-generation, `AGENTS.md` governance, and test-driven verification loop**. Unlike conversational models, Codex agents excel when given explicit file paths, deterministic mathematical verification tests, and zero-network sandbox execution rules.

Copy and paste the unified prompt below into **OpenAI Codex** (or save the governance block to `AGENTS.md` and pass the execution prompt to `codex`):

```text
================================================================================
MASTER ORCHESTRATION PROMPT: OPENAI CODEX MULTI-AGENT WORKFLOW FOR "AURASYNC"
(AUTONOMOUS SANDBOX EXECUTION, AGENTS.MD GOVERNANCE & DETERMINISTIC DSP VERIFICATION)
================================================================================

OBJECTIVE:
You are an autonomous multi-agent engineering swarm operating inside the OpenAI Codex execution environment. Your mission is to architect, implement, and verify "AuraSync"—a 100% offline mobile and tablet application (Flutter/Dart + Native C/C++ FFI Audio DSP + Impeller GLSL Shaders + Local SQLite) that helps children with Autism Spectrum Disorder (ASD) achieve calm, task focus, and rapid meltdown de-escalation.

================================================================================
PHASE 0: INITIALIZE REPOSITORY & WRITE `AGENTS.md`
================================================================================
First, create the root `AGENTS.md` file to govern all Codex worker agents in this repository. Enforce these non-negotiable invariants inside `AGENTS.md`:

1. AIR-GAPPED RUNTIME INVARIANT:
   - Never add HTTP/network packages (`http`, `dio`, `webview_flutter`, analytics SDKs, or remote font loaders).
   - Android `AndroidManifest.xml` MUST NOT declare `android.permission.INTERNET`.
2. CLINICAL NEURO-ACOUSTIC DSP INVARIANTS:
   - Sample Rate: 48,000 Hz stereo float32 ring buffer.
   - Startle Prevention: Every play, stop, pause, or preset switch MUST traverse a 4.0-second (192,000-sample) logarithmic amplitude envelope (`gain = pow(t, 2.2)`). Maximum sample-to-sample delta across state transitions must never exceed `0.005f` (zero clicks/pops).
   - Brickwall Limiter: Master bus soft-knee compressor + hard ceiling at `-3.0 dBFS` (`0.70794578f` linear amplitude).
   - Meltdown SOS Spectral Ceiling: State-variable biquad low-pass filter defaulting to `650.0 Hz` (`Q = 0.7071`) during acute meltdown mode to prevent hyperacusis pain.
   - Procedural Noise Accuracy:
     * Brownian Noise (`-6 dB/octave`): Leaky integrator `y[n] = 0.995 * y[n-1] + 0.05 * white_noise`, DC-blocked at `20 Hz`.
     * Pink Noise (`-3 dB/octave`): Paul Kellet's 7-state IIR pinking filter.
   - Polyvagal SSP Focus Filter: Dynamic band-pass modulation centered between `500.0 Hz` and `2,500.0 Hz` (human vocal prosody band).
   - Harmonic Consonance Lock: Touch-stimming synthesizer voices MUST be strictly quantized to C-Major Pentatonic (`[130.81, 146.83, 164.81, 196.00, 220.00, 261.63, 293.66, 329.63, 392.00, 440.00]` Hz) with 8-voice polyphonic voice-stealing and minimum `45 ms` cosine attack smoothing.
3. ISO-PRINCIPLE DOWN-REGULATION STATE MACHINE:
   - Phase 1 (Match Arousal, `0..180s`): `104.0 BPM` warm marimba/cello pulse, LPF `2000 Hz`, shader velocity `1.0x`.
   - Phase 2 (Harmonic Thinning, `180..480s`): Linear interpolation `104.0 -> 72.0 BPM`, crossfade rhythmic stems into sustained pentatonic pads, LPF sweep `2000 -> 900 Hz`, shader velocity `0.5x`.
   - Phase 3 (Vagal Baseline, `480..720s+`): `58.0 BPM` sub-bass heartbeat (`60-120 Hz` dual lub-dub pulse) + smoothed Brownian Noise, LPF `500 Hz`, shader velocity `0.25x`, Sub-OS screen dimmer `0.40`.
4. PHOTOSENSITIVE & TOUCH-LOCK SAFETY INVARIANTS:
   - All GLSL fragment shaders (`shaders/tunnel.frag`, `shaders/bubbles.frag`, `shaders/lanterns.frag`, `shaders/breathing_orb.frag`) must restrict luminance oscillation to `< 0.2 Hz`.
   - Child Touch-Lock Kiosk requires simultaneous touch hold in Top-Left (`x < 96, y < 96`) AND Top-Right (`x > width - 96, y < 96`) corners for `3000 ms` continuous duration to unlock.

================================================================================
MULTI-AGENT TASK DELEGATION & FILE GENERATION MANIFEST
================================================================================
Execute the following 5 Codex Agent workstreams in parallel/sequence, writing complete, compilable source files (zero placeholders, zero TODOs):

[CODEX-AGENT-1: CORE ARCHITECTURE & ISO-STATE ENGINE]
Create and populate:
- `AGENTS.md` (Repository clinical & technical constitution)
- `pubspec.yaml` (Offline-only dependencies: `sqflite`, `path_provider`, `ffi`, `flutter_shaders`, `provider`/`riverpod`)
- `lib/core/models/sensory_state.dart` (Immutable state models for SOS, Iso-Principle phases, Focus, and Calm modes)
- `lib/core/engine/iso_principle_controller.dart` (Deterministic 60Hz tick controller computing exact BPM, LPF cutoff, stem weights, shader velocity, and dimmer alpha at any elapsed millisecond)

[CODEX-AGENT-2: NATIVE C++/DART DSP AUDIO SYNTHESIS ENGINE]
Create and populate:
- `native/dsp_engine.h` & `native/dsp_engine.cpp` (Pure C++17 zero-allocation real-time audio callback implementing Brownian/Pink noise generators, smoothed Biquad filters, 4.0s logarithmic crossfader, C-Major Pentatonic Kalimba physical-modeling pluck synth, and -3.0 dBFS master limiter)
- `lib/core/audio/dsp_bridge.dart` (Dart FFI bindings + pure-Dart fallback PCM synthesizer so unit tests run in any headless VM)
- `lib/core/audio/familiar_voice_processor.dart` (Offline parent voice de-esser >4kHz and level normalizer)

[CODEX-AGENT-3: GPU VISUAL SHADERS & SENSORY KIOSK UI]
Create and populate:
- `shaders/bioluminescent_tunnel.frag` (Super Duper Fun Music benchmark: slow Z-axis particle tunnel)
- `shaders/classroom_bubbles.frag` (Calming Connections benchmark: rising translucent soap bubbles)
- `shaders/oled_lanterns.frag` (Hey Bear Sensory benchmark: pure `#000000` background with warm glowing lanterns)
- `shaders/breathing_orb.frag` (4s inhale / 6s exhale vagal co-regulation orb)
- `lib/ui/widgets/child_touch_lock_kiosk.dart` (Dual-corner 3s parent unlock + child tap water-ripple & pentatonic note trigger with spam-tap throttling)
- `lib/ui/widgets/visual_transition_timer.dart` (Vanishing rainbow arc timer with 30s harmonic resolution cue)
- `lib/ui/screens/home_sos_screen.dart` (<400ms 1-Tap Meltdown SOS launch screen + Sub-OS alpha dimmer overlay)

[CODEX-AGENT-4: OFFLINE SQLITE VAULT & CLINICAL TELEMETRY]
Create and populate:
- `lib/data/local_database.dart` (SQLite schema for `sensory_profiles` including frequency/timbre blacklists, and `meltdown_logs` for 1-tap Effective/Neutral/Escalated caregiver ratings)
- `lib/data/clinical_report_exporter.dart` (Offline CSV/Markdown report generator for Occupational Therapists and BCBAs)

[CODEX-AGENT-5: AUTOMATED SANDBOX VERIFICATION & DSP AUDIT]
Create and execute:
- `test/dsp_acoustic_safety_test.dart`:
  1. Generate 10 seconds of audio across an abrupt SOS preset switch; assert peak amplitude `<= 0.708f` (-3.0 dBFS) and maximum sample-to-sample derivative `< 0.005f` (proving zero clicks/pops).
  2. Assert Brownian noise power spectral density rolls off by `-6 dB/octave` (+/- 1.0 dB).
  3. Assert `IsoPrincipleController` transitions accurately across Phases 1, 2, and 3.
  4. Simulate 50 rapid child screen taps per second on `ChildTouchLockKiosk` and assert kiosk remains locked while dual-corner 3000ms hold unlocks cleanly.

EXECUTION DIRECTIVE:
Write all files to disk in full, run the verification test suite, and fix any compilation or assertion failures autonomously until all clinical safety tests pass.
```

---

## Part 6: Unified Prompt for a Team of AI Agents in Claude Code

Anthropic's **Claude Code (`claude` CLI)** supports native **parallel Sub-Agents (via the `Task` tool)**, persistent project memory via **`CLAUDE.md`**, and custom slash commands. Claude Code works best when a **Lead Orchestrator Agent** initializes `CLAUDE.md` and then spawns isolated **Sub-Agents** in parallel for C++/Dart DSP synthesis, GLSL Shaders, Kiosk UI, and Clinical QA, followed by a synthesis & verification gate.

Copy and paste the unified prompt below directly into your **Claude Code CLI session**:

```text
================================================================================
MASTER ORCHESTRATION PROMPT: CLAUDE CODE (`claude` CLI) SUB-AGENT SWARM
PROJECT: "AURASYNC" — 100% OFFLINE ASD SENSORY & MELTDOWN REGULATION APP
================================================================================

You are the Lead Systems Architect & Clinical Orchestrator running inside Claude Code. You will use Claude Code's file tools, bash execution, and parallel Sub-Agent (`Task` tool) capabilities to build "AuraSync"—a production-complete, 100% offline mobile/tablet app (Flutter + Native C++ Audio DSP + Impeller GLSL Shaders + SQLite) for children with Autism Spectrum Disorder (ASD).

--------------------------------------------------------------------------------
STEP 1: CREATE `CLAUDE.md` (SHARED MEMORY & CLINICAL CONSTITUTION)
--------------------------------------------------------------------------------
Before spawning any sub-agents, write `CLAUDE.md` in the project root so every spawned sub-agent inherits these strict clinical and architectural rules:
1. 100% OFFLINE & AIR-GAPPED: Zero network permissions, zero external fonts, zero ads, zero telemetry. Must operate reliably in Airplane Mode during public or car meltdowns.
2. ACOUSTIC SAFETY LAWS (HYPERACUSIS & STARTLE PREVENTION):
   - All audio state changes (Play, Pause, SOS Interrupt, Preset Switch) MUST pass through a 4.0-second logarithmic crossfade (`48,000 Hz * 4s = 192,000 samples`).
   - Hard master brickwall limiter at `-3.0 dBFS` (`0.7079f`).
   - Default Meltdown SOS low-pass filter ceiling at `650 Hz` (zero high-frequency hiss or transients > 2,000 Hz).
   - Interactive stimming instruments locked strictly to C-Major Pentatonic (`C, D, E, G, A`) with polyphonic voice-stealing and >= 45ms attack smoothing so rapid child screen-slapping never clips or distorts.
3. ISO-PRINCIPLE AUTONOMIC PACING ENGINE:
   - Phase 1 (Match Arousal, Min 0–3): `104 BPM` grounded marimba/cello pulse, LPF `2,000 Hz`, visual shader speed `1.0x`.
   - Phase 2 (Harmonic Thinning, Min 3–8): Linear ramp `104 -> 72 BPM`, crossfade rhythmic stems into warm pads, LPF sweeps `2,000 -> 900 Hz`, visual speed `0.5x`.
   - Phase 3 (Vagal Baseline, Min 8–12+): `58 BPM` sub-bass heartbeat pulse + smoothed Brownian Noise (`-6 dB/oct`), LPF `500 Hz`, visual speed `0.25x`, Sub-OS screen dimmer `40%`.
4. YOUTUBE BENCHMARK GPU SHADERS (< 0.2 Hz OSCILLATION):
   - Shader 1: Bioluminescent 3D Light Tunnel (inspired by *Super Duper Fun Music* 11M-view meltdown remedy).
   - Shader 2: Rising Translucent Classroom Bubbles (inspired by *Calming Connections* 22M-view focus video).
   - Shader 3: High-Contrast OLED Floating Lanterns on pure `#000000` background (inspired by *Hey Bear Sensory* 40M-view video).
   - Shader 4: Co-Regulation Breathing Orb (`4.0s` inhale expansion, `6.0s` exhale contraction).
5. CHILD TOUCH-LOCK KIOSK:
   - Active sessions lock out OS navigation and UI buttons. Child screen touches generate gentle water ripples + soft pentatonic kalimba plucks.
   - Parent Unlock requires holding Top-Left + Top-Right corners simultaneously for `3.0 seconds`.

--------------------------------------------------------------------------------
STEP 2: SPAWN 4 PARALLEL SUB-AGENTS VIA THE `Task` TOOL
--------------------------------------------------------------------------------
Once `CLAUDE.md` and the directory skeleton (`lib/`, `native/`, `shaders/`, `test/`) are created, spawn 4 specialized Sub-Agents to build their respective domains completely (no stub files, no `// TODO` comments):

• SUB-AGENT A (`dsp-neuro-acoustics`):
  - Mission: Implement `native/dsp_engine.h`, `native/dsp_engine.cpp`, `lib/core/audio/dsp_bridge.dart`, and `lib/core/engine/iso_principle_controller.dart`.
  - Deliverables: Real-time Brownian (`-6 dB/oct`) & Pink (`-3 dB/oct`) noise synthesis, State-Variable Biquad Filter (LPF, Prosody Band-Pass `500-2500 Hz`, Trigger Notch), 4.0s logarithmic crossfader, C-Major Pentatonic Kalimba physical modeling synth, `-3.0 dBFS` limiter, and the 3-phase Iso-Principle state machine.

• SUB-AGENT B (`sensory-shaders-and-kiosk-ui`):
  - Mission: Implement the 4 GLSL fragment shaders in `shaders/` and the complete Flutter UI in `lib/ui/`.
  - Deliverables:
    1. `shaders/bioluminescent_tunnel.frag`, `shaders/classroom_bubbles.frag`, `shaders/oled_lanterns.frag`, `shaders/breathing_orb.frag`.
    2. `lib/ui/screens/home_sos_screen.dart` (Zero-clutter dashboard with `<400ms` 1-Tap Meltdown SOS launch).
    3. `lib/ui/widgets/child_touch_lock_kiosk.dart` (Dual-corner 3s parent unlock + ripple/kalimba touch canvas).
    4. `lib/ui/widgets/visual_transition_timer.dart` (Vanishing rainbow arc timer with 30s harmonic resolution cadence) & `lib/ui/widgets/sub_os_dimmer.dart` (`2%` to `100%` luminance overlay).

• SUB-AGENT C (`offline-sqlite-and-bcba-telemetry`):
  - Mission: Implement `lib/data/local_database.dart`, `lib/data/sensory_profile_repository.dart`, and `lib/data/clinical_report_exporter.dart`.
  - Deliverables: Offline SQLite tables for child sensory profiles (including custom frequency/timbre blacklists such as "Block frequencies > 1800 Hz" or "Disable water sounds"), 1-tap post-meltdown caregiver efficacy logging (`Effective` / `Neutral` / `Escalated`), and local CSV/Markdown therapy report export for BCBAs and Occupational Therapists.

• SUB-AGENT D (`clinical-qa-and-acoustic-auditor`):
  - Mission: Implement comprehensive automated verification tests in `test/dsp_safety_test.dart`, `test/iso_principle_test.dart`, and `test/kiosk_lock_test.dart`.
  - Deliverables: Mathematical verification of the `-3.0 dBFS` ceiling, zero-click/pop derivative continuity across 4.0s fades, Brownian noise spectral slope, Iso-Principle phase timing, and child spam-tap kiosk resilience.

--------------------------------------------------------------------------------
STEP 3: INTEGRATION, BASH TEST EXECUTION & CLINICAL SIGN-OFF
--------------------------------------------------------------------------------
After all 4 Sub-Agents complete their tasks:
1. Review all cross-module imports in `lib/main.dart` to ensure a cohesive, runnable offline application.
2. Run the test suite and static analyzer to verify zero broken imports, zero unhandled exceptions, and 100% pass rate on all clinical acoustic and kiosk safety assertions.
3. Output a final Clinical & Technical Verification Summary detailing the generated files and how each neuro-acoustic constraint was satisfied.

Begin immediately with STEP 1 (`CLAUDE.md` creation and directory scaffolding), then launch the Sub-Agents.
```