import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../data/database/app_database.dart';
import '../../shared/charts/chart_theme.dart';
import '../../shared/widgets/badges.dart';
import '../akten/auftraege/auftraege_repository.dart';
import '../akten/kunden/kunden_repository.dart';
import '../akten/rechnungen/rechnungen_repository.dart';
import '../angebote/angebote/angebote_repository.dart';
import '../auswertung/fortbildungen/fortbildungen_repository.dart';
import '../kalkulation/stunden/stunden_repository.dart';
import '../werkzeuge/geraete/geraete_repository.dart';
import '../werkzeuge/wiedervorlagen/wiedervorlagen_repository.dart';
import 'reminder_widget.dart';

/// Dashboard: Überblick über die gesamte Sachverständigen-Tätigkeit.
///
/// Layout: Kopf-KPIs (Auftrags-Status), Quick-Actions, danach ein
/// **Masonry-artiges Wrap-Grid** aus Kacheln. Jede Kachel hat eine
/// Ziel-Breite (~360 px); bei breiterem Viewport werden sie nebeneinander
/// angeordnet, bei schmalem Viewport automatisch untereinander.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  static final _dateFmt = DateFormat('dd.MM.yyyy', 'de');
  static final _dateTimeFmt = DateFormat('dd.MM.yyyy, HH:mm', 'de');
  static final _monthFmt = DateFormat('MMM', 'de');
  static final _money =
      NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final auftraegeAsync = ref.watch(auftraegeListProvider);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Dashboard', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'Übersicht über deine Sachverständigentätigkeit',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        const _QuickActionsBar(),
        const SizedBox(height: 16),
        auftraegeAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('Fehler: $e'),
          data: (auftraege) => _buildBody(context, ref, auftraege),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref,
      List<AuftragWithKunde> auftraege) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // ---- Auftrags-Status-Listen ----
    final offenList = auftraege
        .where((a) => a.auftrag.status == 'offen')
        .toList()
      ..sort((a, b) => b.auftrag.createdAt.compareTo(a.auftrag.createdAt));
    final laufendList = auftraege
        .where((a) =>
            a.auftrag.status == 'in_arbeit' ||
            a.auftrag.status == 'laufend')
        .toList()
      ..sort((a, b) => b.auftrag.createdAt.compareTo(a.auftrag.createdAt));
    final abgeschlossenList = auftraege
        .where((a) =>
            a.auftrag.status == 'abgeschlossen' ||
            a.auftrag.status == 'abgerechnet')
        .toList()
      ..sort((a, b) => b.auftrag.createdAt.compareTo(a.auftrag.createdAt));
    final rechnungenAll =
        ref.watch(rechnungenListProvider).valueOrNull ?? const [];

    // ---- Fristen & Termine ----
    final offeneFristen = auftraege
        .where((a) =>
            a.auftrag.abschlussAm != null &&
            a.auftrag.status != 'abgeschlossen' &&
            a.auftrag.status != 'abgerechnet' &&
            a.auftrag.status != 'storniert')
        .toList()
      ..sort((a, b) =>
          a.auftrag.abschlussAm!.compareTo(b.auftrag.abschlussAm!));
    final naechsteFristen = offeneFristen.take(5).toList();
    final naechsteFrist =
        offeneFristen.isEmpty ? null : offeneFristen.first;

    final kommendeTermine = auftraege
        .where((a) =>
            a.auftrag.ortsterminAm != null &&
            a.auftrag.ortsterminAm!.isAfter(
                today.subtract(const Duration(days: 1))))
        .toList()
      ..sort((a, b) =>
          a.auftrag.ortsterminAm!.compareTo(b.auftrag.ortsterminAm!));
    final naechsterTermin =
        kommendeTermine.isEmpty ? null : kommendeTermine.first;

    // ---- Recent ----
    final recent = [...auftraege]
      ..sort((a, b) =>
          b.auftrag.createdAt.compareTo(a.auftrag.createdAt));
    final recentSlice = recent.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AuftragsListRow(
          offenList: offenList,
          laufendList: laufendList,
          abgeschlossenList: abgeschlossenList,
          rechnungen: rechnungenAll,
        ),
        const SizedBox(height: 16),
        const ReminderWidget(),
        const SizedBox(height: 20),
        // Masonry-Grid: Kacheln werden automatisch nebeneinander oder
        // untereinander angeordnet, je nach Viewport-Breite.
        LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth;
          final targetWidth = w >= 1400
              ? (w - 24 * 2) / 3
              : (w >= 900 ? (w - 12) / 2 : w);
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: targetWidth,
                child: _FinanzenCard(),
              ),
              SizedBox(
                width: targetWidth,
                child: _PipelineCard(),
              ),
              SizedBox(
                width: targetWidth,
                child: _StundenCard(),
              ),
              SizedBox(
                width: targetWidth,
                child: _HeuteCard(today: today, auftraege: auftraege),
              ),
              SizedBox(
                width: targetWidth,
                child: _FristenListeCard(
                  items: naechsteFristen,
                  today: today,
                ),
              ),
              SizedBox(
                width: targetWidth,
                child: _TermineCard(
                  naechsterTermin: naechsterTermin,
                  naechsteFrist: naechsteFrist,
                  today: today,
                ),
              ),
              SizedBox(
                width: targetWidth,
                child: _UmsatzChartCard(),
              ),
              SizedBox(
                width: targetWidth,
                child: _KalibrierungCard(),
              ),
              SizedBox(
                width: targetWidth,
                child: _FortbildungCard(),
              ),
              SizedBox(
                width: w >= 1400 ? targetWidth * 2 + 12 : targetWidth,
                child: _RecentTable(items: recentSlice),
              ),
            ],
          );
        }),
      ],
    );
  }
}

