// Standalone DSP verification harness (no frameworks).
#include <algorithm>
#include <cmath>
#include <complex>
#include <cstdio>
#include <vector>

#include "../dsp_engine.h"

using namespace aura;

static int g_failures = 0;
#define CHECK(cond, ...)                                  \
  do {                                                    \
    if (!(cond)) {                                        \
      ++g_failures;                                       \
      std::printf("  FAIL: " __VA_ARGS__);                \
      std::printf("\n");                                  \
    }                                                     \
  } while (0)

static const float kCeilF = static_cast<float>(0.70794578);
static const double kSr = 48000.0;

static void fft(std::vector<std::complex<double>>& a) {
  const size_t n = a.size();
  for (size_t i = 1, j = 0; i < n; ++i) {
    size_t bit = n >> 1;
    for (; j & bit; bit >>= 1) j ^= bit;
    j ^= bit;
    if (i < j) std::swap(a[i], a[j]);
  }
  for (size_t len = 2; len <= n; len <<= 1) {
    const double ang = -2.0 * kPi / static_cast<double>(len);
    const std::complex<double> wl(std::cos(ang), std::sin(ang));
    for (size_t i = 0; i < n; i += len) {
      std::complex<double> w(1.0, 0.0);
      for (size_t k = 0; k < len / 2; ++k) {
        const auto u = a[i + k];
        const auto v = a[i + k + len / 2] * w;
        a[i + k] = u + v;
        a[i + k + len / 2] = u - v;
        w *= wl;
      }
    }
  }
}

// Welch PSD (Hann, 50% overlap). Returns power per bin (N/2+1 bins).
static std::vector<double> welch(const std::vector<double>& x, size_t n = 4096) {
  std::vector<double> psd(n / 2 + 1, 0.0);
  std::vector<double> win(n);
  for (size_t i = 0; i < n; ++i) win[i] = 0.5 - 0.5 * std::cos(kTwoPi * i / n);
  int segs = 0;
  for (size_t s = 0; s + n <= x.size(); s += n / 2) {
    std::vector<std::complex<double>> a(n);
    for (size_t i = 0; i < n; ++i) a[i] = x[s + i] * win[i];
    fft(a);
    for (size_t k = 0; k <= n / 2; ++k) psd[k] += std::norm(a[k]);
    ++segs;
  }
  for (auto& v : psd) v /= std::max(1, segs);
  return psd;
}

// Slope in dB/octave by regressing 1/3-octave band-average PSD (dB) on log2(f).
static double slopeDbPerOct(const std::vector<double>& psd, double fLo, double fHi) {
  const size_t n = (psd.size() - 1) * 2;
  std::vector<double> xs, ys;
  for (double fc = fLo; fc * std::pow(2.0, 1.0 / 6.0) <= fHi; fc *= std::pow(2.0, 1.0 / 3.0)) {
    const double lo = fc / std::pow(2.0, 1.0 / 6.0), hi = fc * std::pow(2.0, 1.0 / 6.0);
    double sum = 0;
    int cnt = 0;
    for (size_t k = 1; k < psd.size(); ++k) {
      const double f = k * kSr / n;
      if (f >= lo && f < hi) {
        sum += psd[k];
        ++cnt;
      }
    }
    if (cnt == 0) continue;
    xs.push_back(std::log2(fc));
    ys.push_back(10.0 * std::log10(sum / cnt));
  }
  double mx = 0, my = 0;
  for (size_t i = 0; i < xs.size(); ++i) {
    mx += xs[i];
    my += ys[i];
  }
  mx /= xs.size();
  my /= xs.size();
  double num = 0, den = 0;
  for (size_t i = 0; i < xs.size(); ++i) {
    num += (xs[i] - mx) * (ys[i] - my);
    den += (xs[i] - mx) * (xs[i] - mx);
  }
  return num / den;
}

static double bandPower(const std::vector<double>& psd, double fLo, double fHi) {
  const size_t n = (psd.size() - 1) * 2;
  double s = 0;
  for (size_t k = 1; k < psd.size(); ++k) {
    const double f = k * kSr / n;
    if (f >= fLo && f < fHi) s += psd[k];
  }
  return s;
}

static double rms(const std::vector<float>& v, size_t from, size_t to) {
  double s = 0;
  for (size_t i = from; i < to; ++i) s += double(v[i]) * v[i];
  return std::sqrt(s / std::max<size_t>(1, to - from));
}

struct Capture {
  std::vector<float> data;  // interleaved stereo
  double peak = 0, maxDelta = 0;
  bool finite = true;
  float prevL = 0, prevR = 0;
  void add(const float* buf, int frames) {
    for (int i = 0; i < frames; ++i) {
      const float l = buf[2 * i], r = buf[2 * i + 1];
      if (!std::isfinite(l) || !std::isfinite(r)) finite = false;
      peak = std::max({peak, double(std::fabs(l)), double(std::fabs(r))});
      maxDelta = std::max({maxDelta, double(std::fabs(l - prevL)), double(std::fabs(r - prevR))});
      prevL = l;
      prevR = r;
    }
    data.insert(data.end(), buf, buf + 2 * frames);
  }
};

