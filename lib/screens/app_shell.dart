import 'dart:ui';

import 'package:flutter/material.dart';
import '../app/theme.dart';
import '../services/app_settings.dart';
import '../services/dds_topic_service.dart';
import 'home_screen.dart';
import 'sensors_screen.dart';
import 'settings_screen.dart';
import 'teleop_screen.dart';

// Testing pure multicast discovery now that Tailscale is off — see if
// that was the actual root cause instead of the network blocking
// multicast between Wi-Fi clients. TODO(settings): "known hosts" field
// once the Settings screen supports it, if unicast peers turn out to
// still be needed — see DdsTopicService.
const _kUnicastDiscoveryPeers = <String>[];

class _NavDef {
  final String label;
  final IconData icon;
  const _NavDef(this.label, this.icon);
}

const _kNavDefs = [
  _NavDef('Topics', Icons.dashboard),
  _NavDef('Sensors', Icons.sensors),
  _NavDef('Teleop', Icons.sports_esports),
  _NavDef('Settings', Icons.tune),
];
const _kTopicsIndex = 0;
const _kTeleopIndex = 2;

/// Top-level shell: the floating glass bottom nav bar over an
/// [IndexedStack] of tabs — replaces the old AppBar-pushed Settings
/// navigation. `IndexedStack` keeps each tab's own state (scroll
/// position, expanded cards, in-flight sensor streams) alive when
/// switching away and back, rather than rebuilding from scratch.
///
/// Owns the single [DdsTopicService] shared by every tab that talks to
/// DDS (Topics, Sensors, Teleop) — previously HomeScreen created its
/// own, which meant a second tab reaching for real DDS state would
/// have opened a redundant native binding instead of sharing one.
class AppShell extends StatefulWidget {
  final AppSettings settings;

  const AppShell({super.key, required this.settings});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  DdsTopicService? _dds;

  @override
  void initState() {
    super.initState();
    final dds = DdsTopicService.tryCreate();
    if (dds != null &&
        dds.start(
          domainId: widget.settings.domainId,
          peers: _kUnicastDiscoveryPeers,
        )) {
      _dds = dds;
    } else {
      dds?.dispose();
    }
  }

  @override
  void dispose() {
    _dds?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _index,
            children: [
              HomeScreen(
                settings: widget.settings,
                dds: _dds,
                active: _index == _kTopicsIndex,
              ),
              SensorsScreen(dds: _dds),
              TeleopScreen(dds: _dds, active: _index == _kTeleopIndex),
              SettingsScreen(settings: widget.settings),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 20,
            child: Center(
              child: _GlassNavBar(
                index: _index,
                onSelect: (i) => setState(() => _index = i),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;

  const _GlassNavBar({required this.index, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    // Sized to fill the available width (minus screen margins) rather
    // than sizing to content — with 5 tabs, letting the Row size
    // itself risks overflowing narrow phones; Expanded children inside
    // a fixed-width bar always fit, with the label as a safety net
    // against clipping if a very narrow tab still can't hold its text.
    final barWidth = (MediaQuery.of(context).size.width - 40).clamp(0.0, 420.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: barWidth,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.card.withValues(alpha: .55),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadowDark.withValues(alpha: .28),
                blurRadius: 28,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              for (var i = 0; i < _kNavDefs.length; i++)
                Expanded(child: _navItem(i)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(int i) {
    final def = _kNavDefs[i];
    final on = i == index;
    return GestureDetector(
      onTap: () => onSelect(i),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: on ? AppColors.accTint : Colors.transparent,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              def.icon,
              size: 19,
              color: on ? AppColors.acc2 : AppColors.ink3,
            ),
            const SizedBox(height: 3),
            Text(
              def.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.disp(
                size: 9.5,
                weight: FontWeight.w600,
                color: on ? AppColors.acc2 : AppColors.ink3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
