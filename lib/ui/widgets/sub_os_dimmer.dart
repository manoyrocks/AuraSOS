import 'package:flutter/widgets.dart';

/// Software dimmer below the OS brightness floor: a black, non-interactive overlay.
/// [luminance] 0.02..1.0 maps to overlay alpha `1 - luminance`, clamped to 0..0.98.
class SubOsDimmer extends StatelessWidget {
  const SubOsDimmer({super.key, required this.luminance, required this.child});

  final double luminance;
  final Widget child;

  static double alphaFor(double luminance) {
    if (luminance.isNaN) return 0.0;
    return (1.0 - luminance).clamp(0.0, 0.98).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final int alpha = (alphaFor(luminance) * 255).round();
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        child,
        if (alpha > 0)
          IgnorePointer(
            child: ColoredBox(color: Color.fromARGB(alpha, 0, 0, 0)),
          ),
      ],
    );
  }
}
