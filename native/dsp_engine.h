// AuraSOS neuro-acoustic DSP engine. C++17, zero allocation in render().
#ifndef AURASYNC_DSP_ENGINE_H
#define AURASYNC_DSP_ENGINE_H

#include <stdint.h>

#if defined(_WIN32)
#define AURA_API __declspec(dllexport)
#else
#define AURA_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Preset indices match Dart SessionPreset: 0 isoDownRegulator, 1 deepCrisisAnchor,
// 2 focusClassroom, 3 calmStim. All calls are lock-free and safe from a UI thread
// while another thread calls aura_dsp_render.
AURA_API void* aura_dsp_create(int sampleRate);
AURA_API void aura_dsp_destroy(void* engine);
AURA_API void aura_dsp_start(void* engine, int preset);
AURA_API void aura_dsp_stop(void* engine);
AURA_API void aura_dsp_switch_preset(void* engine, int preset);
AURA_API void aura_dsp_apply_iso(void* engine, double bpm, double lpfHz, double rhythmWeight,
                                 double padWeight, double brownGain, double heartGain);
AURA_API void aura_dsp_set_profile_limits(void* engine, double highCutHz, double masterCap,
                                          int allowWater);
AURA_API void aura_dsp_trigger_note(void* engine, int degree, double velocity);
AURA_API void aura_dsp_render(void* engine, float* out, int frames);

// Caregiver voice weaving. Phrases are mono float32 at 48 kHz (<= 288000 frames, 4 slots).
// load/clear copy into a back buffer on the calling (non-audio) thread and publish it through
// the lock-free queue; load phrases while no session is running.
AURA_API void aura_dsp_load_voice(void* engine, int slot, const float* mono, int frames);
AURA_API void aura_dsp_clear_voice(void* engine, int slot);
AURA_API void aura_dsp_set_voice_weave(void* engine, int enabled, double gain,
                                       double intervalSec);

#ifdef __cplusplus
}  // extern "C"
#endif

#ifdef __cplusplus
#include <atomic>
#include <cmath>
#include <memory>

namespace aura {

constexpr int kSampleRate = 48000;
constexpr int kCrossfadeSamples = 192000;
// 0.70794578 (-3 dBFS) rounded down so the float32 representation never exceeds it.
constexpr double kCeiling = 0.7079457;
constexpr double kPi = 3.14159265358979323846;
constexpr double kTwoPi = 6.28318530717958647692;

struct Rng {
  uint32_t s = 0x9E3779B9u;
  void seed(uint32_t v) { s = v ? v : 0x9E3779B9u; }
  // Uniform in [-1, 1).
  double white() {
    s ^= s << 13;
    s ^= s >> 17;
    s ^= s << 5;
    return static_cast<double>(static_cast<int32_t>(s)) * (1.0 / 2147483648.0);
  }
};

// Leaky integrator (-6 dB/oct) followed by a 20 Hz DC blocker.
class BrownNoise {
 public:
  static constexpr double kLeak = 0.99938;
  static constexpr double kGain = 0.006;
  static constexpr double kHp = 1.0 - kTwoPi * 20.0 / kSampleRate;
  void reset(uint32_t seed) {
    rng_.seed(seed);
    y_ = hpX_ = hpY_ = 0.0;
  }
  double process() {
    y_ = kLeak * y_ + kGain * rng_.white();
    const double out = y_ - hpX_ + kHp * hpY_;
    hpX_ = y_;
    hpY_ = out;
    return out;
  }

 private:
  Rng rng_;
  double y_ = 0.0, hpX_ = 0.0, hpY_ = 0.0;
};

// Paul Kellet's refined 7-state pink filter (-3 dB/oct).
class PinkNoise {
 public:
  void reset(uint32_t seed) {
    rng_.seed(seed);
    b0_ = b1_ = b2_ = b3_ = b4_ = b5_ = b6_ = 0.0;
  }
  double process() {
    const double w = rng_.white();
    b0_ = 0.99886 * b0_ + w * 0.0555179;
    b1_ = 0.99332 * b1_ + w * 0.0750759;
    b2_ = 0.96900 * b2_ + w * 0.1538520;
    b3_ = 0.86650 * b3_ + w * 0.3104856;
    b4_ = 0.55000 * b4_ + w * 0.5329522;
    b5_ = -0.7616 * b5_ - w * 0.0168980;
    const double out = b0_ + b1_ + b2_ + b3_ + b4_ + b5_ + b6_ + w * 0.5362;
    b6_ = w * 0.115926;
    return out * 0.015;
  }