/// ---------------- Quick-Actions ----------------

class _QuickActionsBar extends StatelessWidget {
  const _QuickActionsBar();
  @override
  Widget build(BuildContext context) {
    Widget action(String label, IconData icon, String route) {
      return OutlinedButton.icon(
        onPressed: () => context.go(route),
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: AppTheme.slate900,
          side: const BorderSide(color: AppTheme.slate200),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        action('+ Auftrag', Icons.assignment_outlined, '/auftraege'),
        action('+ Rechnung', Icons.request_page_outlined, '/rechnungen'),
        action('+ Angebot', Icons.price_change_outlined, '/angebote'),
        action('+ Auftraggeber', Icons.person_add_alt_1_outlined, '/kunden'),
        action('Stunden buchen', Icons.schedule_outlined, '/stunden'),
        action('Ortstermin', Icons.location_on_outlined, '/ortstermin'),
      ],
    );
  }
}

/// ---------------- Auftrags-Listen-Row ----------------
///
/// 4 Kacheln nebeneinander: Offene Aufträge, In Bearbeitung, Abgeschlossen,
/// Auftraggeber. Jede Kachel zeigt Anzahl, Summe und eine klickbare Liste
/// (max. 5 Einträge). Klick auf Eintrag → Akte/Kunden öffnen.
class _AuftragsListRow extends StatelessWidget {
  const _AuftragsListRow({
    required this.offenList,
    required this.laufendList,
    required this.abgeschlossenList,
    required this.rechnungen,
  });
  final List<AuftragWithKunde> offenList;
  final List<AuftragWithKunde> laufendList;
  final List<AuftragWithKunde> abgeschlossenList;
  final List<RechnungWithKunde> rechnungen;

  double _sumForAuftraege(List<AuftragWithKunde> items) {
    final ids = items.map((a) => a.auftrag.id).toSet();
    double total = 0;
    for (final r in rechnungen) {
      if (r.rechnung.status == 'storniert') continue;
      if (r.rechnung.auftragId != null && ids.contains(r.rechnung.auftragId)) {
        total += r.rechnung.brutto;
      }
    }
    // Fallback: für Aufträge ohne Rechnung den Kostenvorschuss/-Limit
    // mit einberechnen, damit auch vorab ein grober Wert sichtbar ist.
    for (final a in items) {
      final hatRechnung = rechnungen.any((r) =>
          r.rechnung.auftragId == a.auftrag.id &&
          r.rechnung.status != 'storniert');
      if (!hatRechnung) {
        total += a.auftrag.kostenLimit ?? a.auftrag.kostenvorschuss ?? 0;
      }
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      // Drei Kacheln statt vier — die Auftraggeber-Kachel ist entfernt.
      final cols = w >= 1100 ? 3 : (w >= 700 ? 2 : 1);
      final cardWidth = (w - (cols - 1) * 12) / cols;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          SizedBox(
            width: cardWidth,
            child: _AuftragsListCard(
              label: 'Offene Aufträge',
              bg: BadgeColors.blueBg,
              fg: BadgeColors.blueFg,
              items: offenList,
              summe: _sumForAuftraege(offenList),
              allRoute: '/auftraege',
            ),
          ),
          SizedBox(
            width: cardWidth,
            child: _AuftragsListCard(
              label: 'In Bearbeitung',
              bg: BadgeColors.amberBg,
              fg: BadgeColors.amberFg,
              items: laufendList,
              summe: _sumForAuftraege(laufendList),
              allRoute: '/auftraege',
            ),
          ),
          SizedBox(
            width: cardWidth,
            child: _AuftragsListCard(
              label: 'Abgeschlossen',
              bg: BadgeColors.greenBg,
              fg: BadgeColors.greenFg,
              items: abgeschlossenList,
              summe: _sumForAuftraege(abgeschlossenList),
              allRoute: '/auftraege',
            ),
          ),
        ],
      );
    });
  }
}

