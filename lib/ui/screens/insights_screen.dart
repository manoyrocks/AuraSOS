import 'package:flutter/material.dart';

import '../../core/models/sensory_state.dart';
import '../../data/clinical_report_exporter.dart';
import '../../data/models.dart';
import '../../data/session_insights.dart';
import '../../data/sensory_profile_repository.dart';
import '../widgets/aura_loader.dart';
import '../widgets/readable_width.dart';

/// Caregiver-only overview of what has helped: efficacy per preset, when sessions
/// happen and the latest sessions. Everything is computed on the device.
class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key, required this.repository});

  final SensoryProfileRepository repository;

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  static const Color _good = Color(0xFF4FA38C);
  static const Color _mid = Color(0xFF8A94A6);
  static const Color _bad = Color(0xFFD9625B);

  List<SessionLog>? _logs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    List<SessionLog> logs;
    try {
      logs = await widget.repository.sessions();
    } catch (_) {
      logs = <SessionLog>[];
    }
    if (mounted) setState(() => _logs = logs);
  }

  Future<void> _annotate(SessionLog log) async {
    final _Annotation? result = await showModalBottomSheet<_Annotation>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext _) => _AnnotateSheet(log: log),
    );
    if (result == null) return;
    try {
      await widget.repository.annotateSession(log.id!,
          triggers: result.triggers, note: result.note);
    } catch (_) {
      // A failed save must never crash the screen; the list just stays as it was.
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final List<SessionLog>? logs = _logs;
    return Scaffold(
      appBar: AppBar(title: const Text('What helps')),
      body: ReadableWidth(
        child: logs == null
            ? const Center(child: AuraLoader())
            : logs.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'No sessions yet. After a session, rate how it went and the '
                        'results will appear here.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : _content(context, logs),
      ),
    );
  }

  Widget _content(BuildContext context, List<SessionLog> logs) {
    final SessionInsights insights = SessionInsights.from(logs);
    final TextTheme text = Theme.of(context).textTheme;
    final PresetStats? best = insights.bestPreset;
    final double? esc = insights.escalationRate;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: _tile(context, '${insights.total}', 'sessions')),
            const SizedBox(width: 12),
            Expanded(
                child: _tile(context, '${insights.last7Days}', 'last 7 days')),
            const SizedBox(width: 12),
            Expanded(
              child: _tile(context,
                  esc == null ? '–' : '${(esc * 100).round()}%', 'escalated'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (best != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.favorite_rounded, color: _good),
              title: Text(
                  'Most effective: ${ClinicalReportExporter.presetLabel(best.preset)}'),
              subtitle: Text(
                '${(best.effectiveRate! * 100).round()}% of ${best.rated} rated sessions',
              ),
            ),
          )
        else
          Text(
            'Rate at least ${SessionInsights.minRatedForBest} sessions of a mode to see '
            'which one works best.',
            style: text.bodyMedium,
          ),
        const SizedBox(height: 24),
        Text('By mode', style: text.titleMedium),
        const SizedBox(height: 8),
        for (final PresetStats s in insights.byPreset) _presetRow(context, s),
        const SizedBox(height: 16),
        const Wrap(
          spacing: 16,
          children: <Widget>[
            _Legend(color: _good, label: 'Effective'),
            _Legend(color: _mid, label: 'Neutral'),
            _Legend(color: _bad, label: 'Escalated'),
          ],
        ),
        const SizedBox(height: 24),
        Text('When sessions happen', style: text.titleMedium),
        const SizedBox(height: 8),
        _timeOfDay(context, insights),
        const SizedBox(height: 24),
        if (insights.topTriggers.isNotEmpty) ...<Widget>[
          Text('Common triggers', style: text.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              for (final MapEntry<String, int> t in insights.topTriggers)
                Chip(label: Text('${t.key} · ${t.value}')),
            ],
          ),
          const SizedBox(height: 24),
        ],
        Text('Recent sessions', style: text.titleMedium),
        const SizedBox(height: 4),
        Text('Tap a session to add triggers or a note.', style: text.bodySmall),
        const SizedBox(height: 8),
        for (final SessionLog l in logs.take(10)) _logRow(l),
      ],
    );
  }

  Widget _tile(BuildContext context, String value, String label) {
    final TextTheme text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          children: <Widget>[
            Text(value, style: text.headlineSmall),
            const SizedBox(height: 2),
            Text(label, style: text.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _presetRow(BuildContext context, PresetStats s) {
    final String label = ClinicalReportExporter.presetLabel(s.preset);
    final String rate = s.effectiveRate == null
        ? 'not rated yet'
        : '${(s.effectiveRate! * 100).round()}% of ${s.rated} rated effective';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(label)),
              Text('${s.total} · $rate',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 6),
          _RatingBar(
            key: ValueKey<String>('rating-bar-${s.preset.name}'),
            stats: s,
            good: _good,
            mid: _mid,
            bad: _bad,
          ),
        ],
      ),
    );
  }

  Widget _timeOfDay(BuildContext context, SessionInsights insights) {
    final int peak =
        insights.timeOfDay.values.fold<int>(0, (int a, int b) => a > b ? a : b);
    return Column(
      children: <Widget>[
        for (final MapEntry<String, int> e in insights.timeOfDay.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: <Widget>[
                SizedBox(width: 90, child: Text(e.key)),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      minHeight: 10,
                      value: peak == 0 ? 0 : e.value / peak,
                    ),
                  ),
                ),
                SizedBox(
                    width: 36,
                    child: Text('${e.value}', textAlign: TextAlign.right)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _logRow(SessionLog l) {
    final EfficacyRating? r = l.rating;
    final Color color = r == EfficacyRating.effective
        ? _good
        : r == EfficacyRating.escalated
            ? _bad
            : _mid;
    final String d = l.startedAt.toLocal().toString().substring(0, 16);
    final int minutes = (l.durationSec / 60).round();
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.circle,
          size: 14, color: r == null ? Colors.transparent : color),
      title: Text(ClinicalReportExporter.presetLabel(l.preset)),
      subtitle: Text(
        '$d · ${minutes < 1 ? '<1' : minutes} min'
        '${l.triggers.isEmpty ? '' : '\n${l.triggers.join(', ')}'}'
        '${l.note == null ? '' : '\n${l.note}'}',
      ),
      isThreeLine: l.triggers.isNotEmpty || l.note != null,
      trailing: Text(ClinicalReportExporter.ratingLabel(r)),
      onTap: l.id == null ? null : () => _annotate(l),
    );
  }
}

