#include "dsp_engine.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <new>

namespace aura {
namespace {

const double kPentatonic[10] = {130.81, 146.83, 164.81, 196.00, 220.00,
                                261.63, 293.66, 329.63, 392.00, 440.00};

constexpr double kInvLn10 = 0.43429448190325176;
constexpr double kDbToLn = 0.11512925464970229;  // ln(10)/20
constexpr double kSr = static_cast<double>(kSampleRate);

constexpr double kVelocityCap = 0.85;
constexpr int kKalimbaAttack = 2400;  // 50 ms cosine attack (>= 45 ms)
constexpr double kSlewLimit = 0.0045;

constexpr double kCompThresholdDb = -9.0;
constexpr double kCompKneeDb = 8.0;
constexpr double kCompRatio = 4.0;

enum CmdType {
  kCmdStart,
  kCmdStop,
  kCmdSwitch,
  kCmdIso,
  kCmdLimits,
  kCmdNote,
  kCmdVoiceSwap,
  kCmdVoiceCfg
};

// Logarithmic fade curve: 0 -> 0, 1 -> 1, steep at first, gentle at the end.
inline double fadeCurve(double p) {
  if (p <= 0.0) return 0.0;
  if (p >= 1.0) return 1.0;
  return std::log(1.0 + 9.0 * p) * kInvLn10;
}

inline double onePole(double tauSeconds, double stepSamples) {
  return 1.0 - std::exp(-stepSamples / (tauSeconds * kSr));
}

inline int clampPreset(int p) { return p < 0 ? 0 : (p > 3 ? 3 : p); }

inline double wrapPhase(double p) {
  while (p >= kTwoPi) p -= kTwoPi;
  return p;
}

const int kMarimbaPattern[8] = {0, 2, 4, 2, 3, 1, 4, 2};
const int kCelloRoots[4] = {0, 2, 3, 1};
const double kPadHz[5] = {130.81, 164.81, 196.00, 220.00, 261.63};
const double kPadLfoHz[5] = {1.0 / 11.0, 1.0 / 13.0, 1.0 / 17.0, 1.0 / 19.0, 1.0 / 23.0};
const double kKalimbaRatio[3] = {1.0, 6.267, 17.55};
const double kKalimbaAmp[3] = {1.0, 0.10, 0.025};
const double kKalimbaTau[3] = {1.3, 0.22, 0.07};

}  // namespace

Engine::Engine() {
  for (int i = 0; i < 2; ++i) {
    brown_[i].reset(0x1234567u + 7919u * i);
    pink_[i].reset(0x7654321u + 104729u * i);
    pinkNotch_[i].setCoeffs(3200.0, 2.0);
    pinkHp_[i].setCoeffs(500.0, 0.7071);
    pinkLp_[i].setCoeffs(2500.0, 0.7071);
  }
  waterRng_.seed(0xABCDEF1u);
  waterBp_.setCoeffs(1100.0, 1.5);
  master_.init(2000.0, 0.7071);
  for (int i = 0; i < 5; ++i) {
    padPh_[i][0] = 0.7 * i;
    padPh_[i][1] = 1.9 * i + 0.3;
    padLfo_[i] = 1.3 * i;
  }
  std::memset(q_, 0, sizeof(q_));
}

bool Engine::push(const Cmd& c) {
  const uint32_t h = qHead_.load(std::memory_order_relaxed);
  const uint32_t n = (h + 1) % kQueue;
  if (n == qTail_.load(std::memory_order_acquire)) return false;
  q_[h] = c;
  qHead_.store(n, std::memory_order_release);
  return true;
}

void Engine::start(int preset) { push({kCmdStart, static_cast<double>(preset), 0, 0, 0, 0, 0}); }
void Engine::stop() { push({kCmdStop, 0, 0, 0, 0, 0, 0}); }
void Engine::switchPreset(int preset) {
  push({kCmdSwitch, static_cast<double>(preset), 0, 0, 0, 0, 0});
}
void Engine::applyIso(double bpm, double lpfHz, double rw, double pw, double bg, double hg) {
  push({kCmdIso, bpm, lpfHz, rw, pw, bg, hg});
}
void Engine::setProfileLimits(double highCutHz, double masterCap, bool allowWater) {
  push({kCmdLimits, highCutHz, masterCap, allowWater ? 1.0 : 0.0, 0, 0, 0});
}
void Engine::triggerNote(int degree, double velocity) {
  push({kCmdNote, static_cast<double>(degree), velocity, 0, 0, 0, 0});
}

void Engine::loadVoice(int slot, const float* mono, int frames) {
  if (slot < 0 || slot >= kVoiceSlots) return;
  if (mono == nullptr || frames <= 0) {
    clearVoice(slot);
    return;
  }
  const int n = std::min(frames, kVoiceMax);
  const int next = 1 - vShadow_[slot];
  if (!vbuf_[slot][next]) vbuf_[slot][next].reset(new (std::nothrow) float[kVoiceMax]);
  float* dst = vbuf_[slot][next].get();
  if (dst == nullptr) return;
  for (int i = 0; i < n; ++i) {
    const float v = mono[i];
    dst[i] = (v != v) ? 0.0f : (v > 1.0f ? 1.0f : (v < -1.0f ? -1.0f : v));
  }
  if (push({kCmdVoiceSwap, static_cast<double>(slot), static_cast<double>(next),
            static_cast<double>(n), 0, 0, 0})) {
    vShadow_[slot] = next;
  }
}

void Engine::clearVoice(int slot) {
  if (slot < 0 || slot >= kVoiceSlots) return;
  push({kCmdVoiceSwap, static_cast<double>(slot), static_cast<double>(vShadow_[slot]), 0.0, 0, 0,
        0});
}

void Engine::setVoiceWeave(bool enabled, double gain, double intervalSec) {
  push({kCmdVoiceCfg, enabled ? 1.0 : 0.0, gain, intervalSec, 0, 0, 0});
}

void Engine::drain() {
  uint32_t t = qTail_.load(std::memory_order_relaxed);
  const uint32_t h = qHead_.load(std::memory_order_acquire);
  while (t != h) {
    const Cmd c = q_[t];
    t = (t + 1) % kQueue;
    switch (c.type) {
      case kCmdStart:
        doStart(clampPreset(static_cast<int>(c.a)));
        break;
      case kCmdStop:
        if (!silent_) masterDir_ = -1;
        break;
      case kCmdSwitch:
        doSwitch(clampPreset(static_cast<int>(c.a)));
        break;
      case kCmdIso: {
        auto fin = [](double v, double lo, double hi, double fb) {
          if (!(v == v)) return fb;
          return v < lo ? lo : (v > hi ? hi : v);
        };
        isoBpmT_ = fin(c.a, 30.0, 200.0, isoBpmT_);
        isoLpfT_ = fin(c.b, 100.0, 12000.0, isoLpfT_);
        isoRwT_ = fin(c.c, 0.0, 1.0, isoRwT_);
        isoPwT_ = fin(c.d, 0.0, 1.0, isoPwT_);
        isoBgT_ = fin(c.e, 0.0, 1.0, isoBgT_);
        isoHgT_ = fin(c.f, 0.0, 1.0, isoHgT_);
        break;
      }
      case kCmdLimits:
        highCut_ = (c.a == c.a && c.a > 0.0) ? std::max(c.a, 100.0) : 0.0;
        capT_ = (c.b == c.b) ? std::min(1.0, std::max(0.0, c.b)) : 1.0;
        waterT_ = c.c > 0.5 ? 1.0 : 0.0;
        break;
      case kCmdNote:
        doNote(static_cast<int>(c.a), c.b);
        break;
      case kCmdVoiceSwap: {
        const int slot = static_cast<int>(c.a);
        if (slot < 0 || slot >= kVoiceSlots) break;
        if (vSlot_ == slot) vSlot_ = -1;
        vIdx_[slot] = static_cast<int>(c.b) & 1;
        vLen_[slot] = std::max(0, std::min(kVoiceMax, static_cast<int>(c.c)));
        break;
      }
      case kCmdVoiceCfg: {
        vOn_ = c.a > 0.5;
        const double g = (c.b == c.b) ? c.b : 0.12;
        vGainT_ = std::min(0.5, std::max(0.0, g));
        const double iv = (c.c == c.c) ? c.c : 45.0;
        vIntervalSamples_ = static_cast<int>(std::min(600.0, std::max(10.0, iv)) * kSampleRate);
        vWait_ = std::min(vWait_, vIntervalSamples_);
        break;
      }
      default:
        break;
    }
  }
  qTail_.store(t, std::memory_order_release);
}

void Engine::stemTargets(int preset, double* tg) const {
  for (int i = 0; i < kStemCount; ++i) tg[i] = 0.0;
  switch (preset) {
    case 0:
      tg[kBrown] = isoBg_;
      tg[kPulse] = isoRw_;
      tg[kPad] = isoPw_;
      tg[kHeart] = isoHg_;
      break;
    case 1:
      tg[kBrown] = 1.0;
      tg[kDrone] = 1.0;
      break;
    case 2:
      tg[kPink] = 1.0;
      tg[kPad] = 0.35;
      break;
    default:
      tg[kBrown] = 0.25;
      tg[kPink] = 0.15;
      tg[kPad] = 0.8;
      tg[kWater] = waterS_;
      break;
  }
}

double Engine::presetLpf(int preset) const {
  switch (preset) {
    case 0:
      return isoLpfT_;
    case 1:
      return 650.0;
    case 2:
      return 1200.0;
    default:
      return 2000.0;
  }
}

void Engine::snapToPreset() {
  double tg[kStemCount];
  stemTargets(preset_, tg);
  for (int i = 0; i < kStemCount; ++i) gain_[i] = from_[i] = tg[i];
  xfP_ = 1.0;
  lpfBlend_ = lpfFrom_ = presetLpf(preset_);
}

void Engine::resetStemState() {
  for (int i = 0; i < 2; ++i) {
    brown_[i].reset(0x1234567u + 7919u * i);
    pink_[i].reset(0x7654321u + 104729u * i);
    pinkNotch_[i].reset();
    pinkHp_[i].reset();
    pinkLp_[i].reset();
  }
  waterRng_.seed(0xABCDEF1u);
  waterBp_.reset();
  for (auto& v : marimba_) v = PVoice();
  for (auto& v : cello_) v = PVoice();
  for (auto& v : kalimba_) v = KVoice();
  marimbaNext_ = celloNext_ = 0;
  beatPhase_ = 0.0;
  beatIndex_ = 0;
  heartPhase_ = 0.0;
  heartSince_ = 0;
  heartDub_ = true;
  lub_ = Thump();
  dub_ = Thump();
  compEnv_ = 0.0;
}

void Engine::goSilent() {
  vSlot_ = -1;
  silent_ = true;
  masterP_ = 0.0;
  masterDir_ = 0;
  fadeGain_ = 0.0;
  prevL_ = prevR_ = 0.0;
  resetStemState();
}

void Engine::doStart(int p) {
  if (silent_) {
    resetStemState();
    preset_ = p;
    isoBpm_ = isoBpmT_;
    isoRw_ = isoRwT_;
    isoPw_ = isoPwT_;
    isoBg_ = isoBgT_;
    isoHg_ = isoHgT_;
    waterS_ = waterT_;
    capS_ = capT_;
    snapToPreset();
    master_.init(lpfBlend_, 0.7071);
    prevL_ = prevR_ = 0.0;
    masterP_ = 0.0;
    masterDir_ = 1;
    fadeGain_ = 0.0;
    silent_ = false;
    ctl_ = 0;
    vSlot_ = -1;
    vWait_ = std::min(vIntervalSamples_, 20 * kSampleRate);
  } else {
    if (p != preset_) doSwitch(p);
    masterDir_ = 1;
  }
}

void Engine::doSwitch(int p) {
  if (silent_) {
    preset_ = p;
    return;
  }
  if (p == preset_ && xfP_ >= 1.0) return;
  for (int i = 0; i < kStemCount; ++i) from_[i] = gain_[i];
  lpfFrom_ = lpfBlend_;
  preset_ = p;
  xfP_ = 0.0;
}

void Engine::startKalimba(KVoice& v, int degree, double vel) {
  const int d = degree < 0 ? 0 : (degree > 9 ? 9 : degree);
  const double velocity = std::min(kVelocityCap, std::max(0.0, vel));
  v.active = true;
  v.pending = false;
  v.t = 0;
  v.rel = 1.0;
  v.f = kPentatonic[d];
  v.amp = 0.10 * velocity * std::min(1.0, 220.0 / v.f);
  for (int k = 0; k < 3; ++k) {
    v.ph[k] = 0.0;
    v.dec[k] = 1.0;
  }
}

void Engine::doNote(int degree, double vel) {
  if (silent_ || !(vel == vel)) return;
  for (auto& v : kalimba_) {
    if (!v.active) {
      startKalimba(v, degree, vel);
      return;
    }
  }
  // Voice stealing: fade the oldest voice out over 15 ms, then restart it as the new note.
  KVoice* oldest = nullptr;
  for (auto& v : kalimba_) {
    if (!v.pending && (oldest == nullptr || v.t > oldest->t)) oldest = &v;
  }
  if (oldest == nullptr) oldest = &kalimba_[0];
  oldest->pending = true;
  oldest->pendingDegree = degree;
  oldest->pendingVel = vel;
}

void Engine::triggerMarimba(int degree, double amp) {
  PVoice& v = marimba_[marimbaNext_];
  marimbaNext_ = (marimbaNext_ + 1) % kMarimbaVoices;
  v.active = true;
  v.t = 0;
  v.attack = 720;
  v.f = kPentatonic[degree];
  v.amp = amp;
  v.tau = 0.35;
  v.ph = 0.0;
  v.cello = false;
}

void Engine::triggerCello(int degree) {
  PVoice& v = cello_[celloNext_];
  celloNext_ = (celloNext_ + 1) % kCelloVoices;
  v.active = true;
  v.t = 0;
  v.attack = 2880;  // 60 ms
  v.f = kPentatonic[degree];
  v.amp = 0.05;
  v.tau = 0.8;
  v.ph = 0.0;
  v.cello = true;
}

void Engine::control() {
  // Preset crossfade progress (4.0 s).
  if (xfP_ < 1.0) xfP_ = std::min(1.0, xfP_ + static_cast<double>(kCtl) / kCrossfadeSamples);
  const double w = fadeCurve(xfP_);

  const double cBpm = onePole(1.5, kCtl);
  const double cW = onePole(0.4, kCtl);
  isoBpm_ += (isoBpmT_ - isoBpm_) * cBpm;
  isoRw_ += (isoRwT_ - isoRw_) * cW;
  isoPw_ += (isoPwT_ - isoPw_) * cW;
  isoBg_ += (isoBgT_ - isoBg_) * cW;
  isoHg_ += (isoHgT_ - isoHg_) * cW;
  waterS_ += (waterT_ - waterS_) * onePole(0.1, kCtl);
  capS_ += (capT_ - capS_) * onePole(0.25, kCtl);
  vGain_ += ((vOn_ ? vGainT_ : 0.0) - vGain_) * onePole(0.3, kCtl);

  double tg[kStemCount];
  stemTargets(preset_, tg);
  for (int i = 0; i < kStemCount; ++i) gain_[i] = from_[i] * (1.0 - w) + tg[i] * w;

  const double lt = presetLpf(preset_);
  lpfBlend_ = std::exp(std::log(lpfFrom_) * (1.0 - w) + std::log(lt) * w);
  double eff = lpfBlend_;
  if (highCut_ > 0.0) eff = std::min(eff, highCut_);
  master_.setTarget(eff);

  // Master start/stop fade (4.0 s, symmetric so reversals stay continuous).
  if (masterDir_ != 0) {
    masterP_ += masterDir_ * static_cast<double>(kCtl) / kCrossfadeSamples;
    if (masterP_ >= 1.0) {
      masterP_ = 1.0;
      masterDir_ = 0;
    } else if (masterP_ <= 0.0) {
      masterP_ = 0.0;
      masterDir_ = 0;
      goSilent();
      return;
    }
  }
  fadeGain_ = fadeCurve(masterP_);

  // Voice scheduler: counts down only while the soundscape is fully audible, then plays the
  // next stored phrase (round robin) and waits one interval after it ends.
  if (vOn_ && vSlot_ < 0 && fadeGain_ > 0.95 && masterDir_ >= 0) {
    vWait_ -= kCtl;
    if (vWait_ <= 0) {
      for (int k = 0; k < kVoiceSlots; ++k) {
        const int s = (vNext_ + k) % kVoiceSlots;
        if (vLen_[s] > 0) {
          vSlot_ = s;
          vPos_ = 0;
          vNext_ = (s + 1) % kVoiceSlots;
          break;
        }
      }
      if (vSlot_ < 0) vWait_ = vIntervalSamples_;
    }
  }
}

void Engine::tickSample(float& outL, float& outR) {
  // --- noise beds ---------------------------------------------------------
  const double bL = brown_[0].process();
  const double bR = brown_[1].process();
  double pn[2] = {pink_[0].process(), pink_[1].process()};
  double pk[2];
  for (int c = 0; c < 2; ++c) {
    double lp, bp, hp, l2, b2, h2;
    pinkNotch_[c].tick(pn[c], lp, bp, hp);
    const double notched = lp + hp;
    pinkHp_[c].tick(pn[c], lp, bp, hp);
    pinkLp_[c].tick(hp, l2, b2, h2);
    pk[c] = 0.8 * notched + 0.5 * l2;
  }

  // --- rhythmic pulse stem (marimba + cello) ------------------------------
  const double beatInc = isoBpm_ / 60.0 / kSr;
  const double prevBeat = beatPhase_;
  beatPhase_ += beatInc;
  if (beatPhase_ >= 1.0) {
    beatPhase_ -= 1.0;
    const int pat = kMarimbaPattern[beatIndex_ & 7];
    triggerMarimba(pat, 0.07);
    if ((beatIndex_ & 3) == 0) triggerCello(kCelloRoots[(beatIndex_ >> 2) & 3]);
    ++beatIndex_;
  } else if (prevBeat < 0.5 && beatPhase_ >= 0.5) {
    const int pat = kMarimbaPattern[(beatIndex_ + 7) & 7];
    triggerMarimba(pat % 5 + 5, 0.035);
  }
  double pulse = 0.0;
  for (auto& v : marimba_) {
    if (!v.active) continue;
    double env;
    if (v.t < v.attack) {
      env = 0.5 * (1.0 - std::cos(kPi * v.t / v.attack));
    } else {
      env = std::exp(-(v.t - v.attack) / (v.tau * kSr));
    }
    const double hi = std::exp(-v.t / (0.06 * kSr));
    pulse += v.amp * env * (std::sin(v.ph) + 0.25 * hi * std::sin(4.0 * v.ph));
    v.ph = wrapPhase(v.ph + kTwoPi * v.f / kSr);
    ++v.t;
    if (v.t > v.attack && env < 1e-4) v.active = false;
  }
  for (auto& v : cello_) {
    if (!v.active) continue;
    double env;
    if (v.t < v.attack) {
      env = 0.5 * (1.0 - std::cos(kPi * v.t / v.attack));
    } else {
      env = std::exp(-(v.t - v.attack) / (v.tau * kSr));
    }
    pulse += v.amp * env *
             (std::sin(v.ph) + 0.5 * std::sin(2.0 * v.ph) + 0.33 * std::sin(3.0 * v.ph) +
              0.2 * std::sin(4.0 * v.ph)) *
             0.55;
    v.ph = wrapPhase(v.ph + kTwoPi * v.f / kSr);
    ++v.t;
    if (v.t > v.attack && env < 1e-4) v.active = false;
  }

  // --- warm pentatonic pad ------------------------------------------------
  double padL = 0.0, padR = 0.0;
  for (int i = 0; i < 5; ++i) {
    const double lfo = 0.65 + 0.35 * std::sin(padLfo_[i]);
    const double a = std::sin(padPh_[i][0]);
    const double b = std::sin(padPh_[i][1]);
    padL += lfo * 0.012 * (a + 0.5 * b);
    padR += lfo * 0.012 * (b + 0.5 * a);
    padPh_[i][0] = wrapPhase(padPh_[i][0] + kTwoPi * kPadHz[i] * 0.9985 / kSr);
    padPh_[i][1] = wrapPhase(padPh_[i][1] + kTwoPi * kPadHz[i] * 1.0015 / kSr);
    padLfo_[i] = wrapPhase(padLfo_[i] + kTwoPi * kPadLfoHz[i] / kSr);
  }

  // --- lub-dub heartbeat (60-120 Hz) --------------------------------------
  heartPhase_ += isoBpm_ / 60.0 / kSr;
  ++heartSince_;
  if (heartPhase_ >= 1.0) {
    heartPhase_ -= 1.0;
    lub_ = Thump();
    lub_.active = true;
    lub_.f0 = 120.0;
    lub_.f1 = 70.0;
    lub_.amp = 0.17;
    heartSince_ = 0;
    heartDub_ = false;
  }
  if (!heartDub_ && heartSince_ >= static_cast<int>(0.30 * kSr)) {
    heartDub_ = true;
    dub_ = Thump();
    dub_.active = true;
    dub_.f0 = 100.0;
    dub_.f1 = 60.0;
    dub_.amp = 0.11;
  }
  double heart = 0.0;
  for (Thump* th : {&lub_, &dub_}) {
    if (!th->active) continue;
    const int att = 960;
    double env;
    if (th->t < att) {
      env = 0.5 * (1.0 - std::cos(kPi * th->t / att));
    } else {
      env = std::exp(-(th->t - att) / (0.11 * kSr));
    }
    const double f = th->f1 + (th->f0 - th->f1) * std::exp(-th->t / (0.05 * kSr));
    heart += th->amp * env * std::sin(th->ph);
    th->ph = wrapPhase(th->ph + kTwoPi * f / kSr);
    ++th->t;
    if (th->t > att && env < 1e-4) th->active = false;
  }

  // --- 110 Hz drone -------------------------------------------------------
  const double trem = 0.85 + 0.15 * std::sin(droneLfo_);
  const double drone =
      trem * (0.09 * std::sin(dronePh_[0]) + 0.03 * std::sin(dronePh_[1]) + 0.02 * std::sin(dronePh_[2]));
  dronePh_[0] = wrapPhase(dronePh_[0] + kTwoPi * 110.0 / kSr);
  dronePh_[1] = wrapPhase(dronePh_[1] + kTwoPi * 220.0 / kSr);
  dronePh_[2] = wrapPhase(dronePh_[2] + kTwoPi * 165.0 / kSr);
  droneLfo_ = wrapPhase(droneLfo_ + kTwoPi * 0.1 / kSr);

  // --- water shimmer ------------------------------------------------------
  double wl, wb, wh;
  waterBp_.tick(waterRng_.white(), wl, wb, wh);
  const double waterMod = (0.5 + 0.5 * std::sin(waterLfo_[0])) * (0.5 + 0.5 * std::sin(waterLfo_[1]));
  const double water = 0.08 * wb * waterMod;
  waterLfo_[0] = wrapPhase(waterLfo_[0] + kTwoPi * 0.31 / kSr);
  waterLfo_[1] = wrapPhase(waterLfo_[1] + kTwoPi * 0.17 / kSr);

  // --- kalimba modal pluck synth -----------------------------------------
  double kal = 0.0;
  for (auto& v : kalimba_) {
    if (!v.active) continue;
    double att = v.t < kKalimbaAttack ? 0.5 * (1.0 - std::cos(kPi * v.t / kKalimbaAttack)) : 1.0;
    double s = 0.0;
    for (int k = 0; k < 3; ++k) {
      s += kKalimbaAmp[k] * v.dec[k] * std::sin(v.ph[k]);
      v.ph[k] = wrapPhase(v.ph[k] + kTwoPi * v.f * kKalimbaRatio[k] / kSr);
      v.dec[k] *= std::exp(-1.0 / (kKalimbaTau[k] * kSr));
    }
    kal += v.amp * att * v.rel * s;
    ++v.t;
    if (v.pending) {
      v.rel -= 1.0 / (0.015 * kSr);
      if (v.rel <= 0.0) startKalimba(v, v.pendingDegree, v.pendingVel);
    } else if (v.t > kKalimbaAttack && v.dec[0] < 0.002) {
      v.active = false;
    }
  }

  // --- mix ----------------------------------------------------------------
  const double* g = gain_;
  double mixL = g[kBrown] * bL + g[kPink] * pk[0] + g[kPulse] * pulse + g[kPad] * padL +
                g[kHeart] * heart + g[kDrone] * drone + g[kWater] * water + kal;
  double mixR = g[kBrown] * bR + g[kPink] * pk[1] + g[kPulse] * pulse + g[kPad] * padR +
                g[kHeart] * heart + g[kDrone] * drone + g[kWater] * water + kal;

  if (vSlot_ >= 0) {
    const int len = vLen_[vSlot_];
    const int fade = std::min(12000, len / 2);  // 250 ms raised-cosine edges
    double env = 1.0;
    if (vPos_ < fade) {
      env = 0.5 - 0.5 * std::cos(kPi * vPos_ / fade);
    } else if (vPos_ > len - fade) {
      env = 0.5 - 0.5 * std::cos(kPi * (len - vPos_) / fade);
    }
    const double v = vGain_ * env * vbuf_[vSlot_][vIdx_[vSlot_]][vPos_];
    mixL += v;
    mixR += v;
    if (++vPos_ >= len) {
      vSlot_ = -1;
      vWait_ = vIntervalSamples_;
    }
  }

  master_.tick();
  mixL = master_.process(0, mixL);
  mixR = master_.process(1, mixR);

  const double lvlGain = fadeGain_ * capS_;
  mixL *= lvlGain;
  mixR *= lvlGain;

  // --- soft-knee compressor ----------------------------------------------
  const double det = std::max(std::fabs(mixL), std::fabs(mixR));
  const double coef = det > compEnv_ ? onePole(0.003, 1.0) : onePole(0.15, 1.0);
  compEnv_ += (det - compEnv_) * coef;
  const double lvlDb = 20.0 * std::log10(compEnv_ + 1e-9);
  const double over = lvlDb - kCompThresholdDb;
  double gr;
  if (2.0 * over < -kCompKneeDb) {
    gr = 0.0;
  } else if (2.0 * std::fabs(over) <= kCompKneeDb) {
    const double t = over + kCompKneeDb * 0.5;
    gr = (1.0 / kCompRatio - 1.0) * t * t / (2.0 * kCompKneeDb);
  } else {
    gr = (1.0 / kCompRatio - 1.0) * over;
  }
  const double cg = std::exp(gr * kDbToLn);
  mixL *= cg;
  mixR *= cg;

  // --- brickwall + slew guard --------------------------------------------
  if (!(mixL == mixL)) mixL = 0.0;
  if (!(mixR == mixR)) mixR = 0.0;
  mixL = std::min(kCeiling, std::max(-kCeiling, mixL));
  mixR = std::min(kCeiling, std::max(-kCeiling, mixR));
  double dl = mixL - prevL_;
  double dr = mixR - prevR_;
  if (dl > kSlewLimit) {
    dl = kSlewLimit;
    ++slewHits_;
  } else if (dl < -kSlewLimit) {
    dl = -kSlewLimit;
    ++slewHits_;
  }
  if (dr > kSlewLimit) {
    dr = kSlewLimit;
    ++slewHits_;
  } else if (dr < -kSlewLimit) {
    dr = -kSlewLimit;
    ++slewHits_;
  }
  prevL_ += dl;
  prevR_ += dr;
  outL = static_cast<float>(prevL_);
  outR = static_cast<float>(prevR_);
}

void Engine::render(float* out, int frames) {
  drain();
  for (int i = 0; i < frames; ++i) {
    if (silent_) {
      out[2 * i] = 0.0f;
      out[2 * i + 1] = 0.0f;
      continue;
    }
    if (ctl_ <= 0) {
      control();
      ctl_ = kCtl;
      if (silent_) {
        out[2 * i] = 0.0f;
        out[2 * i + 1] = 0.0f;
        continue;
      }
    }
    --ctl_;
    tickSample(out[2 * i], out[2 * i + 1]);
  }
}

}  // namespace aura

