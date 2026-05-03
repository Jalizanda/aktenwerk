import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart'
    show OrderingTerm, OrderingMode, innerJoin, Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/aw_tokens.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../../shared/widgets/badges.dart';
import '../auftraege/auftraege_form.dart';
import '../auftraege/auftraege_repository.dart';
import '../kunden/kunden_repository.dart';
import '../rechnungen/rechnungen_repository.dart';
import '../rechnungen/rechnungen_screen.dart';
import '../../angebote/angebote/angebote_repository.dart';
import '../../angebote/angebote/angebote_screen.dart';
import '../../kalkulation/stunden/stunden_repository.dart';
import '../../kalkulation/stunden/stunden_screen.dart';
import '../../kalkulation/auslagen/auslagen_repository.dart';
import '../../kalkulation/auslagen/auslagen_screen.dart';
import '../gutachten/gutachten_screen.dart';
import '../dokumente/dokument_viewer.dart';
import '../dokumente/dokumente_repository.dart';
import '../dokumente/dokumente_screen.dart';
import '../erlaeuterungen/erlaeuterungen_repository.dart';
import '../erlaeuterungen/erlaeuterungen_screen.dart';
import '../gerichtssache/gerichtssache_tab.dart';
import '../lv/lv_repository.dart';
import '../lv/lv_screen.dart';
import '../nachfragen/nachfragen_tab.dart';
import '../versand/versand_tab.dart';
import '../../angebote/anschreiben/anschreiben_repository.dart';
import '../../angebote/anschreiben/anschreiben_screen.dart';
import 'kostenvorschuss_dialog.dart';
import '../bauteiloeffnungen/bauteiloeffnung_tab.dart';
import '../journal/journal_tab.dart';
import '../maengel/maengel_tab.dart';
import '../messwerte/messwerte_tab.dart';
import '../protokolle/protokolle_tab.dart';
import '../uebergabe/uebergabe_tab.dart';
import '../wertermittlung/wertermittlung_tab.dart';
import 'akte_benchmark_card.dart';
import 'akte_tabbar.dart';
import 'beteiligte_tab.dart';
import 'wirtschaftlichkeit_tab.dart';
import 'geraete_picker_dialog.dart';
import 'normen_picker_dialog.dart';

/// Auftragsakte — der zentrale Drehpunkt pro Auftrag.
///
/// Zeigt in einer einzigen Ansicht alles, was zu einem Auftrag gehört:
/// Stammdaten, Beteiligte, Termine/Fristen, Stunden, Auslagen, Rechnungen,
/// Angebote, Gutachten, Fotos, Dokumente, Normen, Geräte, Erläuterungen,
/// Anschreiben, Wiedervorlagen.
class AkteScreen extends ConsumerStatefulWidget {
  const AkteScreen({super.key, required this.auftragId});
  final int auftragId;
  @override
  ConsumerState<AkteScreen> createState() => _AkteScreenState();
}

class _AkteScreenState extends ConsumerState<AkteScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 24, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(appDatabaseProvider);
    return StreamBuilder<AuftraegeData?>(
      stream: (db.select(db.auftraege)
            ..where((t) => t.id.equals(widget.auftragId)))
          .watchSingleOrNull(),
      builder: (ctx, snap) {
        final a = snap.data;
        if (a == null && snap.connectionState != ConnectionState.waiting) {
          return const Center(child: Text('Auftrag nicht gefunden.'));
        }
        if (a == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return StreamBuilder<KundenData?>(
          stream: a.kundeId == null
              ? Stream.value(null)
              : (db.select(db.kunden)
                    ..where((t) => t.id.equals(a.kundeId!)))
                  .watchSingleOrNull(),
          builder: (_, kSnap) => _buildBody(context, a, kSnap.data),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, AuftraegeData a, KundenData? k) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AkteHeader(auftrag: a, kunde: k),
        AkteTabBar(
          auftragId: a.id,
          kundeId: a.kundeId,
          controller: _tabs,
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _UebersichtTab(auftrag: a, kunde: k),
              BeteiligteTab(auftrag: a),
              _StundenTab(auftragId: a.id),
              _AuslagenTab(auftragId: a.id),
              _RechnungenTab(auftragId: a.id, kundeId: a.kundeId),
              _AngeboteTab(auftragId: a.id, kundeId: a.kundeId),
              _GutachtenTab(auftragId: a.id),
              _FotosTab(auftragId: a.id),
              _DokumenteTab(auftragId: a.id),
              _NormenTab(auftragId: a.id),
              _GeraeteTab(auftragId: a.id),
              _ErlaeuterungenTab(auftragId: a.id),
              GerichtssacheTab(auftrag: a),
              NachfragenTab(auftrag: a),
              VersandTab(auftrag: a),
              _AnschreibenTab(auftragId: a.id, kundeId: a.kundeId),
              ProtokolleTab(auftrag: a),
              JournalTab(auftragId: a.id),
              MaengelTab(auftragId: a.id),
              UebergabeTab(auftragId: a.id),
              BauteiloeffnungTab(auftragId: a.id),
              MesswerteTab(auftragId: a.id),
              WertermittlungTab(auftragId: a.id),
              WirtschaftlichkeitTab(auftragId: a.id),
              _LvTab(auftragId: a.id),
            ],
          ),
        ),
      ],
    );
  }
}

