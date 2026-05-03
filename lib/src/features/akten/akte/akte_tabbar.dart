import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import 'akte_counts.dart';

/// Ein einzelner Reiter in der Auftragsakte: Icon + Label + optionales
/// Anzahl-Badge. Visuell als Karteireiter umgesetzt (abgerundete obere Ecken,
/// weißer Hintergrund wenn aktiv, sonst transparent).
class AkteTabData {
  final String label;
  final IconData icon;
  final int? count;
  const AkteTabData({required this.label, required this.icon, this.count});
}

class AkteTabBar extends ConsumerWidget {
  const AkteTabBar({
    super.key,
    required this.auftragId,
    required this.kundeId,
    required this.controller,
  });
  final int auftragId;
  final int? kundeId;
  final TabController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    int c(AsyncValue<int> v) => v.valueOrNull ?? 0;
    final tabs = <AkteTabData>[
      const AkteTabData(label: 'Übersicht', icon: Icons.dashboard_outlined),
      const AkteTabData(
          label: 'Beteiligte', icon: Icons.groups_2_outlined),
      AkteTabData(
        label: 'Stunden',
        icon: Icons.schedule_outlined,
        count: c(ref.watch(stundenCountProvider(auftragId))),
      ),
      AkteTabData(
        label: 'Auslagen',
        icon: Icons.payments_outlined,
        count: c(ref.watch(auslagenCountProvider(auftragId))),
      ),
      AkteTabData(
        label: 'Rechnungen',
        icon: Icons.receipt_long_outlined,
        count: c(ref.watch(rechnungenCountProvider(auftragId))),
      ),
      AkteTabData(
        label: 'Angebote',
        icon: Icons.price_change_outlined,
        count: c(ref.watch(angeboteCountProvider(kundeId))),
      ),
      AkteTabData(
        label: 'Gutachten',
        icon: Icons.gavel_outlined,
        count: c(ref.watch(gutachtenCountProvider(auftragId))),
      ),
      AkteTabData(
        label: 'Fotos',
        icon: Icons.photo_library_outlined,
        count: c(ref.watch(fotosCountProvider(auftragId))),
      ),
      AkteTabData(
        label: 'Dokumente',
        icon: Icons.description_outlined,
        count: c(ref.watch(dokumenteCountProvider(auftragId))),
      ),
      AkteTabData(
        label: 'Normen',
        icon: Icons.menu_book_outlined,
        count: c(ref.watch(normenCountProvider(auftragId))),
      ),
      AkteTabData(
        label: 'Geräte',
        icon: Icons.precision_manufacturing_outlined,
        count: c(ref.watch(geraeteCountProvider(auftragId))),
      ),
      AkteTabData(
        label: 'Erläuterungen',
        icon: Icons.event_available_outlined,
        count: c(ref.watch(erlaeuterungenCountProvider(auftragId))),
      ),
      const AkteTabData(
        label: 'Gerichtssache',
        icon: Icons.gavel_outlined,
      ),
      AkteTabData(
        label: 'Nachfragen',
        icon: Icons.help_outline,
        count: c(ref.watch(nachfragenCountProvider(auftragId))),
      ),
      AkteTabData(
        label: 'Versand',
        icon: Icons.local_shipping_outlined,
        count: c(ref.watch(versandCountProvider(auftragId))),
      ),
      const AkteTabData(
        label: 'Anschreiben',
        icon: Icons.drafts_outlined,
      ),
      const AkteTabData(
        label: 'Protokolle',
        icon: Icons.fact_check_outlined,
      ),
      const AkteTabData(
        label: 'Journal',
        icon: Icons.history_edu_outlined,
      ),
      const AkteTabData(
        label: 'Mängel',
        icon: Icons.report_gmailerrorred_outlined,
      ),
      const AkteTabData(
        label: 'Übergabe',
        icon: Icons.handshake_outlined,
      ),
      const AkteTabData(
        label: 'Bauteilöffnung',
        icon: Icons.construction_outlined,
      ),
      const AkteTabData(
        label: 'Messwerte',
        icon: Icons.show_chart,
      ),
      const AkteTabData(
        label: 'Wertermittlung',
        icon: Icons.euro_symbol,
      ),
      const AkteTabData(
        label: 'Wirtschaftlichkeit',
        icon: Icons.euro_outlined,
      ),
      AkteTabData(
        label: 'LV / Kalkulation',
        icon: Icons.list_alt_outlined,
        count: c(ref.watch(lvCountProvider(auftragId))),
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.slate50,
        border: Border(
          bottom: BorderSide(color: AppTheme.slate200),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: AnimatedBuilder(
          animation: controller,
          builder: (_, _) => Row(
            children: [
              for (var i = 0; i < tabs.length; i++)
                _Karteireiter(
                  data: tabs[i],
                  active: controller.index == i,
                  onTap: () => controller.animateTo(i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Karteireiter extends StatefulWidget {
  const _Karteireiter({
    required this.data,
    required this.active,
    required this.onTap,
  });
  final AkteTabData data;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_Karteireiter> createState() => _KarteireiterState();
}

class _KarteireiterState extends State<_Karteireiter> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    // Active = Accent-Orange (wie aktiver Sidebar-Eintrag)
    // Hover = helles Grau (wie Sidebar-Hover)
    // Default = transparent
    final active = widget.active;
    final bgColor = active
        ? AppTheme.accent600
        : (_hovered ? AppTheme.slate100 : Colors.transparent);
    final fgColor = active
        ? Colors.white
        : (_hovered ? AppTheme.slate900 : AppTheme.slate700);
    final iconColor = active
        ? Colors.white
        : (_hovered ? AppTheme.slate700 : AppTheme.slate500);

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          color: bgColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(8),
            topRight: Radius.circular(8),
          ),
          child: InkWell(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(8),
              topRight: Radius.circular(8),
            ),
            onTap: widget.onTap,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.data.icon,
                    size: 16,
                    color: iconColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.data.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          active ? FontWeight.w700 : FontWeight.w500,
                      color: fgColor,
                    ),
                  ),
                  if (widget.data.count != null &&
                      widget.data.count! > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: active
                            ? Colors.white.withValues(alpha: 0.22)
                            : AppTheme.slate200,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${widget.data.count}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: active ? Colors.white : AppTheme.slate700,
                          fontFeatures: const [
                            FontFeature.tabularFigures()
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
