import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

/// Frei definierbares Zusatzfeld einer Akte (entspricht „Aktendaten Plus“
/// im Gutachten-Manager). Wird im `extras`-JSON der Akte unter
/// `zusatzfelder` gespeichert – keine Schemaänderung nötig.
///
/// Platzhalter in Vorlagen: `$<Platzhalter>` bzw. `{{zf.<Platzhalter>}}`.
class Zusatzfeld {
  Zusatzfeld({this.name = '', this.wert = '', String? platzhalter})
      : platzhalter = platzhalter ?? platzhalterAus(name);

  String name;
  String wert;
  String platzhalter;

  /// „Baujahr Dach“ → „BaujahrDach“ (nur Buchstaben/Ziffern/_).
  static String platzhalterAus(String name) {
    final teile = name
        .trim()
        .split(RegExp(r'[^A-Za-zÄÖÜäöüß0-9]+'))
        .where((t) => t.isNotEmpty)
        .map((t) => t[0].toUpperCase() + t.substring(1));
    final s = teile.join();
    if (s.isEmpty) return '';
    return RegExp(r'^[0-9]').hasMatch(s) ? 'Z$s' : s;
  }

  Map<String, dynamic> toJson() =>
      {'name': name, 'wert': wert, 'platzhalter': platzhalter};

  static Zusatzfeld fromJson(Map<String, dynamic> m) => Zusatzfeld(
        name: m['name']?.toString() ?? '',
        wert: m['wert']?.toString() ?? '',
        platzhalter: m['platzhalter']?.toString(),
      );
}

List<Zusatzfeld> zusatzfelderAus(String? extras) {
  if (extras == null || extras.trim().isEmpty) return [];
  try {
    final root = jsonDecode(extras);
    if (root is Map<String, dynamic> && root['zusatzfelder'] is List) {
      return (root['zusatzfelder'] as List)
          .whereType<Map<String, dynamic>>()
          .map(Zusatzfeld.fromJson)
          .where((z) => z.name.trim().isNotEmpty)
          .toList();
    }
  } catch (_) {}
  return [];
}

String zusatzfelderInExtras(String? extras, List<Zusatzfeld> felder) {
  Map<String, dynamic> root = {};
  if (extras != null && extras.trim().isNotEmpty) {
    try {
      final d = jsonDecode(extras);
      if (d is Map<String, dynamic>) root = Map<String, dynamic>.from(d);
    } catch (_) {}
  }
  root['zusatzfelder'] = felder
      .where((z) => z.name.trim().isNotEmpty)
      .map((z) => z.toJson())
      .toList();
  return jsonEncode(root);
}

/// Platzhalter-Map der Zusatzfelder (beide Syntaxen).
Map<String, String> zusatzfelderPlatzhalter(String? extras) {
  final out = <String, String>{};
  for (final z in zusatzfelderAus(extras)) {
    if (z.platzhalter.isEmpty) continue;
    out['{{zf.${z.platzhalter}}}'] = z.wert;
    out['\$${z.platzhalter}'] = z.wert;
  }
  return out;
}

/// Dialog zum Bearbeiten der Zusatzfelder einer Akte.
Future<void> showZusatzfelderDialog(
    BuildContext context, WidgetRef ref, AuftraegeData auftrag) async {
  final felder = zusatzfelderAus(auftrag.extras);
  if (felder.isEmpty) felder.add(Zusatzfeld());
  final ok = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (_) => _ZusatzfelderDialog(felder: felder),
  );
  if (ok != true) return;
  final db = ref.read(appDatabaseProvider);
  final aktuell = await (db.select(db.auftraege)
        ..where((t) => t.id.equals(auftrag.id)))
      .getSingleOrNull();
  await (db.update(db.auftraege)..where((t) => t.id.equals(auftrag.id))).write(
    AuftraegeCompanion(
      extras: Value(zusatzfelderInExtras(aktuell?.extras ?? auftrag.extras, felder)),
      updatedAt: Value(DateTime.now()),
    ),
  );
}

class _ZusatzfelderDialog extends StatefulWidget {
  const _ZusatzfelderDialog({required this.felder});
  final List<Zusatzfeld> felder;
  @override
  State<_ZusatzfelderDialog> createState() => _ZusatzfelderDialogState();
}

class _ZusatzfelderDialogState extends State<_ZusatzfelderDialog> {
  @override
  Widget build(BuildContext context) {
    final f = widget.felder;
    return AlertDialog(
      title: const Text('Zusatzfelder der Akte'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Eigene Angaben zur Akte, z. B. „Baujahr Dach“ oder „Hausverwaltung“. '
                'In Word-Vorlagen und Anschreiben als \$Platzhalter bzw. {{zf.Platzhalter}} nutzbar.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < f.length; i++)
                Padding(
                  key: ObjectKey(f[i]),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          initialValue: f[i].name,
                          decoration: InputDecoration(
                            labelText: 'Feld',
                            isDense: true,
                            helperText: f[i].platzhalter.isEmpty
                                ? null
                                : '\$${f[i].platzhalter}',
                          ),
                          onChanged: (v) => setState(() {
                            f[i].name = v;
                            f[i].platzhalter = Zusatzfeld.platzhalterAus(v);
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 5,
                        child: TextFormField(
                          initialValue: f[i].wert,
                          minLines: 1,
                          maxLines: 4,
                          decoration: const InputDecoration(
                              labelText: 'Wert', isDense: true),
                          onChanged: (v) => f[i].wert = v,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Feld entfernen',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => setState(() => f.removeAt(i)),
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Feld hinzufügen'),
                  onPressed: () => setState(() => f.add(Zusatzfeld())),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen')),
        FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Speichern')),
      ],
    );
  }
}
