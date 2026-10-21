import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../models/sensory_state.dart';
import 'audio_engine.dart';
import 'dsp_bridge.dart';
import 'voice_weave.dart';

/// Browser audio: the pure-Dart engine rendered on the main thread into a Web Audio
/// `ScriptProcessorNode`. Fine for testing the PWA on phones and tablets; a production web
/// build would move [PureDartDsp] into an AudioWorklet.
///
/// Browsers only allow audio after a user gesture, so the context is created and resumed by
/// the first pointer / key event on the page (and again by [start], harmlessly).
class WebAudioEngine implements AudioEngine, VoiceWeaveEngine {
  WebAudioEngine() : _core = PureDartDsp() {
    for (final String type in _gestureEvents) {
      web.document.addEventListener(type, _onGesture);
    }
  }

  static const List<String> _gestureEvents = <String>['pointerdown', 'touchend', 'keydown', 'click'];

  /// 4096 frames = 85 ms; large enough to ride out main-thread jank, small enough for taps.
  static const int _bufferFrames = 4096;

  final PureDartDsp _core;
  final Float32List _interleaved = Float32List(_bufferFrames * 2);
  final Float32List _left = Float32List(_bufferFrames);
  final Float32List _right = Float32List(_bufferFrames);

  web.AudioContext? _context;
  web.ScriptProcessorNode? _node;
  late final JSFunction _onGesture = ((web.Event _) => _ensureRunning()).toJS;
  bool _disposed = false;

  /// True once the browser has let the audio graph run.
  bool get isRunning => _context?.state == 'running';

  /// Sample rate the browser actually granted (48 000 is requested).
  int? get contextSampleRate => _context?.sampleRate.round();

  void _ensureRunning() {
    if (_disposed) return;
    var ctx = _context;
    if (ctx == null) {
      ctx = web.AudioContext(web.AudioContextOptions(
        sampleRate: AudioEngine.sampleRate,
        latencyHint: 'playback'.toJS,
      ));
      final node = ctx.createScriptProcessor(_bufferFrames, 0, 2);
      node.onaudioprocess = ((web.AudioProcessingEvent e) => _fill(e)).toJS;
      node.connect(ctx.destination);
      _context = ctx;
      _node = node;
    }
    if (ctx.state != 'running') {
      ctx.resume();
    } else {
      for (final String type in _gestureEvents) {
        web.document.removeEventListener(type, _onGesture);
      }
    }
  }

  void _fill(web.AudioProcessingEvent e) {
    final buffer = e.outputBuffer;
    final frames = buffer.length < _bufferFrames ? buffer.length : _bufferFrames;
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
    _ensureRunning();
    _core.start(preset);
  }

  @override
  void stop() => _core.stop();

  @override
  void switchPreset(SessionPreset preset) => _core.switchPreset(preset);

  @override
  void applyIso(IsoSnapshot snapshot) => _core.applyIso(snapshot);

  @override
  void setProfileLimits({double highCutHz = 0, double masterCap = 1.0, bool allowWater = true}) =>
      _core.setProfileLimits(highCutHz: highCutHz, masterCap: masterCap, allowWater: allowWater);

  @override
  void triggerNote(int degree, double velocity) => _core.triggerNote(degree, velocity);

  @override
  void render(Float32List out, int frames) => _core.render(out, frames);

  @override
  void loadVoice(int slot, Float32List mono48k) => _core.loadVoice(slot, mono48k);

  @override
  void clearVoice(int slot) => _core.clearVoice(slot);

  @override
  void setVoiceWeave({required bool enabled, double gain = 0.12, double intervalSec = 45}) =>
      _core.setVoiceWeave(enabled: enabled, gain: gain, intervalSec: intervalSec);

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final String type in _gestureEvents) {
      web.document.removeEventListener(type, _onGesture);
    }
    _node?.disconnect();
    _node?.onaudioprocess = null;
    _context?.close();
    _core.dispose();
  }
}
