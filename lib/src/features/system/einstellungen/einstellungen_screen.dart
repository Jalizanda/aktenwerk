import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync/sync_section.dart';
import 'einstellungen_repository.dart';

class EinstellungenScreen extends ConsumerWidget {
  const EinstellungenScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(einstellungenProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (map) =>
          _EinstellungenForm(key: ValueKey(map.length), values: map),
    );
  }
}

class _EinstellungenForm extends ConsumerStatefulWidget {
  const _EinstellungenForm({super.key, required this.values});
  final Map<String, String> values;

  @override
  ConsumerState<_EinstellungenForm> createState() =>
      _EinstellungenFormState();
}

class _EinstellungenFormState
    extends ConsumerState<_EinstellungenForm> {
  late final _akt = _tec(SettingsKeys.nummernkreisAktenzeichen, 'YYYY/####');
  late final _rn = _tec(SettingsKeys.nummernkreisRechnung, 'YYYY-####');
  late final _ang = _tec(SettingsKeys.nummernkreisAngebot, 'A-YYYY-####');
  late final _satz = _tec(SettingsKeys.standardStundensatz, '95');
  late final _ust = _tec(SettingsKeys.standardUstSatz, '19');
  late final _rnFoot = _tec(SettingsKeys.rechnungFusstext, '');
  late final _angFoot = _tec(SettingsKeys.angebotFusstext, '');

  String _theme = 'system';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _theme = widget.values[SettingsKeys.theme] ?? 'system';
  }

  TextEditingController _tec(String key, String fallback) {
    final v = widget.values[key];
    return TextEditingController(text: v != null && v.isNotEmpty ? v : fallback);
  }

  @override
  void dispose() {
    for (final c in [_akt, _rn, _ang, _satz, _ust, _rnFoot, _angFoot]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final repo = ref.read(einstellungenRepositoryProvider);
    await repo.set(SettingsKeys.nummernkreisAktenzeichen, _akt.text.trim());
    await repo.set(SettingsKeys.nummernkreisRechnung, _rn.text.trim());
    await repo.set(SettingsKeys.nummernkreisAngebot, _ang.text.trim());
    await repo.set(SettingsKeys.standardStundensatz, _satz.text.trim());
    await repo.set(SettingsKeys.standardUstSatz, _ust.text.trim());
    await repo.set(SettingsKeys.rechnungFusstext, _rnFoot.text.trim());
    await repo.set(SettingsKeys.angebotFusstext, _angFoot.text.trim());
    await repo.set(SettingsKeys.theme, _theme);
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Einstellungen gespeichert')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          child: Row(
            children: [
              const Icon(Icons.tune_outlined, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Einstellungen',
                        style: theme.textTheme.headlineMedium),
                    Text(
                      'Nummernkreise, Standardwerte, Erscheinungsbild',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined),
                label: const Text('Speichern'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Section('Nummernkreise', children: [
                    _L(
                      'Aktenzeichen',
                      _InfoField(
                        hint: 'Platzhalter: YYYY = Jahr, ### = laufende Nummer',
                        child: TextField(controller: _akt),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _Row2(
                      left: _L('Rechnungsnummer',
                          TextField(controller: _rn)),
                      right: _L('Angebotsnummer',
                          TextField(controller: _ang)),
                    ),
                  ]),
                  _Section('Standardwerte', children: [
                    _Row2(
                      left: _L(
                        'Standard-Stundensatz (€)',
                        TextField(
                          controller: _satz,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                        ),
                      ),
                      right: _L(
                        'Standard-USt-Satz (%)',
                        TextField(
                          controller: _ust,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                        ),
                      ),
                    ),
                  ]),
                  _Section('Erscheinungsbild', children: [
                    _L(
                      'Theme',
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'system', label: Text('System')),
                          ButtonSegment(value: 'light', label: Text('Hell')),
                          ButtonSegment(value: 'dark', label: Text('Dunkel')),
                        ],
                        selected: {_theme},
                        showSelectedIcon: false,
                        onSelectionChanged: (s) =>
                            setState(() => _theme = s.first),
                      ),
                    ),
                  ]),
                  _Section('Fußtexte', children: [
                    _L(
                      'Fußtext Rechnung',
                      TextField(
                          controller: _rnFoot, minLines: 3, maxLines: 6),
                    ),
                    const SizedBox(height: 12),
                    _L(
                      'Fußtext Angebot',
                      TextField(
                          controller: _angFoot, minLines: 3, maxLines: 6),
                    ),
                  ]),
                  _Section('Cloud', children: const [SyncSection()]),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, {required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      );
}

class _L extends StatelessWidget {
  const _L(this.label, this.child);
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
          ),
          child,
        ],
      );
}

class _Row2 extends StatelessWidget {
  const _Row2({required this.left, required this.right});
  final Widget left;
  final Widget right;
  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: left),
          const SizedBox(width: 12),
          Expanded(child: right),
        ],
      );
}

class _InfoField extends StatelessWidget {
  const _InfoField({required this.hint, required this.child});
  final String hint;
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          child,
          const SizedBox(height: 4),
          Text(hint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  )),
        ],
      );
}
