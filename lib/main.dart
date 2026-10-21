import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/audio/audio_engine.dart';
import 'core/audio/dsp_bridge.dart';
import 'core/audio/voice_weave.dart';
import 'data/app_database.dart';
import 'data/local_database.dart';
import 'data/sensory_profile_repository.dart';
import 'data/voice_library.dart';
import 'ui/launch_intent.dart';
import 'ui/screens/home_sos_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  final LocalDatabase database = await openAppDatabase();
  final SensoryProfileRepository repository =
      SensoryProfileRepository(database);
  final AudioEngine audio = DspBridge.create();
  final VoiceLibrary library = VoiceLibrary();
  if (audio is VoiceWeaveEngine) {
    await _loadVoices(audio as VoiceWeaveEngine, library);
  }
  final ShortcutRequests shortcutRequests = ShortcutRequests();
  final LaunchMode? nativeLaunchMode =
      await LaunchChannel.attach(shortcutRequests);
  runApp(AuraSOSApp(
    audio: audio,
    repository: repository,
    library: library,
    launchMode:
        launchModeFrom(Uri.base.queryParameters['mode']) ?? nativeLaunchMode,
    shortcutRequests: shortcutRequests,
  ));
}

/// Pushes saved phrases into the engine before any session can start.
Future<void> _loadVoices(VoiceWeaveEngine engine, VoiceLibrary library) async {
  try {
    final List<Float32List?> phrases = await library.loadAll();
    for (var i = 0; i < phrases.length; i++) {
      final Float32List? p = phrases[i];
      if (p == null) {
        engine.clearVoice(i);
      } else {
        engine.loadVoice(i, p);
      }
    }
  } catch (_) {
    // No phrases is a valid state; the app must still start.
  }
}

class AuraSOSApp extends StatefulWidget {
  const AuraSOSApp(
      {super.key,
      required this.audio,
      required this.repository,
      required this.library,
      this.launchMode,
      this.shortcutRequests});

  final AudioEngine audio;
  final SensoryProfileRepository repository;
  final VoiceLibrary library;
  final LaunchMode? launchMode;
  final ShortcutRequests? shortcutRequests;

  @override
  State<AuraSOSApp> createState() => _AuraSOSAppState();
}

class _AuraSOSAppState extends State<AuraSOSApp> {
  @override
  void dispose() {
    widget.audio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AuraSOS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E6F8E),
          brightness: Brightness.dark,
        ),
      ),
      home: HomeSosScreen(
        audio: widget.audio,
        repository: widget.repository,
        library: widget.library,
        launchMode: widget.launchMode,
        shortcutRequests: widget.shortcutRequests,
      ),
    );
  }
}
