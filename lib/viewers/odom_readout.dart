import 'package:flutter/material.dart';
import '../app/theme.dart';
import 'live_payload_controller.dart';

String _fmt(double n, [int d = 2]) => (n < 0 ? '' : ' ') + n.toStringAsFixed(d);

class OdomReadoutGrid extends StatelessWidget {
  final LivePayloadController controller;

  const OdomReadoutGrid({super.key, required this.controller});

  Widget _card(String title, Color color, String Function() value) {
    return Expanded(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          decoration: panelDecoration(radius: 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppText.disp(size: 9, color: color, letterSpacing: .6),
              ),
              const SizedBox(height: 6),
              Text(
                value(),
                style: AppText.mono(size: 13, weight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _card('POSITION (M)', AppColors.amber, () {
            if (!controller.isLive) {
              final sim = controller.sim!;
              return 'x${_fmt(sim.ox)}\ny${_fmt(sim.oy)}\nz${_fmt(0)}';
            }
            final p = controller.odom?.position;
            if (p == null) return '—';
            return 'x${_fmt(p.x)}\ny${_fmt(p.y)}\nz${_fmt(p.z)}';
          }),
          const SizedBox(width: 9),
          _card('VELOCITY', AppColors.pri, () {
            if (!controller.isLive) {
              final sim = controller.sim!;
              return 'vx${_fmt(sim.vx)}\nvy${_fmt(sim.vy)}\nω ${_fmt(sim.oth)}';
            }
            final odom = controller.odom;
            if (odom == null) return '—';
            return 'vx${_fmt(odom.linearVelocity.x)}\nvy${_fmt(odom.linearVelocity.y)}\nω ${_fmt(odom.angularVelocity.z)}';
          }),
          const SizedBox(width: 9),
          _card('HEADING', AppColors.blue, () {
            if (!controller.isLive) {
              return '${_fmt(controller.sim!.oth * 57.3, 0).trim()}°';
            }
            final yaw = controller.odom?.orientation.toEuler().yaw;
            if (yaw == null) return '—';
            return '${_fmt(yaw * 57.3, 0).trim()}°';
          }),
        ],
      ),
    );
  }
}
