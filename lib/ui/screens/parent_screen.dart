import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/audio/voice_recorder.dart';
import '../../core/audio/voice_weave.dart';
import '../../core/models/sensory_state.dart';
import '../../data/clinical_report_exporter.dart';
import '../../data/models.dart';
import '../../data/sensory_profile_repository.dart';
import '../widgets/about_section.dart';
import '../widgets/readable_width.dart';
import '../widgets/visual_picker.dart';
import 'insights_screen.dart';
import '../../data/voice_library.dart';

/// Caregiver area: sensory profile editing and the BCBA / OT report. Reached only through
/// the 3-second hold gate on the home screen, so a child cannot open it by accident.
class ParentScreen extends StatefulWidget {
  const ParentScreen({
    super.key,
    required this.repository,
    required this.library,
    this.voice,
    this.recorder,
  });

  final SensoryProfileRepository repository;
  final VoiceLibrary library;

  /// Receives saved phrases right away so the next session weaves them in.
  final VoiceWeaveEngine? voice;

  /// Injectable for tests; defaults to the native 'aurasync/voice' channel.
  final VoiceRecorder? recorder;

  @override
  State<ParentScreen> createState() => _ParentScreenState();
}

class _ParentScreenState extends State<ParentScreen> {
  static const double _noCut = 800;

  final TextEditingController _name = TextEditingController();
  final TextEditingController _rules = TextEditingController();
  SensoryProfile? _profile;
  double _volume = 0.6;
  double _brightness = 0.8;
  double _highCut = 0;
  bool _water = true;
  bool _softenHigh = false;
  SessionPreset _sosMode = SessionPreset.isoDownRegulator;
  bool _voiceEnabled = false;
  VisualMode _visual = VisualMode.auto;
  double _focusMinutes = 20;
  double _voiceGain = 0.12;
  double _voiceInterval = 45;
  String? _status;

  late final VoiceRecorder _recorder = widget.recorder ?? VoiceRecorder();
  final List<bool> _filled =
      List<bool>.filled(VoiceWeaveEngine.maxSlots, false);
  int? _recordingSlot;
  bool _busy = false;
  int _secondsLeft = 0;
  Timer? _countdown;

  @override
  void initState() {
    super.initState();
    _load();
    _loadSlots();
  }

  @override
  void dispose() {
    _countdown?.cancel();
    if (_recordingSlot != null) unawaited(_recorder.cancel());
    _name.dispose();
    _rules.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final SensoryProfile p = await widget.repository.activeProfile();
    if (!mounted) return;
    setState(() {
      _profile = p;
      _name.text = p.childName;
      _rules.text = p.blacklist.join('\n');
      _volume = p.masterVolumeCap.clamp(0.1, 1.0).toDouble();
      _brightness = p.brightnessCap.clamp(0.1, 1.0).toDouble();
      _highCut =
          p.highCutHz <= 0 ? 0 : p.highCutHz.clamp(_noCut, 4000.0).toDouble();
      _water = !p.disableWater;
      _softenHigh = p.disableHighPiano;
      _sosMode = p.preferredPreset == SessionPreset.deepCrisisAnchor
          ? SessionPreset.deepCrisisAnchor
          : SessionPreset.isoDownRegulator;
      _voiceEnabled = p.voiceEnabled;
      _visual = p.visualMode;
      _focusMinutes = p.focusMinutes.toDouble();
      _voiceGain = p.voiceGain.clamp(0.04, 0.30).toDouble();
      _voiceInterval = p.voiceIntervalSec.clamp(15.0, 180.0).toDouble();
    });
  }

  Future<void> _loadSlots() async {
    try {
      final List<Float32List?> all = await widget.library.loadAll();
      if (!mounted) return;
      setState(() {
        for (var i = 0; i < _filled.length; i++) {
          _filled[i] = all[i] != null;
        }
      });
    } catch (_) {
      // Slots stay empty; recording still works.
    }
  }

