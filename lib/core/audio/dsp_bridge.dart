import 'dart:math' as math;
import 'dart:typed_data';

import '../models/sensory_state.dart';
import 'audio_engine.dart';
import 'engine_factory.dart';
import 'voice_weave.dart';

const double _sr = 48000.0;
const double _twoPi = 2 * math.pi;
const double _ceiling =
    0.7079457; // 0.70794578 rounded down so float32 never exceeds it
const int _xfSamples = AudioEngine.crossfadeSamples;
const int _ctlStep = 16;
const double _slewLimit = 0.0045;
const double _velocityCap = 0.85;
const int _kalimbaAttack = 2400; // 50 ms cosine attack
const int _stemCount = 7;
const int _stBrown = 0;
const int _stPink = 1;
const int _stPulse = 2;
const int _stPad = 3;
const int _stHeart = 4;
const int _stDrone = 5;
const int _stWater = 6;

const List<int> _marimbaPattern = [0, 2, 4, 2, 3, 1, 4, 2];
const List<int> _celloRoots = [0, 2, 3, 1];
const List<double> _padHz = [130.81, 164.81, 196.00, 220.00, 261.63];
const List<double> _padLfoHz = [1 / 11, 1 / 13, 1 / 17, 1 / 19, 1 / 23];
const List<double> _kalimbaRatio = [1.0, 6.267, 17.55];
const List<double> _kalimbaAmp = [1.0, 0.10, 0.025];
const List<double> _kalimbaTau = [1.3, 0.22, 0.07];

double _fadeCurve(double p) {
  if (p <= 0) return 0.0;
  if (p >= 1) return 1.0;
  return math.log(1.0 + 9.0 * p) * 0.4342944819032518;
}

double _onePole(double tauSeconds, double stepSamples) =>
    1.0 - math.exp(-stepSamples / (tauSeconds * _sr));

double _wrap(double p) {
  while (p >= _twoPi) {
    p -= _twoPi;
  }
  return p;
}

class _Rng {
  int _s = 0x9E3779B9;

  void seed(int v) {
    _s = (v & 0xFFFFFFFF) == 0 ? 0x9E3779B9 : (v & 0xFFFFFFFF);
  }

  double white() {
    var s = _s;
    s ^= (s << 13) & 0xFFFFFFFF;
    s ^= s >> 17;
    s ^= (s << 5) & 0xFFFFFFFF;
    _s = s;
    final signed = s >= 0x80000000 ? s - 0x100000000 : s;
    return signed / 2147483648.0;
  }
}

/// Leaky integrator (-6 dB/oct) followed by a 20 Hz DC blocker.
class BrownNoise {
  static const double leak = 0.99938;
  static const double gain = 0.006;
  static const double _hp = 1.0 - _twoPi * 20.0 / _sr;
  final _Rng _rng = _Rng();
  double _y = 0, _hpX = 0, _hpY = 0;

  BrownNoise([int seed = 1]) {
    reset(seed);
  }

  void reset(int seed) {
    _rng.seed(seed);
    _y = 0;
    _hpX = 0;
    _hpY = 0;
  }

  double process() {
    _y = leak * _y + gain * _rng.white();
    final o = _y - _hpX + _hp * _hpY;
    _hpX = _y;
    _hpY = o;
    return o;
  }
}

/// Paul Kellet's refined 7-state pink filter (-3 dB/oct).
class PinkNoise {
  final _Rng _rng = _Rng();
  double _b0 = 0, _b1 = 0, _b2 = 0, _b3 = 0, _b4 = 0, _b5 = 0, _b6 = 0;

  PinkNoise([int seed = 1]) {
    reset(seed);
  }

  void reset(int seed) {
    _rng.seed(seed);
    _b0 = _b1 = _b2 = _b3 = _b4 = _b5 = _b6 = 0;
  }

  double process() {
    final w = _rng.white();
    _b0 = 0.99886 * _b0 + w * 0.0555179;
    _b1 = 0.99332 * _b1 + w * 0.0750759;
    _b2 = 0.96900 * _b2 + w * 0.1538520;
    _b3 = 0.86650 * _b3 + w * 0.3104856;
    _b4 = 0.55000 * _b4 + w * 0.5329522;
    _b5 = -0.7616 * _b5 - w * 0.0168980;
    final o = _b0 + _b1 + _b2 + _b3 + _b4 + _b5 + _b6 + w * 0.5362;
    _b6 = w * 0.115926;
    return o * 0.015;
  }
}

