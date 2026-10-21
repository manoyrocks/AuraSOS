import 'package:aurasync/core/models/sensory_state.dart';
import 'package:aurasync/data/models.dart';
import 'package:aurasync/data/session_insights.dart';
import 'package:flutter_test/flutter_test.dart';

SessionLog _log(
  SessionPreset preset,
  EfficacyRating? rating, {
  DateTime? at,
  int seconds = 600,
  List<String> triggers = const [],
}) =>
    SessionLog(
      startedAt: at ?? DateTime(2026, 10, 20, 9),
      durationSec: seconds,
      preset: preset,
      reachedPhase: IsoPhase.baseline,
      rating: rating,
      triggers: triggers,
    );

void main() {
  final now = DateTime(2026, 10, 21, 12);

  test('empty history is all zeros with no best preset', () {
    final i = SessionInsights.from(const [], now: now);
    expect(i.total, 0);
    expect(i.last7Days, 0);
    expect(i.byPreset, isEmpty);
    expect(i.bestPreset, isNull);
    expect(i.escalationRate, isNull);
    expect(i.timeOfDay.values.every((v) => v == 0), isTrue);
    expect(i.timeOfDay.keys.toList(),
        ['Morning', 'Afternoon', 'Evening', 'Night']);
  });

  test('per-preset counts, rates and average duration', () {
    final i = SessionInsights.from([
      _log(SessionPreset.isoDownRegulator, EfficacyRating.effective,
          seconds: 600),
      _log(SessionPreset.isoDownRegulator, EfficacyRating.effective,
          seconds: 300),
      _log(SessionPreset.isoDownRegulator, EfficacyRating.escalated,
          seconds: 90),
      _log(SessionPreset.isoDownRegulator, null, seconds: 10),
      _log(SessionPreset.calmStim, EfficacyRating.neutral),
    ], now: now);
    final iso = i.byPreset.first;
    expect(iso.preset, SessionPreset.isoDownRegulator);
    expect(iso.total, 4);
    expect(iso.rated, 3);
    expect(iso.unrated, 1);
    expect(iso.effectiveRate, closeTo(2 / 3, 1e-9));
    expect(iso.avgDurationSec, 250);
    expect(i.byPreset.last.effectiveRate, 0.0);
    expect(i.escalationRate, closeTo(1 / 4, 1e-9));
  });

  test('a preset with nothing rated has no rate', () {
    final i = SessionInsights.from([_log(SessionPreset.focusClassroom, null)],
        now: now);
    expect(i.byPreset.single.effectiveRate, isNull);
    expect(i.escalationRate, isNull);
  });

  test('best preset needs enough ratings and picks the highest effective share',
      () {
    final logs = [
      // 3 of 3 effective but a different preset has more, so compare shares.
      for (var k = 0; k < 3; k++)
        _log(SessionPreset.calmStim, EfficacyRating.effective),
      for (var k = 0; k < 4; k++)
        _log(SessionPreset.isoDownRegulator,
            k < 2 ? EfficacyRating.effective : EfficacyRating.neutral),
      // Perfect but only two ratings: not enough to be called best.
      for (var k = 0; k < 2; k++)
        _log(SessionPreset.deepCrisisAnchor, EfficacyRating.effective),
    ];
    final i = SessionInsights.from(logs, now: now);
    expect(i.bestPreset!.preset, SessionPreset.calmStim);

    final thin = SessionInsights.from(
      [
        for (var k = 0; k < 2; k++)
          _log(SessionPreset.calmStim, EfficacyRating.effective)
      ],
      now: now,
    );
    expect(thin.bestPreset, isNull);
  });

  test('last 7 days and time-of-day buckets', () {
    final i = SessionInsights.from([
      _log(SessionPreset.calmStim, null,
          at: DateTime(2026, 10, 21, 6)), // morning
      _log(SessionPreset.calmStim, null,
          at: DateTime(2026, 10, 20, 13)), // afternoon
      _log(SessionPreset.calmStim, null,
          at: DateTime(2026, 10, 19, 18)), // evening
      _log(SessionPreset.calmStim, null,
          at: DateTime(2026, 10, 18, 23)), // night
      _log(SessionPreset.calmStim, null,
          at: DateTime(2026, 10, 1, 8)), // old, morning
    ], now: now);
    expect(i.total, 5);
    expect(i.last7Days, 4);
    expect(
        i.timeOfDay, {'Morning': 2, 'Afternoon': 1, 'Evening': 1, 'Night': 1});
  });

  test('presets sort by usage, ties by preset order', () {
    final i = SessionInsights.from([
      _log(SessionPreset.calmStim, null),
      _log(SessionPreset.focusClassroom, null),
      _log(SessionPreset.focusClassroom, null),
      _log(SessionPreset.isoDownRegulator, null),
    ], now: now);
    expect(i.byPreset.map((s) => s.preset), [
      SessionPreset.focusClassroom,
      SessionPreset.isoDownRegulator,
      SessionPreset.calmStim,
    ]);
  });

  test(
      'top triggers are counted per session, most common first, ties alphabetical',
      () {
    final i = SessionInsights.from([
      _log(SessionPreset.calmStim, null, triggers: ['Tired', 'Loud noise']),
      _log(SessionPreset.calmStim, null,
          triggers: ['Loud noise', 'Loud noise']), // dup = 1
      _log(SessionPreset.calmStim, null, triggers: ['Waiting']),
      _log(SessionPreset.calmStim, null),
    ], now: now);
    expect(i.topTriggers.map((e) => '${e.key}:${e.value}'),
        ['Loud noise:2', 'Tired:1', 'Waiting:1']);
    expect(SessionInsights.from(const [], now: now).topTriggers, isEmpty);
  });
}
