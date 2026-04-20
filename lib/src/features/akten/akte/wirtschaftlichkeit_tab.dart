import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../system/einstellungen/einstellungen_repository.dart';

/// Tab in der Akte: zeigt Erlöse, direkte + kalkulatorische Kosten,
/// Deckungsbeitrag und Stundenrendite. Live aus Drift-Streams.
class WirtschaftlichkeitTab extends ConsumerWidget {
  const WirtschaftlichkeitTab({super.key, required this.auftragId});
  final int auftragId;

  static final _money =
      NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDatabaseProvider);
    final settings = ref.watch(einstellungenProvider).valueOrNull ??
        const <String, String>{};
    final intSatz = double.tryParse(
            (settings[SettingsKeys.internerKostensatz] ?? '65')
                .replaceAll(',', '.')) ??
        65;

    return StreamBuilder<List<RechnungenData>>(
      stream: (db.select(db.rechnungen)
            ..where((t) => t.auftragId.equals(auftragId)))
          .watch(),
      builder: (_, rSnap) => StreamBuilder<List<EingangsrechnungenData>>(
        stream: (db.select(db.eingangsrechnungen)
              ..where((t) => t.auftragId.equals(auftragId)))
            .watch(),
        builder: (_, eSnap) => StreamBuilder<List<StundenData>>(
          stream: (db.select(db.stunden)
                ..where((t) => t.auftragId.equals(auftragId)))
              .watch(),
          builder: (_, sSnap) => StreamBuilder<List<AuslagenData>>(
            stream: (db.select(db.auslagen)
                  ..where((t) => t.auftragId.equals(auftragId)))
                .watch(),
            builder: (_, aSnap) {
              final rechnungen = rSnap.data ?? const <RechnungenData>[];
              final eingang = eSnap.data ?? const <EingangsrechnungenData>[];
              final stunden = sSnap.data ?? const <StundenData>[];
              final auslagen = aSnap.data ?? const <AuslagenData>[];

              final erloeseNetto = rechnungen
                  .where((r) => r.status != 'storniert')
                  .fold<double>(0, (s, r) => s + r.netto);

              final fremdLeistungEingang = eingang.fold<double>(
                  0, (s, e) => s + e.netto);
              final auslagenSumme =
                  auslagen.fold<double>(0, (s, a) => s + a.summe);

              // Eigene vs. Fremd-Stunden trennen.
              final eigeneStunden =
                  stunden.where((s) => s.partnerId == null).toList();
              final fremdStunden =
                  stunden.where((s) => s.partnerId != null).toList();
              final eigeneMinuten =
                  eigeneStunden.fold<int>(0, (s, t) => s + t.minuten);
              final fremdMinuten =
                  fremdStunden.fold<int>(0, (s, t) => s + t.minuten);
              final eigeneStundenH = eigeneMinuten / 60.0;
              final fremdStundenH = fremdMinuten / 60.0;

              final kundenStundensatzAvg = eigeneStunden.isEmpty
                  ? 0.0
                  : eigeneStunden.fold<double>(
                          0, (s, t) => s + (t.satz ?? 0)) /
                      eigeneStunden.length;
              final bezahlbarStunden =
                  eigeneStundenH * kundenStundensatzAvg;
              final kalkKosten = eigeneStundenH * intSatz;
              // Fremdstunden kosten mit ihrem eigenen Satz.
              final fremdStundenKosten = fremdStunden.fold<double>(
                  0, (s, t) => s + (t.minuten / 60.0) * (t.satz ?? 0));
              final fremdLeistung = fremdLeistungEingang + fremdStundenKosten;

              final direkteKosten =
                  fremdLeistung + auslagenSumme + kalkKosten;
              final deckungsbeitrag = erloeseNetto - direkteKosten;
              final stundenrendite = eigeneStundenH == 0
                  ? 0.0
                  : deckungsbeitrag / eigeneStundenH;

              return SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionTitle('Erlöse'),
                    _Row('Rechnungen netto',
                        _money.format(erloeseNetto), bold: true),
                    _Row('Eigene Stunden × Kunden-Satz (Ø)',
                        '${eigeneStundenH.toStringAsFixed(2)}\u00a0h × '
                            '${_money.format(kundenStundensatzAvg)} = '
                            '${_money.format(bezahlbarStunden)}',
                        muted: true),
                    const SizedBox(height: 20),
                    _SectionTitle('Direkte Kosten'),
                    _Row('Eingangsrechnungen',
                        _money.format(fremdLeistungEingang)),
                    _Row(
                        'Partner-/Subunternehmer-Stunden '
                        '(${fremdStundenH.toStringAsFixed(2)}\u00a0h)',
                        _money.format(fremdStundenKosten)),
                    _Row('Fremdleistung gesamt',
                        _money.format(fremdLeistung),
                        bold: true),
                    _Row('Auslagen', _money.format(auslagenSumme)),
                    _Row(
                        'Kalkulatorische Eigenleistung '
                        '(${eigeneStundenH.toStringAsFixed(2)}\u00a0h × '
                        '${_money.format(intSatz)})',
                        _money.format(kalkKosten)),
                    _Row('Direkte Kosten gesamt',
                        _money.format(direkteKosten),
                        bold: true),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: deckungsbeitrag >= 0
                            ? Colors.green.shade50
                            : Colors.red.shade50,
                        border: Border.all(
                          color: deckungsbeitrag >= 0
                              ? Colors.green.shade200
                              : Colors.red.shade200,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Deckungsbeitrag',
                              style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 4),
                          Text(
                            _money.format(deckungsbeitrag),
                            style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: deckungsbeitrag >= 0
                                    ? Colors.green.shade800
                                    : Colors.red.shade800),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Stundenrendite: ${_money.format(stundenrendite)} pro Stunde',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Hinweis: Der interne Kostensatz ist in den Einstellungen '
                      'veränderbar (aktuell ${_money.format(intSatz)}/h).',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
                color: Theme.of(context).colorScheme.primary)),
      );
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value,
      {this.bold = false, this.muted = false});
  final String label;
  final String value;
  final bool bold;
  final bool muted;
  @override
  Widget build(BuildContext context) {
    final color = muted
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        bold ? FontWeight.w700 : FontWeight.normal,
                    color: color)),
          ),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      bold ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }
}
