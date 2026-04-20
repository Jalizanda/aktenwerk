import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/seed/demo_seed.dart';
import '../../../data/sync/auth_service.dart';
import '../../../data/sync/sync_service.dart';

class DemoSeedSection extends ConsumerStatefulWidget {
  const DemoSeedSection({super.key});
  @override
  ConsumerState<DemoSeedSection> createState() => _DemoSeedSectionState();
}

class _DemoSeedSectionState extends ConsumerState<DemoSeedSection> {
  bool _busy = false;
  DemoSeedReport? _lastReport;
  String? _lastMode;
  String? _error;

  Future<void> _run({required bool withCloud}) async {
    final title = withCloud
        ? 'Alles löschen, Demodaten laden & in die Cloud spiegeln?'
        : 'Alles löschen und Demodaten lokal laden?';
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogCtx) => AlertDialog(
        title: Text(title),
        content: Text(
          withCloud
              ? 'Alle lokalen Einträge werden ersetzt. Anschließend '
                  'werden sämtliche Demo-Daten in deine aktive '
                  'Organisation unter organizations/{orgId}/... hochgeladen.'
              : 'Alle bestehenden Einträge (Kunden, Aufträge, '
                  'Rechnungen, …) werden unwiderruflich gelöscht und '
                  'durch den Demo-Seed der SV-Software ersetzt.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor:
                    Theme.of(dialogCtx).colorScheme.error),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child:
                Text(withCloud ? 'Laden + Cloud-Push' : 'Löschen + Laden'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _busy = true;
      _error = null;
      _lastReport = null;
      _lastMode = withCloud ? 'cloud' : 'lokal';
    });
    try {
      final seeder = ref.read(demoSeederProvider);
      final report = withCloud
          ? await seeder.loadAllAndSync()
          : await seeder.loadAll();
      if (mounted) setState(() => _lastReport = report);
    } catch (e, _) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = ref.watch(authStateProvider);
    final sync = ref.watch(syncServiceProvider);
    final cloudReady = sync.enabled && auth.valueOrNull != null;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.refresh, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Demodaten', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Lädt den kompletten Demo-Seed aus der Original-SV-Software: '
              '10 Kunden, 10 Aufträge, Rechnungen, Angebote, Gutachten, '
              'Stunden, Auslagen, 88 Textbausteine, 26 Normen, '
              '27 Eingangsrechnungen, 25 Artikel, 3 Dokumente und mehr.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : () => _run(withCloud: false),
                  icon: _busy && _lastMode != 'cloud'
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh),
                  label: const Text('Alles löschen & lokal laden'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _busy || !cloudReady
                      ? null
                      : () => _run(withCloud: true),
                  icon: _busy && _lastMode == 'cloud'
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.cloud_upload_outlined),
                  label: Text(cloudReady
                      ? 'Lokal + Cloud (Firestore)'
                      : 'Cloud: bitte erst anmelden'),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!,
                    style: TextStyle(
                        color: theme.colorScheme.onErrorContainer)),
              ),
            ],
            if (_lastReport != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _lastReport.toString(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
