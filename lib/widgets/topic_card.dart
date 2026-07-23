import 'package:flutter/material.dart';
import '../app/theme.dart';
import '../core/viewer_plugin.dart';
import '../models/topic.dart';
import 'freq_bar_chart.dart';

class TopicCard extends StatefulWidget {
  final Topic topic;
  final ValueChanged<String> onCopy;
  final ValueChanged<Topic> onVisualize;

  /// Called when the card's detail view opens/closes, so the caller can
  /// start/stop real stats tracking for just this topic (see
  /// DdsTopicService.watchTopic — deliberately not automatic for every
  /// discovered topic, since some are heavy camera/point-cloud streams).
  final void Function(String topicName, bool expanded)? onExpandChanged;

  const TopicCard({
    super.key,
    required this.topic,
    required this.onCopy,
    required this.onVisualize,
    this.onExpandChanged,
  });

  @override
  State<TopicCard> createState() => _TopicCardState();
}

class _TopicCardState extends State<TopicCard> {
  bool _expanded = false;
  // Raw Hz readings observed while expanded (real DDS stats — see
  // DdsTopicService.watchTopic), not a fake ticker. Normalized to 0..1
  // relative to this window's own peak just before rendering, since
  // FreqBarChart expects normalized bar heights and a topic's real
  // rate can be anywhere from <1 Hz to hundreds of Hz.
  final ValueNotifier<List<double>> _freqHistory = ValueNotifier(<double>[]);

  @override
  void dispose() {
    _freqHistory.dispose();
    // The widget can be disposed while still expanded (e.g. scrolled
    // out of the list) — stop tracking so we don't leak a live DDS
    // subscription to a card nobody can see anymore.
    if (_expanded) {
      widget.onExpandChanged?.call(widget.topic.name, false);
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TopicCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_expanded && widget.topic.hzAvg != '—') {
      final next = List<double>.from(_freqHistory.value)..add(widget.topic.hz);
      if (next.length > 32) {
        next.removeAt(0);
      }
      _freqHistory.value = next;
    }
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (!_expanded) {
      _freqHistory.value = [];
    }
    widget.onExpandChanged?.call(widget.topic.name, _expanded);
  }

