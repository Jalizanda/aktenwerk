import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/aw_tokens.dart';
import '../../data/sync/auth_service.dart';
import '../akten/auftraege/auftraege_repository.dart';
import '../akten/auftraege/auftraege_form.dart';

String _greeting() {
  final h = DateTime.now().hour;
  if (h < 5) return 'Gute Nacht';
  if (h < 11) return 'Guten Morgen';
  if (h < 18) return 'Guten Tag';
  return 'Guten Abend';
}

/// Mobile-Home-Screen — hebt Sachverständigen-Kernaufgaben als
/// Kacheln heraus (Ortstermin, Auftragsakte, Kontakte, Termine, …).
/// Wird auf schmalen Viewports (< ~720 px) anstelle des dichten
/// Desktop-Dashboards gerendert.
class MobileHome extends ConsumerWidget {
  const MobileHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auftraegeAsync = ref.watch(auftraegeListProvider);
    final offenCount = auftraegeAsync.valueOrNull
            ?.where((a) =>
                a.auftrag.status != 'abgeschlossen' &&
                a.auftrag.status != 'abgerechnet' &&
                a.auftrag.status != 'storniert')
            .length ??
        0;

    final user = ref.watch(authStateProvider).valueOrNull;
    final vorname = (user?.displayName ?? '').trim().split(' ').first;
    final greeting = _greeting();
    final heute = DateFormat('EEEE, d. MMMM', 'de').format(DateTime.now());
    final heuteCap = heute.substring(0, 1).toUpperCase() + heute.substring(1);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // Eyebrow + H1
        const Text(
          'QUICK-ZUGRIFF',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 11 * 0.05,
            color: AwTokens.mute,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          vorname.isEmpty ? '$greeting.' : '$greeting, $vorname.',
          style: const TextStyle(
            fontSize: AwTokens.textH1,
            fontWeight: FontWeight.w600,
            letterSpacing: AwTokens.textH1 * -0.025,
            color: AwTokens.ink,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$heuteCap · $offenCount offene Akten',
          style: const TextStyle(
              fontSize: AwTokens.textMd, color: AwTokens.mute),
        ),
        const SizedBox(height: 20),

        // Primary Action — Ortstermin starten (volle Breite, Ink-BG,
        // Orange-Akzent): größter Call-to-Action im Außendienst.
        _PrimaryTile(
          icon: Icons.location_on_outlined,
          eyebrow: 'VOR ORT',
          title: 'Ortstermin starten',
          subtitle: 'Fotos, Messwerte, Protokoll aufnehmen',
          onTap: () => context.go('/ortstermin'),
        ),
        const SizedBox(height: 12),

        // 2×N Grid für die restlichen Kernaktionen.
        _TileGrid(children: [
          _ActionTile(
            icon: Icons.folder_open_outlined,
            label: 'Auftragsakte',
            sub: 'öffnen / suchen',
            onTap: () => context.go('/akten'),
          ),
          _ActionTile(
            icon: Icons.add_circle_outline,
            label: 'Neuer Auftrag',
            sub: 'Akte anlegen',
            onTap: () => showAuftragFormDialog(context),
          ),
          _ActionTile(
            icon: Icons.people_outline,
            label: 'Kontakte',
            sub: 'Auftraggeber, Partner',
            onTap: () => context.go('/kunden'),
          ),
          _ActionTile(
            icon: Icons.calendar_month_outlined,
            label: 'Kalender',
            sub: 'Termine · Fristen',
            onTap: () => context.go('/termine'),
          ),
          _ActionTile(
            icon: Icons.event_available_outlined,
            label: 'Erläuterungstermin',
            sub: 'Gerichtstermin',
            onTap: () => context.go('/erlaeuterungen'),
          ),
          _ActionTile(
            icon: Icons.gavel_outlined,
            label: 'Gutachten',
            sub: 'verfassen · prüfen',
            onTap: () => context.go('/gutachten'),
          ),
          _ActionTile(
            icon: Icons.photo_library_outlined,
            label: 'Fotos',
            sub: 'Ortstermin-Bilder',
            onTap: () => context.go('/fotos'),
          ),
          _ActionTile(
            icon: Icons.schedule_outlined,
            label: 'Stunden',
            sub: 'Zeit erfassen',
            onTap: () => context.go('/stunden'),
          ),
          _ActionTile(
            icon: Icons.receipt_long_outlined,
            label: 'Rechnungen',
            sub: 'offene · Mahnungen',
            onTap: () => context.go('/rechnungen'),
          ),
          _ActionTile(
            icon: Icons.bookmark_add_outlined,
            label: 'Wiedervorlagen',
            sub: 'anstehende Tasks',
            onTap: () => context.go('/wiedervorlagen'),
          ),
        ]),
      ],
    );
  }
}

class _PrimaryTile extends StatelessWidget {
  const _PrimaryTile({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String eyebrow;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AwTokens.ink,
      borderRadius: BorderRadius.circular(AwTokens.radiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AwTokens.radiusLg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AwTokens.orange,
                  borderRadius: BorderRadius.circular(AwTokens.radiusMd),
                ),
                child: Icon(icon, color: AwTokens.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eyebrow,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 10 * 0.08,
                        color: Color(0xB3FFFFFF),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 17 * -0.015,
                        color: AwTokens.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xE6FFFFFF),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: AwTokens.orange, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth > 480 ? 3 : 2;
        return GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          // Querformat: Icon links, Text rechts — flacher als Quadrat.
          childAspectRatio: cols == 3 ? 2.0 : 2.2,
          children: children,
        );
      },
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.sub,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AwTokens.white,
      borderRadius: BorderRadius.circular(AwTokens.radiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AwTokens.radiusLg),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AwTokens.radiusLg),
            border: Border.all(color: AwTokens.line),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, color: AwTokens.orange, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 13.5 * -0.01,
                          color: AwTokens.ink,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AwTokens.mute,
                          height: 1.2,
                        ),
                      ),
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
