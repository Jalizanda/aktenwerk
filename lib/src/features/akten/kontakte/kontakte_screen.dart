import 'package:flutter/material.dart';

import '../../../core/theme/aw_tokens.dart';
import '../kunden/kunden_screen.dart';
import '../lieferanten/lieferanten_screen.dart';
import '../partner/partner_screen.dart';

/// Unified contacts screen with three tabs:
/// Auftraggeber (Kunden) | Lieferanten | Partner / Subunternehmer
class KontakteScreen extends StatefulWidget {
  const KontakteScreen({super.key});

  @override
  State<KontakteScreen> createState() => _KontakteScreenState();
}

class _KontakteScreenState extends State<KontakteScreen>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _KontakteTabBar(controller: _tabs),
        const Divider(height: 1),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: const [
              KundenScreen(),
              LieferantenScreen(),
              PartnerScreen(),
            ],
          ),
        ),
      ],
    );
  }
}

class _KontakteTabBar extends StatelessWidget {
  const _KontakteTabBar({required this.controller});
  final TabController controller;

  static const _tabs = <(String, IconData)>[
    ('Auftraggeber', Icons.people_outline),
    ('Lieferanten', Icons.local_shipping_outlined),
    ('Partner / Subunternehmer', Icons.handshake_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerLowest,
      child: AnimatedBuilder(
        animation: controller,
        builder: (_, _) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < _tabs.length; i++)
                _KontakteReiter(
                  label: _tabs[i].$1,
                  icon: _tabs[i].$2,
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

class _KontakteReiter extends StatelessWidget {
  const _KontakteReiter({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? AwTokens.orange : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: active
                  ? AwTokens.orange
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active
                    ? AwTokens.orange
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
