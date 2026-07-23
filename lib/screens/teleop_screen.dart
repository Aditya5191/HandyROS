import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';
import '../services/dds_topic_service.dart';
import '../widgets/virtual_joystick.dart';

/// Drives a robot directly from the phone: a virtual joystick for
/// surge/sway (linear.x/y) plus two press-and-hold arrows for yaw
/// (angular.z), publishing geometry_msgs/Twist on a topic name the
/// user sets (default /cmd_vel). [active] reflects whether this tab is
/// the one currently selected in AppShell's bottom nav — publishing is
/// force-stopped (with a final zero-Twist) the moment it goes false,
/// since AppShell keeps every tab mounted via IndexedStack and a robot
/// must never keep receiving a stale non-zero command after the driver
/// switches away.
class TeleopScreen extends StatefulWidget {
  final DdsTopicService? dds;
  final bool active;

  const TeleopScreen({super.key, required this.dds, required this.active});

  @override
  State<TeleopScreen> createState() => _TeleopScreenState();
}

class _TeleopScreenState extends State<TeleopScreen> {
  late final TextEditingController _topicController = TextEditingController(
    text: '/cmd_vel',
  );
  bool _publishing = false;
  double _maxLinear = 0.5;
  double _maxAngular = 1.0;
  Offset _knob = Offset.zero;
  // -1 / 0 / +1 while a yaw button is held — angular.z is discrete
  // (full-rate turn-in-place) rather than proportional, since the
  // joystick itself drives surge/sway (linear.x/y), not yaw.
  int _yawInput = 0;
  Timer? _tickTimer;
  String? _activeTopic;

