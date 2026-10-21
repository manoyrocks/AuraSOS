import 'dart:typed_data';

/// Optional capability of an [AudioEngine]: gently weaves caregiver-recorded phrases
/// ("You are safe, take a deep breath") into the running soundscape. Contract file.
///
/// Phrases are mono float32 at 48 000 Hz, at most [maxFrames] long, already de-essed and
/// normalised by `FamiliarVoiceProcessor`. Load phrases while no session is running.
abstract class VoiceWeaveEngine {
  static const int maxSlots = 4;
  static const int maxFrames = 288000; // 6 s

  /// Stores [mono48k] in [slot] (0..maxSlots-1). Longer phrases are truncated.
  void loadVoice(int slot, Float32List mono48k);

  /// Empties [slot].
  void clearVoice(int slot);

  /// [gain] is linear 0..0.5 applied before the master filter, fades and limiter;
  /// [intervalSec] (10..600) is the pause between phrases while a session is audible.
  void setVoiceWeave(
      {required bool enabled, double gain = 0.12, double intervalSec = 45});
}
