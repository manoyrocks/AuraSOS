import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/audio/audio_engine.dart';
import '../../core/audio/sound_gate.dart';
import '../../core/audio/voice_weave.dart';
import '../../core/engine/iso_principle_controller.dart';
import '../../core/models/sensory_state.dart';
import '../../core/platform/screen_awake.dart';
import '../../data/models.dart';
import '../mode_labels.dart';
import '../../data/sensory_profile_repository.dart';
import '../../data/voice_library.dart';
import '../widgets/child_touch_lock_kiosk.dart';
import '../widgets/sensory_shader_view.dart';
import '../widgets/sub_os_dimmer.dart';
import '../widgets/visual_transition_timer.dart';

/// Runs one regulation session. The [audio] engine is owned by the app and is never
/// disposed here; on exit it is stopped, which applies its own 4 s fade-out.
class SessionScreen extends StatefulWidget {
  const SessionScreen({
    super.key,
    required this.preset,
    required this.audio,
    required this.repository,
    this.library,
    this.focusDuration = const Duration(minutes: 20),
  });

  final SessionPreset preset;
  final AudioEngine audio;
  final SensoryProfileRepository repository;

  /// Kept for callers that thread it through; phrases are loaded at startup and by the
  /// caregiver screen, never during a session.
  final VoiceLibrary? library;
  final Duration focusDuration;

  /// Shader for [preset] under the caregiver's [mode]; null means a black screen (audio only).
  static ShaderKind? visualFor(SessionPreset preset, VisualMode mode) {
    switch (mode) {
      case VisualMode.auto:
        return shaderFor(preset);
      case VisualMode.tunnel:
        return ShaderKind.tunnel;
      case VisualMode.bubbles:
        return ShaderKind.bubbles;
      case VisualMode.lanterns:
        return ShaderKind.lanterns;
      case VisualMode.breathingOrb:
        return ShaderKind.breathingOrb;
      case VisualMode.crystals:
        return ShaderKind.crystals;
      case VisualMode.starfield:
        return ShaderKind.starfield;
      case VisualMode.aurora:
        return ShaderKind.aurora;
      case VisualMode.mandala:
        return ShaderKind.mandala;
      case VisualMode.blackScreen:
        return null;
    }
  }

  static ShaderKind shaderFor(SessionPreset preset) {
    switch (preset) {
      case SessionPreset.isoDownRegulator:
        return ShaderKind.tunnel;
      case SessionPreset.deepCrisisAnchor:
        return ShaderKind.lanterns;
      case SessionPreset.focusClassroom:
        return ShaderKind.bubbles;
      case SessionPreset.calmStim:
        return ShaderKind.breathingOrb;
    }
  }

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  final ValueNotifier<IsoSnapshot?> _snapshot =
      ValueNotifier<IsoSnapshot?>(null);
  final ShaderTouchSource _touchSource = ShaderTouchSource();
  final Stopwatch _elapsed = Stopwatch()..start();
  final List<Timer> _resolutionTimers = <Timer>[];
  IsoPrincipleController? _controller;
  Future<int?>? _logId;
  double _brightnessCap = 1.0;
  VisualMode _visualMode = VisualMode.auto;
  late int _focusMinutes = widget.focusDuration.inMinutes;
  bool _prompting = false;
  bool _chipVisible = true;
  Timer? _chipTimer;
  bool _audioStopped = false;
  bool _disposed = false;

  bool get _usesIso =>
      widget.preset == SessionPreset.isoDownRegulator ||
      widget.preset == SessionPreset.deepCrisisAnchor;

  @override
  void initState() {
    super.initState();
    // Everything below is synchronous so the first frame is never delayed.
    widget.audio.start(widget.preset);
    unawaited(ScreenAwake.set(true));
    _armChipTimer();
    if (_usesIso) {
      final IsoPrincipleController c = IsoPrincipleController(
        audio: widget.audio,
        onSnapshot: _onSnapshot,
      );
      c.deepCrisis = widget.preset == SessionPreset.deepCrisisAnchor;
      c.start();
      _controller = c;
    }
    _logId = _startLog();
    unawaited(_loadProfile());
  }

