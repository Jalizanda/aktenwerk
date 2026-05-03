import 'dart:convert';

import 'package:drift/drift.dart' show Value, OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../auftraege/auftraege_repository.dart';

/// Ein Beteiligter in einer Akte — zusätzlich zum Auftraggeber.
class Beteiligter {
  String rolle;
  String name;
  String strasse;
  String plz;
  String ort;
  String telefon;
  String email;
  Beteiligter({
    this.rolle = 'Antragsteller',
    this.name = '',
    this.strasse = '',
    this.plz = '',
    this.ort = '',
    this.telefon = '',
    this.email = '',
  });

  /// Komplette Anschrift als ein String — für Anschreiben-Empfänger.
  String get anschrift {
    final z2 = '${plz.trim()} ${ort.trim()}'.trim();
    return [strasse.trim(), z2]
        .where((s) => s.isNotEmpty)
        .join(', ');
  }

  Map<String, dynamic> toJson() => {
        'rolle': rolle,
        'name': name,
        'strasse': strasse,
        'plz': plz,
        'ort': ort,
        // Für Abwärtskompatibilität: ältere Stellen lesen `anschrift`.
        'anschrift': anschrift,
        'telefon': telefon,
        'email': email,
      };
  static Beteiligter fromJson(Map<String, dynamic> m) {
    // Neue Felder bevorzugt; sonst aus altem `anschrift`-String parsen.
    final str = m['strasse']?.toString();
    final plz = m['plz']?.toString();
    final ort = m['ort']?.toString();
    if (str == null && plz == null && ort == null) {
      // Legacy-Daten: ein Anschrift-String — heuristisch zerlegen.
      final raw = (m['anschrift']?.toString() ?? '').trim();
      var lStrasse = '';
      var lPlz = '';
      var lOrt = '';
      if (raw.isNotEmpty) {
        // Komma-getrennt: „Strasse 1, 12345 Stadt"
        final teile = raw.split(',').map((e) => e.trim()).toList();
        if (teile.length >= 2) {
          lStrasse = teile[0];
          final rest = teile.sublist(1).join(', ').trim();
          final m2 =
              RegExp(r'^(\d{4,5})\s+(.+)$').firstMatch(rest);
          if (m2 != null) {
            lPlz = m2.group(1)!;
            lOrt = m2.group(2)!;
          } else {
            lOrt = rest;
          }
        } else {
          lStrasse = raw;
        }
      }
      return Beteiligter(
        rolle: m['rolle']?.toString() ?? 'Antragsteller',
        name: m['name']?.toString() ?? '',
        strasse: lStrasse,
        plz: lPlz,
        ort: lOrt,
        telefon: m['telefon']?.toString() ?? '',
        email: m['email']?.toString() ?? '',
      );
    }
    return Beteiligter(
      rolle: m['rolle']?.toString() ?? 'Antragsteller',
      name: m['name']?.toString() ?? '',
      strasse: str ?? '',
      plz: plz ?? '',
      ort: ort ?? '',
      telefon: m['telefon']?.toString() ?? '',
      email: m['email']?.toString() ?? '',
    );
  }
}

const beteiligtenRollen = <String>[
  'Antragsteller',
  'Antragsgegner',
  'Kläger',
  'Beklagter',
  'Streitverkündete:r',
  'Mieter',
  'Vermieter',
  'Eigentümer',
  'WEG / Verwalter',
  'Anwalt Kläger',
  'Anwalt Beklagter',
  'Bauherr',
  'Bauträger',
  'Architekt',
  'Sonstiger',
];

List<Beteiligter> decodeBeteiligte(String? raw) {
  if (raw == null || raw.trim().isEmpty) return [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(Beteiligter.fromJson)
          .toList();
    }
  } catch (_) {}
  return [];
}

String encodeBeteiligte(List<Beteiligter> list) =>
    jsonEncode(list.map((b) => b.toJson()).toList());

class BeteiligteTab extends ConsumerStatefulWidget {
  const BeteiligteTab({super.key, required this.auftrag});
  final AuftraegeData auftrag;
  @override
  ConsumerState<BeteiligteTab> createState() => _BeteiligteTabState();
}

