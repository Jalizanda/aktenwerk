import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/sync/auth_service.dart';
import '../../../data/sync/org_service.dart';
import '../benutzer/modul_berechtigungen_dialog.dart';
import 'org_onboarding_dialog.dart';

/// Verwaltung der aktuellen Organisation: Mitglieder, Rollen, Einladungen.
class OrganisationScreen extends ConsumerWidget {
  const OrganisationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentId = ref.watch(currentOrgIdProvider).valueOrNull;
    final orgs = ref.watch(myOrgsProvider).valueOrNull ?? const [];
    final current =
        orgs.where((o) => o.id == currentId).cast<OrgSummary?>().firstOrNull;

    if (current == null) {
      return _EmptyState(
        onCreate: () => showOrgOnboardingDialog(context),
      );
    }

    final members = ref.watch(_membersProvider(current.id));
    return Column(
      children: [
        _Header(org: current),
        const Divider(height: 1),
        Expanded(
          child: members.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Fehler: $e')),
            data: (list) => _MembersList(org: current, members: list),
          ),
        ),
      ],
    );
  }
}

final _membersProvider =
    StreamProvider.family<List<OrgMember>, String>((ref, orgId) {
  return ref.watch(orgServiceProvider).watchMembers(orgId);
});

class _Header extends ConsumerWidget {
  const _Header({required this.org});
  final OrgSummary org;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      child: Row(
        children: [
          const Icon(Icons.business_outlined, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(org.name, style: theme.textTheme.headlineMedium),
                Text(
                  'Mitglieder, Rollen und Einladungen dieser Organisation',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (org.role.canManageMembers) ...[
            OutlinedButton.icon(
              onPressed: () => _showDummyDialog(context, ref, org.id),
              icon: const Icon(Icons.person_outline, size: 18),
              label: const Text('Dummy-User'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _showInviteDialog(context, ref, org.id),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Einladen'),
            ),
          ],
        ],
      ),
    );
  }
}

class _MembersList extends ConsumerWidget {
  const _MembersList({required this.org, required this.members});
  final OrgSummary org;
  final List<OrgMember> members;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authStateProvider).valueOrNull;
    if (members.isEmpty) {
      return const Center(child: Text('Noch keine Mitglieder.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: members.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final m = members[i];
        final isMe = me?.uid == m.uid;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppTheme.slate200),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: AppTheme.accent50,
                child: Text(
                  _initials(m),
                  style: TextStyle(
                      color: AppTheme.accent700,
                      fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(m.displayName ?? m.email ?? m.uid,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600)),
                        if (isMe) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.accent50,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('Du',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.accent700)),
                          ),
                        ],
                        if (m.isDummy) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF9C3),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('Dummy',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF854D0E))),
                          ),
                        ],
                      ],
                    ),
                    if (m.email != null && m.email != m.displayName)
                      Text(m.email!,
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.slate500)),
                  ],
                ),
              ),
              _RolePicker(org: org, member: m, isMe: isMe),
              const SizedBox(width: 8),
              if (org.role.canManageMembers &&
                  m.role != OrgRole.owner &&
                  m.role != OrgRole.admin)
                IconButton(
                  tooltip: 'Modul-Berechtigungen',
                  onPressed: () async {
                    final result = await showModulBerechtigungenDialog(
                      context,
                      memberName: m.displayName ?? m.email ?? m.uid,
                      initialErlaubt: m.erlaubteModule,
                      initialBearbeitbar: m.bearbeitbareModule,
                    );
                    if (result != null) {
                      await ref
                          .read(orgServiceProvider)
                          .setMemberPermissions(
                            org.id,
                            m.uid,
                            erlaubteModule: result.erlaubteCsv,
                            bearbeitbareModule: result.bearbeitbareCsv,
                          );
                    }
                  },
                  icon: const Icon(Icons.tune_outlined),
                ),
              if (org.role.canManageMembers && !isMe)
                IconButton(
                  tooltip: 'Entfernen',
                  onPressed: m.role == OrgRole.owner
                      ? null
                      : () => _confirmRemove(context, ref, org.id, m),
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
        );
      },
    );
  }

  String _initials(OrgMember m) {
    final s = (m.displayName ?? m.email ?? m.uid).trim();
    if (s.isEmpty) return '?';
    final parts = s.split(RegExp(r'\s+|@'));
    final a = parts.first.isNotEmpty ? parts.first[0] : '?';
    final b = parts.length > 1 && parts[1].isNotEmpty ? parts[1][0] : '';
    return (a + b).toUpperCase();
  }
}

class _RolePicker extends ConsumerWidget {
  const _RolePicker(
      {required this.org, required this.member, required this.isMe});
  final OrgSummary org;
  final OrgMember member;
  final bool isMe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canEdit = org.role.canManageMembers && !isMe;
    // Owner-Rolle ist schreibgeschützt, außer der aktuelle User ist selbst Owner.
    final ownerEditable = org.role == OrgRole.owner;
    if (!canEdit || (member.role == OrgRole.owner && !ownerEditable)) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.slate100,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(member.role.label,
            style: const TextStyle(fontSize: 12)),
      );
    }
    return DropdownButton<OrgRole>(
      value: member.role,
      underline: const SizedBox.shrink(),
      onChanged: (r) async {
        if (r == null || r == member.role) return;
        try {
          await ref
              .read(orgServiceProvider)
              .setMemberRole(org.id, member.uid, r);
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Fehler: $e')));
          }
        }
      },
      items: [
        for (final r in OrgRole.values)
          if (r != OrgRole.owner || ownerEditable)
            DropdownMenuItem(value: r, child: Text(r.label)),
      ],
    );
  }
}

