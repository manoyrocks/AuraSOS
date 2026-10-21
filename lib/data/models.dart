import 'dart:convert';

import '../core/models/sensory_state.dart';

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final T v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

T? _enumByNameOrNull<T extends Enum>(List<T> values, Object? name) {
  if (name == null) return null;
  for (final T v in values) {
    if (v.name == name) return v;
  }
  return null;
}

final RegExp _blockFreqRule = RegExp(
  r'block\s+frequenc(?:y|ies)\s*>\s*(\d+(?:\.\d+)?)\s*hz',
  caseSensitive: false,
);

/// Returns the lowest N found in rules shaped like 'Block frequencies > N Hz',
/// or null when no such rule exists.
double? parseHighCutFromBlacklist(List<String> blacklist) {
  double? lowest;
  for (final String rule in blacklist) {
    for (final RegExpMatch m in _blockFreqRule.allMatches(rule)) {
      final double? v = double.tryParse(m.group(1)!);
      if (v == null || v <= 0) continue;
      if (lowest == null || v < lowest) lowest = v;
    }
  }
  return lowest;
}

/// What the child sees. [auto] picks the shader that suits the session preset; the rest
/// decouple the visuals from the sound ([blackScreen] = audio only, nothing lit).
enum VisualMode {
  auto,
  tunnel,
  bubbles,
  lanterns,
  breathingOrb,
  crystals,
  starfield,
  aurora,
  mandala,
  blackScreen,
}

class SensoryProfile {
  const SensoryProfile({
    this.id = 1,
    this.childName = 'Child',
    this.masterVolumeCap = 0.6,
    this.brightnessCap = 0.8,
    this.highCutHz = 0,
    this.disableWater = false,
    this.disableHighPiano = false,
    this.blacklist = const <String>[],
    this.preferredPreset = SessionPreset.isoDownRegulator,
    this.voiceEnabled = false,
    this.voiceGain = 0.12,
    this.voiceIntervalSec = 45,
    this.visualMode = VisualMode.auto,
    this.focusMinutes = 20,
  });

  final int id;
  final String childName;

  /// 0..1
  final double masterVolumeCap;

  /// 0..1
  final double brightnessCap;

  /// 0 = none
  final double highCutHz;
  final bool disableWater;
  final bool disableHighPiano;

  /// Free-form rules such as 'Block frequencies > 1800 Hz'.
  final List<String> blacklist;
  final SessionPreset preferredPreset;

  /// Familiar-voice weaving: on/off, linear gain (0.04..0.30), pause between phrases.
  final bool voiceEnabled;
  final double voiceGain;
  final double voiceIntervalSec;

  final VisualMode visualMode;

  /// Focus-mode timer length, 5..60.
  final int focusMinutes;

  static SensoryProfile defaults() => const SensoryProfile();

  SensoryProfile copyWith({
    int? id,
    String? childName,
    double? masterVolumeCap,
    double? brightnessCap,
    double? highCutHz,
    bool? disableWater,
    bool? disableHighPiano,
    List<String>? blacklist,
    SessionPreset? preferredPreset,
    bool? voiceEnabled,
    double? voiceGain,
    double? voiceIntervalSec,
    VisualMode? visualMode,
    int? focusMinutes,
  }) {
    return SensoryProfile(
      id: id ?? this.id,
      childName: childName ?? this.childName,
      masterVolumeCap: masterVolumeCap ?? this.masterVolumeCap,
      brightnessCap: brightnessCap ?? this.brightnessCap,
      highCutHz: highCutHz ?? this.highCutHz,
      disableWater: disableWater ?? this.disableWater,
      disableHighPiano: disableHighPiano ?? this.disableHighPiano,
      blacklist: blacklist ?? this.blacklist,
      preferredPreset: preferredPreset ?? this.preferredPreset,
      voiceEnabled: voiceEnabled ?? this.voiceEnabled,
      voiceGain: voiceGain ?? this.voiceGain,
      voiceIntervalSec: voiceIntervalSec ?? this.voiceIntervalSec,
      visualMode: visualMode ?? this.visualMode,
      focusMinutes: focusMinutes ?? this.focusMinutes,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'child_name': childName,
        'master_volume_cap': masterVolumeCap,
        'brightness_cap': brightnessCap,
        'high_cut_hz': highCutHz,
        'disable_water': disableWater ? 1 : 0,
        'disable_high_piano': disableHighPiano ? 1 : 0,
        'blacklist': jsonEncode(blacklist),
        'preferred_preset': preferredPreset.name,
        'voice_enabled': voiceEnabled ? 1 : 0,
        'voice_gain': voiceGain,
        'voice_interval_sec': voiceIntervalSec,
        'visual_mode': visualMode.name,
        'focus_minutes': focusMinutes,
      };

  static SensoryProfile fromMap(Map<String, Object?> m) {
    final List<String> rules = <String>[];
    final Object? raw = m['blacklist'];
    if (raw is String && raw.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final Object? e in decoded) {
            if (e != null) rules.add(e.toString());
          }
        }
      } on FormatException {
        rules.add(raw);
      }
    }
    return SensoryProfile(
      id: (m['id'] as num?)?.toInt() ?? 1,
      childName: (m['child_name'] as String?) ?? 'Child',
      masterVolumeCap: ((m['master_volume_cap'] as num?)?.toDouble() ?? 0.6)
          .clamp(0.0, 1.0)
          .toDouble(),
      brightnessCap: ((m['brightness_cap'] as num?)?.toDouble() ?? 0.8)
          .clamp(0.0, 1.0)
          .toDouble(),
      highCutHz: (m['high_cut_hz'] as num?)?.toDouble() ?? 0.0,
      disableWater: ((m['disable_water'] as num?)?.toInt() ?? 0) != 0,
      disableHighPiano: ((m['disable_high_piano'] as num?)?.toInt() ?? 0) != 0,
      blacklist: rules,
      preferredPreset: _enumByName(SessionPreset.values, m['preferred_preset'],
          SessionPreset.isoDownRegulator),
      voiceEnabled: ((m['voice_enabled'] as num?)?.toInt() ?? 0) != 0,
      voiceGain: ((m['voice_gain'] as num?)?.toDouble() ?? 0.12)
          .clamp(0.0, 0.5)
          .toDouble(),
      voiceIntervalSec: ((m['voice_interval_sec'] as num?)?.toDouble() ?? 45.0)
          .clamp(10.0, 600.0)
          .toDouble(),
      visualMode: VisualMode.values.firstWhere(
        (VisualMode v) => v.name == m['visual_mode'],
        orElse: () => VisualMode.auto,
      ),
      focusMinutes:
          ((m['focus_minutes'] as num?)?.toInt() ?? 20).clamp(5, 60).toInt(),
    );
  }
}

