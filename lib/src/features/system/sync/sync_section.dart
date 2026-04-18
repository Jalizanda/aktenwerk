import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/sync/auth_service.dart';
import '../../../data/sync/firebase_init.dart';
import '../../../data/sync/sync_service.dart';

class SyncSection extends ConsumerStatefulWidget {
  const SyncSection({super.key});
  @override
  ConsumerState<SyncSection> createState() => _SyncSectionState();
}

class _SyncSectionState extends ConsumerState<SyncSection> {
  bool _busy = false;
  String? _lastMsg;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final firebaseReady = FirebaseBootstrap.isReady;
    final authState = ref.watch(authStateProvider);
    final auth = ref.watch(authServiceProvider);

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
                Icon(Icons.cloud_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Cloud-Sync (Firestore)',
                    style: theme.textTheme.titleMedium),
                const Spacer(),
                _StatusChip(
                  ready: firebaseReady,
                  signedIn: authState.valueOrNull != null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (!firebaseReady)
              _hint(
                theme,
                'Firebase ist noch nicht konfiguriert. Führe im Terminal aus:\n'
                '  firebase login\n'
                '  flutterfire configure\n'
                'danach einmal die App neu starten.',
              )
            else
              authState.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(),
                ),
                error: (e, _) => _hint(theme, 'Auth-Fehler: $e'),
                data: (user) => user == null
                    ? _loggedOutActions(auth)
                    : _loggedInActions(theme, user.email ?? user.uid, auth),
              ),
            if (_lastMsg != null) ...[
              const SizedBox(height: 10),
              Text(
                _lastMsg!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _hint(ThemeData theme, String text) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: theme.textTheme.bodySmall),
      );

  Widget _loggedOutActions(AuthService auth) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Melde dich an, um Daten mit Firestore zu synchronisieren.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const SizedBox(width: 12),
        FilledButton.tonalIcon(
          onPressed: _busy
              ? null
              : () => _handle(() => auth.signInAnonymously(),
                  successMsg: 'Anonym angemeldet'),
          icon: const Icon(Icons.person_outline),
          label: const Text('Anonym anmelden'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _busy ? null : () => _openLogin(auth),
          icon: const Icon(Icons.mail_outline),
          label: const Text('E-Mail-Login'),
        ),
      ],
    );
  }

  Widget _loggedInActions(ThemeData theme, String label, AuthService auth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle_outline,
                color: theme.colorScheme.tertiary, size: 18),
            const SizedBox(width: 6),
            Expanded(child: Text('Eingeloggt als $label')),
            TextButton.icon(
              onPressed: _busy ? null : () => auth.signOut(),
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Abmelden'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () => _handle(
                        () => ref.read(syncServiceProvider).syncAll(),
                        successMsg:
                            'Alle lokalen Daten in die Cloud gepusht.',
                      ),
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child:
                          CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cloud_upload_outlined),
              label: const Text('Jetzt alles hochladen'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => _handle(
                        () => ref.read(syncServiceProvider).pullKunden(),
                        successMsg: 'Kunden aus der Cloud geladen.',
                      ),
              icon: const Icon(Icons.cloud_download_outlined),
              label: const Text('Kunden aus Cloud ziehen'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _handle(Future<Object?> Function() fn,
      {required String successMsg}) async {
    setState(() {
      _busy = true;
      _lastMsg = null;
    });
    try {
      await fn();
      if (mounted) setState(() => _lastMsg = successMsg);
    } catch (e) {
      if (mounted) setState(() => _lastMsg = 'Fehler: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openLogin(AuthService auth) async {
    final emailController = TextEditingController();
    final pwController = TextEditingController();
    final result = await showDialog<_LoginResult>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Mit E-Mail anmelden'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: emailController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'E-Mail'),
            ),
            TextField(
              controller: pwController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Passwort'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen')),
          TextButton(
              onPressed: () => Navigator.pop(
                  context,
                  _LoginResult(emailController.text,
                      pwController.text, register: true)),
              child: const Text('Registrieren')),
          FilledButton(
              onPressed: () => Navigator.pop(
                  context,
                  _LoginResult(emailController.text, pwController.text)),
              child: const Text('Anmelden')),
        ],
      ),
    );
    if (result == null) return;
    await _handle(
      () => result.register
          ? auth.registerWithEmail(result.email, result.password)
          : auth.signInWithEmail(result.email, result.password),
      successMsg: result.register
          ? 'Registriert und angemeldet.'
          : 'Angemeldet.',
    );
  }
}

class _LoginResult {
  final String email;
  final String password;
  final bool register;
  _LoginResult(this.email, this.password, {this.register = false});
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.ready, required this.signedIn});
  final bool ready;
  final bool signedIn;
  @override
  Widget build(BuildContext context) {
    final (color, label) = !ready
        ? (
            Theme.of(context).colorScheme.surfaceContainerHighest,
            'nicht konfiguriert'
          )
        : signedIn
            ? (
                Theme.of(context).colorScheme.tertiaryContainer,
                'verbunden'
              )
            : (
                Theme.of(context).colorScheme.secondaryContainer,
                'nicht angemeldet'
              );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style:
              const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}
