import 'package:flutter/material.dart';

import '../../core/theme/aw_tokens.dart';

/// Side-Sheet (rechts, 520 px) nach AW-Guideline DIALOGS §6.
///
/// Einsatz: Quick-Inspector in Listen (Kontakt, Gutachten-Vorschau,
/// Filter-Detail). Overlay mit Ink 38 % Deckkraft, Panel slidet von
/// rechts rein (200 ms).
///
/// Aufruf:
/// ```dart
/// await showAwSideSheet(
///   context,
///   title: 'Akte AW-0046',
///   eyebrow: 'QUICK-INSPECTOR',
///   body: MyInspectorContent(...),
///   footerRight: FilledButton(onPressed: ..., child: Text('Öffnen')),
/// );
/// ```
Future<T?> showAwSideSheet<T>(
  BuildContext context, {
  required String title,
  required Widget body,
  String? eyebrow,
  double width = AwTokens.sideSheetWidth,
  List<Widget> footerLeft = const [],
  List<Widget> footerRight = const [],
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierColor: const Color(0x610B1220), // Ink 38 %
    barrierDismissible: barrierDismissible,
    barrierLabel: 'Seitenleiste',
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, _, _) => _AwSideSheetShell(
      title: title,
      eyebrow: eyebrow,
      width: width,
      footerLeft: footerLeft,
      footerRight: footerRight,
      child: body,
    ),
    transitionBuilder: (context, anim, _, child) {
      final slide = Tween<Offset>(
        begin: const Offset(1.0, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutCubic,
      ));
      return SlideTransition(position: slide, child: child);
    },
  );
}

class _AwSideSheetShell extends StatelessWidget {
  const _AwSideSheetShell({
    required this.title,
    required this.eyebrow,
    required this.width,
    required this.child,
    required this.footerLeft,
    required this.footerRight,
  });
  final String title;
  final String? eyebrow;
  final double width;
  final Widget child;
  final List<Widget> footerLeft;
  final List<Widget> footerRight;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: AwTokens.white,
        child: SizedBox(
          width: width,
          height: MediaQuery.of(context).size.height,
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AwTokens.line)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (eyebrow != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                eyebrow!.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 10 * 0.05,
                                  color: AwTokens.mute,
                                  height: 1,
                                ),
                              ),
                            ),
                          Text(
                            title,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 15 * -0.015,
                              color: AwTokens.ink,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      iconSize: 16,
                      icon: const Icon(Icons.close),
                      color: AwTokens.mute,
                      tooltip: 'Schließen',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(color: AwTokens.white, child: child),
              ),
              if (footerLeft.isNotEmpty || footerRight.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 14),
                  decoration: const BoxDecoration(
                    color: AwTokens.paper,
                    border: Border(top: BorderSide(color: AwTokens.line)),
                  ),
                  child: Row(
                    children: [
                      ...footerLeft,
                      const Spacer(),
                      ...footerRight,
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
