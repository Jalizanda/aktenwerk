import 'package:flutter/material.dart';

/// Ein Modul/Bereich der App, auf das Rechte vergeben werden können.
class AppModul {
  final String key;
  final String label;
  final IconData icon;
  final String gruppe; // 'Akten' | 'Werkzeuge' | 'Auswertung' | 'Einstellungen'
  const AppModul({
    required this.key,
    required this.label,
    required this.icon,
    required this.gruppe,
  });
}

/// Zentraler Katalog aller Module.
/// Keys stimmen mit den Routen-Präfixen bzw. Repository-Namen überein.
const List<AppModul> appModule = [
  // ---------- Akten ----------
  AppModul(
      key: 'akten',
      label: 'Akten',
      icon: Icons.folder_outlined,
      gruppe: 'Akten'),
  AppModul(
      key: 'kunden',
      label: 'Auftraggeber',
      icon: Icons.group_outlined,
      gruppe: 'Akten'),
  AppModul(
      key: 'angebote',
      label: 'Angebote',
      icon: Icons.price_change_outlined,
      gruppe: 'Akten'),
  AppModul(
      key: 'auftraege',
      label: 'Aufträge',
      icon: Icons.assignment_outlined,
      gruppe: 'Akten'),
  AppModul(
      key: 'gutachten',
      label: 'Gutachten',
      icon: Icons.gavel_outlined,
      gruppe: 'Akten'),
  AppModul(
      key: 'erlaeuterungen',
      label: 'Erläuterungstermine',
      icon: Icons.event_available_outlined,
      gruppe: 'Akten'),
  AppModul(
      key: 'rechnungen',
      label: 'Rechnungen',
      icon: Icons.receipt_long_outlined,
      gruppe: 'Akten'),
  AppModul(
      key: 'eingangsrechnungen',
      label: 'Eingangsrechnungen',
      icon: Icons.download_outlined,
      gruppe: 'Akten'),
  AppModul(
      key: 'dokumente',
      label: 'Dokumente',
      icon: Icons.description_outlined,
      gruppe: 'Akten'),
  AppModul(
      key: 'lieferanten',
      label: 'Lieferanten',
      icon: Icons.local_shipping_outlined,
      gruppe: 'Akten'),
  // ---------- Werkzeuge ----------
  AppModul(
      key: 'artikel',
      label: 'Artikel / Leistungen',
      icon: Icons.sell_outlined,
      gruppe: 'Werkzeuge'),
  AppModul(
      key: 'geraete',
      label: 'Messgeräte',
      icon: Icons.precision_manufacturing_outlined,
      gruppe: 'Werkzeuge'),
  AppModul(
      key: 'normen',
      label: 'Normen',
      icon: Icons.menu_book_outlined,
      gruppe: 'Werkzeuge'),
  AppModul(
      key: 'textbausteine',
      label: 'Textbausteine',
      icon: Icons.text_snippet_outlined,
      gruppe: 'Werkzeuge'),
  AppModul(
      key: 'stunden',
      label: 'Stunden',
      icon: Icons.schedule_outlined,
      gruppe: 'Werkzeuge'),
  AppModul(
      key: 'auslagen',
      label: 'Auslagen',
      icon: Icons.payments_outlined,
      gruppe: 'Werkzeuge'),
  AppModul(
      key: 'kalkulation',
      label: 'Kalkulation',
      icon: Icons.calculate_outlined,
      gruppe: 'Werkzeuge'),
  AppModul(
      key: 'anschreiben',
      label: 'Anschreiben',
      icon: Icons.mail_outline,
      gruppe: 'Werkzeuge'),
  AppModul(
      key: 'fotos',
      label: 'Fotos',
      icon: Icons.photo_library_outlined,
      gruppe: 'Werkzeuge'),
  AppModul(
      key: 'termine',
      label: 'Termine',
      icon: Icons.event_outlined,
      gruppe: 'Werkzeuge'),
  AppModul(
      key: 'wiedervorlagen',
      label: 'Wiedervorlagen',
      icon: Icons.event_note_outlined,
      gruppe: 'Werkzeuge'),
  AppModul(
      key: 'ortstermin',
      label: 'Ortstermin-Modus',
      icon: Icons.location_on_outlined,
      gruppe: 'Werkzeuge'),
  AppModul(
      key: 'jveg',
      label: 'JVEG-Rechner',
      icon: Icons.balance_outlined,
      gruppe: 'Werkzeuge'),
  // ---------- Auswertung ----------
  AppModul(
      key: 'fortbildungen',
      label: 'Fortbildungen',
      icon: Icons.school_outlined,
      gruppe: 'Auswertung'),
  AppModul(
      key: 'befangenheit',
      label: 'Befangenheits-Register',
      icon: Icons.gavel_outlined,
      gruppe: 'Auswertung'),
  AppModul(
      key: 'opos',
      label: 'OPOS / Mahnwesen',
      icon: Icons.warning_amber_outlined,
      gruppe: 'Auswertung'),
  AppModul(
      key: 'statistik',
      label: 'Steuer & Statistik',
      icon: Icons.bar_chart_outlined,
      gruppe: 'Auswertung'),
];

/// Liste aller Modul-Keys.
List<String> get alleModulKeys =>
    appModule.map((m) => m.key).toList(growable: false);

/// Hilfsklasse zum Parsen / Serialisieren der komma-getrennten Listen.
class ModulRechte {
  final Set<String> erlaubt;
  final Set<String> bearbeitbar;
  final bool istAdmin;

  const ModulRechte({
    required this.erlaubt,
    required this.bearbeitbar,
    required this.istAdmin,
  });

  factory ModulRechte.admin() => ModulRechte(
        erlaubt: alleModulKeys.toSet(),
        bearbeitbar: alleModulKeys.toSet(),
        istAdmin: true,
      );

  factory ModulRechte.parse({
    required String? erlaubteCsv,
    required String? bearbeitbareCsv,
    required String rolle,
  }) {
    if (rolle == 'admin') return ModulRechte.admin();
    if (erlaubteCsv == null) {
      // null bedeutet „Default" → alle Module erlaubt, alle bearbeitbar.
      return ModulRechte(
        erlaubt: alleModulKeys.toSet(),
        bearbeitbar: alleModulKeys.toSet(),
        istAdmin: false,
      );
    }
    final erlaubt = erlaubteCsv
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    final bearbeitbar = (bearbeitbareCsv ?? '')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    return ModulRechte(
      erlaubt: erlaubt,
      bearbeitbar: bearbeitbar,
      istAdmin: false,
    );
  }

  String get erlaubteCsv => erlaubt.join(',');
  String get bearbeitbareCsv => bearbeitbar.join(',');

  bool darfSehen(String modulKey) => istAdmin || erlaubt.contains(modulKey);
  bool darfBearbeiten(String modulKey) =>
      istAdmin || bearbeitbar.contains(modulKey);
}
