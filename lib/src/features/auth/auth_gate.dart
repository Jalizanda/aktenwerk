import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/theme/app_theme.dart';
import '../../data/sync/auth_service.dart';
import '../../data/sync/firebase_init.dart';
import 'user_approval_service.dart';
import 'waiting_for_approval_screen.dart';

/// Wrappt den eigentlichen App-Inhalt (Router/Shell).
///
/// - Nicht eingeloggt → [LoginScreen]
/// - Eingeloggt, aber Account nicht freigeschaltet → [WaitingForApprovalScreen]
/// - Eingeloggt und freigeschaltet → reguläre App
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!FirebaseBootstrap.isReady) return child;
    final auth = ref.watch(authStateProvider);
    return auth.when(
      loading: () => const _SplashScreen(),
      error: (_, _) => const LoginScreen(),
      data: (user) {
        if (user == null) return const LoginScreen();
        // Sicherstellen, dass das users/{uid}-Dokument existiert, sobald
        // sich jemand (neu) anmeldet.
        final userDocAsync = ref.watch(currentUserDocProvider);
        return userDocAsync.when(
          loading: () => const _SplashScreen(),
          error: (e, _) => _ErrorScreen(message: e.toString()),
          data: (doc) {
            if (doc == null) return const _SplashScreen();
            if (!doc.approved && !doc.isSuperAdmin) {
              return const WaitingForApprovalScreen();
            }
            return child;
          },
        );
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.slate50,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset('assets/images/logo.svg', height: 64),
            const SizedBox(height: 24),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.slate50,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Fehler: $message'),
          ),
        ),
      ),
    );
  }
}

/// Schönes Login-Layout im SV-Software-Stil: Logo oben, großer Titel,
/// Button „Mit Google anmelden", „Mit E-Mail anmelden", darunter kleiner
/// Link „Noch keinen Account? Registrieren".
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _handle(Future<Object?> Function() fn) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await fn();
    } catch (e) {
      if (mounted) setState(() => _error = _prettyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _prettyError(Object e) {
    final s = e.toString();
    if (s.contains('wrong-password') || s.contains('invalid-credential')) {
      return 'E-Mail oder Passwort falsch.';
    }
    if (s.contains('user-not-found')) {
      return 'Es gibt noch keinen Account mit dieser E-Mail.';
    }
    if (s.contains('email-already-in-use')) {
      return 'Für diese E-Mail existiert bereits ein Account.';
    }
    if (s.contains('weak-password')) {
      return 'Das Passwort ist zu kurz (mind. 6 Zeichen).';
    }
    if (s.contains('invalid-email')) {
      return 'Die E-Mail-Adresse ist ungültig.';
    }
    if (s.contains('sign-in-cancelled') ||
        s.contains('popup-closed-by-user') ||
        s.contains('cancelled-popup-request')) {
      return 'Anmeldung abgebrochen — das Popup wurde geschlossen. '
          'Bitte erneut versuchen oder die E-Mail-Anmeldung nutzen.';
    }
    if (s.contains('popup-blocked')) {
      return 'Dein Browser blockiert das Anmelde-Popup. Popup-Blocker '
          'erlauben oder die E-Mail-Anmeldung nutzen.';
    }
    if (s.contains('network-request-failed')) {
      return 'Keine Verbindung zum Anmeldedienst. Internetverbindung prüfen.';
    }
    if (s.contains('too-many-requests')) {
      return 'Zu viele Versuche — bitte später erneut probieren.';
    }
    return 'Anmeldung fehlgeschlagen.\n$s';
  }

  Future<void> _googleLogin() async {
    await _handle(() => ref.read(authServiceProvider).signInWithGoogle());
  }

  Future<void> _emailLogin() async {
    final creds = await _askEmailPassword(
      title: 'Anmelden',
      action: 'Anmelden',
    );
    if (creds == null) return;
    await _handle(() => ref
        .read(authServiceProvider)
        .signInWithEmail(creds.email, creds.password));
  }

  Future<void> _emailRegister() async {
    final creds = await _askEmailPassword(
      title: 'Registrieren',
      action: 'Registrieren',
      subtitle:
          'Neue Accounts müssen vom Administrator freigeschaltet werden, '
          'bevor sie mit Daten arbeiten können.',
    );
    if (creds == null) return;
    await _handle(() => ref
        .read(authServiceProvider)
        .registerWithEmail(creds.email, creds.password));
  }

  Future<void> _passwordReset() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Passwort zurücksetzen'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'E-Mail'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('E-Mail senden')),
        ],
      ),
    );
    if (ok != true) return;
    await _handle(() =>
        ref.read(authServiceProvider).sendPasswordReset(ctrl.text.trim()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwort-Reset-Mail gesendet.')),
      );
    }
  }

  Future<_Creds?> _askEmailPassword({
    required String title,
    required String action,
    String? subtitle,
  }) async {
    final emailCtrl = TextEditingController();
    final pwCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    return showDialog<_Creds>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (subtitle != null) ...[
                Text(subtitle,
                    style:
                        const TextStyle(fontSize: 12, color: AppTheme.slate500)),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: emailCtrl,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'E-Mail'),
                validator: (v) => (v == null || !v.contains('@'))
                    ? 'Gib eine gültige E-Mail-Adresse ein.'
                    : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: pwCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Passwort'),
                validator: (v) => (v == null || v.length < 6)
                    ? 'Mindestens 6 Zeichen.'
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(
                    context,
                    _Creds(emailCtrl.text.trim(), pwCtrl.text),
                  );
                }
              },
              child: Text(action)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.slate50,
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 24),
                            child: _card(context),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Text(
                        '© ${DateTime.now().year} Aktenwerk · aktenwerk.app',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.slate400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _card(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.slate200),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F0F172A),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Logo-Kopfbereich: leicht eingefärbter Hintergrund, durch eine
          // Trennlinie vom Formular-Bereich abgesetzt.
          Container(
            color: AppTheme.slate50,
            padding: const EdgeInsets.symmetric(vertical: 32),
            alignment: Alignment.center,
            child: SvgPicture.asset(
              'assets/images/logo.svg',
              height: 84,
              fit: BoxFit.contain,
            ),
          ),
          const Divider(height: 1, color: AppTheme.slate200),
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 26, 32, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Anmelden',
                  style:
                      TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'Melde dich an, um mit deinen Akten weiterzuarbeiten.',
                  style:
                      TextStyle(fontSize: 13, color: AppTheme.slate500),
                ),
                const SizedBox(height: 24),
          _GoogleButton(onPressed: _busy ? null : _googleLogin),
          const SizedBox(height: 12),
          _OrDivider(),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _emailLogin,
            icon: const Icon(Icons.mail_outline, size: 18),
            label: const Text('Mit E-Mail anmelden'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: _busy ? null : _passwordReset,
            child: const Text('Passwort vergessen?'),
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Noch keinen Account?',
                style:
                    TextStyle(fontSize: 13, color: AppTheme.slate600),
              ),
              const SizedBox(width: 6),
              TextButton(
                onPressed: _busy ? null : _emailRegister,
                child: const Text('Registrieren'),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Text(
                _error!,
                style: const TextStyle(
                    color: Color(0xFF991B1B), fontSize: 12, height: 1.3),
              ),
            ),
          ],
          if (_busy) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(minHeight: 2),
          ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Creds {
  final String email;
  final String password;
  _Creds(this.email, this.password);
}

