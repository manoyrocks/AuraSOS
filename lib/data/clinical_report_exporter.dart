import 'dart:io';

import '../core/models/sensory_state.dart';
import 'models.dart';
import 'sensory_profile_repository.dart';

class ClinicalReportExporter {
  ClinicalReportExporter(this._repo);

  final SensoryProfileRepository _repo;

  static const List<String> timeBuckets = <String>[
    'Morning',
    'Afternoon',
    'Evening',
    'Night',
  ];

  static String timeOfDay(DateTime t) {
    final int h = t.hour;
    if (h >= 5 && h < 12) return 'Morning';
    if (h >= 12 && h < 17) return 'Afternoon';
    if (h >= 17 && h < 21) return 'Evening';
    return 'Night';
  }

  static String presetLabel(SessionPreset p) {
    switch (p) {
      case SessionPreset.isoDownRegulator:
        return 'Iso Down-Regulator';
      case SessionPreset.deepCrisisAnchor:
        return 'Deep-Crisis Anchor';
      case SessionPreset.focusClassroom:
        return 'Focus / Classroom';
      case SessionPreset.calmStim:
        return 'Calm / Stim';
    }
  }

  static String phaseLabel(IsoPhase? p) {
    switch (p) {
      case IsoPhase.match:
        return 'Match';
      case IsoPhase.thinning:
        return 'Thinning';
      case IsoPhase.baseline:
        return 'Baseline';
      case null:
        return '';
    }
  }

  static String ratingLabel(EfficacyRating? r) {
    switch (r) {
      case EfficacyRating.effective:
        return 'Effective';
      case EfficacyRating.neutral:
        return 'Neutral';
      case EfficacyRating.escalated:
        return 'Escalated';
      case null:
        return 'Unrated';
    }
  }