extern "C" {

void* aura_dsp_create(int /*sampleRate*/) { return new (std::nothrow) aura::Engine(); }
void aura_dsp_destroy(void* e) { delete static_cast<aura::Engine*>(e); }
void aura_dsp_start(void* e, int preset) { static_cast<aura::Engine*>(e)->start(preset); }
void aura_dsp_stop(void* e) { static_cast<aura::Engine*>(e)->stop(); }
void aura_dsp_switch_preset(void* e, int preset) {
  static_cast<aura::Engine*>(e)->switchPreset(preset);
}
void aura_dsp_apply_iso(void* e, double bpm, double lpfHz, double rw, double pw, double bg,
                        double hg) {
  static_cast<aura::Engine*>(e)->applyIso(bpm, lpfHz, rw, pw, bg, hg);
}
void aura_dsp_set_profile_limits(void* e, double highCutHz, double masterCap, int allowWater) {
  static_cast<aura::Engine*>(e)->setProfileLimits(highCutHz, masterCap, allowWater != 0);
}
void aura_dsp_trigger_note(void* e, int degree, double velocity) {
  static_cast<aura::Engine*>(e)->triggerNote(degree, velocity);
}
void aura_dsp_render(void* e, float* out, int frames) {
  static_cast<aura::Engine*>(e)->render(out, frames);
}
void aura_dsp_load_voice(void* e, int slot, const float* mono, int frames) {
  static_cast<aura::Engine*>(e)->loadVoice(slot, mono, frames);
}
void aura_dsp_clear_voice(void* e, int slot) { static_cast<aura::Engine*>(e)->clearVoice(slot); }
void aura_dsp_set_voice_weave(void* e, int enabled, double gain, double intervalSec) {
  static_cast<aura::Engine*>(e)->setVoiceWeave(enabled != 0, gain, intervalSec);
}

}  // extern "C"
