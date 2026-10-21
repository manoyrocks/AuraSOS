import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/audio/audio_engine.dart';
import '../../core/audio/voice_weave.dart';
import '../../core/models/sensory_state.dart';
import '../../data/models.dart';
import '../../data/sensory_profile_repository.dart';
import '../../data/voice_library.dart';
import '../launch_intent.dart';
import '../mode_labels.dart';
import '../widgets/mode_icons.dart';
import 'parent_screen.dart';
import 'session_screen.dart';

/// Zero-clutter home: one giant SOS button, plus Focus, Calm and Deep-Crisis icon buttons.
/// Tapping navigates synchronously; the session loads its profile in the background.
class HomeSosScreen extends StatefulWidget {
  const HomeSosScreen({
    super.key,
    required this.audio,
    required this.repository,
    required this.library,
    this.sosPreset = SessionPreset.isoDownRegulator,
    this.launchMode,
    this.shortcutRequests,
  });

  final AudioEngine audio;
  final SensoryProfileRepository repository;
  final VoiceLibrary library;

  /// Session to start immediately (home-screen shortcut), or null to just show the home screen.
  final LaunchMode? launchMode;

  /// Taps on the app-icon menu while the app is open (Android / iOS).
  final ShortcutRequests? shortcutRequests;

  /// Preset launched by the big SOS button until the caregiver's choice has loaded.
  final SessionPreset sosPreset;

  @override
  State<HomeSosScreen> createState() => _HomeSosScreenState();
}

class _HomeSosScreenState extends State<HomeSosScreen> {
  late SessionPreset _sos = widget.sosPreset;

  @override
  void initState() {
    super.initState();
    widget.shortcutRequests?.addListener(_onShortcutRequest);
    _startup();
  }

  @override
  void dispose() {
    widget.shortcutRequests?.removeListener(_onShortcutRequest);
    super.dispose();
  }

