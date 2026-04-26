import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/aw_tokens.dart';
import '../../../data/database/app_database.dart';
import '../../../shared/widgets/badges.dart';
import '../auftraege/auftraege_repository.dart';
import 'kunden_form.dart';
import 'kunden_repository.dart';

class KundenScreen extends ConsumerWidget {
  const KundenScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(kundenListProvider);
    final filter = ref.watch(kundenFilterProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Toolbar(filter: filter),
        const Divider(height: 1),
        Expanded(
          child: async.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Fehler beim Laden: $e'),
              ),
            ),
            data: (items) => items.isEmpty
                ? _EmptyState(hasFilter: _hasFilter(filter))
                : _KundenTable(items: items),
          ),
        ),
      ],
    );
  }

  bool _hasFilter(KundenFilter f) => f.query.isNotEmpty || f.typ != null;
}

class _Toolbar extends ConsumerStatefulWidget {
  const _Toolbar({required this.filter});
  final KundenFilter filter;

  @override
  ConsumerState<_Toolbar> createState() => _ToolbarState();
}

class _ToolbarState extends ConsumerState<_Toolbar> {
  late final _queryController =
      TextEditingController(text: widget.filter.query);

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 720;
    final search = TextField(
      controller: _queryController,
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: const Icon(Icons.search, size: 20),
        hintText: 'Suche Name, Firma, Ort, PLZ, E-Mail',
        suffixIcon: widget.filter.query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () {
                  _queryController.clear();
                  ref
                      .read(kundenFilterProvider.notifier)
                      .update((f) => f.copyWith(query: ''));
                },
              ),
      ),
      onChanged: (v) => ref
          .read(kundenFilterProvider.notifier)
          .update((f) => f.copyWith(query: v)),
    );

    if (isMobile) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.people_outline,
                    size: 18, color: AwTokens.orange),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Auftraggeber',
                      style: Theme.of(context).textTheme.headlineSmall),
                ),
                FilledButton.icon(
                  onPressed: () => showKundenFormDialog(context),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Neu'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            search,
            const SizedBox(height: 8),
            DropdownButtonHideUnderline(
              child: DropdownButton<KundenTyp?>(
                isExpanded: true,
                value: widget.filter.typ,
                hint: const Text('Alle Typen'),
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text('Alle Typen')),
                  for (final t in KundenTyp.values)
                    DropdownMenuItem(value: t, child: Text(t.label)),
                ],
                onChanged: (t) =>
                    ref.read(kundenFilterProvider.notifier).update((f) =>
                        t == null
                            ? f.copyWith(clearTyp: true)
                            : f.copyWith(typ: t)),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        children: [
          const Icon(Icons.people_outline, size: 22, color: AwTokens.orange),
          const SizedBox(width: 10),
          Text('Auftraggeber',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(width: 24),
          SizedBox(
            width: 320,
            child: search,
          ),
          const SizedBox(width: 12),
          DropdownButtonHideUnderline(
            child: DropdownButton<KundenTyp?>(
              value: widget.filter.typ,
              hint: const Text('Alle Typen'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Alle Typen')),
                for (final t in KundenTyp.values)
                  DropdownMenuItem(value: t, child: Text(t.label)),
              ],
              onChanged: (t) =>
                  ref.read(kundenFilterProvider.notifier).update((f) =>
                      t == null
                          ? f.copyWith(clearTyp: true)
                          : f.copyWith(typ: t)),
            ),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: () => showKundenFormDialog(context),
            icon: const Icon(Icons.add),
            label: const Text('Neuer Auftraggeber'),
          ),
        ],
      ),
    );
  }
}

class _KundenTable extends ConsumerStatefulWidget {
  const _KundenTable({required this.items});
  final List<KundenData> items;
  @override
  ConsumerState<_KundenTable> createState() => _KundenTableState();
}

class _KundenTableState extends ConsumerState<_KundenTable> {
  final Set<int> _expanded = {};