class _AuftragsListCard extends StatelessWidget {
  const _AuftragsListCard({
    required this.label,
    required this.bg,
    required this.fg,
    required this.items,
    required this.summe,
    required this.allRoute,
  });
  final String label;
  final Color bg;
  final Color fg;
  final List<AuftragWithKunde> items;
  final double summe;
  final String allRoute;

  @override
  Widget build(BuildContext context) {
    final top = items.take(5).toList();
    return _DashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Kopf-Bereich: Label + Count + Summe.
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.08 * 10.5,
                    color: AppTheme.slate500,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${items.length}',
                        style: TextStyle(
                          color: fg,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          height: 1.0,
                          fontFeatures: const [
                            FontFeature.tabularFigures()
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        DashboardScreen._money.format(summe),
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          fontFeatures: [
                            FontFeature.tabularFigures()
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Liste oder Empty-State.
          if (top.isEmpty)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                'Keine Einträge in dieser Kategorie.',
                style: TextStyle(
                    fontSize: 12.5, color: AppTheme.slate500),
              ),
            )
          else
            for (var i = 0; i < top.length; i++) ...[
              if (i > 0)
                const Divider(height: 1, indent: 14, endIndent: 14),
              _AuftragsRow(entry: top[i]),
            ],
          if (items.length > 5) ...[
            const Divider(height: 1),
            InkWell(
              onTap: () => context.go(allRoute),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    vertical: 8, horizontal: 14),
                child: Text(
                  '+ ${items.length - 5} weitere →',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.accent700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Einzelne Zeile in einer Auftrags-Listen-Kachel: Aktenzeichen · Betreff ·
/// Auftraggeber. Klick springt in die Akte.
class _AuftragsRow extends StatelessWidget {
  const _AuftragsRow({required this.entry});
  final AuftragWithKunde entry;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go('/akte/${entry.auftrag.id}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(
                entry.auftrag.aktenzeichen ?? '—',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.accent700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.auftrag.betreff ??
                        entry.auftrag.bezeichnung ??
                        '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (entry.kunde != null)
                    Text(
                      kundeAnzeigename(entry.kunde!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11, color: AppTheme.slate500),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: AppTheme.slate400),
          ],
        ),
      ),
    );
  }
}


/// ---------------- Basis-Kachel ----------------

class _DashCard extends StatelessWidget {
  const _DashCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.slate200),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

Widget _cardHeader(BuildContext context, String title,
    {Widget? trailing}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(title,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700)),
        ),
        ?trailing,
      ],
    ),
  );
}

/// ---------------- Finanzen-Kachel ----------------

