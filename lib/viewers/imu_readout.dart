import 'dart:math';

import 'package:flutter/material.dart';
import '../app/theme.dart';
import 'live_payload_controller.dart';

String _fmt(double n, [int d = 2]) => (n < 0 ? '' : ' ') + n.toStringAsFixed(d);

class ImuReadoutGrid extends StatelessWidget {
  final LivePayloadController controller;

  const ImuReadoutGrid({super.key, required this.controller});

  Widget _card(String title, Color color, String Function() value) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: panelDecoration(radius: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: AppText.disp(size: 9, color: color, letterSpacing: .7),
            ),
            const SizedBox(height: 5),
            Text(
              value(),
              style: AppText.mono(
                size: 13,
                weight: FontWeight.w700,
              ).copyWith(height: 1.25),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      constraints: const BoxConstraints(maxHeight: 236),
      child: SingleChildScrollView(
        child: GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 9,
          crossAxisSpacing: 9,
          childAspectRatio: 1.3,
          children: [
            _card('ORIENTATION (RPY)', AppColors.pink, () {
              if (!controller.isLive) {
                final e = controller.sim!.euler();
                return 'R ${_fmt(e.r * 57.3, 1)}°\nP ${_fmt(e.p * 57.3, 1)}°\nY ${_fmt(e.y * 57.3, 1)}°';
              }
              final imu = controller.imu;
              if (imu == null) return '—';
              final e = imu.orientation.toEuler();
              return 'R ${_fmt(e.roll * 57.3, 1)}°\nP ${_fmt(e.pitch * 57.3, 1)}°\nY ${_fmt(e.yaw * 57.3, 1)}°';
            }),
            _card('QUATERNION', AppColors.blue, () {
              if (!controller.isLive) {
                final q = controller.sim!.quat();
                return 'x${_fmt(q.x)}\ny${_fmt(q.y)}\nz${_fmt(q.z)}\nw${_fmt(q.w)}';
              }
              final q = controller.imu?.orientation;
              if (q == null) return '—';
              return 'x${_fmt(q.x)}\ny${_fmt(q.y)}\nz${_fmt(q.z)}\nw${_fmt(q.w)}';
            }),
            _card('ANGULAR VEL (RAD/S)', AppColors.lime, () {
              if (!controller.isLive) {
                final t = controller.sim!.t;
                return 'x${_fmt(0.27 * cos(t * 0.7))}\ny${_fmt(0.27 * cos(t * 0.9))}\nz${_fmt(0.35)}';
              }
              final v = controller.imu?.angularVelocity;
              if (v == null) return '—';
              return 'x${_fmt(v.x)}\ny${_fmt(v.y)}\nz${_fmt(v.z)}';
            }),
            _card('LINEAR ACCEL (M/S²)', AppColors.amber, () {
              if (!controller.isLive) {
                final t = controller.sim!.t;
                return 'x${_fmt(0.2 * sin(t * 1.3))}\ny${_fmt(0.15 * sin(t))}\nz${_fmt(9.81 + 0.1 * sin(t * 2))}';
              }
              final a = controller.imu?.linearAcceleration;
              if (a == null) return '—';
              return 'x${_fmt(a.x)}\ny${_fmt(a.y)}\nz${_fmt(a.z)}';
            }),
          ],
        ),
      ),
    );
  }
}