class _AkteHeader extends StatelessWidget {
  const _AkteHeader({required this.auftrag, required this.kunde});
  final AuftraegeData auftrag;
  final KundenData? kunde;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go('/akten'),
                tooltip: 'Zurück zur Akten-Übersicht',
              ),
              const SizedBox(width: 4),
              const Icon(Icons.folder_open_outlined,
                  size: 24, color: AppTheme.accent600),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(auftrag.aktenzeichen ?? '(ohne Az.)',
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                fontFamily: 'monospace',
                                color: AppTheme.accent700)),
                        const SizedBox(width: 12),
                        _StatusPill(status: auftrag.status),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      auftrag.betreff ??
                          auftrag.bezeichnung ??
                          '(kein Betreff)',
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
              if (auftrag.art == 'gericht') ...[
                OutlinedButton.icon(
                  icon: const Icon(Icons.payments_outlined, size: 18),
                  label: const Text('Kostenvorschuss-Antrag'),
                  onPressed: () => showDialog(
                    context: context,
                    useRootNavigator: true,
                    builder: (_) => KostenvorschussDialog(
                      auftrag: auftrag,
                      kunde: kunde,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              OutlinedButton.icon(
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Stammdaten bearbeiten'),
                onPressed: () => showAuftragFormDialog(
                  context,
                  auftrag: auftrag,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 20,
            runSpacing: 4,
            children: [
              _meta('Auftraggeber',
                  kunde == null ? '—' : kundeAnzeigename(kunde!)),
              _meta('Art', AuftragArtX.fromDb(auftrag.art).label),
              if (auftrag.objektOrt != null)
                _meta('Objekt',
                    '${auftrag.objektStrasse ?? ''}, ${auftrag.objektPlz ?? ''} ${auftrag.objektOrt}'),
              if (auftrag.ortsterminAm != null)
                _meta('Ortstermin',
                    DateFormat('dd.MM.yyyy · HH:mm', 'de')
                        .format(auftrag.ortsterminAm!)),
              if (auftrag.abschlussAm != null)
                _meta('Abgabefrist',
                    DateFormat('dd.MM.yyyy', 'de').format(auftrag.abschlussAm!)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _meta(String label, String value) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.slate500,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(
                fontSize: 12.5,
                color: Colors.black87,
                fontWeight: FontWeight.w500),
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

// ---------------- Übersicht ----------------

class _UebersichtTab extends ConsumerWidget {
  const _UebersichtTab({required this.auftrag, required this.kunde});
  final AuftraegeData auftrag;
  final KundenData? kunde;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final money =
        NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth;
            final hasObjekt = _hasObjektAdresse(auftrag);
            final left = _AkteInfoCard(auftrag: auftrag, kunde: kunde);
            final middle = hasObjekt
                ? _ObjektMapCard(auftrag: auftrag, compact: true)
                : null;
            final right = _AkteFinanzenCard(
                auftragId: auftrag.id, money: money);
            if (w >= 1180 && middle != null) {
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 3, child: left),
                    const SizedBox(width: 16),
                    Expanded(flex: 4, child: middle),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: right),
                  ],
                ),
              );
            }
            if (w >= 900) {
              return Column(
                children: [
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 3, child: left),
                        const SizedBox(width: 16),
                        Expanded(flex: 2, child: right),
                      ],
                    ),
                  ),
                  if (middle != null) ...[
                    const SizedBox(height: 16),
                    middle,
                  ],
                ],
              );
            }
            return Column(children: [
              left,
              if (middle != null) ...[
                const SizedBox(height: 16),
                middle,
              ],
              const SizedBox(height: 16),
              right,
            ]);
          }),
          const SizedBox(height: 16),
          AkteBenchmarkCard(auftrag: auftrag),
          // Aufgaben/Notizen falls im Auftrag gesetzt
          if ((auftrag.notiz ?? '').isNotEmpty) ...[
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Notiz',
              child: Text(auftrag.notiz!,
                  style: const TextStyle(fontSize: 13, height: 1.5)),
            ),
          ],
        ],
      ),
    );
  }

  bool _hasObjektAdresse(AuftraegeData a) =>
      (a.objektStrasse ?? '').isNotEmpty ||
      (a.objektOrt ?? '').isNotEmpty;
}

