import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

class StundenWithAuftrag {
  final StundenData stunde;
  final AuftraegeData? auftrag;
  const StundenWithAuftrag(this.stunde, this.auftrag);
}

class StundenRepository {
  StundenRepository(this._db);
  final AppDatabase _db;

  Stream<List<StundenWithAuftrag>> watchAll({
    int? auftragId,
    bool? abgerechnet,
  }) {
    final q = _db.select(_db.stunden).join([
      leftOuterJoin(
          _db.auftraege, _db.auftraege.id.equalsExp(_db.stunden.auftragId)),
    ]);
    if (auftragId != null) {
      q.where(_db.stunden.auftragId.equals(auftragId));
    }
    if (abgerechnet != null) {
      q.where(_db.stunden.abgerechnet.equals(abgerechnet));
    }
    q.orderBy([
      OrderingTerm(
          expression: _db.stunden.datum, mode: OrderingMode.desc),
      OrderingTerm(
          expression: _db.stunden.createdAt, mode: OrderingMode.desc),
    ]);
    return q.watch().map((rows) => rows
        .map((r) => StundenWithAuftrag(
              r.readTable(_db.stunden),
              r.readTableOrNull(_db.auftraege),
            ))
        .toList());
  }

  Future<int> upsert(StundenCompanion entry) async {
    if (entry.id.present) {
      await (_db.update(_db.stunden)
            ..where((t) => t.id.equals(entry.id.value)))
          .write(entry.copyWith(updatedAt: Value(DateTime.now())));
      return entry.id.value;
    }
    return _db.into(_db.stunden).insert(entry);
  }

  Future<int> delete(int id) =>
      (_db.delete(_db.stunden)..where((t) => t.id.equals(id))).go();

  /// Summe Minuten pro Auftrag.
  Future<int> totalMinutenFuerAuftrag(int auftragId) async {
    final row = await (_db.selectOnly(_db.stunden)
          ..addColumns([_db.stunden.minuten.sum()])
          ..where(_db.stunden.auftragId.equals(auftragId)))
        .getSingleOrNull();
    return (row?.read(_db.stunden.minuten.sum()) ?? 0).toInt();
  }
}

final stundenRepositoryProvider = Provider<StundenRepository>((ref) {
  return StundenRepository(ref.watch(appDatabaseProvider));
});

class StundenFilter {
  final int? auftragId;
  final bool? abgerechnet;
  const StundenFilter({this.auftragId, this.abgerechnet});
  StundenFilter copyWith({
    int? auftragId,
    bool? abgerechnet,
    bool clearAuftrag = false,
    bool clearAbgerechnet = false,
  }) =>
      StundenFilter(
        auftragId: clearAuftrag ? null : (auftragId ?? this.auftragId),
        abgerechnet:
            clearAbgerechnet ? null : (abgerechnet ?? this.abgerechnet),
      );
}

final stundenFilterProvider =
    StateProvider<StundenFilter>((ref) => const StundenFilter());

final stundenListProvider =
    StreamProvider<List<StundenWithAuftrag>>((ref) {
  final f = ref.watch(stundenFilterProvider);
  return ref
      .watch(stundenRepositoryProvider)
      .watchAll(auftragId: f.auftragId, abgerechnet: f.abgerechnet);
});

/// Laufender Timer-State (Start-Zeit & Auftrag). Nur im Speicher.
class TimerState {
  final DateTime? startedAt;
  final int? auftragId;
  final String? taetigkeit;
  const TimerState({this.startedAt, this.auftragId, this.taetigkeit});

  bool get running => startedAt != null;

  TimerState copyWith({
    DateTime? startedAt,
    int? auftragId,
    String? taetigkeit,
    bool reset = false,
  }) {
    if (reset) return const TimerState();
    return TimerState(
      startedAt: startedAt ?? this.startedAt,
      auftragId: auftragId ?? this.auftragId,
      taetigkeit: taetigkeit ?? this.taetigkeit,
    );
  }
}

class TimerNotifier extends StateNotifier<TimerState> {
  TimerNotifier() : super(const TimerState()) {
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final startMillis = prefs.getInt('timer_started_at');
    final aid = prefs.getInt('timer_auftrag_id');
    final t = prefs.getString('timer_taetigkeit');
    if (startMillis != null) {
      state = TimerState(
        startedAt: DateTime.fromMillisecondsSinceEpoch(startMillis),
        auftragId: aid,
        taetigkeit: t,
      );
    }
  }

  void update(TimerState Function(TimerState) cb) async {
    final next = cb(state);
    state = next;
    final prefs = await SharedPreferences.getInstance();
    if (next.startedAt == null) {
      await prefs.remove('timer_started_at');
      await prefs.remove('timer_auftrag_id');
      await prefs.remove('timer_taetigkeit');
    } else {
      await prefs.setInt('timer_started_at', next.startedAt!.millisecondsSinceEpoch);
      if (next.auftragId != null) {
        await prefs.setInt('timer_auftrag_id', next.auftragId!);
      } else {
        await prefs.remove('timer_auftrag_id');
      }
      if (next.taetigkeit != null) {
        await prefs.setString('timer_taetigkeit', next.taetigkeit!);
      } else {
        await prefs.remove('timer_taetigkeit');
      }
    }
  }
}

final stundenTimerProvider =
    StateNotifierProvider<TimerNotifier, TimerState>((ref) => TimerNotifier());
