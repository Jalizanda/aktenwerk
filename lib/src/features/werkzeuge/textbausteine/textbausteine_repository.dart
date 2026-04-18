import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

class TextbausteineRepository {
  TextbausteineRepository(this._db);
  final AppDatabase _db;

  Stream<List<TextbausteineData>> watchAll(
      {String query = '', String? kategorie, bool nurFavoriten = false}) {
    final q = _db.select(_db.textbausteine);
    if (kategorie != null && kategorie.isNotEmpty) {
      q.where((t) => t.kategorie.equals(kategorie));
    }
    if (nurFavoriten) q.where((t) => t.favorit.equals(true));
    if (query.trim().isNotEmpty) {
      final like = '%${query.trim().toLowerCase()}%';
      q.where((t) =>
          t.titel.lower().like(like) | t.inhalt.lower().like(like));
    }
    q.orderBy([
      (t) => OrderingTerm(expression: t.reihenfolge),
      (t) => OrderingTerm(expression: t.titel),
    ]);
    return q.watch();
  }

  Future<int> upsert(TextbausteineCompanion entry) async {
    if (entry.id.present) {
      await (_db.update(_db.textbausteine)
            ..where((t) => t.id.equals(entry.id.value)))
          .write(entry.copyWith(updatedAt: Value(DateTime.now())));
      return entry.id.value;
    }
    return _db.into(_db.textbausteine).insert(entry);
  }

  Future<int> delete(int id) =>
      (_db.delete(_db.textbausteine)..where((t) => t.id.equals(id))).go();

  Future<List<String>> distinctKategorien() async {
    final rows = await (_db.selectOnly(_db.textbausteine, distinct: true)
          ..addColumns([_db.textbausteine.kategorie])
          ..where(_db.textbausteine.kategorie.isNotNull()))
        .get();
    return rows
        .map((r) => r.read(_db.textbausteine.kategorie))
        .whereType<String>()
        .toList()
      ..sort();
  }
}

final textbausteineRepositoryProvider =
    Provider<TextbausteineRepository>((ref) {
  return TextbausteineRepository(ref.watch(appDatabaseProvider));
});

class TextbausteineFilter {
  final String query;
  final String? kategorie;
  final bool nurFavoriten;
  const TextbausteineFilter(
      {this.query = '', this.kategorie, this.nurFavoriten = false});
  TextbausteineFilter copyWith({
    String? query,
    String? kategorie,
    bool clearKategorie = false,
    bool? nurFavoriten,
  }) =>
      TextbausteineFilter(
        query: query ?? this.query,
        kategorie: clearKategorie ? null : (kategorie ?? this.kategorie),
        nurFavoriten: nurFavoriten ?? this.nurFavoriten,
      );
}

final textbausteineFilterProvider =
    StateProvider<TextbausteineFilter>((ref) => const TextbausteineFilter());

final textbausteineListProvider =
    StreamProvider<List<TextbausteineData>>((ref) {
  final f = ref.watch(textbausteineFilterProvider);
  return ref.watch(textbausteineRepositoryProvider).watchAll(
        query: f.query,
        kategorie: f.kategorie,
        nurFavoriten: f.nurFavoriten,
      );
});

final textbausteinKategorienProvider =
    FutureProvider<List<String>>((ref) async {
  return ref.watch(textbausteineRepositoryProvider).distinctKategorien();
});
