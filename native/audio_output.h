// Platform speaker output for the AuraSOS DSP engine. The platform audio thread pulls
// audio straight from aura_dsp_render (48 kHz, stereo float32), so Dart never sits on the
// real-time path.
#pragma once

#if defined(_WIN32)
#define AURA_OUT_API __declspec(dllexport)
#else
#define AURA_OUT_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Opens the default output and starts pulling from [engine]. Returns 1 on success, 0 on
// failure (the engine then stays usable for offline rendering). Replaces any open output.
AURA_OUT_API int aura_audio_open(void* engine);

// Stops and closes the output if it is currently bound to [engine].
AURA_OUT_API void aura_audio_close(void* engine);

// Returns the address of every exported entry point so a linker running dead-code
// stripping (iOS release builds) keeps them for dlsym / DynamicLibrary.process().
AURA_OUT_API const void* const* aura_keep_symbols(void);

#ifdef __cplusplus
}
#endif
