import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

class PartnerRepository {
  PartnerRepository(this._db);
  final AppDatabase _db;

  Stream<List<PartnerData>> watchAll({String query = ''}) {
    final q = _db.select(_db.partner);
    if (query.trim().isNotEmpty) {
      final like = '%${query.trim().toLowerCase()}%';
      q.where((t) =>
          t.firma.lower().like(like) |
          t.fachgebiet.lower().like(like) |
          t.ort.lower().like(like));
    }
    q.orderBy([(t) => OrderingTerm(expression: t.firma)]);
    return q.watch();
  }

  Future<PartnerData?> byId(int id) =>
      (_db.select(_db.partner)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<int> upsert(PartnerCompanion entry) async {
    if (entry.id.present) {
      await (_db.update(_db.partner)
            ..where((t) => t.id.equals(entry.id.value)))
          .write(entry.copyWith(updatedAt: Value(DateTime.now())));
      return entry.id.value;
    }
    return _db.into(_db.partner).insert(entry);
  }

  Future<int> delete(int id) =>
      (_db.delete(_db.partner)..where((t) => t.id.equals(id))).go();
}

final partnerRepositoryProvider = Provider<PartnerRepository>((ref) {
  return PartnerRepository(ref.watch(appDatabaseProvider));
});

final partnerQueryProvider = StateProvider<String>((ref) => '');

final partnerListProvider = StreamProvider<List<PartnerData>>((ref) {
  final q = ref.watch(partnerQueryProvider);
  return ref.watch(partnerRepositoryProvider).watchAll(query: q);
});
