import 'package:flutter/material.dart';

import '../../core/models/sensory_state.dart';
import '../visual_catalog.dart';
import '../widgets/sensory_shader_view.dart';

/// Full-screen preview of one animation for the caregiver. No audio, no session, nothing
/// is saved; tap the screen to try the touch effect, use the close button to leave.
class VisualPreviewScreen extends StatefulWidget {
  const VisualPreviewScreen({super.key, required this.option});

  final VisualOption option;

  @override
  State<VisualPreviewScreen> createState() => _VisualPreviewScreenState();
}

class _VisualPreviewScreenState extends State<VisualPreviewScreen> {
  final ShaderTouchSource _touch = ShaderTouchSource();

  @override
  void dispose() {
    _touch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ShaderKind? kind = widget.option.shader;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (kind != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (TapDownDetails d) => _touch.touch(d.localPosition),
              onPanUpdate: (DragUpdateDetails d) =>
                  _touch.touch(d.localPosition),
              child: SensoryShaderView(kind: kind, touchSource: _touch),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: <Widget>[
                  IconButton.filledTonal(
                    tooltip: 'Close preview',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 12),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0x55000000),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      child: Text(
                        '${widget.option.title} · preview',
                        style: const TextStyle(
                            color: Color(0xCCFFFFFF),
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