class _FinanzenCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rechnungen =
        ref.watch(rechnungenListProvider).valueOrNull ?? const [];
    final now = DateTime.now();
    final monat = DateTime(now.year, now.month, 1);
    double offen = 0;
    double ueberfaellig = 0;
    double umsatzMonat = 0;
    double umsatzVormonat = 0;
    final vormonatStart = DateTime(now.year, now.month - 1, 1);
    for (final r in rechnungen) {
      final rd = r.rechnung.rechnungsdatum;
      if (r.rechnung.status != 'storniert' &&
          r.rechnung.status != 'bezahlt') {
        offen += r.rechnung.brutto - r.rechnung.bezahlt;
        if (r.rechnung.faelligAm != null &&
            r.rechnung.faelligAm!.isBefore(now)) {
          ueberfaellig += r.rechnung.brutto - r.rechnung.bezahlt;
        }
      }
      if (rd != null && r.rechnung.status != 'storniert') {
        if (rd.isAfter(monat.subtract(const Duration(days: 1)))) {
          umsatzMonat += r.rechnung.netto;
        }
        if (rd.isAfter(vormonatStart.subtract(const Duration(days: 1))) &&
            rd.isBefore(monat)) {
          umsatzVormonat += r.rechnung.netto;
        }
      }
    }
    final delta = umsatzVormonat == 0
        ? null
        : ((umsatzMonat - umsatzVormonat) / umsatzVormonat * 100);
    return _DashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardHeader(context, 'Finanzen',
              trailing: TextButton(
                onPressed: () => context.go('/rechnungen'),
                child: const Text('alle →'),
              )),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _financeRow('Offene Forderungen',
                    DashboardScreen._money.format(offen),
                    BadgeColors.amberFg),
                const SizedBox(height: 6),
                _financeRow('davon überfällig',
                    DashboardScreen._money.format(ueberfaellig),
                    BadgeColors.redFg,
                    bold: ueberfaellig > 0),
                const Divider(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Umsatz ${DashboardScreen._monthFmt.format(now)}',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.slate500)),
                          Text(
                              DashboardScreen._money.format(umsatzMonat),
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                    if (delta != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: delta >= 0
                              ? BadgeColors.greenBg
                              : BadgeColors.redBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${delta >= 0 ? '▲' : '▼'} ${delta.abs().toStringAsFixed(0)} %',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: delta >= 0
                                ? BadgeColors.greenFg
                                : BadgeColors.redFg,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _financeRow(String label, String value, Color color,
      {bool bold = false}) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: const TextStyle(fontSize: 12.5)),
        ),
        Text(value,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            )),
      ],
    );
  }
}

/// ---------------- Pipeline-Kachel ----------------

class _PipelineCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final angebote =
        ref.watch(angeboteListProvider).valueOrNull ?? const [];
    const offenStati = ['anfrage', 'angebot', 'nachverhandlung', 'entwurf',
        'versendet'];
    final offenPipeline = angebote
        .where((a) => offenStati.contains(a.angebot.status))
        .toList();
    final offenSumme = offenPipeline.fold<double>(
        0, (s, a) => s + a.angebot.brutto);
    final entschieden = angebote.where((a) =>
        a.angebot.status == 'angenommen' ||
        a.angebot.status == 'auftragsbestaetigung' ||
        a.angebot.status == 'abgelehnt' ||
        a.angebot.status == 'abgelaufen');
    final angenommen = entschieden
        .where((a) =>
            a.angebot.status == 'angenommen' ||
            a.angebot.status == 'auftragsbestaetigung')
        .length;
    final conv = entschieden.isEmpty
        ? null
        : (angenommen / entschieden.length * 100);
    return _DashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardHeader(context, 'Pipeline / Angebote',
              trailing: TextButton(
                onPressed: () => context.go('/angebote'),
                child: const Text('alle →'),
              )),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Offen',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.slate500)),
                      Text('${offenPipeline.length}',
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w800)),
                      Text(
                        DashboardScreen._money.format(offenSumme),
                        style: const TextStyle(
                            fontSize: 12,
                            color: BadgeColors.amberFg,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Conversion',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.slate500)),
                      Text(
                        conv == null
                            ? '—'
                            : '${conv.toStringAsFixed(0)} %',
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w800),
                      ),
                      Text(
                        conv == null
                            ? 'noch keine entschiedenen Angebote'
                            : '$angenommen von ${entschieden.length} gewonnen',
                        style: TextStyle(
                            fontSize: 11, color: AppTheme.slate500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------------- Stunden-Kachel ----------------

class _StundenCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stunden =
        ref.watch(stundenListProvider).valueOrNull ?? const [];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final wochenStart = today.subtract(Duration(days: today.weekday - 1));
    int minHeute = 0;
    int minWoche = 0;
    double offenBetrag = 0;
    for (final s in stunden) {
      final d = s.stunde.datum;
      if (d.year == today.year &&
          d.month == today.month &&
          d.day == today.day) {
        minHeute += s.stunde.minuten;
      }
      if (d.isAfter(wochenStart.subtract(const Duration(seconds: 1)))) {
        minWoche += s.stunde.minuten;
      }
      if (!s.stunde.abgerechnet) {
        offenBetrag +=
            (s.stunde.minuten / 60.0) * (s.stunde.satz ?? 0);
      }
    }
    String fmt(int m) =>
        '${(m / 60).floor()}:${(m % 60).toString().padLeft(2, '0')} h';
    return _DashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardHeader(context, 'Stunden',
              trailing: TextButton(
                onPressed: () => context.go('/stunden'),
                child: const Text('buchen →'),
              )),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _StatBlock(
                          label: 'Heute',
                          value: fmt(minHeute),
                          color: BadgeColors.blueFg),
                    ),
                    Expanded(
                      child: _StatBlock(
                          label: 'Diese Woche',
                          value: fmt(minWoche),
                          color: BadgeColors.indigoFg),
                    ),
                  ],
                ),
                const Divider(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Text('noch nicht abgerechnet',
                          style: TextStyle(
                              fontSize: 12.5,
                              color: AppTheme.slate500)),
                    ),
                    Text(
                      DashboardScreen._money.format(offenBetrag),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: BadgeColors.amberFg),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  const _StatBlock(
      {required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 11, color: AppTheme.slate500)),
        Text(value,
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}