  void _onShortcutRequest() {
    final ShortcutRequests? requests = widget.shortcutRequests;
    final LaunchMode? mode = requests?.value;
    if (mode == null) return;
    requests!.value = null; // consumed either way
    // Only start from the home screen; never interrupt a session or the caregiver settings.
    if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
      _launchMode(mode);
    }
  }

  void _launchMode(LaunchMode mode) {
    switch (mode) {
      case LaunchMode.sos:
        _launch(context, _sos);
      case LaunchMode.focus:
        _launch(context, SessionPreset.focusClassroom);
      case LaunchMode.calm:
        _launch(context, SessionPreset.calmStim);
      case LaunchMode.deep:
        _launch(context, SessionPreset.deepCrisisAnchor);
    }
  }

  bool _launchedFromShortcut = false;

  /// Loads the caregiver's SOS choice in the background; when started from a shortcut it then
  /// begins the requested session (SOS waits briefly for the choice so the right mode starts).
  Future<void> _startup() async {
    final LaunchMode? mode = widget.launchMode;
    if (mode == LaunchMode.sos) {
      await _loadSosPreset()
          .timeout(const Duration(milliseconds: 300), onTimeout: () {});
    } else {
      unawaited(_loadSosPreset());
    }
    if (mode == null || _launchedFromShortcut || !mounted) return;
    _launchedFromShortcut = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _launchMode(mode);
    });
  }

  /// Read in the background so the SOS tap never waits on the database.
  Future<void> _loadSosPreset() async {
    try {
      final SensoryProfile profile = await widget.repository.activeProfile();
      final SessionPreset chosen = profile.preferredPreset;
      final bool sosCapable = chosen == SessionPreset.isoDownRegulator ||
          chosen == SessionPreset.deepCrisisAnchor;
      if (mounted && sosCapable) setState(() => _sos = chosen);
    } catch (_) {
      // Keep the default; the child must never see an error.
    }
  }

  void _launch(BuildContext context, SessionPreset preset) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 150),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder:
            (BuildContext _, Animation<double> __, Animation<double> ___) =>
                SessionScreen(
          preset: preset,
          audio: widget.audio,
          repository: widget.repository,
          library: widget.library,
        ),
        transitionsBuilder: (BuildContext _, Animation<double> anim,
                Animation<double> __, Widget child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      body: SafeArea(
        child: Stack(children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(20),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints box) {
                final Widget sos = _BigButton(
                  semanticLabel: 'SOS',
                  label: 'SOS',
                  sublabel: modeLabel(_sos),
                  colors: const <Color>[Color(0xFFF08077), Color(0xFFC94A5A)],
                  kind: ModeIconKind.sos,
                  iconSize: 170,
                  circle: true,
                  onTap: () => _launch(context, _sos),
                );
                final List<Widget> modes = <Widget>[
                  _BigButton(
                    semanticLabel: 'Focus',
                    label: modeLabel(SessionPreset.focusClassroom),
                    colors: const <Color>[Color(0xFF5AA0E0), Color(0xFF2F5FA8)],
                    kind: ModeIconKind.focus,
                    iconSize: 72,
                    onTap: () => _launch(context, SessionPreset.focusClassroom),
                  ),
                  _BigButton(
                    semanticLabel: 'Calm',
                    label: modeLabel(SessionPreset.calmStim),
                    colors: const <Color>[Color(0xFF5CC6A8), Color(0xFF2F8A7E)],
                    kind: ModeIconKind.calm,
                    iconSize: 72,
                    onTap: () => _launch(context, SessionPreset.calmStim),
                  ),
                  _BigButton(
                    semanticLabel: 'Deep crisis',
                    label: modeLabel(SessionPreset.deepCrisisAnchor),
                    colors: const <Color>[Color(0xFF5A5688), Color(0xFF2B2745)],
                    kind: ModeIconKind.deep,
                    iconSize: 72,
                    onTap: () =>
                        _launch(context, SessionPreset.deepCrisisAnchor),
                  ),
                ];

                // Landscape (phone on its side, tablet, desktop window): a round SOS on the
                // left and the three modes stacked on the right, instead of stretched bars.
                if (box.maxWidth > box.maxHeight * 1.2) {
                  return Row(
                    children: <Widget>[
                      Expanded(
                        flex: 3,
                        child: Center(
                            child: AspectRatio(aspectRatio: 1, child: sos)),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        flex: 2,
                        // Leave the corner free for the caregiver gate so no mode button
                        // has a dead zone under it.
                        child: Padding(
                          padding: const EdgeInsets.only(top: 44),
                          child: Column(
                            children: <Widget>[
                              for (int i = 0;
                                  i < modes.length;
                                  i++) ...<Widget>[
                                if (i > 0) const SizedBox(height: 16),
                                Expanded(child: modes[i]),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                }

                return Column(
                  children: <Widget>[
                    Expanded(flex: 3, child: sos),
                    const SizedBox(height: 20),
                    Expanded(
                      flex: 1,
                      child: Row(
                        children: <Widget>[
                          for (int i = 0; i < modes.length; i++) ...<Widget>[
                            if (i > 0) const SizedBox(width: 16),
                            Expanded(child: modes[i]),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: _ParentGate(
              onOpen: () => Navigator.of(context)
                  .push(
                    MaterialPageRoute<void>(
                      builder: (BuildContext _) => ParentScreen(
                        repository: widget.repository,
                        library: widget.library,
                        voice: widget.audio is VoiceWeaveEngine
                            ? widget.audio as VoiceWeaveEngine
                            : null,
                      ),
                    ),
                  )
                  .then((_) => _loadSosPreset()),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Faint caregiver entry: needs a continuous 3-second hold, so taps and slaps never open it.
class _ParentGate extends StatefulWidget {
  const _ParentGate({required this.onOpen});

  final VoidCallback onOpen;

  @override
  State<_ParentGate> createState() => _ParentGateState();
}

class _ParentGateState extends State<_ParentGate> {
  Timer? _timer;

  void _begin(PointerDownEvent _) {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 3), widget.onOpen);
  }

  void _cancel(PointerEvent _) {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _begin,
      onPointerUp: _cancel,
      onPointerCancel: _cancel,
      child: const SizedBox(
        width: 56,
        height: 56,
        child: Icon(Icons.settings_rounded, color: Color(0x33FFFFFF), size: 22),
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.semanticLabel,
    required this.label,
    this.sublabel,
    required this.colors,
    required this.kind,
    required this.iconSize,
    required this.onTap,
    this.circle = false,
  });

  final String semanticLabel;

  /// Visible name of the mode.
  final String label;

  /// Optional second line (the SOS button shows which calming mode it starts).
  final String? sublabel;
  final List<Color> colors;
  final ModeIconKind kind;
  final double iconSize;
  final VoidCallback onTap;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final ShapeBorder shape = circle
        ? const StadiumBorder()
        : RoundedRectangleBorder(borderRadius: BorderRadius.circular(36));
    return Semantics(
      button: true,
      label: sublabel == null ? semanticLabel : '$semanticLabel, $sublabel',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: shape,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          shadows: <BoxShadow>[
            BoxShadow(
              color: colors.last.withAlpha(90),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: shape,
            splashColor: Colors.white24,
            highlightColor: Colors.white10,
            onTap: onTap,
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints box) {
                // Short, wide buttons (landscape stack) put the label beside the icon.
                final bool sideBySide = box.maxWidth > box.maxHeight * 1.5;
                final double icon = sideBySide
                    ? math.min(iconSize, box.maxHeight * 0.62)
                    : math.min(iconSize,
                        math.min(box.maxHeight * 0.5, box.maxWidth * 0.62));
                final double fontSize = circle || iconSize > 100
                    ? 34
                    : math.max(13, math.min(20, box.maxWidth * 0.16));
                final Widget text = Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: sideBySide
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        color: Colors.white.withAlpha(240),
                        fontSize: fontSize,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                    if (sublabel != null)
                      Text(
                        sublabel!,
                        maxLines: 1,
                        style: TextStyle(
                          color: Colors.white.withAlpha(190),
                          fontSize: math.max(13, fontSize * 0.5),
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.3,
                        ),
                      ),
                  ],
                );
                final Widget content = sideBySide
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          ModeIcon(kind: kind, size: icon),
                          const SizedBox(width: 14),
                          Flexible(child: text),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          ModeIcon(kind: kind, size: icon),
                          SizedBox(height: math.max(4, icon * 0.06)),
                          text,
                        ],
                      );
                return Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                        padding: const EdgeInsets.all(8), child: content),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
