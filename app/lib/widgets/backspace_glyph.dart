import 'package:flutter/widgets.dart';

/// "⌫" of the password keypad, drawn so that its cross can be half the size
/// of the font glyph's cross (owner decision, 30.10.2026). [size] is the
/// font size the "⌫" text had.
class BackspaceGlyph extends StatelessWidget {
  const BackspaceGlyph({
    required this.size,
    required this.color,
    this.shadow,
    super.key,
  });

  final double size;
  final Color color;
  final Shadow? shadow;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(size * 0.92, size * 0.65),
        painter: _BackspacePainter(color: color, shadow: shadow),
      );
}

class _BackspacePainter extends CustomPainter {
  const _BackspacePainter({required this.color, this.shadow});

  final Color color;
  final Shadow? shadow;

  /// Half extent of the cross relative to the glyph height; the font glyph's
  /// cross runs corner to corner of the box (0.5).
  static const crossHalf = 0.25;

  void paintGlyph(Canvas canvas, Size size, Paint paint) {
    final w = size.width;
    final h = size.height;
    final inset = paint.strokeWidth / 2;
    final outline = Path()
      ..moveTo(inset, h / 2)
      ..lineTo(w * 0.35, inset)
      ..lineTo(w - inset, inset)
      ..lineTo(w - inset, h - inset)
      ..lineTo(w * 0.35, h - inset)
      ..close();
    canvas.drawPath(outline, paint);
    final center = Offset(w * 0.675, h / 2);
    final d = h * crossHalf;
    canvas.drawLine(center + Offset(-d, -d), center + Offset(d, d), paint);
    canvas.drawLine(center + Offset(-d, d), center + Offset(d, -d), paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    Paint stroke(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.height * 0.085
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final shadow = this.shadow;
    if (shadow != null) {
      canvas.save();
      canvas.translate(shadow.offset.dx, shadow.offset.dy);
      paintGlyph(canvas, size, stroke(shadow.color));
      canvas.restore();
    }
    paintGlyph(canvas, size, stroke(color));
  }

  @override
  bool shouldRepaint(_BackspacePainter old) =>
      old.color != color || old.shadow != shadow;
}
