import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:xml/xml.dart' as xml;

import '../../../data/database/app_database.dart';
import '../../../shared/widgets/badges.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';
import '../../akten/eingangsrechnungen/eingangsrechnungen_repository.dart';
import '../../akten/rechnungen/rechnungen_repository.dart';
import 'banking_repository.dart';

/// Banking-Modul: Kontoauszug-Zeilen importiert (CSV) und mit
/// Ausgangs-/Eingangsrechnungen oder „Privat" / „kein Beleg" verknüpft.
class BankingScreen extends ConsumerStatefulWidget {
  const BankingScreen({super.key});
  @override
  ConsumerState<BankingScreen> createState() => _BankingScreenState();
}

class _BankingScreenState extends ConsumerState<BankingScreen> {
  String? _kontoFilter;
  static final _money =
      NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);
  static final _date = DateFormat('dd.MM.yyyy', 'de');

  @override
  Widget build(BuildContext context) {
    final asyncList = ref.watch(bankBewegungenProvider(_kontoFilter));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.account_balance_outlined,
          title: 'Banking',
          subtitle:
              'Kontobewegungen (Volksbank / Sparkasse / …) importieren und mit '
              'Ausgangs-/Eingangsrechnungen verknüpfen.',
          actions: [
            OutlinedButton.icon(
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('CSV / CAMT importieren'),
              onPressed: _csvImport,
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Buchung erfassen'),
              onPressed: () => _openEditor(),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: _kontoFilterRow(),
        ),
        Expanded(
          child: asyncList.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Fehler: $e')),
            data: (rows) {
              if (rows.isEmpty) {
                return const EmptyListState(
                  icon: Icons.account_balance_outlined,
                  title: 'Keine Bewegungen',
                  hint:
                      'CSV-Auszug aus Volksbank/Sparkasse importieren oder '
                      'manuell erfassen — dann hier mit Belegen verknüpfen.',
                );
              }
              final offen = rows.where((r) => r.status == 'offen').length;
              return Column(
                children: [
                  if (offen > 0)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      color: Theme.of(context)
                          .colorScheme
                          .errorContainer
                          .withValues(alpha: 0.3),
                      child: Text(
                        '$offen Bewegung${offen == 1 ? '' : 'en'} ohne Beleg-Zuordnung — bitte prüfen.',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  Expanded(child: _tabelle(rows)),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _kontoFilterRow() {
    return FutureBuilder<List<String>>(
      future: ref.read(bankingRepositoryProvider).distinctKonten(),
      builder: (ctx, snap) {
        final konten = snap.data ?? const <String>[];
        return Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Alle Konten'),
              selected: _kontoFilter == null,
              onSelected: (_) => setState(() => _kontoFilter = null),
            ),
            for (final k in konten)
              ChoiceChip(
                label: Text(k),
                selected: _kontoFilter == k,
                onSelected: (_) => setState(() => _kontoFilter = k),
              ),
          ],
        );
      },
    );
  }

  Widget _tabelle(List<BankBewegungenData> rows) {
    return DataTableCard(
      child: DataTable(
        showCheckboxColumn: false,
        headingRowColor: WidgetStateProperty.all(
            Theme.of(context).colorScheme.surfaceContainerHighest),
        columns: const [
          DataColumn(label: Text('Datum')),
          DataColumn(label: Text('Konto')),
          DataColumn(label: Text('Gegenpartei')),
          DataColumn(label: Text('Verwendungszweck')),
          DataColumn(label: Text('Betrag'), numeric: true),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Beleg / Verknüpfung')),
          DataColumn(label: Text('')),
        ],
        rows: [
          for (final b in rows)
            DataRow(
              onSelectChanged: (_) => _openEditor(b: b),
              cells: [
                DataCell(Text(_date.format(b.buchungsdatum),
                    style: const TextStyle(fontSize: 12))),
                DataCell(Text(b.konto, style: const TextStyle(fontSize: 12))),
                DataCell(SizedBox(
                  width: 200,
                  child: Text(b.gegenpartei ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12)),
                )),
                DataCell(SizedBox(
                  width: 280,
                  child: Text(b.verwendungszweck ?? '—',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11)),
                )),
                DataCell(Text(
                  _money.format(b.betrag),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: b.betrag >= 0
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                  ),
                )),
                DataCell(_StatusChip(status: b.status)),
                DataCell(_BelegInfo(b: b)),
                DataCell(IconButton(
                  tooltip: 'Löschen',
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () =>
                      ref.read(bankingRepositoryProvider).delete(b.id),
                )),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _openEditor({BankBewegungenData? b}) async {
    await showDialog(
      context: context,
      useRootNavigator: true,
      builder: (_) => _BankingEditor(b: b),
    );
  }

  /// Import — erkennt automatisch ob CSV (Volksbank/Sparkasse/DKB-Export)
  /// oder CAMT.053-XML (ISO-20022, der EU-weite Bank-Standard, von jeder
  /// deutschen Bank im Online-Banking als Tagesendabschluss verfügbar).
  Future<void> _csvImport() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt', 'xml'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    // Encoding: erst UTF-8, sonst Latin-1 (deutsche Banken nutzen oft
    // ISO-8859-1).
    String content;
    try {
      content = utf8.decode(bytes);
    } catch (_) {
      content = latin1.decode(bytes);
    }
    final konto = await _kontoBezeichnungAbfragen(file.name);
    if (konto == null) return;
    final istXml = content.trimLeft().startsWith('<?xml') ||
        content.contains('<Document') ||
        file.extension?.toLowerCase() == 'xml';
    final neue = istXml
        ? _parseCamt053(content, konto)
        : _parseGenericCsv(content, konto);
    if (neue.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(istXml
                ? 'Keine Bewegungen in CAMT-XML gefunden — bitte Format prüfen.'
                : 'Keine Bewegungen in CSV gefunden — bitte Format prüfen.')));
      }
      return;
    }
    final inserted =
        await ref.read(bankingRepositoryProvider).importMany(neue);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '$inserted neue ${istXml ? 'CAMT-' : 'CSV-'}Bewegung${inserted == 1 ? '' : 'en'} importiert (${neue.length - inserted} Duplikate übersprungen).')));
  }

  /// Parst CAMT.053 (ISO 20022 Bank-to-Customer-Statement). Greift nur
  /// auf die Pflicht-Elemente zu, die jede deutsche Bank ausfüllt:
  /// Buchungsdatum, Betrag (mit CdtDbtInd-Vorzeichen), Verwendungszweck
  /// (Ustrd), Gegenpartei (Name + IBAN).
  List<BankBewegungenCompanion> _parseCamt053(String content, String konto) {
    final out = <BankBewegungenCompanion>[];
    xml.XmlDocument doc;
    try {
      doc = xml.XmlDocument.parse(content);
    } catch (_) {
      return out;
    }
    // Statements (es können mehrere pro Datei sein, z. B. ein Tag pro Stmt).
    for (final stmt in doc.findAllElements('Stmt')) {
      // Eigene IBAN (für Konto-Bezeichnung Hinweis).
      String? eigeneIban;
      final acct = stmt.findElements('Acct').firstOrNull;
      if (acct != null) {
        eigeneIban = acct
            .findAllElements('IBAN')
            .firstOrNull
            ?.innerText
            .trim();
      }
      for (final ntry in stmt.findElements('Ntry')) {
        final amtEl = ntry.findElements('Amt').firstOrNull;
        if (amtEl == null) continue;
        final betragRaw = double.tryParse(amtEl.innerText.trim());
        if (betragRaw == null) continue;
        final cdtDbt = ntry
            .findElements('CdtDbtInd')
            .firstOrNull
            ?.innerText
            .trim();
        // CRDT = Eingang (positiv), DBIT = Ausgang (negativ).
        final betrag = cdtDbt == 'DBIT' ? -betragRaw : betragRaw;
        final waehrung = amtEl.getAttribute('Ccy') ?? 'EUR';

        final bookgDt = ntry
            .findAllElements('BookgDt')
            .firstOrNull
            ?.findElements('Dt')
            .firstOrNull
            ?.innerText
            .trim();
        final valDt = ntry
            .findAllElements('ValDt')
            .firstOrNull
            ?.findElements('Dt')
            .firstOrNull
            ?.innerText
            .trim();
        final datum = _parseIsoDate(bookgDt) ?? _parseIsoDate(valDt);
        if (datum == null) continue;

        // Verwendungszweck — kann mehrfach unter NtryDtls/TxDtls/RmtInf/Ustrd
        // erscheinen. Wir konkatenieren alle Ustrd-Texte mit Newline.
        final ustrdTexte = ntry
            .findAllElements('Ustrd')
            .map((e) => e.innerText.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        // Manche Banken legen den Buchungstext zusätzlich in AddtlNtryInf.
        final addInf = ntry
            .findElements('AddtlNtryInf')
            .firstOrNull
            ?.innerText
            .trim();
        final zweck = [...ustrdTexte, if (addInf != null) addInf]
            .where((s) => s.isNotEmpty)
            .join('\n');

        // Gegenpartei: bei Eingang Dbtr (Schuldner = der zahlt uns),
        //              bei Ausgang Cdtr (Gläubiger = wir zahlen an).
        String? gegenparteiName;
        String? gegenparteiIban;
        String? gegenparteiBic;
        final partyTag = cdtDbt == 'DBIT' ? 'Cdtr' : 'Dbtr';
        final partyEl = ntry.findAllElements(partyTag).firstOrNull;
        if (partyEl != null) {
          gegenparteiName = partyEl
              .findAllElements('Nm')
              .firstOrNull
              ?.innerText
              .trim();
        }
        final acctTag =
            cdtDbt == 'DBIT' ? 'CdtrAcct' : 'DbtrAcct';
        final acctEl = ntry.findAllElements(acctTag).firstOrNull;
        if (acctEl != null) {
          gegenparteiIban =
              acctEl.findAllElements('IBAN').firstOrNull?.innerText.trim();
        }
        final agtTag = cdtDbt == 'DBIT' ? 'CdtrAgt' : 'DbtrAgt';
        final agtEl = ntry.findAllElements(agtTag).firstOrNull;
        if (agtEl != null) {
          gegenparteiBic =
              agtEl.findAllElements('BIC').firstOrNull?.innerText.trim();
        }

        out.add(BankBewegungenCompanion(
          konto: Value(konto),
          iban: Value(eigeneIban),
          buchungsdatum: Value(datum),
          valuta: Value(_parseIsoDate(valDt)),
          verwendungszweck: Value(zweck.isEmpty ? null : zweck),
          gegenpartei: Value(gegenparteiName?.isEmpty ?? true
              ? null
              : gegenparteiName),
          gegenpartyIban: Value(gegenparteiIban?.isEmpty ?? true
              ? null
              : gegenparteiIban),
          gegenpartyBic: Value(gegenparteiBic?.isEmpty ?? true
              ? null
              : gegenparteiBic),
          betrag: Value(betrag),
          waehrung: Value(waehrung),
        ));
      }
    }
    return out;
  }

  DateTime? _parseIsoDate(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _kontoBezeichnungAbfragen(String dateiname) async {
    final ctrl = TextEditingController(text: _kontoFilter ?? '');
    final result = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (_) => AlertDialog(
        title: const Text('Welches Konto?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Datei: $dateiname',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Bezeichnung',
                hintText: 'z. B. Volksbank Geschäft',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context, rootNavigator: true)
                .pop(ctrl.text.trim()),
            child: const Text('Importieren'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return null;
    return result;
  }

  List<BankBewegungenCompanion> _parseGenericCsv(
      String content, String konto) {
    final lines = content.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
    if (lines.length < 2) return const [];
    // Trennzeichen erkennen — `;` ist in DE Standard, `,` US-Variante.
    final delim = lines.first.contains(';') ? ';' : ',';
    final headers = lines.first
        .split(delim)
        .map((s) => s.replaceAll('"', '').trim().toLowerCase())
        .toList();
    int idxOf(List<String> options) {
      for (final o in options) {
        final i = headers.indexWhere((h) => h.contains(o));
        if (i >= 0) return i;
      }
      return -1;
    }

    final iDatum = idxOf(['buchungstag', 'datum', 'valuta']);
    final iText = idxOf(['verwendungszweck', 'buchungstext', 'umsatzart']);
    final iName = idxOf(['name', 'auftraggeber', 'beguenstigter', 'gegenpartei']);
    final iBetrag = idxOf(['betrag', 'amount']);
    final iIban = idxOf(['iban', 'kontonummer']);
    if (iDatum < 0 || iBetrag < 0) return const [];

    final out = <BankBewegungenCompanion>[];
    for (var ln = 1; ln < lines.length; ln++) {
      final cols = lines[ln]
          .split(delim)
          .map((s) => s.replaceAll('"', '').trim())
          .toList();
      if (cols.length <= iBetrag) continue;
      final datumStr = iDatum < cols.length ? cols[iDatum] : '';
      final datum = _parseGermanDate(datumStr);
      if (datum == null) continue;
      final betragStr = cols[iBetrag]
          .replaceAll('.', '')
          .replaceAll(',', '.');
      final betrag = double.tryParse(betragStr);
      if (betrag == null) continue;
      out.add(BankBewegungenCompanion(
        konto: Value(konto),
        iban: iIban >= 0 && iIban < cols.length
            ? Value(cols[iIban].isEmpty ? null : cols[iIban])
            : const Value.absent(),
        buchungsdatum: Value(datum),
        verwendungszweck: iText >= 0 && iText < cols.length
            ? Value(cols[iText].isEmpty ? null : cols[iText])
            : const Value.absent(),
        gegenpartei: iName >= 0 && iName < cols.length
            ? Value(cols[iName].isEmpty ? null : cols[iName])
            : const Value.absent(),
        betrag: Value(betrag),
      ));
    }
    return out;
  }

  DateTime? _parseGermanDate(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    // dd.mm.yyyy oder dd.mm.yy
    final m = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{2,4})$').firstMatch(t);
    if (m == null) return null;
    var y = int.parse(m.group(3)!);
    if (y < 100) y += 2000;
    return DateTime(y, int.parse(m.group(2)!), int.parse(m.group(1)!));
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (status) {
      'zugeordnet' => ('Zugeordnet', BadgeColors.greenBg, BadgeColors.greenFg),
      'privat' => ('Privat', BadgeColors.indigoBg, BadgeColors.indigoFg),
      'kein_beleg' =>
        ('Ohne Beleg', BadgeColors.amberBg, BadgeColors.amberFg),
      'ignoriert' =>
        ('Ignoriert', BadgeColors.slateBg, BadgeColors.slateFg),
      _ => ('Offen', BadgeColors.redBg, BadgeColors.redFg),
    };
    return PillBadge(text: label, background: bg, foreground: fg);
  }
}

class _BelegInfo extends ConsumerWidget {
  const _BelegInfo({required this.b});
  final BankBewegungenData b;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (b.rechnungId != null) {
      return Text('Rechnung #${b.rechnungId}',
          style: const TextStyle(fontSize: 11));
    }
    if (b.eingangsrechnungId != null) {
      return Text('Eingangsrechnung #${b.eingangsrechnungId}',
          style: const TextStyle(fontSize: 11));
    }
    if ((b.datevKonto ?? '').isNotEmpty) {
      return Text('DATEV ${b.datevKonto}',
          style: const TextStyle(fontSize: 11));
    }
    if ((b.notiz ?? '').isNotEmpty) {
      return Text(b.notiz!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11));
    }
    return const Text('—',
        style: TextStyle(fontSize: 11, color: Colors.grey));
  }
}