/// Topology-preserving state-variable filter.
class StateVariableFilter {
  double _g = 0, _k = 1, _a1 = 0, _a2 = 0, _a3 = 0, _ic1 = 0, _ic2 = 0;

  /// Outputs of the most recent [tick]; [bp] has unity peak gain.
  double lp = 0, bp = 0, hp = 0;

  StateVariableFilter([double fc = 1000, double q = 0.7071]) {
    setCoeffs(fc, q);
  }

  void setCoeffs(double fc, double q) {
    const nyq = 0.49 * _sr;
    if (fc > nyq) fc = nyq;
    if (fc < 5) fc = 5;
    _g = math.tan(math.pi * fc / _sr);
    _k = 1.0 / q;
    _a1 = 1.0 / (1.0 + _g * (_g + _k));
    _a2 = _g * _a1;
    _a3 = _g * _a2;
  }

  void reset() {
    _ic1 = 0;
    _ic2 = 0;
  }

  void tick(double x) {
    final v3 = x - _ic2;
    final v1 = _a1 * _ic1 + _a2 * v3;
    final v2 = _ic2 + _a2 * _ic1 + _a3 * v3;
    _ic1 = 2.0 * v1 - _ic1;
    _ic2 = 2.0 * v2 - _ic2;
    lp = v2;
    bp = v1 * _k;
    hp = x - _k * v1 - v2;
  }

  double lowpass(double x) {
    tick(x);
    return lp;
  }
}

class _SmoothLowpass {
  final StateVariableFilter _l = StateVariableFilter();
  final StateVariableFilter _r = StateVariableFilter();
  double _q = 0.7071, _logCur = 11, _logTarget = 11;
  int _n = 0;
  static const double _smooth = 1.0 / (0.12 * _sr);

  void init(double fc, double q) {
    _q = q;
    _logCur = _logTarget = math.log(fc) / math.ln2;
    _n = 0;
    _update();
    _l.reset();
    _r.reset();
  }

  void setTarget(double fc) {
    _logTarget = math.log(fc < 20 ? 20 : fc) / math.ln2;
  }

  void tick() {
    _logCur += (_logTarget - _logCur) * _smooth;
    if (++_n >= 16) {
      _n = 0;
      _update();
    }
  }

  void _update() {
    final fc = math.pow(2.0, _logCur).toDouble();
    _l.setCoeffs(fc, _q);
    _r.setCoeffs(fc, _q);
  }

  double process(int ch, double x) => ch == 0 ? _l.lowpass(x) : _r.lowpass(x);
}

class _PulseVoice {
  bool active = false;
  int t = 0, attack = 1;
  double f = 0, amp = 0, tau = 0.3, ph = 0;
}

class _Thump {
  bool active = false;
  int t = 0;
  double f0 = 100, f1 = 60, amp = 0.2, ph = 0;
}

class _KalimbaVoice {
  bool active = false, pending = false;
  int t = 0, pendingDegree = 0;
  double pendingVel = 0, amp = 0, rel = 1, f = 0;
  final List<double> ph = [0, 0, 0];
  final List<double> dec = [1, 1, 1];
}

enum _CmdType {
  start,
  stop,
  switchPreset,
  iso,
  limits,
  note,
  voiceSwap,
  voiceCfg
}

class _Cmd {
  _Cmd(this.type,
      [this.a = 0,
      this.b = 0,
      this.c = 0,
      this.d = 0,
      this.e = 0,
      this.f = 0,
      this.data]);
  final _CmdType type;
  final double a, b, c, d, e, f;
  final Float32List? data;
}

/// Faithful pure-Dart port of `native/dsp_engine.cpp` (same algorithms and constants).
/// Deterministic and headless; commands are queued and applied at the start of [render].
class PureDartDsp implements AudioEngine, VoiceWeaveEngine {
  PureDartDsp() {
    for (var i = 0; i < 2; i++) {
      _pinkNotch[i].setCoeffs(3200, 2.0);
      _pinkHp[i].setCoeffs(500, 0.7071);
      _pinkLp[i].setCoeffs(2500, 0.7071);
    }
    _waterBp.setCoeffs(1100, 1.5);
    _master.init(2000, 0.7071);
    for (var i = 0; i < 5; i++) {
      _padPh[i * 2] = 0.7 * i;
      _padPh[i * 2 + 1] = 1.9 * i + 0.3;
      _padLfo[i] = 1.3 * i;
    }
    _resetStem();
  }

  final List<_Cmd> _queue = <_Cmd>[];

