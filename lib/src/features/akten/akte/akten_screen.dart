import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/aw_tokens.dart';
import '../../../shared/widgets/badges.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';
import '../auftraege/auftraege_form.dart';
import '../auftraege/auftraege_repository.dart';
import '../kunden/kunden_repository.dart';
import '../rechnungen/rechnungen_repository.dart';
import 'akte_counts.dart';

/// Übersicht aller Auftragsakten — jeder Auftrag ist eine Akte, die alle
/// zugehörigen Objekte (Angebote, Rechnungen, Gutachten, Stunden, Auslagen,
/// Fotos, Dokumente, Normen, Geräte, Erläuterungen) bündelt.
///
/// Klick auf eine Zeile öffnet die Auftragsakte (`/akte/:id`).
class AktenScreen extends ConsumerStatefulWidget {
  const AktenScreen({super.key});
  @override
  ConsumerState<AktenScreen> createState() => _AktenScreenState();
}

/// Compliance-Checks, die als Filter-Tiles über der Akten-Liste erscheinen.
/// Jedes Tile zeigt die Anzahl der Akten mit dem entsprechenden Mangel und
/// filtert die Liste auf Klick.
enum _ComplianceCheck {
  befangenheitFehlt,
  kostenvorschussFehlt,
  beweisfragenFehlen,
  fristUeberfaellig,
}

bool _istGerichtsakte(String? art) =>
    art == 'gericht' || art == 'beweissicherung';

bool _hatMangel(_ComplianceCheck c, AuftragWithKunde a) {
  final auf = a.auftrag;
  return switch (c) {
    _ComplianceCheck.befangenheitFehlt =>
      _istGerichtsakte(auf.art) && auf.befangenheitsGeprueftAm == null,
    _ComplianceCheck.kostenvorschussFehlt =>
      _istGerichtsakte(auf.art) &&
          (auf.kostenvorschuss == null || auf.kostenvorschuss == 0),
    _ComplianceCheck.beweisfragenFehlen =>
      _istGerichtsakte(auf.art) &&
          (auf.beweisfragenJson == null ||
              auf.beweisfragenJson!.trim().isEmpty ||
              auf.beweisfragenJson == '[]'),
    _ComplianceCheck.fristUeberfaellig =>
      auf.fristAm != null &&
          auf.fristAm!.isBefore(DateTime.now()) &&
          auf.status != 'abgeschlossen' &&
          auf.status != 'abgerechnet' &&
          auf.status != 'storniert',
  };
}

