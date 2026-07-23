import 'dart:math';

import 'package:flutter/material.dart';
import '../app/theme.dart';
import '../models/live_payload.dart';
import 'live_payload_controller.dart';
import 'sim_clock.dart';

typedef Vec3 = ({double x, double y, double z});

void _dashedLine(
  Canvas canvas,
  Offset a,
  Offset b,
  Paint paint,
  double dash,
  double gap,
  double offset,
) {
  final total = (b - a).distance;
  if (total == 0) return;
  final dir = (b - a) / total;
  double dist = offset % (dash + gap);
  if (dist < 0) dist += dash + gap;
  while (dist < total) {
    final segStart = (dist).clamp(0, total);
    final segEnd = (dist + dash).clamp(0, total);
    if (segEnd > segStart) {
      canvas.drawLine(
        a + dir * segStart.toDouble(),
        a + dir * segEnd.toDouble(),
        paint,
      );
    }
    dist += dash + gap;
  }
}

void _paintWaitingState(Canvas canvas, Size size, String message) {
  final tp = TextPainter(
    text: TextSpan(
      text: message,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.ink3,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: size.width - 32);
  tp.paint(
    canvas,
    Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2),
  );
}

/// Camera feed for sensor_msgs/Image — draws the decoded ui.Image
/// LivePayloadController prepared off the UI thread. Falls back to a
/// procedural demo scene when no live DDS connection is available.
class ImageScenePainter extends CustomPainter {
  final LivePayloadController controller;
  ImageScenePainter(this.controller) : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    if (!controller.isLive) {
      _paintDemo(canvas, size, controller.sim!);
      return;
    }
    final img = controller.decodedImage;
    if (img == null) {
      _paintWaitingState(
        canvas,
        size,
        controller.imageDecodeError ?? 'waiting for first frame…',
      );
      return;
    }
    final src = Rect.fromLTWH(
      0,
      0,
      img.width.toDouble(),
      img.height.toDouble(),
    );
    final fit = applyBoxFit(
      BoxFit.contain,
      Size(img.width.toDouble(), img.height.toDouble()),
      size,
    );
    final dstSize = fit.destination;
    final dst = Rect.fromLTWH(
      (size.width - dstSize.width) / 2,
      (size.height - dstSize.height) / 2,
      dstSize.width,
      dstSize.height,
    );
    canvas.drawImageRect(
      img,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  void _paintDemo(Canvas canvas, Size size, SimClock sim) {
    final w = size.width, h = size.height, t = sim.t;
    final full = Rect.fromLTWH(0, 0, w, h);

    canvas.drawRect(
      full,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF12314F),
            Color(0xFF284B63),
            Color(0xFF3A3F33),
            Color(0xFF1C1A12),
          ],
          stops: [0, 0.5, 0.55, 1],
        ).createShader(full),
    );

    final sunCenter = Offset(w * 0.72, h * 0.28);
    canvas.drawRect(
      full,
      Paint()
        ..shader = RadialGradient(
          colors: const [Color(0xE6FFF0BE), Color(0x00FFF0BE)],
        ).createShader(Rect.fromCircle(center: sunCenter, radius: 90)),
    );

    final hz = h * 0.54;
    final road = Path()
      ..moveTo(w * 0.5 - 14, hz)
      ..lineTo(w * 0.5 + 14, hz)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(road, Paint()..color = const Color(0xFF20241F));

    _dashedLine(
      canvas,
      Offset(w * 0.5, hz),
      Offset(w * 0.5, h),
      Paint()
        ..color = const Color(0xBFF0ECE0)
        ..strokeWidth = 3,
      16,
      16,
      -(t * 120) % 64,
    );

    final vx = w * 0.5 + sin(t * 0.8) * w * 0.16;
    final vy = hz + (h - hz) * 0.42;
    final vs = 1 + (vy - hz) / (h - hz);
    canvas.drawRect(
      Rect.fromLTWH(vx - 16 * vs, vy - 10 * vs, 32 * vs, 18 * vs),
      Paint()..color = const Color(0xFFC23B3B),
    );
    canvas.drawRect(
      Rect.fromLTWH(vx - 16 * vs, vy - 2 * vs, 32 * vs, 4 * vs),
      Paint()..color = const Color(0xFF7A1F1F),
    );

    final detRect = Rect.fromLTWH(vx - 20 * vs, vy - 14 * vs, 40 * vs, 26 * vs);
    canvas.drawRect(
      detRect,
      Paint()
        ..color = const Color(0xF25E8B82)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawRect(
      Rect.fromLTWH(vx - 20 * vs, vy - 26, 58, 14),
      Paint()..color = const Color(0xF25E8B82),
    );
    final tp = TextPainter(
      text: const TextSpan(
        text: 'car 0.98',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(vx - 17 * vs, vy - 24));

    final scan = Paint()..color = const Color(0x0F000000);
    for (double y = 0; y < h; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, w, 1), scan);
    }

    sim.imgFps = double.parse((29 + sin(t * 3)).toStringAsFixed(1));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 3D axis gizmo showing live orientation, matching the IMU viewer.
