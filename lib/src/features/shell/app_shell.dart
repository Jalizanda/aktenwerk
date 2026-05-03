import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/widgets/aw_logo.dart';
import 'package:go_router/go_router.dart';

import '../../core/icons/heroicons.dart';
import '../../core/router/nav_destinations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/aw_tokens.dart';
import '../../data/sync/auth_service.dart';
import '../../data/sync/auto_sync_service.dart';
import '../../data/sync/org_service.dart';
import '../auth/subscription_service.dart';
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
          : Drawer(
              backgroundColor: AwTokens.white,
              // SafeArea, damit Logo + Mandant-Block nicht unter
              // dem Notch / Dynamic Island sitzen.
              child: SafeArea(
                top: true,
                bottom: false,
                child: _Sidebar(currentPath: currentPath),
              ),
            ),
      bottomNavigationBar: showSidebar
          ? null
          : _MobileBottomNav(currentPath: currentPath),
      body: SafeArea(
        // Top: Notch/Dynamic-Island. Bottom + Sides regelt Scaffold via
        // bottomNavigationBar bzw. der Drawer.
        top: true,
        bottom: false,
        child: Row(
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
                  const _TrialBanner(),
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
      ),
    );
  }
}

/// Bottom-Navigation für Mobile. Zeigt die 5 meistbenutzten Bereiche:
/// Home, Akten, Kalender, Kontakte, Ortstermin (prominent in Orange).
class _MobileBottomNav extends StatelessWidget {
  const _MobileBottomNav({required this.currentPath});
  final String currentPath;

  static const _items = <({String path, IconData icon, String label})>[
    (path: '/', icon: Icons.home_outlined, label: 'Home'),
    (path: '/akten', icon: Icons.folder_open_outlined, label: 'Akten'),
    (path: '/ortstermin', icon: Icons.location_on_outlined, label: 'Ortstermin'),
    (path: '/termine', icon: Icons.calendar_month_outlined, label: 'Kalender'),
    (path: '/kunden', icon: Icons.people_outline, label: 'Kontakte'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AwTokens.white,
        border: Border(top: BorderSide(color: AwTokens.line)),
      ),
      padding: EdgeInsets.only(
          bottom: MediaQuery.paddingOf(context).bottom),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            for (final it in _items) Expanded(child: _tab(context, it)),
          ],
        ),
      ),
    );
  }

  Widget _tab(
      BuildContext context,
      ({String path, IconData icon, String label}) it) {
    final active = currentPath == it.path ||
        (it.path != '/' && currentPath.startsWith(it.path));
    final isOrtstermin = it.path == '/ortstermin';
    return InkWell(
      onTap: () => GoRouter.of(context).go(it.path),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            it.icon,
            size: 22,
            color: isOrtstermin
                ? AwTokens.orange
                : (active ? AwTokens.orange : AwTokens.mute),
          ),
          const SizedBox(height: 3),
          Text(
            it.label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              color: active ? AwTokens.ink : AwTokens.mute,
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
    // AW-Guideline §5 „Topbar": 56 px, weiß, Line-Border unten.
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < AppShell._collapsedBreakpoint;

    return Container(
      height: 56,
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 20),
      decoration: const BoxDecoration(
        color: AwTokens.white,
        border: Border(bottom: BorderSide(color: AwTokens.line)),
      ),
      child: isMobile
          ? _buildMobile(context, ref)
          : _buildDesktop(context, ref),
    );
  }

  Widget _buildMobile(BuildContext context, WidgetRef ref) {
    final loggedIn = ref.watch(authStateProvider).valueOrNull != null;
    final w = MediaQuery.sizeOf(context).width;
    // Auf sehr schmalen Phones (< 400 px) das Lockup auf 26 reduzieren —
    // sonst kollidiert es mit Suche + Avatar.
    final logoSize = w < 400 ? 26.0 : 30.0;
    return Row(
      children: [
        Builder(
          builder: (btnCtx) => IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Menü',
            icon: const Icon(Icons.menu, color: AwTokens.ink),
            onPressed: () => Scaffold.of(btnCtx).openDrawer(),
          ),
        ),
        const SizedBox(width: 2),
        Flexible(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => GoRouter.of(context).go('/'),
            child: Tooltip(
              message: 'Zur Übersicht',
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: AwLogo(size: logoSize, variant: AwLogoVariant.lockup),
              ),
            ),
          ),
        ),
        const Spacer(),
        // Suche bleibt im Topbar (nicht in der Bottom-Nav). Ortstermin
        // ist redundant — den Bottom-Nav-Tab gibt's separat.
        if (loggedIn)
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Suche',
            icon: const Icon(Icons.search, color: AwTokens.mute),
            onPressed: () => showGlobalSearch(context),
          ),
        _UserMenu(),
      ],
    );
  }

  Widget _buildDesktop(BuildContext context, WidgetRef ref) {
    return Row(
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
          icon: const Icon(Icons.location_on_outlined, color: AwTokens.mute),
        ),
        const SizedBox(width: 8),
        const OrgSwitcher(),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Hilfe & Anleitung',
          onPressed: () => showHelpDialog(context),
          icon: const Icon(Icons.help_outline, color: AwTokens.mute),
        ),
        IconButton(
          tooltip: 'Release-Notes',
          onPressed: () => showReleaseNotesDialog(context),
          icon: const Icon(Icons.campaign_outlined, color: AwTokens.mute),
        ),
        const AutoSyncBadge(),
        IconButton(
          tooltip: 'Einstellungen',
          onPressed: () => GoRouter.of(context).go('/einstellungen'),
          icon: const Icon(Icons.settings_outlined, color: AwTokens.mute),
        ),
        const SizedBox(width: 4),
        _UserMenu(),
      ],
    );
  }
}

