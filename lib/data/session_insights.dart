import '../core/models/sensory_state.dart';
import 'clinical_report_exporter.dart';
import 'models.dart';

/// Rating counts and averages for one preset.
class PresetStats {
  const PresetStats({
    required this.preset,
    required this.total,
    required this.effective,
    required this.neutral,
    required this.escalated,
    required this.avgDurationSec,
  });

  final SessionPreset preset;
  final int total;
  final int effective;
  final int neutral;
  final int escalated;
  final int avgDurationSec;

  int get rated => effective + neutral + escalated;
  int get unrated => total - rated;

  /// Share of rated sessions marked Effective, or null until something has been rated.
  double? get effectiveRate => rated == 0 ? null : effective / rated;
}

/// Caregiver-facing summary of the session history. Pure: no database, no clock unless
/// [now] is passed, so it is trivially testable.
class SessionInsights {
  const SessionInsights({
    required this.total,
    required this.last7Days,
    required this.byPreset,
    required this.timeOfDay,
    required this.bestPreset,
    required this.escalationRate,
    required this.topTriggers,
  });

  /// Rated sessions needed before a preset can be called the best one.
  static const int minRatedForBest = 3;

  final int total;
  final int last7Days;

  /// Presets that have sessions, most-used first.
  final List<PresetStats> byPreset;

  /// Session counts per time-of-day bucket, in morning-to-night order.
  final Map<String, int> timeOfDay;

  /// Preset with the highest Effective share among those with enough ratings.
  final PresetStats? bestPreset;

  /// Share of all rated sessions marked Escalated, or null when nothing is rated.
  final double? escalationRate;

  /// Caregiver-tagged triggers by number of sessions, most common first.
  final List<MapEntry<String, int>> topTriggers;

  static SessionInsights from(List<SessionLog> logs, {DateTime? now}) {
    final DateTime clock = now ?? DateTime.now();
    final DateTime weekAgo = clock.subtract(const Duration(days: 7));

    final Map<SessionPreset, List<SessionLog>> grouped =
        <SessionPreset, List<SessionLog>>{};
    final Map<String, int> buckets = <String, int>{
      for (final String b in ClinicalReportExporter.timeBuckets) b: 0,
    };
    final Map<String, int> triggerCounts = <String, int>{};
    int recent = 0;
    int rated = 0;
    int escalated = 0;
    for (final SessionLog l in logs) {
      grouped.putIfAbsent(l.preset, () => <SessionLog>[]).add(l);
      final String bucket = ClinicalReportExporter.timeOfDay(l.startedAt);
      buckets[bucket] = (buckets[bucket] ?? 0) + 1;
      if (l.startedAt.isAfter(weekAgo)) recent++;
      if (l.rating != null) rated++;
      if (l.rating == EfficacyRating.escalated) escalated++;
      for (final String t in l.triggers.toSet()) {
        triggerCounts[t] = (triggerCounts[t] ?? 0) + 1;
      }
    }

    final List<PresetStats> stats = <PresetStats>[
      for (final MapEntry<SessionPreset, List<SessionLog>> e in grouped.entries)
        PresetStats(
          preset: e.key,
          total: e.value.length,
          effective: e.value
              .where((SessionLog l) => l.rating == EfficacyRating.effective)
              .length,
          neutral: e.value
              .where((SessionLog l) => l.rating == EfficacyRating.neutral)
              .length,
          escalated: e.value
              .where((SessionLog l) => l.rating == EfficacyRating.escalated)
              .length,
          avgDurationSec: e.value
                  .fold<int>(0, (int s, SessionLog l) => s + l.durationSec) ~/
              e.value.length,
        ),
    ]..sort((PresetStats a, PresetStats b) {
        final int byTotal = b.total.compareTo(a.total);
        return byTotal != 0
            ? byTotal
            : a.preset.index.compareTo(b.preset.index);
      });

    PresetStats? best;
    for (final PresetStats s in stats) {
      if (s.rated < minRatedForBest) continue;
      if (best == null || s.effectiveRate! > best.effectiveRate!) best = s;
    }

    return SessionInsights(
      total: logs.length,
      last7Days: recent,
      byPreset: stats,
      timeOfDay: buckets,
      bestPreset: best,
      escalationRate: rated == 0 ? null : escalated / rated,
      topTriggers: triggerCounts.entries.toList()
        ..sort((MapEntry<String, int> a, MapEntry<String, int> b) {
          final int c = b.value.compareTo(a.value);
          return c != 0 ? c : a.key.compareTo(b.key);
        }),
    );
  }
}