  // Caregiver voice layer (mirrors native/dsp_engine.cpp).
  final List<Float32List?> _vbuf =
      List<Float32List?>.filled(VoiceWeaveEngine.maxSlots, null);
  bool _vOn = false;
  double _vGainT = 0.12, _vGain = 0;
  int _vIntervalSamples = 45 * AudioEngine.sampleRate;
  int _vWait = 20 * AudioEngine.sampleRate;
  int _vSlot = -1, _vPos = 0, _vNext = 0;
  bool _silent = true;
  int _preset = 0;
  double _masterP = 0;
  int _masterDir = 0;
  double _xfP = 1;
  final List<double> _gain = List<double>.filled(_stemCount, 0);
  final List<double> _from = List<double>.filled(_stemCount, 0);
  final List<double> _tg = List<double>.filled(_stemCount, 0);
  double _lpfFrom = 2000, _lpfBlend = 2000;
  int _ctl = 0;
  double _fadeGain = 0;

  double _isoBpmT = 104,
      _isoLpfT = 2000,
      _isoRwT = 1,
      _isoPwT = 0,
      _isoBgT = 0,
      _isoHgT = 0;
  double _isoBpm = 104, _isoRw = 1, _isoPw = 0, _isoBg = 0, _isoHg = 0;

  double _highCut = 0, _capT = 1, _capS = 1, _waterT = 1, _waterS = 1;

  final List<BrownNoise> _brown = [BrownNoise(), BrownNoise()];
  final List<PinkNoise> _pink = [PinkNoise(), PinkNoise()];
  final _Rng _waterRng = _Rng();
  final List<StateVariableFilter> _pinkNotch = [
    StateVariableFilter(),
    StateVariableFilter()
  ];
  final List<StateVariableFilter> _pinkHp = [
    StateVariableFilter(),
    StateVariableFilter()
  ];
  final List<StateVariableFilter> _pinkLp = [
    StateVariableFilter(),
    StateVariableFilter()
  ];
  final StateVariableFilter _waterBp = StateVariableFilter();
  final _SmoothLowpass _master = _SmoothLowpass();

  final List<_PulseVoice> _marimba =
      List<_PulseVoice>.generate(4, (_) => _PulseVoice());
  final List<_PulseVoice> _cello =
      List<_PulseVoice>.generate(2, (_) => _PulseVoice());
  int _marimbaNext = 0, _celloNext = 0;
  double _beatPhase = 0;
  int _beatIndex = 0;

  final List<double> _padPh = List<double>.filled(10, 0);
  final List<double> _padLfo = List<double>.filled(5, 0);
  double _heartPhase = 0;
  int _heartSince = 0;
  bool _heartDub = true;
  final _Thump _lub = _Thump();
  final _Thump _dub = _Thump();
  final List<double> _dronePh = [0, 0, 0];
  double _droneLfo = 0;
  final List<double> _waterLfo = [0, 0];
  final List<_KalimbaVoice> _kalimba =
      List<_KalimbaVoice>.generate(8, (_) => _KalimbaVoice());

  double _compEnv = 0;
  double _prevL = 0, _prevR = 0;
  int _slewHits = 0;
  bool _disposed = false;

  /// Number of samples the final slew guard had to limit (diagnostic).
  int get slewHits => _slewHits;

  /// True when the engine is fully faded out and rendering silence.
  bool get isSilent => _silent;

  @override
  void start(SessionPreset preset) =>
      _queue.add(_Cmd(_CmdType.start, preset.index.toDouble()));

  @override
  void stop() => _queue.add(_Cmd(_CmdType.stop));

  @override
  void switchPreset(SessionPreset preset) =>
      _queue.add(_Cmd(_CmdType.switchPreset, preset.index.toDouble()));

  @override
  void applyIso(IsoSnapshot s) => _queue.add(_Cmd(_CmdType.iso, s.bpm, s.lpfHz,
      s.rhythmWeight, s.padWeight, s.brownNoiseGain, s.heartbeatGain));

  @override
  void setProfileLimits(
          {double highCutHz = 0,
          double masterCap = 1.0,
          bool allowWater = true}) =>
      _queue.add(
          _Cmd(_CmdType.limits, highCutHz, masterCap, allowWater ? 1.0 : 0.0));

  @override
  void triggerNote(int degree, double velocity) =>
      _queue.add(_Cmd(_CmdType.note, degree.toDouble(), velocity));