class ImuOrientationPainter extends CustomPainter {
  final LivePayloadController controller;
  ImuOrientationPainter(this.controller) : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    ({double r, double p, double y}) e;
    if (!controller.isLive) {
      e = controller.sim!.euler();
    } else {
      final imu = controller.imu;
      if (imu == null) {
        _paintWaitingState(canvas, size, 'waiting for first sample…');
        return;
      }
      final euler = imu.orientation.toEuler();
      e = (r: euler.roll, p: euler.pitch, y: euler.yaw);
    }

    final cx = size.width / 2, cy = size.height / 2;
    final l = min(size.width, size.height) * 0.30;

    final gridPaint = Paint()
      ..color = AppColors.shadowDark.withValues(alpha: .12)
      ..strokeWidth = 1;
    for (int i = -3; i <= 3; i++) {
      final a = rotRPY((x: i * 0.5, y: -1.6, z: 0), e);
      final b = rotRPY((x: i * 0.5, y: 1.6, z: 0), e);
      canvas.drawLine(
        Offset(cx + a.x * l, cy - a.y * l * 0.5 - a.z * l * 0.5),
        Offset(cx + b.x * l, cy - b.y * l * 0.5 - b.z * l * 0.5),
        gridPaint,
      );
    }

    Offset proj(Vec3 v) =>
        Offset(cx + v.x * l, cy - v.y * l * 0.55 - v.z * l * 0.75);
    final axes = <(Vec3, Color, String)>[
      ((x: 1.0, y: 0.0, z: 0.0), const Color(0xFFB3806E), 'X'),
      ((x: 0.0, y: 1.0, z: 0.0), const Color(0xFF7F9B6B), 'Y'),
      ((x: 0.0, y: 0.0, z: 1.0), const Color(0xFF6B83A6), 'Z'),
    ];
    final withDepth = axes.map((a) {
      final r = rotRPY(a.$1, e);
      return (color: a.$2, label: a.$3, point: proj(r), depth: r.z);
    }).toList()..sort((p, q) => p.depth.compareTo(q.depth));

