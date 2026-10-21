import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/audio/voice_weave.dart';
import '../core/audio/wav_codec.dart';

/// Offline store for the caregiver's processed 48 kHz mono phrases (`voice_0.wav`..`voice_3.wav`).
class VoiceLibrary {
  VoiceLibrary({Directory? root}) : _root = root;

  final Directory? _root;

  Future<Directory> _dir() async {
    final Directory base = _root ??
        Directory(
            p.join((await getApplicationDocumentsDirectory()).path, 'voice'));
    if (!await base.exists()) await base.create(recursive: true);
    return base;
  }

  Future<File> _file(int slot) async {
    _check(slot);
    return File(p.join((await _dir()).path, 'voice_$slot.wav'));
  }

  static void _check(int slot) {
    if (slot < 0 || slot >= VoiceWeaveEngine.maxSlots) {
      throw RangeError.range(slot, 0, VoiceWeaveEngine.maxSlots - 1, 'slot');
    }
  }

  Future<List<Float32List?>> loadAll() async {
    final List<Float32List?> out = <Float32List?>[];
    for (var i = 0; i < VoiceWeaveEngine.maxSlots; i++) {
      out.add(await load(i));
    }
    return out;
  }

  /// Null for an empty slot or an unreadable / corrupt file.
  Future<Float32List?> load(int slot) async {
    final File f = await _file(slot);
    try {
      if (!await f.exists()) return null;
      final WavData wav = decodeWav16Mono(await f.readAsBytes());
      final Float32List s = wav.sampleRate == 48000
          ? wav.samples
          : resampleTo48k(wav.samples, wav.sampleRate);
      return s.length > VoiceWeaveEngine.maxFrames
          ? Float32List.sublistView(s, 0, VoiceWeaveEngine.maxFrames)
          : s;
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> saveProcessed(int slot, Float32List mono48k) async {
    final File f = await _file(slot);
    if (mono48k.isEmpty) {
      await delete(slot);
      return;
    }
    final Float32List s = mono48k.length > VoiceWeaveEngine.maxFrames
        ? Float32List.sublistView(mono48k, 0, VoiceWeaveEngine.maxFrames)
        : mono48k;
    final File tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(encodeWav16Mono(s, 48000), flush: true);
    await tmp.rename(f.path);
  }

  Future<void> delete(int slot) async {
    final File f = await _file(slot);
    if (await f.exists()) await f.delete();
  }
}