  @override
  void loadVoice(int slot, Float32List mono48k) {
    if (slot < 0 || slot >= VoiceWeaveEngine.maxSlots) return;
    final n = math.min(mono48k.length, VoiceWeaveEngine.maxFrames);
    final copy = Float32List(n);
    for (var i = 0; i < n; i++) {
      final v = mono48k[i];
      copy[i] = v.isNaN ? 0.0 : (v > 1.0 ? 1.0 : (v < -1.0 ? -1.0 : v));
    }
    _queue.add(_Cmd(_CmdType.voiceSwap, slot.toDouble(), 0, 0, 0, 0, 0, copy));
  }

  @override
  void clearVoice(int slot) {
    if (slot < 0 || slot >= VoiceWeaveEngine.maxSlots) return;
    _queue.add(_Cmd(_CmdType.voiceSwap, slot.toDouble()));
  }

  @override
  void setVoiceWeave(
          {required bool enabled,
          double gain = 0.12,
          double intervalSec = 45}) =>
      _queue
          .add(_Cmd(_CmdType.voiceCfg, enabled ? 1.0 : 0.0, gain, intervalSec));

  @override
  void dispose() {
    _disposed = true;
    _queue.clear();
  }

  // ---------------------------------------------------------------- commands

  static int _clampPreset(double v) {
    final i = v.toInt();
    return i < 0 ? 0 : (i > 3 ? 3 : i);
  }

  static double _fin(double v, double lo, double hi, double fb) {
    if (v.isNaN) return fb;
    return v < lo ? lo : (v > hi ? hi : v);
  }

  void _drain() {
    if (_queue.isEmpty) return;
    for (final c in _queue) {
      switch (c.type) {
        case _CmdType.start:
          _doStart(_clampPreset(c.a));
        case _CmdType.stop:
          if (!_silent) _masterDir = -1;
        case _CmdType.switchPreset:
          _doSwitch(_clampPreset(c.a));
        case _CmdType.iso:
          _isoBpmT = _fin(c.a, 30, 200, _isoBpmT);
          _isoLpfT = _fin(c.b, 100, 12000, _isoLpfT);
          _isoRwT = _fin(c.c, 0, 1, _isoRwT);
          _isoPwT = _fin(c.d, 0, 1, _isoPwT);
          _isoBgT = _fin(c.e, 0, 1, _isoBgT);
          _isoHgT = _fin(c.f, 0, 1, _isoHgT);
        case _CmdType.limits:
          _highCut = (!c.a.isNaN && c.a > 0) ? math.max(c.a, 100.0) : 0.0;
          _capT = c.b.isNaN ? 1.0 : math.min(1.0, math.max(0.0, c.b));
          _waterT = c.c > 0.5 ? 1.0 : 0.0;
        case _CmdType.note:
          _doNote(c.a.toInt(), c.b);
        case _CmdType.voiceSwap:
          final slot = c.a.toInt();
          if (slot < 0 || slot >= VoiceWeaveEngine.maxSlots) break;
          if (_vSlot == slot) _vSlot = -1;
          _vbuf[slot] = (c.data == null || c.data!.isEmpty) ? null : c.data;
        case _CmdType.voiceCfg:
          _vOn = c.a > 0.5;
          _vGainT = (c.b.isNaN ? 0.12 : c.b).clamp(0.0, 0.5).toDouble();
          final iv = (c.c.isNaN ? 45.0 : c.c).clamp(10.0, 600.0).toDouble();
          _vIntervalSamples = (iv * AudioEngine.sampleRate).round();
          _vWait = math.min(_vWait, _vIntervalSamples);
      }
    }
    _queue.clear();
  }

  void _stemTargets(int preset, List<double> t) {
    for (var i = 0; i < _stemCount; i++) {
      t[i] = 0;
    }
    switch (preset) {
      case 0:
        t[_stBrown] = _isoBg;
        t[_stPulse] = _isoRw;
        t[_stPad] = _isoPw;
        t[_stHeart] = _isoHg;
      case 1:
        t[_stBrown] = 1;
        t[_stDrone] = 1;
      case 2:
        t[_stPink] = 1;
        t[_stPad] = 0.35;
      default:
        t[_stBrown] = 0.25;
        t[_stPink] = 0.15;
        t[_stPad] = 0.8;
        t[_stWater] = _waterS;
    }
  }

  double _presetLpf(int preset) {
    switch (preset) {
      case 0:
        return _isoLpfT;
      case 1:
        return 650.0;
      case 2:
        return 1200.0;
      default:
        return 2000.0;
    }
  }

  void _snap() {
    _stemTargets(_preset, _tg);
    for (var i = 0; i < _stemCount; i++) {
      _gain[i] = _from[i] = _tg[i];
    }
    _xfP = 1;
    _lpfBlend = _lpfFrom = _presetLpf(_preset);
  }

