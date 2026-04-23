import 'dart:convert';

import 'package:drift/drift.dart' show Value, OrderingTerm, OrderingMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart' show Uint8List;

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../../features/akten/kunden/kunden_repository.dart';
import '../../../features/angebote/anschreiben/anschreiben_repository.dart';
import '../../../features/system/einstellungen/absender_service.dart';
import '../../../shared/richtext/quill_editor.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';
import 'serienbrief_pdf.dart';

/// Serienbrief-Modul: Brief in Rich-Text verfassen, Empfänger aus der
/// Kundenliste auswählen, beim Absenden für jeden Empfänger ein
/// Anschreiben-Objekt in dessen aktueller Akte anlegen.
class SerienbriefScreen extends ConsumerStatefulWidget {
  const SerienbriefScreen({super.key});
  @override
  ConsumerState<SerienbriefScreen> createState() =>
      _SerienbriefScreenState();
}

class _SerienbriefScreenState extends ConsumerState<SerienbriefScreen> {
  final _betreff = TextEditingController(text: 'Information');
  final _anrede = TextEditingController(text: 'Sehr geehrte {{anrede}} {{name}},');
  final _gruss = TextEditingController(text: 'Mit freundlichen Grüßen');
  String? _brieftextJson;
  DateTime _datum = DateTime.now();
  final Set<int> _selected = {};
  String _filterTyp = 'alle';
  final _query = TextEditingController();
  bool _saving = false;
  /// 'brief' = Briefversand (PDF drucken), 'mail' = E-Mail-Entwurf.
  String _versandart = 'brief';

