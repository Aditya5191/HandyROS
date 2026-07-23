import 'package:flutter/material.dart';
import '../app/theme.dart';
import 'live_payload_controller.dart';

String _fmt(double n, [int d = 2]) => (n < 0 ? '' : ' ') + n.toStringAsFixed(d);

/// Fallback viewer for any type in a known package with no dedicated
/// Viewer (e.g. sensor_msgs/CameraInfo, rosgraph_msgs/Clock). Rather
/// than hand-decoding the long tail of remaining registered types,
/// shows the real topic metadata we do have (name/type/QoS/rate/size/
/// latency — already computed by TopicStatsTracker) plus an honest
/// "not decoded yet" notice, instead of pretending with fake data.
class RawEchoView extends StatelessWidget {
  final LivePayloadController controller;

  const RawEchoView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      padding: const EdgeInsets.all(17),
      decoration: recessedDecoration(base: AppColors.card, radius: 20),
      child: SingleChildScrollView(
        child: controller.isLive
            ? AnimatedBuilder(
                animation: controller,
                builder: (context, _) {
                  final topic = controller.liveTopic ?? controller.topic;
                  final qos = topic.qos;
                  final text =
                      'name: "${topic.name}"\n'
                      'type: "${topic.type}"\n'
                      'qos:\n'
                      '  reliability: ${qos.reliability}\n'
                      '  durability: ${qos.durability}\n'
                      '  history: ${qos.history} (depth ${qos.depth})\n'
                      'rate: ${topic.hzAvg}\n'
                      'size: ${topic.messageSize}\n'
                      'bandwidth: ${topic.bandwidth}\n'
                      'latency: ${topic.latency}\n'
                      '\n'
                      '# Field-level decode isn\'t implemented for\n'
                      '# ${topic.type} yet — this is topic metadata\n'
                      '# only, not the message body.';
                  return Text(
                    text,
                    style: AppText.mono(
                      size: 12,
                      weight: FontWeight.w500,
                      color: AppColors.acc2,
                    ),
                  );
                },
              )
            : AnimatedBuilder(
                animation: controller,
                builder: (context, _) {
                  final sim = controller.sim!;
                  final text =
                      'header:\n'
                      '  stamp: ${(1721000000 + sim.t.floor())}\n'
                      '  frame_id: "base_link"\n'
                      'twist:\n'
                      '  linear:  { x: ${_fmt(sim.vx)}, y: 0.00, z: 0.00 }\n'
                      '  angular: { z: ${_fmt(sim.oth)} }';
                  return Text(
                    text,
                    style: AppText.mono(
                      size: 12,
                      weight: FontWeight.w500,
                      color: AppColors.acc2,
                    ),
                  );
                },
              ),
      ),
    );
  }
}
