import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/sync/auth_service.dart';
import '../../../data/sync/org_service.dart';
import 'org_onboarding_dialog.dart';

/// Popup-Menü in der Top-Bar, mit dem die aktive Organisation gewechselt
/// oder eine neue angelegt/beigetreten werden kann.
class OrgSwitcher extends ConsumerWidget {
  const OrgSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authUser = ref.watch(authStateProvider).valueOrNull;
    if (authUser == null) return const SizedBox.shrink();

    final orgs = ref.watch(myOrgsProvider).valueOrNull ?? const [];
    final currentId = ref.watch(currentOrgIdProvider).valueOrNull;
    final current =
        orgs.where((o) => o.id == currentId).cast<OrgSummary?>().firstOrNull;

    return PopupMenuButton<String>(
      tooltip: 'Organisation wechseln',
      position: PopupMenuPosition.under,
      onSelected: (value) async {
        if (value == '__new__') {
          await showOrgOnboardingDialog(context);
        } else if (value == '__members__') {
          if (context.mounted) GoRouter.of(context).go('/organisation');
        } else if (value != currentId) {
          await ref.read(currentOrgIdProvider.notifier).set(value);
        }
      },
      itemBuilder: (ctx) => [
        if (orgs.isEmpty)
          const PopupMenuItem<String>(
            enabled: false,
            child: Text('Noch keine Organisation'),
          ),
        for (final o in orgs)
          PopupMenuItem<String>(
            value: o.id,
            child: Row(
              children: [
                Icon(
                  o.id == currentId
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                  size: 16,
                  color: o.id == currentId
                      ? AppTheme.accent600
                      : AppTheme.slate400,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(o.name,
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                      Text(o.role.label,
                          style: TextStyle(
                              fontSize: 11, color: AppTheme.slate500)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: '__members__',
          child: Row(children: [
            Icon(Icons.group_outlined, size: 16),
            SizedBox(width: 8),
            Text('Mitglieder verwalten'),
          ]),
        ),
        const PopupMenuItem<String>(
          value: '__new__',
          child: Row(children: [
            Icon(Icons.add, size: 16),
            SizedBox(width: 8),
            Text('Organisation anlegen / beitreten'),
          ]),
        ),
      ],
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppTheme.slate50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.slate200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.business_outlined,
                size: 16, color: AppTheme.slate500),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                current?.name ?? 'Organisation wählen',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down,
                size: 18, color: AppTheme.slate500),
          ],
        ),
      ),
    );
  }
}
