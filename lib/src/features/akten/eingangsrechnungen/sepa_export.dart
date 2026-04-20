import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show leftOuterJoin;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/database/database_provider.dart';
import '../../system/einstellungen/einstellungen_repository.dart';
import 'skr_kategorien.dart';

// ---------------------------------------------------------------------------
// SEPA-Sammelüberweisung (pain.001.001.03)
// ---------------------------------------------------------------------------

Future<void> showSepaExportDialog(
    BuildContext context, WidgetRef ref) async {
  final db = ref.read(appDatabaseProvider);
  final repo = ref.read(einstellungenRepositoryProvider);
  final eigenerName = await repo.get(SettingsKeys.bankInhaber);
  final eigeneIban = await repo.get(SettingsKeys.bankIban);
  final eigenerBic = await repo.get(SettingsKeys.bankBic);

  if ((eigenerName ?? '').isEmpty || (eigeneIban ?? '').isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Bankverbindung in Einstellungen pflegen (Kontoinhaber + IBAN).')));
    }
    return;
  }

  // Offene Eingangsrechnungen mit Lieferanten-IBAN laden.
  final rows = await (db.select(db.eingangsrechnungen).join([
    leftOuterJoin(
        db.lieferanten,
        db.lieferanten.id
            .equalsExp(db.eingangsrechnungen.lieferantId)),
  ])
        ..where(db.eingangsrechnungen.status.isNotValue('bezahlt'))
        ..where(db.eingangsrechnungen.status.isNotValue('storniert')))
      .get();

  final selection = <_SepaItem>[];
  for (final r in rows) {
    final er = r.readTable(db.eingangsrechnungen);
    final lief = r.readTableOrNull(db.lieferanten);
    final iban = lief?.iban?.replaceAll(' ', '') ?? '';
    final offen = er.brutto - er.bezahlt;
    if (offen <= 0) continue;
    if (iban.isEmpty) continue;
    selection.add(_SepaItem(
      id: er.id,
      belegNr: er.rechnungsnummer ?? 'ER-${er.id}',
      name: lief?.firma ?? er.lieferantName ?? '(Lieferant)',
      iban: iban,
      bic: lief?.bic,
      betrag: offen,
      verwendungszweck:
          '${er.rechnungsnummer ?? "Rechnung"}${(lief?.kundennummer ?? "").isEmpty ? "" : " · Kd ${lief!.kundennummer}"}',
    ));
  }

  if (!context.mounted) return;
  if (selection.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Keine offenen Rechnungen mit Lieferanten-IBAN gefunden.')));
    return;
  }

  final picked = <_SepaItem>{...selection};
  final ok = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (_) => StatefulBuilder(builder: (ctx, setLocal) {
      final fmt =
          NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);
      final summe =
          picked.fold<double>(0, (s, i) => s + i.betrag);
      return Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                child: Row(
                  children: [
                    const Icon(Icons.account_balance),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('SEPA-Sammelüberweisung',
                          style: Theme.of(ctx).textTheme.titleLarge),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Text(
                  'Wähle die offenen Eingangsrechnungen aus, für die eine SEPA-Überweisung '
                  'erzeugt werden soll. Die XML-Datei (pain.001.001.03) kannst du in dein '
                  'Banking-Programm einlesen.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final i in selection)
                      CheckboxListTile(
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: picked.contains(i),
                        onChanged: (v) => setLocal(() {
                          if (v == true) {
                            picked.add(i);
                          } else {
                            picked.remove(i);
                          }
                        }),
                        title: Text(
                            '${i.name} · ${fmt.format(i.betrag)}',
                            style: const TextStyle(fontSize: 13)),
                        subtitle: Text(
                          '${i.belegNr} · IBAN ${_maskIban(i.iban)}'
                          '${(i.bic ?? "").isEmpty ? "" : " · BIC ${i.bic}"}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Text('${picked.length} Zahlungen · Summe: ${fmt.format(summe)}',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Abbrechen'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      icon: const Icon(Icons.ios_share),
                      label: const Text('XML exportieren'),
                      onPressed: picked.isEmpty
                          ? null
                          : () => Navigator.pop(ctx, true),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }),
  );

  if (ok != true || picked.isEmpty) return;
  final xml = _buildSepaPain001(
    auftraggeberName: eigenerName!,
    auftraggeberIban: eigeneIban!.replaceAll(' ', ''),
    auftraggeberBic: eigenerBic ?? '',
    items: picked.toList(),
  );
  await Share.shareXFiles(
    [
      XFile.fromData(
        Uint8List.fromList(utf8.encode(xml)),
        name: 'sepa-ueberweisung-${DateFormat('yyyy-MM-dd').format(DateTime.now())}.xml',
        mimeType: 'application/xml',
      ),
    ],
    subject: 'SEPA-Sammelüberweisung',
    text: '${picked.length} Überweisungen',
  );
}

class _SepaItem {
  final int id;
  final String belegNr;
  final String name;
  final String iban;
  final String? bic;
  final double betrag;
  final String verwendungszweck;
  const _SepaItem({
    required this.id,
    required this.belegNr,
    required this.name,
    required this.iban,
    required this.betrag,
    required this.verwendungszweck,
    this.bic,
  });
}

String _maskIban(String iban) {
  if (iban.length < 8) return iban;
  return '${iban.substring(0, 4)}****${iban.substring(iban.length - 4)}';
}

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll("'", '&apos;')
    .replaceAll('"', '&quot;');

String _buildSepaPain001({
  required String auftraggeberName,
  required String auftraggeberIban,
  required String auftraggeberBic,
  required List<_SepaItem> items,
}) {
  final ts = DateTime.now().toIso8601String().substring(0, 19);
  final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
  final ms = DateTime.now().millisecondsSinceEpoch;
  final msgId = 'AKT$ms';
  final pmtId = 'PMT$ms';
  final summe = items.fold<double>(0, (s, i) => s + i.betrag);
  final buf = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
        '<Document xmlns="urn:iso:std:iso:20022:tech:xsd:pain.001.001.03" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">')
    ..writeln('  <CstmrCdtTrfInitn>')
    ..writeln('    <GrpHdr>')
    ..writeln('      <MsgId>$msgId</MsgId>')
    ..writeln('      <CreDtTm>$ts</CreDtTm>')
    ..writeln('      <NbOfTxs>${items.length}</NbOfTxs>')
    ..writeln('      <CtrlSum>${summe.toStringAsFixed(2)}</CtrlSum>')
    ..writeln('      <InitgPty><Nm>'
        '${_esc(_cut(auftraggeberName, 70))}</Nm></InitgPty>')
    ..writeln('    </GrpHdr>')
    ..writeln('    <PmtInf>')
    ..writeln('      <PmtInfId>$pmtId</PmtInfId>')
    ..writeln('      <PmtMtd>TRF</PmtMtd>')
    ..writeln('      <BtchBookg>true</BtchBookg>')
    ..writeln('      <NbOfTxs>${items.length}</NbOfTxs>')
    ..writeln('      <CtrlSum>${summe.toStringAsFixed(2)}</CtrlSum>')
    ..writeln(
        '      <PmtTpInf><SvcLvl><Cd>SEPA</Cd></SvcLvl></PmtTpInf>')
    ..writeln('      <ReqdExctnDt>$today</ReqdExctnDt>')
    ..writeln('      <Dbtr><Nm>'
        '${_esc(_cut(auftraggeberName, 70))}</Nm></Dbtr>')
    ..writeln(
        '      <DbtrAcct><Id><IBAN>${_esc(auftraggeberIban)}</IBAN></Id></DbtrAcct>');
  if (auftraggeberBic.isNotEmpty) {
    buf.writeln('      <DbtrAgt><FinInstnId><BIC>'
        '${_esc(auftraggeberBic)}</BIC></FinInstnId></DbtrAgt>');
  } else {
    buf.writeln('      <DbtrAgt><FinInstnId><Othr><Id>NOTPROVIDED</Id>'
        '</Othr></FinInstnId></DbtrAgt>');
  }
  buf.writeln('      <ChrgBr>SLEV</ChrgBr>');
  for (final t in items) {
    buf
      ..writeln('      <CdtTrfTxInf>')
      ..writeln(
          '        <PmtId><EndToEndId>${_esc(_cut(t.verwendungszweck, 35))}</EndToEndId></PmtId>')
      ..writeln(
          '        <Amt><InstdAmt Ccy="EUR">${t.betrag.toStringAsFixed(2)}</InstdAmt></Amt>');
    if ((t.bic ?? '').isNotEmpty) {
      buf.writeln(
          '        <CdtrAgt><FinInstnId><BIC>${_esc(t.bic!)}</BIC></FinInstnId></CdtrAgt>');
    }
    buf
      ..writeln('        <Cdtr><Nm>${_esc(_cut(t.name, 70))}</Nm></Cdtr>')
      ..writeln(
          '        <CdtrAcct><Id><IBAN>${_esc(t.iban)}</IBAN></Id></CdtrAcct>')
      ..writeln(
          '        <RmtInf><Ustrd>${_esc(_cut(t.verwendungszweck, 140))}</Ustrd></RmtInf>')
      ..writeln('      </CdtTrfTxInf>');
  }
  buf
    ..writeln('    </PmtInf>')
    ..writeln('  </CstmrCdtTrfInitn>')
    ..writeln('</Document>');
  return buf.toString();
}

String _cut(String s, int max) => s.length <= max ? s : s.substring(0, max);

// ---------------------------------------------------------------------------
// DATEV-CSV-Export (Eingangsrechnungen, SV-Software-kompatibel)
// ---------------------------------------------------------------------------

Future<void> exportEingangsrechnungenDatevCsv(
    BuildContext context, WidgetRef ref) async {
  final db = ref.read(appDatabaseProvider);
  final settings = ref.read(einstellungenProvider).valueOrNull ??
      const <String, String>{};
  final skr = settings[SettingsKeys.datevKontenrahmen] ?? 'SKR03';

  final rows = await (db.select(db.eingangsrechnungen).join([
    leftOuterJoin(
        db.lieferanten,
        db.lieferanten.id
            .equalsExp(db.eingangsrechnungen.lieferantId)),
  ])).get();

  if (rows.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Keine Eingangsrechnungen zum Exportieren.')));
    }
    return;
  }

  final dateFmt = DateFormat('dd.MM.yyyy');
  final moneyFmt =
      NumberFormat.currency(locale: 'de_DE', symbol: '', decimalDigits: 2);

  String cell(String s) {
    final esc = s.replaceAll('"', '""');
    final needs = s.contains(';') || s.contains('"') || s.contains('\n');
    return needs ? '"$esc"' : esc;
  }

  final header = [
    'Belegnr',
    'Datum',
    'Lieferant',
    'Kategorie',
    'Konto',
    'Netto',
    'USt-Satz',
    'USt',
    'Brutto',
    'Akte',
    'Status',
  ];
  final lines = <String>[header.map(cell).join(';')];
  for (final r in rows) {
    final er = r.readTable(db.eingangsrechnungen);
    final lief = r.readTableOrNull(db.lieferanten);
    final kat = skrByKey(er.kategorie);
    final konto = skr == 'SKR04' ? kat.skr04 : kat.skr03;
    lines.add([
      er.rechnungsnummer ?? '',
      er.rechnungsdatum == null ? '' : dateFmt.format(er.rechnungsdatum!),
      lief?.firma ?? er.lieferantName ?? '',
      kat.label,
      er.datevKonto ?? konto,
      moneyFmt.format(er.netto),
      er.ustSatz.toStringAsFixed(0),
      moneyFmt.format(er.ustBetrag),
      moneyFmt.format(er.brutto),
      '', // Akten-Az fehlt im Join — bewusst leer
      er.status,
    ].map(cell).join(';'));
  }
  final csv = lines.join('\r\n');
  await Share.shareXFiles(
    [
      XFile.fromData(
        Uint8List.fromList(latin1.encode(csv)),
        name:
            'eingangsrechnungen_${DateFormat("yyyy-MM-dd").format(DateTime.now())}.csv',
        mimeType: 'text/csv',
      ),
    ],
    subject: 'DATEV-CSV Eingangsrechnungen',
    text: '${rows.length} Datensätze · Kontenrahmen $skr',
  );
}
