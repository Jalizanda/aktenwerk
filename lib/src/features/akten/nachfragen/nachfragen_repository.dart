import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

/// Eine einzelne Nachfrage / Frage innerhalb einer Stellungnahme.
class NachfrageEintrag {
  final String nr;
  final String frage;
  final String antwort;
  const NachfrageEintrag({
    required this.nr,
    required this.frage,
    required this.antwort,
  });

  Map<String, dynamic> toJson() =>
      {'nr': nr, 'frage': frage, 'antwort': antwort};

  factory NachfrageEintrag.fromJson(Map<String, dynamic> j) => NachfrageEintrag(
        nr: j['nr']?.toString() ?? '',
        frage: j['frage']?.toString() ?? '',
        antwort: j['antwort']?.toString() ?? '',
      );

  NachfrageEintrag copyWith({String? nr, String? frage, String? antwort}) =>
      NachfrageEintrag(
        nr: nr ?? this.nr,
        frage: frage ?? this.frage,
        antwort: antwort ?? this.antwort,
      );
}

List<NachfrageEintrag> decodeFragen(String? json) {
  if (json == null || json.trim().isEmpty) return const [];
  try {
    final raw = jsonDecode(json);
    if (raw is List) {
      return raw
          .whereType<Map<String, dynamic>>()
          .map(NachfrageEintrag.fromJson)
          .toList();
    }
  } catch (_) {}
  return const [];
}

String encodeFragen(List<NachfrageEintrag> list) =>
    jsonEncode(list.map((e) => e.toJson()).toList());

class NachfragenRepository {
  NachfragenRepository(this._db);
  final AppDatabase _db;

  Stream<List<RueckfragenData>> watchByAuftrag(int auftragId) {
    return (_db.select(_db.rueckfragen)
          ..where((t) => t.auftragId.equals(auftragId))
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.datum, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  Future<RueckfragenData?> byId(int id) =>
      (_db.select(_db.rueckfragen)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<int> upsert(RueckfragenCompanion entry) async {
    if (entry.id.present) {
      await (_db.update(_db.rueckfragen)
            ..where((t) => t.id.equals(entry.id.value)))
          .write(entry.copyWith(updatedAt: Value(DateTime.now())));
      return entry.id.value;
    }
    return _db.into(_db.rueckfragen).insert(entry);
  }

  Future<int> delete(int id) =>
      (_db.delete(_db.rueckfragen)..where((t) => t.id.equals(id))).go();
}

final nachfragenRepositoryProvider =
    Provider<NachfragenRepository>((ref) {
  return NachfragenRepository(ref.watch(appDatabaseProvider));
});

final nachfragenByAuftragProvider = StreamProvider.autoDispose
    .family<List<RueckfragenData>, int>((ref, auftragId) {
  return ref
      .watch(nachfragenRepositoryProvider)
      .watchByAuftrag(auftragId);
});
