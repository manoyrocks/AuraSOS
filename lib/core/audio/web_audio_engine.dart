import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import '../models/sensory_state.dart';
import 'audio_engine.dart';
import 'dsp_bridge.dart';
import 'sound_gate.dart';
import 'voice_weave.dart';

/// Browser audio: the pure-Dart engine rendered on the main thread into a Web Audio
/// `ScriptProcessorNode`. Fine for testing the PWA on phones and tablets; a production web
/// build would move [PureDartDsp] into an AudioWorklet.
///
/// Browsers only let audio play after a user gesture, and the rules differ: Chrome on a touch
/// screen counts the *release* of a tap, Safari wants the context resumed inside the gesture
/// handler, and the context can be suspended again after a call or when the app is backgrounded.
/// So the engine listens on the window (capture phase, so Flutter cannot swallow the events) for
/// every kind of gesture, for the whole life of the app, and resumes whenever the context is not
/// running. [soundBlocked] tells the UI when a session is waiting for that touch.
class WebAudioEngine implements AudioEngine, VoiceWeaveEngine, SoundGate {
  WebAudioEngine() : _core = PureDartDsp() {
    _requestMediaPlayback();
    final options = web.AddEventListenerOptions(capture: true, passive: true);
    for (final String type in _gestureEvents) {
      web.window.addEventListener(type, _onGesture, options);
    }
  }

  static const List<String> _gestureEvents = <String>[
    'pointerdown',
    'pointerup',
    'touchstart',
    'touchend',
    'mousedown',
    'mouseup',
    'click',
    'keydown',
  ];

  /// 4096 frames = 85 ms; large enough to ride out main-thread jank, small enough for taps.
  static const int _bufferFrames = 4096;

  final PureDartDsp _core;
  final Float32List _interleaved = Float32List(_bufferFrames * 2);
  final Float32List _left = Float32List(_bufferFrames);
  final Float32List _right = Float32List(_bufferFrames);
  final ValueNotifier<bool> _blocked = ValueNotifier<bool>(false);

  web.AudioContext? _context;
  web.ScriptProcessorNode? _node;
  late final JSFunction _onGesture = ((web.Event _) => _ensureRunning()).toJS;
  bool _sessionWanted = false;
  bool _unlocked = false;
  bool _disposed = false;

  @override
  ValueListenable<bool> get soundBlocked => _blocked;

  /// True once the browser has let the audio graph run.
  bool get isRunning => _context?.state == 'running';

  /// Sample rate the browser actually granted (48 000 is requested).
  int? get contextSampleRate => _context?.sampleRate.round();

  /// iOS Safari 16.4+: treat the page as media playback so the ringer / silent switch does not
  /// mute it (Web Audio is otherwise muted by the switch). A no-op where the API does not exist.
  void _requestMediaPlayback() {
    try {
      final JSObject navigator = web.window.navigator as JSObject;
      if (!navigator.has('audioSession')) return;
      navigator
          .getProperty<JSObject?>('audioSession'.toJS)
          ?.setProperty('type'.toJS, 'playback'.toJS);
    } catch (_) {
      // Sound still works without it; the silent switch just keeps winning.
    }
  }

  web.AudioContext _create() {
    final ctx = web.AudioContext(web.AudioContextOptions(
      sampleRate: AudioEngine.sampleRate,
      latencyHint: 'playback'.toJS,
    ));
    final node = ctx.createScriptProcessor(_bufferFrames, 0, 2);
    node.onaudioprocess = ((web.AudioProcessingEvent e) => _fill(e)).toJS;
    node.connect(ctx.destination);
    ctx.onstatechange = ((web.Event _) => _syncBlocked()).toJS;
    _context = ctx;
    _node = node;
    return ctx;
  }

  /// Older iOS only unlocks audio once something has been *started* inside a gesture.
  void _playSilentUnlock(web.AudioContext ctx) {
    if (_unlocked) return;
    try {
      final source = ctx.createBufferSource();
      source.buffer = ctx.createBuffer(1, 1, ctx.sampleRate);
      source.connect(ctx.destination);
      source.start();
      _unlocked = true;
    } catch (_) {
      // Try again on the next gesture.
    }
  }

  void _ensureRunning() {
    if (_disposed) return;
    final ctx = _context ?? _create();
    if (ctx.state == 'running') {
      _syncBlocked();
      return;
    }
    _playSilentUnlock(ctx);
    ctx.resume().toDart.then<void>((_) => _syncBlocked(),
        onError: (Object _) => _syncBlocked());
    _syncBlocked();
  }

  void _syncBlocked() {
    if (_disposed) return;
    final ctx = _context;
    _blocked.value = _sessionWanted && (ctx == null || ctx.state != 'running');
  }

  void _fill(web.AudioProcessingEvent e) {
    final buffer = e.outputBuffer;
    final frames =
        buffer.length < _bufferFrames ? buffer.length : _bufferFrames;
    _core.render(_interleaved, frames);
    for (var i = 0; i < frames; i++) {
      _left[i] = _interleaved[2 * i];
      _right[i] = _interleaved[2 * i + 1];
    }
    buffer.copyToChannel(_left.toJS, 0);
    buffer.copyToChannel(_right.toJS, 1);
  }

  @override
  void start(SessionPreset preset) {
    _sessionWanted = true;
    _ensureRunning();
    _core.start(preset);
    // If the browser has not let the sound play a moment later, say so.
    Future<void>.delayed(const Duration(milliseconds: 400), _syncBlocked);
  }

  @override
  void stop() => _core.stop();

  @override
  void switchPreset(SessionPreset preset) => _core.switchPreset(preset);

  @override
  void applyIso(IsoSnapshot snapshot) => _core.applyIso(snapshot);

  @override
  void setProfileLimits(
          {double highCutHz = 0,
          double masterCap = 1.0,
          bool allowWater = true}) =>
      _core.setProfileLimits(
          highCutHz: highCutHz, masterCap: masterCap, allowWater: allowWater);

  @override
  void triggerNote(int degree, double velocity) =>
      _core.triggerNote(degree, velocity);

  @override
  void render(Float32List out, int frames) => _core.render(out, frames);

  @override
  void loadVoice(int slot, Float32List mono48k) =>
      _core.loadVoice(slot, mono48k);

  @override
  void clearVoice(int slot) => _core.clearVoice(slot);

  @override
  void setVoiceWeave(
          {required bool enabled,
          double gain = 0.12,
          double intervalSec = 45}) =>
      _core.setVoiceWeave(
          enabled: enabled, gain: gain, intervalSec: intervalSec);

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final options = web.EventListenerOptions(capture: true);
    for (final String type in _gestureEvents) {
      web.window.removeEventListener(type, _onGesture, options);
    }
    _node?.disconnect();
    _node?.onaudioprocess = null;
    _context?.close();
    _core.dispose();
    _blocked.dispose();
  }
}