    for (final item in withDepth) {
      canvas.drawLine(
        Offset(cx, cy),
        item.point,
        Paint()
          ..color = item.color
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(item.point, 7, Paint()..color = item.color);
      final tp = TextPainter(
        text: TextSpan(
          text: item.label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, item.point - Offset(tp.width / 2, tp.height / 2));
    }

    canvas.drawCircle(
      Offset(cx, cy),
      6,
      Paint()..color = const Color(0xFF8878A6),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 2D radar-style sweep for sensor_msgs/LaserScan.
class LaserScanPainter extends CustomPainter {
  final LivePayloadController controller;
  LaserScanPainter(this.controller) : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    if (!controller.isLive) {
      _paintDemo(canvas, size, controller.sim!);
      return;
    }
    final scan = controller.laserScan;
    if (scan == null) {
      _paintWaitingState(canvas, size, 'waiting for first scan…');
      return;
    }
    _paintReal(canvas, size, scan);
  }

  void _paintReal(Canvas canvas, Size size, LaserScanSample scan) {
    final cx = size.width / 2, cy = size.height / 2;
    final scale = min(size.width, size.height) * 0.16;

    final ringPaint = Paint()
      ..color = AppColors.shadowDark.withValues(alpha: .18)
      ..style = PaintingStyle.stroke;
    for (int r = 1; r <= 4; r++) {
      canvas.drawCircle(Offset(cx, cy), r * scale, ringPaint);
    }

    final pts = <(double a, double d)>[];
    double minD = double.infinity, minA = 0;
    for (var i = 0; i < scan.ranges.length; i++) {
      final r = scan.ranges[i];
      if (!r.isFinite || r < scan.rangeMin || r > scan.rangeMax) continue;
      final a = scan.angleMin + i * scan.angleIncrement;
      pts.add((a, r));
      if (r < minD) {
        minD = r;
        minA = a;
      }
    }

    if (pts.isEmpty) {
      _paintWaitingState(canvas, size, 'no valid ranges in this scan');
      return;
    }

    final fillPath = Path();
    for (var i = 0; i < pts.length; i++) {
      final (a, d) = pts[i];
      final p = Offset(cx + cos(a) * d * scale, cy + sin(a) * d * scale);
      if (i == 0) {
        fillPath.moveTo(p.dx, p.dy);
      } else {
        fillPath.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(fillPath, Paint()..color = const Color(0x247F9B6B));
    canvas.drawPath(
      fillPath,
      Paint()
        ..color = const Color(0x807F9B6B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    final ptPaint = Paint()..color = const Color(0xFF7F9B6B);
    for (final (a, d) in pts) {
      final p = Offset(cx + cos(a) * d * scale, cy + sin(a) * d * scale);
      canvas.drawRect(
        Rect.fromCenter(center: p, width: 2.6, height: 2.6),
        ptPaint,
      );
    }

    if (minD.isFinite) {
      final mx = cx + cos(minA) * minD * scale,
          my = cy + sin(minA) * minD * scale;
      canvas.drawLine(
        Offset(cx, cy),
        Offset(mx, my),
        Paint()
          ..color = const Color(0xFFB3806E)
          ..strokeWidth = 1.5,
      );
      canvas.drawCircle(
        Offset(mx, my),
        5,
        Paint()..color = const Color(0xFFB3806E),
      );
    }

    canvas.drawCircle(
      Offset(cx, cy),
      6,
      Paint()..color = const Color(0xFF5E8B82),
    );
  }

  void _paintDemo(Canvas canvas, Size size, SimClock sim) {
    final cx = size.width / 2, cy = size.height / 2;
    final scale = min(size.width, size.height) * 0.16;
    final t = sim.t, yaw = t * 0.15;

    final ringPaint = Paint()
      ..color = AppColors.shadowDark.withValues(alpha: .18)
      ..style = PaintingStyle.stroke;
    for (int r = 1; r <= 4; r++) {
      canvas.drawCircle(Offset(cx, cy), r * scale, ringPaint);
    }

    double dist(double a) {
      final dx = cos(a), dy = sin(a);
      const ax = 3.0, ay = 2.2;
      double d = min(
        (ax / (dx == 0 ? 1e-6 : dx)).abs(),
        (ay / (dy == 0 ? 1e-6 : dy)).abs(),
      );
      const ox = 1.4, oy = 0.6, orr = 0.5;
      final b = dx * (-ox) + dy * (-oy);
      final cc = ox * ox + oy * oy - orr * orr;
      final disc = b * b - cc;
      if (disc > 0) {
        final hDist = -b - sqrt(disc);
        if (hDist > 0 && hDist < d) d = hDist;
      }
      return d + sin(a * 9) * 0.03;
    }

    final pts = <(double a, double d)>[];
    double minD = 99, minA = 0;
    for (int i = 0; i < 360; i += 2) {
      final a = i * pi / 180;
      final d = dist(a - yaw);
      pts.add((a, d));
      if (d < minD) {
        minD = d;
        minA = a;
      }
    }

    final fillPath = Path();
    for (var i = 0; i < pts.length; i++) {
      final (a, d) = pts[i];
      final p = Offset(cx + cos(a) * d * scale, cy + sin(a) * d * scale);
      if (i == 0) {
        fillPath.moveTo(p.dx, p.dy);
      } else {
        fillPath.lineTo(p.dx, p.dy);
      }
    }
    fillPath.close();
    canvas.drawPath(fillPath, Paint()..color = const Color(0x247F9B6B));
    canvas.drawPath(
      fillPath,
      Paint()
        ..color = const Color(0x807F9B6B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    final ptPaint = Paint()..color = const Color(0xFF7F9B6B);
    for (final (a, d) in pts) {
      final p = Offset(cx + cos(a) * d * scale, cy + sin(a) * d * scale);
      canvas.drawRect(
        Rect.fromCenter(center: p, width: 2.6, height: 2.6),
        ptPaint,
      );
    }

    final mx = cx + cos(minA) * minD * scale,
        my = cy + sin(minA) * minD * scale;
    canvas.drawLine(
      Offset(cx, cy),
      Offset(mx, my),
      Paint()
        ..color = const Color(0xFFB3806E)
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(
      Offset(mx, my),
      5,
      Paint()..color = const Color(0xFFB3806E),
    );

    canvas.drawCircle(
      Offset(cx, cy),
      6,
      Paint()..color = const Color(0xFF5E8B82),
    );
    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx + cos(-yaw) * 22, cy + sin(-yaw) * 22),
      Paint()
        ..color = const Color(0xFF5E8B82)
        ..strokeWidth = 2,
    );

    sim.laserMin = minD;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Projected 3D point-cloud surface for sensor_msgs/PointCloud2. Real
/// clouds can carry hundreds of thousands of points — renders a fixed
/// budget (stride-sampled) regardless of source size, the same
/// resource-conscious reasoning as everywhere else in this feature.
class PointCloudPainter extends CustomPainter {
  final LivePayloadController controller;
  static const int _renderBudget = 5000;

  PointCloudPainter(this.controller) : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    if (!controller.isLive) {
      _paintDemo(canvas, size, controller.sim!);
      return;
    }
    final cloud = controller.pointCloud;
    if (cloud == null || cloud.pointCount == 0) {
      _paintWaitingState(canvas, size, 'waiting for first cloud…');
      return;
    }
    _paintReal(canvas, size, cloud);
  }

  void _paintReal(Canvas canvas, Size size, PointCloudSample cloud) {
    final cx = size.width / 2, cy = size.height / 2 + 10;
    final scale = min(size.width, size.height) * 0.5 * controller.cloudZoom;
    final stride = max(1, cloud.pointCount ~/ _renderBudget);
    final useRgb = cloud.colorMode == 'rgb';

    // User-controlled viewing angle — drag to rotate, pinch to zoom
    // (see the GestureDetector wired up in ViewerScreen). Defaults
    // match the old fixed angle, so the cloud looks the same before
    // anyone touches it.
    final e = (r: controller.cloudPitch, p: 0.0, y: controller.cloudYaw);

    final pts = <(Vec3 rotated, int colorBits)>[];
    for (int i = 0; i < cloud.pointCount; i += stride) {
      final x = cloud.xyz[i * 4],
          y = cloud.xyz[i * 4 + 1],
          z = cloud.xyz[i * 4 + 2];
      if (!x.isFinite || !y.isFinite || !z.isFinite) continue;
      final rotated = rotRPY((x: x, y: y, z: z), e);
      pts.add((rotated, useRgb ? cloud.colorBits[i * 4 + 3] : 0));
    }
    pts.sort((a, b) => a.$1.z.compareTo(b.$1.z));

    for (final (rotated, colorBits) in pts) {
      final persp = 1 / (2.4 + rotated.z.clamp(-2.0, 10.0));
      final sx = cx + rotated.x * scale * persp,
          sy = cy - rotated.y * scale * persp * 1.1;
      final Color color;
      if (useRgb) {
        final r = (colorBits >> 16) & 0xFF,
            g = (colorBits >> 8) & 0xFF,
            b = colorBits & 0xFF;
        color = Color.fromARGB(217, r, g, b);
      } else {
        final hue = (200 - (rotated.z + 0.6) * 150).clamp(0, 360).toDouble();
        color = HSVColor.fromAHSV(0.85, hue, 0.85, 0.6).toColor();
      }
      final r = 1.6 * persp * 2;
      canvas.drawRect(
        Rect.fromCenter(center: Offset(sx, sy), width: r * 2, height: r * 2),
        Paint()..color = color,
      );
    }
  }

  void _paintDemo(Canvas canvas, Size size, SimClock sim) {
    final cx = size.width / 2, cy = size.height / 2 + 10;
    final t = sim.t, yaw = t * 0.28;
    final scale = min(size.width, size.height) * 0.5;
    final e = (r: 0.9, p: 0.0, y: yaw);

    final pts = <(Vec3 rotated, double z)>[];
    for (int ix = -16; ix <= 16; ix++) {
      for (int iy = -14; iy <= 14; iy++) {
        final x = ix / 8, y = iy / 8;
        final z = 0.55 * sin(x * 1.6 + t * 0.4) * cos(y * 1.6);
        final rotated = rotRPY((x: x, y: y, z: z), e);
        pts.add((rotated, z));
      }
    }
    pts.sort((a, b) => a.$1.z.compareTo(b.$1.z));

    for (final (rotated, z) in pts) {
      final persp = 1 / (2.4 + rotated.z);
      final sx = cx + rotated.x * scale * persp,
          sy = cy - rotated.y * scale * persp * 1.1;
      final hue = (200 - (z + 0.6) * 150).clamp(0, 360).toDouble();
      final color = HSVColor.fromAHSV(0.85, hue, 0.85, 0.6).toColor();
      final r = 1.6 * persp * 2;
      canvas.drawRect(
        Rect.fromCenter(center: Offset(sx, sy), width: r * 2, height: r * 2),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Top-down trail view for nav_msgs/Odometry.
class OdomTrailPainter extends CustomPainter {
  final LivePayloadController controller;
  OdomTrailPainter(this.controller) : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    if (!controller.isLive) {
      _paintDemo(canvas, size, controller.sim!);
      return;
    }
    final odom = controller.odom;
    if (odom == null) {
      _paintWaitingState(canvas, size, 'waiting for first sample…');
      return;
    }

    final w = size.width, h = size.height;
    final cx = w / 2, cy = h / 2;
    final scale = min(w, h) * 0.14;

    _drawGrid(canvas, size, cx, cy, scale);

    final trail = controller.odomTrail;
    if (trail.isNotEmpty) {
      final path = Path();
      for (var i = 0; i < trail.length; i++) {
        final p = trail[i];
        final sp = Offset(cx + p.x * scale, cy - p.y * scale);
        if (i == 0) {
          path.moveTo(sp.dx, sp.dy);
        } else {
          path.lineTo(sp.dx, sp.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFFC2A05A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }

    final yaw = odom.orientation.toEuler().yaw;
    final rx = cx + odom.position.x * scale, ry = cy - odom.position.y * scale;
    canvas.save();
    canvas.translate(rx, ry);
    canvas.rotate(-yaw);
    final arrow = Path()
      ..moveTo(14, 0)
      ..lineTo(-9, -9)
      ..lineTo(-5, 0)
      ..lineTo(-9, 9)
      ..close();
    canvas.drawPath(arrow, Paint()..color = const Color(0xFF5E8B82));
    canvas.restore();
  }

  void _drawGrid(Canvas canvas, Size size, double cx, double cy, double scale) {
    final w = size.width, h = size.height;
    final gridPaint = Paint()
      ..color = AppColors.shadowDark.withValues(alpha: .12)
      ..strokeWidth = 1;
    for (int i = -4; i <= 4; i++) {
      canvas.drawLine(
        Offset(cx + i * scale, 0),
        Offset(cx + i * scale, h),
        gridPaint,
      );
      canvas.drawLine(
        Offset(0, cy + i * scale),
        Offset(w, cy + i * scale),
        gridPaint,
      );
    }
    final axisPaint = Paint()
      ..color = AppColors.shadowDark.withValues(alpha: .22);
    canvas.drawLine(Offset(cx, 0), Offset(cx, h), axisPaint);
    canvas.drawLine(Offset(0, cy), Offset(w, cy), axisPaint);
  }

  void _paintDemo(Canvas canvas, Size size, SimClock sim) {
    final w = size.width, h = size.height;
    final cx = w / 2, cy = h / 2;
    final scale = min(w, h) * 0.14;

    _drawGrid(canvas, size, cx, cy, scale);

    if (sim.trail.isNotEmpty) {
      final path = Path();
      for (var i = 0; i < sim.trail.length; i++) {
        final p = sim.trail[i];
        final sp = Offset(cx + p.dx * scale, cy - p.dy * scale);
        if (i == 0) {
          path.moveTo(sp.dx, sp.dy);
        } else {
          path.lineTo(sp.dx, sp.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFFC2A05A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }

    final rx = cx + sim.ox * scale, ry = cy - sim.oy * scale;
    canvas.save();
    canvas.translate(rx, ry);
    canvas.rotate(-sim.oth);
    final arrow = Path()
      ..moveTo(14, 0)
      ..lineTo(-9, -9)
      ..lineTo(-5, 0)
      ..lineTo(-9, 9)
      ..close();
    canvas.drawPath(arrow, Paint()..color = const Color(0xFF5E8B82));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Scrolling line chart used for scalar topics (Float32/Float64…).
/// Auto-scales to the visible history's own min/max rather than
/// assuming a fixed 0–100 range, since real scalar topics (voltage,
/// pressure, thrust) can be in any range.
class GraphPainter extends CustomPainter {
  final LivePayloadController controller;
  GraphPainter(this.controller) : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 16.0;
    final w = size.width, h = size.height;
    final gw = w - pad * 2, gh = h - pad * 2;

    final gridPaint = Paint()
      ..color = AppColors.shadowDark.withValues(alpha: .12);
    for (int i = 0; i <= 4; i++) {
      final y = pad + gh * i / 4;
      canvas.drawLine(Offset(pad, y), Offset(w - pad, y), gridPaint);
    }

    final history = controller.isLive
        ? controller.floatHistory
        : controller.sim!.graphHistory;
    if (history.length < 2) {
      _paintWaitingState(canvas, size, 'waiting for data…');
      return;
    }

    double minV = history.first, maxV = history.first, sum = 0;
    for (final v in history) {
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
      sum += v;
    }
    final mean = sum / history.length;
    // Stretching a signal's own min..max to fill 100% of the plot
    // height makes a nearly-flat value look like it's swinging wildly
    // — a pressure reading wobbling by 0.001 shouldn't fill the whole
    // screen. Floor the range to a fraction of the signal's own
    // magnitude so near-constant data reads as the flat line it is,
    // and keep 20% headroom top/bottom so genuine swings don't touch
    // the plot edges either.
    final rawRange = maxV - minV;
    final floor = mean.abs() * 0.08;
    final range = rawRange < floor ? (floor < 1e-9 ? 1.0 : floor) : rawRange;
    // Center on the data's own midpoint (not just minV) so widening a
    // near-flat range out to the floor doesn't bias the line low.
    final centerV = (minV + maxV) / 2;
    final displayRange = range / 0.6;
    final effectiveMin = centerV - displayRange / 2;

    final path = Path();
    for (var i = 0; i < history.length; i++) {
      final x = pad + gw * i / (history.length - 1);
      final y = pad + gh * (1 - (history[i] - effectiveMin) / displayRange);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF5E8B82)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    final fillPath = Path.from(path)
      ..lineTo(w - pad, h - pad)
      ..lineTo(pad, h - pad)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x381FE0D6), Color(0x001FE0D6)],
        ).createShader(Rect.fromLTWH(0, pad, w, gh)),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
