import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../models/sensory_state.dart';
import 'audio_engine.dart';
import 'voice_weave.dart';

typedef _CreateC = Pointer<Void> Function(Int32);
typedef _CreateD = Pointer<Void> Function(int);
typedef _DestroyC = Void Function(Pointer<Void>);
typedef _DestroyD = void Function(Pointer<Void>);
typedef _IntC = Void Function(Pointer<Void>, Int32);
typedef _IntD = void Function(Pointer<Void>, int);
typedef _StopC = Void Function(Pointer<Void>);
typedef _StopD = void Function(Pointer<Void>);
typedef _IsoC = Void Function(
    Pointer<Void>, Double, Double, Double, Double, Double, Double);
typedef _IsoD = void Function(
    Pointer<Void>, double, double, double, double, double, double);
typedef _LimitsC = Void Function(Pointer<Void>, Double, Double, Int32);
typedef _LimitsD = void Function(Pointer<Void>, double, double, int);
typedef _NoteC = Void Function(Pointer<Void>, Int32, Double);
typedef _NoteD = void Function(Pointer<Void>, int, double);
typedef _RenderC = Void Function(Pointer<Void>, Pointer<Float>, Int32);
typedef _RenderD = void Function(Pointer<Void>, Pointer<Float>, int);
typedef _LoadVoiceC = Void Function(
    Pointer<Void>, Int32, Pointer<Float>, Int32);
typedef _LoadVoiceD = void Function(Pointer<Void>, int, Pointer<Float>, int);
typedef _VoiceCfgC = Void Function(Pointer<Void>, Int32, Double, Double);
typedef _VoiceCfgD = void Function(Pointer<Void>, int, double, double);
typedef _OpenOutC = Int32 Function(Pointer<Void>);
typedef _OpenOutD = int Function(Pointer<Void>);

/// dart:ffi binding to the C++ engine (`libaurasync_dsp`).
class NativeDsp implements AudioEngine, VoiceWeaveEngine {
  NativeDsp._(DynamicLibrary lib)
      : _create = lib.lookupFunction<_CreateC, _CreateD>('aura_dsp_create'),
        _destroy = lib.lookupFunction<_DestroyC, _DestroyD>('aura_dsp_destroy'),
        _start = lib.lookupFunction<_IntC, _IntD>('aura_dsp_start'),
        _stop = lib.lookupFunction<_StopC, _StopD>('aura_dsp_stop'),
        _switch = lib.lookupFunction<_IntC, _IntD>('aura_dsp_switch_preset'),
        _iso = lib.lookupFunction<_IsoC, _IsoD>('aura_dsp_apply_iso'),
        _limits = lib
            .lookupFunction<_LimitsC, _LimitsD>('aura_dsp_set_profile_limits'),
        _note = lib.lookupFunction<_NoteC, _NoteD>('aura_dsp_trigger_note'),
        _render = lib.lookupFunction<_RenderC, _RenderD>('aura_dsp_render'),
        _loadVoice =
            lib.lookupFunction<_LoadVoiceC, _LoadVoiceD>('aura_dsp_load_voice'),
        _clearVoice = lib.lookupFunction<_IntC, _IntD>('aura_dsp_clear_voice'),
        _voiceCfg = lib
            .lookupFunction<_VoiceCfgC, _VoiceCfgD>('aura_dsp_set_voice_weave'),
        _openOut = lib.lookupFunction<_OpenOutC, _OpenOutD>('aura_audio_open'),
        _closeOut =
            lib.lookupFunction<_DestroyC, _DestroyD>('aura_audio_close') {
    _handle = _create(AudioEngine.sampleRate);
    if (_handle == nullptr) {
      throw StateError('aura_dsp_create returned null');
    }
  }

  final _CreateD _create;
  final _DestroyD _destroy;
  final _IntD _start;
  final _StopD _stop;
  final _IntD _switch;
  final _IsoD _iso;
  final _LimitsD _limits;
  final _NoteD _note;
  final _RenderD _render;
  final _LoadVoiceD _loadVoice;
  final _IntD _clearVoice;
  final _VoiceCfgD _voiceCfg;
  final _OpenOutD _openOut;
  final _DestroyD _closeOut;