Future<void> _confirmRemove(
    BuildContext context, WidgetRef ref, String orgId, OrgMember m) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Mitglied entfernen?'),
      content: Text(
          '${m.displayName ?? m.email ?? m.uid} verliert sofort den Zugriff auf diese Organisation.'),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context, rootNavigator: true).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () =>
              Navigator.of(context, rootNavigator: true).pop(true),
          child: const Text('Entfernen'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await ref.read(orgServiceProvider).removeMember(orgId, m.uid);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }
}

Future<void> _showInviteDialog(
    BuildContext context, WidgetRef ref, String orgId) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _InviteDialog(orgId: orgId),
  );
}

Future<void> _showDummyDialog(
    BuildContext context, WidgetRef ref, String orgId) async {
  await showDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (_) => _DummyUserDialog(orgId: orgId),
  );
}

class _DummyUserDialog extends ConsumerStatefulWidget {
  const _DummyUserDialog({required this.orgId});
  final String orgId;
  @override
  ConsumerState<_DummyUserDialog> createState() => _DummyUserDialogState();
}

class _DummyUserDialogState extends ConsumerState<_DummyUserDialog> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  OrgRole _role = OrgRole.member;
  bool _saving = false;

  static const _presets = [
    ('Max Mustermann', 'max.mustermann@demo.aktenwerk.app', OrgRole.member),
    ('Anna Schmidt', 'anna.schmidt@demo.aktenwerk.app', OrgRole.member),
    ('Lisa Meier', 'lisa.meier@demo.aktenwerk.app', OrgRole.readonly),
    ('Peter Bauer', 'peter.bauer@demo.aktenwerk.app', OrgRole.member),
  ];

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _add(String name, String email, OrgRole role) async {
    setState(() => _saving = true);
    try {
      await ref.read(orgServiceProvider).createDummyMember(
            widget.orgId,
            displayName: name,
            email: email,
            role: role,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$name angelegt')));
        _name.clear();
        _email.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fehler: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addAllPresets() async {
    for (final (name, email, role) in _presets) {
      await _add(name, email, role);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Dummy-Benutzer hinzufügen',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                  'Testbenutzer ohne echtes Firebase-Auth-Konto. '
                  'Nützlich zum Demonstrieren von Modul-Berechtigungen.',
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.slate500)),
              const SizedBox(height: 16),
              Text('Vordefinierte Testbenutzer',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.slate500,
                      letterSpacing: 1)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final (name, email, role) in _presets)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.person_add_alt_1, size: 14),
                      label: Text(
                          '$name · ${role == OrgRole.readonly ? "nur Lesen" : "Mitarbeiter"}',
                          style: const TextStyle(fontSize: 12)),
                      onPressed: _saving
                          ? null
                          : () => _add(name, email, role),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.group_add, size: 16),
                label: const Text('Alle vordefinierten anlegen'),
                onPressed: _saving ? null : _addAllPresets,
              ),
              const Divider(height: 28),
              Text('Eigenen Dummy anlegen',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.slate500,
                      letterSpacing: 1)),
              const SizedBox(height: 6),
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Anzeigename'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'E-Mail'),
              ),
              const SizedBox(height: 10),
              DropdownButton<OrgRole>(
                value: _role,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(
                      value: OrgRole.member, child: Text('Mitarbeiter')),
                  DropdownMenuItem(
                      value: OrgRole.readonly,
                      child: Text('Nur Lesezugriff')),
                ],
                onChanged: (v) => setState(() => _role = v ?? OrgRole.member),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context,
                            rootNavigator: true)
                        .pop(),
                    child: const Text('Schließen'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Hinzufügen'),
                    onPressed: _saving ||
                            _name.text.trim().isEmpty ||
                            _email.text.trim().isEmpty
                        ? null
                        : () => _add(_name.text.trim(),
                            _email.text.trim(), _role),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InviteDialog extends ConsumerStatefulWidget {
  const _InviteDialog({required this.orgId});
  final String orgId;
  @override
  ConsumerState<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends ConsumerState<_InviteDialog> {
  OrgRole _role = OrgRole.member;
  String? _code;
  bool _busy = false;
  String? _error;

  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final code = await ref
          .read(orgServiceProvider)
          .createInvite(widget.orgId, role: _role);
      setState(() => _code = code);
    } catch (e) {
      setState(() => _error = 'Fehler: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Mitglied einladen'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Wähle die Rolle für das neue Mitglied. Nach dem Erstellen erhältst '
              'du einen 8-stelligen Code, der 14 Tage gültig und einmalig verwendbar ist.',
              style: TextStyle(color: AppTheme.slate500),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<OrgRole>(
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'Rolle'),
              items: [
                for (final r in OrgRole.values)
                  if (r != OrgRole.owner)
                    DropdownMenuItem(value: r, child: Text(r.label)),
              ],
              onChanged: (r) => setState(() => _role = r ?? OrgRole.member),
            ),
            const SizedBox(height: 16),
            if (_code != null)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.accent50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        _code!,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 22,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kopieren',
                      icon: const Icon(Icons.copy),
                      onPressed: () async {
                        await Clipboard.setData(
                            ClipboardData(text: _code!));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Code in Zwischenablage')),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context, rootNavigator: true).pop(),
          child: const Text('Schließen'),
        ),
        FilledButton(
          onPressed: _busy ? null : _generate,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_code == null ? 'Code erzeugen' : 'Neuen Code erzeugen'),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});
  final VoidCallback onCreate;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.business_outlined,
                size: 48, color: AppTheme.slate400),
            const SizedBox(height: 12),
            const Text('Keine Organisation ausgewählt',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              'Wähle oben eine Organisation oder lege eine neue an.',
              style: TextStyle(color: AppTheme.slate500),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Organisation anlegen / beitreten'),
            ),
          ],
        ),
      ),
    );
  }
}
