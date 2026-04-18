import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/router/nav_destinations.dart';
import '../akten/auftraege/auftraege_repository.dart';
import '../akten/rechnungen/rechnungen_repository.dart';
import '../werkzeuge/wiedervorlagen/wiedervorlagen_repository.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});
  static final _money = NumberFormat.currency(locale: 'de', symbol: '€');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final auftraege = ref.watch(auftraegeListProvider).valueOrNull ?? [];
    final rechnungen = ref.watch(rechnungenListProvider).valueOrNull ?? [];
    final wvOffen = ref
        .watch(wiedervorlagenListProvider)
        .valueOrNull ??
        [];

    final now = DateTime.now();
    final jahr = now.year;

    final offeneAuftraege = auftraege
        .where((a) =>
            a.auftrag.status != 'abgeschlossen' &&
            a.auftrag.status != 'abgerechnet' &&
            a.auftrag.status != 'storniert')
        .length;
    final offeneRechnungen = rechnungen
        .where((r) =>
            r.rechnung.status != 'bezahlt' &&
            r.rechnung.status != 'storniert')
        .length;
    final offenBetrag = rechnungen
        .where((r) =>
            r.rechnung.status != 'bezahlt' &&
            r.rechnung.status != 'storniert')
        .fold<double>(
            0, (acc, r) => acc + (r.rechnung.brutto - r.rechnung.bezahlt));
    final umsatzJahr = rechnungen
        .where((r) =>
            r.rechnung.rechnungsdatum?.year == jahr &&
            r.rechnung.status != 'storniert')
        .fold<double>(0, (acc, r) => acc + r.rechnung.netto);
    final heuteFaellig = wvOffen.where((w) {
      final d = w.eintrag.faelligAm;
      return d.year == now.year &&
          d.month == now.month &&
          d.day == now.day;
    }).length;

    final quickItems = <NavItem>[
      for (final s in navSections)
        for (final i in s.items)
          if (i.path != '/') i,
    ];

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Willkommen im Aktenwerk',
            style: theme.textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'Bausachverständigen-Verwaltung · Akten, Gutachten, Rechnungen, Angebote',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Stat(
                label: 'Offene Aufträge',
                value: offeneAuftraege.toString(),
                icon: Icons.assignment_outlined,
                onTap: () => context.go('/auftraege')),
            _Stat(
                label: 'Offene Rechnungen',
                value: offeneRechnungen.toString(),
                icon: Icons.request_page_outlined,
                sub: _money.format(offenBetrag),
                onTap: () => context.go('/rechnungen')),
            _Stat(
                label: 'Wiedervorlagen heute',
                value: heuteFaellig.toString(),
                icon: Icons.notifications_active_outlined,
                color: heuteFaellig > 0 ? theme.colorScheme.tertiary : null,
                onTap: () => context.go('/wiedervorlagen')),
            _Stat(
                label: 'Umsatz $jahr',
                value: _money.format(umsatzJahr),
                icon: Icons.euro_outlined,
                color: theme.colorScheme.primary,
                onTap: () => context.go('/steuer')),
          ],
        ),
        const SizedBox(height: 28),
        Text('Module', style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth > 1200
                ? 4
                : c.maxWidth > 800
                    ? 3
                    : c.maxWidth > 500
                        ? 2
                        : 1;
            return GridView.count(
              crossAxisCount: cols,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 3.0,
              children: [
                for (final item in quickItems) _QuickTile(item: item),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.icon,
    this.sub,
    this.color,
    this.onTap,
  });
  final String label;
  final String value;
  final IconData icon;
  final String? sub;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side:
              BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon,
                    color: color ?? Theme.of(context).colorScheme.primary,
                    size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                      Text(
                        value,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(
                                color: color, fontWeight: FontWeight.w700),
                      ),
                      if (sub != null)
                        Text(sub!,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    )),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({required this.item});
  final NavItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.go(item.path),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(item.icon, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(item.label, style: theme.textTheme.titleSmall),
              ),
              Icon(Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