  @override
  void didUpdateWidget(covariant TeleopScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active && !widget.active && _publishing) {
      _stop();
    }
  }

  @override
  void dispose() {
    if (_publishing) {
      _stop();
    }
    _topicController.dispose();
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink.withValues(alpha: .92),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        margin: const EdgeInsets.only(bottom: 100, left: 60, right: 60),
        duration: const Duration(milliseconds: 1700),
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: AppText.disp(
            size: 12,
            weight: FontWeight.w600,
            color: AppColors.bg,
          ),
        ),
      ),
    );
  }

  void _start() {
    final dds = widget.dds;
    if (dds == null) {
      _toast('No DDS connection');
      return;
    }
    final topic = _topicController.text.trim();
    if (topic.isEmpty || !topic.startsWith('/')) {
      _toast('Topic name must start with /');
      return;
    }
    setState(() {
      _publishing = true;
      _activeTopic = topic;
    });
    _tickTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _tick(),
    );
  }

  void _tick() {
    final dds = widget.dds;
    final topic = _activeTopic;
    if (dds == null || topic == null) return;
    dds.publishTwist(
      topic,
      lx: -_knob.dy * _maxLinear,
      ly: -_knob.dx * _maxLinear,
      lz: 0,
      ax: 0,
      ay: 0,
      az: _yawInput * _maxAngular,
    );
  }

  void _setYaw(int direction, bool held) {
    setState(
      () => _yawInput = held
          ? direction
          : (_yawInput == direction ? 0 : _yawInput),
    );
  }

  void _stop() {
    _tickTimer?.cancel();
    _tickTimer = null;
    final dds = widget.dds;
    final topic = _activeTopic;
    if (dds != null && topic != null) {
      // Final zero-Twist so the robot doesn't keep driving on the last
      // non-zero command.
      dds.publishTwist(topic, lx: 0, ly: 0, lz: 0, ax: 0, ay: 0, az: 0);
      dds.stopPublishing(topic);
    }
    _knob = Offset.zero;
    _yawInput = 0;
    if (mounted) {
      setState(() {
        _publishing = false;
        _activeTopic = null;
      });
    } else {
      _publishing = false;
      _activeTopic = null;
    }
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

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    String unit,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: AppText.disp(
                size: 12,
                weight: FontWeight.w500,
                color: AppColors.ink2,
              ),
            ),
            Text(
              '${value.toStringAsFixed(2)} $unit',
              style: AppText.mono(
                size: 12,
                weight: FontWeight.w600,
                color: AppColors.acc2,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppColors.acc,
            inactiveTrackColor: AppColors.line,
            thumbColor: AppColors.acc,
            overlayColor: AppColors.accTint,
            trackHeight: 3,
          ),
          child: Slider(value: value, min: min, max: max, onChanged: onChanged),
        ),
      ],
    );
  }

  Widget _yawButton(IconData icon, int direction) {
    final held = _yawInput == direction;
    return GestureDetector(
      onTapDown: (_) => _setYaw(direction, true),
      onTapUp: (_) => _setYaw(direction, false),
      onTapCancel: () => _setYaw(direction, false),
      child: Container(
        width: 50,
        height: 50,
        decoration: held
            ? recessedDecoration(base: AppColors.accTint, radius: 25)
            : BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.card,
                boxShadow: raisedShadow,
              ),
        child: Icon(
          icon,
          size: 24,
          color: held ? AppColors.acc2 : AppColors.ink2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lx = -_knob.dy * _maxLinear;
    final ly = -_knob.dx * _maxLinear;
    final az = _yawInput * _maxAngular;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'geometry_msgs · Twist',
                        style: AppText.body(
                          size: 13,
                          weight: FontWeight.w500,
                          color: AppColors.ink3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Teleop',
                        style: AppText.disp(
                          size: 26,
                          weight: FontWeight.w600,
                          letterSpacing: -.5,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 42,
                  child: Material(
                    borderRadius: BorderRadius.circular(14),
                    color: _publishing ? AppColors.red : AppColors.acc,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _publishing ? _stop : _start,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _publishing
                                  ? Icons.stop_circle_outlined
                                  : Icons.play_arrow,
                              size: 18,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 7),
                            Text(
                              _publishing ? 'Stop' : 'Start',
                              style: AppText.disp(
                                size: 13,
                                weight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 112),
              children: [
                _sectionLabel('TARGET TOPIC'),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  decoration: recessedDecoration(radius: 14),
                  child: TextField(
                    controller: _topicController,
                    enabled: !_publishing,
                    style: AppText.mono(size: 14, weight: FontWeight.w600),
                    inputFormatters: [
                      FilteringTextInputFormatter.deny(RegExp(r'\s')),
                    ],
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 13),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _sectionLabel('LIMITS'),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: panelDecoration(radius: 20),
                  child: Column(
                    children: [
                      _slider(
                        'Max linear',
                        _maxLinear,
                        0.1,
                        5.0,
                        'm/s',
                        (v) => setState(() => _maxLinear = v),
                      ),
                      const SizedBox(height: 4),
                      _slider(
                        'Max angular',
                        _maxAngular,
                        0.2,
                        6.0,
                        'rad/s',
                        (v) => setState(() => _maxAngular = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _yawButton(Icons.turn_left, 1),
                        const SizedBox(height: 10),
                        _yawButton(Icons.turn_right, -1),
                      ],
                    ),
                    const SizedBox(width: 16),
                    VirtualJoystick(
                      size: 168,
                      onChanged: (o) => setState(() => _knob = o),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    'surge / sway — joystick   ·   yaw — hold arrows',
                    style: AppText.body(size: 11, color: AppColors.ink3),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  decoration: recessedDecoration(radius: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Text(
                        'surge  ${lx.toStringAsFixed(2)}',
                        style: AppText.mono(
                          size: 12,
                          weight: FontWeight.w600,
                          color: AppColors.acc2,
                        ),
                      ),
                      Text(
                        'sway  ${ly.toStringAsFixed(2)}',
                        style: AppText.mono(
                          size: 12,
                          weight: FontWeight.w600,
                          color: AppColors.acc2,
                        ),
                      ),
                      Text(
                        'yaw  ${az.toStringAsFixed(2)}',
                        style: AppText.mono(
                          size: 12,
                          weight: FontWeight.w600,
                          color: AppColors.acc2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