class _AkteInfoCard extends StatelessWidget {
  const _AkteInfoCard({required this.auftrag, required this.kunde});
  final AuftraegeData auftrag;
  final KundenData? kunde;
  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Stammdaten',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _kv('Aktenzeichen', auftrag.aktenzeichen ?? '—'),
          if ((auftrag.azExtern ?? '').isNotEmpty)
            _kv('Az. extern', auftrag.azExtern!),
          _kv('Art', AuftragArtX.fromDb(auftrag.art).label),
          _kv('Status', auftrag.status),
          if ((auftrag.betreff ?? '').isNotEmpty)
            _kv('Betreff', auftrag.betreff!),
          if ((auftrag.bezeichnung ?? '').isNotEmpty)
            _kv('Bezeichnung', auftrag.bezeichnung!),
          if ((auftrag.kategorie ?? '').isNotEmpty)
            _kv('Kategorie', auftrag.kategorie!),
          _kv('Sachgebiet', auftrag.sachgebiet ?? '—'),
          _kv('Honorargruppe', auftrag.honorargruppe ?? '—'),
          if (auftrag.stundensatz != null)
            _kv('Stundensatz',
                '${auftrag.stundensatz!.toStringAsFixed(2)} €/h'),
          if (auftrag.kostenvorschuss != null)
            _kv('Kostenvorschuss',
                '${auftrag.kostenvorschuss!.toStringAsFixed(2)} €'),
          if (auftrag.kostenLimit != null)
            _kv('Kosten-Limit',
                '${auftrag.kostenLimit!.toStringAsFixed(2)} €'),
          if (auftrag.aufwandSchaetzung != null)
            _kv('Geschätzter Aufwand',
                '${auftrag.aufwandSchaetzung!.toStringAsFixed(1)} h'),
          // --- Termine kompakt ---
          if (_hatTermine(auftrag)) ...[
            const Divider(height: 24),
            const Text('Termine',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            if (auftrag.eingangAm != null)
              _kv('Eingang',
                  DateFormat('dd.MM.yyyy', 'de').format(auftrag.eingangAm!)),
            if (auftrag.auftragAm != null)
              _kv('Beauftragt',
                  DateFormat('dd.MM.yyyy', 'de').format(auftrag.auftragAm!)),
            if (auftrag.akteneingangAm != null)
              _kv('Akteneingang',
                  DateFormat('dd.MM.yyyy', 'de')
                      .format(auftrag.akteneingangAm!)),
            if (auftrag.ortsterminAm != null)
              _kv('Ortstermin',
                  DateFormat('dd.MM.yyyy · HH:mm', 'de')
                      .format(auftrag.ortsterminAm!)),
            if (auftrag.fristAm != null)
              _kv('Frist',
                  DateFormat('dd.MM.yyyy', 'de').format(auftrag.fristAm!)),
            if (auftrag.abschlussAm != null)
              _kv('Abgabe',
                  DateFormat('dd.MM.yyyy', 'de')
                      .format(auftrag.abschlussAm!)),
          ],
          const Divider(height: 24),
          const Text('Auftraggeber',
              style:
                  TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(kunde == null ? '—' : kundeAnzeigename(kunde!),
              style: const TextStyle(fontSize: 13)),
          if (kunde?.strasse != null || kunde?.ort != null)
            Text(
              [kunde?.strasse, '${kunde?.plz ?? ''} ${kunde?.ort ?? ''}']
                  .whereType<String>()
                  .where((s) => s.trim().isNotEmpty)
                  .join(', '),
              style: TextStyle(fontSize: 12, color: AppTheme.slate500),
            ),
          if ((kunde?.telefon ?? '').isNotEmpty)
            Text('Tel.: ${kunde!.telefon}',
                style: TextStyle(fontSize: 12, color: AppTheme.slate600)),
          if ((kunde?.email ?? '').isNotEmpty)
            Text('E-Mail: ${kunde!.email}',
                style: TextStyle(fontSize: 12, color: AppTheme.slate600)),
          const Divider(height: 24),
          const Text('Objekt',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            [
              auftrag.objektStrasse,
              '${auftrag.objektPlz ?? ''} ${auftrag.objektOrt ?? ''}',
            ]
                .whereType<String>()
                .where((s) => s.trim().isNotEmpty)
                .join(', '),
            style: const TextStyle(fontSize: 13),
          ),
          if ((auftrag.objektart ?? '').isNotEmpty ||
              (auftrag.baujahr ?? '').isNotEmpty)
            Text(
              [
                auftrag.objektart,
                if ((auftrag.baujahr ?? '').isNotEmpty)
                  'Bj. ${auftrag.baujahr}',
              ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
              style: TextStyle(fontSize: 12, color: AppTheme.slate500),
            ),
          if (_hatGerichtInfo(auftrag)) ...[
            const Divider(height: 24),
            const Text('Gericht & Verfahren',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            if ((auftrag.gericht ?? '').isNotEmpty ||
                (auftrag.gerichtsort ?? '').isNotEmpty)
              Text(
                [auftrag.gericht, auftrag.gerichtsort]
                    .whereType<String>()
                    .where((s) => s.trim().isNotEmpty)
                    .join(' · '),
                style: const TextStyle(fontSize: 13),
              ),
            if ((auftrag.gerichtsAktenzeichen ?? '').isNotEmpty)
              Text('Az.: ${auftrag.gerichtsAktenzeichen}',
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.slate600)),
            if ((auftrag.verfahrensart ?? '').isNotEmpty)
              Text('Verfahrensart: ${auftrag.verfahrensart}',
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.slate600)),
            if ((auftrag.klaeger ?? '').isNotEmpty ||
                (auftrag.beklagter ?? '').isNotEmpty)
              Text(
                'In Sachen ${auftrag.klaeger ?? '—'} ./. ${auftrag.beklagter ?? '—'}',
                style: TextStyle(
                    fontSize: 12, color: AppTheme.slate600),
              ),
            if ((auftrag.richter ?? '').isNotEmpty)
              Text('Richter/in: ${auftrag.richter}',
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.slate600)),
            if (auftrag.beweisbeschluss1 != null)
              Text(
                'Beweisbeschluss: ${DateFormat('dd.MM.yyyy', 'de').format(auftrag.beweisbeschluss1!)}'
                '${auftrag.beweisbeschluss2 != null ? " · Erg.: ${DateFormat('dd.MM.yyyy', 'de').format(auftrag.beweisbeschluss2!)}" : ""}'
                '${auftrag.beweisbeschluss3 != null ? " · Erg.: ${DateFormat('dd.MM.yyyy', 'de').format(auftrag.beweisbeschluss3!)}" : ""}',
                style: TextStyle(
                    fontSize: 12, color: AppTheme.slate600),
              ),
            if (auftrag.anzahlAusfertigungen != null)
              Text('Ausfertigungen: ${auftrag.anzahlAusfertigungen}'
                  '${auftrag.aktenSeitenBis != null ? " · Aktenseiten ${auftrag.aktenSeitenVon ?? 1}–${auftrag.aktenSeitenBis}" : ""}',
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.slate600)),
          ],
          if ((auftrag.beweisbeschlussStorageUrl ?? '').isNotEmpty ||
              (auftrag.objektFotoStorageUrl ?? '').isNotEmpty) ...[
            const Divider(height: 24),
            const Text('Anlagen',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            if ((auftrag.beweisbeschlussStorageUrl ?? '').isNotEmpty)
              InkWell(
                onTap: () async {
                  final uri = Uri.tryParse(
                      auftrag.beweisbeschlussStorageUrl!);
                  if (uri != null) {
                    await launchUrl(uri,
                        mode: LaunchMode.externalApplication);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      const Icon(Icons.picture_as_pdf,
                          size: 18, color: AwTokens.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          auftrag.beweisbeschlussDateiname ??
                              'Beweisbeschluss',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AwTokens.blue,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                      const Icon(Icons.open_in_new, size: 14),
                    ],
                  ),
                ),
              ),
            if ((auftrag.objektFotoStorageUrl ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  auftrag.objektFotoStorageUrl!,
                  height: 120,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    height: 120,
                    color: AppTheme.slate200,
                    alignment: Alignment.center,
                    child: const Icon(Icons.broken_image,
                        color: AppTheme.slate500),
                  ),
                ),
              ),
              if ((auftrag.objektFotoDateiname ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(auftrag.objektFotoDateiname!,
                      style: TextStyle(
                          fontSize: 11, color: AppTheme.slate500)),
                ),
            ],
          ],
          if ((auftrag.schneelastzone ?? '').isNotEmpty ||
              (auftrag.windlastzone ?? '').isNotEmpty) ...[
            const Divider(height: 24),
            const Text('Lastzonen',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            if ((auftrag.schneelastzone ?? '').isNotEmpty)
              Text(
                'Schneelast: Zone ${auftrag.schneelastzone}'
                '${auftrag.schneelastKnm2 != null ? " · ${auftrag.schneelastKnm2!.toStringAsFixed(2)} kN/m²" : ""}',
                style: TextStyle(
                    fontSize: 12, color: AppTheme.slate600),
              ),
            if ((auftrag.windlastzone ?? '').isNotEmpty)
              Text('Windlast: Zone ${auftrag.windlastzone}',
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.slate600)),
          ],
        ],
      ),
    );
  }

  bool _hatGerichtInfo(AuftraegeData a) {
    return (a.gericht ?? '').isNotEmpty ||
        (a.gerichtsort ?? '').isNotEmpty ||
        (a.gerichtsAktenzeichen ?? '').isNotEmpty ||
        (a.klaeger ?? '').isNotEmpty ||
        (a.beklagter ?? '').isNotEmpty ||
        (a.richter ?? '').isNotEmpty ||
        (a.verfahrensart ?? '').isNotEmpty ||
        a.beweisbeschluss1 != null;
  }

  bool _hatTermine(AuftraegeData a) {
    return a.eingangAm != null ||
        a.auftragAm != null ||
        a.akteneingangAm != null ||
        a.ortsterminAm != null ||
        a.fristAm != null ||
        a.abschlussAm != null;
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style:
                    TextStyle(fontSize: 12, color: AppTheme.slate500)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _AkteFinanzenCard extends ConsumerWidget {
  const _AkteFinanzenCard(
      {required this.auftragId, required this.money});
  final int auftragId;
  final NumberFormat money;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rechnungen =
        ref.watch(rechnungenListProvider).valueOrNull ?? const [];
    final mine = rechnungen
        .where((r) => r.rechnung.auftragId == auftragId)
        .toList();
    double umsatz = 0;
    double offen = 0;
    double bezahlt = 0;
    for (final r in mine) {
      if (r.rechnung.status == 'storniert') continue;
      umsatz += r.rechnung.brutto;
      bezahlt += r.rechnung.bezahlt;
      if (r.rechnung.status != 'bezahlt') {
        offen += r.rechnung.brutto - r.rechnung.bezahlt;
      }
    }
    return _SectionCard(
      title: 'Finanzen',
      child: Column(
        children: [
          _line('Umsatz (brutto)', money.format(umsatz),
              BadgeColors.blueFg),
          _line('Offen', money.format(offen), BadgeColors.amberFg),
          _line('Bezahlt', money.format(bezahlt), BadgeColors.greenFg),
          const Divider(),
          Row(
            children: [
              Expanded(
                  child: Text('Rechnungen',
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.slate500))),
              Text('${mine.length}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _line(String l, String v, Color c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
                child: Text(l, style: const TextStyle(fontSize: 12.5))),
            Text(v,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: c)),
          ],
        ),
      );
}


/// Satelliten-Vorschau der Objektadresse + Direkt-Link in Google Maps.
/// Nutzt Esri World Imagery (frei, keine API-Keys) via Nominatim-Geocoding.
class _ObjektMapCard extends StatefulWidget {
  const _ObjektMapCard({required this.auftrag, this.compact = false});
  final AuftraegeData auftrag;
  /// `true` → schmalere Darstellung (Bild mit kleinerem Seitenverhältnis),
  /// damit die Karte gut zwischen Stammdaten und Finanzen passt.
  final bool compact;
  @override
  State<_ObjektMapCard> createState() => _ObjektMapCardState();
}

class _ObjektMapCardState extends State<_ObjektMapCard> {
  double? _lat;
  double? _lon;
  bool _loading = true;
  String? _error;

  String get _adresse => [
        widget.auftrag.objektStrasse,
        [widget.auftrag.objektPlz, widget.auftrag.objektOrt]
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .join(' '),
      ].whereType<String>().where((s) => s.trim().isNotEmpty).join(', ');

  @override
  void initState() {
    super.initState();
    _geocode();
  }

  Future<void> _geocode() async {
    try {
      final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/search?format=json&limit=1&q=${Uri.encodeComponent(_adresse)}');
      final resp = await http.get(uri, headers: {
        'User-Agent': 'Aktenwerk/1.0 (hello@aktenwerk.app)',
      });
      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List;
        if (list.isNotEmpty) {
          final m = list.first as Map;
          _lat = double.tryParse(m['lat']?.toString() ?? '');
          _lon = double.tryParse(m['lon']?.toString() ?? '');
        }
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final address = _adresse;
    final gmaps =
        Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}');
    return _SectionCard(
      title: 'Objekt & Lage',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(address, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AspectRatio(
              aspectRatio: widget.compact ? 1.3 : 2.0,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_loading)
                    const ColoredBox(
                      color: AppTheme.slate50,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_lat != null && _lon != null)
                    _EsriSatImage(lat: _lat!, lon: _lon!)
                  else
                    ColoredBox(
                      color: AppTheme.slate50,
                      child: Center(
                        child: Text(
                          _error != null
                              ? 'Karte nicht verfügbar.'
                              : 'Adresse konnte nicht lokalisiert werden.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.open_in_new, size: 14),
                      label: const Text('In Google Maps öffnen'),
                      onPressed: () =>
                          launchUrl(gmaps, mode: LaunchMode.externalApplication),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Einfache Satelliten-Kachel. Esri World Imagery bietet kostenfreie
/// Satellitenbilder im WebMercator-Tile-Grid.
class _EsriSatImage extends StatelessWidget {
  const _EsriSatImage({required this.lat, required this.lon});
  final double lat;
  final double lon;

  /// Berechnet die X/Y-Tile-Nummer bei Zoom [z] für lat/lon (WebMercator).
  (int, int) _latLonToTile(double lat, double lon, int z) {
    final n = 1 << z;
    final x = ((lon + 180.0) / 360.0 * n).floor();
    final latRad = lat * math.pi / 180.0;
    final y = ((1.0 -
                math.log(math.tan(latRad) + 1 / math.cos(latRad)) /
                    math.pi) /
            2.0 *
            n)
        .floor();
    return (x, y);
  }

  @override
  Widget build(BuildContext context) {
    const z = 18;
    final (x, y) = _latLonToTile(lat, lon, z);
    // 3×3 Raster aus Tiles, zentrum ist (x,y) — gibt ein besseres Bildfeld.
    return GridView.count(
      crossAxisCount: 3,
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      children: [
        for (var dy = -1; dy <= 1; dy++)
          for (var dx = -1; dx <= 1; dx++)
            Image.network(
              'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/$z/${y + dy}/${x + dx}',
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  Container(color: AppTheme.slate50),
            ),
      ],
    );
  }
}

// ---------------- Einzel-Tabs mit gefilterten Listen ----------------

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.slate200),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700)),
          const Divider(),
          child,
        ],
      ),
    );
  }
}

