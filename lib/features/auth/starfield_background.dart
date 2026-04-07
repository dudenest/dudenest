import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Animated deep-space background: twinkling stars + curved connecting lines.
/// Designed to evoke a "Nest" constellation — nodes briefly joined by thin tendrils.
class StarfieldBackground extends StatefulWidget {
  final Widget child;
  const StarfieldBackground({super.key, required this.child});
  @override
  State<StarfieldBackground> createState() => _StarfieldBackgroundState();
}

class _StarfieldBackgroundState extends State<StarfieldBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late List<_Star> _stars;
  static const _count = 72;
  static const _connectDist = 220.0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 12))
      ..repeat();
    final rng = math.Random(7);
    _stars = List.generate(_count, (_) => _Star(
      x: rng.nextDouble(),
      y: rng.nextDouble(),
      size: 0.8 + rng.nextDouble() * 2.2,
      phase: rng.nextDouble() * math.pi * 2,
      speed: 0.25 + rng.nextDouble() * 0.6,
      curveSeed: rng.nextDouble() * math.pi * 2,
    ));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Container(color: const Color(0xFF060C1A)),
      AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => CustomPaint(
          painter: _StarfieldPainter(_stars, _ctrl.value, _connectDist),
          size: Size.infinite,
        ),
      ),
      widget.child,
    ]);
  }
}

class _Star {
  final double x, y, size, phase, speed, curveSeed;
  const _Star({required this.x, required this.y, required this.size,
    required this.phase, required this.speed, required this.curveSeed});
}

class _StarfieldPainter extends CustomPainter {
  final List<_Star> stars;
  final double t;
  final double maxDist;
  _StarfieldPainter(this.stars, this.t, this.maxDist);

  @override
  void paint(Canvas canvas, Size size) {
    final positions = <Offset>[];
    final alphas = <double>[];
    for (final s in stars) {
      final a = (math.sin(t * math.pi * 2 * s.speed + s.phase) * 0.5 + 0.5).clamp(0.0, 1.0);
      positions.add(Offset(s.x * size.width, s.y * size.height));
      alphas.add(a);
    }

    // Draw curved connections (behind stars)
    for (int i = 0; i < stars.length; i++) {
      for (int j = i + 1; j < stars.length; j++) {
        final d = (positions[i] - positions[j]).distance;
        if (d > maxDist) continue;
        final lineA = alphas[i] * alphas[j] * (1 - d / maxDist) * 0.35;
        if (lineA < 0.025) continue;
        final si = stars[i];
        final sj = stars[j];
        final mid = (positions[i] + positions[j]) / 2;
        // Perpendicular offset — animated slowly, unique per pair
        final dx = positions[j].dx - positions[i].dx;
        final dy = positions[j].dy - positions[i].dy;
        final len = math.sqrt(dx * dx + dy * dy);
        final nx = -dy / len; final ny = dx / len; // unit normal
        final curveMag = d * 0.12 * math.sin(t * math.pi * 2 * 0.3 + si.curveSeed + sj.curveSeed);
        final ctrl = Offset(mid.dx + nx * curveMag, mid.dy + ny * curveMag);
        final path = Path()
          ..moveTo(positions[i].dx, positions[i].dy)
          ..quadraticBezierTo(ctrl.dx, ctrl.dy, positions[j].dx, positions[j].dy);
        canvas.drawPath(path, Paint()
          ..color = Color.fromRGBO(90, 140, 255, lineA)
          ..strokeWidth = 0.55
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round);
      }
    }

    // Draw stars
    for (int i = 0; i < stars.length; i++) {
      final a = alphas[i];
      final p = positions[i];
      final s = stars[i];
      // Soft glow halo
      canvas.drawCircle(p, s.size * 3.5, Paint()
        ..color = Color.fromRGBO(110, 160, 255, a * 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
      // Star core — slightly warm white with blue tint
      canvas.drawCircle(p, s.size, Paint()
        ..color = Color.fromRGBO(210, 225, 255, a * 0.88));
    }
  }

  @override
  bool shouldRepaint(_StarfieldPainter old) => old.t != t;
}