  void _resetStem() {
    for (var i = 0; i < 2; i++) {
      _brown[i].reset(0x1234567 + 7919 * i);
      _pink[i].reset(0x7654321 + 104729 * i);
      _pinkNotch[i].reset();
      _pinkHp[i].reset();
      _pinkLp[i].reset();
    }
    _waterRng.seed(0xABCDEF1);
    _waterBp.reset();
    for (final v in _marimba) {
      v.active = false;
    }
    for (final v in _cello) {
      v.active = false;
    }
    for (final v in _kalimba) {
      v
        ..active = false
        ..pending = false
        ..t = 0
        ..rel = 1;
    }
    _marimbaNext = 0;
    _celloNext = 0;
    _beatPhase = 0;
    _beatIndex = 0;
    _heartPhase = 0;
    _heartSince = 0;
    _heartDub = true;
    _lub.active = false;
    _dub.active = false;
    _compEnv = 0;
  }

  void _goSilent() {
    _vSlot = -1;
    _silent = true;
    _masterP = 0;
    _masterDir = 0;
    _fadeGain = 0;
    _prevL = 0;
    _prevR = 0;
    _resetStem();
  }

  void _doStart(int p) {
    if (_silent) {
      _resetStem();
      _preset = p;
      _isoBpm = _isoBpmT;
      _isoRw = _isoRwT;
      _isoPw = _isoPwT;
      _isoBg = _isoBgT;
      _isoHg = _isoHgT;
      _waterS = _waterT;
      _capS = _capT;
      _snap();
      _master.init(_lpfBlend, 0.7071);
      _prevL = 0;
      _prevR = 0;
      _masterP = 0;
      _masterDir = 1;
      _fadeGain = 0;
      _silent = false;
      _ctl = 0;
      _vSlot = -1;
      _vWait = math.min(_vIntervalSamples, 20 * AudioEngine.sampleRate);
    } else {
      if (p != _preset) _doSwitch(p);
      _masterDir = 1;
    }
  }

  void _doSwitch(int p) {
    if (_silent) {
      _preset = p;
      return;
    }
    if (p == _preset && _xfP >= 1) return;
    for (var i = 0; i < _stemCount; i++) {
      _from[i] = _gain[i];
    }
    _lpfFrom = _lpfBlend;
    _preset = p;
    _xfP = 0;
  }

  void _startKalimba(_KalimbaVoice v, int degree, double vel) {
    final d = degree < 0 ? 0 : (degree > 9 ? 9 : degree);
    final velocity = math.min(_velocityCap, math.max(0.0, vel));
    v
      ..active = true
      ..pending = false
      ..t = 0
      ..rel = 1
      ..f = AudioEngine.pentatonicHz[d];
    v.amp = 0.10 * velocity * math.min(1.0, 220.0 / v.f);
    for (var k = 0; k < 3; k++) {
      v.ph[k] = 0;
      v.dec[k] = 1;
    }
  }

  void _doNote(int degree, double vel) {
    if (_silent || vel.isNaN) return;
    for (final v in _kalimba) {
      if (!v.active) {
        _startKalimba(v, degree, vel);
        return;
      }
    }
    // Voice stealing: fade the oldest voice over 15 ms, then restart it as the new note.
    _KalimbaVoice? oldest;
    for (final v in _kalimba) {
      if (!v.pending && (oldest == null || v.t > oldest.t)) oldest = v;
    }
    oldest ??= _kalimba[0];
    oldest
      ..pending = true
      ..pendingDegree = degree
      ..pendingVel = vel;
  }

  void _triggerMarimba(int degree, double amp) {
    final v = _marimba[_marimbaNext];
    _marimbaNext = (_marimbaNext + 1) % _marimba.length;
    v
      ..active = true
      ..t = 0
      ..attack = 720
      ..f = AudioEngine.pentatonicHz[degree]
      ..amp = amp
      ..tau = 0.35
      ..ph = 0;
  }

  void _triggerCello(int degree) {
    final v = _cello[_celloNext];
    _celloNext = (_celloNext + 1) % _cello.length;
    v
      ..active = true
      ..t = 0
      ..attack = 2880
      ..f = AudioEngine.pentatonicHz[degree]
      ..amp = 0.05
      ..tau = 0.8
      ..ph = 0;
  }

  // ----------------------------------------------------------------- control

