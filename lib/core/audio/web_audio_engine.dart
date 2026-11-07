import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import '../models/sensory_state.dart';
import 'audio_engine.dart';
import 'pure_dart_dsp.dart';
import 'voice_weave.dart';

/// Browser playback runs the shared DSP on the audio thread, not Flutter's UI
/// thread. Use `playback: false` for synchronous, deterministic headless renders.
class WebAudioEngine implements AudioEngine, VoiceWeaveEngine {
  WebAudioEngine({bool playback = true})
      : _offlineCore = playback ? null : PureDartDsp() {
    if (playback) {
      for (final type in _gestureEvents) {
        web.document.addEventListener(type, _onGesture);
      }
    }
  }

  static const List<String> _gestureEvents = [
    'pointerdown', 'touchend', 'keydown', 'click',
  ];

  final PureDartDsp? _offlineCore;
  final List<JSArray<JSAny?>> _pending = [];
  web.AudioContext? _context;
  web.AudioWorkletNode? _node;
  Future<void>? _initializing;
  Object? _failure;
  bool _disposed = false;
  late final JSFunction _onGesture = ((web.Event _) => _ensureRunning()).toJS;

  bool get isRunning =>
      _node != null && _failure == null && _context?.state == 'running';

  int? get contextSampleRate => _context?.sampleRate.round();

  void _removeGestures() {
    for (final type in _gestureEvents) {
      web.document.removeEventListener(type, _onGesture);
    }
  }

  void _reportFailure(Object error, StackTrace stack) {
    _failure = error;
    _pending.clear();
    _node?.disconnect();
    _removeGestures();
    FlutterError.reportError(FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'AuraSOS web audio',
      context: ErrorDescription('while starting or processing audio playback'),
    ));
  }

  void _ensureRunning() {
    if (_disposed || _offlineCore != null || _failure != null) return;
    try {
      final ctx = _context ??= web.AudioContext(web.AudioContextOptions(
        sampleRate: AudioEngine.sampleRate,
        latencyHint: 'playback'.toJS,
      ));
      if (ctx.sampleRate != AudioEngine.sampleRate) {
        throw StateError('AuraSOS audio requires a 48000 Hz context');
      }
      // Resume synchronously within the gesture, before waiting for the module.
      if (ctx.state != 'running') {
        unawaited(ctx.resume().toDart.then((_) {
          if (!_disposed && ctx.state == 'running') _removeGestures();
        }, onError: (Object error, StackTrace stack) {
          _reportFailure(error, stack);
        }));
      }
      _initializing ??= _initialize(ctx);
    } catch (error, stack) {
      _reportFailure(error, stack);
    }
  }

  Future<void> _initialize(web.AudioContext ctx) async {
    try {
      await ctx.audioWorklet.addModule(
        web.URL('audio_worklet.js', web.document.baseURI).href,
      ).toDart;
      if (_disposed || _failure != null) return;
      final node = web.AudioWorkletNode(ctx, 'aura-dsp',
          web.AudioWorkletNodeOptions(
            numberOfInputs: 0,
            numberOfOutputs: 1,
            outputChannelCount: [2.toJS].toJS,
          ));
      node.onprocessorerror = ((web.Event _) {
        _reportFailure(
            StateError('AuraSOS audio processor failed'), StackTrace.current);
      }).toJS;
      _node = node;
      for (final command in _pending) {
        node.port.postMessage(command);
      }
      _pending.clear();
      node.connect(ctx.destination);
    } catch (error, stack) {
      _reportFailure(error, stack);
    }
  }

  void _send(String command, [List<JSAny?> args = const []]) {
    if (_disposed) return;
    if (_failure != null) {
      throw StateError('AuraSOS audio is unavailable: $_failure');
    }
    final message = <JSAny?>[command.toJS, ...args].toJS;
    final node = _node;
    if (node == null) {
      _pending.add(message);
    } else {
      node.port.postMessage(message);
    }
  }

  @override
  void start(SessionPreset preset) {
    if (_offlineCore case final core?) {
      core.start(preset);
    } else {
      _ensureRunning();
      _send('start', [preset.index.toJS]);
    }
  }

  @override
  void stop() {
    if (_offlineCore case final core?) {
      core.stop();
    } else {
      _send('stop');
    }
  }

  @override
  void switchPreset(SessionPreset preset) {
    if (_offlineCore case final core?) {
      core.switchPreset(preset);
    } else {
      _send('switchPreset', [preset.index.toJS]);
    }
  }

  @override
  void applyIso(IsoSnapshot s) {
    if (_offlineCore case final core?) {
      core.applyIso(s);
    } else {
      _send('applyIso', [
        s.bpm.toJS, s.lpfHz.toJS, s.rhythmWeight.toJS, s.padWeight.toJS,
        s.brownNoiseGain.toJS, s.heartbeatGain.toJS,
      ]);
    }
  }

  @override
  void setProfileLimits(
      {double highCutHz = 0, double masterCap = 1, bool allowWater = true}) {
    if (_offlineCore case final core?) {
      core.setProfileLimits(
          highCutHz: highCutHz, masterCap: masterCap, allowWater: allowWater);
    } else {
      _send('setProfileLimits',
          [highCutHz.toJS, masterCap.toJS, allowWater.toJS]);
    }
  }

  @override
  void triggerNote(int degree, double velocity) {
    if (_offlineCore case final core?) {
      core.triggerNote(degree, velocity);
    } else {
      _send('triggerNote', [degree.toJS, velocity.toJS]);
    }
  }

  @override
  void render(Float32List out, int frames) {
    final core = _offlineCore;
    if (core == null) {
      throw StateError('Use WebAudioEngine(playback: false) to render offline');
    }
    core.render(out, frames);
  }

  @override
  void loadVoice(int slot, Float32List mono48k) {
    if (_offlineCore case final core?) {
      core.loadVoice(slot, mono48k);
    } else {
      _send('loadVoice', [slot.toJS, mono48k.toJS]);
    }
  }

  @override
  void clearVoice(int slot) {
    if (_offlineCore case final core?) {
      core.clearVoice(slot);
    } else {
      _send('clearVoice', [slot.toJS]);
    }
  }

  @override
  void setVoiceWeave(
      {required bool enabled, double gain = 0.12, double intervalSec = 45}) {
    if (_offlineCore case final core?) {
      core.setVoiceWeave(
          enabled: enabled, gain: gain, intervalSec: intervalSec);
    } else {
      _send('setVoiceWeave', [enabled.toJS, gain.toJS, intervalSec.toJS]);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    if (_node != null) _send('dispose');
    _disposed = true;
    _removeGestures();
    _pending.clear();
    _node?.disconnect();
    if (_context case final ctx?) unawaited(ctx.close().toDart);
    _offlineCore?.dispose();
  }
}
