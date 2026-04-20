import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'search_repository.dart';

/// Globale Suche – wird aus der Top-Bar über Lupen-Button geöffnet.
Future<void> showGlobalSearch(BuildContext context) async {
  await showDialog(
    context: context,
    builder: (_) => const _GlobalSearchDialog(),
  );
}

class _GlobalSearchDialog extends ConsumerStatefulWidget {
  const _GlobalSearchDialog();
  @override
  ConsumerState<_GlobalSearchDialog> createState() =>
      _GlobalSearchDialogState();
}

class _GlobalSearchDialogState
    extends ConsumerState<_GlobalSearchDialog> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<SearchHit> _hits = const [];
  bool _loading = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () async {
      if (!mounted) return;
      setState(() => _loading = true);
      final res = await ref.read(searchRepositoryProvider).search(q);
      if (!mounted) return;
      setState(() {
        _hits = res;
        _loading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grouped = <SearchEntity, List<SearchHit>>{};
    for (final h in _hits) {
      grouped.putIfAbsent(h.entity, () => []).add(h);
    }
    final entities = SearchEntity.values
        .where((e) => grouped.containsKey(e))
        .toList();

    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(top: 80, left: 16, right: 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _controller,
                autofocus: true,
                onChanged: _onChanged,
                style: theme.textTheme.titleMedium,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search),
                  hintText:
                      'Global suchen — Kunden, Aufträge, Rechnungen, Normen, Textbausteine …',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _controller.clear();
                            setState(() {
                              _hits = const [];
                            });
                          },
                        ),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading && _hits.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _hits.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _controller.text.length < 2
                                  ? 'Mindestens 2 Zeichen eingeben …'
                                  : 'Keine Treffer.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: entities.length,
                          itemBuilder: (_, i) {
                            final e = entities[i];
                            final items = grouped[e]!;
                            return Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.stretch,
                              children: [
                                Container(
                                  padding: const EdgeInsets.fromLTRB(
                                      16, 10, 16, 4),
                                  color: theme.colorScheme
                                      .surfaceContainerHighest,
                                  child: Text(
                                    '${e.label}  ·  ${items.length}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.8,
                                      color: theme
                                          .colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                for (final h in items)
                                  ListTile(
                                    dense: true,
                                    title: Text(h.title),
                                    subtitle: (h.subtitle ?? '').isEmpty
                                        ? null
                                        : Text(h.subtitle!),
                                    trailing: const Icon(
                                        Icons.chevron_right,
                                        size: 18),
                                    onTap: () {
                                      Navigator.of(context).pop();
                                      GoRouter.of(context).go(e.route);
                                    },
                                  ),
                                const Divider(height: 1),
                              ],
                            );
                          },
                        ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              color: theme.colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  Text(
                    '${_hits.length} Treffer · 11 Module durchsucht',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'ESC zum Schließen',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
