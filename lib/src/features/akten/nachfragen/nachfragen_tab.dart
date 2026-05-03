import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/database/app_database.dart';
import 'nachfragen_repository.dart';
import 'nachfragen_dialog.dart';

/// Tab "Nachfragen" innerhalb der Akte. Zeigt alle gerichtlichen / anwaltlichen
/// Schriftsätze mit Nachfragen zum Gutachten und erlaubt das Anlegen einer
/// nummerierten Stellungnahme + Druck als Ergänzungs-Stellungnahme-PDF.
class NachfragenTab extends ConsumerWidget {
  const NachfragenTab({super.key, required this.auftrag});
  final AuftraegeData auftrag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liste = ref.watch(nachfragenByAuftragProvider(auftrag.id));
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.help_outline, color: AppTheme.accent600),
              const SizedBox(width: 8),
              Text(
                'Nachfragen zum Gutachten',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Neuer Schriftsatz'),
                onPressed: () => _oeffneEditor(context, ref, null),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Schriftsätze mit Fragen zum bereits erstellten Gutachten — '
            'Antworten werden zu einer „Ergänzenden Stellungnahme" zusammengefasst.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: liste.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Fehler: $e')),
              data: (rows) {
                if (rows.isEmpty) {
                  return _leererZustand(context, ref);
                }
                return ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _SchriftsatzKarte(
                    auftrag: auftrag,
                    rueckfrage: rows[i],
                    onOeffnen: () => _oeffneEditor(context, ref, rows[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _leererZustand(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.help_outline,
              size: 56, color: Theme.of(context).colorScheme.outlineVariant),
          const SizedBox(height: 12),
          Text('Noch keine Nachfragen erfasst.',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Sobald das Gericht oder ein Anwalt Fragen zum Gutachten stellt,\n'
            'können Sie hier den Schriftsatz erfassen und beantworten.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Ersten Schriftsatz erfassen'),
            onPressed: () => _oeffneEditor(context, ref, null),
          ),
        ],
      ),
    );
  }

  Future<void> _oeffneEditor(
    BuildContext context,
    WidgetRef ref,
    RueckfragenData? r,
  ) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => NachfragenDialog(auftrag: auftrag, rueckfrage: r),
    );
  }
}

class _SchriftsatzKarte extends ConsumerWidget {
  const _SchriftsatzKarte({
    required this.auftrag,
    required this.rueckfrage,
    required this.onOeffnen,
  });
  final AuftraegeData auftrag;
  final RueckfragenData rueckfrage;
  final VoidCallback onOeffnen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = DateFormat('dd.MM.yyyy', 'de');
    final fragen = decodeFragen(rueckfrage.fragenJson);
    final beantwortet =
        fragen.where((f) => f.antwort.trim().isNotEmpty).length;
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onOeffnen,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _stellerChip(rueckfrage.stellerArt, rueckfrage.stellerName),
                  const SizedBox(width: 8),
                  if (rueckfrage.schriftsatzVom != null)
                    Text(
                      'Schriftsatz vom ${fmt.format(rueckfrage.schriftsatzVom!)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  const Spacer(),
                  _statusChip(rueckfrage.status),
                ],
              ),
              const SizedBox(height: 6),
              if ((rueckfrage.betreff ?? '').isNotEmpty)
                Text(
                  rueckfrage.betreff!,
                  style: theme.textTheme.titleSmall,
                ),
              const SizedBox(height: 4),
              if (fragen.isNotEmpty)
                Row(
                  children: [
                    Icon(Icons.checklist_rtl,
                        size: 14, color: theme.colorScheme.outline),
                    const SizedBox(width: 4),
                    Text(
                      '$beantwortet / ${fragen.length} Fragen beantwortet',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                )
              else if ((rueckfrage.frage ?? '').isNotEmpty)
                Text(
                  rueckfrage.frage!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stellerChip(String? art, String? name) {
    final label = switch (art) {
      'gericht' => 'Gericht',
      'anwalt_klaeger' => 'Anwalt Kläger',
      'anwalt_beklagter' => 'Anwalt Beklagter',
      'auftraggeber' => 'Auftraggeber',
      'versicherung' => 'Versicherung',
      _ => 'Sonstiges',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.accent50,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        (name ?? '').isNotEmpty ? '$label · $name' : label,
        style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppTheme.accent700),
      ),
    );
  }

  Widget _statusChip(String? status) {
    final (label, color) = switch (status) {
      'beantwortet' => ('beantwortet', Colors.green),
      'versendet' => ('versendet', Colors.blue),
      'in_bearbeitung' => ('in Bearbeitung', Colors.orange),
      _ => ('offen', Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}