  void _control() {
    if (_xfP < 1) _xfP = math.min(1.0, _xfP + _ctlStep / _xfSamples);
    final w = _fadeCurve(_xfP);
    final cBpm = _onePole(1.5, _ctlStep.toDouble());
    final cW = _onePole(0.4, _ctlStep.toDouble());
    _isoBpm += (_isoBpmT - _isoBpm) * cBpm;
    _isoRw += (_isoRwT - _isoRw) * cW;
    _isoPw += (_isoPwT - _isoPw) * cW;
    _isoBg += (_isoBgT - _isoBg) * cW;
    _isoHg += (_isoHgT - _isoHg) * cW;
    _waterS += (_waterT - _waterS) * _onePole(0.1, _ctlStep.toDouble());
    _capS += (_capT - _capS) * _onePole(0.25, _ctlStep.toDouble());
    _vGain +=
        ((_vOn ? _vGainT : 0.0) - _vGain) * _onePole(0.3, _ctlStep.toDouble());

    _stemTargets(_preset, _tg);
    for (var i = 0; i < _stemCount; i++) {
      _gain[i] = _from[i] * (1.0 - w) + _tg[i] * w;
    }
    final lt = _presetLpf(_preset);
    _lpfBlend = math.exp(math.log(_lpfFrom) * (1.0 - w) + math.log(lt) * w);
    var eff = _lpfBlend;
    if (_highCut > 0) eff = math.min(eff, _highCut);
    _master.setTarget(eff);

    if (_masterDir != 0) {
      _masterP += _masterDir * _ctlStep / _xfSamples;
      if (_masterP >= 1) {
        _masterP = 1;
        _masterDir = 0;
      } else if (_masterP <= 0) {
        _masterP = 0;
        _masterDir = 0;
        _goSilent();
        return;
      }
    }
    _fadeGain = _fadeCurve(_masterP);

    // Voice scheduler: counts down only while fully audible, then plays the next stored
    // phrase (round robin) and waits one interval after it ends.
    if (_vOn && _vSlot < 0 && _fadeGain > 0.95 && _masterDir >= 0) {
      _vWait -= _ctlStep;
      if (_vWait <= 0) {
        for (var k = 0; k < VoiceWeaveEngine.maxSlots; k++) {
          final s = (_vNext + k) % VoiceWeaveEngine.maxSlots;
          if (_vbuf[s] != null) {
            _vSlot = s;
            _vPos = 0;
            _vNext = (s + 1) % VoiceWeaveEngine.maxSlots;
            break;
          }
        }
        if (_vSlot < 0) _vWait = _vIntervalSamples;
      }
    }
  }

  // ------------------------------------------------------------------ render

  @override
  void render(Float32List out, int frames) {
    if (_disposed) {
      for (var i = 0; i < frames * 2 && i < out.length; i++) {
        out[i] = 0;
      }
      return;
    }
    _drain();
    for (var i = 0; i < frames; i++) {
      if (_silent) {
        out[2 * i] = 0;
        out[2 * i + 1] = 0;
        continue;
      }
      if (_ctl <= 0) {
        _control();
        _ctl = _ctlStep;
        if (_silent) {
          out[2 * i] = 0;
          out[2 * i + 1] = 0;
          continue;
        }
      }
      _ctl--;
      _tick(out, i);
    }
  }