class _StundenTab extends ConsumerWidget {
  const _StundenTab({required this.auftragId});
  final int auftragId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDatabaseProvider);
    return StreamBuilder<List<StundenData>>(
      stream: (db.select(db.stunden)
            ..where((t) => t.auftragId.equals(auftragId))
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.datum, mode: OrderingMode.desc)
            ]))
          .watch(),
      builder: (ctx, snap) {
        final items = snap.data ?? const [];
        if (items.isEmpty) {
          return _emptyTab(ctx, Icons.schedule_outlined,
              'Noch keine Stunden gebucht.', '/stunden',
              createLabel: '+ Stunde erfassen',
              onCreate: () => showStundenEditor(ctx,
                  prefillAuftragId: auftragId));
        }
        final minutes = items.fold<int>(0, (a, s) => a + s.minuten);
        final betrag = items.fold<double>(
            0, (a, s) => a + (s.minuten / 60.0) * (s.satz ?? 0));
        return _listWrapper(
          ctx,
          header:
              '${items.length} Einträge · ${(minutes / 60).toStringAsFixed(1)} h · ${_money(betrag)}',
          onOpen: () => ctx.go('/stunden'),
          createLabel: '+ Stunde',
          onCreate: () => showStundenEditor(ctx,
              prefillAuftragId: auftragId),
          table: DataTable(
            showCheckboxColumn: false,
            columns: const [
              DataColumn(label: Text('Datum')),
              DataColumn(label: Text('Tätigkeit')),
              DataColumn(label: Text('Dauer')),
              DataColumn(label: Text('Satz €')),
              DataColumn(label: Text('Betrag €')),
              DataColumn(label: Text('Abgerechnet')),
            ],
            rows: [
              for (final s in items)
                DataRow(
                  onSelectChanged: (_) async {
                    final db = ref.read(appDatabaseProvider);
                    final a = await (db.select(db.auftraege)
                          ..where((t) => t.id.equals(auftragId)))
                        .getSingleOrNull();
                    if (!ctx.mounted) return;
                    await showStundenEditor(ctx,
                        eintrag: StundenWithAuftrag(s, a));
                  },
                  cells: [
                  DataCell(Text(_dateFmt.format(s.datum))),
                  DataCell(Text(s.taetigkeit ?? '')),
                  DataCell(Text(
                      '${(s.minuten / 60).floor()}:${(s.minuten % 60).toString().padLeft(2, '0')}')),
                  DataCell(Text(s.satz?.toStringAsFixed(2) ?? '')),
                  DataCell(Text(((s.minuten / 60.0) * (s.satz ?? 0))
                      .toStringAsFixed(2))),
                  DataCell(Icon(
                    s.abgerechnet
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 16,
                    color: s.abgerechnet
                        ? BadgeColors.greenFg
                        : AppTheme.slate400,
                  )),
                ]),
            ],
          ),
        );
      },
    );
  }
}