String _wvDescribe(WiedervorlageWithAuftrag w) {
  final haupt = (w.eintrag.anlass?.trim().isNotEmpty ?? false)
      ? w.eintrag.anlass!
      : (w.eintrag.titel.trim().isNotEmpty
          ? w.eintrag.titel
          : 'Wiedervorlage');
  final beschr = w.eintrag.beschreibung?.trim() ?? '';
  return beschr.isEmpty ? haupt : '$haupt — $beschr';
}

/// ---------------- Heute-Kachel ----------------

class _HeuteCard extends ConsumerWidget {
  const _HeuteCard({required this.today, required this.auftraege});
  final DateTime today;
  final List<AuftragWithKunde> auftraege;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wv = ref.watch(wiedervorlagenListProvider).valueOrNull ?? const [];
    final tomorrow = today.add(const Duration(days: 1));
    final wvHeute = wv
        .where((w) =>
            !w.eintrag.erledigt &&
            !w.eintrag.faelligAm.isAfter(tomorrow))
        .toList()
      ..sort((a, b) => a.eintrag.faelligAm.compareTo(b.eintrag.faelligAm));

    final termineHeute = auftraege
        .where((a) =>
            a.auftrag.ortsterminAm != null &&
            a.auftrag.ortsterminAm!.year == today.year &&
            a.auftrag.ortsterminAm!.month == today.month &&
            a.auftrag.ortsterminAm!.day == today.day)
        .toList()
      ..sort((a, b) =>
          a.auftrag.ortsterminAm!.compareTo(b.auftrag.ortsterminAm!));

    final ueberfaellig = auftraege
        .where((a) =>
            a.auftrag.abschlussAm != null &&
            a.auftrag.abschlussAm!.isBefore(today) &&
            a.auftrag.status != 'abgeschlossen' &&
            a.auftrag.status != 'abgerechnet' &&
            a.auftrag.status != 'storniert')
        .toList();

    return _DashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardHeader(context, 'Heute im Blick'),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _heuteGroup(
                  icon: Icons.location_on_outlined,
                  color: BadgeColors.blueFg,
                  label: 'Ortstermine heute',
                  empty: 'Kein Termin heute.',
                  items: [
                    for (final a in termineHeute)
                      '${DateFormat('HH:mm').format(a.auftrag.ortsterminAm!)} · '
                          '${a.auftrag.betreff ?? a.auftrag.bezeichnung ?? ''}',
                  ],
                ),
                const SizedBox(height: 10),
                _heuteGroup(
                  icon: Icons.event_note_outlined,
                  color: BadgeColors.amberFg,
                  label: 'Wiedervorlagen fällig',
                  empty: 'Keine Wiedervorlagen heute.',
                  items: [
                    for (final w in wvHeute.take(3))
                      _wvDescribe(w),
                  ],
                ),
                const SizedBox(height: 10),
                _heuteGroup(
                  icon: Icons.warning_amber_outlined,
                  color: BadgeColors.redFg,
                  label: 'Überfällige Fristen',
                  empty: 'Keine überfälligen Fristen.',
                  items: [
                    for (final a in ueberfaellig.take(3))
                      '${DashboardScreen._dateFmt.format(a.auftrag.abschlussAm!)} · '
                          '${a.auftrag.aktenzeichen ?? ''} — '
                          '${a.auftrag.betreff ?? a.auftrag.bezeichnung ?? ''}',
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heuteGroup({
    required IconData icon,
    required Color color,
    required String label,
    required String empty,
    required List<String> items,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: color)),
          ],
        ),
        const SizedBox(height: 2),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Text(empty,
                style: TextStyle(
                    fontSize: 12, color: AppTheme.slate500)),
          )
        else
          ...items.map((t) => Padding(
                padding: const EdgeInsets.only(left: 20, top: 1),
                child: Text(
                  t,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5),
                ),
              )),
      ],
    );
  }
}