  List<KundenData> get _sorted {
    final list = [...widget.items];
    list.sort((a, b) =>
        kundeAnzeigename(a).toLowerCase().compareTo(
            kundeAnzeigename(b).toLowerCase()));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final sorted = _sorted;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: sorted.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final k = sorted[i];
        final expanded = _expanded.contains(k.id);
        return Container(
          decoration: BoxDecoration(
            color: AwTokens.white,
            borderRadius: BorderRadius.circular(AwTokens.radiusLg),
            border: Border.all(color: AwTokens.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: () => setState(() {
                  if (expanded) {
                    _expanded.remove(k.id);
                  } else {
                    _expanded.add(k.id);
                  }
                }),
                child: Padding(
                  padding:
                      const EdgeInsets.fromLTRB(14, 12, 6, 12),
                  child: Row(
                    children: [
                      _TypBadge(typ: KundenTypX.fromDb(k.typ)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              kundeAnzeigename(k),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AwTokens.ink,
                                height: 1.2,
                              ),
                            ),
                            if ((k.ort ?? '').isNotEmpty ||
                                (k.plz ?? '').isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  [k.plz, k.ort]
                                      .whereType<String>()
                                      .where((s) => s.isNotEmpty)
                                      .join(' '),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AwTokens.mute,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Bearbeiten',
                        icon:
                            const Icon(Icons.edit_outlined, size: 18),
                        color: AwTokens.mute,
                        onPressed: () =>
                            showKundenFormDialog(context, kunde: k),
                      ),
                      IconButton(
                        tooltip: 'Löschen',
                        icon: const Icon(Icons.delete_outline,
                            size: 18),
                        color: AwTokens.mute,
                        onPressed: () => _confirmDelete(context, ref, k),
                      ),
                      AnimatedRotation(
                        duration: const Duration(milliseconds: 180),
                        turns: expanded ? 0.5 : 0,
                        child: const Icon(
                          Icons.expand_more,
                          size: 20,
                          color: AwTokens.mute,
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              ),
              if (expanded)
                _KundeDetail(kunde: k),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, KundenData k) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Auftraggeber löschen?'),
        content: Text(
            '«${kundeAnzeigename(k)}» wird dauerhaft gelöscht.\n'
            'Verknüpfte Aufträge verlieren die Referenz.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(kundenRepositoryProvider).delete(k.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('«${kundeAnzeigename(k)}» gelöscht')),
        );
      }
    }
  }
}

/// Aufklappbarer Detail-Bereich pro Auftraggeber: Adresse, Kontakt,
/// Liste aller verknüpften Akten mit Kurzinfo + Sprung-Link.
class _KundeDetail extends ConsumerWidget {
  const _KundeDetail({required this.kunde});
  final KundenData kunde;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adresse = [
      kunde.strasse,
      [kunde.plz, kunde.ort]
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .join(' '),
      kunde.land,
    ].whereType<String>().where((s) => s.isNotEmpty).join('\n');

    return Container(
      decoration: const BoxDecoration(
        color: AwTokens.paper,
        border: Border(top: BorderSide(color: AwTokens.line)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Adresse + Kontakt-Block (zweispaltig auf Desktop, gestapelt auf Mobile)
          LayoutBuilder(builder: (ctx, c) {
            final wide = c.maxWidth > 600;
            final adresseW = _Block(
              label: 'ANSCHRIFT',
              child: Text(
                adresse.isEmpty ? '—' : adresse,
                style: const TextStyle(
                    fontSize: 13, color: AwTokens.ink, height: 1.4),
              ),
            );
            final kontaktW = _Block(
              label: 'KONTAKT',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((kunde.telefon ?? '').isNotEmpty)
                    _KontaktZeile(
                        icon: Icons.phone_outlined, text: kunde.telefon!),
                  if ((kunde.mobil ?? '').isNotEmpty)
                    _KontaktZeile(
                        icon: Icons.smartphone_outlined,
                        text: kunde.mobil!),
                  if ((kunde.email ?? '').isNotEmpty)
                    _KontaktZeile(
                        icon: Icons.mail_outline, text: kunde.email!),
                  if ((kunde.telefon ?? '').isEmpty &&
                      (kunde.mobil ?? '').isEmpty &&
                      (kunde.email ?? '').isEmpty)
                    const Text('—',
                        style: TextStyle(
                            fontSize: 13, color: AwTokens.mute)),
                ],
              ),
            );
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: adresseW),
                  const SizedBox(width: 16),
                  Expanded(child: kontaktW),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                adresseW,
                const SizedBox(height: 10),
                kontaktW,
              ],
            );
          }),
          const SizedBox(height: 12),
          // Akten-Liste
          _AktenFuerKunde(kundeId: kunde.id),
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.label, required this.child});
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 10 * 0.08,
            color: AwTokens.mute,
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

