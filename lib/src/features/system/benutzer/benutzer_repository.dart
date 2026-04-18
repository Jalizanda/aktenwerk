import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

/// Verwaltet den (effektiven) Sachverständigen-Datensatz.
///
/// In der Praxis nutzen wir genau einen "aktiven" Benutzer: den Betreiber
/// der Anwendung. Die Tabelle erlaubt zwar mehrere Einträge, wir pflegen
/// hier aber nur den ersten (kleinste id, aktiv==true) als Briefkopf.
class BenutzerRepository {
  BenutzerRepository(this._db);
  final AppDatabase _db;

  Stream<BenutzerData?> watchActive() {
    final q = _db.select(_db.benutzer)
      ..where((t) => t.aktiv.equals(true))
      ..orderBy([(t) => OrderingTerm(expression: t.id)])
      ..limit(1);
    return q.watchSingleOrNull();
  }

  Future<BenutzerData?> getActive() async {
    return (_db.select(_db.benutzer)
          ..where((t) => t.aktiv.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.id)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// Speichert – bei leerer Tabelle wird angelegt, sonst der aktive Eintrag
  /// aktualisiert.
  Future<int> saveActive(BenutzerCompanion entry) async {
    final current = await getActive();
    if (current == null) {
      return _db.into(_db.benutzer).insert(entry.copyWith(
            aktiv: const Value(true),
            updatedAt: Value(DateTime.now()),
          ));
    }
    await (_db.update(_db.benutzer)
          ..where((t) => t.id.equals(current.id)))
        .write(entry.copyWith(updatedAt: Value(DateTime.now())));
    return current.id;
  }
}

final benutzerRepositoryProvider = Provider<BenutzerRepository>((ref) {
  return BenutzerRepository(ref.watch(appDatabaseProvider));
});

final activeBenutzerProvider = StreamProvider<BenutzerData?>((ref) {
  return ref.watch(benutzerRepositoryProvider).watchActive();
});
