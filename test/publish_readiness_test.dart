import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aurasync/core/app_info.dart';
import 'package:aurasync/ui/launch_intent.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards what must be true before the PWA is published: a strict, consistent CSP, no inline
/// scripts, a self-contained privacy page, shortcuts the app understands, and hosting configs
/// that carry the same policy.
void main() {
  final index = File('web/index.html').readAsStringSync();
  final headers = File('web/_headers').readAsStringSync();

  String cspFrom(String text) => RegExp(r"Content-Security-Policy: (.+)")
      .firstMatch(text)!
      .group(1)!
      .trim();

  final headerCsp = cspFrom(headers);
  final metaCsp =
      RegExp(r'http-equiv="Content-Security-Policy" content="([^"]+)"')
          .firstMatch(index)!
          .group(1)!;

  group('Content-Security-Policy', () {
    test('the <meta> policy equals the header policy (minus frame-ancestors)',
        () {
      expect(headerCsp.replaceAll("; frame-ancestors 'none'", ''), metaCsp);
      expect(headerCsp, contains("frame-ancestors 'none'"));
    });

    test('is strict: same-origin only, no inline script, no eval, no wildcards',
        () {
      for (final d in [
        "default-src 'self'",
        "script-src 'self' 'wasm-unsafe-eval'",
        "connect-src 'self'",
        "object-src 'none'",
        "base-uri 'self'",
        "form-action 'none'",
      ]) {
        expect(metaCsp, contains(d), reason: d);
      }
      final scripts =
          RegExp(r'script-src ([^;]+)').firstMatch(metaCsp)!.group(1)!;
      expect(scripts, isNot(contains('unsafe-inline')));
      expect(metaCsp.replaceAll("'wasm-unsafe-eval'", ''),
          isNot(contains('unsafe-eval')));
      expect(metaCsp, isNot(contains('*')));
      expect(RegExp(r'https?:').hasMatch(metaCsp), isFalse);
    });

    test('index.html has no inline script or style block', () {
      for (final m in RegExp(r'<script\b([^>]*)>').allMatches(index)) {
        expect(m.group(1), contains('src='),
            reason: 'inline <script> would violate the CSP');
      }
      expect(index, isNot(contains('<style')));
      expect(index, isNot(contains(' onclick=')));
    });

    test('security headers are all present', () {
      for (final h in [
        'X-Content-Type-Options: nosniff',
        'X-Frame-Options: DENY',
        'Referrer-Policy: no-referrer',
        'Permissions-Policy:',
        'Cross-Origin-Opener-Policy: same-origin',
        'Cache-Control: no-cache',
      ]) {
        expect(headers, contains(h), reason: h);
      }
      expect(headers, contains('microphone=()'));
    });
  });

  group('hosting configs carry the same policy', () {
    for (final f in [
      'deploy/nginx.conf',
      'deploy/apache.htaccess',
      'deploy/vercel.json',
      'deploy/firebase.json',
    ]) {
      test(f, () {
        final text = File(f).readAsStringSync();
        final csp = f.endsWith('.json')
            ? text.contains(jsonEncode(headerCsp)
                .substring(1, jsonEncode(headerCsp).length - 1))
            : text.contains(headerCsp);
        expect(csp, isTrue, reason: '$f has a different CSP than web/_headers');
        expect(text, contains('nosniff'));
        expect(text, contains('no-cache'));
      });
    }

    test('JSON configs are valid JSON', () {
      for (final f in ['deploy/vercel.json', 'deploy/firebase.json']) {
        expect(() => jsonDecode(File(f).readAsStringSync()), returnsNormally,
            reason: f);
      }
    });

    test('nginx serves wasm with the right type', () {
      expect(File('deploy/nginx.conf').readAsStringSync(),
          contains('application/wasm'));
    });

    test(
        'the GitHub Pages workflow sets a base href, gates on tests, and matches its template',
        () {
      final y = File('deploy/github-pages.yml').readAsStringSync();
      expect(y, contains('--base-href'));
      expect(y, contains('flutter test'));
      expect(y, contains('flutter analyze'));
      expect(y, contains('tool/build_web.sh'));
      expect(y, contains('actions/deploy-pages'));
      expect(y, contains('flutter-version: 3.47.7'),
          reason: 'pin the Flutter version for reproducible builds');
      final live = File('.github/workflows/pages.yml');
      expect(live.existsSync(), isTrue);
      expect(live.readAsStringSync(), y,
          reason: 'deploy/github-pages.yml and the live workflow drifted');
    });
  });

  group('privacy page', () {
    final page = File('web/privacy.html').readAsStringSync();

    test('is self-contained: no scripts, no external URLs', () {
      expect(page, isNot(contains('<script')));
      expect(RegExp(r'https?://').hasMatch(page), isFalse);
      expect(File('web/privacy.css').existsSync(), isTrue);
    });

    test('states the key promises', () {
      final text = page.toLowerCase();
      for (final phrase in [
        'no accounts',
        'no ads',
        'analytics',
        'offline',
        'deleting your data',
        'not medical'
      ]) {
        expect(text, contains(phrase), reason: phrase);
      }
    });
  });

  group('manifest shortcuts', () {
    final manifest = jsonDecode(File('web/manifest.json').readAsStringSync())
        as Map<String, dynamic>;
    final shortcuts =
        (manifest['shortcuts'] as List).cast<Map<String, dynamic>>();

    test('there is one per mode and each icon exists', () {
      expect(shortcuts, hasLength(4));
      for (final s in shortcuts) {
        expect(s['name'], isNotEmpty);
        for (final icon in (s['icons'] as List).cast<Map<String, dynamic>>()) {
          expect(File('web/${icon['src']}').existsSync(), isTrue);
        }
      }
    });

    test('every shortcut url is understood by the app', () {
      final modes = <LaunchMode>{};
      for (final s in shortcuts) {
        final uri = Uri.parse(s['url'] as String);
        final mode = launchModeFrom(uri.queryParameters['mode']);
        expect(mode, isNotNull, reason: s['url'] as String);
        modes.add(mode!);
      }
      expect(modes, LaunchMode.values.toSet());
    });
  });

  group('launch mode parsing', () {
    test('known values, case-insensitive and trimmed', () {
      expect(launchModeFrom('sos'), LaunchMode.sos);
      expect(launchModeFrom(' FOCUS '), LaunchMode.focus);
      expect(launchModeFrom('Calm'), LaunchMode.calm);
      expect(launchModeFrom('deep'), LaunchMode.deep);
    });

    test('anything else shows the normal home screen', () {
      for (final v in [null, '', 'bogus', 'sos;drop', '<script>', 'focus2']) {
        expect(launchModeFrom(v), isNull, reason: '$v');
      }
    });
  });

  group('files a browser requests on its own', () {
    test('favicon.ico is a real ICO wrapping a PNG', () {
      final b = File('web/favicon.ico').readAsBytesSync();
      final d = ByteData.sublistView(Uint8List.fromList(b));
      expect(d.getUint16(0, Endian.little), 0);
      expect(d.getUint16(2, Endian.little), 1, reason: 'icon type');
      expect(d.getUint16(4, Endian.little), 1, reason: 'one image');
      final offset = d.getUint32(18, Endian.little);
      expect(b.sublist(offset, offset + 4), [0x89, 0x50, 0x4E, 0x47]);
    });

    test('robots.txt allows indexing', () {
      expect(File('web/robots.txt').readAsStringSync(), contains('Allow: /'));
    });
  });

  group('version', () {
    test('the default app version matches pubspec.yaml', () {
      final v = RegExp(r'^version: *(.+)$', multiLine: true)
          .firstMatch(File('pubspec.yaml').readAsStringSync())!
          .group(1)!
          .trim();
      expect(kAppVersion, v,
          reason: 'update lib/core/app_info.dart when bumping the version');
    });

    test('the web build script passes the pubspec version into the app', () {
      final script = File('tool/build_web.sh').readAsStringSync();
      expect(script, contains('--dart-define=APP_VERSION'));
      expect(script, contains('check_web_build.py'));
      expect(script, contains('--base-href'));
    });
  });
}