class _KontaktZeile extends StatelessWidget {
  const _KontaktZeile({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 13, color: AwTokens.mute),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, color: AwTokens.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _AktenFuerKunde extends ConsumerWidget {
  const _AktenFuerKunde({required this.kundeId});
  final int kundeId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(auftraegeListProvider).valueOrNull ??
        const <AuftragWithKunde>[];
    final akten =
        all.where((a) => a.auftrag.kundeId == kundeId).toList()
          ..sort((a, b) =>
              b.auftrag.createdAt.compareTo(a.auftrag.createdAt));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'AKTEN',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 10 * 0.08,
                color: AwTokens.mute,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: AwTokens.orangeSoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${akten.length}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AwTokens.orange,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (akten.isEmpty)
          const Text(
            'Keine Akten verknüpft.',
            style: TextStyle(
              fontSize: 12.5,
              color: AwTokens.mute,
              fontStyle: FontStyle.italic,
            ),
          )
        else
          for (final a in akten)
            _AkteRow(eintrag: a),
      ],
    );
  }
}

class _AkteRow extends StatelessWidget {
  const _AkteRow({required this.eintrag});
  final AuftragWithKunde eintrag;
  @override
  Widget build(BuildContext context) {
    final a = eintrag.auftrag;
    final betreff = (a.bezeichnung ?? '').isEmpty
        ? '(ohne Betreff)'
        : a.bezeichnung!;
    final adr = [
      a.objektStrasse,
      [a.objektPlz, a.objektOrt]
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .join(' '),
    ].whereType<String>().where((s) => s.isNotEmpty).join(', ');
    return InkWell(
      onTap: () => context.go('/akte/${a.id}'),
      borderRadius: BorderRadius.circular(AwTokens.radiusMd),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AwTokens.white,
          border: Border.all(color: AwTokens.line),
          borderRadius: BorderRadius.circular(AwTokens.radiusMd),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 96,
              child: Text(
                a.aktenzeichen ?? '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AwTokens.orange,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    betreff,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AwTokens.ink,
                    ),
                  ),
                  if (adr.isNotEmpty)
                    Text(
                      adr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AwTokens.mute,
                      ),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                size: 18, color: AwTokens.mute),
          ],
        ),
      ),
    );
  }
}

class _TypBadge extends StatelessWidget {
  const _TypBadge({required this.typ});
  final KundenTyp typ;

  @override
  Widget build(BuildContext context) {
    // Farbpalette 1:1 aus der Original-SV-Software (.badge-priv etc.).
    final (bg, fg) = switch (typ) {
      KundenTyp.privat => (BadgeColors.indigoBg, BadgeColors.indigoFg),
      KundenTyp.firma => (BadgeColors.amberBg, BadgeColors.amberFg),
      KundenTyp.anwalt => (BadgeColors.blueBg, BadgeColors.blueFg),
      KundenTyp.gericht => (BadgeColors.redBg, BadgeColors.redFg),
      KundenTyp.versicherung => (BadgeColors.greenBg, BadgeColors.greenFg),
      KundenTyp.behoerde => (BadgeColors.slateBg, BadgeColors.slateFg),
    };
    return PillBadge(text: typ.label, background: bg, foreground: fg);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasFilter});
  final bool hasFilter;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline,
                size: 64,
                color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              hasFilter
                  ? 'Keine Treffer für diesen Filter'
                  : 'Noch keine Auftraggeber erfasst',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (!hasFilter)
              Text(
                'Lege oben rechts deinen ersten Auftraggeber an.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
          ],
        ),
      ),
    );
  }
}
