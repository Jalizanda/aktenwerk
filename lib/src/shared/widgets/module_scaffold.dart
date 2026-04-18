import 'package:flutter/material.dart';

/// Einheitliche Modul-Kopfzeile mit Icon, Titel und Toolbar.
class ModuleHeader extends StatelessWidget {
  const ModuleHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actions = const <Widget>[],
    this.filters = const <Widget>[],
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> filters;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context).textTheme.headlineSmall),
                    if (subtitle != null)
                      Text(subtitle!,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  )),
                  ],
                ),
              ),
              for (final a in actions) ...[const SizedBox(width: 8), a],
            ],
          ),
          if (filters.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: filters,
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
