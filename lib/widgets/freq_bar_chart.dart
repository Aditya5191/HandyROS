import 'package:flutter/material.dart';

/// Small live-looking bar chart used inside an expanded topic card to
/// show recent message frequency. [values] are normalized 0..1. Sits
/// directly in the caller's already-recessed detail panel — no
/// decoration of its own.
class FreqBarChart extends StatelessWidget {
  final List<double> values;
  final Color color;

  const FreqBarChart({super.key, required this.values, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        spacing: 3,
        children: [
          for (final v in values)
            Expanded(
              child: FractionallySizedBox(
                heightFactor: v.clamp(0.08, 1.0),
                alignment: Alignment.bottomCenter,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(2),
                    ),
                    color: color.withValues(alpha: .6),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
