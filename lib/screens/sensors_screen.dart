import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../services/dds_topic_service.dart';
import '../services/phone_sensor_publisher.dart';

/// "Phone as sensor" tab: turns phone hardware (IMU, GPS,
/// magnetometer, camera) into ROS topics the user names. Each card is
/// independent — starting/stopping one doesn't affect the others, and
/// (unlike Teleop) these keep publishing across tab switches, since
/// background sensor logging while browsing Topics/Settings is a
/// reasonable thing to want and there's no runaway-motion risk here.
class SensorsScreen extends StatefulWidget {
  final DdsTopicService? dds;

  const SensorsScreen({super.key, required this.dds});

  @override
  State<SensorsScreen> createState() => _SensorsScreenState();
}

class _SensorsScreenState extends State<SensorsScreen> {
  PhoneSensorPublisher? _publisher;
  final _imuTopic = TextEditingController(text: '/phone/imu');
  final _gpsTopic = TextEditingController(text: '/phone/gps');
  final _magTopic = TextEditingController(text: '/phone/mag');
  final _cameraTopic = TextEditingController(text: '/phone/camera/image_raw');

  @override
  void initState() {
    super.initState();
    final dds = widget.dds;
    if (dds != null) {
      _publisher = PhoneSensorPublisher(dds);
    }
  }

  @override
  void dispose() {
    _publisher?.dispose();
    _imuTopic.dispose();
    _gpsTopic.dispose();
    _magTopic.dispose();
    _cameraTopic.dispose();
    super.dispose();
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 11),
    child: Text(
      text,
      style: AppText.disp(
        size: 10,
        weight: FontWeight.w600,
        color: AppColors.ink3,
        letterSpacing: .9,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final publisher = _publisher;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Phone hardware',
                  style: AppText.body(
                    size: 13,
                    weight: FontWeight.w500,
                    color: AppColors.ink3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Sensors',
                  style: AppText.disp(
                    size: 26,
                    weight: FontWeight.w600,
                    letterSpacing: -.5,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: publisher == null
                ? Center(
                    child: Text(
                      'No DDS connection',
                      style: AppText.body(size: 13, color: AppColors.ink2),
                    ),
                  )
                : AnimatedBuilder(
                    animation: publisher,
                    builder: (context, _) {
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 112),
                        children: [
                          _sectionLabel('IMU'),
                          RepaintBoundary(
                            child: _SensorCard(
                              icon: Icons.explore,
                              color: AppColors.sec,
                              typeLabel: 'sensor_msgs/msg/Imu',
                              topicController: _imuTopic,
                              active: publisher.imuActive,
                              onStart: () =>
                                  publisher.startImu(_imuTopic.text.trim()),
                              onStop: publisher.stopImu,
                              readout:
                                  publisher.imuActive &&
                                      publisher.lastAccel != null
                                  ? '${publisher.lastAccel!.x.toStringAsFixed(2)}, ${publisher.lastAccel!.y.toStringAsFixed(2)}, ${publisher.lastAccel!.z.toStringAsFixed(2)} m/s²'
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _sectionLabel('GPS'),
                          RepaintBoundary(
                            child: _SensorCard(
                              icon: Icons.satellite_alt,
                              color: AppColors.amber,
                              typeLabel: 'sensor_msgs/msg/NavSatFix',
                              topicController: _gpsTopic,
                              active: publisher.gpsActive,
                              error: publisher.gpsError,
                              onStart: () =>
                                  publisher.startGps(_gpsTopic.text.trim()),
                              onStop: publisher.stopGps,
                              readout:
                                  publisher.gpsActive &&
                                      publisher.lastPosition != null
                                  ? '${publisher.lastPosition!.latitude.toStringAsFixed(5)}, ${publisher.lastPosition!.longitude.toStringAsFixed(5)}'
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _sectionLabel('MAGNETOMETER'),
                          RepaintBoundary(
                            child: _SensorCard(
                              icon: Icons.explore_outlined,
                              color: AppColors.lime,
                              typeLabel: 'sensor_msgs/msg/MagneticField',
                              topicController: _magTopic,
                              active: publisher.magActive,
                              onStart: () => publisher.startMagnetometer(
                                _magTopic.text.trim(),
                              ),
                              onStop: publisher.stopMagnetometer,
                              readout:
                                  publisher.magActive &&
                                      publisher.lastMag != null
                                  ? '${publisher.lastMag!.x.toStringAsFixed(1)}, ${publisher.lastMag!.y.toStringAsFixed(1)}, ${publisher.lastMag!.z.toStringAsFixed(1)} µT'
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _sectionLabel('CAMERA'),
                          RepaintBoundary(
                            child: _SensorCard(
                              icon: Icons.camera_alt,
                              color: AppColors.pink,
                              typeLabel: 'sensor_msgs/msg/Image · ~10 fps',
                              topicController: _cameraTopic,
                              active: publisher.cameraActive,
                              error: publisher.cameraError,
                              onStart: () => publisher.startCamera(
                                _cameraTopic.text.trim(),
                              ),
                              onStop: publisher.stopCamera,
                              preview:
                                  publisher.cameraActive &&
                                      publisher.cameraController != null
                                  ? publisher.cameraController!
                                  : null,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SensorCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String typeLabel;
  final TextEditingController topicController;
  final bool active;
  final String? error;
  final String? readout;
  final CameraController? preview;
  final VoidCallback onStart;
  final VoidCallback onStop;

  const _SensorCard({
    required this.icon,
    required this.color,
    required this.typeLabel,
    required this.topicController,
    required this.active,
    this.error,
    this.readout,
    this.preview,
    required this.onStart,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: panelDecoration(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: AppGradients.iconBadge,
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  typeLabel,
                  style: AppText.mono(
                    size: 11,
                    weight: FontWeight.w500,
                    color: AppColors.ink3,
                  ),
                ),
              ),
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? color : AppColors.ink3.withValues(alpha: .4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          GestureDetector(
            onTap: active ? null : () => _editTopicName(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
              decoration: recessedDecoration(radius: 12),
              child: Row(
                children: [
                  Expanded(
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: topicController,
                      builder: (context, value, _) => Text(
                        value.text,
                        style: AppText.mono(size: 13, weight: FontWeight.w600),
                      ),
                    ),
                  ),
                  if (!active)
                    Icon(Icons.edit_outlined, size: 15, color: AppColors.ink3),
                ],
              ),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 9),
            Text(error!, style: AppText.body(size: 11.5, color: AppColors.red)),
          ],
          if (active && readout != null) ...[
            const SizedBox(height: 9),
            Text(
              readout!,
              style: AppText.mono(
                size: 11.5,
                weight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
          if (active && preview != null && preview!.value.isInitialized) ...[
            const SizedBox(height: 9),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: preview!.value.aspectRatio,
                child: CameraPreview(preview!),
              ),
            ),
          ],
          const SizedBox(height: 13),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: Material(
              borderRadius: BorderRadius.circular(13),
              color: active ? AppColors.red : color,
              child: InkWell(
                borderRadius: BorderRadius.circular(13),
                onTap: active ? onStop : onStart,
                child: Center(
                  child: Text(
                    active ? 'Stop' : 'Start',
                    style: AppText.disp(
                      size: 13,
                      weight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editTopicName(BuildContext context) async {
    final controller = TextEditingController(text: topicController.text);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(
          'Topic name',
          style: AppText.disp(size: 15, weight: FontWeight.w600),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: AppText.mono(size: 13, weight: FontWeight.w600),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null) {
      topicController.text = result;
    }
  }
}