// Render `seconds` in 480-frame blocks, calling `perBlock(blockIndex)` before each block.
template <typename F>
static void run(Engine& e, Capture& cap, double seconds, F perBlock) {
  std::vector<float> buf(960);
  const int blocks = static_cast<int>(seconds * kSr / 480.0);
  for (int b = 0; b < blocks; ++b) {
    perBlock(b);
    e.render(buf.data(), 480);
    cap.add(buf.data(), 480);
  }
}

static void testNoiseSlopes() {
  std::printf("[noise slopes]\n");
  const size_t n = 1 << 20;
  std::vector<double> x(n);
  BrownNoise br;
  br.reset(42);
  for (size_t i = 0; i < 4800; ++i) br.process();
  for (auto& v : x) v = br.process();
  const double sb = slopeDbPerOct(welch(x), 100.0, 5000.0);
  std::printf("  brown slope %.3f dB/oct (target -6.02 +-1)\n", sb);
  CHECK(std::fabs(sb + 6.02) <= 1.0, "brown slope %.3f", sb);

  PinkNoise pk;
  pk.reset(43);
  for (auto& v : x) v = pk.process();
  const double sp = slopeDbPerOct(welch(x), 100.0, 8000.0);
  std::printf("  pink slope  %.3f dB/oct (target -3.01 +-1)\n", sp);
  CHECK(std::fabs(sp + 3.01) <= 1.0, "pink slope %.3f", sp);

  double r = 0;
  br.reset(42);
  for (int i = 0; i < 480000; ++i) {
    const double v = br.process();
    r += v * v;
  }
  std::printf("  brown rms %.4f\n", std::sqrt(r / 480000));
}

static void testLowpass() {
  std::printf("[LPF 650 Hz]\n");
  auto gainDb = [](double f) {
    Svf s;
    s.setCoeffs(650.0, 0.7071);
    double peak = 0;
    for (int i = 0; i < 96000; ++i) {
      const double y = s.lowpass(std::sin(kTwoPi * f * i / kSr));
      if (i > 48000) peak = std::max(peak, std::fabs(y));
    }
    return 20.0 * std::log10(peak);
  };
  const double g100 = gainDb(100), g2k = gainDb(2000), g4k = gainDb(4000), g8k = gainDb(8000);
  std::printf("  100Hz %.2f dB, 2k %.2f dB, 4k %.2f dB, 8k %.2f dB\n", g100, g2k, g4k, g8k);
  CHECK(g100 > -0.5, "passband %.2f", g100);
  CHECK(g2k < -18.0, "2k atten %.2f", g2k);
  CHECK(g4k < -30.0, "4k atten %.2f", g4k);
  CHECK(g8k < -42.0, "8k atten %.2f", g8k);

  // Engine-level: Deep Crisis (SOS) must carry nothing audible above 2 kHz.
  Engine e;
  Capture cap;
  e.start(1);
  run(e, cap, 14.0, [](int) {});
  std::vector<double> mono;
  for (size_t i = 8 * 48000; i + 1 < cap.data.size(); i += 2) mono.push_back(cap.data[i]);
  const auto psd = welch(mono);
  const double hi = bandPower(psd, 2000.0, 24000.0), lo = bandPower(psd, 20.0, 650.0);
  const double ratio = 10.0 * std::log10((hi + 1e-30) / lo);
  std::printf("  SOS engine: >2 kHz vs <650 Hz energy = %.1f dB\n", ratio);
  CHECK(ratio < -40.0, "SOS HF energy ratio %.1f dB", ratio);
}

