import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/ki_modelle.dart';
import 'einstellungen_repository.dart';

/// Einstellungssektion: Modell pro KI-Aufgabe auswählen.
class KiModelleSection extends ConsumerWidget {
  const KiModelleSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mapAsync = ref.watch(kiModellMapProvider);
    final repo = ref.watch(einstellungenRepositoryProvider);
    final scheme = Theme.of(context).colorScheme;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.psychology_alt_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Text('KI-Modell pro Funktion',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Jede KI-Funktion kann einzeln einem Modell zugeordnet werden. '
              'Flash ist günstig und schnell — Pro ist deutlich teurer, aber '
              'stärker im juristischen Denken und beim PDF-Lesen.',
              style: TextStyle(
                  fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            mapAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: LinearProgressIndicator(),
              ),
              error: (e, _) => Text('Fehler: $e'),
              data: (map) => Column(
                children: [
                  for (final aufgabe in KiAufgabe.values)
                    _AufgabeZeile(
                      aufgabe: aufgabe,
                      aktuell: map[aufgabe] ?? aufgabe.defaultModell,
                      onChanged: (neu) async {
                        await repo.set(aufgabe.settingsKey, neu);
                        ref.invalidate(kiModellMapProvider);
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Preise (Vertex AI, USD pro 1 Mio. Tokens)',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  for (final m in kiModelle)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '${m.label}: Input \$${m.preisInput.toStringAsFixed(2)} · '
                        'Output \$${m.preisOutput.toStringAsFixed(2)}',
                        style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ]),
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

class _AufgabeZeile extends StatelessWidget {
  const _AufgabeZeile({
    required this.aufgabe,
    required this.aktuell,
    required this.onChanged,
  });
  final KiAufgabe aufgabe;
  final String aktuell;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final info = kiModellInfo(aktuell);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 260,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(aufgabe.label,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                Text(info.beschreibung,
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: aktuell,
              isDense: true,
              decoration: InputDecoration(
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
              items: [
                for (final m in kiModelle)
                  DropdownMenuItem(
                    value: m.id,
                    child: Text(
                      m.label,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ],
      ),
    );
  }
}
