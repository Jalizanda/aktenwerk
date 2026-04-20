import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/sync/org_service.dart';

/// Dialog, der erscheint, wenn ein eingeloggter User noch keiner Organisation
/// angehört. Bietet zwei Wege: **Organisation anlegen** oder **Einladung einlösen**.
Future<void> showOrgOnboardingDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _OrgOnboardingDialog(),
  );
}

class _OrgOnboardingDialog extends ConsumerStatefulWidget {
  const _OrgOnboardingDialog();
  @override
  ConsumerState<_OrgOnboardingDialog> createState() =>
      _OrgOnboardingDialogState();
}

enum _Mode { chooser, create, redeem }

class _OrgOnboardingDialogState extends ConsumerState<_OrgOnboardingDialog> {
  _Mode _mode = _Mode.chooser;
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _createOrg() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Bitte einen Namen eingeben.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final org = ref.read(orgServiceProvider);
      final id = await org.createOrg(
        name: name,
        beschreibung:
            _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      );
      await ref.read(currentOrgIdProvider.notifier).set(id);
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    } catch (e) {
      setState(() => _error = 'Fehler: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _redeem() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _error = 'Bitte einen Einladungs-Code eingeben.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final org = ref.read(orgServiceProvider);
      await org.redeemInvite(code);
      ref.invalidate(currentOrgIdProvider);
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    } catch (e) {
      setState(() => _error = 'Fehler: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Willkommen bei Aktenwerk',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                _mode == _Mode.chooser
                    ? 'Richte deine Organisation ein, um loszulegen.'
                    : _mode == _Mode.create
                        ? 'Neue Organisation anlegen'
                        : 'Einer bestehenden Organisation beitreten',
                style: TextStyle(color: AppTheme.slate500),
              ),
              const SizedBox(height: 20),
              if (_mode == _Mode.chooser) _buildChooser(),
              if (_mode == _Mode.create) _buildCreate(),
              if (_mode == _Mode.redeem) _buildRedeem(),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChooser() {
    return Column(
      children: [
        _ChoiceTile(
          icon: Icons.add_business_outlined,
          title: 'Organisation anlegen',
          subtitle:
              'Starte eine neue Organisation. Du wirst ihr Inhaber und kannst Kolleg:innen einladen.',
          onTap: () => setState(() => _mode = _Mode.create),
        ),
        const SizedBox(height: 10),
        _ChoiceTile(
          icon: Icons.mail_outline,
          title: 'Einladung einlösen',
          subtitle:
              'Du hast einen Einladungs-Code erhalten? Tritt einer bestehenden Organisation bei.',
          onTap: () => setState(() => _mode = _Mode.redeem),
        ),
      ],
    );
  }

  Widget _buildCreate() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Name der Organisation',
            hintText: 'z.B. Büro Müller',
          ),
          autofocus: true,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _descCtrl,
          decoration: const InputDecoration(
            labelText: 'Beschreibung (optional)',
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            TextButton(
              onPressed:
                  _busy ? null : () => setState(() => _mode = _Mode.chooser),
              child: const Text('Zurück'),
            ),
            const Spacer(),
            FilledButton(
              onPressed: _busy ? null : _createOrg,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Organisation anlegen'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRedeem() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _codeCtrl,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Einladungs-Code',
            hintText: 'z.B. A1B2C3D4',
          ),
          autofocus: true,
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            TextButton(
              onPressed:
                  _busy ? null : () => setState(() => _mode = _Mode.chooser),
              child: const Text('Zurück'),
            ),
            const Spacer(),
            FilledButton(
              onPressed: _busy ? null : _redeem,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Beitreten'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.slate50,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppTheme.accent600, size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                          color: AppTheme.slate500, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppTheme.slate400),
            ],
          ),
        ),
      ),
    );
  }
}