  @override
  void dispose() {
    _betreff.dispose();
    _anrede.dispose();
    _gruss.dispose();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(kundenListProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.mail_outline,
          title: 'Serienbriefe',
          subtitle:
              'Rundschreiben an mehrere Auftraggeber — pro Empfänger ein Anschreiben-Objekt',
          actions: [
            OutlinedButton.icon(
              icon: const Icon(Icons.history, size: 16),
              label: const Text('Historie'),
              onPressed: () => _zeigeHistorie(async.valueOrNull ?? const []),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('CSV-Export'),
              onPressed: () => _exportCsv(async.valueOrNull ?? const []),
            ),
            FilledButton.icon(
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
              label: Text(_saving
                  ? 'Anlegen…'
                  : 'Versenden (${_selected.length})'),
              onPressed: _selected.isEmpty || _saving
                  ? null
                  : () => _versenden(async.valueOrNull ?? const []),
            ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 380,
                child: _EmpfaengerListe(
                  selected: _selected,
                  filterTyp: _filterTyp,
                  queryCtrl: _query,
                  onFilterTyp: (v) => setState(() => _filterTyp = v),
                  onQueryChanged: () => setState(() {}),
                  async: async,
                  onSelectChanged: (id, v) => setState(() {
                    if (v) {
                      _selected.add(id);
                    } else {
                      _selected.remove(id);
                    }
                  }),
                  onSelectAll: (list) {
                    setState(() {
                      if (list.every((k) => _selected.contains(k.id))) {
                        for (final k in list) {
                          _selected.remove(k.id);
                        }
                      } else {
                        for (final k in list) {
                          _selected.add(k.id);
                        }
                      }
                    });
                  },
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: Container(
                  color: const Color(0xFFF5F5F4),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 820),
                        child: Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: const BorderSide(
                                color: Color(0xFFE5E7EB)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row2(
                                  left: LabeledField(
                                    'Datum',
                                    InkWell(
                                      onTap: () async {
                                        final d = await showDatePicker(
                                          context: context,
                                          initialDate: _datum,
                                          firstDate: DateTime(2020),
                                          lastDate: DateTime(2100),
                                        );
                                        if (d != null) {
                                          setState(() => _datum = d);
                                        }
                                      },
                                      child: InputDecorator(
                                        decoration: const InputDecoration(
                                          suffixIcon: Icon(Icons
                                              .calendar_month_outlined),
                                        ),
                                        child: Text(DateFormat(
                                                'dd.MM.yyyy', 'de')
                                            .format(_datum)),
                                      ),
                                    ),
                                  ),
                                  right: LabeledField(
                                    'Betreff',
                                    TextFormField(controller: _betreff),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                LabeledField(
                                  'Versandart',
                                  SegmentedButton<String>(
                                    segments: const [
                                      ButtonSegment(
                                          value: 'brief',
                                          icon: Icon(Icons.print_outlined,
                                              size: 16),
                                          label: Text('Brief (PDF drucken)')),
                                      ButtonSegment(
                                          value: 'mail',
                                          icon: Icon(Icons.mail_outline,
                                              size: 16),
                                          label: Text('E-Mail')),
                                    ],
                                    selected: {_versandart},
                                    showSelectedIcon: false,
                                    onSelectionChanged: (s) =>
                                        setState(() => _versandart = s.first),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                LabeledField(
                                  'Anrede-Formel (Platzhalter: {{anrede}}, {{name}}, {{vorname}}, {{firma}})',
                                  TextFormField(controller: _anrede),
                                ),
                                const SizedBox(height: 12),
                                Text('Brieftext',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall),
                                const SizedBox(height: 6),
                                SizedBox(
                                  height: 360,
                                  child: RichTextEditor(
                                    initialDeltaJson: _brieftextJson,
                                    onChanged: (json) =>
                                        _brieftextJson = json,
                                    placeholder:
                                        'Brieftext – wird für jeden Empfänger mit der Anrede personalisiert …',
                                  ),
                                ),
                                const SizedBox(height: 12),
                                LabeledField(
                                  'Grußformel',
                                  TextFormField(
                                      controller: _gruss,
                                      minLines: 2,
                                      maxLines: 4),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _versenden(List<KundenData> all) async {
    setState(() => _saving = true);
    final selected =
        all.where((k) => _selected.contains(k.id)).toList();
    var angelegt = 0;
    final db = ref.read(appDatabaseProvider);
    final plainBrief = plainTextFromDeltaJson(_brieftextJson);

    // Ein Serienbrief-Historie-Eintrag (Batch) für Wiedervorlage.
    await db.into(db.serienbriefe).insert(
          SerienbriefeCompanion.insert(
            datum: Value(_datum),
            betreff: Value(_betreff.text.trim().isEmpty
                ? null
                : _betreff.text.trim()),
            anrede: Value(_anrede.text.trim().isEmpty
                ? null
                : _anrede.text.trim()),
            gruss: Value(_gruss.text.trim().isEmpty
                ? null
                : _gruss.text.trim()),
            inhaltJson: Value(_brieftextJson),
            versandart: Value(_versandart),
            empfaengerIdsJson: Value(
                jsonEncode(selected.map((k) => k.id).toList())),
            anzahl: Value(selected.length),
          ),
        );

    // Pro Empfänger Anschreiben-Objekt anlegen.
    final eintraege = <SerienEintrag>[];
    for (final k in selected) {
      final akte = await (db.select(db.auftraege)
            ..where((t) => t.kundeId.equals(k.id))
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.createdAt, mode: OrderingMode.desc)
            ])
            ..limit(1))
          .getSingleOrNull();
      final anrede = _ersetzeAnrede(_anrede.text, k);
      final brieftext = _ersetzeAnrede(plainBrief, k);
      final status = _versandart == 'mail' ? 'versendet' : 'gedruckt';
      await ref.read(anschreibenRepositoryProvider).upsert(
            AnschreibenCompanion.insert(
              kundeId: Value(k.id),
              auftragId: Value(akte?.id),
              datum: Value(_datum),
              betreff: Value(_betreff.text.trim()),
              anrede: Value(anrede),
              gruss: Value(_gruss.text.trim()),
              briefText: Value(brieftext),
              inhaltJson: Value(_brieftextJson),
              status: Value(status),
            ),
          );
      angelegt++;
      eintraege.add(SerienEintrag(kunde: k, anrede: anrede, brieftext: brieftext));
    }

    if (!mounted) {
      setState(() => _saving = false);
      return;
    }
    setState(() => _saving = false);

    if (_versandart == 'mail') {
      await _oeffneMails(eintraege);
    } else {
      await _drucke(eintraege);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_versandart == 'mail'
                ? '$angelegt E-Mail-Entwürfe vorbereitet.'
                : '$angelegt Briefe als PDF erzeugt & abgelegt.')),
      );
    }
  }

  Future<void> _oeffneMails(List<SerienEintrag> list) async {
    for (final e in list) {
      final email = (e.kunde.email ?? '').trim();
      if (email.isEmpty) continue;
      final body = '${e.anrede}\n\n${e.brieftext}\n\n${_gruss.text.trim()}';
      final uri = Uri(
        scheme: 'mailto',
        path: email,
        queryParameters: {
          'subject': _betreff.text.trim(),
          'body': body,
        },
      );
      await launchUrl(uri);
    }
  }

  Future<void> _drucke(List<SerienEintrag> list) async {
    final absender = await absenderFromSettings(ref);
    final pdfBytes = await buildSerienbriefPdf(
      eintraege: list,
      absender: absender,
      betreff: _betreff.text.trim(),
      gruss: _gruss.text.trim(),
      datum: _datum,
    );
    await Printing.layoutPdf(
      onLayout: (_) async => pdfBytes,
      name:
          'serienbrief_${DateFormat("yyyyMMdd").format(_datum)}.pdf',
    );
  }

  String _ersetzeAnrede(String template, KundenData k) {
    final anrede = (k.anrede ?? '').isNotEmpty
        ? k.anrede!
        : (k.typ == 'gericht' ? 'Sehr geehrte Damen und Herren' : 'Herr/Frau');
    final name = (k.nachname ?? '').isNotEmpty
        ? k.nachname!
        : (k.firma ?? '');
    return template
        .replaceAll('{{anrede}}', anrede)
        .replaceAll('{{name}}', name)
        .replaceAll('{{vorname}}', k.vorname ?? '')
        .replaceAll('{{firma}}', k.firma ?? '');
  }

  /// Öffnet den Historie-Dialog. Ein Klick auf einen Eintrag lädt die
  /// Einstellungen (Betreff/Anrede/Gruß/Brieftext/Versandart) und die
  /// Empfänger-Auswahl zurück ins Formular, so dass der Serienbrief
  /// kopiert und erneut versendet werden kann.
  Future<void> _zeigeHistorie(List<KundenData> alle) async {
    final db = ref.read(appDatabaseProvider);
    final list = await (db.select(db.serienbriefe)
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.datum, mode: OrderingMode.desc),
          ]))
        .get();
    if (!mounted) return;
    final picked = await showDialog<SerienbriefeData>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _HistorieDialog(eintraege: list),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _betreff.text = picked.betreff ?? '';
      _anrede.text = picked.anrede ?? '';
      _gruss.text = picked.gruss ?? '';
      _brieftextJson = picked.inhaltJson;
      _versandart = picked.versandart;
      _datum = DateTime.now();
      _selected.clear();
      try {
        final ids = (jsonDecode(picked.empfaengerIdsJson ?? '[]') as List)
            .whereType<num>()
            .map((n) => n.toInt())
            .toSet();
        // Nur Empfänger markieren, die es noch gibt.
        for (final id in ids) {
          if (alle.any((k) => k.id == id)) _selected.add(id);
        }
      } catch (_) {}
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Serienbrief „${picked.betreff ?? ''}" geladen — ${_selected.length} Empfänger wieder ausgewählt.')),
      );
    }
  }