 private:
  Rng rng_;
  double b0_ = 0, b1_ = 0, b2_ = 0, b3_ = 0, b4_ = 0, b5_ = 0, b6_ = 0;
};

// Topology-preserving state-variable filter (stable under coefficient modulation).
class Svf {
 public:
  void setCoeffs(double fc, double q) {
    const double nyq = 0.49 * kSampleRate;
    if (fc > nyq) fc = nyq;
    if (fc < 5.0) fc = 5.0;
    g_ = std::tan(kPi * fc / kSampleRate);
    k_ = 1.0 / q;
    a1_ = 1.0 / (1.0 + g_ * (g_ + k_));
    a2_ = g_ * a1_;
    a3_ = g_ * a2_;
  }
  void reset() { ic1_ = ic2_ = 0.0; }
  inline void tick(double x, double& lp, double& bp, double& hp) {
    const double v3 = x - ic2_;
    const double v1 = a1_ * ic1_ + a2_ * v3;
    const double v2 = ic2_ + a2_ * ic1_ + a3_ * v3;
    ic1_ = 2.0 * v1 - ic1_;
    ic2_ = 2.0 * v2 - ic2_;
    lp = v2;
    bp = v1 * k_;  // unity-gain band-pass
    hp = x - k_ * v1 - v2;
  }
  inline double lowpass(double x) {
    double lp, bp, hp;
    tick(x, lp, bp, hp);
    return lp;
  }

 private:
  double g_ = 0, k_ = 1, a1_ = 0, a2_ = 0, a3_ = 0, ic1_ = 0, ic2_ = 0;
};

// Stereo low-pass whose cutoff glides in the log domain; coefficients refresh every
// 16 samples so there is no zipper noise.
class SmoothLowpass {
 public:
  void init(double fc, double q) {
    q_ = q;
    logCur_ = logTarget_ = std::log2(fc);
    n_ = 0;
    update();
    l_.reset();
    r_.reset();
  }
  void setTarget(double fc) { logTarget_ = std::log2(fc < 20.0 ? 20.0 : fc); }
  void tick() {
    logCur_ += (logTarget_ - logCur_) * kSmooth;
    if (++n_ >= 16) {
      n_ = 0;
      update();
    }
  }
  double process(int ch, double x) { return ch == 0 ? l_.lowpass(x) : r_.lowpass(x); }
  void resetState() {
    l_.reset();
    r_.reset();
  }

 private:
  static constexpr double kSmooth = 1.0 / (0.12 * kSampleRate);
  void update() {
    const double fc = std::exp2(logCur_);
    l_.setCoeffs(fc, q_);
    r_.setCoeffs(fc, q_);
  }
  Svf l_, r_;
  double logCur_ = 11, logTarget_ = 11, q_ = 0.7071;
  int n_ = 0;
};

enum Stem { kBrown = 0, kPink, kPulse, kPad, kHeart, kDrone, kWater, kStemCount };

class Engine {
 public:
  Engine();
  void start(int preset);
  void stop();
  void switchPreset(int preset);
  void applyIso(double bpm, double lpfHz, double rw, double pw, double bg, double hg);
  void setProfileLimits(double highCutHz, double masterCap, bool allowWater);
  void triggerNote(int degree, double velocity);
  void render(float* out, int frames);
  void loadVoice(int slot, const float* mono, int frames);
  void clearVoice(int slot);
  void setVoiceWeave(bool enabled, double gain, double intervalSec);

  // Diagnostics (render thread only).
  uint64_t slewHits() const { return slewHits_; }
  bool silent() const { return silent_; }

 private:
  struct Cmd {
    int type;
    double a, b, c, d, e, f;
  };
  static constexpr uint32_t kQueue = 1024;
  static constexpr int kCtl = 16;
  static constexpr int kKalimbaVoices = 8;
  static constexpr int kMarimbaVoices = 4;
  static constexpr int kCelloVoices = 2;

