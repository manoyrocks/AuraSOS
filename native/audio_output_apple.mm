// AudioQueue backend shared by iOS and macOS. On iOS the audio session is set to
// Playback so a calming session keeps sounding with the silent switch on, and the queue
// is restarted after phone calls / Siri interruptions.
#import <Foundation/Foundation.h>
#import <TargetConditionals.h>
#import <AudioToolbox/AudioToolbox.h>
#if TARGET_OS_IOS
#import <AVFoundation/AVFoundation.h>
#endif

#include <atomic>
#include <cstring>

#include "audio_output.h"
#include "dsp_engine.h"

namespace {

constexpr int kSampleRate = 48000;
constexpr UInt32 kBuffers = 3;
constexpr UInt32 kFramesPerBuffer = 2048;  // ~43 ms; the app never needs low latency
constexpr UInt32 kBytesPerFrame = 2 * sizeof(float);

std::atomic<void*> gEngine{nullptr};
AudioQueueRef gQueue = nullptr;
id gInterruptionObserver = nil;

void onBuffer(void*, AudioQueueRef queue, AudioQueueBufferRef buffer) {
  const UInt32 frames = buffer->mAudioDataBytesCapacity / kBytesPerFrame;
  void* engine = gEngine.load(std::memory_order_acquire);
  float* out = static_cast<float*>(buffer->mAudioData);
  if (engine == nullptr) {
    std::memset(out, 0, frames * kBytesPerFrame);
  } else {
    aura_dsp_render(engine, out, static_cast<int>(frames));
  }
  buffer->mAudioDataByteSize = frames * kBytesPerFrame;
  AudioQueueEnqueueBuffer(queue, buffer, 0, nullptr);
}

void teardown() {
#if TARGET_OS_IOS
  if (gInterruptionObserver != nil) {
    [[NSNotificationCenter defaultCenter] removeObserver:gInterruptionObserver];
    gInterruptionObserver = nil;
  }
#endif
  if (gQueue != nullptr) {
    AudioQueueStop(gQueue, true);
    AudioQueueDispose(gQueue, true);
    gQueue = nullptr;
  }
}

}  // namespace

extern "C" int aura_audio_open(void* engine) {
  teardown();
  gEngine.store(engine, std::memory_order_release);

#if TARGET_OS_IOS
  AVAudioSession* session = [AVAudioSession sharedInstance];
  NSError* error = nil;
  [session setCategory:AVAudioSessionCategoryPlayback error:&error];
  [session setPreferredSampleRate:kSampleRate error:nil];
  [session setActive:YES error:nil];
#endif

  AudioStreamBasicDescription format = {};
  format.mSampleRate = kSampleRate;
  format.mFormatID = kAudioFormatLinearPCM;
  format.mFormatFlags = kLinearPCMFormatFlagIsFloat | kLinearPCMFormatFlagIsPacked;
  format.mBitsPerChannel = 32;
  format.mChannelsPerFrame = 2;
  format.mBytesPerFrame = kBytesPerFrame;
  format.mFramesPerPacket = 1;
  format.mBytesPerPacket = kBytesPerFrame;

  if (AudioQueueNewOutput(&format, onBuffer, nullptr, nullptr, nullptr, 0, &gQueue) != noErr) {
    gQueue = nullptr;
    gEngine.store(nullptr, std::memory_order_release);
    return 0;
  }
  for (UInt32 i = 0; i < kBuffers; ++i) {
    AudioQueueBufferRef buffer = nullptr;
    if (AudioQueueAllocateBuffer(gQueue, kFramesPerBuffer * kBytesPerFrame, &buffer) != noErr) {
      teardown();
      gEngine.store(nullptr, std::memory_order_release);
      return 0;
    }
    onBuffer(nullptr, gQueue, buffer);
  }
  if (AudioQueueStart(gQueue, nullptr) != noErr) {
    teardown();
    gEngine.store(nullptr, std::memory_order_release);
    return 0;
  }

#if TARGET_OS_IOS
  gInterruptionObserver = [[NSNotificationCenter defaultCenter]
      addObserverForName:AVAudioSessionInterruptionNotification
                  object:nil
                   queue:[NSOperationQueue mainQueue]
              usingBlock:^(NSNotification* note) {
                NSNumber* type = note.userInfo[AVAudioSessionInterruptionTypeKey];
                if (type.unsignedIntegerValue == AVAudioSessionInterruptionTypeEnded &&
                    gQueue != nullptr) {
                  [[AVAudioSession sharedInstance] setActive:YES error:nil];
                  AudioQueueStart(gQueue, nullptr);
                }
              }];
#endif
  return 1;
}

extern "C" void aura_audio_close(void* engine) {
  if (engine == nullptr || engine != gEngine.load()) return;
  teardown();
  gEngine.store(nullptr, std::memory_order_release);
}