  Future<void> _toggleRecording(int slot) async {
    if (_busy) return;
    if (_recordingSlot == slot) {
      await _finishRecording();
      return;
    }
    if (_recordingSlot != null) return;
    setState(() => _busy = true);
    final bool started = await _recorder.start();
    if (!mounted) {
      if (started) unawaited(_recorder.cancel());
      return;
    }
    if (!started) {
      setState(() {
        _busy = false;
        _status = 'Microphone unavailable or permission denied.';
      });
      return;
    }
    setState(() {
      _busy = false;
      _recordingSlot = slot;
      _secondsLeft = VoiceRecorder.maxSeconds.round();
      _status = null;
    });
    _countdown?.cancel();
    _countdown = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        t.cancel();
        unawaited(_finishRecording());
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  Future<void> _finishRecording() async {
    final int? slot = _recordingSlot;
    if (slot == null || _busy) return;
    _countdown?.cancel();
    setState(() {
      _busy = true;
      _recordingSlot = null;
    });
    String message;
    try {
      final Float32List? samples = await _recorder.stop();
      if (samples == null || samples.isEmpty) {
        message = 'Nothing was recorded. Please try again.';
      } else {
        await widget.library.saveProcessed(slot, samples);
        widget.voice?.loadVoice(slot, samples);
        _filled[slot] = true;
        message = 'Phrase ${slot + 1} saved.';
      }
    } catch (_) {
      message = 'Could not save the phrase.';
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _status = message;
      });
    }
  }

  Future<void> _deleteSlot(int slot) async {
    try {
      await widget.library.delete(slot);
      widget.voice?.clearVoice(slot);
      if (!mounted) return;
      setState(() {
        _filled[slot] = false;
        _status = 'Phrase ${slot + 1} deleted.';
      });
    } catch (_) {
      if (mounted) setState(() => _status = 'Could not delete the phrase.');
    }
  }

  Future<void> _save() async {
    final SensoryProfile? base = _profile;
    if (base == null) return;
    final SensoryProfile next = base.copyWith(
      childName: _name.text.trim().isEmpty ? 'Child' : _name.text.trim(),
      masterVolumeCap: _volume,
      brightnessCap: _brightness,
      highCutHz: _highCut,
      disableWater: !_water,
      disableHighPiano: _softenHigh,
      preferredPreset: _sosMode,
      voiceEnabled: _voiceEnabled,
      visualMode: _visual,
      focusMinutes: _focusMinutes.round(),
      voiceGain: _voiceGain,
      voiceIntervalSec: _voiceInterval,
      blacklist: _rules.text
          .split('\n')
          .map((String r) => r.trim())
          .where((String r) => r.isNotEmpty)
          .toList(),
    );
    await widget.repository.saveProfile(next);
    if (!mounted) return;
    setState(() {
      _profile = next;
      _status = 'Profile saved. It applies to the next session.';
    });
  }

  Future<void> _copy(Future<String> Function() build, String label) async {
    final String text = await build();
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) setState(() => _status = '$label copied to the clipboard.');
  }

  Future<void> _saveFiles() async {
    try {
      final Directory dir = await getApplicationDocumentsDirectory();
      final File md =
          await ClinicalReportExporter(widget.repository).writeReports(dir);
      if (mounted) {
        setState(() =>
            _status = 'Saved CSV and Markdown reports next to ${md.path}');
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Could not save the report files.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ClinicalReportExporter exporter =
        ClinicalReportExporter(widget.repository);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Caregiver settings'),
        actions: <Widget>[
          IconButton(
            tooltip: 'What helps',
            icon: const Icon(Icons.insights_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext _) =>
                    InsightsScreen(repository: widget.repository),
              ),
            ),
          ),
        ],
      ),
      body: ReadableWidth(
        child: _profile == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: <Widget>[
                  TextField(
                    controller: _name,
                    decoration:
                        const InputDecoration(labelText: "Child's name"),
                  ),
                  const SizedBox(height: 16),
                  _slider(
                      'Maximum volume',
                      _volume,
                      0.1,
                      1.0,
                      '${(_volume * 100).round()}%',
                      (double v) => setState(() => _volume = v)),
                  _slider(
                      'Maximum screen brightness',
                      _brightness,
                      0.1,
                      1.0,
                      '${(_brightness * 100).round()}%',
                      (double v) => setState(() => _brightness = v)),
                  _slider(
                    'High-frequency cut',
                    _highCut < _noCut ? _noCut : _highCut,
                    _noCut,
                    4000,
                    _highCut == 0 ? 'off' : '${_highCut.round()} Hz',
                    (double v) => setState(() => _highCut = v),
                    trailing: TextButton(
                      onPressed: () => setState(() => _highCut = 0),
                      child: const Text('Off'),
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('Water sounds'),
                    value: _water,
                    onChanged: (bool v) => setState(() => _water = v),
                  ),
                  SwitchListTile(
                    title: const Text('Soften high tones (cap at 1.2 kHz)'),
                    value: _softenHigh,
                    onChanged: (bool v) => setState(() => _softenHigh = v),
                  ),
                  const SizedBox(height: 8),
                  Text('Animation',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  const Text(
                      'What your child sees. Tap the play button on a card to preview it full screen.'),
                  const SizedBox(height: 12),
                  VisualPicker(
                    value: _visual,
                    onChanged: (VisualMode v) => setState(() => _visual = v),
                  ),
                  const SizedBox(height: 8),
                  _slider(
                      'Focus timer',
                      _focusMinutes,
                      5,
                      60,
                      '${_focusMinutes.round()} min',
                      (double v) =>
                          setState(() => _focusMinutes = v.roundToDouble())),
                  const SizedBox(height: 8),
                  const Text('SOS button starts'),
                  const SizedBox(height: 8),
                  SegmentedButton<SessionPreset>(
                    segments: const <ButtonSegment<SessionPreset>>[
                      ButtonSegment<SessionPreset>(
                        value: SessionPreset.isoDownRegulator,
                        label: Text('Gradual calm-down'),
                      ),
                      ButtonSegment<SessionPreset>(
                        value: SessionPreset.deepCrisisAnchor,
                        label: Text('Deep crisis anchor'),
                      ),
                    ],
                    selected: <SessionPreset>{_sosMode},
                    onSelectionChanged: (Set<SessionPreset> v) =>
                        setState(() => _sosMode = v.first),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _rules,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Custom rules, one per line',
                      helperText:
                          "e.g. 'Block frequencies > 1800 Hz' is applied automatically",
                    ),
                  ),
                  const Divider(height: 40),
                  if (kIsWeb)
                    const Text(
                        'Voice recording needs the mobile app (the browser version has no microphone capture).')
                  else ...<Widget>[
                    Text('Familiar voice',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    const Text(
                        'Record up to four short phrases (6 seconds each), such as "You are safe, '
                        'take a deep breath". They stay on this device.'),
                    const SizedBox(height: 8),
                    for (int i = 0; i < VoiceWeaveEngine.maxSlots; i++)
                      _voiceSlot(i),
                    SwitchListTile(
                      title: const Text('Weave my voice into sessions'),
                      value: _voiceEnabled,
                      onChanged: (bool v) => setState(() => _voiceEnabled = v),
                    ),
                    _slider(
                        'Voice level',
                        _voiceGain,
                        0.04,
                        0.30,
                        '${(_voiceGain * 100).round()}%',
                        (double v) => setState(() => _voiceGain = v)),
                    _slider(
                        'Pause between phrases',
                        _voiceInterval,
                        15,
                        180,
                        '${_voiceInterval.round()} s',
                        (double v) =>
                            setState(() => _voiceInterval = v.roundToDouble())),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Save profile'),
                  ),
                  const Divider(height: 40),
                  Text('Therapy report',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: <Widget>[
                      OutlinedButton(
                        onPressed: () => _copy(exporter.toMarkdown, 'Report'),
                        child: const Text('Copy report'),
                      ),
                      OutlinedButton(
                        onPressed: () => _copy(exporter.toCsv, 'CSV'),
                        child: const Text('Copy CSV'),
                      ),
                      if (!kIsWeb)
                        OutlinedButton(
                            onPressed: _saveFiles,
                            child: const Text('Save to files')),
                    ],
                  ),
                  if (_status != null) ...<Widget>[
                    const SizedBox(height: 16),
                    Text(_status!),
                  ],
                  const Divider(height: 40),
                  const AboutSection(),
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }

  Widget _voiceSlot(int slot) {
    final bool recording = _recordingSlot == slot;
    final bool otherBusy = _busy || (_recordingSlot != null && !recording);
    final String subtitle = recording
        ? 'Recording... ${_secondsLeft}s left. Tap to stop.'
        : (_filled[slot] ? 'Recorded' : 'Empty');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
          _filled[slot] ? Icons.check_circle_rounded : Icons.circle_outlined),
      title: Text('Phrase ${slot + 1}'),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            tooltip: recording ? 'Stop recording' : 'Record phrase ${slot + 1}',
            onPressed: otherBusy ? null : () => _toggleRecording(slot),
            icon: Icon(
                recording ? Icons.stop_circle_rounded : Icons.mic_rounded,
                color: recording ? Colors.redAccent : null),
          ),
          IconButton(
            tooltip: 'Delete phrase ${slot + 1}',
            onPressed: otherBusy || recording || !_filled[slot]
                ? null
                : () => _deleteSlot(slot),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }

  Widget _slider(String label, double value, double min, double max,
      String readout, ValueChanged<double> onChanged,
      {Widget? trailing}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text('$label: $readout')),
            if (trailing != null) trailing,
          ],
        ),
        Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            onChanged: onChanged),
      ],
    );
  }
}