  Future<void> _exportCsv(List<KundenData> all) async {
    final selected = all.where((k) => _selected.contains(k.id)).toList();
    final target = selected.isEmpty ? all : selected;
    final rows = <List<String>>[
      ['Anrede', 'Titel', 'Vorname', 'Nachname', 'Firma', 'Straße', 'PLZ', 'Ort', 'E-Mail', 'Debitor-Nr.'],
      for (final k in target)
        [
          k.anrede ?? '',
          k.titel ?? '',
          k.vorname ?? '',
          k.nachname ?? '',
          k.firma ?? '',
          k.strasse ?? '',
          k.plz ?? '',
          k.ort ?? '',
          k.email ?? '',
          k.debitornummer ?? '',
        ],
    ];
    final csv = rows
        .map((r) =>
            r.map((c) => '"${c.replaceAll('"', '""')}"').join(';'))
        .join('\r\n');
    await Share.shareXFiles(
      [
        XFile.fromData(
          Uint8List.fromList(utf8.encode(csv)),
          name: 'serienbrief_empfaenger.csv',
          mimeType: 'text/csv',
        ),
      ],
      subject: 'Serienbrief-Empfängerliste',
    );
  }
}

class _HistorieDialog extends StatelessWidget {
  const _HistorieDialog({required this.eintraege});
  final List<SerienbriefeData> eintraege;

  static final _fmt = DateFormat('dd.MM.yyyy', 'de');

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 600),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 10),
              child: Row(
                children: [
                  const Icon(Icons.history),
                  const SizedBox(width: 10),
                  Text('Serienbrief-Historie',
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: true).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: eintraege.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                            'Noch keine Serienbriefe versendet. Sobald du einen Batch verschickst, erscheint er hier.'),
                      ),
                    )
                  : ListView.separated(
                      itemCount: eintraege.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final e = eintraege[i];
                        return ListTile(
                          title: Text(
                              e.betreff?.trim().isNotEmpty == true
                                  ? e.betreff!
                                  : '(ohne Betreff)',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            '${_fmt.format(e.datum)} · ${e.versandart == 'mail' ? 'E-Mail' : 'Brief'} · ${e.anzahl} Empfänger',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: FilledButton.tonalIcon(
                            icon: const Icon(
                                Icons.content_copy, size: 14),
                            label: const Text('Kopieren'),
                            onPressed: () => Navigator.of(context,
                                    rootNavigator: true)
                                .pop(e),
                          ),
                          onTap: () => Navigator.of(context,
                                  rootNavigator: true)
                              .pop(e),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmpfaengerListe extends ConsumerWidget {
  const _EmpfaengerListe({
    required this.selected,
    required this.filterTyp,
    required this.queryCtrl,
    required this.onFilterTyp,
    required this.onQueryChanged,
    required this.async,
    required this.onSelectChanged,
    required this.onSelectAll,
  });
  final Set<int> selected;
  final String filterTyp;
  final TextEditingController queryCtrl;
  final ValueChanged<String> onFilterTyp;
  final VoidCallback onQueryChanged;
  final AsyncValue<List<KundenData>> async;
  final void Function(int id, bool selected) onSelectChanged;
  final void Function(List<KundenData> list) onSelectAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              TextField(
                controller: queryCtrl,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18),
                  hintText: 'Suchen …',
                ),
                onChanged: (_) => onQueryChanged(),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: filterTyp,
                isDense: true,
                items: const [
                  DropdownMenuItem(value: 'alle', child: Text('Alle Typen')),
                  DropdownMenuItem(value: 'privat', child: Text('Privat')),
                  DropdownMenuItem(value: 'firma', child: Text('Firma')),
                  DropdownMenuItem(value: 'anwalt', child: Text('Anwalt')),
                  DropdownMenuItem(value: 'gericht', child: Text('Gericht')),
                  DropdownMenuItem(value: 'versicherung', child: Text('Versicherung')),
                  DropdownMenuItem(value: 'behoerde', child: Text('Behörde')),
                ],
                onChanged: (v) => onFilterTyp(v ?? 'alle'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Fehler: $e')),
            data: (all) {
              final q = queryCtrl.text.trim().toLowerCase();
              final filtered = all.where((k) {
                if (filterTyp != 'alle' && k.typ != filterTyp) return false;
                if (q.isEmpty) return true;
                final s = [
                  k.firma ?? '',
                  k.nachname ?? '',
                  k.vorname ?? '',
                  k.ort ?? '',
                ].join(' ').toLowerCase();
                return s.contains(q);
              }).toList();
              final allSelected = filtered.isNotEmpty &&
                  filtered.every((k) => selected.contains(k.id));
              return Column(
                children: [
                  CheckboxListTile(
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: allSelected,
                    onChanged: (_) => onSelectAll(filtered),
                    title: Text('Alle auswählen (${filtered.length})'),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final k = filtered[i];
                        final isSel = selected.contains(k.id);
                        return CheckboxListTile(
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: isSel,
                          onChanged: (v) =>
                              onSelectChanged(k.id, v ?? false),
                          title: Text(kundeAnzeigename(k)),
                          subtitle: Text(
                            [k.plz, k.ort]
                                .whereType<String>()
                                .where((s) => s.isNotEmpty)
                                .join(' '),
                            style: const TextStyle(fontSize: 11),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