  static String _csvField(String v) {
    if (v.contains(',') ||
        v.contains('"') ||
        v.contains('\n') ||
        v.contains('\r')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _stamp(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-${_two(t.month)}-${_two(t.day)} '
      '${_two(t.hour)}:${_two(t.minute)}';

  static String _mdCell(String v) =>
      v.replaceAll('|', r'\|').replaceAll(RegExp(r'[\r\n]+'), ' ');

  Future<List<SessionLog>> _chronological() async {
    final List<SessionLog> all = await _repo.sessions();
    return all.reversed.toList();
  }

  Future<String> toCsv() async {
    final List<SessionLog> logs = await _chronological();
    final StringBuffer b = StringBuffer();
    b.write(
        'id,started_at,time_of_day,duration_sec,preset,reached_phase,rating,triggers,note\r\n');
    for (final SessionLog l in logs) {
      final List<String> row = <String>[
        l.id?.toString() ?? '',
        l.startedAt.toIso8601String(),
        timeOfDay(l.startedAt),
        l.durationSec.toString(),
        l.preset.name,
        l.reachedPhase?.name ?? '',
        l.rating?.name ?? 'unrated',
        l.triggers.join('; '),
        l.note ?? '',
      ];
      b.write(row.map(_csvField).join(','));
      b.write('\r\n');
    }
    return b.toString();
  }

  Future<String> toMarkdown() async {
    final SensoryProfile profile = await _repo.activeProfile();
    final List<SessionLog> logs = await _chronological();
    final StringBuffer b = StringBuffer();

    b.writeln('# AuraSOS Clinical Report');
    b.writeln();
    b.writeln('Generated: ${_stamp(DateTime.now())}');
    b.writeln();

    b.writeln('## Sensory Profile');
    b.writeln();
    b.writeln('- Child: ${profile.childName}');
    b.writeln(
        '- Master volume cap: ${(profile.masterVolumeCap * 100).round()}%');
    b.writeln('- Brightness cap: ${(profile.brightnessCap * 100).round()}%');
    b.writeln(profile.highCutHz > 0
        ? '- High-cut: ${profile.highCutHz.round()} Hz'
        : '- High-cut: none');
    b.writeln(
        '- Water sounds: ${profile.disableWater ? 'disabled' : 'enabled'}');
    b.writeln(
        '- High piano register: ${profile.disableHighPiano ? 'disabled' : 'enabled'}');
    b.writeln('- Preferred preset: ${presetLabel(profile.preferredPreset)}');
    b.writeln();

    b.writeln('## Sensory Blacklist');
    b.writeln();
    if (profile.blacklist.isEmpty) {
      b.writeln('No custom rules.');
    } else {
      for (final String rule in profile.blacklist) {
        b.writeln('- ${rule.replaceAll(RegExp(r'[\r\n]+'), ' ')}');
      }
    }
    b.writeln();

    b.writeln('## Efficacy by Preset');
    b.writeln();
    b.writeln(
        '| Preset | Sessions | Effective | Neutral | Escalated | Unrated | Avg duration |');
    b.writeln('|---|---|---|---|---|---|---|');
    for (final SessionPreset preset in SessionPreset.values) {
      final List<SessionLog> sub =
          logs.where((SessionLog l) => l.preset == preset).toList();
      if (sub.isEmpty) continue;
      final int total = sub.length;
      String cell(EfficacyRating? r) {
        final int n = sub.where((SessionLog l) => l.rating == r).length;
        return '$n (${(n * 100 / total).toStringAsFixed(0)}%)';
      }

      final int sum =
          sub.fold<int>(0, (int a, SessionLog l) => a + l.durationSec);
      b.writeln('| ${presetLabel(preset)} | $total | '
          '${cell(EfficacyRating.effective)} | ${cell(EfficacyRating.neutral)} | '
          '${cell(EfficacyRating.escalated)} | ${cell(null)} | '
          '${_duration((sum / total).round())} |');
    }
    if (logs.isEmpty) {
      b.writeln(
          '| (no sessions recorded) | 0 | 0 (0%) | 0 (0%) | 0 (0%) | 0 (0%) | 0m 00s |');
    }
    b.writeln();

    final int totalSum =
        logs.fold<int>(0, (int a, SessionLog l) => a + l.durationSec);
    b.writeln('## Summary');
    b.writeln();
    b.writeln('- Total sessions: ${logs.length}');
    b.writeln(
        '- Average duration: ${logs.isEmpty ? '0m 00s' : _duration((totalSum / logs.length).round())}');
    b.writeln();

    b.writeln('## Time-of-Day Distribution');
    b.writeln();
    b.writeln('| Time of day | Sessions | Share |');
    b.writeln('|---|---|---|');
    for (final String bucket in timeBuckets) {
      final int n =
          logs.where((SessionLog l) => timeOfDay(l.startedAt) == bucket).length;
      final String share = logs.isEmpty
          ? '0%'
          : '${(n * 100 / logs.length).toStringAsFixed(0)}%';
      b.writeln('| $bucket | $n | $share |');
    }
    b.writeln();

    final Map<String, int> triggerCounts = <String, int>{};
    for (final SessionLog l in logs) {
      for (final String t in l.triggers) {
        triggerCounts[t] = (triggerCounts[t] ?? 0) + 1;
      }
    }
    if (triggerCounts.isNotEmpty) {
      final List<MapEntry<String, int>> ranked = triggerCounts.entries.toList()
        ..sort((MapEntry<String, int> a, MapEntry<String, int> b) {
          final int c = b.value.compareTo(a.value);
          return c != 0 ? c : a.key.compareTo(b.key);
        });
      b.writeln('## Reported Triggers');
      b.writeln();
      b.writeln('| Trigger | Sessions |');
      b.writeln('|---|---|');
      for (final MapEntry<String, int> e in ranked) {
        b.writeln('| ${_mdCell(e.key)} | ${e.value} |');
      }
      b.writeln();
    }

    b.writeln('## Session Log (chronological)');
    b.writeln();
    b.writeln(
        '| # | Started | Time of day | Duration | Preset | Reached phase | Rating | Triggers | Note |');
    b.writeln('|---|---|---|---|---|---|---|---|---|');
    for (int i = 0; i < logs.length; i++) {
      final SessionLog l = logs[i];
      final String phase = phaseLabel(l.reachedPhase);
      b.writeln(
          '| ${i + 1} | ${_stamp(l.startedAt)} | ${timeOfDay(l.startedAt)} | '
          '${_duration(l.durationSec)} | ${_mdCell(presetLabel(l.preset))} | '
          '${phase.isEmpty ? '-' : phase} | ${ratingLabel(l.rating)} | '
          '${_mdCell(l.triggers.isEmpty ? '-' : l.triggers.join(', '))} | '
          '${_mdCell(l.note ?? '-')} |');
    }
    b.writeln();

    b.writeln('---');
    b.writeln();
    b.writeln(
        'This report summarizes caregiver-recorded observations from the AuraSOS app for discussion with a qualified '
        'professional. It is not medical advice, a diagnosis, or a treatment recommendation. All data was stored on-device only.');
    return b.toString();
  }

  static String _duration(int sec) {
    final int m = sec ~/ 60;
    final int s = sec % 60;
    return '${m}m ${_two(s)}s';
  }

  /// Writes aurasos_report.csv and aurasos_report.md into [dir]; returns the markdown file.
  Future<File> writeReports(Directory dir) async {
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final String csv = await toCsv();
    final String md = await toMarkdown();
    final File csvFile =
        File('${dir.path}${Platform.pathSeparator}aurasos_report.csv');
    final File mdFile =
        File('${dir.path}${Platform.pathSeparator}aurasos_report.md');
    await csvFile.writeAsString(csv, flush: true);
    await mdFile.writeAsString(md, flush: true);
    return mdFile;
  }
}
