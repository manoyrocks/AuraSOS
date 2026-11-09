// OpenSL ES backend (every Android version we ship to, API 24+; AAudio would need API 26). Float
// stereo through the Android simple buffer queue. The app's slow 4 s fades never need low
// latency, so four 20 ms buffers keep underruns away.
#if defined(__ANDROID__)

#include <SLES/OpenSLES.h>
#include <SLES/OpenSLES_Android.h>

#include <atomic>
#include <cstring>
#include <mutex>

#include "audio_output.h"
#include "dsp_engine.h"

namespace {

constexpr int kSampleRate = 48000;
constexpr int kChannels = 2;
constexpr int kBufferFrames = 960;
constexpr int kBufferCount = 4;

std::atomic<void*> gEngine{nullptr};
std::mutex gMutex;  // guards every OpenSL object below
SLObjectItf gSlEngine = nullptr;
SLObjectItf gMix = nullptr;
SLObjectItf gPlayer = nullptr;
SLPlayItf gPlay = nullptr;
SLAndroidSimpleBufferQueueItf gQueue = nullptr;
float gBuffers[kBufferCount][kBufferFrames * kChannels];
int gNext = 0;

// Runs on the OpenSL audio thread: no locks, no allocation.
void fillAndEnqueue() {
  float* out = gBuffers[gNext];
  gNext = (gNext + 1) % kBufferCount;
  void* engine = gEngine.load(std::memory_order_acquire);
  if (engine == nullptr) {
    std::memset(out, 0, sizeof(float) * kChannels * kBufferFrames);
  } else {
    aura_dsp_render(engine, out, kBufferFrames);
  }
  (*gQueue)->Enqueue(gQueue, out, sizeof(float) * kChannels * kBufferFrames);
}

void onBuffer(SLAndroidSimpleBufferQueueItf, void*) { fillAndEnqueue(); }

void destroyLocked() {
  if (gPlay != nullptr) (*gPlay)->SetPlayState(gPlay, SL_PLAYSTATE_STOPPED);
  if (gQueue != nullptr) (*gQueue)->Clear(gQueue);
  if (gPlayer != nullptr) (*gPlayer)->Destroy(gPlayer);
  if (gMix != nullptr) (*gMix)->Destroy(gMix);
  if (gSlEngine != nullptr) (*gSlEngine)->Destroy(gSlEngine);
  gPlayer = gMix = gSlEngine = nullptr;
  gPlay = nullptr;
  gQueue = nullptr;
}

bool openLocked() {
  SLEngineItf engineItf = nullptr;
  if (slCreateEngine(&gSlEngine, 0, nullptr, 0, nullptr, nullptr) != SL_RESULT_SUCCESS) return false;
  if ((*gSlEngine)->Realize(gSlEngine, SL_BOOLEAN_FALSE) != SL_RESULT_SUCCESS) return false;
  if ((*gSlEngine)->GetInterface(gSlEngine, SL_IID_ENGINE, &engineItf) != SL_RESULT_SUCCESS) return false;
  if ((*engineItf)->CreateOutputMix(engineItf, &gMix, 0, nullptr, nullptr) != SL_RESULT_SUCCESS) return false;
  if ((*gMix)->Realize(gMix, SL_BOOLEAN_FALSE) != SL_RESULT_SUCCESS) return false;

  SLDataLocator_AndroidSimpleBufferQueue queue = {SL_DATALOCATOR_ANDROIDSIMPLEBUFFERQUEUE, kBufferCount};
  SLAndroidDataFormat_PCM_EX format = {};
  format.formatType = SL_ANDROID_DATAFORMAT_PCM_EX;
  format.numChannels = kChannels;
  format.sampleRate = kSampleRate * 1000;  // milliHertz
  format.bitsPerSample = 32;
  format.containerSize = 32;
  format.channelMask = SL_SPEAKER_FRONT_LEFT | SL_SPEAKER_FRONT_RIGHT;
  format.endianness = SL_BYTEORDER_LITTLEENDIAN;
  format.representation = SL_ANDROID_PCM_REPRESENTATION_FLOAT;
  SLDataSource source = {&queue, &format};
  SLDataLocator_OutputMix mix = {SL_DATALOCATOR_OUTPUTMIX, gMix};
  SLDataSink sink = {&mix, nullptr};

  const SLInterfaceID ids[] = {SL_IID_ANDROIDSIMPLEBUFFERQUEUE};
  const SLboolean req[] = {SL_BOOLEAN_TRUE};
  if ((*engineItf)->CreateAudioPlayer(engineItf, &gPlayer, &source, &sink, 1, ids, req) != SL_RESULT_SUCCESS) return false;
  if ((*gPlayer)->Realize(gPlayer, SL_BOOLEAN_FALSE) != SL_RESULT_SUCCESS) return false;
  if ((*gPlayer)->GetInterface(gPlayer, SL_IID_PLAY, &gPlay) != SL_RESULT_SUCCESS) return false;
  if ((*gPlayer)->GetInterface(gPlayer, SL_IID_ANDROIDSIMPLEBUFFERQUEUE, &gQueue) != SL_RESULT_SUCCESS) return false;
  if ((*gQueue)->RegisterCallback(gQueue, onBuffer, nullptr) != SL_RESULT_SUCCESS) return false;

  gNext = 0;
  for (int i = 0; i < kBufferCount; ++i) fillAndEnqueue();
  return (*gPlay)->SetPlayState(gPlay, SL_PLAYSTATE_PLAYING) == SL_RESULT_SUCCESS;
}

}  // namespace

extern "C" int aura_audio_open(void* engine) {
  aura_audio_close(gEngine.load());
  std::lock_guard<std::mutex> lock(gMutex);
  gEngine.store(engine, std::memory_order_release);
  if (openLocked()) return 1;
  destroyLocked();
  gEngine.store(nullptr, std::memory_order_release);
  return 0;
}

extern "C" void aura_audio_close(void* engine) {
  if (engine == nullptr || engine != gEngine.load()) return;
  std::lock_guard<std::mutex> lock(gMutex);
  gEngine.store(nullptr, std::memory_order_release);
  destroyLocked();
}

#endif  // __ANDROID__
