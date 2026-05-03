import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
import 'lv_repository.dart';

/// Aufmaß-Panel: Liste von Mengenzeilen mit Bezeichnung + Formel
/// (z. B. `3,5*2,8`) und Live-Ergebnis. Summe wird oben angezeigt; per
/// Button kann sie in das `menge`-Feld der Position übernommen werden.
class LvAufmassPanel extends ConsumerStatefulWidget {
  const LvAufmassPanel({
    super.key,
    required this.positionId,
    required this.einheit,
    required this.onSummeUebernehmen,
  });
  final int positionId;
  final String? einheit;
  final ValueChanged<double> onSummeUebernehmen;

  @override
  ConsumerState<LvAufmassPanel> createState() => _LvAufmassPanelState();
}

class _LvAufmassPanelState extends ConsumerState<LvAufmassPanel> {
  static final _fmt = NumberFormat.decimalPattern('de_DE');

  Future<void> _addZeile() async {
    final repo = ref.read(lvRepositoryProvider);
    final all = await repo.watchMengen(widget.positionId).first;
    await repo.upsertMenge(LvMengenzeilenCompanion.insert(
      positionId: widget.positionId,
      sortIndex: Value(all.length * 10),
      bezeichnung: const Value(''),
      formel: const Value(''),
      ergebnis: const Value(0),
    ));
  }

  Future<void> _updateZeile(LvMengenzeilenData zeile,
      {String? bezeichnung, String? formel}) async {
    final neueFormel = formel ?? zeile.formel ?? '';
    final neuesErgebnis = evalFormel(neueFormel);
    await ref.read(lvRepositoryProvider).upsertMenge(
          LvMengenzeilenCompanion(
            id: Value(zeile.id),
            positionId: Value(zeile.positionId),
            sortIndex: Value(zeile.sortIndex),
            bezeichnung:
                Value(bezeichnung ?? zeile.bezeichnung ?? ''),
            formel: Value(neueFormel),
            ergebnis: Value(neuesErgebnis),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final zeilen = ref.watch(lvMengenProvider(widget.positionId));
    return zeilen.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Text('Fehler: $e'),
      data: (rows) {
        final summe = rows.fold<double>(0, (s, z) => s + z.ergebnis);
        return Container(
          decoration: BoxDecoration(
            border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.calculate_outlined,
                      size: 16,
                      color: Theme.of(context).colorScheme.outline),
                  const SizedBox(width: 6),
                  Text('Aufmaß / Mengenermittlung',
                      style: Theme.of(context).textTheme.titleSmall),
                  const Spacer(),
                  Text('Summe: ${_fmt.format(summe)} ${widget.einheit ?? ""}',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.arrow_circle_up_outlined,
                        size: 16),
                    label: const Text('In Menge übernehmen'),
                    onPressed: rows.isEmpty
                        ? null
                        : () => widget.onSummeUebernehmen(summe),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Formeln werden live ausgewertet — `+ - * /`, Klammern, '
                'Komma als Dezimaltrenner. Beispiel: `(12 + 8) * 1,15` = ${_fmt.format(evalFormel("(12+8)*1,15"))}.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline),
              ),
              const SizedBox(height: 8),
              if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('Noch keine Aufmaß-Zeilen.',
                      style: Theme.of(context).textTheme.bodySmall),
                )
              else
                ...rows.map((z) => _AufmassZeile(
                      key: ValueKey(z.id),
                      zeile: z,
                      einheit: widget.einheit,
                      onChanged: (b, f) =>
                          _updateZeile(z, bezeichnung: b, formel: f),
                      onDelete: () => ref
                          .read(lvRepositoryProvider)
                          .deleteMenge(z.id),
                    )),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Aufmaß-Zeile hinzufügen'),
                  onPressed: _addZeile,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AufmassZeile extends StatefulWidget {
  const _AufmassZeile({
    super.key,
    required this.zeile,
    required this.einheit,
    required this.onChanged,
    required this.onDelete,
  });
  final LvMengenzeilenData zeile;
  final String? einheit;
  final void Function(String? bezeichnung, String? formel) onChanged;
  final VoidCallback onDelete;

  @override
  State<_AufmassZeile> createState() => _AufmassZeileState();
}

class _AufmassZeileState extends State<_AufmassZeile> {
  late final _bez =
      TextEditingController(text: widget.zeile.bezeichnung ?? '');
  late final _formel =
      TextEditingController(text: widget.zeile.formel ?? '');
  static final _fmt = NumberFormat.decimalPattern('de_DE');

  @override
  void dispose() {
    _bez.dispose();
    _formel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ergebnis = evalFormel(_formel.text);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: TextField(
              controller: _bez,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Bezeichnung (z. B. Wand Nordseite)',
              ),
              onChanged: (v) => widget.onChanged(v, null),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: TextField(
              controller: _formel,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Formel  (z. B. 3,5 * 2,8)',
              ),
              onChanged: (v) {
                widget.onChanged(null, v);
                setState(() {});
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: Text(
              '${_fmt.format(ergebnis)} ${widget.einheit ?? ""}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            tooltip: 'Zeile löschen',
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: widget.onDelete,
          ),
        ],
      ),
    );
  }
}
