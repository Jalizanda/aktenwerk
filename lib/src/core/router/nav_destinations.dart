/// Ein Modul innerhalb einer Sektion.
/// [icon] ist der Schlüssel im `Heroicons`-Katalog.
class NavItem {
  final String label;
  final String icon;
  final String path;
  /// Wenn gesetzt: wird nur Super-Admins angezeigt.
  final bool superAdminOnly;
  const NavItem(this.label, this.icon, this.path,
      {this.superAdminOnly = false});
}

/// Eine Sektion der Seitenleiste.
/// Leerer Titel = keine Sektion-Überschrift (z.B. Dashboard).
class NavSection {
  final String title;
  final List<NavItem> items;
  const NavSection(this.title, this.items);
}

/// Navigationsstruktur – entspricht 1:1 der linken Seitenleiste der
/// Original-SV-Software, ergänzt um Auslagen/Kalkulation/Anschreiben.
const navSections = <NavSection>[
  NavSection('', [
    NavItem('Dashboard', 'dashboard', '/'),
    NavItem('Akten', 'akten', '/akten'),
    NavItem('Kalender', 'kalender', '/termine'),
  ]),
  NavSection('Akten', [
    NavItem('Kontakte', 'kunden', '/kunden'),
    NavItem('Angebote', 'angebote', '/angebote'),
    NavItem('Aufträge', 'auftraege', '/auftraege'),
    NavItem('Gutachten', 'gutachten', '/gutachten'),
    NavItem('Erläuterungstermine', 'erlaeuterungen', '/erlaeuterungen'),
    NavItem('Rechnungen', 'rechnungen', '/rechnungen'),
    NavItem('Eingangsrechnungen', 'eingangsrechnungen', '/eingangsrechnungen'),
    NavItem('Dokumente', 'dokumente', '/dokumente'),
  ]),
  NavSection('Werkzeuge', [
    NavItem('Artikel / Leistungen', 'artikel', '/artikel'),
    NavItem('Messgeräte', 'geraete', '/geraete'),
    NavItem('Normen', 'normen', '/normen'),
    NavItem('Textbausteine', 'textbausteine', '/textbausteine'),
    NavItem('Recherche-Ablage', 'recherche', '/recherche'),
    NavItem('Stunden', 'stunden', '/stunden'),
    NavItem('Auslagen', 'auslagen', '/auslagen'),
    NavItem('Kalkulation', 'kalkulation', '/kalkulation'),
    NavItem('Anschreiben', 'anschreiben', '/anschreiben'),
    NavItem('Serienbriefe', 'serienbrief', '/serienbrief'),
    NavItem('Fotos', 'fotos', '/fotos'),
    NavItem('Kalender', 'kalender', '/termine'),
    NavItem('Wiedervorlagen', 'wiedervorlagen', '/wiedervorlagen'),
    NavItem('Ortstermin-Modus', 'ortstermin', '/ortstermin'),
  ]),
  NavSection('Auswertung', [
    NavItem('OPOS / Mahnwesen', 'opos', '/opos'),
    NavItem('Steuer & Statistik', 'steuer', '/steuer'),
    NavItem('Jahresbericht', 'jahresbericht', '/jahresbericht'),
    NavItem('CO₂-Tracker', 'co2', '/co2'),
  ]),
  NavSection('System', [
    NavItem('Einstellungen', 'einstellungen', '/einstellungen'),
    NavItem('Benutzer', 'benutzer', '/benutzer'),
    NavItem('Administration', 'admin', '/admin', superAdminOnly: true),
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
