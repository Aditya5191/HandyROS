import 'package:flutter/material.dart';
import '../app/theme.dart';
import 'live_payload_controller.dart';

class _LogLine {
  final String ts;
  final String text;
  final Color color;

  const _LogLine(this.ts, this.text, this.color);
}

final _kDemoLines = [
  _LogLine(
    '[12:04:01]',
    '[INFO] [bt_navigator]: Begin navigating to (2.10, 1.30)',
    AppColors.acc,
  ),
  _LogLine(
    '[12:04:01]',
    '[INFO] [controller]: Passing new path to controller',
    AppColors.ink,
  ),
  _LogLine(
    '[12:04:02]',
    '[WARN] [costmap]: Robot is close to obstacle (0.42m)',
    AppColors.amber,
  ),
  _LogLine(
    '[12:04:02]',
    '[DEBUG] [dwb]: Trajectory scored: 0.87',
    AppColors.blue,
  ),
  _LogLine(
    '[12:04:03]',
    '[INFO] [controller]: Reached the goal!',
    AppColors.acc,
  ),
];

// rcl_interfaces/msg/Log level constants.
Color _levelColor(int? level) {
  if (level == null)
    return AppColors.ink2; // plain std_msgs/String — no level concept
  if (level >= 40) return AppColors.red; // ERROR / FATAL
  if (level >= 30) return AppColors.amber; // WARN
  if (level >= 20) return AppColors.acc; // INFO
  return AppColors.blue; // DEBUG
}

String _levelTag(int? level) {
  if (level == null) return '';
  if (level >= 50) return '[FATAL] ';
  if (level >= 40) return '[ERROR] ';
  if (level >= 30) return '[WARN] ';
  if (level >= 20) return '[INFO] ';
  return '[DEBUG] ';
}

String _timeOfDay(DateTime t) =>
    '[${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}]';

class TerminalView extends StatefulWidget {
  final LivePayloadController controller;
  const TerminalView({super.key, required this.controller});

  @override
  State<TerminalView> createState() => _TerminalViewState();
}

class _TerminalViewState extends State<TerminalView> {
  final ScrollController _scroll = ScrollController();
  int _lastLineCount = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _maybeAutoScroll() {
    if (!_scroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      padding: const EdgeInsets.all(16),
      decoration: recessedDecoration(base: AppColors.card, radius: 20),
      child: widget.controller.isLive
          ? AnimatedBuilder(
              animation: widget.controller,
              builder: (context, _) {
                final lines = widget.controller.logLines;
                if (lines.length != _lastLineCount) {
                  _lastLineCount = lines.length;
                  _maybeAutoScroll();
                }
                if (lines.isEmpty) {
                  return Center(
                    child: Text(
                      'waiting for first message…',
                      style: AppText.mono(size: 12, color: AppColors.ink3),
                    ),
                  );
                }
                return ListView.builder(
                  controller: _scroll,
                  itemCount: lines.length,
                  itemBuilder: (context, i) {
                    final entry = lines[i];
                    final color = _levelColor(entry.sample.level);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: RichText(
                        text: TextSpan(
                          style: AppText.mono(
                            size: 12,
                            weight: FontWeight.w500,
                            color: color,
                          ),
                          children: [
                            TextSpan(
                              text: '${_timeOfDay(entry.timestamp)} ',
                              style: AppText.mono(
                                size: 12,
                                weight: FontWeight.w500,
                                color: AppColors.ink3,
                              ),
                            ),
                            if (entry.sample.name != null &&
                                entry.sample.name!.isNotEmpty)
                              TextSpan(
                                text:
                                    '${_levelTag(entry.sample.level)}[${entry.sample.name}]: ',
                              ),
                            TextSpan(text: entry.sample.text),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            )
          : ListView(
              children: [
                for (final l in _kDemoLines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: RichText(
                      text: TextSpan(
                        style: AppText.mono(
                          size: 12,
                          weight: FontWeight.w500,
                          color: l.color,
                        ),
                        children: [
                          TextSpan(
                            text: '${l.ts} ',
                            style: AppText.mono(
                              size: 12,
                              weight: FontWeight.w500,
                              color: AppColors.ink3,
                            ),
                          ),
                          TextSpan(text: l.text),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