class _AktenScreenState extends ConsumerState<AktenScreen> {
  int _sortCol = 0;
  bool _sortAsc = false;
  String _query = '';
  bool _nurAktiv = true;
  _ComplianceCheck? _complianceFilter;
  static final _dateFmt = DateFormat('dd.MM.yyyy', 'de');
  static final _money =
      NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(auftraegeListProvider);
    final rechnungen =
        ref.watch(rechnungenListProvider).valueOrNull ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.folder_open_outlined,
          title: 'Akten',
          subtitle:
              'Der zentrale Drehpunkt: pro Auftrag alle Dokumente, Rechnungen, Angebote, Gutachten …',
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Neue Akte'),
              onPressed: () => _neueAkte(context),
            ),
          ],
          searchHint: 'Suche Aktenzeichen, Betreff, Auftraggeber, Objekt-Ort …',
          onSearchChanged: (v) => setState(() => _query = v),
          filters: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: _nurAktiv,
                  onChanged: (v) =>
                      setState(() => _nurAktiv = v ?? true),
                ),
                const Text('nur aktive'),
              ],
            ),
          ],
        ),
        const Divider(height: 1),
        async.maybeWhen(
          data: (all) => _ComplianceTiles(
            akten: all,
            aktiver: _complianceFilter,
            onTap: (c) => setState(() {
              _complianceFilter = (_complianceFilter == c) ? null : c;
            }),
          ),
          orElse: () => const SizedBox(),
        ),
        Expanded(
          child: async.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Fehler: $e')),
            data: (all) {
              final items = _filter(all);
              if (items.isEmpty) {
                return const EmptyListState(
                  icon: Icons.folder_open_outlined,
                  title: 'Keine Akten',
                  hint:
                      'Sobald du einen Auftrag anlegst, erscheint er hier als Akte.',
                );
              }
              return DataTableCard(
                child: DataTable(
                  showCheckboxColumn: false,
                  sortColumnIndex: _sortCol,
                  sortAscending: _sortAsc,
                  headingRowColor: WidgetStateProperty.all(
                    Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                  ),
                  columns: [
                    _col('Az.', 0),
                    _col('Auftraggeber', 2),
                    _col('Betreff', 3),
                    const DataColumn(label: Text('Inhalte')),
                    _col('Ortstermin', 5),
                    _col('Abgabe', 6),
                    _col('Umsatz €', 7, numeric: true),
                    _col('Status', 8),
                    const DataColumn(label: Text('')),
                  ],
                  rows: [
                    for (final a in _sorted(items, rechnungen))
                      DataRow(
                        onSelectChanged: (_) =>
                            context.go('/akte/${a.auftrag.id}'),
                        cells: [
                          DataCell(Text(
                            a.auftrag.aktenzeichen ?? '',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AwTokens.orange,
                                fontFeatures: [FontFeature.tabularFigures()]),
                          )),
                          DataCell(SizedBox(
                            width: 180,
                            child: Text(
                              a.kunde == null
                                  ? '—'
                                  : kundeAnzeigename(a.kunde!),
                              overflow: TextOverflow.ellipsis,
                            ),
                          )),
                          DataCell(SizedBox(
                            width: 260,
                            child: Text(
                              a.auftrag.betreff ??
                                  a.auftrag.bezeichnung ??
                                  '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          )),
                          DataCell(_InhalteCell(
                              auftragId: a.auftrag.id,
                              kundeId: a.kunde?.id)),
                          DataCell(Text(
                            a.auftrag.ortsterminAm == null
                                ? ''
                                : DateFormat('dd.MM · HH:mm', 'de')
                                    .format(a.auftrag.ortsterminAm!),
                            style: const TextStyle(fontSize: 12),
                          )),
                          DataCell(Text(
                            a.auftrag.abschlussAm == null
                                ? ''
                                : _dateFmt.format(a.auftrag.abschlussAm!),
                            style: const TextStyle(fontSize: 12),
                          )),
                          DataCell(Text(
                            _money.format(_umsatzFuer(
                                a.auftrag.id, rechnungen)),
                            style: const TextStyle(fontSize: 12),
                          )),
                          DataCell(_StatusPill(status: a.auftrag.status)),
                          DataCell(Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined,
                                    size: 18),
                                tooltip: 'Öffnen / Bearbeiten',
                                onPressed: () =>
                                    context.go('/akte/${a.auftrag.id}'),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 18),
                                tooltip: 'Löschen',
                                onPressed: () =>
                                    _confirmDelete(context, a),
                              ),
                            ],
                          )),
                        ],
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  DataColumn _col(String label, int i, {bool numeric = false}) =>
      DataColumn(
        label: Text(label),
        numeric: numeric,
        onSort: (c, asc) => setState(() {
          _sortCol = c;
          _sortAsc = asc;
        }),
      );

  List<AuftragWithKunde> _filter(List<AuftragWithKunde> all) {
    final q = _query.trim().toLowerCase();
    var list = all;
    if (_nurAktiv) {
      list = list
          .where((a) =>
              a.auftrag.status != 'abgeschlossen' &&
              a.auftrag.status != 'abgerechnet' &&
              a.auftrag.status != 'storniert')
          .toList();
    }
    if (q.isNotEmpty) {
      list = list.where((a) {
        final parts = [
          a.auftrag.aktenzeichen,
          a.auftrag.betreff,
          a.auftrag.bezeichnung,
          a.auftrag.objektOrt,
          a.auftrag.objektStrasse,
          a.kunde == null ? null : kundeAnzeigename(a.kunde!),
        ].whereType<String>().map((s) => s.toLowerCase()).join(' ');
        return parts.contains(q);
      }).toList();
    }
    if (_complianceFilter != null) {
      list = list.where((a) => _hatMangel(_complianceFilter!, a)).toList();
    }
    return list;
  }

  List<AuftragWithKunde> _sorted(List<AuftragWithKunde> items,
      List<RechnungWithKunde> rechnungen) {
    int cmp<T extends Comparable>(T? a, T? b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return a.compareTo(b);
    }

    final list = [...items];
    list.sort((a, b) {
      final c = switch (_sortCol) {
        0 => cmp(a.auftrag.aktenzeichen, b.auftrag.aktenzeichen),
        2 => cmp(
            a.kunde == null ? null : kundeAnzeigename(a.kunde!).toLowerCase(),
            b.kunde == null ? null : kundeAnzeigename(b.kunde!).toLowerCase()),
        3 => cmp(a.auftrag.betreff, b.auftrag.betreff),
        5 => cmp(a.auftrag.ortsterminAm, b.auftrag.ortsterminAm),
        6 => cmp(a.auftrag.abschlussAm, b.auftrag.abschlussAm),
        7 => cmp(_umsatzFuer(a.auftrag.id, rechnungen),
            _umsatzFuer(b.auftrag.id, rechnungen)),
        8 => cmp(a.auftrag.status, b.auftrag.status),
        _ => 0,
      };
      return _sortAsc ? c : -c;
    });
    return list;
  }

  double _umsatzFuer(int auftragId, List<RechnungWithKunde> rechnungen) {
    return rechnungen
        .where((r) =>
            r.rechnung.auftragId == auftragId &&
            r.rechnung.status != 'storniert')
        .fold<double>(0, (s, r) => s + r.rechnung.brutto);
  }

  Future<void> _neueAkte(BuildContext context) async {
    final id = await showAuftragFormDialog(context);
    if (id != null && context.mounted) {
      context.go('/akte/$id');
    }
  }

  Future<void> _confirmDelete(
      BuildContext context, AuftragWithKunde a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Akte löschen?'),
        content: Text(
            'Akte «${a.auftrag.aktenzeichen ?? a.auftrag.id}» wird gelöscht. '
            'Rechnungen/Angebote mit Bezug verlieren die Verknüpfung.'),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref
        .read(auftraegeRepositoryProvider)
        .delete(a.auftrag.id);
  }
}

/// Kompakte Zeile aus Icon+Zähler-Chips pro Modul.
class _InhalteCell extends ConsumerWidget {
  const _InhalteCell({required this.auftragId, required this.kundeId});
  final int auftragId;
  final int? kundeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    int c(AsyncValue<int> v) => v.valueOrNull ?? 0;
    final items = <(IconData, int, String)>[
      (
        Icons.schedule_outlined,
        c(ref.watch(stundenCountProvider(auftragId))),
        'Stunden'
      ),
      (
        Icons.payments_outlined,
        c(ref.watch(auslagenCountProvider(auftragId))),
        'Auslagen'
      ),
      (
        Icons.price_change_outlined,
        c(ref.watch(angeboteCountProvider(kundeId))),
        'Angebote'
      ),
      (
        Icons.receipt_long_outlined,
        c(ref.watch(rechnungenCountProvider(auftragId))),
        'Rechnungen'
      ),
      (
        Icons.gavel_outlined,
        c(ref.watch(gutachtenCountProvider(auftragId))),
        'Gutachten'
      ),
      (
        Icons.photo_library_outlined,
        c(ref.watch(fotosCountProvider(auftragId))),
        'Fotos'
      ),
      (
        Icons.description_outlined,
        c(ref.watch(dokumenteCountProvider(auftragId))),
        'Dokumente'
      ),
      (
        Icons.menu_book_outlined,
        c(ref.watch(normenCountProvider(auftragId))),
        'Normen'
      ),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (icon, count, label) in items)
          Tooltip(
            message: '$label: $count',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: count > 0
                        ? AppTheme.accent700
                        : AppTheme.slate300,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    count > 0 ? '$count' : '–',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: count > 0
                          ? AppTheme.accent700
                          : AppTheme.slate300,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ComplianceTiles extends StatelessWidget {
  const _ComplianceTiles({
    required this.akten,
    required this.aktiver,
    required this.onTap,
  });
  final List<AuftragWithKunde> akten;
  final _ComplianceCheck? aktiver;
  final ValueChanged<_ComplianceCheck> onTap;

  static const _defs = <(_ComplianceCheck, String, IconData)>[
    (
      _ComplianceCheck.befangenheitFehlt,
      'Befangenheit fehlt',
      Icons.verified_user_outlined,
    ),
    (
      _ComplianceCheck.kostenvorschussFehlt,
      'Kostenvorschuss offen',
      Icons.payments_outlined,
    ),
    (
      _ComplianceCheck.beweisfragenFehlen,
      'Beweisfragen fehlen',
      Icons.gavel_outlined,
    ),
    (
      _ComplianceCheck.fristUeberfaellig,
      'Frist überfällig',
      Icons.warning_amber_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final counts = <_ComplianceCheck, int>{};
    for (final (c, _, _) in _defs) {
      counts[c] = akten.where((a) => _hatMangel(c, a)).length;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (check, label, icon) in _defs) ...[
              _ComplianceTile(
                label: label,
                icon: icon,
                count: counts[check] ?? 0,
                aktiv: aktiver == check,
                onTap: () => onTap(check),
              ),
              const SizedBox(width: 10),
            ],
            if (aktiver != null)
              TextButton.icon(
                icon: const Icon(Icons.close, size: 14),
                label: const Text('Filter aufheben'),
                onPressed: () => onTap(aktiver!),
              ),
          ],
        ),
      ),
    );
  }
}

class _ComplianceTile extends StatelessWidget {
  const _ComplianceTile({
    required this.label,
    required this.icon,
    required this.count,
    required this.aktiv,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final int count;
  final bool aktiv;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasIssues = count > 0;
    final theme = Theme.of(context);
    // Tile mit Akzent-Hintergrund, wenn es Mängel gibt; grau, wenn alles ok.
    final bg = aktiv
        ? AppTheme.accent600
        : (hasIssues
            ? Colors.orange.withValues(alpha: 0.10)
            : theme.colorScheme.surfaceContainerHigh);
    final fg = aktiv
        ? Colors.white
        : (hasIssues
            ? Colors.orange[800]!
            : theme.colorScheme.onSurfaceVariant);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: hasIssues ? onTap : null,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: aktiv
                ? AppTheme.accent700
                : (hasIssues
                    ? Colors.orange.withValues(alpha: 0.35)
                    : theme.colorScheme.outlineVariant),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: fg,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ],
        ),
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
