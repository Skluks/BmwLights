import 'package:flutter/material.dart';

import '../model/lamp.dart';

Color lampColor(LampColor c) => switch (c) {
      LampColor.white => const Color(0xFFE8F4FF),
      LampColor.amber => const Color(0xFFFFA726),
      LampColor.red => const Color(0xFFFF3B30),
    };

/// Top-down E60 silhouette with lamps; lit lamps glow.
class CarView extends StatelessWidget {
  const CarView({super.key, required this.lit, this.available, this.height = 260, this.onTapLamp});

  final Set<Lamp> lit;

  /// Lamps that have a mapping; others are drawn faded. Null = all.
  final Set<Lamp>? available;
  final double height;
  final void Function(Lamp lamp)? onTapLamp;

  static const _aspect = 0.45; // width / height

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: LayoutBuilder(builder: (context, c) {
        final h = height;
        final w = h * _aspect;
        final left = (c.maxWidth - w) / 2;
        return GestureDetector(
          onTapUp: onTapLamp == null
              ? null
              : (d) {
                  final p = d.localPosition - Offset(left, 0);
                  Lamp? best;
                  var bestDist = double.infinity;
                  for (final l in Lamp.values) {
                    final dist = (Offset(l.pos.dx * w, l.pos.dy * h) - p).distance;
                    if (dist < bestDist) {
                      bestDist = dist;
                      best = l;
                    }
                  }
                  if (best != null && bestDist < 24) onTapLamp!(best);
                },
          child: CustomPaint(
            size: Size(c.maxWidth, h),
            painter: _CarPainter(lit, available, left, w, h, Theme.of(context).colorScheme),
          ),
        );
      }),
    );
  }
}

class _CarPainter extends CustomPainter {
  _CarPainter(this.lit, this.available, this.left, this.w, this.h, this.scheme);

  final Set<Lamp> lit;
  final Set<Lamp>? available;
  final double left, w, h;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(left, 0);

    final body = RRect.fromRectAndCorners(
      Rect.fromLTWH(w * 0.04, h * 0.01, w * 0.92, h * 0.98),
      topLeft: Radius.circular(w * 0.28),
      topRight: Radius.circular(w * 0.28),
      bottomLeft: Radius.circular(w * 0.2),
      bottomRight: Radius.circular(w * 0.2),
    );
    canvas.drawRRect(body, Paint()..color = const Color(0xFF263238));
    canvas.drawRRect(
        body,
        Paint()
          ..color = const Color(0xFF546E7A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);

    // Mirrors
    final mirror = Paint()..color = const Color(0xFF37474F);
    canvas.drawRRect(RRect.fromRectXY(Rect.fromLTWH(-w * 0.02, h * 0.21, w * 0.08, h * 0.03), 4, 4), mirror);
    canvas.drawRRect(RRect.fromRectXY(Rect.fromLTWH(w * 0.94, h * 0.21, w * 0.08, h * 0.03), 4, 4), mirror);

    // Glass
    final glass = Paint()..color = const Color(0xFF102027);
    canvas.drawRRect(
        RRect.fromRectXY(Rect.fromLTRB(w * 0.14, h * 0.25, w * 0.86, h * 0.38), w * 0.1, w * 0.1), glass);
    canvas.drawRRect(
        RRect.fromRectXY(Rect.fromLTRB(w * 0.16, h * 0.72, w * 0.84, h * 0.82), w * 0.08, w * 0.08), glass);
    // Hood line / kidneys
    final line = Paint()
      ..color = const Color(0xFF455A64)
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(w * 0.3, h * 0.06), Offset(w * 0.32, h * 0.22), line);
    canvas.drawLine(Offset(w * 0.7, h * 0.06), Offset(w * 0.68, h * 0.22), line);
    final kidney = Paint()..color = const Color(0xFF90A4AE);
    canvas.drawRRect(RRect.fromRectXY(Rect.fromLTWH(w * 0.41, h * 0.012, w * 0.08, h * 0.018), 3, 3), kidney);
    canvas.drawRRect(RRect.fromRectXY(Rect.fromLTWH(w * 0.51, h * 0.012, w * 0.08, h * 0.018), 3, 3), kidney);

    for (final lamp in Lamp.values) {
      final c = Offset(lamp.pos.dx * w, lamp.pos.dy * h);
      final on = lit.contains(lamp);
      final usable = available == null || available!.contains(lamp);
      final col = lampColor(lamp.color);
      final r = w * 0.035;
      if (on) {
        canvas.drawCircle(
            c, r * 3.2, Paint()..shader = RadialGradient(colors: [col.withValues(alpha: 0.7), col.withValues(alpha: 0)])
                .createShader(Rect.fromCircle(center: c, radius: r * 3.2)));
        canvas.drawCircle(c, r, Paint()..color = col);
      } else {
        canvas.drawCircle(c, r, Paint()..color = col.withValues(alpha: usable ? 0.22 : 0.07));
        canvas.drawCircle(
            c,
            r,
            Paint()
              ..color = col.withValues(alpha: usable ? 0.6 : 0.15)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CarPainter old) =>
      old.lit != lit || old.available != available || old.w != w || old.left != left;
}
