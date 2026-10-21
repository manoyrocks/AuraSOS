import 'dart:convert';
import 'dart:io';

import 'package:aurasync/core/audio/dsp_bridge.dart';
import 'package:aurasync/data/json_database.dart';
import 'package:aurasync/data/local_database.dart';
import 'package:aurasync/data/sensory_profile_repository.dart';
import 'package:aurasync/data/voice_library.dart';
import 'package:aurasync/ui/launch_intent.dart';
import 'package:aurasync/ui/screens/home_sos_screen.dart';
import 'package:aurasync/ui/screens/session_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Keeps the web, Android and iOS shells identical: the same icon artwork at every size each
/// platform needs, and the same four long-press menu entries.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ({int width, int height, int colorType}) png(String path) {
    final b = File(path).readAsBytesSync();
    expect(b.sublist(0, 8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
        reason: '$path is not a PNG');
    final d = ByteData.sublistView(Uint8List.fromList(b));
    return (width: d.getUint32(16), height: d.getUint32(20), colorType: b[25]);
  }

  const res = 'android/app/src/main/res';
  final strings = File('$res/values/strings.xml').readAsStringSync();
  final shortcuts = File('$res/xml/shortcuts.xml').readAsStringSync();
  final plist = File('ios/Runner/Info.plist').readAsStringSync();
  final manifest = jsonDecode(File('web/manifest.json').readAsStringSync())
      as Map<String, dynamic>;

  String unescape(String s) => s.replaceAll('&amp;', '&');
  String stringRes(String name) =>
      unescape(RegExp('<string name="$name">([^<]*)</string>')
          .firstMatch(strings)!
          .group(1)!);

  final androidShortcuts = RegExp(r'<shortcut\b(.*?)</shortcut>', dotAll: true)
      .allMatches(shortcuts)
      .map((m) => m.group(1)!)
      .toList();
  final iosItems = RegExp(
          r'<key>UIApplicationShortcutItemType</key>\s*<string>([^<]+)</string>\s*'
          r'<key>UIApplicationShortcutItemTitle</key>\s*<string>([^<]+)</string>\s*'
          r'<key>UIApplicationShortcutItemIconSymbolName</key>\s*<string>([^<]+)</string>')
      .allMatches(plist)
      .map((m) => (
            type: m.group(1)!,
            title: unescape(m.group(2)!),
            symbol: m.group(3)!
          ))
      .toList();
  final webShortcuts =
      (manifest['shortcuts'] as List).cast<Map<String, dynamic>>();

  group('iOS app icon', () {
    const iconset = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
    final images =
        ((jsonDecode(File('$iconset/Contents.json').readAsStringSync())
                as Map)['images'] as List)
            .cast<Map<String, dynamic>>();

    test('every size in Contents.json exists at the exact pixel size', () {
      expect(images, isNotEmpty);
      for (final img in images) {
        final base = double.parse((img['size'] as String).split('x').first);
        final scale = int.parse((img['scale'] as String).replaceAll('x', ''));
        final px = (base * scale).round();
        final info = png('$iconset/${img['filename']}');
        expect(info.width, px, reason: '${img['filename']} width');
        expect(info.height, px, reason: '${img['filename']} height');
      }
    });

    test(
        'the icons are opaque (App Store rejects an alpha channel) and the marketing icon is 1024',
        () {
      for (final img in images) {
        expect(png('$iconset/${img['filename']}').colorType, 2,
            reason: '${img['filename']} has alpha');
      }
      expect(images.any((i) => i['idiom'] == 'ios-marketing'), isTrue);
    });

    test('app name is AuraSOS', () {
      expect(
          plist,
          contains(
              '<key>CFBundleDisplayName</key>\n\t<string>AuraSOS</string>'));
    });
  });

  group('Android launcher icon', () {
    const legacy = {
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192
    };
    const layers = {
      'mdpi': 108,
      'hdpi': 162,
      'xhdpi': 216,
      'xxhdpi': 324,
      'xxxhdpi': 432
    };

    test('legacy launcher icon exists at every density', () {
      legacy.forEach((d, px) {
        final i = png('$res/mipmap-$d/ic_launcher.png');
        expect((i.width, i.height), (px, px), reason: d);
      });
    });

    test(
        'adaptive icon has transparent foreground and monochrome layers at every density',
        () {
      layers.forEach((d, px) {
        for (final name in [
          'ic_launcher_foreground',
          'ic_launcher_monochrome'
        ]) {
          final i = png('$res/drawable-$d/$name.png');
          expect((i.width, i.height), (px, px), reason: '$d $name');
          expect(i.colorType, 6, reason: '$name must have alpha');
        }
      });
    });

    test('adaptive XML wires background, foreground and the themed-icon layer',
        () {
      final x =
          File('$res/mipmap-anydpi-v26/ic_launcher.xml').readAsStringSync();
      expect(x, contains('<adaptive-icon'));
      for (final r in [
        'ic_launcher_background',
        'ic_launcher_foreground',
        'ic_launcher_monochrome'
      ]) {
        expect(x, contains('@drawable/$r'));
      }
      expect(File('$res/drawable/ic_launcher_background.xml').existsSync(),
          isTrue);
    });

    test('manifest uses the icon and the AuraSOS name', () {
      final m =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(m, contains('android:icon="@mipmap/ic_launcher"'));
      expect(m, contains('android:label="@string/app_name"'));
      expect(stringRes('app_name'), 'AuraSOS');
    });
  });

  group('long-press menu: identical on web, Android and iOS', () {
    test('four entries per platform', () {
      expect(webShortcuts, hasLength(4));
      expect(androidShortcuts, hasLength(4));
      expect(iosItems, hasLength(4));
    });

    test('same modes, same order', () {
      final web = webShortcuts
          .map((s) => Uri.parse(s['url'] as String).queryParameters['mode'])
          .toList();
      final android = androidShortcuts
          .map((s) => RegExp(r'aurasync\.mode"\s+android:value="(\w+)"')
              .firstMatch(s)!
              .group(1))
          .toList();
      final ios = iosItems.map((i) => i.type.split('.').last).toList();
      expect(android, web);
      expect(ios, web);
      expect(web.map(launchModeFrom).toSet(), LaunchMode.values.toSet());
    });

    test('same visible names', () {
      final web = webShortcuts.map((s) => s['name']).toList();
      final android = androidShortcuts
          .map((s) => stringRes(RegExp(r'shortcutLongLabel="@string/(\w+)"')
              .firstMatch(s)!
              .group(1)!))
          .toList();
      expect(android, web);
      expect(iosItems.map((i) => i.title).toList(), web);
    });

    test(
        'Android shortcuts have icons that exist, short labels, and target the main activity',
        () {
      for (final s in androidShortcuts) {
        final icon =
            RegExp(r'android:icon="@drawable/(\w+)"').firstMatch(s)!.group(1)!;
        expect(File('$res/drawable/$icon.xml').existsSync(), isTrue,
            reason: icon);
        final short = stringRes(RegExp(r'shortcutShortLabel="@string/(\w+)"')
            .firstMatch(s)!
            .group(1)!);
        expect(short, isNotEmpty);
        expect(short.length, lessThanOrEqualTo(10), reason: short);
        expect(s, contains('targetClass="com.aurasync.aurasync.MainActivity"'));
      }
      expect(
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
          contains('android:name="android.app.shortcuts"'));
    });

    test('iOS items use SF Symbols and the bundle-id prefix', () {
      for (final i in iosItems) {
        expect(i.type, startsWith('com.aurasync.aurasync.'));
        expect(i.symbol, isNotEmpty);
      }
    });
  });

  group('dark launch screens', () {
    test('Android launch and window backgrounds are the app colour, not white',
        () {
      expect(File('$res/values/colors.xml').readAsStringSync(),
          contains('#0B1220'));
      for (final f in ['values', 'values-night', 'values-v31']) {
        final styles = File('$res/$f/styles.xml').readAsStringSync();
        expect(styles, contains('Theme.Black.NoTitleBar'), reason: f);
        expect(styles, isNot(contains('Theme.Light')), reason: f);
        expect(styles, contains('@color/aura_background'), reason: f);
      }
      final launch =
          File('$res/drawable/launch_background.xml').readAsStringSync();
      expect(launch, contains('@color/aura_background'));
      expect(launch, contains('ic_launcher_foreground'));
      expect(File('$res/drawable-v21/launch_background.xml').readAsStringSync(),
          launch);
    });

    test('iOS launch screen is dark with the heart', () {
      final sb = File('ios/Runner/Base.lproj/LaunchScreen.storyboard')
          .readAsStringSync();
      expect(sb, isNot(contains('red="1" green="1" blue="1"')),
          reason: 'white background');
      expect(sb, contains('red="0.043137254901960784"'));
      const launchDir = 'ios/Runner/Assets.xcassets/LaunchImage.imageset';
      expect(png('$launchDir/LaunchImage.png').width, 144);
      expect(png('$launchDir/LaunchImage@2x.png').width, 288);
      expect(png('$launchDir/LaunchImage@3x.png').width, 432);
    });
  });

  group('native handlers use the same channel as Dart', () {
    final channel = LaunchChannel.channel.name;

    test('Android MainActivity', () {
      final k = File(
              'android/app/src/main/kotlin/com/aurasync/aurasync/MainActivity.kt')
          .readAsStringSync();
      expect(k, contains('"$channel"'));
      expect(k, contains('"initialMode"'));
      expect(k, contains('"launchMode"'));
      expect(k, contains('onNewIntent'));
      expect(k, contains('"aurasync.mode"'));
    });

    test('iOS AppDelegate and SceneDelegate', () {
      final a = File('ios/Runner/AppDelegate.swift').readAsStringSync();
      expect(a, contains('"$channel"'));
      expect(a, contains('"initialMode"'));
      expect(a, contains('"launchMode"'));
      final s = File('ios/Runner/SceneDelegate.swift').readAsStringSync();
      expect(s, contains('connectionOptions.shortcutItem'));
      expect(s, contains('performActionFor'));
    });
  });

  group('LaunchChannel', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(
        () => messenger.setMockMethodCallHandler(LaunchChannel.channel, null));

    test('reads the shortcut that started the app', () async {
      messenger.setMockMethodCallHandler(LaunchChannel.channel,
          (c) async => c.method == 'initialMode' ? 'focus' : null);
      expect(await LaunchChannel.attach(ShortcutRequests()), LaunchMode.focus);
    });

    test(
        'a plain launch, an unknown value or no native side all mean the home screen',
        () async {
      messenger.setMockMethodCallHandler(
          LaunchChannel.channel, (c) async => null);
      expect(await LaunchChannel.attach(ShortcutRequests()), isNull);
      messenger.setMockMethodCallHandler(
          LaunchChannel.channel, (c) async => 'bogus');
      expect(await LaunchChannel.attach(ShortcutRequests()), isNull);
      messenger.setMockMethodCallHandler(LaunchChannel.channel, null);
      expect(await LaunchChannel.attach(ShortcutRequests()), isNull,
          reason: 'MissingPluginException');
    });

    test('a tap while the app is running reaches the request notifier',
        () async {
      messenger.setMockMethodCallHandler(
          LaunchChannel.channel, (c) async => null);
      final requests = ShortcutRequests();
      await LaunchChannel.attach(requests);
      Future<void> fromNative(Object? mode) => messenger.handlePlatformMessage(
          LaunchChannel.channel.name,
          LaunchChannel.channel.codec
              .encodeMethodCall(MethodCall('launchMode', mode)),
          (_) {});
      await fromNative('deep');
      expect(requests.value, LaunchMode.deep);
      requests.value = null;
      await fromNative('garbage');
      expect(requests.value, isNull);
      await fromNative(null);
      expect(requests.value, isNull);
    });
  });

  group('shortcut while the app is running', () {
    Future<SensoryProfileRepository> repo() async => SensoryProfileRepository(
        await LocalDatabase.openJson(MemoryKeyValueStore()));

    Widget app(SensoryProfileRepository r, ShortcutRequests req) => MaterialApp(
          home: HomeSosScreen(
            audio: PureDartDsp(),
            repository: r,
            library: VoiceLibrary(root: Directory.systemTemp),
            shortcutRequests: req,
          ),
        );

    testWidgets('on the home screen it starts the session and is consumed',
        (tester) async {
      final r = (await tester.runAsync(repo))!;
      final req = ShortcutRequests();
      await tester.pumpWidget(app(r, req));
      await tester.pump();
      req.value = LaunchMode.calm;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
          tester.widget<SessionScreen>(find.byType(SessionScreen)).preset.name,
          'calmStim');
      expect(req.value, isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('it never interrupts a session that is already running',
        (tester) async {
      final r = (await tester.runAsync(repo))!;
      final req = ShortcutRequests();
      await tester.pumpWidget(app(r, req));
      await tester.pump();
      req.value = LaunchMode.focus;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      req.value = LaunchMode.deep; // arrives while Focus is showing
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(SessionScreen), findsOneWidget);
      expect(
          tester.widget<SessionScreen>(find.byType(SessionScreen)).preset.name,
          'focusClassroom');
      expect(req.value, isNull, reason: 'consumed so it cannot fire later');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('it does not open over the caregiver settings', (tester) async {
      final r = (await tester.runAsync(repo))!;
      final req = ShortcutRequests();
      // Home screen listening, then covered by a pushed route.
      await tester.pumpWidget(MaterialApp(
          home: HomeSosScreen(
        audio: PureDartDsp(),
        repository: r,
        library: VoiceLibrary(root: Directory.systemTemp),
        shortcutRequests: req,
      )));
      await tester.pump();
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.push(MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('covering page'))));
      await tester.pump(const Duration(milliseconds: 400));
      req.value = LaunchMode.sos;
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(SessionScreen), findsNothing);
      expect(find.text('covering page'), findsOneWidget);
      expect(req.value, isNull);
    });
  });
}