/// Antecedents a caregiver can tag on a session (ABC-style data for BCBA / OT review).
const List<String> kTriggerOptions = <String>[
  'Loud noise',
  'Crowd / busy place',
  'Transition',
  'Change in routine',
  'Tired',
  'Hungry',
  'Waiting',
  'Screen taken away',
  'Unknown',
];

class SessionLog {
  const SessionLog({
    this.id,
    required this.startedAt,
    required this.durationSec,
    required this.preset,
    this.reachedPhase,
    this.rating,
    this.triggers = const <String>[],
    this.note,
  });

  final int? id;
  final DateTime startedAt;
  final int durationSec;
  final SessionPreset preset;
  final IsoPhase? reachedPhase;
  final EfficacyRating? rating;

  /// Caregiver-chosen antecedents, see [kTriggerOptions].
  final List<String> triggers;

  /// Free-text caregiver note, at most 500 characters.
  final String? note;

  Map<String, Object?> toMap() => <String, Object?>{
        if (id != null) 'id': id,
        'started_at': startedAt.millisecondsSinceEpoch,
        'duration_sec': durationSec,
        'preset': preset.name,
        'reached_phase': reachedPhase?.name,
        'rating': rating?.name,
        'trigger_tags': jsonEncode(triggers),
        'note': note,
      };

  static SessionLog fromMap(Map<String, Object?> m) {
    return SessionLog(
      id: (m['id'] as num?)?.toInt(),
      startedAt: DateTime.fromMillisecondsSinceEpoch(
          (m['started_at'] as num?)?.toInt() ?? 0),
      durationSec: (m['duration_sec'] as num?)?.toInt() ?? 0,
      preset: _enumByName(
          SessionPreset.values, m['preset'], SessionPreset.isoDownRegulator),
      reachedPhase: _enumByNameOrNull(IsoPhase.values, m['reached_phase']),
      rating: _enumByNameOrNull(EfficacyRating.values, m['rating']),
      triggers: _decodeTags(m['trigger_tags']),
      note: (m['note'] as String?)?.trim().isEmpty ?? true
          ? null
          : (m['note'] as String).trim(),
    );
  }
}

List<String> _decodeTags(Object? raw) {
  if (raw is! String || raw.isEmpty) return const <String>[];
  try {
    final Object? decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded
          .whereType<String>()
          .where((String t) => t.trim().isNotEmpty)
          .toList();
    }
  } on FormatException {
    // A damaged cell reads as no tags.
  }
  return const <String>[];
}

extension SensoryProfileAudioLimits on SensoryProfile {
  /// Strictest high-cut across the explicit setting, the "soften high tones" switch
  /// (1.2 kHz) and any 'Block frequencies > N Hz' blacklist rule. 0 means no cut.
  double get effectiveHighCutHz {
    final double? ruleCut = parseHighCutFromBlacklist(blacklist);
    final List<double> cuts = <double>[
      if (highCutHz > 0) highCutHz,
      if (disableHighPiano) 1200.0,
      if (ruleCut != null) ruleCut,
    ];
    return cuts.isEmpty
        ? 0
        : cuts.reduce((double a, double b) => a < b ? a : b);
  }
}
