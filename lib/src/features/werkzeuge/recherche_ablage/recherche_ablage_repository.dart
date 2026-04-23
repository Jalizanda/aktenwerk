import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

class RechercheAblageRepository {
  RechercheAblageRepository(this._db);
  final AppDatabase _db;

  /// Alle Notizen, optional gefiltert nach Akte.
  Stream<List<RechercheNotizenData>> watchAll({int? auftragId}) {
    final q = _db.select(_db.rechercheNotizen);
    if (auftragId != null) {
      q.where((t) => t.auftragId.equals(auftragId));
    }
    q.orderBy([
      (t) => OrderingTerm(
          expression: t.createdAt, mode: OrderingMode.desc),
    ]);
    return q.watch();
  }

  Future<RechercheNotizenData> insert({
    int? auftragId,
    required String titel,
    required String inhalt,
    String? quelle,
    String? referenzNormenJson,
  }) async {
    final id = await _db.into(_db.rechercheNotizen).insert(
          RechercheNotizenCompanion.insert(
            auftragId: Value(auftragId),
            titel: titel.trim(),
            inhalt: inhalt.trim(),
            quelle: Value(quelle),
            referenzNormenJson: Value(referenzNormenJson),
          ),
        );
    return (await (_db.select(_db.rechercheNotizen)
              ..where((t) => t.id.equals(id)))
            .getSingle());
  }

  Future<void> delete(int id) async {
    await (_db.delete(_db.rechercheNotizen)
          ..where((t) => t.id.equals(id)))
        .go();
  }

  Future<void> setVerwendet(int id, bool value) async {
    await (_db.update(_db.rechercheNotizen)
          ..where((t) => t.id.equals(id)))
        .write(RechercheNotizenCompanion(
      verwendet: Value(value),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<void> updateText(int id,
      {required String titel, required String inhalt, int? auftragId}) async {
    await (_db.update(_db.rechercheNotizen)
          ..where((t) => t.id.equals(id)))
        .write(RechercheNotizenCompanion(
      titel: Value(titel.trim()),
      inhalt: Value(inhalt.trim()),
      auftragId: Value(auftragId),
      updatedAt: Value(DateTime.now()),
    ));
  }
}

final rechercheAblageRepositoryProvider =
    Provider<RechercheAblageRepository>((ref) {
  return RechercheAblageRepository(ref.watch(appDatabaseProvider));
});

/// Alle Notizen, nach Datum absteigend. Nutzt [StreamProvider], damit
/// Liste + Editor sofort reagieren.
final rechercheAblageProvider =
    StreamProvider<List<RechercheNotizenData>>((ref) {
  return ref.watch(rechercheAblageRepositoryProvider).watchAll();
});

/// Notizen einer spezifischen Akte (z. B. im Gutachten-Editor).
final rechercheNotizenFuerAuftragProvider = StreamProvider.family<
    List<RechercheNotizenData>, int>((ref, auftragId) {
  return ref
      .watch(rechercheAblageRepositoryProvider)
      .watchAll(auftragId: auftragId);
});