class _BankingEditor extends ConsumerStatefulWidget {
  const _BankingEditor({this.b});
  final BankBewegungenData? b;
  @override
  ConsumerState<_BankingEditor> createState() => _BankingEditorState();
}

class _BankingEditorState extends ConsumerState<_BankingEditor> {
  late final _konto = TextEditingController(text: widget.b?.konto ?? '');
  late final _gegenpartei =
      TextEditingController(text: widget.b?.gegenpartei);
  late final _zweck =
      TextEditingController(text: widget.b?.verwendungszweck);
  late final _betrag = TextEditingController(
      text: widget.b == null
          ? ''
          : NumberFormat.decimalPattern('de_DE').format(widget.b!.betrag));
  late final _notiz = TextEditingController(text: widget.b?.notiz);
  late final _datevKonto = TextEditingController(text: widget.b?.datevKonto);
  late DateTime _datum = widget.b?.buchungsdatum ?? DateTime.now();
  late String _status = widget.b?.status ?? 'offen';
  int? _rechnungId;
  int? _eingangsrechnungId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _rechnungId = widget.b?.rechnungId;
    _eingangsrechnungId = widget.b?.eingangsrechnungId;
  }

  @override
  void dispose() {
    for (final c in [_konto, _gegenpartei, _zweck, _betrag, _notiz, _datevKonto]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final betrag = double.tryParse(
        _betrag.text.replaceAll('.', '').replaceAll(',', '.'));
    if (betrag == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Betrag ist ungültig.')));
      return;
    }
    setState(() => _saving = true);
    final ent = BankBewegungenCompanion(
      id: widget.b == null ? const Value.absent() : Value(widget.b!.id),
      konto: Value(_konto.text.trim()),
      buchungsdatum: Value(_datum),
      gegenpartei: Value(_gegenpartei.text.trim().isEmpty
          ? null
          : _gegenpartei.text.trim()),
      verwendungszweck:
          Value(_zweck.text.trim().isEmpty ? null : _zweck.text.trim()),
      betrag: Value(betrag),
      status: Value(_status),
      rechnungId: Value(_status == 'zugeordnet' ? _rechnungId : null),
      eingangsrechnungId: Value(
          _status == 'zugeordnet' ? _eingangsrechnungId : null),
      datevKonto: Value(_datevKonto.text.trim().isEmpty
          ? null
          : _datevKonto.text.trim()),
      notiz: Value(_notiz.text.trim().isEmpty ? null : _notiz.text.trim()),
    );
    try {
      await ref.read(bankingRepositoryProvider).upsert(ent);
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rechnungenAsync = ref.watch(rechnungenListProvider);
    final eingangsAsync = ref.watch(eingangsrechnungenListProvider);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
            child: Row(children: [
              const Icon(Icons.account_balance_outlined),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(
                widget.b == null
                    ? 'Neue Bankbewegung'
                    : 'Bankbewegung bearbeiten',
                style: Theme.of(context).textTheme.titleMedium,
              )),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () =>
                    Navigator.of(context, rootNavigator: true).pop(),
              ),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _konto,
                      decoration: const InputDecoration(
                          labelText: 'Konto-Bezeichnung *'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                            context: context,
                            initialDate: _datum,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100));
                        if (picked != null) {
                          setState(() => _datum = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                            labelText: 'Buchungsdatum'),
                        child: Text(
                            DateFormat('dd.MM.yyyy', 'de').format(_datum)),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: _gegenpartei,
                  decoration:
                      const InputDecoration(labelText: 'Gegenpartei'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _zweck,
                  maxLines: 2,
                  decoration:
                      const InputDecoration(labelText: 'Verwendungszweck'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _betrag,
                  decoration: const InputDecoration(
                      labelText: 'Betrag (EUR) *',
                      hintText: 'Eingang positiv, Ausgang negativ'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(value: 'offen', child: Text('Offen')),
                    DropdownMenuItem(
                        value: 'zugeordnet', child: Text('Zugeordnet')),
                    DropdownMenuItem(
                        value: 'privat', child: Text('Privat')),
                    DropdownMenuItem(
                        value: 'kein_beleg', child: Text('Ohne Beleg')),
                    DropdownMenuItem(
                        value: 'ignoriert', child: Text('Ignoriert')),
                  ],
                  onChanged: (v) =>
                      setState(() => _status = v ?? _status),
                ),
                if (_status == 'zugeordnet') ...[
                  const SizedBox(height: 12),
                  rechnungenAsync.when(
                    loading: () =>
                        const LinearProgressIndicator(minHeight: 2),
                    error: (e, _) => Text('Fehler: $e'),
                    data: (list) =>
                        DropdownButtonFormField<int?>(
                      initialValue: _rechnungId,
                      decoration: const InputDecoration(
                          labelText: 'Ausgangs-Rechnung'),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('— keine —')),
                        for (final r in list)
                          DropdownMenuItem(
                            value: r.rechnung.id,
                            child: Text(
                              '${r.rechnung.rechnungsnummer ?? '#${r.rechnung.id}'}'
                              ' · ${NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2).format(r.rechnung.brutto)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        setState(() {
                          _rechnungId = v;
                          if (v != null) _eingangsrechnungId = null;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  eingangsAsync.when(
                    loading: () =>
                        const LinearProgressIndicator(minHeight: 2),
                    error: (e, _) => Text('Fehler: $e'),
                    data: (list) =>
                        DropdownButtonFormField<int?>(
                      initialValue: _eingangsrechnungId,
                      decoration: const InputDecoration(
                          labelText: 'Eingangs-Rechnung'),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('— keine —')),
                        for (final r in list)
                          DropdownMenuItem(
                            value: r.rechnung.id,
                            child: Text(
                              '${r.rechnung.rechnungsnummer ?? '#${r.rechnung.id}'}'
                              ' · ${r.rechnung.lieferantName ?? ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        setState(() {
                          _eingangsrechnungId = v;
                          if (v != null) _rechnungId = null;
                        });
                      },
                    ),
                  ),
                ],
                if (_status == 'kein_beleg' || _status == 'privat') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _datevKonto,
                    decoration: const InputDecoration(
                        labelText: 'DATEV-Konto',
                        hintText:
                            'z. B. 1880 (Privatentnahme), 4970 (Bankgebühren)'),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _notiz,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Notiz'),
                ),
              ]),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(children: [
              const Spacer(),
              TextButton(
                onPressed: _saving
                    ? null
                    : () => Navigator.of(context, rootNavigator: true).pop(),
                child: const Text('Abbrechen'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: _saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child:
                            CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check, size: 16),
                label: const Text('Speichern'),
                onPressed: _saving ? null : _save,
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