class _AuslagenTab extends ConsumerWidget {
  const _AuslagenTab({required this.auftragId});
  final int auftragId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDatabaseProvider);
    return StreamBuilder<List<AuslagenData>>(
      stream: (db.select(db.auslagen)
            ..where((t) => t.auftragId.equals(auftragId))
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.datum, mode: OrderingMode.desc)
            ]))
          .watch(),
      builder: (ctx, snap) {
        final items = snap.data ?? const [];
        if (items.isEmpty) {
          return _emptyTab(ctx, Icons.payments_outlined,
              'Noch keine Auslagen gebucht.', '/auslagen',
              createLabel: '+ Auslage buchen',
              onCreate: () => showAuslageEditor(ctx,
                  prefillAuftragId: auftragId));
        }
        final summe = items.fold<double>(0, (a, s) => a + s.summe);
        return _listWrapper(
          ctx,
          header: '${items.length} Einträge · ${_money(summe)}',
          onOpen: () => ctx.go('/auslagen'),
          createLabel: '+ Auslage',
          onCreate: () => showAuslageEditor(ctx,
              prefillAuftragId: auftragId),
          table: DataTable(
            showCheckboxColumn: false,
            columns: const [
              DataColumn(label: Text('Datum')),
              DataColumn(label: Text('Art')),
              DataColumn(label: Text('Beschreibung')),
              DataColumn(label: Text('Menge')),
              DataColumn(label: Text('Summe €')),
            ],
            rows: [
              for (final a in items)
                DataRow(
                  onSelectChanged: (_) async {
                    final db = ref.read(appDatabaseProvider);
                    final auf = await (db.select(db.auftraege)
                          ..where((t) => t.id.equals(auftragId)))
                        .getSingleOrNull();
                    if (!ctx.mounted) return;
                    await showAuslageEditor(ctx,
                        eintrag: AuslageWithAuftrag(a, auf));
                  },
                  cells: [
                    DataCell(Text(_dateFmt.format(a.datum))),
                    DataCell(Text(a.art ?? '')),
                    DataCell(Text(a.beschreibung ?? '')),
                    DataCell(Text(
                        '${a.menge.toStringAsFixed(1)} ${a.einheit ?? ''}')),
                    DataCell(Text(a.summe.toStringAsFixed(2))),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _RechnungenTab extends ConsumerWidget {
  const _RechnungenTab({required this.auftragId, required this.kundeId});
  final int auftragId;
  final int? kundeId;

  void _neueRechnung(BuildContext context) {
    showRechnungEditor(
      context,
      prefillAuftragId: auftragId,
      prefillKundeId: kundeId,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(rechnungenListProvider).valueOrNull ?? const [];
    final mine = all.where((r) => r.rechnung.auftragId == auftragId).toList();
    if (mine.isEmpty) {
      return _emptyTab(context, Icons.request_page_outlined,
          'Noch keine Rechnungen zu dieser Akte.', '/rechnungen',
          createLabel: '+ Neue Rechnung',
          onCreate: () => _neueRechnung(context));
    }
    return _listWrapper(
      context,
      header: '${mine.length} Rechnungen',
      onOpen: () => context.go('/rechnungen'),
      createLabel: '+ Neue Rechnung',
      onCreate: () => _neueRechnung(context),
      table: DataTable(
        showCheckboxColumn: false,
        columns: const [
          DataColumn(label: Text('Rg-Nr.')),
          DataColumn(label: Text('Datum')),
          DataColumn(label: Text('Typ')),
          DataColumn(label: Text('Netto €')),
          DataColumn(label: Text('Brutto €')),
          DataColumn(label: Text('Status')),
        ],
        rows: [
          for (final r in mine)
            DataRow(
              onSelectChanged: (_) =>
                  showRechnungEditor(context, eintrag: r),
              cells: [
                DataCell(Text(r.rechnung.rechnungsnummer ?? '',
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 12))),
                DataCell(Text(r.rechnung.rechnungsdatum == null
                    ? ''
                    : _dateFmt.format(r.rechnung.rechnungsdatum!))),
                DataCell(Text(r.rechnung.typ)),
                DataCell(Text(_money(r.rechnung.netto))),
                DataCell(Text(_money(r.rechnung.brutto))),
                DataCell(Text(r.rechnung.status)),
              ],
            ),
        ],
      ),
    );
  }
}

class _AngeboteTab extends ConsumerWidget {
  const _AngeboteTab({required this.auftragId, required this.kundeId});
  final int auftragId;
  final int? kundeId;

  void _neuesAngebot(BuildContext context) {
    showAngebotEditor(
      context,
      prefillAuftragId: auftragId,
      prefillKundeId: kundeId,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(angeboteListProvider).valueOrNull ?? const [];
    final mine = kundeId == null
        ? const <AngebotWithKunde>[]
        : all.where((a) => a.angebot.kundeId == kundeId).toList();
    if (mine.isEmpty) {
      return _emptyTab(context, Icons.price_change_outlined,
          'Keine Angebote verknüpft.', '/angebote',
          createLabel: '+ Neues Angebot',
          onCreate: () => _neuesAngebot(context));
    }
    return _listWrapper(
      context,
      header: '${mine.length} Angebote',
      onOpen: () => context.go('/angebote'),
      createLabel: '+ Neues Angebot',
      onCreate: () => _neuesAngebot(context),
      table: DataTable(
        showCheckboxColumn: false,
        columns: const [
          DataColumn(label: Text('Nr.')),
          DataColumn(label: Text('Datum')),
          DataColumn(label: Text('Beschreibung')),
          DataColumn(label: Text('Objekt')),
          DataColumn(label: Text('Brutto €')),
          DataColumn(label: Text('Status')),
        ],
        rows: [
          for (final a in mine)
            DataRow(
              onSelectChanged: (_) =>
                  showAngebotEditor(context, eintrag: a),
              cells: [
                DataCell(Text(a.angebot.angebotsnummer ?? '',
                    style: const TextStyle(fontFamily: 'monospace'))),
                DataCell(Text(_dateFmt.format(a.angebot.datum))),
                DataCell(SizedBox(
                  width: 280,
                  child: Text(
                    (a.angebot.anfrage?.trim().isNotEmpty ?? false)
                        ? a.angebot.anfrage!
                        : (a.angebot.betreff ?? ''),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                )),
                DataCell(SizedBox(
                  width: 200,
                  child: Text(
                    [
                      a.angebot.objektStrasse,
                      [a.angebot.objektPlz, a.angebot.objektOrt]
                          .whereType<String>()
                          .where((s) => s.trim().isNotEmpty)
                          .join(' '),
                    ]
                        .whereType<String>()
                        .where((s) => s.trim().isNotEmpty)
                        .join(', '),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                )),
                DataCell(Text(_money(a.angebot.brutto))),
                DataCell(Text(a.angebot.status)),
              ],
            ),
        ],
      ),
    );
  }
}

class _GutachtenTab extends ConsumerWidget {
  const _GutachtenTab({required this.auftragId});
  final int auftragId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDatabaseProvider);
    return StreamBuilder<List<GutachtenData>>(
      stream: (db.select(db.gutachten)
            ..where((t) => t.auftragId.equals(auftragId)))
          .watch(),
      builder: (ctx, snap) {
        final items = snap.data ?? const [];
        if (items.isEmpty) {
          return _emptyTab(ctx, Icons.description_outlined,
              'Noch kein Gutachten angelegt.', '/gutachten',
              createLabel: '+ Neues Gutachten',
              onCreate: () => showGutachtenEditor(ctx,
                  prefillAuftragId: auftragId));
        }
        return _listWrapper(
          ctx,
          header: '${items.length} Gutachten',
          onOpen: () => ctx.go('/gutachten'),
          createLabel: '+ Neues Gutachten',
          onCreate: () => showGutachtenEditor(ctx,
              prefillAuftragId: auftragId),
          table: DataTable(
            showCheckboxColumn: false,
            columns: const [
              DataColumn(label: Text('Nr.')),
              DataColumn(label: Text('Titel')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Ortstermin')),
              DataColumn(label: Text('Abgabe')),
            ],
            rows: [
              for (final g in items)
                DataRow(
                  onSelectChanged: (_) =>
                      showGutachtenEditor(ctx, gutachten: g),
                  cells: [
                    DataCell(Text(g.nummer ?? '',
                        style: const TextStyle(fontFamily: 'monospace'))),
                    DataCell(Text(g.titel ?? '')),
                    DataCell(Text(g.status)),
                    DataCell(Text(g.ortsterminAm == null
                        ? ''
                        : _dateFmt.format(g.ortsterminAm!))),
                    DataCell(Text(g.abgabeAm == null
                        ? ''
                        : _dateFmt.format(g.abgabeAm!))),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _FotosTab extends ConsumerWidget {
  const _FotosTab({required this.auftragId});
  final int auftragId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDatabaseProvider);
    return StreamBuilder<List<Foto>>(
      stream: (db.select(db.fotos)
            ..where((t) => t.auftragId.equals(auftragId)))
          .watch(),
      builder: (ctx, snap) {
        final items = snap.data ?? const [];
        if (items.isEmpty) {
          return _emptyTab(ctx, Icons.photo_library_outlined,
              'Keine Fotos zur Akte.', '/fotos',
              createLabel: '+ Fotos hinzufügen');
        }
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Text('${items.length} Fotos',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton(
                    onPressed: () => ctx.go('/fotos'),
                    child: const Text('im Foto-Modul öffnen →')),
              ]),
              const SizedBox(height: 10),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 4,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  children: [
                    for (final f in items)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: AppTheme.slate200),
                        ),
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(f.titel ?? '(ohne Titel)',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            if ((f.raum ?? '').isNotEmpty)
                              Text(f.raum!,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.slate500)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DokumenteTab extends ConsumerWidget {
  const _DokumenteTab({required this.auftragId});
  final int auftragId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDatabaseProvider);
    return StreamBuilder<List<DokumenteData>>(
      stream: (db.select(db.dokumente)
            ..where((t) => t.auftragId.equals(auftragId)))
          .watch(),
      builder: (ctx, snap) {
        final items = snap.data ?? const [];
        if (items.isEmpty) {
          return _emptyTab(ctx, Icons.attach_file_outlined,
              'Keine Dokumente hinterlegt.', '/dokumente',
              createLabel: '+ Dokument / E-Mail hochladen',
              onCreate: () => showDokumenteUploadDialog(ctx,
                  auftragId: auftragId));
        }
        return _listWrapper(
          ctx,
          header: '${items.length} Dokumente',
          onOpen: () => ctx.go('/dokumente'),
          createLabel: '+ Dokument / E-Mail',
          onCreate: () =>
              showDokumenteUploadDialog(ctx, auftragId: auftragId),
          table: DataTable(
            showCheckboxColumn: false,
            columns: const [
              DataColumn(label: Text('Datum')),
              DataColumn(label: Text('Titel')),
              DataColumn(label: Text('Kategorie')),
              DataColumn(label: Text('MIME')),
              DataColumn(label: Text('Größe'), numeric: true),
              DataColumn(label: Text('')),
            ],
            rows: [
              for (final d in items)
                DataRow(
                  onSelectChanged: (_) => openDokument(ctx, d),
                  cells: [
                    DataCell(Text(_dateFmt.format(d.datum))),
                    DataCell(Text(d.titel ?? '')),
                    DataCell(Text(d.kategorie ?? '')),
                    DataCell(Text(d.mimeType ?? '')),
                    DataCell(Text(d.dateigroesse == null
                        ? ''
                        : '${(d.dateigroesse! / 1024).toStringAsFixed(1)} KB')),
                    DataCell(Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.visibility_outlined,
                              size: 18),
                          tooltip: 'Öffnen / Vorschau',
                          onPressed: () => openDokument(ctx, d),
                        ),
                        IconButton(
                          icon:
                              const Icon(Icons.edit_outlined, size: 18),
                          tooltip: 'Metadaten bearbeiten',
                          onPressed: () async {
                            final db = ref.read(appDatabaseProvider);
                            final auf = await (db.select(db.auftraege)
                                  ..where((t) =>
                                      t.id.equals(auftragId)))
                                .getSingleOrNull();
                            if (!ctx.mounted) return;
                            await showDokumentEditor(ctx,
                                eintrag:
                                    DokumentWithAuftrag(d, auf));
                          },
                        ),
                      ],
                    )),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Tab "LV / Kalkulation" innerhalb der Akte. Listet alle LVs zur Akte
/// und öffnet auf Klick den LV-Editor unter `/lv/:id`.
class _LvTab extends ConsumerWidget {
  const _LvTab({required this.auftragId});
  final int auftragId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(lvListProvider(auftragId));
    return list.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (rows) {
        if (rows.isEmpty) {
          return _emptyTab(
            context,
            Icons.list_alt_outlined,
            'Noch kein Leistungsverzeichnis erstellt.',
            '/lv',
            createLabel: '+ LV / Kalkulation anlegen',
            onCreate: () async {
              final id = await showLvAnlegenDialog(context,
                  auftragId: auftragId);
              if (id != null && context.mounted) {
                context.go('/lv/$id');
              }
            },
          );
        }
        return _listWrapper(
          context,
          header: '${rows.length} LV / Kalkulation',
          onOpen: () => context.go('/lv'),
          createLabel: '+ Neues LV',
          onCreate: () async {
            final id = await showLvAnlegenDialog(context,
                auftragId: auftragId);
            if (id != null && context.mounted) {
              context.go('/lv/$id');
            }
          },
          table: DataTable(
            showCheckboxColumn: false,
            columns: const [
              DataColumn(label: Text('Datum')),
              DataColumn(label: Text('Bezeichnung')),
              DataColumn(label: Text('LV-Nr.')),
              DataColumn(label: Text('Status')),
            ],
            rows: [
              for (final r in rows)
                DataRow(
                  onSelectChanged: (_) => context.go('/lv/${r.id}'),
                  cells: [
                    DataCell(Text(_dateFmt.format(r.datum))),
                    DataCell(Text(r.bezeichnung)),
                    DataCell(Text(r.nummer ?? '')),
                    DataCell(Text(r.status)),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _NormenTab extends ConsumerWidget {
  const _NormenTab({required this.auftragId});
  final int auftragId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDatabaseProvider);
    return StreamBuilder<List<NormenData>>(
      stream: (db.select(db.normen)
            ..where((t) => t.auftragId.equals(auftragId)))
          .watch(),
      builder: (ctx, snap) {
        final items = snap.data ?? const [];
        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.menu_book_outlined,
                      size: 44, color: AppTheme.slate400),
                  const SizedBox(height: 10),
                  const Text(
                      'Keine Normen zugeordnet. Aus dem Katalog übernehmen.',
                      style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton.icon(
                        onPressed: () =>
                            showNormenKatalogPicker(ctx,
                                auftragId: auftragId),
                        icon: const Icon(Icons.library_add_outlined,
                            size: 16),
                        label: const Text('Aus Katalog zuordnen'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => ctx.go('/normen'),
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text('Normen-Modul öffnen'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }
        return _listWrapper(
          ctx,
          header: '${items.length} Normen',
          onOpen: () => ctx.go('/normen'),
          createLabel: '+ Aus Katalog',
          onCreate: () =>
              showNormenKatalogPicker(ctx, auftragId: auftragId),
          table: DataTable(
            showCheckboxColumn: false,
            columns: const [
              DataColumn(label: Text('Nummer')),
              DataColumn(label: Text('Titel')),
              DataColumn(label: Text('Ausgabe')),
              DataColumn(label: Text('Relevanz')),
              DataColumn(label: Text('')),
            ],
            rows: [
              for (final n in items)
                DataRow(
                  onSelectChanged: (_) => ctx.go('/normen'),
                  cells: [
                    DataCell(Text(n.nummer,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12))),
                    DataCell(Text(n.titel ?? '')),
                    DataCell(Text(n.ausgabe ?? '')),
                    DataCell(Text(n.relevanz ?? '')),
                    DataCell(IconButton(
                      tooltip: 'Norm aus dieser Akte entfernen',
                      icon: const Icon(Icons.link_off_outlined,
                          size: 18),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: ctx,
                          useRootNavigator: true,
                          builder: (_) => AlertDialog(
                            title: const Text(
                                'Norm aus Akte entfernen?'),
                            content: Text(
                                'Die Zuordnung von „${n.nummer}" zu '
                                'dieser Akte wird gelöst. Die Norm '
                                'selbst bleibt im Katalog erhalten.'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx,
                                        rootNavigator: true)
                                    .pop(false),
                                child: const Text('Abbrechen'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.of(ctx,
                                        rootNavigator: true)
                                    .pop(true),
                                child: const Text('Entfernen'),
                              ),
                            ],
                          ),
                        );
                        if (ok != true) return;
                        await (db.update(db.normen)
                              ..where((t) => t.id.equals(n.id)))
                            .write(const NormenCompanion(
                                auftragId: Value(null)));
                      },
                    )),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _GeraeteTab extends ConsumerWidget {
  const _GeraeteTab({required this.auftragId});
  final int auftragId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDatabaseProvider);
    return StreamBuilder<List<GeraeteData>>(
      stream: ((db.select(db.auftraegeGeraete)
                ..where((t) => t.auftragId.equals(auftragId)))
              .join([
        innerJoin(
            db.geraete, db.geraete.id.equalsExp(db.auftraegeGeraete.geraetId))
      ]))
          .watch()
          .map((rows) => rows.map((r) => r.readTable(db.geraete)).toList()),
      builder: (ctx, snap) {
        final items = snap.data ?? const [];
        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.build_circle_outlined,
                      size: 44, color: AppTheme.slate400),
                  const SizedBox(height: 10),
                  const Text('Keine Messgeräte zugeordnet.',
                      style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton.icon(
                        onPressed: () => showGeraeteKatalogPicker(ctx,
                            auftragId: auftragId),
                        icon: const Icon(Icons.library_add_outlined,
                            size: 16),
                        label: const Text('Aus Katalog zuordnen'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => ctx.go('/geraete'),
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text('Geräte-Modul öffnen'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }
        return _listWrapper(
          ctx,
          header: '${items.length} Geräte im Einsatz',
          onOpen: () => ctx.go('/geraete'),
          createLabel: '+ Aus Katalog',
          onCreate: () =>
              showGeraeteKatalogPicker(ctx, auftragId: auftragId),
          table: DataTable(
            showCheckboxColumn: false,
            columns: const [
              DataColumn(label: Text('Inv.-Nr.')),
              DataColumn(label: Text('Bezeichnung')),
              DataColumn(label: Text('Hersteller')),
              DataColumn(label: Text('Nächste Kal.')),
              DataColumn(label: Text('')),
            ],
            rows: [
              for (final g in items)
                DataRow(
                  onSelectChanged: (_) => ctx.go('/geraete'),
                  cells: [
                    DataCell(Text(g.inventarNr ?? '')),
                    DataCell(Text(g.bezeichnung)),
                    DataCell(Text(g.hersteller ?? '')),
                    DataCell(Text(g.naechsteKalibrierung == null
                        ? ''
                        : _dateFmt.format(g.naechsteKalibrierung!))),
                    DataCell(IconButton(
                      tooltip: 'Gerät aus dieser Akte entfernen',
                      icon: const Icon(Icons.link_off_outlined,
                          size: 18),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: ctx,
                          useRootNavigator: true,
                          builder: (_) => AlertDialog(
                            title: const Text(
                                'Gerät aus Akte entfernen?'),
                            content: Text(
                                'Die Zuordnung von „${g.bezeichnung}" '
                                'zu dieser Akte wird gelöst. Das Gerät '
                                'selbst bleibt im Inventar erhalten.'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx,
                                        rootNavigator: true)
                                    .pop(false),
                                child: const Text('Abbrechen'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.of(ctx,
                                        rootNavigator: true)
                                    .pop(true),
                                child: const Text('Entfernen'),
                              ),
                            ],
                          ),
                        );
                        if (ok != true) return;
                        await (db.delete(db.auftraegeGeraete)
                              ..where((t) =>
                                  t.auftragId.equals(auftragId))
                              ..where((t) => t.geraetId.equals(g.id)))
                            .go();
                      },
                    )),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ErlaeuterungenTab extends ConsumerWidget {
  const _ErlaeuterungenTab({required this.auftragId});
  final int auftragId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDatabaseProvider);
    return StreamBuilder<List<ErlaeuterungenData>>(
      stream: (db.select(db.erlaeuterungen)
            ..where((t) => t.auftragId.equals(auftragId)))
          .watch(),
      builder: (ctx, snap) {
        final items = snap.data ?? const [];
        if (items.isEmpty) {
          return _emptyTab(ctx, Icons.gavel_outlined,
              'Keine Erläuterungstermine.', '/erlaeuterungen',
              createLabel: '+ Neuer Erläuterungstermin',
              onCreate: () => showErlaeuterungEditor(ctx,
                  prefillAuftragId: auftragId));
        }
        return _listWrapper(
          ctx,
          header: '${items.length} Termine',
          onOpen: () => ctx.go('/erlaeuterungen'),
          createLabel: '+ Neuer Termin',
          onCreate: () => showErlaeuterungEditor(ctx,
              prefillAuftragId: auftragId),
          table: DataTable(
            showCheckboxColumn: false,
            columns: const [
              DataColumn(label: Text('Datum')),
              DataColumn(label: Text('Gericht')),
              DataColumn(label: Text('Saal')),
              DataColumn(label: Text('Status')),
            ],
            rows: [
              for (final e in items)
                DataRow(
                  onSelectChanged: (_) async {
                    final auf = await (db.select(db.auftraege)
                          ..where((t) => t.id.equals(auftragId)))
                        .getSingleOrNull();
                    if (!ctx.mounted) return;
                    await showErlaeuterungEditor(ctx,
                        eintrag: ErlaeuterungWithAuftrag(e, auf));
                  },
                  cells: [
                    DataCell(Text(e.terminAm == null
                        ? ''
                        : DateFormat('dd.MM.yyyy HH:mm', 'de')
                            .format(e.terminAm!))),
                    DataCell(Text(e.gericht ?? '')),
                    DataCell(Text(e.saal ?? '')),
                    DataCell(Text(e.status)),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _AnschreibenTab extends ConsumerWidget {
  const _AnschreibenTab({required this.auftragId, required this.kundeId});
  final int auftragId;
  final int? kundeId;

  void _neuesAnschreiben(BuildContext context) {
    showAnschreibenEditor(
      context,
      prefillAuftragId: auftragId,
      prefillKundeId: kundeId,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(anschreibenListProvider).valueOrNull ?? const [];
    final mine =
        all.where((a) => a.anschreiben.auftragId == auftragId).toList();
    if (mine.isEmpty) {
      return _emptyTab(context, Icons.drafts_outlined,
          'Noch keine Anschreiben zu dieser Akte.', '/anschreiben',
          createLabel: '+ Neues Anschreiben',
          onCreate: () => _neuesAnschreiben(context));
    }
    return _listWrapper(
      context,
      header: '${mine.length} Anschreiben',
      onOpen: () => context.go('/anschreiben'),
      createLabel: '+ Neues Anschreiben',
      onCreate: () => _neuesAnschreiben(context),
      table: DataTable(
        showCheckboxColumn: false,
        columns: const [
          DataColumn(label: Text('Datum')),
          DataColumn(label: Text('Betreff')),
          DataColumn(label: Text('Empfänger')),
          DataColumn(label: Text('Status')),
        ],
        rows: [
          for (final a in mine)
            DataRow(
              onSelectChanged: (_) =>
                  showAnschreibenEditor(context, eintrag: a),
              cells: [
                DataCell(Text(_dateFmt.format(a.anschreiben.datum))),
                DataCell(SizedBox(
                  width: 280,
                  child: Text(
                    a.anschreiben.betreff ?? '',
                    overflow: TextOverflow.ellipsis,
                  ),
                )),
                DataCell(Text(
                    a.kunde == null ? '—' : kundeAnzeigename(a.kunde!))),
                DataCell(Text(a.anschreiben.status)),
              ],
            ),
        ],
      ),
    );
  }
}

// ---------------- Helpers ----------------

final _dateFmt = DateFormat('dd.MM.yyyy', 'de');
String _money(double v) =>
    NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2)
        .format(v);

Widget _emptyTab(
  BuildContext ctx,
  IconData icon,
  String text,
  String route, {
  String? createLabel,
  VoidCallback? onCreate,
}) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: AppTheme.slate400),
          const SizedBox(height: 10),
          Text(text,
              style: TextStyle(color: AppTheme.slate600, fontSize: 13)),
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                onPressed: onCreate ?? () => ctx.go(route),
                icon: const Icon(Icons.add, size: 16),
                label: Text(createLabel ?? 'Neu anlegen'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => ctx.go(route),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Modul öffnen'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

Widget _listWrapper(
  BuildContext ctx, {
  required String header,
  required VoidCallback onOpen,
  required Widget table,
  String? createLabel,
  VoidCallback? onCreate,
  List<Widget> extraActions = const [],
}) {
  return Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Text(header,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600)),
          const Spacer(),
          for (final a in extraActions) ...[a, const SizedBox(width: 6)],
          if (createLabel != null) ...[
            FilledButton.icon(
              onPressed: onCreate ?? onOpen,
              icon: const Icon(Icons.add, size: 16),
              label: Text(createLabel),
            ),
            const SizedBox(width: 6),
          ],
          TextButton(
              onPressed: onOpen, child: const Text('im Modul öffnen →')),
        ]),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.slate200),
          ),
          child: SingleChildScrollView(
              scrollDirection: Axis.horizontal, child: table),
        ),
      ],
    ),
  );
}
