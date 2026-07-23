import 'package:flutter/material.dart';
import '../app/theme.dart';

/// A circular drag pad. Reports a normalized offset (-1..1 on each
/// axis, dx = left/right, dy = up/down) via [onChanged] on every
/// update, and springs back to (0,0) on release — teleop must never
/// keep sending a non-zero command just because the driver's thumb is
/// still resting near where it let go.
class VirtualJoystick extends StatefulWidget {
  final ValueChanged<Offset> onChanged;
  final double size;

  const VirtualJoystick({super.key, required this.onChanged, this.size = 220});

  @override
  State<VirtualJoystick> createState() => _VirtualJoystickState();
}

class _VirtualJoystickState extends State<VirtualJoystick>
    with SingleTickerProviderStateMixin {
  static const _knobRadius = 30.0;

  Offset _knob = Offset.zero;
  late final AnimationController _spring;
  Animation<Offset>? _springAnim;

  @override
  void initState() {
    super.initState();
    _spring =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 220),
        )..addListener(() {
          final anim = _springAnim;
          if (anim == null) return;
          setState(() => _knob = anim.value);
          widget.onChanged(_knob);
        });
  }

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  double get _travel => widget.size / 2 - _knobRadius;

  void _updateFromLocal(Offset local) {
    final center = Offset(widget.size / 2, widget.size / 2);
    var delta = local - center;
    if (delta.distance > _travel) {
      delta = Offset.fromDirection(delta.direction, _travel);
    }
    setState(() => _knob = Offset(delta.dx / _travel, delta.dy / _travel));
    widget.onChanged(_knob);
  }

  void _release() {
    _springAnim = Tween<Offset>(
      begin: _knob,
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _spring, curve: Curves.easeOutBack));
    _spring.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (d) => _updateFromLocal(d.localPosition),
      onPanUpdate: (d) => _updateFromLocal(d.localPosition),
      onPanEnd: (_) => _release(),
      onPanCancel: _release,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: recessedDecoration(radius: widget.size / 2),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              Icons.add,
              size: 28,
              color: AppColors.ink3.withValues(alpha: .4),
            ),
            Transform.translate(
              offset: Offset(_knob.dx * _travel, _knob.dy * _travel),
              child: Container(
                width: _knobRadius * 2,
                height: _knobRadius * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.card,
                  boxShadow: raisedShadow,
                ),
                child: Icon(
                  Icons.control_camera,
                  size: 24,
                  color: AppColors.acc,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
