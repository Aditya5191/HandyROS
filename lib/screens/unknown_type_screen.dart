import 'package:flutter/material.dart';
import '../app/theme.dart';
import '../models/topic.dart';

class UnknownTypeScreen extends StatelessWidget {
  final Topic topic;

  const UnknownTypeScreen({super.key, required this.topic});

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink.withValues(alpha: .92),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        margin: const EdgeInsets.only(bottom: 40, left: 60, right: 60),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 20),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: AppColors.card,
                      boxShadow: raisedShadowSm,
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.of(context).maybePop(),
                        child: Icon(
                          Icons.arrow_back,
                          size: 22,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 13),
                  Text(
                    'Unknown type',
                    style: AppText.disp(size: 17, weight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        margin: const EdgeInsets.only(bottom: 24),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(30),
                          color: AppColors.card,
                          boxShadow: raisedShadow,
                        ),
                        child: Icon(
                          Icons.help_outline,
                          size: 46,
                          color: AppColors.ink3,
                        ),
                      ),
                      Text(
                        topic.type,
                        style: AppText.mono(size: 14, weight: FontWeight.w500),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No viewer is registered for this message type. Import its definition to decode and visualize it.',
                        textAlign: TextAlign.center,
                        style: AppText.body(size: 14, color: AppColors.ink2),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        topic.name,
                        style: AppText.mono(
                          size: 11,
                          weight: FontWeight.w500,
                          color: AppColors.ink3,
                        ),
                      ),
                      const SizedBox(height: 30),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: Material(
                          borderRadius: BorderRadius.circular(16),
                          color: AppColors.acc,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _toast(
                              context,
                              'Import .msg / .idl definition…',
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.upload_file,
                                  size: 21,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 9),
                                Text(
                                  'Import definition',
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
                      const SizedBox(height: 11),
                      Row(
                        children: [
                          Expanded(
                            child: _softButton(
                              'Ignore',
                              () => Navigator.of(context).maybePop(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: _softButton('Docs', () {})),
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
    );
  }

  Widget _softButton(String label, VoidCallback onTap) {
    return Container(
      height: 47,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        color: AppColors.card,
        boxShadow: raisedShadowSm,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              style: AppText.disp(
                size: 13,
                weight: FontWeight.w600,
                color: AppColors.ink2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