/// ---------------- Fristen-Liste ----------------

class _FristenListeCard extends StatelessWidget {
  const _FristenListeCard({required this.items, required this.today});
  final List<AuftragWithKunde> items;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    return _DashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardHeader(context, 'Nächste Abgabefristen',
              trailing: TextButton(
                onPressed: () => context.go('/auftraege'),
                child: const Text('alle →'),
              )),
          const Divider(height: 1),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Keine offenen Fristen.'),
            )
          else
            ...items.asMap().entries.map((e) {
              final a = e.value;
              final days = a.auftrag.abschlussAm!.difference(today).inDays;
              return Column(
                children: [
                  if (e.key > 0) const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    child: Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              DashboardScreen._dateFmt
                                  .format(a.auftrag.abschlussAm!),
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                            _DaysBadge(days: days),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                a.auftrag.betreff ??
                                    a.auftrag.bezeichnung ??
                                    '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600),
                              ),
                              Text(
                                'Az. ${a.auftrag.aktenzeichen ?? ''}',
                                style: TextStyle(
                                    fontSize: 11, color: AppTheme.slate500),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }),
        ],
      ),
    );
  }
}

/// ---------------- Termine (nächster Ortstermin + nächste Frist) ----------------

class _TermineCard extends StatelessWidget {
  const _TermineCard({
    required this.naechsterTermin,
    required this.naechsteFrist,
    required this.today,
  });
  final AuftragWithKunde? naechsterTermin;
  final AuftragWithKunde? naechsteFrist;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    return _DashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardHeader(context, 'Nächster Termin'),
          const Divider(height: 1),
          _section(
            icon: Icons.location_on_outlined,
            label: 'Ortstermin',
            entry: naechsterTermin,
            value: naechsterTermin == null
                ? '—'
                : DashboardScreen._dateTimeFmt
                    .format(naechsterTermin!.auftrag.ortsterminAm!),
            meta: naechsterTermin == null
                ? 'Keine anstehenden Termine.'
                : [
                    naechsterTermin!.auftrag.objektStrasse,
                    [
                      naechsterTermin!.auftrag.objektPlz,
                      naechsterTermin!.auftrag.objektOrt
                    ].whereType<String>().join(' '),
                  ].whereType<String>().where((s) => s.isNotEmpty).join(', '),
            days: naechsterTermin?.auftrag.ortsterminAm
                ?.difference(today)
                .inDays,
          ),
          const Divider(height: 1),
          _section(
            icon: Icons.event_available_outlined,
            label: 'Abgabefrist',
            entry: naechsteFrist,
            value: naechsteFrist == null
                ? '—'
                : DashboardScreen._dateFmt
                    .format(naechsteFrist!.auftrag.abschlussAm!),
            meta: naechsteFrist == null
                ? 'Keine offenen Fristen.'
                : 'Az. ${naechsteFrist!.auftrag.aktenzeichen ?? ''} — '
                    '${naechsteFrist!.auftrag.betreff ?? naechsteFrist!.auftrag.bezeichnung ?? ''}',
            days: naechsteFrist?.auftrag.abschlussAm
                ?.difference(today)
                .inDays,
          ),
        ],
      ),
    );
  }

  Widget _section({
    required IconData icon,
    required String label,
    required AuftragWithKunde? entry,
    required String value,
    required String meta,
    required int? days,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppTheme.slate500),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(label,
                          style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.slate500)),
                    ),
                    if (days != null) _DaysBadge(days: days),
                  ],
                ),
                Text(value,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                Text(meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.slate500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------------- Umsatz-Chart (Sparkline 6 Monate) ----------------

class _UmsatzChartCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rechnungen =
        ref.watch(rechnungenListProvider).valueOrNull ?? const [];
    final now = DateTime.now();
    final monate = <double>[];
    final labels = <String>[];
    for (var i = 5; i >= 0; i--) {
      final d = DateTime(now.year, now.month - i, 1);
      labels.add(DateFormat('MMM', 'de').format(d));
      final summe = rechnungen
          .where((r) =>
              r.rechnung.rechnungsdatum != null &&
              r.rechnung.status != 'storniert' &&
              r.rechnung.rechnungsdatum!.year == d.year &&
              r.rechnung.rechnungsdatum!.month == d.month)
          .fold<double>(0, (s, r) => s + r.rechnung.netto);
      monate.add(summe);
    }
    final maxY = (monate.reduce((a, b) => a > b ? a : b)) * 1.2;
    final summeGesamt = monate.fold<double>(0, (s, v) => s + v);
    return _DashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardHeader(context, 'Umsatz netto (letzte 6 Monate)',
              trailing: Text(
                DashboardScreen._money.format(summeGesamt),
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 12),
              )),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: SizedBox(
              height: 140,
              child: BarChart(
                BarChartData(
                  maxY: maxY <= 0 ? 100 : maxY,
                  barTouchData: ChartStyle.barTouchData(
                    format: (v) => DashboardScreen._money.format(v),
                  ),
                  barGroups: [
                    for (var i = 0; i < monate.length; i++)
                      BarChartGroupData(x: i, barRods: [
                        ChartStyle.bar(monate[i], width: 18),
                      ]),
                  ],
                  borderData: FlBorderData(show: false),
                  gridData: ChartStyle.gridData(),
                  titlesData: FlTitlesData(
                    leftTitles: ChartStyle.emptyAxis(),
                    rightTitles: ChartStyle.emptyAxis(),
                    topTitles: ChartStyle.emptyAxis(),
                    bottomTitles: ChartStyle.bottomLabels(labels),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------------- Kalibrierungs-Warnung ----------------

class _KalibrierungCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final geraete = ref.watch(geraeteListProvider).valueOrNull ?? const [];
    final now = DateTime.now();
    final ueberfaellig = <GeraeteData>[];
    final baldFaellig = <GeraeteData>[];
    for (final g in geraete) {
      if (!g.aktiv) continue;
      final n = g.naechsteKalibrierung;
      if (n == null) continue;
      final days = n.difference(now).inDays;
      if (days < 0) {
        ueberfaellig.add(g);
      } else if (days <= 60) {
        baldFaellig.add(g);
      }
    }
    return _DashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardHeader(context, 'Geräte-Kalibrierung',
              trailing: TextButton(
                onPressed: () => context.go('/geraete'),
                child: const Text('alle →'),
              )),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _calRow('überfällig', ueberfaellig.length,
                    BadgeColors.redBg, BadgeColors.redFg),
                const SizedBox(height: 6),
                _calRow('in ≤ 60 Tagen fällig', baldFaellig.length,
                    BadgeColors.amberBg, BadgeColors.amberFg),
                if (ueberfaellig.isEmpty && baldFaellig.isEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Alle Geräte im grünen Bereich.',
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.slate500)),
                ],
                if (ueberfaellig.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ...ueberfaellig.take(3).map((g) => Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '• ${g.bezeichnung} '
                          '(${g.inventarNr ?? ''})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      )),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _calRow(String label, int count, Color bg, Color fg) {
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 12.5))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration:
              BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
          child: Text('$count',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
        ),
      ],
    );
  }
}