Future<bool> _confirmOrgWechsel(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (_) => AlertDialog(
      title: const Text('Mandant wechseln?'),
      content: const Text(
          'Beim Wechsel wird die App neu geladen und alle Listen ziehen '
          'die Daten des neuen Mandanten. Ungespeicherte Eingaben in '
          'offenen Dialogen gehen verloren.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Wechseln'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Popup-Menü mit Avatar: Nutzername/E-Mail + Mandanten-Wechsel +
/// Einstellungen + Abmelden.
class _UserMenu extends ConsumerWidget {
  static const _orgPrefix = 'org:';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;
    // Wenn (noch) niemand eingeloggt ist → Anmelden-Pille statt Avatar.
    // Tap startet die normale Auth-Flow via AuthGate (Logout → LoginScreen).
    if (user == null) {
      return TextButton.icon(
        icon: const Icon(Icons.login, size: 16, color: AwTokens.orange),
        label: const Text(
          'Anmelden',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AwTokens.orange,
          ),
        ),
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          minimumSize: const Size(0, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: () async {
          try {
            await ref.read(authServiceProvider).signOut();
          } catch (_) {}
        },
      );
    }

    final initials = (user.displayName ?? user.email ?? '?')
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0])
        .join()
        .toUpperCase();

    final orgs = ref.watch(myOrgsProvider).valueOrNull ?? const [];
    final currentOrgId = ref.watch(currentOrgIdProvider).valueOrNull;

    return PopupMenuButton<String>(
      tooltip: 'Konto',
      position: PopupMenuPosition.under,
      onSelected: (value) async {
        if (value.startsWith(_orgPrefix)) {
          final newId = value.substring(_orgPrefix.length);
          if (newId == currentOrgId) return;
          final ok = await _confirmOrgWechsel(context);
          if (!ok) return;
          await ref.read(currentOrgIdProvider.notifier).set(newId);
          ref.invalidate(myOrgsProvider);
        } else if (value == 'mandant_neu') {
          await showOrgOnboardingDialog(context);
        } else if (value == 'mandant_verwalten') {
          if (context.mounted) GoRouter.of(context).go('/organisation');
        } else if (value == 'einstellungen') {
          if (context.mounted) GoRouter.of(context).go('/einstellungen');
        } else if (value == 'datenschutz') {
          if (context.mounted) GoRouter.of(context).go('/datenschutz');
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
                        fontSize: 11, color: AwTokens.mute)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        // Mandanten-Bereich (nur wenn Orgs vorhanden).
        const PopupMenuItem<String>(
          enabled: false,
          height: 28,
          child: Text(
            'MANDANT',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 10 * 0.08,
              color: AwTokens.mute,
            ),
          ),
        ),
        if (orgs.isEmpty)
          const PopupMenuItem<String>(
            enabled: false,
            child: Text(
              'Noch keine Organisation',
              style: TextStyle(fontSize: 12, color: AwTokens.mute),
            ),
          ),
        for (final o in orgs)
          PopupMenuItem<String>(
            value: '$_orgPrefix${o.id}',
            child: Row(
              children: [
                Icon(
                  o.id == currentOrgId
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                  size: 16,
                  color: o.id == currentOrgId
                      ? AwTokens.orange
                      : AwTokens.muteSoft,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(o.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                      Text(o.role.label,
                          style: const TextStyle(
                              fontSize: 11, color: AwTokens.mute)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const PopupMenuItem<String>(
          value: 'mandant_neu',
          child: Row(children: [
            Icon(Icons.add_business_outlined,
                size: 16, color: AwTokens.mute),
            SizedBox(width: 10),
            Text('Mandant anlegen', style: TextStyle(fontSize: 13)),
          ]),
        ),
        const PopupMenuItem<String>(
          value: 'mandant_verwalten',
          child: Row(children: [
            Icon(Icons.business_outlined, size: 16, color: AwTokens.mute),
            SizedBox(width: 10),
            Text('Mandant verwalten', style: TextStyle(fontSize: 13)),
          ]),
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
          value: 'datenschutz',
          child: Row(children: [
            Icon(Icons.privacy_tip_outlined, size: 16),
            SizedBox(width: 8),
            Text('Datenschutz'),
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
    // AW-Topbar-Suche: Paper-BG, Line-Border, 34 px Höhe, 8 px Radius.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Material(
        color: AwTokens.paper,
        borderRadius: BorderRadius.circular(AwTokens.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(AwTokens.radiusMd),
          onTap: onTap,
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AwTokens.radiusMd),
              border: Border.all(color: AwTokens.line),
            ),
            child: const Row(
              children: [
                Icon(Icons.search, size: 16, color: AwTokens.mute),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Global suchen … (Kunden, Aufträge, Rechnungen, Normen …)',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AwTokens.mute, fontSize: 12.5),
                  ),
                ),
                _Kbd('⌘K'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Kleiner Keyboard-Shortcut-Chip (z. B. ⌘K) — weiße Box, Line-Border.
class _Kbd extends StatelessWidget {
  const _Kbd(this.label);
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AwTokens.white,
        borderRadius: BorderRadius.circular(AwTokens.radiusXs),
        border: Border.all(color: AwTokens.line),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          color: AwTokens.mute,
          fontFamily: AwTokens.fontMono,
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
    final isSuperAdmin =
        ref.watch(currentUserDocProvider).valueOrNull?.isSuperAdmin ?? false;
    // AW-Guideline §5: Sidebar weißer BG, Line-Border rechts — Paper
    // bleibt dem Main-Bereich vorbehalten.
    return Container(
      decoration: const BoxDecoration(
        color: AwTokens.white,
        border: Border(right: BorderSide(color: AwTokens.line)),
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

/// Mandant-Block oben in der Sidebar / im Drawer: zeigt den aktuellen
/// Mandanten + öffnet bei Klick einen Wechsel-Dialog mit allen Orgs.
class _MandantBlock extends ConsumerWidget {
  const _MandantBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orgs = ref.watch(myOrgsProvider).valueOrNull ?? const [];
    final currentId = ref.watch(currentOrgIdProvider).valueOrNull;
    final current =
        orgs.where((o) => o.id == currentId).cast<OrgSummary?>().firstOrNull;
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AwTokens.line)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(AwTokens.radiusMd),
        onTap: () => _openMandantPicker(context, ref, orgs, currentId),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            children: [
              const Icon(Icons.business_outlined,
                  size: 16, color: AwTokens.orange),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'MANDANT',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 10 * 0.08,
                        color: AwTokens.mute,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      current?.name ??
                          (orgs.isEmpty
                              ? 'Anmelden für Mandanten'
                              : 'Mandant wählen'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AwTokens.ink,
                        height: 1.15,
                      ),
                    ),
                    if (current != null)
                      Text(
                        current.role.label,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AwTokens.mute,
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.unfold_more,
                  size: 16, color: AwTokens.mute),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openMandantPicker(BuildContext context, WidgetRef ref,
      List<OrgSummary> orgs, String? currentId) async {
    final picked = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (_) => SimpleDialog(
        title: const Text('Mandant'),
        children: [
          if (orgs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text(
                'Noch kein Mandant. Du kannst entweder einen anlegen oder '
                'dem Demo-Mandanten beitreten.',
                style: TextStyle(fontSize: 12.5, color: AwTokens.mute),
              ),
            ),
          for (final o in orgs)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, o.id),
              child: Row(
                children: [
                  Icon(
                    o.id == currentId
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                    size: 18,
                    color: o.id == currentId
                        ? AwTokens.orange
                        : AwTokens.muteSoft,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(o.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        Text(o.role.label,
                            style: const TextStyle(
                                fontSize: 11, color: AwTokens.mute)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (orgs.isNotEmpty) const Divider(),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(context);
              showOrgOnboardingDialog(context);
            },
            child: const Row(children: [
              Icon(Icons.add_business_outlined,
                  size: 18, color: AwTokens.mute),
              SizedBox(width: 12),
              Text('Mandant anlegen'),
            ]),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(context);
              GoRouter.of(context).go('/organisation');
            },
            child: const Row(children: [
              Icon(Icons.business_outlined, size: 18, color: AwTokens.mute),
              SizedBox(width: 12),
              Text('Mandant verwalten'),
            ]),
          ),
        ],
      ),
    );
    if (picked != null && picked != currentId) {
      if (!context.mounted) return;
      final ok = await _confirmOrgWechsel(context);
      if (!ok) return;
      await ref.read(currentOrgIdProvider.notifier).set(picked);
      ref.invalidate(myOrgsProvider);
    }
  }
}

class _BrandHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AwTokens.line)),
      ),
      child: InkWell(
        onTap: () => GoRouter.of(context).go('/'),
        // Lockup (Mark + „Aktenwerk"-Wortmarke) + Claim-Subline darunter.
        // Höhe 44 px → ca. +40 % ggü. der ersten Fassung (32 px).
        child: const Align(
          alignment: Alignment.centerLeft,
          child: AwLogo(
            size: 48,
            variant: AwLogoVariant.lockup,
            // Wortmarke +20 % ggü. SVG-Proportion — nur in der Sidebar.
            wortmarkeScale: 0.528,
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
    // AW-Guideline §3 „micro": 10 px 600 uppercase, letter-spacing 0.12em.
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 10 * 0.12,
          color: AwTokens.muteSoft,
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
    // AW-Guideline §5 „Sidebar": Aktiv = orange-soft BG, Icon orange,
    // Text Ink 500, 2.5-px-Akzent-Bar links. Hover = Paper, inaktiv =
    // transparent.
    final bg = active
        ? AwTokens.orangeSoft
        : _hover
            ? AwTokens.paper
            : Colors.transparent;
    final textColor = active
        ? AwTokens.ink
        : _hover
            ? AwTokens.ink
            : AwTokens.mute;
    final iconColor = active
        ? AwTokens.orange
        : _hover
            ? AwTokens.ink
            : AwTokens.mute;

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
                color: active ? AwTokens.orange : Colors.transparent,
                width: 2.5,
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
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AwTokens.line)),
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
                  color: AwTokens.green,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'Aktenwerk v1.0',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AwTokens.mute),
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

/// Banner-Streifen oben unter der Top-Bar — nur sichtbar wenn der
/// Trial-Zeitraum bald ausläuft oder schon abgelaufen ist.
class _TrialBanner extends ConsumerWidget {
  const _TrialBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = ref.watch(aktuelleOrgSubscriptionProvider).valueOrNull;
    if (sub == null) return const SizedBox.shrink();
    final eff = sub.effektiverStatus;
    if (eff == SubscriptionStatus.master ||
        eff == SubscriptionStatus.aktiv) {
      return const SizedBox.shrink();
    }
    final tage = sub.tageVerbleibend;
    // Trial: nur ab 7 Tagen oder weniger anzeigen
    if (eff == SubscriptionStatus.trial &&
        (tage == null || tage > 7)) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final abgelaufen = eff == SubscriptionStatus.trialAbgelaufen ||
        eff == SubscriptionStatus.gekuendigt;
    final bg = abgelaufen ? scheme.errorContainer : Colors.amber.shade100;
    final fg = abgelaufen ? scheme.error : Colors.amber.shade900;
    final text = abgelaufen
        ? 'Test abgelaufen — Mandant aktivieren, um wieder schreibend arbeiten zu können.'
        : (tage != null && tage <= 0
            ? 'Test endet heute — bitte Abo abschließen.'
            : (tage == 1
                ? 'Test endet morgen.'
                : 'Test endet in $tage Tagen — Abo abschließen.'));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: bg,
      child: Row(
        children: [
          Icon(
            abgelaufen ? Icons.lock_outline : Icons.timer_outlined,
            size: 16,
            color: fg,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600, color: fg),
            ),
          ),
          if (sub.memberCount > 0)
            Text(
              '${sub.memberCount} Nutzer · ${(sub.memberCount * sub.pricePerUserCents / 100).toStringAsFixed(2)} €/Monat',
              style: TextStyle(fontSize: 11.5, color: fg),
            ),
        ],
      ),
    );
  }
}
