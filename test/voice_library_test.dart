import 'dart:io';
import 'dart:typed_data';

import 'package:aurasync/core/audio/voice_weave.dart';
import 'package:aurasync/data/voice_library.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late VoiceLibrary lib;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('voice_lib_test');
    lib = VoiceLibrary(root: Directory('${dir.path}/voice'));
  });

  tearDown(() async => dir.delete(recursive: true));

  Float32List ramp(int n) => Float32List.fromList(List<double>.generate(n, (i) => (i % 100) / 200 - 0.25));

  test('empty library has four null slots', () async {
    final all = await lib.loadAll();
    expect(all.length, VoiceWeaveEngine.maxSlots);
    expect(all.every((e) => e == null), isTrue);
  });

  test('save / load round-trips and uses the voice_N.wav names', () async {
    final src = ramp(4800);
    await lib.saveProcessed(2, src);
    expect(File('${dir.path}/voice/voice_2.wav').existsSync(), isTrue);
    final back = (await lib.load(2))!;
    expect(back.length, src.length);
    for (var i = 0; i < src.length; i++) {
      expect(back[i], closeTo(src[i], 1e-4));
    }
    final all = await lib.loadAll();
    expect(all[2], isNotNull);
    expect(all[0], isNull);
  });

  test('over-long phrases are truncated to maxFrames', () async {
    await lib.saveProcessed(0, ramp(VoiceWeaveEngine.maxFrames + 5000));
    expect((await lib.load(0))!.length, VoiceWeaveEngine.maxFrames);
  });

  test('slot bounds are enforced', () async {
    expect(() => lib.saveProcessed(-1, ramp(10)), throwsRangeError);
    expect(() => lib.saveProcessed(VoiceWeaveEngine.maxSlots, ramp(10)), throwsRangeError);
    expect(() => lib.load(4), throwsRangeError);
    expect(() => lib.delete(-1), throwsRangeError);
  });

  test('delete empties the slot and is idempotent', () async {
    await lib.saveProcessed(1, ramp(100));
    await lib.delete(1);
    expect(await lib.load(1), isNull);
    await lib.delete(1);
  });

  test('a corrupt file reads as an empty slot', () async {
    await lib.saveProcessed(3, ramp(100));
    await File('${dir.path}/voice/voice_3.wav').writeAsBytes([1, 2, 3]);
    expect(await lib.load(3), isNull);
  });
}
