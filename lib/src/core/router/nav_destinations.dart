import 'package:flutter/material.dart';

/// Ein Modul innerhalb einer Sektion.
class NavItem {
  final String label;
  final IconData icon;
  final String path;
  const NavItem(this.label, this.icon, this.path);
}

/// Eine Sektion der Seitenleiste (Gruppe von Modulen).
class NavSection {
  final String title;
  final IconData icon;
  final List<NavItem> items;
  const NavSection(this.title, this.icon, this.items);
}

/// Navigationsstruktur – entspricht der linken Seitenleiste des Originals.
const navSections = <NavSection>[
  NavSection('Übersicht', Icons.dashboard_outlined, [
    NavItem('Dashboard', Icons.space_dashboard_outlined, '/'),
  ]),
  NavSection('Akten', Icons.folder_outlined, [
    NavItem('Auftraggeber', Icons.people_outline, '/kunden'),
    NavItem('Aufträge', Icons.assignment_outlined, '/auftraege'),
    NavItem('Gutachten', Icons.description_outlined, '/gutachten'),
    NavItem('Erläuterungen', Icons.gavel_outlined, '/erlaeuterungen'),
    NavItem('Rechnungen', Icons.request_page_outlined, '/rechnungen'),
    NavItem('Eingangsrechnungen', Icons.receipt_long_outlined, '/eingangsrechnungen'),
    NavItem('Lieferanten', Icons.local_shipping_outlined, '/lieferanten'),
  ]),
  NavSection('Angebote & Anschreiben', Icons.mail_outline, [
    NavItem('Angebote', Icons.price_change_outlined, '/angebote'),
    NavItem('Anschreiben', Icons.drafts_outlined, '/anschreiben'),
  ]),
  NavSection('Kalkulationen', Icons.calculate_outlined, [
    NavItem('Artikel / Leistungen', Icons.inventory_2_outlined, '/artikel'),
    NavItem('Stunden', Icons.schedule_outlined, '/stunden'),
    NavItem('Auslagen', Icons.payments_outlined, '/auslagen'),
    NavItem('Kalkulation', Icons.functions_outlined, '/kalkulation'),
  ]),
  NavSection('Werkzeuge', Icons.build_outlined, [
    NavItem('Messgeräte', Icons.speed_outlined, '/geraete'),
    NavItem('Normen', Icons.menu_book_outlined, '/normen'),
    NavItem('Textbausteine', Icons.text_snippet_outlined, '/textbausteine'),
    NavItem('Fotos', Icons.photo_library_outlined, '/fotos'),
    NavItem('Termine', Icons.event_outlined, '/termine'),
    NavItem('Wiedervorlagen', Icons.notifications_active_outlined, '/wiedervorlagen'),
    NavItem('JVEG-Rechner', Icons.balance_outlined, '/jveg'),
    NavItem('Ortstermin-Modus', Icons.place_outlined, '/ortstermin'),
  ]),
  NavSection('Auswertung', Icons.analytics_outlined, [
    NavItem('OPOS / Mahnwesen', Icons.warning_amber_outlined, '/opos'),
    NavItem('Steuer & Statistik', Icons.query_stats_outlined, '/steuer'),
    NavItem('Jahresbericht', Icons.picture_as_pdf_outlined, '/jahresbericht'),
    NavItem('Fortbildungen', Icons.school_outlined, '/fortbildungen'),
  ]),
  NavSection('System', Icons.settings_outlined, [
    NavItem('Einstellungen', Icons.tune_outlined, '/einstellungen'),
    NavItem('Benutzer', Icons.account_circle_outlined, '/benutzer'),
  ]),
];

/// Findet das NavItem zum aktuellen Path.
NavItem? findNavItem(String path) {
  for (final s in navSections) {
    for (final i in s.items) {
      if (i.path == path) return i;
    }
  }
  return null;
}