class _OrDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
            child: Divider(
                color: AppTheme.slate200, height: 1, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('oder',
              style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.slate500,
                  letterSpacing: 0.3)),
        ),
        Expanded(
            child: Divider(
                color: AppTheme.slate200, height: 1, thickness: 1)),
      ],
    );
  }
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({this.onPressed});
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const _GoogleG(),
      label: const Text('Mit Google anmelden'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.slate900,
        backgroundColor: Colors.white,
        side: const BorderSide(color: AppTheme.slate200),
        minimumSize: const Size.fromHeight(46),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    );
  }
}

class _GoogleG extends StatelessWidget {
  const _GoogleG();
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: CustomPaint(painter: _GPainter()),
    );
  }
}

class _GPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final colors = [
      const Color(0xFF4285F4),
      const Color(0xFF34A853),
      const Color(0xFFFBBC05),
      const Color(0xFFEA4335),
    ];
    final c = size.width / 2;
    final r = size.width * 0.45;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.18;
    final rect = Rect.fromCircle(center: Offset(c, c), radius: r);
    final sweeps = [
      (-40.0, 90.0, colors[0]),
      (50.0, 90.0, colors[1]),
      (140.0, 90.0, colors[2]),
      (230.0, 90.0, colors[3]),
    ];
    for (final s in sweeps) {
      paint.color = s.$3;
      canvas.drawArc(rect, s.$1 * 3.141592653 / 180,
          s.$2 * 3.141592653 / 180, false, paint);
    }
    final line = Paint()
      ..color = colors[0]
      ..strokeWidth = size.width * 0.14
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(c, c),
        Offset(size.width - size.width * 0.05, c), line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
