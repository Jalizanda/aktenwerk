import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/seed/demo_seed.dart';
import '../../../data/sync/org_service.dart';
import '../../../data/sync/sync_service.dart';
import '../../../features/auth/user_approval_service.dart';
import '../../../shared/widgets/badges.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';

/// Admin-Übersicht für den Super-Admin: Nutzer freischalten, Organisationen
/// freischalten, globale Stammdaten managen.
///
/// Die Seite ist nur für Super-Admins sichtbar — im Sidebar-NavItem wird sie
/// entsprechend nur für diese gezeigt. Zur Sicherheit prüft sie intern
/// nochmal den aktuellen User.
class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});
  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 4, vsync: this);
  static final _dateFmt = DateFormat('dd.MM.yyyy HH:mm', 'de');

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserDocProvider).valueOrNull;
    if (me == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!me.isSuperAdmin) {
      return const _NotAllowed();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ModuleHeader(
          icon: Icons.admin_panel_settings_outlined,
          title: 'Administration',
          subtitle:
              'Benutzer freischalten, Mandanten (Organisationen) prüfen',
        ),
        TabBar(
          controller: _tabs,
          labelColor: Theme.of(context).colorScheme.primary,
          indicatorColor: Theme.of(context).colorScheme.primary,
          tabs: const [
            Tab(text: 'Benutzer'),
            Tab(text: 'Mandanten'),
            Tab(text: 'Alle Benutzer'),
            Tab(text: 'Demo / Seeding'),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _PendingUsersTab(dateFmt: _dateFmt),
              _OrganisationsTab(dateFmt: _dateFmt),
              _AllUsersTab(dateFmt: _dateFmt),
              const _DemoSeedingTab(),
            ],
          ),
        ),
      ],
    );
  }
}

