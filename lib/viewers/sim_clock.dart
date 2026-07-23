import 'dart:math';
import 'dart:ui';

import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart';

/// Drives the fake per-frame animation for the canvas viewers (image
/// scene, IMU cube, laser scan, point cloud, odometry trail, graph),
/// standing in for real live message data until DDS is wired up.
///
/// Ported from the `_frame`/`_draw*` logic in the HandyROS.dc.html
/// design mockup.
class SimClock extends ChangeNotifier {
  double t = 0;
  Offset _prev = Offset.zero;
  double ox = 0, oy = 0, oth = 0, vx = 0, vy = 0;
  final List<Offset> trail = [];
  double laserMin = 0;
  double imgFps = 30;
  final List<double> graphHistory = List.generate(120, (_) => 50);
  double graphVal = 50;

  Ticker? _ticker;
  double _lastSeconds = 0;

  void start(TickerProvider vsync) {
    _ticker = vsync.createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final es = elapsed.inMicroseconds / 1e6;
    final dt = _lastSeconds == 0 ? 0.016 : (es - _lastSeconds).clamp(0.0, 0.05);
    _lastSeconds = es;
    t += dt;

    final nx = 2.0 * sin(t * 0.35), ny = 1.4 * sin(t * 0.7);
    if (dt > 0) {
      vx = (nx - _prev.dx) / dt;
      vy = (ny - _prev.dy) / dt;
    }
    _prev = Offset(nx, ny);
    ox = nx;
    oy = ny;
    oth = atan2(vy, vx);
    trail.add(Offset(nx, ny));
    if (trail.length > 260) trail.removeAt(0);

    graphHistory.add(50 + 38 * sin(t * 1.4) + (Random().nextDouble() * 6 - 3));
    if (graphHistory.length > 120) graphHistory.removeAt(0);
    graphVal = graphHistory.last;

    notifyListeners();
  }

  ({double r, double p, double y}) euler() => (
    r: 0.38 * sin(t * 0.7),
    p: 0.30 * sin(t * 0.9 + 1),
    y: (t * 0.35) % (pi * 2) - pi,
  );

  ({double w, double x, double y, double z}) quat() {
    final e = euler();
    final cr = cos(e.r / 2), sr = sin(e.r / 2);
    final cp = cos(e.p / 2), sp = sin(e.p / 2);
    final cy = cos(e.y / 2), sy = sin(e.y / 2);
    return (
      w: cr * cp * cy + sr * sp * sy,
      x: sr * cp * cy - cr * sp * sy,
      y: cr * sp * cy + sr * cp * sy,
      z: cr * cp * sy - sr * sp * cy,
    );
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }
}

/// Rotates a 3D vector by roll/pitch/yaw, matching the design's `_rot`.
({double x, double y, double z}) rotRPY(
  ({double x, double y, double z}) v,
  ({double r, double p, double y}) e,
) {
  double x = v.x, y = v.y, z = v.z;
  double c = cos(e.r), s = sin(e.r);
  final y1 = y * c - z * s, z1 = y * s + z * c;
  y = y1;
  z = z1;
  c = cos(e.p);
  s = sin(e.p);
  final x1 = x * c + z * s, z2 = -x * s + z * c;
  x = x1;
  z = z2;
  c = cos(e.y);
  s = sin(e.y);
  final x2 = x * c - y * s, y2 = x * s + y * c;
  x = x2;
  y = y2;
  return (x: x, y: y, z: z);
}
