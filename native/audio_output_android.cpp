// AAudio backend (Android API 26+). Shared mode, float stereo, power-saving: the app's
// slow 4 s fades never need low latency, and larger buffers avoid underruns.
#if defined(__ANDROID__)

#include <aaudio/AAudio.h>

#include <atomic>
#include <cstring>
#include <mutex>
#include <thread>

#include "audio_output.h"
#include "dsp_engine.h"

namespace {

constexpr int kSampleRate = 48000;
constexpr int kChannels = 2;

std::atomic<void*> gEngine{nullptr};
std::atomic<bool> gActive{false};
std::mutex gStreamMutex;       // guards gStream
AAudioStream* gStream = nullptr;
std::mutex gRestartMutex;      // guards gRestarter
std::thread gRestarter;

aaudio_data_callback_result_t onData(AAudioStream*, void*, void* audio, int32_t frames) {
  void* engine = gEngine.load(std::memory_order_acquire);
  if (engine == nullptr) {
    std::memset(audio, 0, sizeof(float) * kChannels * static_cast<size_t>(frames));
  } else {
    aura_dsp_render(engine, static_cast<float*>(audio), frames);
  }
  return AAUDIO_CALLBACK_RESULT_CONTINUE;
}

void closeStreamLocked() {
  if (gStream != nullptr) {
    AAudioStream_requestStop(gStream);
    AAudioStream_close(gStream);
    gStream = nullptr;
  }
}

bool openStreamLocked();

// Runs off the audio thread: AAudio forbids closing a stream from its own callbacks.
void restartAfterError() {
  std::lock_guard<std::mutex> lock(gStreamMutex);
  if (!gActive.load()) return;
  closeStreamLocked();
  openStreamLocked();
}

void onError(AAudioStream*, void*, aaudio_result_t error) {
  if (error != AAUDIO_ERROR_DISCONNECTED || !gActive.load()) return;
  std::lock_guard<std::mutex> lock(gRestartMutex);
  if (gRestarter.joinable()) gRestarter.join();
  gRestarter = std::thread(restartAfterError);
}

bool openStreamLocked() {
  AAudioStreamBuilder* builder = nullptr;
  if (AAudio_createStreamBuilder(&builder) != AAUDIO_OK) return false;
  AAudioStreamBuilder_setDirection(builder, AAUDIO_DIRECTION_OUTPUT);
  AAudioStreamBuilder_setFormat(builder, AAUDIO_FORMAT_PCM_FLOAT);
  AAudioStreamBuilder_setChannelCount(builder, kChannels);
  AAudioStreamBuilder_setSampleRate(builder, kSampleRate);
  AAudioStreamBuilder_setSharingMode(builder, AAUDIO_SHARING_MODE_SHARED);
  AAudioStreamBuilder_setPerformanceMode(builder, AAUDIO_PERFORMANCE_MODE_POWER_SAVING);
  AAudioStreamBuilder_setDataCallback(builder, onData, nullptr);
  AAudioStreamBuilder_setErrorCallback(builder, onError, nullptr);

  AAudioStream* stream = nullptr;
  const aaudio_result_t opened = AAudioStreamBuilder_openStream(builder, &stream);
  AAudioStreamBuilder_delete(builder);
  if (opened != AAUDIO_OK || stream == nullptr) return false;

  const int32_t burst = AAudioStream_getFramesPerBurst(stream);
  if (burst > 0) AAudioStream_setBufferSizeInFrames(stream, burst * 4);

  if (AAudioStream_requestStart(stream) != AAUDIO_OK) {
    AAudioStream_close(stream);
    return false;
  }
  gStream = stream;
  return true;
}

}  // namespace

extern "C" int aura_audio_open(void* engine) {
  aura_audio_close(gEngine.load());
  std::lock_guard<std::mutex> lock(gStreamMutex);
  gEngine.store(engine, std::memory_order_release);
  gActive.store(true);
  if (openStreamLocked()) return 1;
  gActive.store(false);
  gEngine.store(nullptr, std::memory_order_release);
  return 0;
}

extern "C" void aura_audio_close(void* engine) {
  if (engine == nullptr || engine != gEngine.load()) return;
  gActive.store(false);
  {
    std::lock_guard<std::mutex> lock(gRestartMutex);
    if (gRestarter.joinable()) gRestarter.join();
  }
  std::lock_guard<std::mutex> lock(gStreamMutex);
  closeStreamLocked();
  gEngine.store(nullptr, std::memory_order_release);
}

#endif  // __ANDROID__
