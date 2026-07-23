import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app/theme.dart';
import '../core/viewer_plugin.dart';
import '../services/app_settings.dart';

/// The Settings tab. Functionality is unchanged from before this
/// re-skin — real editable ROS Domain ID (persisted, applies next
/// connect) and a real Light/Dark/System theme toggle, plus the
/// (accurate) registered-viewers list. No RMW selector, message-defs
/// list, animation toggles, or accent picker — those were removed
/// earlier for being fake/non-functional and stay removed.
class SettingsScreen extends StatefulWidget {
  final AppSettings settings;

  const SettingsScreen({super.key, required this.settings});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _domainController = TextEditingController(
    text: '${widget.settings.domainId}',
  );

  @override
  void dispose() {
    _domainController.dispose();
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

  Future<void> _applyDomainId() async {
    final parsed = int.tryParse(_domainController.text.trim());
    if (parsed == null || parsed < 0 || parsed > 232) {
      _toast('Domain ID must be 0–232');
      _domainController.text = '${widget.settings.domainId}';
      return;
    }
    await widget.settings.setDomainId(parsed);
    if (mounted) {
      _toast(
        'Domain $parsed will apply next time HandyROS connects — restart the app',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  'HandyROS v1.0',
                  style: AppText.body(
                    size: 13,
                    weight: FontWeight.w500,
                    color: AppColors.ink3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Settings',
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
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 112),
              children: [
                _sectionLabel('COMMUNICATION'),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: panelDecoration(radius: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Middleware',
                        style: AppText.disp(
                          size: 12,
                          weight: FontWeight.w500,
                          color: AppColors.ink2,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        'Cyclone DDS',
                        style: AppText.mono(size: 13, weight: FontWeight.w600),
                      ),
                      const SizedBox(height: 15),
                      Text(
                        'ROS Domain ID',
                        style: AppText.disp(
                          size: 12,
                          weight: FontWeight.w500,
                          color: AppColors.ink2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 13,
                              ),
                              decoration: recessedDecoration(radius: 12),
                              child: TextField(
                                controller: _domainController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                style: AppText.mono(
                                  size: 14,
                                  weight: FontWeight.w600,
                                ),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                ),
                                onSubmitted: (_) => _applyDomainId(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 9),
                          Material(
                            color: Colors.transparent,
                            child: Ink(
                              height: 46,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: AppColors.acc,
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: _applyDomainId,
                                child: Center(
                                  child: Text(
                                    'SET',
                                    style: AppText.disp(
                                      size: 12,
                                      weight: FontWeight.w600,
                                      color: Colors.white,
                                      letterSpacing: .5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Must match ROS_DOMAIN_ID on your ROS 2 machine. Takes effect the next time the app connects.',
                        style: AppText.body(size: 11, color: AppColors.ink3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _sectionLabel('APPEARANCE'),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: panelDecoration(radius: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Theme',
                        style: AppText.disp(
                          size: 12,
                          weight: FontWeight.w500,
                          color: AppColors.ink2,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: recessedDecoration(radius: 15),
                        child: Row(
                          children: [
                            Expanded(
                              child: _themeOption(
                                ThemeMode.light,
                                'Light',
                                Icons.light_mode,
                              ),
                            ),
                            Expanded(
                              child: _themeOption(
                                ThemeMode.dark,
                                'Dark',
                                Icons.dark_mode,
                              ),
                            ),
                            Expanded(
                              child: _themeOption(
                                ThemeMode.system,
                                'System',
                                Icons.smartphone,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        'REGISTERED VIEWERS',
                        style: AppText.disp(
                          size: 10,
                          weight: FontWeight.w600,
                          color: AppColors.ink3,
                          letterSpacing: .9,
                        ),
                      ),
                    ),
                    Text(
                      '${ViewerRegistry.plugins.length} plugins',
                      style: AppText.mono(
                        size: 10,
                        weight: FontWeight.w500,
                        color: AppColors.acc2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 11),
                for (final p in ViewerRegistry.plugins) _viewerRow(p),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    'Mobile ROS 2 inspector · build 2026.07',
                    style: AppText.mono(
                      size: 10,
                      weight: FontWeight.w500,
                      color: AppColors.ink3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _themeOption(ThemeMode mode, String label, IconData icon) {
    final on = widget.settings.themeMode == mode;
    return GestureDetector(
      onTap: () => widget.settings.setThemeMode(mode),
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          color: on ? AppColors.card : Colors.transparent,
          boxShadow: on ? raisedShadowSm : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: on ? AppColors.acc2 : AppColors.ink3),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppText.disp(
                size: 12,
                weight: FontWeight.w600,
                color: on ? AppColors.acc2 : AppColors.ink3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _viewerRow(ViewerPlugin p) {
    final isFallback = !p.builtIn;
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: panelDecoration(radius: 17, small: true),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: AppGradients.iconBadge,
            ),
            child: Icon(p.icon, size: 20, color: p.color),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.label,
                  style: AppText.disp(size: 13, weight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  p.types.join(', '),
                  style: AppText.mono(
                    size: 9.5,
                    weight: FontWeight.w500,
                    color: AppColors.ink3,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              color: isFallback ? AppColors.bg : AppColors.accTint,
            ),
            child: Text(
              isFallback ? 'FALLBACK' : 'BUILT-IN',
              style: AppText.disp(
                size: 8,
                weight: FontWeight.w600,
                color: isFallback ? AppColors.ink3 : AppColors.acc2,
                letterSpacing: .4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