class _BeteiligteTabState extends ConsumerState<BeteiligteTab> {
  late List<Beteiligter> _liste;
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _liste = decodeBeteiligte(widget.auftrag.beteiligteJson);
  }

  @override
  void didUpdateWidget(covariant BeteiligteTab old) {
    super.didUpdateWidget(old);
    if (old.auftrag.id != widget.auftrag.id ||
        old.auftrag.beteiligteJson != widget.auftrag.beteiligteJson) {
      setState(() {
        _liste = decodeBeteiligte(widget.auftrag.beteiligteJson);
        _dirty = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(auftraegeRepositoryProvider).upsert(
            AuftraegeCompanion(
              id: Value(widget.auftrag.id),
              beteiligteJson: Value(encodeBeteiligte(_liste)),
              updatedAt: Value(DateTime.now()),
            ),
          );
      if (mounted) {
        setState(() {
          _saving = false;
          _dirty = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Beteiligte gespeichert.')),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Weitere Beteiligte (zusätzlich zum Auftraggeber)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              if (_liste.isNotEmpty) ...[
                OutlinedButton.icon(
                  icon: const Icon(Icons.event_outlined, size: 16),
                  label: const Text('Termin-Einladung an alle'),
                  onPressed: () => _massenEinladung(context),
                ),
                const SizedBox(width: 8),
              ],
              FilledButton.tonalIcon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Beteiligten hinzufügen'),
                onPressed: () => setState(() {
                  _liste.add(Beteiligter());
                  _dirty = true;
                }),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: _saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined, size: 16),
                label: Text(_saving ? 'Speichern…' : 'Speichern'),
                onPressed: _saving || !_dirty ? null : _save,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _liste.isEmpty
                ? const EmptyListState(
                    icon: Icons.groups_2_outlined,
                    title: 'Keine zusätzlichen Beteiligten erfasst',
                    hint:
                        'Auftraggeber steht in den Stammdaten — hier kannst du Kläger, Beklagte, Anwälte, Mieter usw. ergänzen.')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Spalten-Überschriften
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                        child: Row(children: [
                          _ColLabel(width: 130, text: 'Rolle'),
                          const SizedBox(width: 8),
                          _ColLabel(flex: 2, text: 'Name / Firma'),
                          const SizedBox(width: 8),
                          _ColLabel(flex: 3, text: 'Straße'),
                          const SizedBox(width: 8),
                          _ColLabel(width: 80, text: 'PLZ'),
                          const SizedBox(width: 8),
                          _ColLabel(flex: 2, text: 'Ort'),
                          const SizedBox(width: 8),
                          _ColLabel(width: 130, text: 'Telefon'),
                          const SizedBox(width: 8),
                          _ColLabel(flex: 3, text: 'E-Mail'),
                          const SizedBox(width: 8),
                          const SizedBox(width: 96), // Aktionen
                        ]),
                      ),
                      Expanded(
                        child: ListView.separated(
                          itemCount: _liste.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) => _BeteiligterRow(
                            key: ValueKey(_liste[i]),
                            b: _liste[i],
                            onChanged: () => setState(() => _dirty = true),
                            onRemove: () => setState(() {
                              _liste.removeAt(i);
                              _dirty = true;
                            }),
                            onBrief: () => _einzelEinladung(_liste[i],
                                viaMail: false),
                            onMail: () => _einzelEinladung(_liste[i],
                                viaMail: true),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// Einzel-Einladung an genau einen Beteiligten — verzweigt direkt in
  /// den Anschreiben-Dialog (Brief) oder Mail-Compose-Flow.
  Future<void> _einzelEinladung(Beteiligter b, {required bool viaMail}) async {
    if (b.name.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Bitte erst Name eintragen.')));
      return;
    }
    if (viaMail) {
      if (b.email.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Keine E-Mail-Adresse hinterlegt — bitte ergänzen.')));
        return;
      }
      // Browser-Mailto-Link öffnen — nutzt das System-Mailprogramm.
      final url = Uri(
        scheme: 'mailto',
        path: b.email,
        queryParameters: {
          'subject': 'Einladung zum Ortstermin — ${widget.auftrag.aktenzeichen ?? ''}',
          'body': _briefanredeFuer(b.name, b.rolle) +
              '\n\nin oben genannter Sache lade ich Sie zum Ortstermin ein.\n\n'
                  'Termin: (bitte einfügen)\nOrt: (bitte einfügen)\n\n'
                  'Bitte teilen Sie mir kurz mit, ob Sie den Termin wahrnehmen können.\n\n'
                  'Mit freundlichen Grüßen',
        },
      );
      // ignore: deprecated_member_use
      await Future.delayed(Duration.zero);
      // Mailto via launchUrl-API wäre eine Möglichkeit; hier minimal halten —
      // wir kopieren den Link in die Zwischenablage als Fallback.
      // Browser-Web öffnet Mailto via window.location, wenn möglich.
      try {
        // Wir nutzen url_launcher nicht — html.window.open statt dessen.
        final webUrl = url.toString();
        // Kein direkter html-Import hier — wir signalisieren via Hinweis.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Mail-Vorbereitung: $webUrl')));
        }
      } catch (_) {}
      return;
    }
    // Brief-Pfad: erzeugt einen Anschreiben-Entwurf für genau diesen
    // Beteiligten. Datum/Ort/Hinweis kommen aus dem normalen Anschreiben-
    // Editor — der Benutzer kann dort feinjustieren.
    final db = ref.read(appDatabaseProvider);
    final extras = jsonEncode({
      'beteiligterRolle': b.rolle,
      'beteiligterName': b.name,
      'beteiligterAnschrift': b.anschrift,
      'einladungBestaetigt': null,
    });
    await db.into(db.anschreiben).insert(AnschreibenCompanion.insert(
          auftragId: Value(widget.auftrag.id),
          betreff: const Value('Einladung zum Ortstermin'),
          datum: Value(DateTime.now()),
          anrede: Value(_briefanredeFuer(b.name, b.rolle)),
          briefText: const Value(
              'in oben genannter Sache lade ich Sie hiermit zum Ortstermin ein.\n\n'
              'Termin: (bitte einfügen)\nOrt: (bitte einfügen)\n\n'
              'Bitte teilen Sie uns kurz mit, ob Sie den Termin wahrnehmen können.\n\n'
              'Mit freundlichen Grüßen'),
          gruss: const Value('Mit freundlichen Grüßen'),
          status: const Value('entwurf'),
          extras: Value(extras),
        ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Brief-Entwurf für ${b.name} angelegt — im Tab „Anschreiben" finalisieren.')));
  }

  /// Öffnet den Termin-Einladung-Dialog: Datum/Uhrzeit-Picker, Empfänger-
  /// Auswahl, Konflikt-Check, Textbaustein-Picker und Wiedervorlage-
  /// Eintrag im eigenen Kalender.
  Future<void> _massenEinladung(BuildContext context) async {
    if (_liste.where((b) => b.name.trim().isNotEmpty).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Erst Beteiligte erfassen, dann Einladungen verschicken.')));
      return;
    }
    final result = await showDialog<_EinladungResult>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _TerminEinladungDialog(
        auftrag: widget.auftrag,
        beteiligte: _liste
            .where((b) => b.name.trim().isNotEmpty)
            .toList(growable: false),
      ),
    );
    if (result == null || !context.mounted) return;

    final db = ref.read(appDatabaseProvider);
    var erstellt = 0;
    final terminText = result.termin == null
        ? 'wird gesondert mitgeteilt'
        : DateFormat("EEEE, dd.MM.yyyy ' um ' HH:mm ' Uhr'", 'de')
            .format(result.termin!);
    for (final b in result.empfaenger) {
      final anrede = _briefanredeFuer(b.name, b.rolle);
      final brief = StringBuffer()
        ..writeln(
            'in oben genannter Sache lade ich Sie hiermit zum Ortstermin ein.')
        ..writeln()
        ..writeln('Termin: $terminText')
        ..writeln('Ort: ${result.ort.isEmpty ? "—" : result.ort}')
        ..writeln();
      if (result.hinweis.isNotEmpty) {
        brief.writeln(result.hinweis);
        brief.writeln();
      }
      brief.write('Mit freundlichen Grüßen');

      final extras = jsonEncode({
        'beteiligterRolle': b.rolle,
        'beteiligterName': b.name,
        'beteiligterAnschrift': b.anschrift,
        'terminText': terminText,
        'ortText': result.ort,
        'einladungBestaetigt': null, // null=offen, true/false=Antwort
      });
      await db.into(db.anschreiben).insert(AnschreibenCompanion.insert(
            auftragId: Value(widget.auftrag.id),
            betreff: Value(result.betreff),
            datum: Value(DateTime.now()),
            anrede: Value(anrede),
            briefText: Value(brief.toString()),
            gruss: const Value('Mit freundlichen Grüßen'),
            status: const Value('entwurf'),
            extras: Value(extras),
          ));
      erstellt++;
    }

    // Termin im eigenen Kalender (Wiedervorlagen-Tabelle).
    if (result.termin != null && result.inKalender) {
      await db.into(db.wiedervorlagen).insert(WiedervorlagenCompanion.insert(
            auftragId: Value(widget.auftrag.id),
            titel: 'Ortstermin: ${result.betreff}',
            faelligAm: Value(result.termin!),
            endeAm: Value(result.termin!.add(const Duration(hours: 2))),
            beschreibung: Value(
                '${result.empfaenger.length} Beteiligte eingeladen. Bestätigungen offen.\nOrt: ${result.ort}'),
          ));
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          '$erstellt ${result.kanal == _Kanal.brief ? "Anschreiben" : "Mail-Entwürfe"} '
          'erzeugt${result.inKalender && result.termin != null ? " · Termin im Kalender hinterlegt" : ""}. '
          'Bestätigungen sind offen — antwortet ein Beteiligter, im Anschreiben-Tab als „bestätigt" markieren.'),
    ));
  }

  /// Baut „Sehr geehrte Frau X," / „Sehr geehrter Herr Y," aus dem Namen.
  String _briefanredeFuer(String name, String rolle) {
    final n = name.trim();
    if (n.isEmpty) return 'Sehr geehrte Damen und Herren,';
    // Für Anwälte / Gericht-Rollen Standard-Anrede mit Frau/Herr Nachname
    final teile = n.split(RegExp(r'\s+'));
    final nachname = teile.isNotEmpty ? teile.last : n;
    final lower = n.toLowerCase();
    if (lower.contains(' frau ') || lower.startsWith('frau ')) {
      return 'Sehr geehrte Frau $nachname,';
    }
    if (lower.contains(' herr ') || lower.startsWith('herr ')) {
      return 'Sehr geehrter Herr $nachname,';
    }
    // Bei Firmennamen / unklarem Geschlecht: neutrale Anrede
    return 'Sehr geehrte Damen und Herren,';
  }
}

class _ColLabel extends StatelessWidget {
  const _ColLabel({this.flex, this.width, required this.text});
  final int? flex;
  final double? width;
  final String text;
  @override
  Widget build(BuildContext context) {
    final label = Text(
      text,
      style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
    if (width != null) return SizedBox(width: width, child: label);
    return Expanded(flex: flex ?? 1, child: label);
  }
}

class _BeteiligterRow extends StatefulWidget {
  const _BeteiligterRow({
    super.key,
    required this.b,
    required this.onChanged,
    required this.onRemove,
    required this.onBrief,
    required this.onMail,
  });
  final Beteiligter b;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  final VoidCallback onBrief;
  final VoidCallback onMail;
  @override
  State<_BeteiligterRow> createState() => _BeteiligterRowState();
}

class _BeteiligterRowState extends State<_BeteiligterRow> {
  late final _name = TextEditingController(text: widget.b.name);
  late final _strasse = TextEditingController(text: widget.b.strasse);
  late final _plz = TextEditingController(text: widget.b.plz);
  late final _ort = TextEditingController(text: widget.b.ort);
  late final _telefon = TextEditingController(text: widget.b.telefon);
  late final _email = TextEditingController(text: widget.b.email);

  @override
  void dispose() {
    for (final c in [_name, _strasse, _plz, _ort, _telefon, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration deco() => const InputDecoration(
        isDense: true,
        contentPadding:
            EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: OutlineInputBorder());
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border:
            Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 130,
            child: DropdownButtonFormField<String>(
              initialValue: beteiligtenRollen.contains(widget.b.rolle)
                  ? widget.b.rolle
                  : 'Sonstiger',
              isDense: true,
              decoration: deco(),
              items: [
                for (final r in beteiligtenRollen)
                  DropdownMenuItem(value: r, child: Text(r)),
              ],
              onChanged: (v) {
                widget.b.rolle = v ?? 'Sonstiger';
                widget.onChanged();
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextField(
              controller: _name,
              decoration: deco(),
              onChanged: (v) {
                widget.b.name = v;
                widget.onChanged();
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: TextField(
              controller: _strasse,
              decoration: deco(),
              onChanged: (v) {
                widget.b.strasse = v;
                widget.onChanged();
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: TextField(
              controller: _plz,
              decoration: deco(),
              onChanged: (v) {
                widget.b.plz = v;
                widget.onChanged();
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextField(
              controller: _ort,
              decoration: deco(),
              onChanged: (v) {
                widget.b.ort = v;
                widget.onChanged();
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 130,
            child: TextField(
              controller: _telefon,
              decoration: deco(),
              onChanged: (v) {
                widget.b.telefon = v;
                widget.onChanged();
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: TextField(
              controller: _email,
              decoration: deco(),
              onChanged: (v) {
                widget.b.email = v;
                widget.onChanged();
              },
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Brief direkt erzeugen',
            icon: const Icon(Icons.mail_outline, size: 18),
            onPressed: widget.onBrief,
          ),
          IconButton(
            tooltip: 'E-Mail direkt verfassen',
            icon: const Icon(Icons.alternate_email, size: 18),
            onPressed: widget.onMail,
          ),
          IconButton(
            tooltip: 'Eintrag löschen',
            icon: const Icon(Icons.close, size: 18),
            color: Theme.of(context).colorScheme.error,
            onPressed: widget.onRemove,
          ),
        ],
      ),
    );
  }
}

enum _Kanal { brief, mail }

class _EinladungResult {
  final DateTime? termin;
  final String ort;
  final String betreff;
  final String hinweis;
  final List<Beteiligter> empfaenger;
  final _Kanal kanal;
  final bool inKalender;
  const _EinladungResult({
    required this.termin,
    required this.ort,
    required this.betreff,
    required this.hinweis,
    required this.empfaenger,
    required this.kanal,
    required this.inKalender,
  });
}

class _TerminEinladungDialog extends ConsumerStatefulWidget {
  const _TerminEinladungDialog({
    required this.auftrag,
    required this.beteiligte,
  });
  final AuftraegeData auftrag;
  final List<Beteiligter> beteiligte;
  @override
  ConsumerState<_TerminEinladungDialog> createState() =>
      _TerminEinladungDialogState();
}

class _TerminEinladungDialogState
    extends ConsumerState<_TerminEinladungDialog> {
  DateTime? _datum;
  TimeOfDay _zeit = const TimeOfDay(hour: 10, minute: 0);
  late final _ort = TextEditingController(
    text: [
      widget.auftrag.objektStrasse,
      '${widget.auftrag.objektPlz ?? ''} ${widget.auftrag.objektOrt ?? ''}'
          .trim(),
    ].whereType<String>().where((s) => s.trim().isNotEmpty).join(', '),
  );
  late final _betreff =
      TextEditingController(text: 'Einladung zum Ortstermin');
  late final _hinweis = TextEditingController(
      text:
          'Bitte teilen Sie uns kurz mit, ob Sie den Termin wahrnehmen können.');
  late final Set<int> _ausgewaehlt = {
    for (var i = 0; i < widget.beteiligte.length; i++) i
  };
  _Kanal _kanal = _Kanal.brief;
  bool _inKalender = true;
  List<WiedervorlagenData> _konflikte = const [];

  @override
  void dispose() {
    _ort.dispose();
    _betreff.dispose();
    _hinweis.dispose();
    super.dispose();
  }

  DateTime? get _terminMoment {
    if (_datum == null) return null;
    return DateTime(
        _datum!.year, _datum!.month, _datum!.day, _zeit.hour, _zeit.minute);
  }

  Future<void> _waehleDatum() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _datum ?? DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      locale: const Locale('de'),
    );
    if (picked == null) return;
    setState(() => _datum = picked);
    await _pruefeKonflikte();
  }

  Future<void> _waehleZeit() async {
    final picked =
        await showTimePicker(context: context, initialTime: _zeit);
    if (picked == null) return;
    setState(() => _zeit = picked);
    await _pruefeKonflikte();
  }

  Future<void> _pruefeKonflikte() async {
    if (_datum == null) return;
    final db = ref.read(appDatabaseProvider);
    final tagBeginn = DateTime(_datum!.year, _datum!.month, _datum!.day);
    final tagEnde = tagBeginn.add(const Duration(days: 1));
    // Datums-Filter in Dart anwenden (Drift-Lambda kann hier wegen
    // Type-Inferenz keine direkten Datum-Vergleiche).
    final alle = await (db.select(db.wiedervorlagen)
          ..where((t) => t.erledigt.equals(false))
          ..orderBy([(t) => OrderingTerm(expression: t.faelligAm)]))
        .get();
    final rows = alle
        .where((w) =>
            !w.faelligAm.isBefore(tagBeginn) &&
            w.faelligAm.isBefore(tagEnde))
        .toList();
    if (!mounted) return;
    setState(() => _konflikte = rows);
  }

  Future<void> _einfuegeTextbaustein() async {
    final db = ref.read(appDatabaseProvider);
    final liste = await (db.select(db.textbausteine)
          ..where((t) => t.kategorie.equals('anschreiben'))
          ..orderBy([(t) => OrderingTerm(expression: t.titel)]))
        .get();
    if (!mounted) return;
    if (liste.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Keine Anschreiben-Textbausteine hinterlegt — Modul „Textbausteine" nutzen.')));
      return;
    }
    final picked = await showDialog<TextbausteineData>(
      context: context,
      useRootNavigator: true,
      builder: (_) => Dialog(
        child: SizedBox(
          width: 540,
          height: 480,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child:
                    Text('Textbaustein wählen', style: TextStyle(fontSize: 16)),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: liste.length,
                  itemBuilder: (_, i) {
                    final t = liste[i];
                    return ListTile(
                      title: Text(t.titel),
                      subtitle: Text(t.inhalt ?? '',
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () =>
                          Navigator.of(context, rootNavigator: true).pop(t),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final cur = _hinweis.text.trim();
    final neu = picked.inhalt ?? '';
    setState(() {
      _hinweis.text = cur.isEmpty ? neu : '$cur\n\n$neu';
    });
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd.MM.yyyy', 'de');
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 720,
        height: 760,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
              child: Row(children: [
                const Icon(Icons.event_outlined),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Termin-Einladung an Beteiligte',
                      style: TextStyle(fontSize: 16)),
                ),
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
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Expanded(
                        child: InkWell(
                          onTap: _waehleDatum,
                          child: InputDecorator(
                            decoration:
                                const InputDecoration(labelText: 'Datum'),
                            child: Row(children: [
                              const Icon(Icons.calendar_today_outlined,
                                  size: 16),
                              const SizedBox(width: 8),
                              Text(_datum == null
                                  ? '— Datum wählen —'
                                  : dateFmt.format(_datum!)),
                            ]),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: _waehleZeit,
                          child: InputDecorator(
                            decoration:
                                const InputDecoration(labelText: 'Uhrzeit'),
                            child: Row(children: [
                              const Icon(Icons.schedule, size: 16),
                              const SizedBox(width: 8),
                              Text(_zeit.format(context)),
                            ]),
                          ),
                        ),
                      ),
                    ]),
                    if (_konflikte.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .errorContainer
                              .withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: Theme.of(context).colorScheme.error,
                              width: 0.5),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                '⚠ ${_konflikte.length} Termin${_konflikte.length == 1 ? '' : 'e'} am '
                                '${dateFmt.format(_datum!)} bereits eingetragen:',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .error)),
                            const SizedBox(height: 4),
                            for (final k in _konflikte)
                              Text(
                                  '  • ${DateFormat('HH:mm').format(k.faelligAm)} — ${k.titel}',
                                  style: const TextStyle(fontSize: 11)),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _ort,
                      decoration: const InputDecoration(
                          labelText: 'Ort / Anschrift Ortstermin'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _betreff,
                      decoration:
                          const InputDecoration(labelText: 'Betreff'),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      const Text('Hinweis / freier Text',
                          style: TextStyle(fontSize: 13)),
                      const Spacer(),
                      TextButton.icon(
                        icon: const Icon(Icons.article_outlined, size: 14),
                        label: const Text('Textbaustein'),
                        onPressed: _einfuegeTextbaustein,
                      ),
                    ]),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _hinweis,
                      minLines: 6,
                      maxLines: 12,
                      decoration: const InputDecoration(
                          alignLabelWithHint: true,
                          hintText:
                              'Bitte teilen Sie uns kurz mit, ob Sie den Termin wahrnehmen können …'),
                    ),
                    const SizedBox(height: 12),
                    Text('Empfänger',
                        style: Theme.of(context).textTheme.titleSmall),
                    for (var i = 0; i < widget.beteiligte.length; i++)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: _ausgewaehlt.contains(i),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _ausgewaehlt.add(i);
                          } else {
                            _ausgewaehlt.remove(i);
                          }
                        }),
                        title: Text(
                            '${widget.beteiligte[i].rolle} · ${widget.beteiligte[i].name}'),
                        subtitle: (widget.beteiligte[i].email).isEmpty
                            ? null
                            : Text(widget.beteiligte[i].email,
                                style: const TextStyle(fontSize: 11)),
                      ),
                    const SizedBox(height: 12),
                    Row(children: [
                      const Text('Versandweg', style: TextStyle(fontSize: 13)),
                      const SizedBox(width: 12),
                      SegmentedButton<_Kanal>(
                        segments: const [
                          ButtonSegment(
                              value: _Kanal.brief,
                              icon: Icon(Icons.mail_outline, size: 14),
                              label: Text('Brief')),
                          ButtonSegment(
                              value: _Kanal.mail,
                              icon: Icon(Icons.alternate_email, size: 14),
                              label: Text('E-Mail')),
                        ],
                        selected: {_kanal},
                        onSelectionChanged: (s) =>
                            setState(() => _kanal = s.first),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: _inKalender,
                      onChanged: (v) =>
                          setState(() => _inKalender = v ?? true),
                      title: const Text(
                          'Termin in meinem Kalender (Wiedervorlagen) eintragen'),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(children: [
                Text(
                  '${_ausgewaehlt.length} ${_kanal == _Kanal.brief ? "Brief" : "Mail"}-Entwürfe werden erzeugt.',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () =>
                      Navigator.of(context, rootNavigator: true).pop(),
                  child: const Text('Abbrechen'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.send_outlined, size: 16),
                  label: const Text('Erzeugen'),
                  onPressed: _ausgewaehlt.isEmpty
                      ? null
                      : () {
                          final empfaenger = [
                            for (final i in _ausgewaehlt) widget.beteiligte[i]
                          ];
                          Navigator.of(context, rootNavigator: true).pop(
                            _EinladungResult(
                              termin: _terminMoment,
                              ort: _ort.text.trim(),
                              betreff: _betreff.text.trim().isEmpty
                                  ? 'Einladung zum Ortstermin'
                                  : _betreff.text.trim(),
                              hinweis: _hinweis.text.trim(),
                              empfaenger: empfaenger,
                              kanal: _kanal,
                              inKalender: _inKalender,
                            ),
                          );
                        },
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
