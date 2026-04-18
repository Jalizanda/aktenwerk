import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

class AuslageWithAuftrag {
  final AuslagenData auslage;
  final AuftraegeData? auftrag;
  const AuslageWithAuftrag(this.auslage, this.auftrag);
}

class AuslagenRepository {
  AuslagenRepository(this._db);
  final AppDatabase _db;

  Stream<List<AuslageWithAuftrag>> watchAll(
      {int? auftragId, bool? abgerechnet}) {
    final q = _db.select(_db.auslagen).join([
      leftOuterJoin(
          _db.auftraege, _db.auftraege.id.equalsExp(_db.auslagen.auftragId)),
    ]);
    if (auftragId != null) {
      q.where(_db.auslagen.auftragId.equals(auftragId));
    }
    if (abgerechnet != null) {
      q.where(_db.auslagen.abgerechnet.equals(abgerechnet));
    }
    q.orderBy([
      OrderingTerm(expression: _db.auslagen.datum, mode: OrderingMode.desc),
    ]);
    return q.watch().map((rows) => rows
        .map((r) => AuslageWithAuftrag(
            r.readTable(_db.auslagen), r.readTableOrNull(_db.auftraege)))
        .toList());
  }

  Future<int> upsert(AuslagenCompanion entry) async {
    if (entry.id.present) {
      await (_db.update(_db.auslagen)
            ..where((t) => t.id.equals(entry.id.value)))
          .write(entry.copyWith(updatedAt: Value(DateTime.now())));
      return entry.id.value;
    }
    return _db.into(_db.auslagen).insert(entry);
  }

  Future<int> delete(int id) =>
      (_db.delete(_db.auslagen)..where((t) => t.id.equals(id))).go();
}

final auslagenRepositoryProvider = Provider<AuslagenRepository>((ref) {
  return AuslagenRepository(ref.watch(appDatabaseProvider));
});

class AuslagenFilter {
  final int? auftragId;
  final bool? abgerechnet;
  const AuslagenFilter({this.auftragId, this.abgerechnet});
  AuslagenFilter copyWith({
    int? auftragId,
    bool? abgerechnet,
    bool clearAuftrag = false,
    bool clearAbgerechnet = false,
  }) =>
      AuslagenFilter(
        auftragId: clearAuftrag ? null : (auftragId ?? this.auftragId),
        abgerechnet:
            clearAbgerechnet ? null : (abgerechnet ?? this.abgerechnet),
      );
}

final auslagenFilterProvider =
    StateProvider<AuslagenFilter>((ref) => const AuslagenFilter());

final auslagenListProvider =
    StreamProvider<List<AuslageWithAuftrag>>((ref) {
  final f = ref.watch(auslagenFilterProvider);
  return ref
      .watch(auslagenRepositoryProvider)
      .watchAll(auftragId: f.auftragId, abgerechnet: f.abgerechnet);
});
