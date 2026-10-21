import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Guards the installable / offline shell of the web build (web/ sources, not build output).
void main() {
  final manifest = jsonDecode(File('web/manifest.json').readAsStringSync())
      as Map<String, dynamic>;
  final index = File('web/index.html').readAsStringSync();

  test('manifest describes an installable standalone app', () {
    expect(manifest['name'], 'AuraSOS');
    expect(manifest['short_name'], isNotEmpty);
    expect(manifest['display'], 'standalone');
    expect(manifest['start_url'], isNotNull);
    expect(manifest['orientation'], 'any',
        reason: 'must work on phones and tablets, both ways');
    expect(manifest['background_color'], '#0B1220');
    expect(manifest['theme_color'], '#0B1220');
  });

  test('manifest icons exist, are real PNGs and include maskable variants', () {
    final icons = (manifest['icons'] as List).cast<Map<String, dynamic>>();
    expect(icons.map((i) => i['sizes']), containsAll(['192x192', '512x512']));
    expect(icons.where((i) => i['purpose'] == 'maskable'), isNotEmpty);
    for (final i in icons) {
      final f = File('web/${i['src']}');
      expect(f.existsSync(), isTrue, reason: '${i['src']} missing');
      final bytes = f.readAsBytesSync();
      expect(bytes.sublist(0, 8),
          [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      final size = int.parse((i['sizes'] as String).split('x').first);
      final w = ByteData.sublistView(bytes, 16, 20).getUint32(0);
      expect(w, size, reason: '${i['src']} is not ${i['sizes']}');
    }
  });

  test('index.html is mobile-ready and wires the shell files', () {
    expect(index, contains('name="viewport"'));
    expect(index, contains('viewport-fit=cover'));
    expect(index, contains('rel="manifest"'));
    expect(index, contains('apple-mobile-web-app-capable'));
    expect(index, contains('rel="apple-touch-icon"'));
    expect(index, contains('href="splash.css"'));
    expect(index, contains('src="pwa_init.js"'));
    expect(index, isNot(contains('flutter_service_worker')));
  });

  test('the shell files do the registering, splash and anti-scroll work', () {
    final init = File('web/pwa_init.js').readAsStringSync();
    expect(init, contains("register('aura_sw.js')"));
    expect(init, contains('flutter-first-frame'));
    final css = File('web/splash.css').readAsStringSync();
    expect(css, contains('overscroll-behavior: none'),
        reason: 'a child swiping must not pull-to-refresh');
    expect(css, contains('user-select: none'));
    expect(css, contains('prefers-reduced-motion'));
  });

  test("Flutter's deprecated self-unregistering worker is not registered", () {
    final bootstrap = File('web/flutter_bootstrap.js').readAsStringSync();
    expect(bootstrap, contains('{{flutter_js}}'));
    expect(bootstrap, contains('{{flutter_build_config}}'));
    expect(bootstrap, isNot(contains('serviceWorkerSettings')));
  });

  test(
      'service worker source only handles same-origin GETs and is stamped at build',
      () {
    final sw = File('web/aura_sw.js').readAsStringSync();
    expect(sw, contains('__AURA_VERSION__'));
    expect(sw, contains('__AURA_FILES__'));
    expect(sw, contains("req.method !== 'GET'"));
    expect(sw, contains('url.origin !== self.location.origin'));
    expect(sw, isNot(contains('skipWaiting')),
        reason:
            'a new version must wait so a running session is never swapped');
    expect(RegExp(r'https?://').hasMatch(sw), isFalse);
  });

  test('build script uses bundled web resources (no CDN)', () {
    final script = File('tool/build_web.sh').readAsStringSync();
    expect(script, contains('--no-web-resources-cdn'));
  });
}
