// Air-gap audit (CLAUDE.md section 1): no network packages, no network code,
// no INTERNET permission. Run from the package root (flutter test default).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final RegExp _depLine = RegExp(r'^  ([A-Za-z0-9_]+)\s*:');

/// Names of every package declared under dependencies / dev_dependencies /
/// dependency_overrides.
Set<String> _declaredPackages(String pubspec) {
  final names = <String>{};
  var inDeps = false;
  for (final raw in pubspec.split('\n')) {
    final line = raw.replaceAll('\r', '');
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
    if (!line.startsWith(' ')) {
      inDeps = line.startsWith('dependencies:') ||
          line.startsWith('dev_dependencies:') ||
          line.startsWith('dependency_overrides:');
      continue;
    }
    if (!inDeps) continue;
    final m = _depLine.firstMatch(line);
    if (m != null) names.add(m.group(1)!);
  }
  return names;
}

bool _isForbiddenPackage(String name) {
  const exact = {
    'http',
    'dio',
    'webview_flutter',
    'google_fonts',
    'http_parser',
    'retrofit',
    'chopper',
    'web_socket_channel',
    'socket_io_client',
    'url_launcher',
    'connectivity_plus',
    'sentry',
    'sentry_flutter',
    'mixpanel_flutter',
    'amplitude_flutter',
    'flutter_inappwebview',
  };
  return exact.contains(name) ||
      name.startsWith('firebase') ||
      name.startsWith('cloud_firestore') ||
      name.contains('analytics') ||
      name.contains('crashlytics') ||
      name.contains('webview');
}

/// Removes comments while leaving string literals (and their URLs) intact.
String _stripComments(String src) {
  final out = StringBuffer();
  var i = 0;
  final n = src.length;
  while (i < n) {
    final c = src[i];
    final next = i + 1 < n ? src[i + 1] : '';
    if (c == '/' && next == '/') {
      while (i < n && src[i] != '\n') {
        i++;
      }
      continue;
    }
    if (c == '/' && next == '*') {
      i += 2;
      while (i + 1 < n && !(src[i] == '*' && src[i + 1] == '/')) {
        if (src[i] == '\n') out.write('\n');
        i++;
      }
      i += 2;
      continue;
    }
    if (c == "'" || c == '"') {
      final triple = i + 2 < n && src[i + 1] == c && src[i + 2] == c;
      final raw = i > 0 && src[i - 1] == 'r';
      final q = triple ? c * 3 : c;
      out.write(q);
      i += q.length;
      while (i < n) {
        if (!raw && src[i] == r'\' && i + 1 < n) {
          out.write(src[i]);
          out.write(src[i + 1]);
          i += 2;
          continue;
        }
        if (src.startsWith(q, i)) {
          out.write(q);
          i += q.length;
          break;
        }
        if (!triple && src[i] == '\n') break;
        out.write(src[i]);
        i++;
      }
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

List<File> _dartFiles(Directory dir) => dir
    .listSync(recursive: true, followLinks: false)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));

void main() {
  test('pubspec.yaml declares no network / analytics / remote-font package',
      () {
    final f = File('pubspec.yaml');
    expect(f.existsSync(), isTrue, reason: 'run tests from the package root');
    final declared = _declaredPackages(f.readAsStringSync());
    expect(declared, contains('flutter'));
    final bad = declared.where(_isForbiddenPackage).toList();
    expect(bad, isEmpty, reason: 'forbidden packages: $bad');
  });

  test('pubspec.yaml dependencies are within the allow-list', () {
    const allowed = {
      'flutter',
      'flutter_test',
      'flutter_lints',
      'sqflite',
      'path',
      'path_provider',
      'ffi',
      // Browser bindings (localStorage, Web Audio) for the PWA build; no networking.
      'web',
      'sqflite_common_ffi',
    };
    final declared = _declaredPackages(File('pubspec.yaml').readAsStringSync());
    expect(declared.difference(allowed), isEmpty);
  });

  final lib = Directory('lib');

  test('lib/ exists and contains Dart sources', () {
    expect(lib.existsSync(), isTrue);
    expect(_dartFiles(lib), isNotEmpty);
  });

  test('lib/ has no HttpClient / Socket / WebSocket / HttpServer usage', () {
    final pattern = RegExp(
        r'\b(HttpClient|HttpServer|HttpOverrides|Socket|RawSocket|ServerSocket|'
        r'RawServerSocket|WebSocket|RawDatagramSocket|SecureSocket)\b');
    final hits = <String>[];
    for (final f in _dartFiles(lib)) {
      final code = _stripComments(f.readAsStringSync());
      final lines = code.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (pattern.hasMatch(lines[i])) {
          hits.add('${f.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test(
      'lib/ imports no network package and no dart:html / dart:js / dart:js_util',
      () {
    final pattern = RegExp(
        r'''import\s+['"](package:(http|dio|webview_flutter|google_fonts|'''
        r'''firebase[a-z_]*|[a-z_]*analytics[a-z_]*|web_socket_channel|'''
        r'''url_launcher)/|dart:html|dart:js(?!_interop)|dart:js_util)''');
    final hits = <String>[];
    for (final f in _dartFiles(lib)) {
      final code = _stripComments(f.readAsStringSync());
      for (final m in pattern.allMatches(code)) {
        hits.add('${f.path}: ${m.group(0)}');
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test(
      'lib/ uses no browser networking API (fetch, XMLHttpRequest, beacons, ...)',
      () {
    final pattern = RegExp(
        r'(\.fetch\s*\(|\bXMLHttpRequest\b|\bEventSource\b|\bsendBeacon\b|'
        r'\bimportScripts\b|\bRTCPeerConnection\b|\bHttpRequest\b)');
    final hits = <String>[];
    for (final f in _dartFiles(lib)) {
      final lines = _stripComments(f.readAsStringSync()).split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (pattern.hasMatch(lines[i])) {
          hits.add('${f.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test(
      'web/ shell files reference no external host (no CDN, fonts or analytics)',
      () {
    final web = Directory('web');
    if (!web.existsSync()) return;
    final hits = <String>[];
    for (final f in web.listSync().whereType<File>()) {
      if (!(f.path.endsWith('.html') ||
          f.path.endsWith('.json') ||
          f.path.endsWith('.js'))) {
        continue;
      }
      final text = f.readAsStringSync();
      for (final m in RegExp(r'https?://[^\s"<>)]+').allMatches(text)) {
        hits.add('${f.path}: ${m.group(0)}');
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test('lib/ code contains no http:// or https:// URL', () {
    final pattern = RegExp(r'https?://', caseSensitive: false);
    final hits = <String>[];
    for (final f in _dartFiles(lib)) {
      final lines = _stripComments(f.readAsStringSync()).split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (pattern.hasMatch(lines[i])) {
          hits.add('${f.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test('AndroidManifest.xml (if present) does not request INTERNET', () {
    final f = File('android/app/src/main/AndroidManifest.xml');
    if (!f.existsSync()) {
      // Platform folder not generated yet; nothing to audit.
      return;
    }
    final xml = f
        .readAsStringSync()
        .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
    expect(xml.contains('android.permission.INTERNET'), isFalse);
    expect(xml.contains('ACCESS_NETWORK_STATE'), isFalse);
  });
}
