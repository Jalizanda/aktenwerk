import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../features/werkzeuge/termine/termine_repository.dart';
import '../../shared/widgets/badges.dart';

/// Kalender-Kachel in der Top-Bar. Zeigt das heutige Datum als Tagesblatt
/// mit großer Tageszahl und kleinem Monats-Kürzel; rechts davon farbige
/// Punkte mit Anzahl pro Kategorie (Ortstermin, Frist, Erläuterung,
/// Wiedervorlage). Klick springt ins Kalender-Modul. Popup zeigt die
/// heutigen Einträge im Detail.
class KalenderBadge extends ConsumerWidget {
  const KalenderBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(termineListProvider);
    final list = async.valueOrNull ?? const <TerminEintrag>[];
    final now = DateTime.now();
    final heute = list.where((t) => _isHeute(t.zeitpunkt, now)).toList();

    final counts = <String, int>{};
    for (final t in heute) {
      counts[t.typ] = (counts[t.typ] ?? 0) + 1;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _zeigePopup(context, heute, now),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.slate50,
            border: Border.all(color: AppTheme.slate200),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Tageskachel(datum: now),
              if (counts.isNotEmpty) ...[
                const SizedBox(width: 10),
                for (final e in _sortKategorien(counts.entries)) ...[
                  _KategoriePunkt(typ: e.key, anzahl: e.value),
                  const SizedBox(width: 4),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  static bool _isHeute(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<MapEntry<String, int>> _sortKategorien(
      Iterable<MapEntry<String, int>> entries) {
    const reihenfolge = [
      'Ortstermin',
      'Frist',
      'Erläuterung',
      'Wiedervorlage',
    ];
    final copy = entries.toList();
    copy.sort((a, b) {
      final ia = reihenfolge.indexOf(a.key);
      final ib = reihenfolge.indexOf(b.key);
      return (ia == -1 ? 99 : ia).compareTo(ib == -1 ? 99 : ib);
    });
    return copy;
  }

  /// ISO-8601-Kalenderwoche (Montag-Montag, Jahresübergang klemmt).
  static int _isoKw(DateTime d) {
    final dayOfYear = int.parse(DateFormat('D').format(d));
    return ((dayOfYear - d.weekday + 10) / 7).floor();
  }

  void _zeigePopup(
      BuildContext context, List<TerminEintrag> heute, DateTime now) {
    final fmt = DateFormat('EEEE, d. MMMM y', 'de');
    final kw = _isoKw(now);
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
                child: Row(
                  children: [
                    _Tageskachel(datum: now),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Heute',
                              style:
                                  Theme.of(context).textTheme.titleLarge),
                          Text('KW $kw · ${fmt.format(now)}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.slate500)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: heute.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                              'Keine Kalender-Einträge für heute.'),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: heute.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final t = heute[i];
                          final zeit =
                              DateFormat('HH:mm', 'de').format(t.zeitpunkt);
                          return ListTile(
                            leading: _KategoriePunkt(typ: t.typ, anzahl: 1),
                            title: Text(t.titel,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              [
                                zeit,
                                t.aktenzeichen,
                                t.ort,
                              ]
                                  .whereType<String>()
                                  .where((s) => s.trim().isNotEmpty)
                                  .join(' · '),
                              style: const TextStyle(fontSize: 12),
                            ),
                            onTap: () {
                              Navigator.of(ctx).pop();
                              if (t.auftragId != null) {
                                GoRouter.of(context)
                                    .go('/akte/${t.auftragId}');
                              }
                            },
                          );
                        },
                      ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.calendar_month_outlined,
                          size: 16),
                      label: const Text('Kalender öffnen'),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        GoRouter.of(context).go('/termine');
                      },
                    ),
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

/// Kleine Tageskachel: Monat oben als „APR", großer Tag darunter.
class _Tageskachel extends StatelessWidget {
  const _Tageskachel({required this.datum});
  final DateTime datum;
  @override
  Widget build(BuildContext context) {
    final monat = DateFormat('MMM', 'de').format(datum).toUpperCase();
    final tag = datum.day.toString();
    return Container(
      width: 40,
      height: 34,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Monats-Kürzel als „Wasserzeichen" im Hintergrund.
          Positioned(
            left: 0,
            right: 0,
            top: 1,
            child: Container(
              height: 10,
              color: AppTheme.accent600,
              alignment: Alignment.center,
              child: Text(
                monat,
                style: const TextStyle(
                  fontSize: 7,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 12,
            bottom: 0,
            child: Center(
              child: Text(
                tag,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Farbiger Punkt mit Anzahl pro Termin-Typ.
class _KategoriePunkt extends StatelessWidget {
  const _KategoriePunkt({required this.typ, required this.anzahl});
  final String typ;
  final int anzahl;

  @override
  Widget build(BuildContext context) {
    final farbe = _farbeFuer(typ);
    return Tooltip(
      message: '$anzahl × $typ',
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: farbe.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: farbe.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration:
                  BoxDecoration(color: farbe, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Text(
              '$anzahl',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: farbe),
            ),
          ],
        ),
      ),
    );
  }

  Color _farbeFuer(String typ) {
    switch (typ) {
      case 'Ortstermin':
        return BadgeColors.greenFg;
      case 'Frist':
        return BadgeColors.redFg;
      case 'Erläuterung':
        return const Color(0xFF2563EB);
      case 'Wiedervorlage':
        return BadgeColors.amberFg;
    }
    return AppTheme.slate500;
  }
}
