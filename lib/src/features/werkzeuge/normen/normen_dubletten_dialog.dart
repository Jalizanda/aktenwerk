import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/aw_tokens.dart';
import '../../../data/database/app_database.dart';
import 'normen_repository.dart';
import 'normen_screen.dart';

/// Gruppe von erkannten Dubletten
class NormDublettenGruppe {
  NormDublettenGruppe({
    required this.schluessel,
    required this.anzeigeTitel,
    required this.eintraege,
  });

  final String schluessel;
  final String anzeigeTitel;
  final List<NormenData> eintraege;
}

/// Dialog zur automatischen Erkennung & Bereinigung von Dokumenten-Dubletten in der Bibliothek
class NormenDublettenDialog extends ConsumerStatefulWidget {
  const NormenDublettenDialog({super.key});

  @override
  ConsumerState<NormenDublettenDialog> createState() =>
      _NormenDublettenDialogState();
}

class _NormenDublettenDialogState
    extends ConsumerState<NormenDublettenDialog> {
  final Set<int> _ausgewaehltZumLoeschen = {};
  bool _loescht = false;

  List<NormDublettenGruppe> _berechneDubletten(List<NormenData> normen) {
    final gruppenMap = <String, List<NormenData>>{};

    for (final n in normen) {
      final tClean =
          (n.titel ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final ausgabeClean = (n.ausgabe ?? '').replaceAll(RegExp(r'[^0-9]'), '');

      // Schlüssel aus normalisiertem Titel + Ausgabe (oder Titel allein bei langem Titel)
      String key;
      if (tClean.length >= 10) {
        key = tClean;
      } else {
        final nrClean =
            n.nummer.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        key = '${nrClean}_$ausgabeClean';
      }

      if (key.trim().isEmpty) continue;

      gruppenMap.putIfAbsent(key, () => []).add(n);
    }

    final ergebnis = <NormDublettenGruppe>[];

    for (final entry in gruppenMap.entries) {
      if (entry.value.length > 1) {
        // Sortieren: Ältester / Vollständigster Eintrag zuerst (Original behalten)
        final sortierte = [...entry.value]..sort((a, b) {
            final aHasPdf =
                a.pdfStorageUrl != null && a.pdfStorageUrl!.isNotEmpty ? 1 : 0;
            final bHasPdf =
                b.pdfStorageUrl != null && b.pdfStorageUrl!.isNotEmpty ? 1 : 0;
            if (aHasPdf != bHasPdf) return bHasPdf.compareTo(aHasPdf);
            return a.id.compareTo(b.id);
          });

        ergebnis.add(NormDublettenGruppe(
          schluessel: entry.key,
          anzeigeTitel: sortierte.first.titel ?? sortierte.first.nummer,
          eintraege: sortierte,
        ));
      }
    }

    return ergebnis;
  }

  Future<void> _bereinigen() async {
    if (_ausgewaehltZumLoeschen.isEmpty || _loescht) return;
    setState(() => _loescht = true);
    try {
      final repo = ref.read(normenRepositoryProvider);
      int geloescht = 0;
      for (final id in _ausgewaehltZumLoeschen) {
        await repo.delete(id);
        geloescht++;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$geloescht Dubletten erfolgreich entfernt.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Löschen: $e')),
        );
        setState(() => _loescht = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final normenAsync = ref.watch(normenListProvider);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 850, maxHeight: 750),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.copy_rounded, color: AwTokens.orange, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Dubletten-Prüfung & Bereinigung',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Prüft die Bibliothek auf inhaltlich oder titelgleiche Mehrfacheinträge. Das älteste/vollständigste Dokument bleibt erhalten.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const Divider(height: 24),
              Expanded(
                child: normenAsync.when(
                  loading: () => const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('Durchsuche Bibliothek nach Dubletten …'),
                      ],
                    ),
                  ),
                  error: (err, _) => Center(
                    child: Text('Fehler beim Laden: $err'),
                  ),
                  data: (normen) {
                    final gruppen = _berechneDubletten(normen);

                    // Standard-Vorauswahl: Alle außer dem 1. Eintrag jeder Gruppe
                    if (_ausgewaehltZumLoeschen.isEmpty) {
                      for (final g in gruppen) {
                        for (int i = 1; i < g.eintraege.length; i++) {
                          _ausgewaehltZumLoeschen.add(g.eintraege[i].id);
                        }
                      }
                    }

                    if (gruppen.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle_outline,
                                size: 48, color: Colors.green),
                            const SizedBox(height: 12),
                            Text(
                              'Keine Dubletten gefunden!',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 4),
                            const Text(
                                'Jedes Dokument in der Bibliothek liegt nur einmal vor.'),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      itemCount: gruppen.length,
                      itemBuilder: (context, gIndex) {
                        final gruppe = gruppen[gIndex];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(color: scheme.outlineVariant),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AwTokens.orange
                                            .withValues(alpha: 0.15),
                                        borderRadius:
                                            BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '${gruppe.eintraege.length}× vorhanden',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: AwTokens.orange,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        gruppe.anzeigeTitel,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                for (int i = 0;
                                    i < gruppe.eintraege.length;
                                    i++) ...[
                                  _buildNormItemRow(gruppe.eintraege[i],
                                      isHauptEintrag: i == 0),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  if (normenAsync.valueOrNull != null &&
                      _berechneDubletten(normenAsync.value!).isNotEmpty)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AwTokens.red,
                      ),
                      icon: _loescht
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.delete_sweep_outlined, size: 18),
                      label: Text(
                          '${_ausgewaehltZumLoeschen.length} Dublette(n) löschen'),
                      onPressed: _ausgewaehltZumLoeschen.isEmpty || _loescht
                          ? null
                          : _bereinigen,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNormItemRow(NormenData item, {required bool isHauptEintrag}) {
    final theme = Theme.of(context);
    final isSelected = _ausgewaehltZumLoeschen.contains(item.id);

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isHauptEintrag
            ? Colors.green.withValues(alpha: 0.08)
            : isSelected
                ? AwTokens.red.withValues(alpha: 0.06)
                : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isHauptEintrag
              ? Colors.green.withValues(alpha: 0.3)
              : isSelected
                  ? AwTokens.red.withValues(alpha: 0.3)
                  : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          if (isHauptEintrag)
            const Tooltip(
              message: 'Original / Hauptdokument (bleibt erhalten)',
              child: Icon(Icons.check_circle, color: Colors.green, size: 18),
            )
          else
            Checkbox(
              value: isSelected,
              activeColor: AwTokens.red,
              onChanged: (val) {
                setState(() {
                  if (val == true) {
                    _ausgewaehltZumLoeschen.add(item.id);
                  } else {
                    _ausgewaehltZumLoeschen.remove(item.id);
                  }
                });
              },
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      item.nummer,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Ausgabe: ${formatAusgabeJahr(item.ausgabe)}',
                      style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                if (item.titel != null)
                  Text(
                    item.titel!,
                    style: const TextStyle(fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (isHauptEintrag)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Behalten',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.green),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AwTokens.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Dublette',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AwTokens.red),
              ),
            ),
        ],
      ),
    );
  }
}