class _NotAllowed extends StatelessWidget {
  const _NotAllowed();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline,
                size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            const Text('Keine Berechtigung',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              'Dieser Bereich ist nur für Super-Administratoren zugänglich.',
              style: TextStyle(color: AppTheme.slate500),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- Pending Users ----------------

class _PendingUsersTab extends ConsumerWidget {
  const _PendingUsersTab({required this.dateFmt});
  final DateFormat dateFmt;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pendingUsersProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyListState(
            icon: Icons.person_outline,
            title: 'Keine offenen Registrierungen',
            hint: 'Wenn sich ein neuer Benutzer registriert, erscheint er hier.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final u = list[i];
            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.slate200),
              ),
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: BadgeColors.amberBg,
                    child: const Icon(Icons.hourglass_top_outlined,
                        color: Color(0xFFB45309), size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          u.displayName ?? u.email ?? u.uid,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (u.email != null && u.email != u.displayName)
                          Text(u.email!,
                              style: TextStyle(
                                  fontSize: 12, color: AppTheme.slate500)),
                        if (u.createdAt != null)
                          Text(
                            'Registriert: ${dateFmt.format(u.createdAt!)}',
                            style: TextStyle(
                                fontSize: 11, color: AppTheme.slate500),
                          ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Freischalten'),
                    onPressed: () async {
                      await ref
                          .read(userApprovalServiceProvider)
                          .approve(u.uid);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(
                                  '${u.email ?? u.uid} freigeschaltet.')),
                        );
                      }
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _AllUsersTab extends ConsumerWidget {
  const _AllUsersTab({required this.dateFmt});
  final DateFormat dateFmt;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(allUsersProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyListState(
              icon: Icons.group_outlined, title: 'Noch keine Benutzer');
        }
        return ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final u = list[i];
            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.slate200),
              ),
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              u.displayName ?? u.email ?? u.uid,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 8),
                            if (u.isSuperAdmin)
                              const PillBadge(
                                text: 'Super-Admin',
                                background: BadgeColors.indigoBg,
                                foreground: BadgeColors.indigoFg,
                              ),
                          ],
                        ),
                        if (u.email != null && u.email != u.displayName)
                          Text(u.email!,
                              style: TextStyle(
                                  fontSize: 12, color: AppTheme.slate500)),
                        if (u.createdAt != null)
                          Text(
                            'Registriert: ${dateFmt.format(u.createdAt!)}'
                            '${u.approved && u.approvedAt != null ? ' · freigeschaltet: ${dateFmt.format(u.approvedAt!)}' : ''}',
                            style: TextStyle(
                                fontSize: 11, color: AppTheme.slate500),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (u.approved)
                    const PillBadge(
                      text: 'freigeschaltet',
                      background: BadgeColors.greenBg,
                      foreground: BadgeColors.greenFg,
                    )
                  else
                    const PillBadge(
                      text: 'wartend',
                      background: BadgeColors.amberBg,
                      foreground: BadgeColors.amberFg,
                    ),
                  const SizedBox(width: 8),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (v) async {
                      final svc = ref.read(userApprovalServiceProvider);
                      switch (v) {
                        case 'approve':
                          await svc.approve(u.uid);
                          break;
                        case 'revoke':
                          await svc.revokeApproval(u.uid);
                          break;
                        case 'makeAdmin':
                          await svc.setSuperAdmin(u.uid, true);
                          break;
                        case 'removeAdmin':
                          await svc.setSuperAdmin(u.uid, false);
                          break;
                      }
                    },
                    itemBuilder: (_) => [
                      if (!u.approved)
                        const PopupMenuItem(
                            value: 'approve', child: Text('Freischalten')),
                      if (u.approved)
                        const PopupMenuItem(
                            value: 'revoke',
                            child: Text('Freischaltung widerrufen')),
                      if (!u.isSuperAdmin)
                        const PopupMenuItem(
                            value: 'makeAdmin',
                            child: Text('Zum Super-Admin machen')),
                      if (u.isSuperAdmin)
                        const PopupMenuItem(
                            value: 'removeAdmin',
                            child: Text('Super-Admin-Rechte entziehen')),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------- Organisations ----------------

class _OrganisationsTab extends ConsumerWidget {
  const _OrganisationsTab({required this.dateFmt});
  final DateFormat dateFmt;

  Stream<List<_AdminOrg>> _watchAll() {
    return FirebaseFirestore.instance
        .collection('organizations')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(_AdminOrg.fromDoc).toList());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<List<_AdminOrg>>(
      stream: _watchAll(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) return Center(child: Text('Fehler: ${snap.error}'));
        final list = snap.data ?? const <_AdminOrg>[];
        if (list.isEmpty) {
          return const EmptyListState(
              icon: Icons.business_outlined,
              title: 'Noch keine Mandanten');
        }
        return ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final o = list[i];
            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.slate200),
              ),
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: o.approved
                        ? BadgeColors.greenBg
                        : BadgeColors.amberBg,
                    child: Icon(
                      Icons.business_outlined,
                      size: 18,
                      color: o.approved
                          ? BadgeColors.greenFg
                          : BadgeColors.amberFg,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(o.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        if ((o.beschreibung ?? '').isNotEmpty)
                          Text(o.beschreibung!,
                              style: TextStyle(
                                  fontSize: 12, color: AppTheme.slate500)),
                        Text(
                          'Inhaber: ${o.ownerUid}'
                          '${o.createdAt != null ? ' · angelegt: ${dateFmt.format(o.createdAt!)}' : ''}',
                          style: TextStyle(
                              fontSize: 11, color: AppTheme.slate500),
                        ),
                      ],
                    ),
                  ),
                  if (o.approved)
                    const PillBadge(
                      text: 'freigeschaltet',
                      background: BadgeColors.greenBg,
                      foreground: BadgeColors.greenFg,
                    )
                  else
                    const PillBadge(
                      text: 'wartet',
                      background: BadgeColors.amberBg,
                      foreground: BadgeColors.amberFg,
                    ),
                  const SizedBox(width: 8),
                  if (!o.approved)
                    FilledButton.icon(
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Freischalten'),
                      onPressed: () async {
                        await FirebaseFirestore.instance
                            .collection('organizations')
                            .doc(o.id)
                            .update({
                          'approved': true,
                          'approvedAt': FieldValue.serverTimestamp(),
                          'approvedBy': ref
                              .read(currentUserDocProvider)
                              .valueOrNull
                              ?.uid,
                        });
                      },
                    )
                  else
                    OutlinedButton.icon(
                      icon: const Icon(Icons.block, size: 16),
                      label: const Text('Sperren'),
                      onPressed: () async {
                        await FirebaseFirestore.instance
                            .collection('organizations')
                            .doc(o.id)
                            .update({'approved': false});
                      },
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _AdminOrg {
  final String id;
  final String name;
  final String? beschreibung;
  final String ownerUid;
  final bool approved;
  final DateTime? createdAt;
  const _AdminOrg({
    required this.id,
    required this.name,
    this.beschreibung,
    required this.ownerUid,
    required this.approved,
    this.createdAt,
  });

  factory _AdminOrg.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return _AdminOrg(
      id: d.id,
      name: m['name']?.toString() ?? 'Organisation',
      beschreibung: m['beschreibung']?.toString(),
      ownerUid: m['ownerUid']?.toString() ?? '',
      approved: m['approved'] as bool? ?? false,
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// Nur als Unused-Guard damit OrgSummary nicht wegoptimiert wird.
// ignore: unused_element
final _unused = OrgSummary;

/// Tab zum Initialisieren des Demo-Mandanten mit Beispieldaten.
/// Nur Super-Admin, der in der Demo-Org als aktive Organisation eingeloggt
/// ist, kann die Demo-Daten in die Cloud pushen.
class _DemoSeedingTab extends ConsumerStatefulWidget {
  const _DemoSeedingTab();
  @override
  ConsumerState<_DemoSeedingTab> createState() => _DemoSeedingTabState();
}

class _DemoSeedingTabState extends ConsumerState<_DemoSeedingTab> {
  bool _busy = false;
  String? _lastMsg;

  Future<void> _setAktiveOrg(String orgId) async {
    await ref.read(currentOrgIdProvider.notifier).set(orgId);
    setState(() => _lastMsg = 'Aktive Organisation gewechselt.');
  }

  Future<void> _seedDemoData() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Demo-Daten laden und in Cloud pushen?'),
        content: const Text(
          'Alle lokalen Einträge werden gelöscht und durch die Beispieldaten '
          'ersetzt. Anschließend werden die Daten in den aktuell aktiven '
          'Demo-Mandanten hochgeladen.',
        ),
        actions: [
          TextButton(
              onPressed: () =>
                  Navigator.of(context, rootNavigator: true).pop(false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () =>
                  Navigator.of(context, rootNavigator: true).pop(true),
              child: const Text('Laden + pushen')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _busy = true;
      _lastMsg = null;
    });
    try {
      final rep = await ref.read(demoSeederProvider).loadAllAndSync();
      setState(() => _lastMsg =
          'Geladen: ${rep.total} Datensätze. Pushen in Demo-Org läuft …');
      await ref.read(syncServiceProvider).syncAll();
      setState(() => _lastMsg =
          'Demo-Daten erfolgreich in die Demo-Org gepusht (${rep.total} Einträge).');
    } catch (e) {
      setState(() => _lastMsg = 'Fehler: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final aktiveOrg = ref.watch(currentOrgIdProvider).valueOrNull;
    final isDemo = aktiveOrg == UserApprovalService.demoOrgId;
    final myOrgs = ref.watch(myOrgsProvider).valueOrNull ?? const [];
    final hasDemoMembership = myOrgs
        .any((o) => o.id == UserApprovalService.demoOrgId);
    final hasProduktiv = myOrgs.any((o) =>
        o.name == UserApprovalService.produktivOrgName &&
        o.id != UserApprovalService.demoOrgId);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _statusCard(context, hasDemoMembership, hasProduktiv),
        const SizedBox(height: 20),
        _Block(
          title: '1. Demo-Mandant aktivieren',
          subtitle:
              'Wechsle deinen aktiven Mandanten auf „Demo — Bauelemente-Experte". '
              'Dorthin werden die Beispieldaten gepusht.',
          child: Row(
            children: [
              if (isDemo)
                const PillBadge(
                  text: 'Demo ist aktive Organisation',
                  background: BadgeColors.greenBg,
                  foreground: BadgeColors.greenFg,
                )
              else
                FilledButton.icon(
                  icon: const Icon(Icons.swap_horiz, size: 16),
                  label: const Text('Demo als aktive Org wählen'),
                  onPressed: hasDemoMembership
                      ? () => _setAktiveOrg(UserApprovalService.demoOrgId)
                      : null,
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _Block(
          title: '2. Demo-Daten laden und in Cloud pushen',
          subtitle:
              'Lädt den mitgelieferten Demo-Seed (~285 Datensätze: Kunden, '
              'Aufträge, Gutachten, Rechnungen …) und pusht ihn in die '
              'aktive Organisation (= Demo).\n\nHinweis: Die aktuell geladenen '
              'lokalen Daten werden dabei ersetzt.',
          child: Row(
            children: [
              FilledButton.icon(
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cloud_upload_outlined, size: 16),
                label: const Text('Demo-Daten laden + pushen'),
                onPressed: (!isDemo || _busy) ? null : _seedDemoData,
              ),
              const SizedBox(width: 12),
              if (!isDemo)
                Text(
                  'Nur möglich, wenn Demo-Mandant aktive Organisation ist.',
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.slate500),
                ),
            ],
          ),
        ),
        if (_lastMsg != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.slate50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.slate200),
            ),
            child: Text(_lastMsg!,
                style: const TextStyle(fontSize: 13, height: 1.4)),
          ),
        ],
      ],
    );
  }

  Widget _statusCard(BuildContext context, bool demo, bool produktiv) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Initialer Mandanten-Status',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 10),
          _statusRow(
            'Demo-Mandant',
            demo,
            demo
                ? 'vorhanden – jeder freigegebene User bekommt Lesezugriff.'
                : 'fehlt (wird beim nächsten Admin-Login automatisch angelegt).',
          ),
          const SizedBox(height: 6),
          _statusRow(
            'Produktiv-Mandant „Bauelemente-Experte"',
            produktiv,
            produktiv
                ? 'vorhanden – steht für produktive Aufträge bereit.'
                : 'fehlt (wird beim nächsten Admin-Login automatisch angelegt).',
          ),
        ],
      ),
    );
  }

  Widget _statusRow(String title, bool ok, String hint) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(ok ? Icons.check_circle : Icons.info_outline,
            size: 16,
            color: ok ? BadgeColors.greenFg : BadgeColors.amberFg),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(hint,
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.slate500)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Block extends StatelessWidget {
  const _Block(
      {required this.title, required this.subtitle, required this.child});
  final String title;
  final String subtitle;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(subtitle,
              style:
                  TextStyle(fontSize: 12.5, color: AppTheme.slate600)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
