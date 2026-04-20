import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/theme/app_theme.dart';
import '../../data/sync/auth_service.dart';

/// Wird angezeigt, solange ein registrierter User noch nicht vom
/// Super-Admin freigeschaltet wurde.
class WaitingForApprovalScreen extends ConsumerWidget {
  const WaitingForApprovalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;
    return Scaffold(
      backgroundColor: AppTheme.slate50,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
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
              padding: const EdgeInsets.fromLTRB(36, 36, 36, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SvgPicture.asset('assets/images/logo.svg', height: 48),
                  const SizedBox(height: 24),
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppTheme.accent50,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.hourglass_top_outlined,
                        color: AppTheme.accent600, size: 28),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Account wartet auf Freischaltung',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Vielen Dank für deine Registrierung. Dein Account '
                    '(${user?.email ?? user?.uid ?? '—'}) wurde angelegt, '
                    'muss aber vom Administrator noch geprüft und '
                    'freigeschaltet werden.\n\n'
                    'Sobald dein Account freigegeben ist, kannst du hier '
                    'eine Organisation anlegen oder einer bestehenden per '
                    'Einladung beitreten.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.slate600,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: () =>
                        ref.read(authServiceProvider).signOut(),
                    icon: const Icon(Icons.logout, size: 16),
                    label: const Text('Abmelden'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
