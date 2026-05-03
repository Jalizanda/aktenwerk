import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/database/app_database.dart';
import 'versand_dialog.dart';
import 'versand_repository.dart';

/// Tab "Versand" innerhalb der Akte. Listet alle Versandvorgänge
/// (Gutachten, Stellungnahmen, Anschreiben, Rechnungen ...) chronologisch
/// und erlaubt das Erfassen neuer Versände inkl. Tracking-Nummer und
/// Anzahl Ausfertigungen.
class VersandTab extends ConsumerWidget {
  const VersandTab({super.key, required this.auftrag});
  final AuftraegeData auftrag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liste = ref.watch(versandByAuftragProvider(auftrag.id));
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.local_shipping_outlined,
                  color: AppTheme.accent600),
              const SizedBox(width: 8),
              Text('Versand-Protokoll',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Versand erfassen'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => VersandDialog(auftrag: auftrag),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Wer hat wann was bekommen — Post / Einschreiben / EGVP / E-Mail / Kurier mit Tracking-Nr. und Anzahl Ausfertigungen.',
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
                if (rows.isEmpty) return _leererZustand(context);
                return ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (_, i) =>
                      _VersandKarte(auftrag: auftrag, eintrag: rows[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _leererZustand(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_shipping_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.outlineVariant),
          const SizedBox(height: 12),
          Text('Noch keine Versände erfasst.',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Sobald Sie ein Gutachten, eine Stellungnahme oder ein Anschreiben\n'
            'an Gericht oder Beteiligte versenden, hier protokollieren.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _VersandKarte extends ConsumerWidget {
  const _VersandKarte({required this.auftrag, required this.eintrag});
  final AuftraegeData auftrag;
  final VersandData eintrag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = DateFormat('dd.MM.yyyy', 'de');
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) =>
              VersandDialog(auftrag: auftrag, versand: eintrag),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _artChip(eintrag.art),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(fmt.format(eintrag.datum),
                            style: Theme.of(context).textTheme.bodySmall),
                        if ((eintrag.empfaenger ?? '').isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '→ ${eintrag.empfaenger}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if ((eintrag.bezugBezeichnung ?? '').isNotEmpty ||
                        (eintrag.betreff ?? '').isNotEmpty)
                      Text(
                        eintrag.bezugBezeichnung ?? eintrag.betreff!,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    Wrap(
                      spacing: 12,
                      children: [
                        if (eintrag.anzahlAusfertigungen != null &&
                            eintrag.anzahlAusfertigungen! > 0)
                          _meta(context, Icons.copy_all_outlined,
                              '${eintrag.anzahlAusfertigungen} Ausf.'),
                        if ((eintrag.trackingNr ?? '').isNotEmpty)
                          _meta(context, Icons.qr_code_outlined,
                              eintrag.trackingNr!),
                      ],
                    ),
                  ],
                ),
              ),
              _statusChip(eintrag.status),
            ],
          ),
        ),
      ),
    );
  }

  Widget _meta(BuildContext context, IconData ic, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(ic, size: 13, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 3),
        Text(text, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _artChip(String? art) {
    final label = switch (art) {
      'einschreiben' => 'Einschreiben',
      'einschreiben_rs' => 'E.B. Rückschein',
      'post' => 'Post',
      'egvp' => 'EGVP/beA',
      'email' => 'E-Mail',
      'kurier' => 'Kurier',
      'persoenlich' => 'Persönlich',
      _ => 'Versand',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.accent50,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.accent700)),
    );
  }

  Widget _statusChip(String? status) {
    final (label, color) = switch (status) {
      'zugestellt' => ('zugestellt', Colors.green),
      'unzustellbar' => ('unzustellbar', Colors.red),
      _ => ('versendet', Colors.blue),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}