static void testPeakAndDelta() {
  std::printf("[peak / delta]\n");
  // 1) abrupt preset switching with kalimba spam, full-scale iso params.
  {
    Engine e;
    Capture cap;
    e.setProfileLimits(0, 1.0, true);
    e.applyIso(58, 500, 0, 1, 1, 1);
    e.start(0);
    int note = 0;
    auto spam = [&](int b) {
      if (b % 2 == 0) e.triggerNote(note++ % 10, 1.0);
      if (b % 3 == 0) e.triggerNote((note * 7) % 10, 5.0);
    };
    run(e, cap, 3.0, spam);
    e.switchPreset(1);
    run(e, cap, 0.5, spam);
    e.switchPreset(2);
    run(e, cap, 0.5, spam);
    e.switchPreset(3);
    run(e, cap, 0.5, spam);
    e.switchPreset(0);
    run(e, cap, 4.0, spam);
    e.stop();
    run(e, cap, 5.0, spam);
    std::printf("  spam run: peak %.8f (ceiling %.8f), max delta %.6f, slew hits %llu, finite=%d\n",
                cap.peak, double(kCeilF), cap.maxDelta, (unsigned long long)e.slewHits(),
                cap.finite);
    CHECK(cap.finite, "non-finite sample");
    CHECK(cap.peak <= double(kCeilF), "peak %.8f exceeds ceiling", cap.peak);
    CHECK(cap.maxDelta < 0.005, "max delta %.6f", cap.maxDelta);
    CHECK(cap.peak > 0.02, "engine produced no audible signal (peak %.5f)", cap.peak);
  }
  // 2) no kalimba: start, switch, stop; natural delta (slew guard should stay idle).
  for (int p = 0; p < 4; ++p) {
    Engine e;
    Capture cap;
    e.applyIso(104, 2000, 1, 0, 0, 0);
    e.start(p);
    run(e, cap, 5.0, [](int) {});
    const double fadeInRms = rms(cap.data, 0, 4800 * 2);
    const double fullRms = rms(cap.data, 4 * 48000 * 2, 5 * 48000 * 2);
    e.switchPreset((p + 1) % 4);
    run(e, cap, 6.0, [](int) {});
    e.stop();
    run(e, cap, 5.0, [](int) {});
    const double tailRms = rms(cap.data, cap.data.size() - 4800, cap.data.size());
    std::printf("  preset %d: peak %.4f, max delta %.6f, slew hits %llu, rms start %.5f -> %.4f, tail %.8f, silent=%d\n",
                p, cap.peak, cap.maxDelta, (unsigned long long)e.slewHits(), fadeInRms, fullRms,
                tailRms, e.silent());
    CHECK(cap.maxDelta < 0.005, "preset %d max delta %.6f", p, cap.maxDelta);
    CHECK(cap.peak <= double(kCeilF), "preset %d peak %.8f", p, cap.peak);
    CHECK(fadeInRms < 0.1 * fullRms, "preset %d fade-in not gradual", p);
    CHECK(e.silent() && tailRms == 0.0, "preset %d not silent after stop", p);
  }
  // 3) Iso transition parameters sweep through the whole protocol.
  {
    Engine e;
    Capture cap;
    e.start(0);
    const double pts[4][6] = {{104, 2000, 1, 0, 0, 0},
                              {88, 1450, 0.5, 0.5, 0, 0},
                              {72, 900, 0, 1, 0.5, 0.5},
                              {58, 500, 0, 1, 1, 1}};
    for (int i = 0; i < 4; ++i) {
      e.applyIso(pts[i][0], pts[i][1], pts[i][2], pts[i][3], pts[i][4], pts[i][5]);
      run(e, cap, 4.0, [&](int b) {
        if (b % 40 == 0) e.triggerNote(b / 40 % 10, 0.9);
      });
    }
    std::printf("  iso sweep: peak %.4f, max delta %.6f\n", cap.peak, cap.maxDelta);
    CHECK(cap.peak <= double(kCeilF), "iso sweep peak %.8f", cap.peak);
    CHECK(cap.maxDelta < 0.005, "iso sweep delta %.6f", cap.maxDelta);
  }
  // 4) master cap, high cut, no water.
  {
    double peaks[2];
    const double caps[2] = {0.5, 1.0};
    for (int i = 0; i < 2; ++i) {
      Engine e;
      Capture cap;
      e.setProfileLimits(800.0, caps[i], false);
      e.start(3);
      run(e, cap, 8.0, [&](int blk) {
        if (blk % 20 == 0) e.triggerNote(blk % 10, 1.0);
      });
      peaks[i] = cap.peak;
    }
    std::printf("  master cap: peak %.4f at cap 0.5 vs %.4f at cap 1.0\n", peaks[0], peaks[1]);
    CHECK(peaks[0] <= 0.6 * peaks[1], "master cap not applied");
  }
}

