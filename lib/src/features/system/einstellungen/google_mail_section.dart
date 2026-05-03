import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/sync/google_mail_service.dart';

/// Einstellungs-Karte für die Gmail-Integration. Phase 1: Verbinden zum
/// Senden mit Anhang. Phase 2 (geplant): zusätzlicher Lesescope für
/// automatischen Eingangsmail-Import.
class GoogleMailSection extends ConsumerStatefulWidget {
  const GoogleMailSection({super.key});

  @override
  ConsumerState<GoogleMailSection> createState() => _GoogleMailSectionState();
}

class _GoogleMailSectionState extends ConsumerState<GoogleMailSection> {
  bool _busy = false;
  bool? _connected;
  bool _readonly = false;
  String? _email;
  String? _name;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final svc = ref.read(googleMailServiceProvider);
    final c = await svc.isConnected();
    final r = await svc.isReadonlyEnabled();
    final e = await svc.getUserEmail();
    final n = await svc.getUserName();
    if (!mounted) return;
    setState(() {
      _connected = c;
      _readonly = r;
      _email = e;
      _name = n;
    });
  }

  Future<void> _connect({required bool withReadonly}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await ref
          .read(googleMailServiceProvider)
          .connect(withReadonly: withReadonly);
      if (!ok && mounted) {
        setState(() => _error = 'Verbindung abgebrochen.');
      }
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    setState(() => _busy = true);
    await ref.read(googleMailServiceProvider).disconnect();
    await _refresh();
    if (mounted) setState(() => _busy = false);
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
                Icon(Icons.alternate_email,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Gmail-Integration',
                    style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Verbindet Aktenwerk mit deinem Google-Konto, damit '
              'Anschreiben (und künftig Rechnungen, Stellungnahmen, '
              'Kostenvorschuss-Anträge) direkt mit angehängtem PDF aus '
              'der App versendet werden können. Die Mail erscheint in '
              'deinem Gmail-„Gesendet"-Ordner. Aktenwerk speichert nur '
              'das Access-Token lokal im Browser.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (_connected == true) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle,
                            color: Colors.green, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          'Verbunden${_email == null ? "" : " · $_email"}',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                    if (_name != null && _name!.isNotEmpty)
                      Text(_name!, style: theme.textTheme.bodySmall),
                    const SizedBox(height: 4),
                    Text(
                      _readonly
                          ? 'Berechtigungen: Senden + Lesen (für Auto-Import)'
                          : 'Berechtigungen: Nur Senden',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_connected != true)
                  FilledButton.icon(
                    onPressed:
                        _busy ? null : () => _connect(withReadonly: false),
                    icon: const Icon(Icons.send_outlined),
                    label: const Text('Gmail verbinden (Senden)'),
                  ),
                if (_connected == true && !_readonly)
                  OutlinedButton.icon(
                    onPressed:
                        _busy ? null : () => _connect(withReadonly: true),
                    icon: const Icon(Icons.inbox_outlined),
                    label: const Text(
                        'Auch Lesen erlauben (für späteren Auto-Import)'),
                  ),
                if (_connected == true)
                  TextButton.icon(
                    onPressed: _busy ? null : _disconnect,
                    icon: const Icon(Icons.link_off, size: 16),
                    label: const Text('Trennen'),
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
            const SizedBox(height: 8),
            Text(
              'Hinweis: Solange Aktenwerk noch nicht den Google-OAuth-Verifizierungsprozess '
              'durchlaufen hat, sehen externe Benutzer beim ersten Verbinden einen '
              '„nicht verifiziert"-Banner — das ist Google-Standard und stellt kein '
              'Sicherheitsproblem dar, solange du der App vertraust.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.privacy_tip_outlined, size: 14),
              label: const Text(
                  'Was Aktenwerk mit den Mail-Daten tut → Datenschutzerklärung'),
              onPressed: () => context.go('/datenschutz'),
            ),
          ],
        ),
      ),
    );
  }
}
