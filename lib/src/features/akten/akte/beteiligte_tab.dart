import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../auftraege/auftraege_repository.dart';

/// Ein Beteiligter in einer Akte — zusätzlich zum Auftraggeber.
class Beteiligter {
  String rolle;
  String name;
  String anschrift;
  String telefon;
  String email;
  Beteiligter({
    this.rolle = 'Antragsteller',
    this.name = '',
    this.anschrift = '',
    this.telefon = '',
    this.email = '',
  });
  Map<String, dynamic> toJson() => {
        'rolle': rolle,
        'name': name,
        'anschrift': anschrift,
        'telefon': telefon,
        'email': email,
      };
  static Beteiligter fromJson(Map<String, dynamic> m) => Beteiligter(
        rolle: m['rolle']?.toString() ?? 'Antragsteller',
        name: m['name']?.toString() ?? '',
        anschrift: m['anschrift']?.toString() ?? '',
        telefon: m['telefon']?.toString() ?? '',
        email: m['email']?.toString() ?? '',
      );
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
                : ListView.separated(
                    itemCount: _liste.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _BeteiligterRow(
                      key: ValueKey(_liste[i]),
                      b: _liste[i],
                      onChanged: () => setState(() => _dirty = true),
                      onRemove: () => setState(() {
                        _liste.removeAt(i);
                        _dirty = true;
                      }),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// Öffnet einen kleinen Dialog zur Eingabe von Termin-Datum + Ort und
  /// erzeugt anschließend für jeden Beteiligten ein vorgefülltes
  /// Anschreiben. Der User kann sie danach im Anschreiben-Modul oder im
  /// Akte-Anschreiben-Tab bearbeiten/drucken.
  Future<void> _massenEinladung(BuildContext context) async {
    final terminCtrl = TextEditingController();
    final ortCtrl = TextEditingController(
      text: [
        widget.auftrag.objektStrasse,
        '${widget.auftrag.objektPlz ?? ''} ${widget.auftrag.objektOrt ?? ''}'
            .trim(),
      ].whereType<String>().where((s) => s.trim().isNotEmpty).join(', '),
    );
    final betreffCtrl = TextEditingController(
        text: 'Einladung zum Ortstermin');
    final hinweisCtrl = TextEditingController(
        text:
            'Bitte teilen Sie uns kurz mit, ob Sie den Termin wahrnehmen können.');

    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Termin-Einladung an alle Beteiligten'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: terminCtrl,
                decoration: const InputDecoration(
                  labelText: 'Termin (z. B. 14.05.2026 um 10:00 Uhr)',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ortCtrl,
                decoration: const InputDecoration(
                  labelText: 'Ort / Anschrift Ortstermin',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: betreffCtrl,
                decoration: const InputDecoration(labelText: 'Betreff'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: hinweisCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Zusätzlicher Hinweis (optional)',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${_liste.length} Anschreiben werden als Entwurf erzeugt.',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: const Text('Erzeugen')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    final db = ref.read(appDatabaseProvider);
    final ortText = ortCtrl.text.trim();
    final terminText = terminCtrl.text.trim();
    final hinweisText = hinweisCtrl.text.trim();
    final betreff = betreffCtrl.text.trim().isEmpty
        ? 'Einladung zum Ortstermin'
        : betreffCtrl.text.trim();
    int erstellt = 0;
    for (final b in _liste) {
      if (b.name.trim().isEmpty) continue;
      final anrede = _briefanredeFuer(b.name, b.rolle);
      final brief = StringBuffer()
        ..writeln(
            'in oben genannter Sache lade ich Sie hiermit zum Ortstermin ein.')
        ..writeln()
        ..writeln('Termin: ${terminText.isEmpty ? "wird gesondert mitgeteilt" : terminText}')
        ..writeln('Ort: ${ortText.isEmpty ? "—" : ortText}')
        ..writeln();
      if (hinweisText.isNotEmpty) {
        brief.writeln(hinweisText);
        brief.writeln();
      }
      brief.write('Mit freundlichen Grüßen');

      // Beteiligten-Adresse als JSON in extras ablegen, damit das PDF-
      // Rendering sie als Empfänger nutzen kann.
      final extras = jsonEncode({
        'beteiligterRolle': b.rolle,
        'beteiligterName': b.name,
        'beteiligterAnschrift': b.anschrift,
        'terminText': terminText,
        'ortText': ortText,
      });
      await db.into(db.anschreiben).insert(AnschreibenCompanion.insert(
            auftragId: Value(widget.auftrag.id),
            betreff: Value(betreff),
            datum: Value(DateTime.now()),
            anrede: Value(anrede),
            briefText: Value(brief.toString()),
            gruss: const Value('Mit freundlichen Grüßen'),
            status: const Value('entwurf'),
            extras: Value(extras),
          ));
      erstellt++;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          '$erstellt Anschreiben als Entwurf erzeugt. Im Tab „Anschreiben" der Akte einsehbar.'),
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

class _BeteiligterRow extends StatefulWidget {
  const _BeteiligterRow({
    super.key,
    required this.b,
    required this.onChanged,
    required this.onRemove,
  });
  final Beteiligter b;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  @override
  State<_BeteiligterRow> createState() => _BeteiligterRowState();
}

class _BeteiligterRowState extends State<_BeteiligterRow> {
  late final _name = TextEditingController(text: widget.b.name);
  late final _anschrift = TextEditingController(text: widget.b.anschrift);
  late final _telefon = TextEditingController(text: widget.b.telefon);
  late final _email = TextEditingController(text: widget.b.email);

  @override
  void dispose() {
    for (final c in [_name, _anschrift, _telefon, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: DropdownButtonFormField<String>(
              initialValue: beteiligtenRollen.contains(widget.b.rolle)
                  ? widget.b.rolle
                  : 'Sonstiger',
              isDense: true,
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
            flex: 3,
            child: TextField(
              controller: _name,
              decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Name / Firma',
                  border: OutlineInputBorder()),
              onChanged: (v) {
                widget.b.name = v;
                widget.onChanged();
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: TextField(
              controller: _anschrift,
              decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Anschrift',
                  border: OutlineInputBorder()),
              onChanged: (v) {
                widget.b.anschrift = v;
                widget.onChanged();
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 130,
            child: TextField(
              controller: _telefon,
              decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Telefon',
                  border: OutlineInputBorder()),
              onChanged: (v) {
                widget.b.telefon = v;
                widget.onChanged();
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 170,
            child: TextField(
              controller: _email,
              decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'E-Mail',
                  border: OutlineInputBorder()),
              onChanged: (v) {
                widget.b.email = v;
                widget.onChanged();
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: Theme.of(context).colorScheme.error,
            onPressed: widget.onRemove,
          ),
        ],
      ),
    );
  }
}
