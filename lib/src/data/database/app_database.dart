import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../tables/angebote_table.dart';
import '../tables/anschreiben_table.dart';
import '../tables/artikel_table.dart';
import '../tables/auftraege_table.dart';
import '../tables/auslagen_table.dart';
import '../tables/benutzer_table.dart';
import '../tables/dokumente_table.dart';
import '../tables/eingangsrechnungen_table.dart';
import '../tables/einstellungen_table.dart';
import '../tables/erlaeuterungen_table.dart';
import '../tables/fortbildungen_table.dart';
import '../tables/fotos_table.dart';
import '../tables/geraete_table.dart';
import '../tables/gutachten_table.dart';
import '../tables/kalkulationen_table.dart';
import '../tables/kunden_table.dart';
import '../tables/lieferanten_table.dart';
import '../tables/normen_table.dart';
import '../tables/rechnungen_table.dart';
import '../tables/rueckfragen_table.dart';
import '../tables/stunden_table.dart';
import '../tables/textbausteine_table.dart';
import '../tables/versand_table.dart';
import '../tables/wiedervorlagen_table.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [
  Kunden,
  Auftraege,
  Gutachten,
  Rechnungen,
  Stunden,
  Fotos,
  Einstellungen,
  Anschreiben,
  Textbausteine,
  Dokumente,
  Kalkulationen,
  Rueckfragen,
  Auslagen,
  Angebote,
  Wiedervorlagen,
  Versand,
  Fortbildungen,
  Artikel,
  Benutzer,
  Geraete,
  Normen,
  Eingangsrechnungen,
  Lieferanten,
  Erlaeuterungen,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'aktenwerk'));

  @override
  int get schemaVersion => 1;
}