  late Pointer<Void> _handle;
  bool _playing = false;
  Pointer<Float> _buffer = nullptr;
  int _bufferFrames = 0;
  bool _disposed = false;

  /// True once the platform speaker output is pulling audio from the engine.
  bool get isPlaying => _playing;

  /// Opens the platform library or returns null when it is unavailable. With [playback]
  /// the platform audio thread starts pulling from the engine immediately (silent until
  /// [start]); tests pass `playback: false` to keep rendering offline.
  static NativeDsp? tryLoad({bool playback = true}) {
    try {
      final DynamicLibrary lib;
      if (Platform.isAndroid || Platform.isLinux) {
        lib = DynamicLibrary.open('libaurasync_dsp.so');
      } else if (Platform.isIOS) {
        lib = DynamicLibrary.process();
      } else if (Platform.isMacOS) {
        lib = DynamicLibrary.open('libaurasync_dsp.dylib');
      } else if (Platform.isWindows) {
        lib = DynamicLibrary.open('aurasync_dsp.dll');
      } else {
        return null;
      }
      final NativeDsp engine = NativeDsp._(lib);
      if (playback) engine._playing = engine._openOut(engine._handle) == 1;
      return engine;
    } catch (_) {
      return null;
    }
  }

  @override
  void start(SessionPreset preset) {
    if (!_disposed) _start(_handle, preset.index);
  }

  @override
  void stop() {
    if (!_disposed) _stop(_handle);
  }

  @override
  void switchPreset(SessionPreset preset) {
    if (!_disposed) _switch(_handle, preset.index);
  }

  @override
  void applyIso(IsoSnapshot s) {
    if (_disposed) return;
    _iso(_handle, s.bpm, s.lpfHz, s.rhythmWeight, s.padWeight, s.brownNoiseGain,
        s.heartbeatGain);
  }

  @override
  void setProfileLimits(
      {double highCutHz = 0, double masterCap = 1.0, bool allowWater = true}) {
    if (!_disposed) _limits(_handle, highCutHz, masterCap, allowWater ? 1 : 0);
  }

  @override
  void triggerNote(int degree, double velocity) {
    if (!_disposed) _note(_handle, degree, velocity);
  }

  @override
  void loadVoice(int slot, Float32List mono48k) {
    if (_disposed || mono48k.isEmpty) return;
    final n = math.min(mono48k.length, VoiceWeaveEngine.maxFrames);
    final Pointer<Float> tmp = calloc<Float>(n);
    try {
      tmp.asTypedList(n).setRange(0, n, mono48k);
      _loadVoice(_handle, slot, tmp, n); // the engine copies synchronously
    } finally {
      calloc.free(tmp);
    }
  }

  @override
  void clearVoice(int slot) {
    if (!_disposed) _clearVoice(_handle, slot);
  }

  @override
  void setVoiceWeave(
      {required bool enabled, double gain = 0.12, double intervalSec = 45}) {
    if (!_disposed) _voiceCfg(_handle, enabled ? 1 : 0, gain, intervalSec);
  }

  @override
  void render(Float32List out, int frames) {
    if (_disposed) {
      out.fillRange(0, math.min(out.length, frames * 2), 0.0);
      return;
    }
    if (frames > _bufferFrames) {
      if (_buffer != nullptr) calloc.free(_buffer);
      _buffer = calloc<Float>(frames * 2);
      _bufferFrames = frames;
    }
    _render(_handle, _buffer, frames);
    out.setRange(0, frames * 2, _buffer.asTypedList(frames * 2));
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_playing) {
      _closeOut(_handle);
      _playing = false;
    }
    _destroy(_handle);
    if (_buffer != nullptr) {
      calloc.free(_buffer);
      _buffer = nullptr;
    }
  }
}

