import 'package:flutter/material.dart';

/// Einheitliche Modul-Kopfzeile mit Icon, Titel, globaler Suche und Toolbar.
///
/// Die **zentrale Suche** rechts neben dem Titel wirkt als Live-Filter auf
/// die darunter liegende Tabelle — jedes Modul implementiert den Filter
/// selbst in seinem StateProvider und setzt `searchHint` / `onSearchChanged`.
class ModuleHeader extends StatefulWidget {
  const ModuleHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actions = const <Widget>[],
    this.filters = const <Widget>[],
    this.searchHint,
    this.onSearchChanged,
    this.searchInitial,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> filters;

  /// Wenn gesetzt, erscheint rechts neben dem Titel ein Suchfeld.
  final String? searchHint;

  /// Wird bei jeder Eingabe aufgerufen.
  final ValueChanged<String>? onSearchChanged;

  /// Vorbelegung des Suchfeldes.
  final String? searchInitial;

  @override
  State<ModuleHeader> createState() => _ModuleHeaderState();
}

class _ModuleHeaderState extends State<ModuleHeader> {
  late final TextEditingController _searchCtrl =
      TextEditingController(text: widget.searchInitial ?? '');

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(widget.icon, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        style: Theme.of(context).textTheme.headlineSmall),
                    if (widget.subtitle != null)
                      Text(widget.subtitle!,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  )),
                  ],
                ),
              ),
              if (widget.searchHint != null) ...[
                const SizedBox(width: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search, size: 18),
                      hintText: widget.searchHint,
                      suffixIcon: _searchCtrl.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                _searchCtrl.clear();
                                widget.onSearchChanged?.call('');
                                setState(() {});
                              },
                            ),
                    ),
                    onChanged: (v) {
                      widget.onSearchChanged?.call(v);
                      setState(() {}); // damit Clear-Icon ein-/ausblendet
                    },
                  ),
                ),
                const SizedBox(width: 12),
              ],
              for (final a in widget.actions) ...[
                const SizedBox(width: 8),
                a
              ],
            ],
          ),
          if (widget.filters.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: widget.filters,
            ),
          ],
        ],
      ),
    );
  }
}

/// Card um eine DataTable (konsistenter Look für alle Listen).
class DataTableCard extends StatelessWidget {
  const DataTableCard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: child,
        ),
      ),
    );
  }
}
