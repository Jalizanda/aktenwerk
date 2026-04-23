import 'package:flutter/material.dart';

import '../../data/seed/gerichte.dart';

/// Öffnet einen Modal-Dialog zur Auswahl eines Gerichts aus der
/// [GerichteRepository]-Liste (158 deutsche Gerichte). Gibt das
/// ausgewählte [Gericht] zurück oder `null` bei Abbruch.
Future<Gericht?> showGerichtPicker(BuildContext context) {
  return showDialog<Gericht>(
    context: context,
    useRootNavigator: true,
    builder: (_) => const _GerichtPicker(),
  );
}

class _GerichtPicker extends StatefulWidget {
  const _GerichtPicker();
  @override
  State<_GerichtPicker> createState() => _GerichtPickerState();
}

class _GerichtPickerState extends State<_GerichtPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Text('Gericht auswählen',
                      style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: true).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 20),
                  hintText: 'Name, Ort, PLZ, Typ …',
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Gericht>>(
                future: GerichteRepository.instance.search(_query),
                builder: (_, snap) {
                  final items = snap.data ?? const <Gericht>[];
                  if (snap.connectionState == ConnectionState.waiting &&
                      items.isEmpty) {
                    return const Center(
                        child: CircularProgressIndicator());
                  }
                  if (items.isEmpty) {
                    return const Center(child: Text('Keine Treffer'));
                  }
                  return ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final g = items[i];
                      return ListTile(
                        dense: true,
                        leading: Text(
                          g.typ,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color:
                                Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        title: Text(g.name),
                        subtitle: Text(
                            '${g.strasse} · ${g.plz} ${g.ort} · ${g.telefon}'),
                        onTap: () =>
                            Navigator.of(context, rootNavigator: true)
                                .pop(g),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
