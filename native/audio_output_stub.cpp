// Desktop/Linux/Windows have no speaker backend: the engine stays available for offline
// rendering and tests, and aura_audio_open reports that no output was opened.
#if !defined(__ANDROID__) && !defined(__APPLE__)

#include "audio_output.h"

extern "C" int aura_audio_open(void*) { return 0; }
extern "C" void aura_audio_close(void*) {}

#endif
