import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../core/models/sensory_state.dart';
import '../../data/models.dart';
import '../screens/visual_preview_screen.dart';
import '../visual_catalog.dart';
import 'sensory_shader_view.dart';

/// Grid of selectable animations with a thumbnail, a one-line description and a full-screen
/// preview. Thumbnails use the cheap Canvas painters so a whole page of them stays light.
class VisualPicker extends StatefulWidget {
  const VisualPicker({super.key, required this.value, required this.onChanged});

  final VisualMode value;
  final ValueChanged<VisualMode> onChanged;

  @override
  State<VisualPicker> createState() => _VisualPickerState();
}

class _VisualPickerState extends State<VisualPicker> {
  /// A fixed moment in the animation so every thumbnail is a pleasant still.
  final ValueNotifier<double> _still = ValueNotifier<double>(34);

  @override
  void dispose() {
    _still.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        const double gap = 12;
        final int columns = box.maxWidth >= 560 ? 3 : 2;
        final double width = (box.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (final VisualOption o in kVisualOptions)
              SizedBox(
                width: width,
                child: _OptionCard(
                  option: o,
                  selected: o.mode == widget.value,
                  still: _still,
                  onTap: () => widget.onChanged(o.mode),
                  onPreview: o.mode == VisualMode.auto
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (BuildContext _) =>
                                  VisualPreviewScreen(option: o),
                            ),
                          ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.option,
    required this.selected,
    required this.still,
    required this.onTap,
    required this.onPreview,
  });

  final VisualOption option;
  final bool selected;
  final ValueListenable<double> still;
  final VoidCallback onTap;
  final VoidCallback? onPreview;

  Widget _thumbnail() {
    final ShaderKind? kind = option.shader;
    if (option.mode == VisualMode.auto) {
      // A 2x2 of the four classic animations: "chosen for you".
      const List<ShaderKind> classic = <ShaderKind>[
        ShaderKind.tunnel,
        ShaderKind.bubbles,
        ShaderKind.lanterns,
        ShaderKind.breathingOrb,
      ];
      return GridView.count(
        crossAxisCount: 2,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: <Widget>[
          for (final ShaderKind k in classic)
            CustomPaint(
                painter:
                    FallbackSensoryPainter(kind: k, time: still, dim: 1.0)),
        ],
      );
    }
    if (kind == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
            child: Icon(Icons.visibility_off_rounded,
                color: Colors.white24, size: 32)),
      );
    }
    return CustomPaint(
        painter: FallbackSensoryPainter(kind: kind, time: still, dim: 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '${option.title}. ${option.description}',
      child: Material(
        color: scheme.surfaceContainerHighest.withAlpha(60),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected
                ? scheme.primary
                : scheme.outlineVariant.withAlpha(120),
            width: selected ? 2.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AspectRatio(
                aspectRatio: 16 / 10,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    ClipRect(child: _thumbnail()),
                    if (selected)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: CircleAvatar(
                          radius: 12,
                          backgroundColor: scheme.primary,
                          child: Icon(Icons.check_rounded,
                              size: 16, color: scheme.onPrimary),
                        ),
                      ),
                    if (onPreview != null)
                      Positioned(
                        right: 4,
                        top: 4,
                        child: IconButton.filledTonal(
                          tooltip: 'Preview ${option.title}',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.play_arrow_rounded),
                          onPressed: onPreview,
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(option.title,
                        style: text.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(option.description,
                        style: text.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
