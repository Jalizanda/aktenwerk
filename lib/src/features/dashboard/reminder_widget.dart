import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/database/app_database.dart';
import '../../data/database/database_provider.dart';
import '../../shared/widgets/badges.dart';
import '../system/einstellungen/einstellungen_repository.dart';
import '../werkzeuge/termine/termine_repository.dart';

/// Einheitlicher Fristen-Eintrag fürs Dashboard-Widget.
class _Fristentry {
  final DateTime zeitpunkt;
  final String titel;
  final String quelle;
  final String? akte;
  final int? auftragId;
  final String? route; // Direktsprung-Ziel
  const _Fristentry({
    required this.zeitpunkt,
    required this.titel,
    required this.quelle,
    this.akte,
    this.auftragId,
    this.route,
  });
}

final _fristenRangeProvider = StateProvider<int>((ref) => 14);

/// Dashboard-Widget: listet **alle** fälligen Termine / Fristen der nächsten
/// N Tage gemischt (Termine, Rechnungs-Verzug, Eichungen, Siegel-Ablauf,
/// Wiedervorlagen). Klick springt zur Akte / zum Modul.
class ReminderWidget extends ConsumerWidget {
  const ReminderWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tage = ref.watch(_fristenRangeProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final bis = today.add(Duration(days: tage));

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side:
            BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.alarm_outlined),
                const SizedBox(width: 8),
                Text('Fällig in den nächsten $tage Tagen',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 7, label: Text('7')),
                    ButtonSegment(value: 14, label: Text('14')),
                    ButtonSegment(value: 30, label: Text('30')),
                  ],
                  selected: {tage},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => ref
                      .read(_fristenRangeProvider.notifier)
                      .state = s.first,
                ),
              ],
            ),
            const Divider(height: 20),
            _FristenListe(from: today, to: bis),
          ],
        ),
      ),
    );
  }
}

class _FristenListe extends ConsumerWidget {
  const _FristenListe({required this.from, required this.to});
  final DateTime from;
  final DateTime to;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDatabaseProvider);
    final termineAsync = ref.watch(termineListProvider);
    final settings = ref.watch(einstellungenProvider).valueOrNull ??
        const <String, String>{};

    return StreamBuilder<List<GeraeteData>>(
      stream: db.select(db.geraete).watch(),
      builder: (_, geraeteSnap) => StreamBuilder<List<RechnungenData>>(
        stream: db.select(db.rechnungen).watch(),
        builder: (_, rechnungenSnap) {
          final entries = <_Fristentry>[];

          // 1. Termine aus dem vereinten Repository
          final termine = termineAsync.valueOrNull ?? const <TerminEintrag>[];
          for (final t in termine) {
            if (t.zeitpunkt.isBefore(from) || t.zeitpunkt.isAfter(to)) continue;
            entries.add(_Fristentry(
              zeitpunkt: t.zeitpunkt,
              titel: t.titel,
              quelle: t.typ,
              akte: t.aktenzeichen,
              auftragId: t.auftragId,
              route: t.auftragId != null ? '/akte/${t.auftragId}' : '/termine',
            ));
          }

          // 2. Überfällige / bald fällige Rechnungen
          for (final r in rechnungenSnap.data ?? const <RechnungenData>[]) {
            if (r.status == 'bezahlt' || r.status == 'storniert') continue;
            final f = r.faelligAm;
            if (f == null) continue;
            if (f.isAfter(to)) continue;
            final overdue = f.isBefore(from);
            entries.add(_Fristentry(
              zeitpunkt: f,
              titel: overdue
                  ? 'Rechnung ${r.rechnungsnummer ?? ''} überfällig'
                  : 'Rechnung ${r.rechnungsnummer ?? ''} fällig',
              quelle: 'Rechnung',
              route: r.auftragId != null ? '/akte/${r.auftragId}' : '/opos',
            ));
          }

          // 3. Messgeräte-Eichungen
          for (final g in geraeteSnap.data ?? const <GeraeteData>[]) {
            final k = g.naechsteKalibrierung;
            if (k == null || k.isAfter(to)) continue;
            entries.add(_Fristentry(
              zeitpunkt: k,
              titel: 'Kalibrierung ${g.bezeichnung}',
              quelle: 'Messgerät',
              route: '/geraete',
            ));
          }

          // 4. Sachverständigen-Bestellung läuft aus
          final gueltigBisRaw = settings[SettingsKeys.siegelGueltigBis];
          if (gueltigBisRaw != null && gueltigBisRaw.isNotEmpty) {
            final gueltigBis = DateTime.tryParse(gueltigBisRaw);
            if (gueltigBis != null && !gueltigBis.isAfter(to)) {
              entries.add(_Fristentry(
                zeitpunkt: gueltigBis,
                titel: 'Sachverständigen-Bestellung läuft aus',
                quelle: 'Siegel',
                route: '/einstellungen',
              ));
            }
          }

          entries.sort((a, b) => a.zeitpunkt.compareTo(b.zeitpunkt));

          if (entries.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'Nichts anstehend — durchatmen!',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            );
          }

          return Column(
            children: [
              for (final e in entries.take(20))
                _FristRow(entry: e, from: from),
            ],
          );
        },
      ),
    );
  }
}

class _FristRow extends StatelessWidget {
  const _FristRow({required this.entry, required this.from});
  final _Fristentry entry;
  final DateTime from;

  @override
  Widget build(BuildContext context) {
    final days = DateTime(entry.zeitpunkt.year, entry.zeitpunkt.month,
            entry.zeitpunkt.day)
        .difference(from)
        .inDays;
    final (bg, fg, label) = _escalation(days);
    final dateFmt = DateFormat('dd.MM.', 'de');
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: entry.route == null ? null : () => context.go(entry.route!),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 54,
              child: Text(dateFmt.format(entry.zeitpunkt),
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()])),
            ),
            const SizedBox(width: 6),
            PillBadge(text: label, background: bg, foreground: fg),
            const SizedBox(width: 8),
            PillBadge(
              text: entry.quelle,
              background: BadgeColors.slateBg,
              foreground: BadgeColors.slateFg,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(entry.titel,
                  style: const TextStyle(fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            if (entry.akte != null)
              Text(entry.akte!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  static (Color, Color, String) _escalation(int days) {
    if (days < 0) {
      return (
        BadgeColors.redBg,
        BadgeColors.redFg,
        '${-days}\u00a0T überfällig'
      );
    }
    if (days == 0) return (BadgeColors.redBg, BadgeColors.redFg, 'heute');
    if (days <= 3) {
      return (BadgeColors.redBg, BadgeColors.redFg, 'in $days\u00a0T');
    }
    if (days <= 7) {
      return (BadgeColors.amberBg, BadgeColors.amberFg, 'in $days\u00a0T');
    }
    if (days <= 14) {
      return (BadgeColors.amberBg, BadgeColors.amberFg,
          'in $days\u00a0T');
    }
    return (BadgeColors.greenBg, BadgeColors.greenFg, 'in $days\u00a0T');
  }
}
