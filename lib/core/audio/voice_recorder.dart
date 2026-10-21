import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'familiar_voice_processor.dart';
import 'voice_weave.dart';
import 'wav_codec.dart';

/// Caregiver microphone capture through the native 'aurasync/voice' channel (no plugin).
/// The native side caps a take at [maxSeconds].
class VoiceRecorder {
  VoiceRecorder({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('aurasync/voice');

  static const double maxSeconds = 6.0;

  final MethodChannel _channel;

  /// True once recording has started; false if permission was denied or capture is unavailable.
  Future<bool> start() async {
    try {
      return (await _channel.invokeMethod<bool>('start')) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Ends the take and returns it as processed 48 kHz mono, or null if nothing usable was captured.
  Future<Float32List?> stop() async {
    String? path;
    try {
      final Map<Object?, Object?>? r =
          await _channel.invokeMapMethod<Object?, Object?>('stop');
      path = r?['path'] as String?;
      if (path == null) return null;
      final Uint8List bytes = await File(path).readAsBytes();
      final WavData wav = decodeWav16Mono(bytes);
      final Float32List mono48 = resampleTo48k(wav.samples, wav.sampleRate);
      final Float32List processed =
          const FamiliarVoiceProcessor().process(mono48);
      return processed.length > VoiceWeaveEngine.maxFrames
          ? Float32List.sublistView(processed, 0, VoiceWeaveEngine.maxFrames)
          : processed;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    } finally {
      if (path != null) {
        try {
          await File(path).delete();
        } on FileSystemException {
          // Already gone.
        }
      }
    }
  }

  Future<void> cancel() async {
    try {
      await _channel.invokeMethod<void>('cancel');
    } on MissingPluginException {
      // No native recorder on this platform.
    } on PlatformException {
      // Nothing to cancel.
    }
  }
}