/// ---------------- Fortbildungs-Progress ----------------

class _FortbildungCard extends ConsumerWidget {
  static const _ziel = 30.0;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summen = ref.watch(fortbildungenSummenProvider).valueOrNull ??
        const <int, double>{};
    final jahr = DateTime.now().year;
    final stunden = summen[jahr] ?? 0;
    final pct = (stunden / _ziel).clamp(0.0, 1.5);
    return _DashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardHeader(context, 'Fortbildungsstunden $jahr',
              trailing: TextButton(
                onPressed: () => context.go('/fortbildungen'),
                child: const Text('erfassen →'),
              )),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      stunden.toStringAsFixed(1),
                      style: const TextStyle(
                          fontSize: 26, fontWeight: FontWeight.w800),
                    ),
                    Text('  / ${_ziel.toInt()} h',
                        style: TextStyle(
                            fontSize: 14, color: AppTheme.slate500)),
                    const Spacer(),
                    PillBadge(
                      text: pct >= 1
                          ? 'Ziel erreicht'
                          : '${(pct * 100).toStringAsFixed(0)} %',
                      background: pct >= 1
                          ? BadgeColors.greenBg
                          : BadgeColors.amberBg,
                      foreground: pct >= 1
                          ? BadgeColors.greenFg
                          : BadgeColors.amberFg,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct > 1 ? 1 : pct,
                    minHeight: 8,
                    backgroundColor: AppTheme.slate100,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      pct >= 1
                          ? BadgeColors.greenFg
                          : AppTheme.accent600,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Richtwert IHK: 30 Stunden pro Jahr für die Wiederbestellung.',
                  style:
                      TextStyle(fontSize: 11, color: AppTheme.slate500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------------- Recent-Table als Kachel ----------------

class _RecentTable extends StatelessWidget {
  const _RecentTable({required this.items});
  final List<AuftragWithKunde> items;

  @override
  Widget build(BuildContext context) {
    return _DashCard(
      child: Column(
        children: [
          _cardHeader(context, 'Zuletzt angelegte Akten',
              trailing: TextButton(
                onPressed: () => context.go('/akten'),
                child: const Text('alle →'),
              )),
          const Divider(height: 1),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text('Noch keine Akten erfasst.',
                      style: TextStyle(
                          color: AppTheme.slate500)),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: () => context.go('/auftraege'),
                    icon: const Icon(Icons.add),
                    label: const Text('Ersten Auftrag anlegen'),
                  ),
                ],
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
              showCheckboxColumn: false,
                headingRowColor: WidgetStateProperty.all(
                    Theme.of(context).colorScheme.surfaceContainerLow),
                columns: const [
                  DataColumn(label: Text('Az.')),
                  DataColumn(label: Text('Art')),
                  DataColumn(label: Text('Betreff')),
                  DataColumn(label: Text('Auftraggeber')),
                  DataColumn(label: Text('Status')),
                ],
                rows: [
                  for (final r in items)
                    DataRow(
                      onSelectChanged: (_) =>
                          context.go('/akte/${r.auftrag.id}'),
                      cells: [
                        DataCell(Text(
                          r.auftrag.aktenzeichen ?? '',
                          style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.accent700),
                        )),
                        DataCell(Text(
                            AuftragArtX.fromDb(r.auftrag.art).label,
                            style: const TextStyle(fontSize: 12))),
                        DataCell(SizedBox(
                          width: 380,
                          child: Text(
                            r.auftrag.betreff ??
                                r.auftrag.bezeichnung ??
                                '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        )),
                        DataCell(Text(
                          r.kunde == null
                              ? '—'
                              : kundeAnzeigename(r.kunde!),
                          style: const TextStyle(fontSize: 12.5),
                        )),
                        DataCell(_StatusPill(status: r.auftrag.status)),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = switch (status) {
      'offen' => (BadgeColors.blueBg, BadgeColors.blueFg, 'Offen'),
      'in_arbeit' || 'laufend' =>
        (BadgeColors.amberBg, BadgeColors.amberFg, 'In Bearbeitung'),
      'wartet' => (BadgeColors.slateBg, BadgeColors.slateFg, 'Wartet'),
      'abgeschlossen' =>
        (BadgeColors.greenBg, BadgeColors.greenFg, 'Abgeschlossen'),
      'abgerechnet' =>
        (BadgeColors.greenBg, BadgeColors.greenFg, 'Abgerechnet'),
      'storniert' => (BadgeColors.redBg, BadgeColors.redFg, 'Storniert'),
      _ => (BadgeColors.slateBg, BadgeColors.slateFg, status),
    };
    return PillBadge(text: label, background: bg, foreground: fg);
  }
}

class _DaysBadge extends StatelessWidget {
  const _DaysBadge({required this.days});
  final int days;

  static const _yellowBg = Color(0xFFFEF9C3);
  static const _yellowFg = Color(0xFF854D0E);

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = switch (days) {
      < 0 => (
          BadgeColors.redBg,
          BadgeColors.redFg,
          '${-days}\u00a0T überf.'
        ),
      0 => (BadgeColors.redBg, BadgeColors.redFg, 'heute'),
      1 => (BadgeColors.amberBg, BadgeColors.amberFg, 'morgen'),
      <= 7 =>
        (BadgeColors.amberBg, BadgeColors.amberFg, 'in $days T'),
      <= 14 => (_yellowBg, _yellowFg, 'in $days T'),
      _ => (BadgeColors.greenBg, BadgeColors.greenFg, 'in $days T'),
    };
    return PillBadge(text: label, background: bg, foreground: fg);
  }
}
