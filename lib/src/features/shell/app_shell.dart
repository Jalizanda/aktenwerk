import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../core/icons/heroicons.dart';
import '../../core/router/nav_destinations.dart';
import '../../core/theme/app_theme.dart';
import '../../data/sync/auth_service.dart';
import '../../data/sync/auto_sync_service.dart';
import '../../data/sync/org_service.dart';
import '../auth/user_approval_service.dart';
import '../search/search_dialog.dart';
import 'kalender_badge.dart';
import '../system/help/help_dialog.dart';
import '../system/help/release_notes_dialog.dart';
import '../system/org/org_onboarding_dialog.dart';
import 'auto_sync_badge.dart';
import '../system/org/org_switcher.dart';
import 'timer_widget.dart';

/// Haupt-Layout mit linker Seitenleiste und Content-Bereich.
/// Orientiert sich 1:1 am Original (Tailwind slate/orange, Inter).
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  static const double _sidebarWidth = 256;
  static const double _collapsedBreakpoint = 900;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _onboardingShown = false;
  bool _autoSyncGestartet = false;

  @override
  void initState() {
    super.initState();
    // Auto-Sync einmalig beim ersten Build anwerfen. Nötige Checks
    // (Auth + Org) laufen intern.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_autoSyncGestartet) return;
      _autoSyncGestartet = true;
      final aktiv = await AutoSyncService.istAktiviert();
      if (aktiv && mounted) {
        ref.read(autoSyncServiceProvider).start();
      }
    });
  }

  void _maybeShowOnboarding() {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;
    final currentOrg = ref.read(currentOrgIdProvider).valueOrNull;
    final orgs = ref.read(myOrgsProvider).valueOrNull;
    // Nur prüfen, wenn die Liste der Orgs geladen ist.
    if (orgs == null) return;
    final hasOrg = currentOrg != null && orgs.any((o) => o.id == currentOrg);
    if (!hasOrg && orgs.isEmpty && !_onboardingShown) {
      _onboardingShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showOrgOnboardingDialog(context);
      });
    } else if (!hasOrg && orgs.isNotEmpty) {
      // User hat Orgs, aber keine ausgewählt → erste auswählen.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(currentOrgIdProvider.notifier).set(orgs.first.id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listener auf Auth/Org-Status → Onboarding anstoßen.
    ref.listen(authStateProvider, (_, _) => _maybeShowOnboarding());
    ref.listen(myOrgsProvider, (_, _) => _maybeShowOnboarding());
    ref.listen(currentOrgIdProvider, (_, _) => _maybeShowOnboarding());
    // Initial (wenn beim Build bereits alles geladen ist).
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowOnboarding());
    final width = MediaQuery.sizeOf(context).width;
    final showSidebar = width >= AppShell._collapsedBreakpoint;
    const sidebarWidth = AppShell._sidebarWidth;
    final currentPath = GoRouterState.of(context).uri.path;
    // findNavItem(currentPath) wird nicht mehr fürs Top-Bar benötigt —
    // der Modul-Titel wird ausschließlich im jeweiligen ModuleHeader angezeigt.
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLow,
      drawer: showSidebar
          ? null
          : Drawer(child: _Sidebar(currentPath: currentPath)),
      body: Row(
        children: [
          if (showSidebar)
            SizedBox(
              width: sidebarWidth,
              child: _Sidebar(currentPath: currentPath),
            ),
          Expanded(
            child: Column(
              children: [
                const _TopBar(),
                Expanded(
                  child: Container(
                    color: scheme.surfaceContainerLow,
                    child: widget.child,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Kompakte Top-Bar mit Globaler Suche, Org-Switcher und Einstellungen.
/// Der Modul-Titel wird bewusst NICHT mehr hier dupliziert — jedes Modul
/// trägt seinen Titel inkl. Kurzbeschreibung im eigenen [ModuleHeader].
class _TopBar extends ConsumerWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SearchField(
              onSubmit: (_) => showGlobalSearch(context),
              onTap: () => showGlobalSearch(context),
            ),
          ),
          const SizedBox(width: 12),
          const KalenderBadge(),
          const SizedBox(width: 12),
          const TimerWidget(),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Ortstermin-Modus öffnen',
            onPressed: () => GoRouter.of(context).go('/ortstermin'),
            icon: Icon(Icons.location_on_outlined,
                color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 8),
          const OrgSwitcher(),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Hilfe & Anleitung',
            onPressed: () => showHelpDialog(context),
            icon: Icon(Icons.help_outline,
                color: scheme.onSurfaceVariant),
          ),
          IconButton(
            tooltip: 'Release-Notes',
            onPressed: () => showReleaseNotesDialog(context),
            icon: Icon(Icons.campaign_outlined,
                color: scheme.onSurfaceVariant),
          ),
          const AutoSyncBadge(),
          IconButton(
            tooltip: 'Einstellungen',
            onPressed: () => GoRouter.of(context).go('/einstellungen'),
            icon: Icon(Icons.settings_outlined,
                color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 4),
          _UserMenu(),
        ],
      ),
    );
  }
}

/// Popup-Menü mit Avatar: Nutzername/E-Mail + Abmelden.
class _UserMenu extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;
    if (user == null) return const SizedBox.shrink();

    final initials = (user.displayName ?? user.email ?? '?')
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0])
        .join()
        .toUpperCase();

    return PopupMenuButton<String>(
      tooltip: 'Konto',
      position: PopupMenuPosition.under,
      onSelected: (value) async {
        if (value == 'einstellungen') {
          if (context.mounted) GoRouter.of(context).go('/einstellungen');
        } else if (value == 'abmelden') {
          final ok = await showDialog<bool>(
            context: context,
            useRootNavigator: true,
            builder: (_) => AlertDialog(
              title: const Text('Abmelden?'),
              content: const Text(
                  'Du wirst ausgeloggt und siehst die Login-Maske. '
                  'Deine lokalen Daten bleiben im Browser erhalten.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Abmelden'),
                ),
              ],
            ),
          );
          if (ok == true) {
            await ref.read(authServiceProvider).signOut();
          }
        }
      },
      itemBuilder: (ctx) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.displayName ?? 'Angemeldet',
                  style:
                      const TextStyle(fontWeight: FontWeight.w600)),
              if ((user.email ?? '').isNotEmpty)
                Text(user.email!,
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.slate500)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'einstellungen',
          child: Row(children: [
            Icon(Icons.settings_outlined, size: 16),
            SizedBox(width: 8),
            Text('Einstellungen'),
          ]),
        ),
        const PopupMenuItem<String>(
          value: 'abmelden',
          child: Row(children: [
            Icon(Icons.logout, size: 16),
            SizedBox(width: 8),
            Text('Abmelden'),
          ]),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.all(4),
        child: CircleAvatar(
          radius: 16,
          backgroundColor: AppTheme.accent600,
          foregroundImage: (user.photoURL ?? '').isEmpty
              ? null
              : NetworkImage(user.photoURL!),
          child: Text(
            initials.isEmpty ? '?' : initials,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// Permanent sichtbares Such-Feld in der Top-Bar (read-only, öffnet Dialog).
class _SearchField extends StatelessWidget {
  const _SearchField({required this.onSubmit, required this.onTap});
  final ValueChanged<String> onSubmit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Icon(Icons.search,
                    size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Global suchen … (Kunden, Aufträge, Rechnungen, Normen …)',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Text(
                    '⌘K',
                    style: TextStyle(
                      fontSize: 10,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.currentPath});
  final String currentPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isSuperAdmin =
        ref.watch(currentUserDocProvider).valueOrNull?.isSuperAdmin ?? false;
    return Container(
      decoration: BoxDecoration(
        // Gleicher Ton wie der Modul-Bereich (surfaceContainerLow = slate50)
        // — Kacheln und Cards setzen sich dadurch in Weiß klar ab.
        color: scheme.surfaceContainerLow,
        border: Border(right: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BrandHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 6),
              children: [
                for (final section in navSections) ...[
                  if (section.items.any((i) =>
                          !i.superAdminOnly || isSuperAdmin) &&
                      (section.items.length > 1 ||
                          section.items.first.path != '/'))
                    _SectionLabel(section.title),
                  for (final item in section.items)
                    if (!item.superAdminOnly || isSuperAdmin)
                      _NavItem(item: item, active: currentPath == item.path),
                ],
                const SizedBox(height: 12),
              ],
            ),
          ),
          _VersionFooter(),
        ],
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: InkWell(
        onTap: () => GoRouter.of(context).go('/'),
        // Logo nimmt die volle Spaltenbreite ein und skaliert proportional.
        child: SizedBox(
          width: double.infinity,
          child: SvgPicture.asset(
            'assets/images/logo.svg',
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.08 * 10.5,
          color: AppTheme.slate400,
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({required this.item, required this.active});
  final NavItem item;
  final bool active;
  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final bg = active
        ? AppTheme.accent50
        : _hover
            ? AppTheme.slate100
            : Colors.transparent;
    final textColor = active
        ? AppTheme.accent700
        : _hover
            ? AppTheme.slate900
            : AppTheme.slate600;
    final iconColor = active
        ? AppTheme.accent600
        : _hover
            ? AppTheme.slate900
            : AppTheme.slate500;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => GoRouter.of(context).go(widget.item.path),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            border: Border(
              left: BorderSide(
                color: active ? AppTheme.accent600 : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              HeroIcon(name: widget.item.icon, size: 18, color: iconColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.item.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    color: textColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VersionFooter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.slate200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFF10B981), // emerald-500
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Aktenwerk v1.0',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.slate500),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'aktenwerk.app',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppTheme.accent600,
            ),
          ),
        ],
      ),
    );
  }
}