  Widget _statCell(String label, String value) {
    return Container(
      color: AppColors.bg,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppText.disp(
              size: 9,
              weight: FontWeight.w600,
              color: AppColors.ink3,
              letterSpacing: .6,
            ),
          ),
          const SizedBox(height: 6),
          Text(value, style: AppText.mono(size: 13, weight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _statsGrid(Topic t) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        color: AppColors.line,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: _statCell('AVG RATE', t.hzAvg)),
                Container(width: 1, height: 68, color: AppColors.line),
                Expanded(child: _statCell('BANDWIDTH', t.bandwidth)),
              ],
            ),
            Container(height: 1, color: AppColors.line),
            Row(
              children: [
                Expanded(child: _statCell('MSG SIZE', t.messageSize)),
                Container(width: 1, height: 68, color: AppColors.line),
                Expanded(child: _statCell('LATENCY', t.latency)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
    text,
    style: AppText.disp(
      size: 10,
      weight: FontWeight.w600,
      color: AppColors.ink3,
      letterSpacing: .8,
    ),
  );

  Widget _qosChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: AppColors.card,
        boxShadow: raisedShadowSm,
      ),
      child: Text(
        label,
        style: AppText.mono(
          size: 10,
          weight: FontWeight.w500,
          color: AppColors.ink2,
        ),
      ),
    );
  }

  Widget _nodeRow(String node, Color dotColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              node,
              style: AppText.mono(
                size: 11,
                weight: FontWeight.w500,
                color: AppColors.ink,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.topic;
    final plugin = ViewerRegistry.viewerFor(t.type);
    // hzAvg is '—' whenever this type doesn't have real rate
    // measurement wired up yet (see DdsTopicService) — showing "0.0 Hz"
    // in that case would misleadingly read as "confirmed silent".
    final hasRate = t.hzAvg != '—';
    final hzColor = hasRate && t.hz > 0 ? t.color : AppColors.ink3;
    final shortType = t.type.split('/').isNotEmpty
        ? t.type.split('/').last
        : t.type;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      // Shadow lives on this outer, unclipped decoration; a ClipRRect
      // handles rounding the content separately below. Putting boxShadow
      // and clipBehavior on the same Container clips the shadow itself
      // to a hard edge at the card's own corner instead of letting it
      // fade outward.
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: _expanded ? raisedShadowLg : raisedShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Container(
          color: AppColors.card,
          child: Column(
            children: [
              InkWell(
                onTap: _toggle,
                child: Padding(
                  padding: const EdgeInsets.all(15),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: AppGradients.iconBadge,
                        ),
                        child: Icon(t.icon, size: 22, color: t.color),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.name,
                              style: AppText.mono(
                                size: 13.5,
                                weight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              shortType,
                              style: AppText.mono(
                                size: 10.5,
                                weight: FontWeight.w500,
                                color: AppColors.ink3,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            t.hzAvg,
                            style: AppText.mono(
                              size: 12,
                              weight: FontWeight.w600,
                              color: hzColor,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            t.bandwidth,
                            style: AppText.mono(
                              size: 9.5,
                              weight: FontWeight.w500,
                              color: AppColors.ink3,
                            ),
                          ),
                        ],
                      ),
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutCubic,
                        child: Icon(
                          Icons.expand_more,
                          size: 22,
                          color: AppColors.ink3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 250),
                crossFadeState: _expanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                firstChild: const SizedBox(width: double.infinity, height: 0),
                secondChild: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Container(
                    padding: const EdgeInsets.all(15),
                    decoration: recessedDecoration(radius: 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _sectionLabel('FREQUENCY'),
                            Text(
                              t.hzAvg,
                              style: AppText.mono(
                                size: 11,
                                weight: FontWeight.w600,
                                color: AppColors.acc,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ValueListenableBuilder<List<double>>(
                          valueListenable: _freqHistory,
                          builder: (context, raw, _) {
                            if (raw.isEmpty) {
                              return SizedBox(
                                height: 42,
                                child: Center(
                                  child: Text(
                                    'waiting for data…',
                                    style: AppText.mono(
                                      size: 10,
                                      color: AppColors.ink3,
                                    ),
                                  ),
                                ),
                              );
                            }
                            final maxV = raw.reduce((a, b) => a > b ? a : b);
                            final normalized = raw
                                .map(
                                  (v) => maxV <= 0
                                      ? 0.08
                                      : (v / maxV).clamp(0.08, 1.0),
                                )
                                .toList();
                            return FreqBarChart(
                              values: normalized,
                              color: t.color,
                            );
                          },
                        ),
                        const SizedBox(height: 15),
                        _statsGrid(t),
                        const SizedBox(height: 15),
                        Text(
                          t.type,
                          style: AppText.mono(
                            size: 10.5,
                            weight: FontWeight.w500,
                            color: AppColors.ink2,
                          ),
                        ),
                        const SizedBox(height: 13),
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: [
                            _qosChip(t.qos.reliability),
                            _qosChip(t.qos.history),
                            _qosChip('depth ${t.qos.depth}'),
                          ],
                        ),
                        const SizedBox(height: 15),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _sectionLabel('PUB · ${t.publisherCount}'),
                                  const SizedBox(height: 9),
                                  if (t.publishers.isEmpty)
                                    Text(
                                      '—',
                                      style: AppText.mono(
                                        size: 11,
                                        color: AppColors.ink3,
                                      ),
                                    ),
                                  for (final p in t.publishers)
                                    _nodeRow(p.node, AppColors.acc),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _sectionLabel('SUB · ${t.subscriberCount}'),
                                  const SizedBox(height: 9),
                                  if (t.subscribers.isEmpty)
                                    Text(
                                      '—',
                                      style: AppText.mono(
                                        size: 11,
                                        color: AppColors.ink3,
                                      ),
                                    ),
                                  for (final s in t.subscribers)
                                    _nodeRow(s.node, AppColors.ink3),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 50,
                                child: Material(
                                  borderRadius: BorderRadius.circular(16),
                                  color: AppColors.acc,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () => widget.onVisualize(t),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          plugin?.visualizeIcon ??
                                              Icons.help_outline,
                                          size: 20,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          plugin?.visualizeLabel ??
                                              'Import Definition',
                                          style: AppText.disp(
                                            size: 14,
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
                            const SizedBox(width: 9),
                            Container(
                              width: 50,
                              height: 50,
                              // Plain Container, not Ink — Ink paints its
                              // decoration via an InkFeature on the
                              // Material's canvas, which does not blur
                              // BoxShadow correctly (renders as a hard,
                              // unrounded rectangle instead).
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                color: AppColors.card,
                                boxShadow: raisedShadowSm,
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () => widget.onCopy(t.name),
                                  child: Icon(
                                    Icons.content_copy,
                                    size: 19,
                                    color: AppColors.ink2,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