  /// The mode chip fades away after a few seconds so the visuals stay clean, and returns
  /// briefly whenever the screen is touched.
  void _armChipTimer() {
    _chipTimer?.cancel();
    _chipTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _chipVisible = false);
    });
  }

  void _pokeChip() {
    if (_disposed) return;
    if (!_chipVisible) setState(() => _chipVisible = true);
    _armChipTimer();
  }

  void _onSnapshot(IsoSnapshot s) {
    if (_disposed) return;
    _snapshot.value = s;
  }

  Future<int?> _startLog() async {
    try {
      return await widget.repository
          .startSessionLog(widget.preset, DateTime.now());
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await widget.repository.activeProfile();
      if (_disposed) return;
      widget.audio.setProfileLimits(
        highCutHz: profile.effectiveHighCutHz,
        masterCap: profile.masterVolumeCap,
        allowWater: !profile.disableWater,
      );
      final AudioEngine engine = widget.audio;
      if (engine is VoiceWeaveEngine) {
        (engine as VoiceWeaveEngine).setVoiceWeave(
          enabled: profile.voiceEnabled,
          gain: profile.voiceGain,
          intervalSec: profile.voiceIntervalSec,
        );
      }
      setState(() {
        _brightnessCap = profile.brightnessCap.clamp(0.02, 1.0).toDouble();
        _visualMode = profile.visualMode;
        _focusMinutes = profile.focusMinutes;
      });
    } catch (_) {
      // Keep defaults; the child must never see an error.
    }
  }

  void _stopAudioOnce() {
    if (_audioStopped) return;
    _audioStopped = true;
    for (final Timer t in _resolutionTimers) {
      t.cancel();
    }
    _resolutionTimers.clear();
    _controller?.stop();
    widget.audio.stop();
  }

  /// Gentle C-major resolution (C, E, G, then low C) played softly as the timer nears its end.
  void _resolveHarmonically() {
    const List<int> degrees = <int>[5, 7, 8, 0];
    for (int i = 0; i < degrees.length; i++) {
      _resolutionTimers.add(Timer(Duration(milliseconds: 900 * i), () {
        if (_disposed || _audioStopped) return;
        widget.audio.triggerNote(degrees[i], 0.3);
      }));
    }
  }

  void _onTimerFinished() {
    // Let the session end quietly; the adult unlocks and rates afterwards.
    _stopAudioOnce();
  }

  void _onUnlocked() {
    if (!mounted || _prompting) return;
    setState(() => _prompting = true);
  }

  void _resumeChildView() {
    if (!mounted) return;
    setState(() => _prompting = false);
  }

  void _rateAndExit(EfficacyRating rating) {
    final IsoPhase phase = _snapshot.value?.phase ?? IsoPhase.match;
    final int durationSec = _elapsed.elapsed.inSeconds;
    final Future<int?>? logFuture = _logId;
    _stopAudioOnce();
    unawaited(_persist(logFuture, rating, durationSec, phase));
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _persist(
    Future<int?>? logFuture,
    EfficacyRating rating,
    int durationSec,
    IsoPhase phase,
  ) async {
    try {
      final int? id = await logFuture;
      if (id == null) return;
      await widget.repository
          .finishSessionLog(id, durationSec: durationSec, reachedPhase: phase);
      await widget.repository.rateSession(id, rating);
    } catch (_) {
      // Logging is best-effort.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _chipTimer?.cancel();
    unawaited(ScreenAwake.set(false));
    _stopAudioOnce();
    _snapshot.dispose();
    _touchSource.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ShaderKind? kind =
        SessionScreen.visualFor(widget.preset, _visualMode);
    final bool showTimer = widget.preset == SessionPreset.focusClassroom;

    final Widget kiosk = ChildTouchLockKiosk(
      audio: widget.audio,
      onUnlocked: _onUnlocked,
      onTouch: (Offset o) {
        _touchSource.touch(o);
        _pokeChip();
      },
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ValueListenableBuilder<IsoSnapshot?>(
            valueListenable: _snapshot,
            builder: (BuildContext context, IsoSnapshot? snap, Widget? _) {
              if (kind == null) return const ColoredBox(color: Colors.black);
              return SensoryShaderView(
                kind: kind,
                speed: snap?.shaderSpeed ?? 1.0,
                touchSource: _touchSource,
              );
            },
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Center(
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _chipVisible ? 1 : 0,
                      duration: const Duration(milliseconds: 900),
                      child: ValueListenableBuilder<IsoSnapshot?>(
                        valueListenable: _snapshot,
                        builder: (BuildContext context, IsoSnapshot? snap,
                            Widget? _) {
                          final bool iso =
                              widget.preset == SessionPreset.isoDownRegulator;
                          final String text = modeLabel(widget.preset) +
                              (iso && snap != null
                                  ? ' · ${phaseHint(snap.phase)}'
                                  : '');
                          return _ModeChip(text: text);
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (widget.audio is SoundGate)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(top: 66),
                  child: Center(
                    child: IgnorePointer(
                      child: ValueListenableBuilder<bool>(
                        valueListenable:
                            (widget.audio as SoundGate).soundBlocked,
                        builder:
                            (BuildContext context, bool blocked, Widget? _) =>
                                blocked
                                    ? const _SoundHint()
                                    : const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (showTimer)
            Positioned(
              left: 0,
              right: 0,
              bottom: 40,
              child: Center(
                child: VisualTransitionTimer(
                  key: ValueKey<int>(_focusMinutes),
                  duration: Duration(minutes: _focusMinutes),
                  onFinished: _onTimerFinished,
                  onResolutionCadence: _resolveHarmonically,
                ),
              ),
            ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ValueListenableBuilder<IsoSnapshot?>(
            valueListenable: _snapshot,
            child: kiosk,
            builder: (BuildContext context, IsoSnapshot? snap, Widget? child) {
              final double protocol = 1.0 - (snap?.dimmerAlpha ?? 0.0);
              final double luminance =
                  (protocol * _brightnessCap).clamp(0.02, 1.0).toDouble();
              return SubOsDimmer(luminance: luminance, child: child!);
            },
          ),
          if (_prompting)
            _RatingPrompt(onRate: _rateAndExit, onDismiss: _resumeChildView),
        ],
      ),
    );
  }
}

/// Adult-facing one-tap outcome prompt: emoji and colour only.
class _RatingPrompt extends StatelessWidget {
  const _RatingPrompt({required this.onRate, required this.onDismiss});

  final ValueChanged<EfficacyRating> onRate;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xE6000000),
      child: SafeArea(
        child: Stack(
          children: <Widget>[
            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 28,
                runSpacing: 28,
                children: <Widget>[
                  _RatingButton(
                    emoji: '\u{1F642}',
                    color: const Color(0xFF2E9E5B),
                    label: 'Effective',
                    onTap: () => onRate(EfficacyRating.effective),
                  ),
                  _RatingButton(
                    emoji: '\u{1F610}',
                    color: const Color(0xFFD9A21B),
                    label: 'Neutral',
                    onTap: () => onRate(EfficacyRating.neutral),
                  ),
                  _RatingButton(
                    emoji: '\u{1F623}',
                    color: const Color(0xFFC94A4A),
                    label: 'Escalated',
                    onTap: () => onRate(EfficacyRating.escalated),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                iconSize: 36,
                color: const Color(0x99FFFFFF),
                tooltip: 'Back',
                icon: const Icon(Icons.close_rounded),
                onPressed: onDismiss,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RatingButton extends StatelessWidget {
  const _RatingButton({
    required this.emoji,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final String emoji;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: color,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 120,
            height: 120,
            child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 56))),
          ),
        ),
      ),
    );
  }
}

/// Quiet pill naming the current mode (and, for the calm-down, its stage).
class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x33000000),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        child: Text(
          text,
          style: const TextStyle(
            color: Color(0xB3FFFFFF),
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}

/// Shown only while the browser is still holding sound back: the next touch lets it play.
class _SoundHint extends StatelessWidget {
  const _SoundHint();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x66000000),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.volume_off_rounded, size: 20, color: Color(0xCCFFFFFF)),
            SizedBox(width: 10),
            Text(
              'Tap the screen to turn on sound',
              style: TextStyle(
                  color: Color(0xCCFFFFFF),
                  fontSize: 16,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