static void testKalimbaAndDeterminism() {
  std::printf("[kalimba / determinism]\n");
  Engine a, b;
  Capture ca, cb;
  a.start(3);
  b.start(3);
  auto trig = [](Engine& e) {
    return [&e](int blk) {
      if (blk == 100) e.triggerNote(4, 0.7);
    };
  };
  run(a, ca, 6.0, trig(a));
  run(b, cb, 6.0, trig(b));
  CHECK(ca.data == cb.data, "engine not deterministic");

  // Kalimba onset: a single note on an otherwise silent bed must have >=45 ms rise.
  Capture quiet;
  Engine e2;
  e2.setProfileLimits(0, 1.0, false);
  e2.start(1);
  run(e2, quiet, 5.0, [](int) {});
  Capture withNote;
  Engine e3;
  e3.setProfileLimits(0, 1.0, false);
  e3.start(1);
  run(e3, withNote, 5.0, [&](int blk) {
    if (blk == 480) e3.triggerNote(9, 1.0);
  });
  // difference signal = kalimba contribution (compressor idle at these levels).
  double early = 0, late = 0;
  const size_t start = 480 * 480 * 2;
  for (size_t i = 0; i < 480 * 2; ++i)  // first 10 ms after onset
    early = std::max(early, std::fabs(double(withNote.data[start + i]) - quiet.data[start + i]));
  for (size_t i = 3000 * 2; i < 6000 * 2; ++i)
    late = std::max(late, std::fabs(double(withNote.data[start + i]) - quiet.data[start + i]));
  std::printf("  kalimba 10 ms envelope max %.5f vs later max %.5f\n", early, late);
  CHECK(late > 0.003, "kalimba inaudible");
  CHECK(early < 0.2 * late, "kalimba attack too abrupt");
}

static void testVoiceWeave() {
  std::printf("[voice weave]\n");
  // A 2 s "phrase": 220 Hz carrier with a slow syllable-like envelope, peak 0.5.
  std::vector<float> phrase(96000);
  for (size_t i = 0; i < phrase.size(); ++i) {
    const double t = double(i) / kSr;
    phrase[i] = float(0.5 * std::sin(2.0 * kPi * 220.0 * t) * (0.6 + 0.4 * std::sin(2.0 * kPi * 3.0 * t)));
  }
  auto setup = [&](Engine& e, bool voice) {
    e.start(0);
    if (voice) {
      e.loadVoice(0, phrase.data(), int(phrase.size()));
      e.setVoiceWeave(true, 0.12, 10.0);
    }
  };
  Engine with, without;
  Capture cw, co;
  setup(with, true);
  setup(without, false);
  run(with, cw, 40.0, [](int) {});
  run(without, co, 40.0, [](int) {});

  CHECK(cw.finite, "non-finite output with voice");
  CHECK(cw.peak <= kCeilF, "voice breaks the -3 dBFS ceiling (%.5f)", cw.peak);
  CHECK(cw.maxDelta < 0.005, "voice causes click/pop (delta %.5f)", cw.maxDelta);

  auto diffRms = [&](double fromS, double toS) {
    double sum = 0;
    const size_t a = size_t(fromS * kSr) * 2, b = size_t(toS * kSr) * 2;
    for (size_t i = a; i < b; ++i) {
      const double d = double(cw.data[i]) - co.data[i];
      sum += d * d;
    }
    return std::sqrt(sum / double(b - a));
  };
  // First phrase starts ~10 s after the soundscape is fully audible (4 s fade + 10 s wait).
  const double before = diffRms(0.0, 13.5);
  const double during = diffRms(15.0, 16.0);
  const double gap = diffRms(17.0, 22.0);
  const double second = diffRms(26.8, 27.4);
  std::printf("  diff rms: before %.6f, phrase1 %.6f, gap %.6f, phrase2 %.6f\n", before, during,
              gap, second);
  CHECK(before < 1e-6, "voice leaked before its first slot");
  CHECK(during > 1e-3, "first phrase inaudible");
  CHECK(gap < during * 0.1, "voice does not pause between phrases");
  CHECK(second > 1e-3, "second phrase never played");

  // Clearing the slot silences the weave; disabling does too.
  Engine cleared, plain;
  Capture cc, cp;
  setup(cleared, true);
  cleared.clearVoice(0);
  setup(plain, false);
  run(cleared, cc, 25.0, [](int) {});
  run(plain, cp, 25.0, [](int) {});
  CHECK(cc.data == cp.data, "cleared slot still produced audio");

  // Hostile input is sanitised: NaN / huge samples never break the ceiling.
  std::vector<float> bad(48000, 1e9f);
  bad[100] = std::nanf("");
  Engine hostile;
  Capture ch;
  hostile.start(1);
  hostile.loadVoice(1, bad.data(), int(bad.size()));
  hostile.loadVoice(9, bad.data(), 10);  // invalid slot ignored
  hostile.setVoiceWeave(true, 99.0, 0.0);
  run(hostile, ch, 40.0, [](int) {});
  CHECK(ch.finite, "NaN voice input leaked into the output");
  CHECK(ch.peak <= kCeilF, "hostile voice exceeded the ceiling (%.5f)", ch.peak);
  CHECK(ch.maxDelta < 0.005, "hostile voice caused a click (delta %.5f)", ch.maxDelta);
}

int main() {
  testNoiseSlopes();
  testLowpass();
  testPeakAndDelta();
  testKalimbaAndDeterminism();
  testVoiceWeave();
  if (g_failures == 0) {
    std::printf("ALL DSP TESTS PASSED\n");
    return 0;
  }
  std::printf("%d CHECK(S) FAILED\n", g_failures);
  return 1;
}
