import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

class WiedervorlageWithAuftrag {
  final WiedervorlagenData eintrag;
  final AuftraegeData? auftrag;
  const WiedervorlageWithAuftrag(this.eintrag, this.auftrag);
}

enum WiedervorlagenScope { alle, heute, woche, ueberfaellig, offen, erledigt }

class WiedervorlagenRepository {
  WiedervorlagenRepository(this._db);
  final AppDatabase _db;

  Stream<List<WiedervorlageWithAuftrag>> watchAll({
    WiedervorlagenScope scope = WiedervorlagenScope.offen,
    int? auftragId,
  }) {
    final q = _db.select(_db.wiedervorlagen).join([
      leftOuterJoin(_db.auftraege,
          _db.auftraege.id.equalsExp(_db.wiedervorlagen.auftragId)),
    ]);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final endOfWeek = today.add(Duration(days: 7 - today.weekday));

    switch (scope) {
      case WiedervorlagenScope.heute:
        q.where(_db.wiedervorlagen.faelligAm.isBetweenValues(today, tomorrow));
        q.where(_db.wiedervorlagen.erledigt.equals(false));
      case WiedervorlagenScope.woche:
        q.where(_db.wiedervorlagen.faelligAm
            .isBetweenValues(today, endOfWeek));
        q.where(_db.wiedervorlagen.erledigt.equals(false));
      case WiedervorlagenScope.ueberfaellig:
        q.where(_db.wiedervorlagen.faelligAm.isSmallerThanValue(today));
        q.where(_db.wiedervorlagen.erledigt.equals(false));
      case WiedervorlagenScope.offen:
        q.where(_db.wiedervorlagen.erledigt.equals(false));
      case WiedervorlagenScope.erledigt:
        q.where(_db.wiedervorlagen.erledigt.equals(true));
      case WiedervorlagenScope.alle:
        break;
    }
    if (auftragId != null) {
      q.where(_db.wiedervorlagen.auftragId.equals(auftragId));
    }
    q.orderBy([OrderingTerm(expression: _db.wiedervorlagen.faelligAm)]);
    return q.watch().map((rows) => rows
        .map((r) => WiedervorlageWithAuftrag(
            r.readTable(_db.wiedervorlagen), r.readTableOrNull(_db.auftraege)))
        .toList());
  }

  Future<int> upsert(WiedervorlagenCompanion entry) async {
    if (entry.id.present) {
      await (_db.update(_db.wiedervorlagen)
            ..where((t) => t.id.equals(entry.id.value)))
          .write(entry.copyWith(updatedAt: Value(DateTime.now())));
      return entry.id.value;
    }
    return _db.into(_db.wiedervorlagen).insert(entry);
  }

  Future<int> delete(int id) =>
      (_db.delete(_db.wiedervorlagen)..where((t) => t.id.equals(id))).go();

  Future<void> toggleErledigt(int id, bool value) async {
    await (_db.update(_db.wiedervorlagen)..where((t) => t.id.equals(id)))
        .write(WiedervorlagenCompanion(
      erledigt: Value(value),
      erledigtAm: Value(value ? DateTime.now() : null),
    ));
  }
}

final wiedervorlagenRepositoryProvider =
    Provider<WiedervorlagenRepository>((ref) {
  return WiedervorlagenRepository(ref.watch(appDatabaseProvider));
});

final wiedervorlagenScopeProvider = StateProvider<WiedervorlagenScope>(
    (ref) => WiedervorlagenScope.offen);

final wiedervorlagenListProvider =
    StreamProvider<List<WiedervorlageWithAuftrag>>((ref) {
  final scope = ref.watch(wiedervorlagenScopeProvider);
  return ref.watch(wiedervorlagenRepositoryProvider).watchAll(scope: scope);
});
