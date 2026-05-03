import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:drift/drift.dart' show Value;

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../../features/akten/auftraege/auftraege_repository.dart';
import '../../../features/akten/kunden/kunden_repository.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';
import '../textbausteine/textbausteine_repository.dart';
import 'recherche_ablage_repository.dart';

/// Übersicht über die Recherche-Ablage — zeigt alle gespeicherten
/// Notizen aus dem Normen-KI-Chat (und ggf. manuell angelegte), mit
/// Filter nach Akte und Status „verwendet".
class RechercheAblageScreen extends ConsumerStatefulWidget {
  const RechercheAblageScreen({super.key});
  @override
  ConsumerState<RechercheAblageScreen> createState() =>
      _RechercheAblageScreenState();
}

class _RechercheAblageScreenState
    extends ConsumerState<RechercheAblageScreen> {
  String _query = '';
  int? _auftragFilter;
  bool _nurUnverwendet = false;
  _RechercheSort _sort = _RechercheSort.neueste;

  static final _fmt = DateFormat('dd.MM.yyyy HH:mm');

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(rechercheAblageProvider);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.bookmark_outline,
          title: 'Recherche-Ablage',
          subtitle:
              'Zwischenspeicher für Normen-Recherche und Notizen — beim Gutachten-Schreiben abschnittsweise einfügbar',
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Notiz anlegen'),
              onPressed: () => _open(context, null),
            ),
          ],
          searchHint: 'Suche Titel oder Inhalt',
          onSearchChanged: (v) => setState(() => _query = v),
          filters: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Checkbox(
                value: _nurUnverwendet,
                onChanged: (v) =>
                    setState(() => _nurUnverwendet = v ?? false),
              ),
              const Text('nur offene'),
            ]),
            _AuftragFilterDropdown(
              aktuell: _auftragFilter,
              onChanged: (id) => setState(() => _auftragFilter = id),
            ),
            DropdownButtonHideUnderline(
              child: DropdownButton<_RechercheSort>(
                value: _sort,
                items: const [
                  DropdownMenuItem(
                      value: _RechercheSort.neueste,
                      child: Text('Neueste zuerst')),
                  DropdownMenuItem(
                      value: _RechercheSort.aelteste,
                      child: Text('Älteste zuerst')),
                  DropdownMenuItem(
                      value: _RechercheSort.titelAsc,
                      child: Text('Titel A → Z')),
                  DropdownMenuItem(
                      value: _RechercheSort.titelDesc,
                      child: Text('Titel Z → A')),
                  DropdownMenuItem(
                      value: _RechercheSort.quelle,
                      child: Text('Nach Quelle')),
                ],
                onChanged: (v) => setState(() => _sort = v ?? _sort),
              ),
            ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: async.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Fehler: $e')),
            data: (alle) {
              final q = _query.trim().toLowerCase();
              final gefiltert = alle.where((n) {
                if (_nurUnverwendet && n.verwendet) return false;
                if (_auftragFilter != null &&
                    n.auftragId != _auftragFilter) {
                  return false;
                }
                if (q.isEmpty) return true;
                return n.titel.toLowerCase().contains(q) ||
                    n.inhalt.toLowerCase().contains(q);
              }).toList();
              gefiltert.sort((a, b) {
                switch (_sort) {
                  case _RechercheSort.neueste:
                    return b.updatedAt.compareTo(a.updatedAt);
                  case _RechercheSort.aelteste:
                    return a.updatedAt.compareTo(b.updatedAt);
                  case _RechercheSort.titelAsc:
                    return a.titel
                        .toLowerCase()
                        .compareTo(b.titel.toLowerCase());
                  case _RechercheSort.titelDesc:
                    return b.titel
                        .toLowerCase()
                        .compareTo(a.titel.toLowerCase());
                  case _RechercheSort.quelle:
                    final aq = (a.quelle ?? '').toLowerCase();
                    final bq = (b.quelle ?? '').toLowerCase();
                    final c = aq.compareTo(bq);
                    return c == 0
                        ? b.updatedAt.compareTo(a.updatedAt)
                        : c;
                }
              });
              if (gefiltert.isEmpty) {
                return const EmptyListState(
                  icon: Icons.bookmark_outline,
                  title: 'Keine Recherche-Notizen',
                  hint:
                      'Nutze „KI-Frage stellen" im Normen-Modul und '
                      'speichere Antworten hier ab.',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: gefiltert.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) =>
                    _eintrag(gefiltert[i], scheme),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _eintrag(RechercheNotizenData n, ColorScheme scheme) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
            color: n.verwendet
                ? scheme.outlineVariant
                : scheme.primary.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _open(context, n),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (n.verwendet)
                    Icon(Icons.check_circle,
                        size: 16, color: scheme.primary),
                  if (n.verwendet) const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      n.titel,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (n.quelle != null && n.quelle!.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(n.quelle!,
                          style: const TextStyle(fontSize: 11)),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(_fmt.format(n.createdAt),
                      style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                          fontFeatures: const [
                            FontFeature.tabularFigures()
                          ])),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    icon: const Icon(Icons.playlist_add),
                    tooltip: 'Als Textbaustein übernehmen',
                    onPressed: () => _alsTextbaustein(n),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Löschen',
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        useRootNavigator: true,
                        builder: (_) => AlertDialog(
                          title: const Text('Notiz löschen?'),
                          content: Text(
                              'Der Eintrag „${n.titel}" wird endgültig entfernt.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context,
                                      rootNavigator: true)
                                  .pop(false),
                              child: const Text('Abbrechen'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.of(context,
                                      rootNavigator: true)
                                  .pop(true),
                              child: const Text('Löschen'),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) {
                        await ref
                            .read(rechercheAblageRepositoryProvider)
                            .delete(n.id);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                n.inhalt,
                style: const TextStyle(fontSize: 13),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Überführt eine Recherche-Notiz in die Textbausteine-Bibliothek.
  /// Öffnet einen kleinen Dialog, in dem der Nutzer Titel, Kategorie
  /// und Sachgebiet ergänzen kann. Optional wird die Recherche-Notiz
  /// danach gelöscht.
  Future<void> _alsTextbaustein(RechercheNotizenData n) async {
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _AlsTextbausteinDialog(notiz: n),
    );
  }

  Future<void> _open(
      BuildContext context, RechercheNotizenData? n) async {
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _NotizEditor(notiz: n),
    );
  }
}

class _AuftragFilterDropdown extends ConsumerWidget {
  const _AuftragFilterDropdown(
      {required this.aktuell, required this.onChanged});
  final int? aktuell;
  final ValueChanged<int?> onChanged;

  /// Baut die zweizeilige Anzeige für ein Akten-Dropdown-Item:
  /// Zeile 1 = Aktenzeichen + Name, Zeile 2 = Anschrift + Thema.
  Widget _buildItem(AuftragWithKunde a) {
    final az = a.auftrag.aktenzeichen ?? '—';
    final name = a.kunde == null ? '' : kundeAnzeigename(a.kunde!);
    final adresse = [
      a.auftrag.objektStrasse,
      [a.auftrag.objektPlz, a.auftrag.objektOrt]
          .whereType<String>()
          .where((s) => s.trim().isNotEmpty)
          .join(' '),
    ].whereType<String>().where((s) => s.trim().isNotEmpty).join(', ');
    final thema = (a.auftrag.bezeichnung?.trim().isNotEmpty ?? false)
        ? a.auftrag.bezeichnung!.trim()
        : (a.auftrag.betreff?.trim() ?? '');
    final zeile1 =
        [az, if (name.isNotEmpty) name].join(' · ');
    final zeile2Parts = [
      if (adresse.isNotEmpty) adresse,
      if (thema.isNotEmpty) thema,
    ];
    final zeile2 = zeile2Parts.join(' · ');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(zeile1,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        if (zeile2.isNotEmpty)
          Text(zeile2,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.black54)),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(auftraegeListProvider);
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (list) => DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: aktuell,
          hint: const Text('Alle Akten'),
          isExpanded: true,
          // Im geschlossenen Zustand möchten wir nur einzeilige Anzeige
          // (Aktenzeichen + Name). Im aufgeklappten Menu: zwei Zeilen
          // (Aktenzeichen + Name oben, Anschrift + Thema unten).
          selectedItemBuilder: (_) => [
            const Text('Alle Akten'),
            for (final a in list)
              Builder(builder: (_) {
                final az = a.auftrag.aktenzeichen ?? '—';
                final name = a.kunde == null ? '' : kundeAnzeigename(a.kunde!);
                return Text([az, if (name.isNotEmpty) name].join(' · '),
                    overflow: TextOverflow.ellipsis);
              }),
          ],
          items: [
            const DropdownMenuItem<int?>(
                value: null, child: Text('Alle Akten')),
            for (final a in list)
              DropdownMenuItem<int?>(
                value: a.auftrag.id,
                child: _buildItem(a),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _NotizEditor extends ConsumerStatefulWidget {
  const _NotizEditor({this.notiz});
  final RechercheNotizenData? notiz;
  @override
  ConsumerState<_NotizEditor> createState() => _NotizEditorState();
}

class _NotizEditorState extends ConsumerState<_NotizEditor> {
  late final _titel =
      TextEditingController(text: widget.notiz?.titel ?? '');
  late final _inhalt =
      TextEditingController(text: widget.notiz?.inhalt ?? '');
  int? _auftragId;
  bool _saving = false;

  bool get _isEdit => widget.notiz != null;

  @override
  void initState() {
    super.initState();
    _auftragId = widget.notiz?.auftragId;
  }

  @override
  void dispose() {
    _titel.dispose();
    _inhalt.dispose();
    super.dispose();
  }

  Future<void> _speichern() async {
    setState(() => _saving = true);
    try {
      final repo = ref.read(rechercheAblageRepositoryProvider);
      if (_isEdit) {
        await repo.updateText(
          widget.notiz!.id,
          titel: _titel.text,
          inhalt: _inhalt.text,
          auftragId: _auftragId,
        );
      } else {
        await repo.insert(
          auftragId: _auftragId,
          titel: _titel.text,
          inhalt: _inhalt.text,
          quelle: 'Manuell',
        );
      }
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.bookmark_outline),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isEdit
                          ? 'Notiz bearbeiten'
                          : 'Neue Recherche-Notiz',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: true).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _titel,
                decoration: const InputDecoration(
                  labelText: 'Titel',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _inhalt,
                minLines: 6,
                maxLines: 14,
                decoration: const InputDecoration(
                  labelText: 'Inhalt',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              _AuftragFilterDropdown(
                aktuell: _auftragId,
                onChanged: (id) => setState(() => _auftragId = id),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context,
                                rootNavigator: true)
                            .pop(),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check, size: 16),
                    label:
                        Text(_saving ? 'Speichere …' : 'Speichern'),
                    onPressed: _saving ? null : _speichern,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialog zum Überführen einer Recherche-Notiz in einen Textbaustein.
class _AlsTextbausteinDialog extends ConsumerStatefulWidget {
  const _AlsTextbausteinDialog({required this.notiz});
  final RechercheNotizenData notiz;
  @override
  ConsumerState<_AlsTextbausteinDialog> createState() =>
      _AlsTextbausteinDialogState();
}

class _AlsTextbausteinDialogState
    extends ConsumerState<_AlsTextbausteinDialog> {
  late final _titel = TextEditingController(text: widget.notiz.titel);
  late final _inhalt = TextEditingController(text: widget.notiz.inhalt);
  late final _kategorie = TextEditingController(text: 'recherche');
  late final _sachgebiet = TextEditingController();
  bool _recherche_loeschen = true;
  bool _saving = false;

  @override
  void dispose() {
    _titel.dispose();
    _inhalt.dispose();
    _kategorie.dispose();
    _sachgebiet.dispose();
    super.dispose();
  }

  Future<void> _speichern() async {
    setState(() => _saving = true);
    try {
      final db = ref.read(appDatabaseProvider);
      await db.into(db.textbausteine).insert(
            TextbausteineCompanion.insert(
              titel: _titel.text.trim(),
              kategorie: Value(_kategorie.text.trim().isEmpty
                  ? null
                  : _kategorie.text.trim()),
              sachgebiet: Value(_sachgebiet.text.trim().isEmpty
                  ? null
                  : _sachgebiet.text.trim()),
              inhalt: Value(_inhalt.text),
              reihenfolge: const Value(500),
              favorit: const Value(false),
            ),
          );
      if (_recherche_loeschen) {
        await ref
            .read(rechercheAblageRepositoryProvider)
            .delete(widget.notiz.id);
      }
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_recherche_loeschen
              ? 'Als Textbaustein gespeichert — Notiz entfernt.'
              : 'Als Textbaustein gespeichert.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.playlist_add),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Als Textbaustein übernehmen',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context, rootNavigator: true)
                            .pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _titel,
                decoration: const InputDecoration(
                  labelText: 'Titel',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _kategorie,
                      decoration: const InputDecoration(
                        labelText: 'Kategorie',
                        hintText: 'z. B. recherche, anschreiben, gutachten',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _sachgebiet,
                      decoration: const InputDecoration(
                        labelText: 'Sachgebiet (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _inhalt,
                minLines: 6,
                maxLines: 14,
                decoration: const InputDecoration(
                  labelText: 'Inhalt',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Checkbox(
                    value: _recherche_loeschen,
                    onChanged: (v) =>
                        setState(() => _recherche_loeschen = v ?? true),
                  ),
                  const Expanded(
                    child: Text(
                      'Recherche-Notiz nach der Übernahme löschen',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context,
                                rootNavigator: true)
                            .pop(),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white))
                        : const Icon(Icons.check, size: 16),
                    label:
                        Text(_saving ? 'Speichere …' : 'Übernehmen'),
                    onPressed: _saving ? null : _speichern,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _RechercheSort {
  neueste,
  aelteste,
  titelAsc,
  titelDesc,
  quelle,
}