  struct KVoice {
    bool active = false, pending = false;
    int t = 0;
    int pendingDegree = 0;
    double pendingVel = 0.0;
    double amp = 0.0, rel = 1.0;
    double f = 0.0;
    double ph[3] = {0, 0, 0};
    double dec[3] = {1, 1, 1};
  };
  struct PVoice {  // marimba / cello pulse voice
    bool active = false;
    int t = 0;
    int attack = 1;
    double f = 0.0, amp = 0.0, tau = 0.3, ph = 0.0;
    bool cello = false;
  };
  struct Thump {
    bool active = false;
    int t = 0;
    double f0 = 100, f1 = 60, amp = 0.2, ph = 0.0;
  };

  bool push(const Cmd& c);
  void drain();
  void doStart(int p);
  void doSwitch(int p);
  void doNote(int degree, double vel);
  void control();
  void stemTargets(int preset, double* tg) const;
  double presetLpf(int preset) const;
  void snapToPreset();
  void goSilent();
  void resetStemState();
  void tickSample(float& outL, float& outR);
  void startKalimba(KVoice& v, int degree, double vel);
  void triggerMarimba(int degree, double amp);
  void triggerCello(int degree);

  Cmd q_[kQueue];
  std::atomic<uint32_t> qHead_{0}, qTail_{0};

  // Caregiver voice layer. Buffers are filled on the UI thread (back buffer only) and
  // published to the render thread by a queue command, so render never allocates or locks.
  static constexpr int kVoiceSlots = 4;
  static constexpr int kVoiceMax = 288000;  // 6 s
  std::unique_ptr<float[]> vbuf_[kVoiceSlots][2];
  int vShadow_[kVoiceSlots] = {0, 0, 0, 0};  // UI thread: buffer index currently published
  int vLen_[kVoiceSlots] = {0, 0, 0, 0};     // render thread
  int vIdx_[kVoiceSlots] = {0, 0, 0, 0};     // render thread
  bool vOn_ = false;
  double vGainT_ = 0.12, vGain_ = 0.0;
  int vIntervalSamples_ = 45 * 48000;
  int vWait_ = 20 * 48000;
  int vSlot_ = -1, vPos_ = 0, vNext_ = 0;

  // Transport.
  bool silent_ = true;
  int preset_ = 0;
  double masterP_ = 0.0;
  int masterDir_ = 0;
  double xfP_ = 1.0;
  double gain_[kStemCount] = {0};
  double from_[kStemCount] = {0};
  double lpfFrom_ = 2000.0, lpfBlend_ = 2000.0;
  int ctl_ = 0;
  double fadeGain_ = 0.0;

  // Iso targets and smoothed values.
  double isoBpmT_ = 104, isoLpfT_ = 2000, isoRwT_ = 1, isoPwT_ = 0, isoBgT_ = 0, isoHgT_ = 0;
  double isoBpm_ = 104, isoRw_ = 1, isoPw_ = 0, isoBg_ = 0, isoHg_ = 0;

  // Profile.
  double highCut_ = 0.0, capT_ = 1.0, capS_ = 1.0, waterT_ = 1.0, waterS_ = 1.0;

  // Sources.
  BrownNoise brown_[2];
  PinkNoise pink_[2];
  Rng waterRng_;
  Svf pinkNotch_[2], pinkHp_[2], pinkLp_[2], waterBp_;
  SmoothLowpass master_;

  PVoice marimba_[kMarimbaVoices];
  PVoice cello_[kCelloVoices];
  int marimbaNext_ = 0, celloNext_ = 0;
  double beatPhase_ = 0.0;
  int beatIndex_ = 0;

  double padPh_[5][2] = {{0}};
  double padLfo_[5] = {0};
  double heartPhase_ = 0.0;
  int heartSince_ = 0;
  bool heartDub_ = true;
  Thump lub_, dub_;
  double dronePh_[3] = {0, 0, 0};
  double droneLfo_ = 0.0;
  double waterLfo_[2] = {0, 0};
  KVoice kalimba_[kKalimbaVoices];

  // Master dynamics.
  double compEnv_ = 0.0;
  double prevL_ = 0.0, prevR_ = 0.0;
  uint64_t slewHits_ = 0;
};

}  // namespace aura
#endif  // __cplusplus

#endif  // AURASYNC_DSP_ENGINE_H
