import 'dart:js_interop';
import 'dart:typed_data';

import '../models/sensory_state.dart';
import 'pure_dart_dsp.dart';

@JS('auraCreateDsp')
external set _factory(JSFunction value);

/// Compiled separately so the browser's audio thread runs the same tested DSP.
void main() {
  _factory = (() => createJSInteropWrapper(_WorkletDsp())).toJS;
}

@JSExport()
class _WorkletDsp {
  final PureDartDsp _core = PureDartDsp();
  final Float32List _samples = Float32List(128 * 2);

  JSFloat32Array process(int frames) {
    _core.render(_samples, frames);
    return _samples.toJS;
  }

  void start(int preset) => _core.start(SessionPreset.values[preset]);

  void stop() => _core.stop();

  void switchPreset(int preset) =>
      _core.switchPreset(SessionPreset.values[preset]);

  void applyIso(double bpm, double lpfHz, double rhythm, double pad,
      double brown, double heart) =>
      _core.applyIso(IsoSnapshot(
        elapsedMs: 0,
        phase: IsoPhase.match,
        bpm: bpm,
        lpfHz: lpfHz,
        shaderSpeed: 1,
        dimmerAlpha: 0,
        rhythmWeight: rhythm,
        padWeight: pad,
        brownNoiseGain: brown,
        heartbeatGain: heart,
      ));

  void setProfileLimits(double highCutHz, double masterCap, bool allowWater) =>
      _core.setProfileLimits(
          highCutHz: highCutHz, masterCap: masterCap, allowWater: allowWater);

  void triggerNote(int degree, double velocity) =>
      _core.triggerNote(degree, velocity);

  void loadVoice(int slot, JSFloat32Array mono) =>
      _core.loadVoice(slot, mono.toDart);

  void clearVoice(int slot) => _core.clearVoice(slot);

  void setVoiceWeave(bool enabled, double gain, double intervalSec) =>
      _core.setVoiceWeave(
          enabled: enabled, gain: gain, intervalSec: intervalSec);

  void dispose() => _core.dispose();
}