class _RatingBar extends StatelessWidget {
  const _RatingBar(
      {super.key,
      required this.stats,
      required this.good,
      required this.mid,
      required this.bad});

  final PresetStats stats;
  final Color good;
  final Color mid;
  final Color bad;

  @override
  Widget build(BuildContext context) {
    if (stats.total == 0) return const SizedBox.shrink();
    Widget seg(int n, Color c) => n == 0
        ? const SizedBox.shrink()
        : Expanded(flex: n, child: ColoredBox(color: c));
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: SizedBox(
        height: 12,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            seg(stats.effective, good),
            seg(stats.neutral, mid),
            seg(stats.escalated, bad),
            seg(stats.unrated, Colors.white12),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _Annotation {
  const _Annotation(this.triggers, this.note);

  final List<String> triggers;
  final String note;
}

class _AnnotateSheet extends StatefulWidget {
  const _AnnotateSheet({required this.log});

  final SessionLog log;

  @override
  State<_AnnotateSheet> createState() => _AnnotateSheetState();
}

class _AnnotateSheetState extends State<_AnnotateSheet> {
  late final Set<String> _selected = <String>{...widget.log.triggers};
  late final TextEditingController _note =
      TextEditingController(text: widget.log.note ?? '');

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<String> options = <String>[
      ...kTriggerOptions,
      for (final String t in widget.log.triggers)
        if (!kTriggerOptions.contains(t)) t,
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('What happened before?',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: <Widget>[
                for (final String t in options)
                  FilterChip(
                    label: Text(t),
                    selected: _selected.contains(t),
                    onSelected: (bool on) => setState(() {
                      on ? _selected.add(t) : _selected.remove(t);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _note,
              maxLength: 500,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(
                  _Annotation(
                    options.where(_selected.contains).toList(),
                    _note.text,
                  ),
                ),
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
