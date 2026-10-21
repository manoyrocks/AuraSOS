#include "audio_output.h"
#include "dsp_engine.h"

extern "C" const void* const* aura_keep_symbols(void) {
  static const void* const table[] = {
      reinterpret_cast<const void*>(&aura_dsp_create),
      reinterpret_cast<const void*>(&aura_dsp_destroy),
      reinterpret_cast<const void*>(&aura_dsp_start),
      reinterpret_cast<const void*>(&aura_dsp_stop),
      reinterpret_cast<const void*>(&aura_dsp_switch_preset),
      reinterpret_cast<const void*>(&aura_dsp_apply_iso),
      reinterpret_cast<const void*>(&aura_dsp_set_profile_limits),
      reinterpret_cast<const void*>(&aura_dsp_trigger_note),
      reinterpret_cast<const void*>(&aura_dsp_render),
      reinterpret_cast<const void*>(&aura_dsp_load_voice),
      reinterpret_cast<const void*>(&aura_dsp_clear_voice),
      reinterpret_cast<const void*>(&aura_dsp_set_voice_weave),
      reinterpret_cast<const void*>(&aura_audio_open),
      reinterpret_cast<const void*>(&aura_audio_close),
      nullptr,
  };
  return table;
}
