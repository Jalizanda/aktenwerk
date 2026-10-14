import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      {int? auftragId, bool? abgerechnet, String? art}) {
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
    if (art != null) {
      q.where(_db.auslagen.art.equals(art));
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
  /// Auslagen-Art (`fahrt`, `kopie_sw`, `lichtbilder` …). `null` = alle Arten.
  final String? art;
  const AuslagenFilter({this.auftragId, this.abgerechnet, this.art});
  AuslagenFilter copyWith({
    int? auftragId,
    bool? abgerechnet,
    String? art,
    bool clearAuftrag = false,
    bool clearAbgerechnet = false,
    bool clearArt = false,
  }) =>
      AuslagenFilter(
        auftragId: clearAuftrag ? null : (auftragId ?? this.auftragId),
        abgerechnet:
            clearAbgerechnet ? null : (abgerechnet ?? this.abgerechnet),
        art: clearArt ? null : (art ?? this.art),
      );
}

class AuslagenFilterNotifier extends StateNotifier<AuslagenFilter> {
  AuslagenFilterNotifier() : super(const AuslagenFilter()) {
    _init();
  }
  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final aid = prefs.getInt('filter_auslagen_auftrag');
    final abg = prefs.getBool('filter_auslagen_abgerechnet');
    final art = prefs.getString('filter_auslagen_art');
    state = AuslagenFilter(auftragId: aid, abgerechnet: abg, art: art);
  }
  void update(AuslagenFilter Function(AuslagenFilter) cb) async {
    final next = cb(state);
    state = next;
    final prefs = await SharedPreferences.getInstance();
    if (next.auftragId != null) prefs.setInt('filter_auslagen_auftrag', next.auftragId!);
    else prefs.remove('filter_auslagen_auftrag');
    if (next.abgerechnet != null) prefs.setBool('filter_auslagen_abgerechnet', next.abgerechnet!);
    else prefs.remove('filter_auslagen_abgerechnet');
    if (next.art != null) prefs.setString('filter_auslagen_art', next.art!);
    else prefs.remove('filter_auslagen_art');
  }
}

final auslagenFilterProvider =
    StateNotifierProvider<AuslagenFilterNotifier, AuslagenFilter>((ref) => AuslagenFilterNotifier());

final auslagenListProvider =
    StreamProvider<List<AuslageWithAuftrag>>((ref) {
  final f = ref.watch(auslagenFilterProvider);
  return ref
      .watch(auslagenRepositoryProvider)
      .watchAll(auftragId: f.auftragId, abgerechnet: f.abgerechnet, art: f.art);
});
