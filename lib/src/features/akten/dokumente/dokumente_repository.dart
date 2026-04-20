import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

class DokumentWithAuftrag {
  final DokumenteData dokument;
  final AuftraegeData? auftrag;
  const DokumentWithAuftrag(this.dokument, this.auftrag);
}

class DokumenteRepository {
  DokumenteRepository(this._db);
  final AppDatabase _db;

  Stream<List<DokumentWithAuftrag>> watchAll({
    int? auftragId,
    String? kategorie,
    String query = '',
  }) {
    final q = _db.select(_db.dokumente).join([
      leftOuterJoin(_db.auftraege,
          _db.auftraege.id.equalsExp(_db.dokumente.auftragId)),
    ]);
    if (auftragId != null) {
      q.where(_db.dokumente.auftragId.equals(auftragId));
    }
    if (kategorie != null && kategorie.isNotEmpty) {
      q.where(_db.dokumente.kategorie.equals(kategorie));
    }
    if (query.trim().isNotEmpty) {
      final like = '%${query.trim().toLowerCase()}%';
      q.where(_db.dokumente.titel.lower().like(like) |
          _db.dokumente.beschreibung.lower().like(like) |
          _db.dokumente.kategorie.lower().like(like));
    }
    q.orderBy([
      OrderingTerm(
          expression: _db.dokumente.datum, mode: OrderingMode.desc),
    ]);
    return q.watch().map((rows) => rows
        .map((r) => DokumentWithAuftrag(
            r.readTable(_db.dokumente), r.readTableOrNull(_db.auftraege)))
        .toList());
  }

  Future<int> upsert(DokumenteCompanion entry) async {
    if (entry.id.present) {
      await (_db.update(_db.dokumente)
            ..where((t) => t.id.equals(entry.id.value)))
          .write(entry.copyWith(updatedAt: Value(DateTime.now())));
      return entry.id.value;
    }
    return _db.into(_db.dokumente).insert(entry);
  }

  Future<int> delete(int id) =>
      (_db.delete(_db.dokumente)..where((t) => t.id.equals(id))).go();

  Future<DokumenteData?> byId(int id) =>
      (_db.select(_db.dokumente)..where((t) => t.id.equals(id)))
          .getSingleOrNull();
}

final dokumenteRepositoryProvider =
    Provider<DokumenteRepository>((ref) {
  return DokumenteRepository(ref.watch(appDatabaseProvider));
});

class DokumenteFilter {
  final int? auftragId;
  final String query;
  final String? kategorie;
  const DokumenteFilter({this.auftragId, this.query = '', this.kategorie});
  DokumenteFilter copyWith({
    int? auftragId,
    String? query,
    String? kategorie,
    bool clearAuftrag = false,
    bool clearKategorie = false,
  }) =>
      DokumenteFilter(
        auftragId:
            clearAuftrag ? null : (auftragId ?? this.auftragId),
        query: query ?? this.query,
        kategorie:
            clearKategorie ? null : (kategorie ?? this.kategorie),
      );
}

final dokumenteFilterProvider =
    StateProvider<DokumenteFilter>((ref) => const DokumenteFilter());

final dokumenteListProvider =
    StreamProvider<List<DokumentWithAuftrag>>((ref) {
  final f = ref.watch(dokumenteFilterProvider);
  return ref.watch(dokumenteRepositoryProvider).watchAll(
        auftragId: f.auftragId,
        kategorie: f.kategorie,
        query: f.query,
      );
});
