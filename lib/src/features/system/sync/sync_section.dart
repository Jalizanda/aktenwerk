import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/aw_tokens.dart';
import '../../../data/sync/auth_service.dart';
import '../../../data/sync/auto_sync_service.dart';
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
  bool? _autoSyncAktiv;
  int? _autoSyncIntervall;

  @override
  void initState() {
    super.initState();
    AutoSyncService.istAktiviert().then((v) {
      if (mounted) setState(() => _autoSyncAktiv = v);
    });
    AutoSyncService.intervallMinuten().then((v) {
      if (mounted) setState(() => _autoSyncIntervall = v);
    });
  }

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Melde dich an, um Daten mit Firestore zu synchronisieren.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AwTokens.white,
                foregroundColor: AwTokens.ink,
                side: const BorderSide(color: AwTokens.line),
              ),
              onPressed: _busy
                  ? null
                  : () => _handle(
                        () => auth.signInWithGoogle(),
                        successMsg: 'Mit Google angemeldet.',
                      ),
              icon: const _GoogleLogo(),
              label: const Text('Mit Google anmelden'),
            ),
            FilledButton.icon(
              onPressed: _busy ? null : () => _openLogin(auth),
              icon: const Icon(Icons.mail_outline),
              label: const Text('E-Mail / Passwort'),
            ),
          ],
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
        Wrap(
          spacing: 8,
          runSpacing: 8,
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
            FilledButton.tonalIcon(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() {
                        _busy = true;
                        _lastMsg = null;
                      });
                      try {
                        final report = await ref
                            .read(syncServiceProvider)
                            .pullAll();
                        if (!mounted) return;
                        await _zeigePullReport(report);
                      } catch (e) {
                        if (mounted) {
                          setState(() => _lastMsg = 'Fehler: $e');
                        }
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              icon: const Icon(Icons.cloud_download_outlined),
              label: const Text('Alles aus Cloud laden'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Divider(color: theme.colorScheme.outlineVariant),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(Icons.sync,
                size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Automatischer Hintergrund-Sync',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Switch(
              value: _autoSyncAktiv ?? true,
              onChanged: _autoSyncAktiv == null
                  ? null
                  : (v) async {
                      setState(() => _autoSyncAktiv = v);
                      await ref
                          .read(autoSyncServiceProvider)
                          .setAktiviert(v);
                    },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const SizedBox(width: 26),
            const Text('Intervall: ', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 6),
            DropdownButton<int>(
              value: _autoSyncIntervall ??
                  AutoSyncService.intervallDefault,
              items: [
                for (final m in AutoSyncService.intervallOptionen)
                  DropdownMenuItem(
                    value: m,
                    child: Text(_intervallLabel(m)),
                  ),
              ],
              onChanged: (_autoSyncAktiv ?? true) == false
                  ? null
                  : (v) async {
                      if (v == null) return;
                      setState(() => _autoSyncIntervall = v);
                      await ref
                          .read(autoSyncServiceProvider)
                          .setIntervallMinuten(v);
                    },
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Wenn aktiviert: Im gewählten Intervall automatischer Push + '
          'Pull, zusätzlich bei App-Start, wenn der Tab wieder Fokus '
          'bekommt und sobald das Netz wieder da ist. Nur geänderte '
          'Datensätze werden hochgeladen. Sync funktioniert nur '
          'innerhalb derselben Organisation — Mandantenwechsel oben '
          'rechts prüfen, falls Daten fehlen.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Future<void> _zeigePullReport(Map<String, int> report) async {
    if (!mounted) return;
    final total = report.values.fold<int>(0, (a, b) => a + b);
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.cloud_download_outlined, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text('$total Datensätze aus Cloud geladen'),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (total == 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Die Cloud enthält keine Daten für die aktuelle '
                    'Organisation. Möglicher Grund: Die Daten liegen '
                    'in einer anderen Org (Mandantenwechsel oben rechts '
                    'prüfen) oder wurden auf dem Ausgangsrechner noch '
                    'nicht mit "Jetzt alles hochladen" gepusht.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(
                            color: Theme.of(context).colorScheme.error),
                  ),
                ),
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8),
                child: Column(
                  children: [
                    for (final e in (report.entries.toList()
                      ..sort((a, b) => b.value.compareTo(a.value))))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _label(e.key),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            Text(
                              '${e.value}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: e.value == 0
                                    ? Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant
                                    : Theme.of(context).colorScheme.primary,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  String _intervallLabel(int minuten) {
    if (minuten < 60) return '$minuten Minute${minuten == 1 ? "" : "n"}';
    if (minuten % 60 == 0) {
      final std = minuten ~/ 60;
      return '$std Stunde${std == 1 ? "" : "n"}';
    }
    return '$minuten Minuten';
  }

  String _label(String key) => switch (key) {
        'kunden' => 'Auftraggeber (Kunden)',
        'auftraege' => 'Akten / Aufträge',
        'rechnungen' => 'Rechnungen',
        'angebote' => 'Angebote',
        'eingangsrechnungen' => 'Eingangsrechnungen',
        'lieferanten' => 'Lieferanten',
        'artikel' => 'Artikel / Leistungen',
        'stunden' => 'Stunden',
        'auslagen' => 'Auslagen',
        'normen' => 'Normen',
        'geraete' => 'Messgeräte',
        'textbausteine' => 'Textbausteine',
        'fortbildungen' => 'Fortbildungen',
        'gutachten' => 'Gutachten',
        'anschreiben' => 'Anschreiben',
        'fotos' => 'Fotos (Metadaten)',
        'dokumente' => 'Dokumente (Metadaten)',
        'benutzer' => 'Benutzer',
        'einstellungen' => 'Einstellungen',
        'erlaeuterungen' => 'Erläuterungstermine',
        'recherche_notizen' => 'Recherche-Ablage',
        _ => key,
      };

  Future<void> _handle(Future<Object?> Function() fn,
      {String? successMsg,
      String Function(dynamic result)? successMsgFn}) async {
    setState(() {
      _busy = true;
      _lastMsg = null;
    });
    try {
      final result = await fn();
      if (mounted) {
        setState(() => _lastMsg =
            successMsgFn != null ? successMsgFn(result) : successMsg);
      }
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
      () => auth.signInWithEmail(result.email, result.password),
      successMsg: 'Angemeldet.',
    );
  }
}

class _LoginResult {
  final String email;
  final String password;
  _LoginResult(this.email, this.password);
}

/// 18×18-Google-Logo als SVG für den Login-Button.
class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo();
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Vereinfachtes "G" in den Google-Farben.
    final colors = [
      const Color(0xFF4285F4),
      const Color(0xFF34A853),
      const Color(0xFFFBBC05),
      const Color(0xFFEA4335),
    ];
    final rect = Offset.zero & size;
    final c = size.width / 2;
    final r = size.width * 0.45;
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = size.width * 0.18;
    final rect2 = Rect.fromCircle(center: Offset(c, c), radius: r);
    final sweeps = [
      (-40.0, 90.0, colors[0]),
      (50.0, 90.0, colors[1]),
      (140.0, 90.0, colors[2]),
      (230.0, 90.0, colors[3]),
    ];
    for (final s in sweeps) {
      paint.color = s.$3;
      canvas.drawArc(rect2, s.$1 * 3.141592653 / 180,
          s.$2 * 3.141592653 / 180, false, paint);
    }
    // Kleine horizontale Linie als "G-Strich"
    final linePaint = Paint()
      ..color = colors[0]
      ..strokeWidth = size.width * 0.14
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
        Offset(c, c), Offset(rect.right - size.width * 0.05, c), linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
