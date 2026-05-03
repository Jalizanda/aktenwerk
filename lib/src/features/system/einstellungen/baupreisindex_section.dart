import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../akten/lv/baupreisindex_service.dart';

/// Einstellungs-Karte für die Destatis-GENESIS-API. Speichert
/// Username + Passwort für den kostenfreien Zugang und erlaubt einen
/// Verbindungstest, der die Tabelle „Baupreisindex Wohngebäude"
/// abruft und den jüngsten Indexwert anzeigt.
class BaupreisindexSection extends ConsumerStatefulWidget {
  const BaupreisindexSection({super.key});

  @override
  ConsumerState<BaupreisindexSection> createState() =>
      _BaupreisindexSectionState();
}

class _BaupreisindexSectionState
    extends ConsumerState<BaupreisindexSection> {
  final _user = TextEditingController();
  final _pw = TextEditingController();
  bool _busy = false;
  bool _showPw = false;
  String? _error;
  String? _result;
  bool _configured = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = ref.read(baupreisindexServiceProvider);
    final ok = await svc.isConfigured();
    if (!mounted) return;
    setState(() => _configured = ok);
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      await ref.read(baupreisindexServiceProvider).setCredentials(
            _user.text.trim(),
            _pw.text,
          );
      await _load();
      if (mounted) {
        setState(() => _result = 'Zugangsdaten gespeichert.');
        _user.clear();
        _pw.clear();
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final res = await ref
          .read(baupreisindexServiceProvider)
          .aktuellerIndex();
      if (res == null) {
        setState(() =>
            _result = 'Keine Werte zurückgegeben — Tabelle leer?');
      } else {
        setState(() => _result =
            'Aktueller Index: ${res.wert.toStringAsFixed(1)} (${res.stichtag}, Wohngebäude)');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    await ref
        .read(baupreisindexServiceProvider)
        .setCredentials(null, null);
    await _load();
  }

  @override
  void dispose() {
    _user.dispose();
    _pw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                Icon(Icons.trending_up,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Baupreisindex (Destatis)',
                    style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Anbindung an die kostenfreie GENESIS-Online-API des '
              'Statistischen Bundesamtes (Tabelle 61261-0001 Wohngebäude). '
              'Damit lassen sich historische LVs und Kostenkennwerte auf '
              'das aktuelle Preisniveau hochrechnen. Account anlegen unter '
              'www-genesis.destatis.de/genesis/online → „Registrieren".',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            if (_configured) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 18),
                    SizedBox(width: 6),
                    Text('Zugangsdaten gespeichert'),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.wifi_tethering),
                    label: const Text('Verbindung testen'),
                    onPressed: _busy ? null : _test,
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.link_off, size: 16),
                    label: const Text('Trennen'),
                    onPressed: _busy ? null : _disconnect,
                  ),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _user,
                      decoration: const InputDecoration(
                        labelText: 'Benutzername',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _pw,
                      obscureText: !_showPw,
                      decoration: InputDecoration(
                        labelText: 'Passwort',
                        isDense: true,
                        suffixIcon: IconButton(
                          icon: Icon(_showPw
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () =>
                              setState(() => _showPw = !_showPw),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                icon: _busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined),
                label: const Text('Speichern'),
                onPressed: _busy ? null : _save,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(_error!,
                    style: TextStyle(
                        color: theme.colorScheme.onErrorContainer)),
              ),
            ],
            if (_result != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(_result!,
                    style: theme.textTheme.bodySmall),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