  void _tick(Float32List out, int idx) {
    final bL = _brown[0].process();
    final bR = _brown[1].process();
    var pkL = 0.0, pkR = 0.0;
    for (var c = 0; c < 2; c++) {
      final pn = _pink[c].process();
      _pinkNotch[c].tick(pn);
      final notched = _pinkNotch[c].lp + _pinkNotch[c].hp;
      _pinkHp[c].tick(pn);
      _pinkLp[c].tick(_pinkHp[c].hp);
      final shaped = 0.8 * notched + 0.5 * _pinkLp[c].lp;
      if (c == 0) {
        pkL = shaped;
      } else {
        pkR = shaped;
      }
    }

    // Rhythmic pulse stem (marimba + cello).
    final prevBeat = _beatPhase;
    _beatPhase += _isoBpm / 60.0 / _sr;
    if (_beatPhase >= 1) {
      _beatPhase -= 1;
      _triggerMarimba(_marimbaPattern[_beatIndex & 7], 0.07);
      if ((_beatIndex & 3) == 0) {
        _triggerCello(_celloRoots[(_beatIndex >> 2) & 3]);
      }
      _beatIndex++;
    } else if (prevBeat < 0.5 && _beatPhase >= 0.5) {
      _triggerMarimba(_marimbaPattern[(_beatIndex + 7) & 7] % 5 + 5, 0.035);
    }
    var pulse = 0.0;
    for (final v in _marimba) {
      if (!v.active) continue;
      final env = v.t < v.attack
          ? 0.5 * (1.0 - math.cos(math.pi * v.t / v.attack))
          : math.exp(-(v.t - v.attack) / (v.tau * _sr));
      final hi = math.exp(-v.t / (0.06 * _sr));
      pulse +=
          v.amp * env * (math.sin(v.ph) + 0.25 * hi * math.sin(4.0 * v.ph));
      v.ph = _wrap(v.ph + _twoPi * v.f / _sr);
      v.t++;
      if (v.t > v.attack && env < 1e-4) v.active = false;
    }
    for (final v in _cello) {
      if (!v.active) continue;
      final env = v.t < v.attack
          ? 0.5 * (1.0 - math.cos(math.pi * v.t / v.attack))
          : math.exp(-(v.t - v.attack) / (v.tau * _sr));
      pulse += v.amp *
          env *
          (math.sin(v.ph) +
              0.5 * math.sin(2.0 * v.ph) +
              0.33 * math.sin(3.0 * v.ph) +
              0.2 * math.sin(4.0 * v.ph)) *
          0.55;
      v.ph = _wrap(v.ph + _twoPi * v.f / _sr);
      v.t++;
      if (v.t > v.attack && env < 1e-4) v.active = false;
    }

    // Warm pentatonic pad.
    var padL = 0.0, padR = 0.0;
    for (var k = 0; k < 5; k++) {
      final lfo = 0.65 + 0.35 * math.sin(_padLfo[k]);
      final a = math.sin(_padPh[2 * k]);
      final b = math.sin(_padPh[2 * k + 1]);
      padL += lfo * 0.012 * (a + 0.5 * b);
      padR += lfo * 0.012 * (b + 0.5 * a);
      _padPh[2 * k] = _wrap(_padPh[2 * k] + _twoPi * _padHz[k] * 0.9985 / _sr);
      _padPh[2 * k + 1] =
          _wrap(_padPh[2 * k + 1] + _twoPi * _padHz[k] * 1.0015 / _sr);
      _padLfo[k] = _wrap(_padLfo[k] + _twoPi * _padLfoHz[k] / _sr);
    }

    // Lub-dub heartbeat (60-120 Hz).
    _heartPhase += _isoBpm / 60.0 / _sr;
    _heartSince++;
    if (_heartPhase >= 1) {
      _heartPhase -= 1;
      _lub
        ..active = true
        ..t = 0
        ..f0 = 120
        ..f1 = 70
        ..amp = 0.17
        ..ph = 0;
      _heartSince = 0;
      _heartDub = false;
    }
    if (!_heartDub && _heartSince >= (0.30 * _sr).floor()) {
      _heartDub = true;
      _dub
        ..active = true
        ..t = 0
        ..f0 = 100
        ..f1 = 60
        ..amp = 0.11
        ..ph = 0;
    }
    var heart = 0.0;
    for (var n = 0; n < 2; n++) {
      final th = n == 0 ? _lub : _dub;
      if (!th.active) continue;
      const att = 960;
      final env = th.t < att
          ? 0.5 * (1.0 - math.cos(math.pi * th.t / att))
          : math.exp(-(th.t - att) / (0.11 * _sr));
      final f = th.f1 + (th.f0 - th.f1) * math.exp(-th.t / (0.05 * _sr));
      heart += th.amp * env * math.sin(th.ph);
      th.ph = _wrap(th.ph + _twoPi * f / _sr);
      th.t++;
      if (th.t > att && env < 1e-4) th.active = false;
    }

    // 110 Hz drone (Deep Crisis).
    final trem = 0.85 + 0.15 * math.sin(_droneLfo);
    final drone = trem *
        (0.09 * math.sin(_dronePh[0]) +
            0.03 * math.sin(_dronePh[1]) +
            0.02 * math.sin(_dronePh[2]));
    _dronePh[0] = _wrap(_dronePh[0] + _twoPi * 110.0 / _sr);
    _dronePh[1] = _wrap(_dronePh[1] + _twoPi * 220.0 / _sr);
    _dronePh[2] = _wrap(_dronePh[2] + _twoPi * 165.0 / _sr);
    _droneLfo = _wrap(_droneLfo + _twoPi * 0.1 / _sr);

    // Water shimmer.
    _waterBp.tick(_waterRng.white());
    final waterMod = (0.5 + 0.5 * math.sin(_waterLfo[0])) *
        (0.5 + 0.5 * math.sin(_waterLfo[1]));
    final water = 0.08 * _waterBp.bp * waterMod;
    _waterLfo[0] = _wrap(_waterLfo[0] + _twoPi * 0.31 / _sr);
    _waterLfo[1] = _wrap(_waterLfo[1] + _twoPi * 0.17 / _sr);

    // Kalimba modal pluck synth.
    var kal = 0.0;
    for (final v in _kalimba) {
      if (!v.active) continue;
      final att = v.t < _kalimbaAttack
          ? 0.5 * (1.0 - math.cos(math.pi * v.t / _kalimbaAttack))
          : 1.0;
      var s = 0.0;
      for (var k = 0; k < 3; k++) {
        s += _kalimbaAmp[k] * v.dec[k] * math.sin(v.ph[k]);
        v.ph[k] = _wrap(v.ph[k] + _twoPi * v.f * _kalimbaRatio[k] / _sr);
        v.dec[k] *= math.exp(-1.0 / (_kalimbaTau[k] * _sr));
      }
      kal += v.amp * att * v.rel * s;
      v.t++;
      if (v.pending) {
        v.rel -= 1.0 / (0.015 * _sr);
        if (v.rel <= 0) _startKalimba(v, v.pendingDegree, v.pendingVel);
      } else if (v.t > _kalimbaAttack && v.dec[0] < 0.002) {
        v.active = false;
      }
    }

    final g = _gain;
    final common = g[_stDrone] * drone +
        g[_stWater] * water +
        g[_stPulse] * pulse +
        g[_stHeart] * heart +
        kal;
    var mL = g[_stBrown] * bL + g[_stPink] * pkL + g[_stPad] * padL + common;
    var mR = g[_stBrown] * bR + g[_stPink] * pkR + g[_stPad] * padR + common;

    final voice = _vbuf.isEmpty || _vSlot < 0 ? null : _vbuf[_vSlot];
    if (voice != null) {
      final len = voice.length;
      final fade = math.min(12000, len ~/ 2); // 250 ms raised-cosine edges
      var env = 1.0;
      if (_vPos < fade) {
        env = 0.5 - 0.5 * math.cos(math.pi * _vPos / fade);
      } else if (_vPos > len - fade) {
        env = 0.5 - 0.5 * math.cos(math.pi * (len - _vPos) / fade);
      }
      final v = _vGain * env * voice[_vPos];
      mL += v;
      mR += v;
      if (++_vPos >= len) {
        _vSlot = -1;
        _vWait = _vIntervalSamples;
      }
    }

    _master.tick();
    mL = _master.process(0, mL);
    mR = _master.process(1, mR);

    final lvl = _fadeGain * _capS;
    mL *= lvl;
    mR *= lvl;

    // Soft-knee compressor (-9 dB, 8 dB knee, 4:1).
    final det = math.max(mL.abs(), mR.abs());
    final cf = det > _compEnv ? _onePole(0.003, 1.0) : _onePole(0.15, 1.0);
    _compEnv += (det - _compEnv) * cf;
    final over = 20.0 * math.log(_compEnv + 1e-9) * 0.4342944819032518 + 9.0;
    double gr;
    if (2.0 * over < -8.0) {
      gr = 0.0;
    } else if (2.0 * over.abs() <= 8.0) {
      final t = over + 4.0;
      gr = (0.25 - 1.0) * t * t / 16.0;
    } else {
      gr = (0.25 - 1.0) * over;
    }
    final cg = math.exp(gr * 0.11512925464970229);
    mL *= cg;
    mR *= cg;

    // Brickwall + slew guard.
    if (mL.isNaN) mL = 0;
    if (mR.isNaN) mR = 0;
    mL = math.min(_ceiling, math.max(-_ceiling, mL));
    mR = math.min(_ceiling, math.max(-_ceiling, mR));
    var dl = mL - _prevL;
    var dr = mR - _prevR;
    if (dl > _slewLimit) {
      dl = _slewLimit;
      _slewHits++;
    } else if (dl < -_slewLimit) {
      dl = -_slewLimit;
      _slewHits++;
    }
    if (dr > _slewLimit) {
      dr = _slewLimit;
      _slewHits++;
    } else if (dr < -_slewLimit) {
      dr = -_slewLimit;
      _slewHits++;
    }
    _prevL += dl;
    _prevR += dr;
    out[2 * idx] = _prevL;
    out[2 * idx + 1] = _prevR;
  }
}

/// Chooses the best available DSP backend for the platform: the native C++ engine on
/// mobile / desktop, a Web Audio driven pure-Dart engine in the browser.
class DspBridge {
  DspBridge._();

  static AudioEngine create() => createPlatformEngine();
}
