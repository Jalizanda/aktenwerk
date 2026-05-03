import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

/// Repository für Leistungsverzeichnisse + Positionen + Mengenermittlung
/// + eigener Katalog. Hält die Tabellen-Operationen zentral, damit der
/// Editor saubere Streams bekommt und keine SQL-Logik selbst macht.
class LvRepository {
  LvRepository(this._db);
  final AppDatabase _db;

  // ---------- LV-Kopf ----------

  Stream<List<LvKopfData>> watchAll({int? auftragId}) {
    final q = _db.select(_db.lvKopf);
    if (auftragId != null) {
      q.where((t) => t.auftragId.equals(auftragId));
    }
    q.orderBy([
      (t) => OrderingTerm(expression: t.datum, mode: OrderingMode.desc),
    ]);
    return q.watch();
  }

  Future<LvKopfData?> byId(int id) =>
      (_db.select(_db.lvKopf)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<int> upsertKopf(LvKopfCompanion entry) async {
    if (entry.id.present) {
      await (_db.update(_db.lvKopf)
            ..where((t) => t.id.equals(entry.id.value)))
          .write(entry.copyWith(updatedAt: Value(DateTime.now())));
      return entry.id.value;
    }
    return _db.into(_db.lvKopf).insert(entry);
  }

  Future<int> deleteKopf(int id) =>
      (_db.delete(_db.lvKopf)..where((t) => t.id.equals(id))).go();

  // ---------- Positionen ----------

  Stream<List<LvPositionenData>> watchPositionen(int lvId) {
    return (_db.select(_db.lvPositionen)
          ..where((t) => t.lvId.equals(lvId))
          ..orderBy([
            (t) => OrderingTerm(expression: t.sortIndex),
            (t) => OrderingTerm(expression: t.id),
          ]))
        .watch();
  }

  Future<List<LvPositionenData>> getPositionen(int lvId) {
    return (_db.select(_db.lvPositionen)
          ..where((t) => t.lvId.equals(lvId))
          ..orderBy([
            (t) => OrderingTerm(expression: t.sortIndex),
            (t) => OrderingTerm(expression: t.id),
          ]))
        .get();
  }

  Future<int> upsertPosition(LvPositionenCompanion entry) async {
    if (entry.id.present) {
      await (_db.update(_db.lvPositionen)
            ..where((t) => t.id.equals(entry.id.value)))
          .write(entry.copyWith(updatedAt: Value(DateTime.now())));
      return entry.id.value;
    }
    return _db.into(_db.lvPositionen).insert(entry);
  }

  Future<int> deletePosition(int id) =>
      (_db.delete(_db.lvPositionen)..where((t) => t.id.equals(id))).go();

  /// Berechnet die nächste Sort-Index-Position innerhalb desselben
  /// `parentId` (oder Top-Level mit `parentId == null`).
  Future<int> nextSortIndex(int lvId, int? parentId) async {
    final q = _db.select(_db.lvPositionen)
      ..where((t) => t.lvId.equals(lvId));
    if (parentId == null) {
      q.where((t) => t.parentId.isNull());
    } else {
      q.where((t) => t.parentId.equals(parentId));
    }
    q.orderBy([(t) => OrderingTerm(
        expression: t.sortIndex, mode: OrderingMode.desc)]);
    q.limit(1);
    final last = await q.getSingleOrNull();
    return (last?.sortIndex ?? -1) + 10;
  }

  // ---------- Mengenermittlung ----------

  Stream<List<LvMengenzeilenData>> watchMengen(int positionId) {
    return (_db.select(_db.lvMengenzeilen)
          ..where((t) => t.positionId.equals(positionId))
          ..orderBy([(t) => OrderingTerm(expression: t.sortIndex)]))
        .watch();
  }

  Future<int> upsertMenge(LvMengenzeilenCompanion entry) async {
    if (entry.id.present) {
      await (_db.update(_db.lvMengenzeilen)
            ..where((t) => t.id.equals(entry.id.value)))
          .write(entry);
      return entry.id.value;
    }
    return _db.into(_db.lvMengenzeilen).insert(entry);
  }

  Future<int> deleteMenge(int id) =>
      (_db.delete(_db.lvMengenzeilen)..where((t) => t.id.equals(id))).go();

  // ---------- Katalog ----------

  Stream<List<LvKatalogData>> watchKatalog({String query = ''}) {
    final q = _db.select(_db.lvKatalog);
    if (query.trim().isNotEmpty) {
      final like = '%${query.trim().toLowerCase()}%';
      q.where((t) =>
          t.kurztext.lower().like(like) |
          t.langtext.lower().like(like) |
          t.gewerk.lower().like(like) |
          t.tags.lower().like(like));
    }
    q.orderBy([
      (t) => OrderingTerm(
          expression: t.verwendungsZaehler, mode: OrderingMode.desc),
      (t) => OrderingTerm(expression: t.kurztext),
    ]);
    return q.watch();
  }

  Future<int> upsertKatalog(LvKatalogCompanion entry) async {
    if (entry.id.present) {
      await (_db.update(_db.lvKatalog)
            ..where((t) => t.id.equals(entry.id.value)))
          .write(entry.copyWith(updatedAt: Value(DateTime.now())));
      return entry.id.value;
    }
    return _db.into(_db.lvKatalog).insert(entry);
  }

  Future<int> deleteKatalog(int id) =>
      (_db.delete(_db.lvKatalog)..where((t) => t.id.equals(id))).go();

  /// Importiert den ausgelieferten Standard-Sanierungs-Katalog
  /// (`assets/data/lv_katalog_seed.json` — ca. 200 Positionen). Bestehende
  /// Einträge mit identischem Kurztext werden NICHT überschrieben — der
  /// Import ist additiv. Liefert die Anzahl neu eingefügter Positionen.
  Future<int> importStandardKatalog() async {
    final raw = await rootBundle
        .loadString('assets/data/lv_katalog_seed.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final list = (json['katalog'] as List).whereType<Map>().toList();

    // Bestehende Kurztexte einsammeln, damit wir Duplikate vermeiden.
    final vorhandene = await _db.select(_db.lvKatalog).get();
    final bekannt = vorhandene
        .map((e) => e.kurztext.trim().toLowerCase())
        .toSet();

    var neue = 0;
    for (final p in list) {
      final kurztext = (p['kurztext']?.toString() ?? '').trim();
      if (kurztext.isEmpty) continue;
      if (bekannt.contains(kurztext.toLowerCase())) continue;
      final ep = p['einzelpreis'];
      await _db.into(_db.lvKatalog).insert(LvKatalogCompanion.insert(
            kurztext: kurztext,
            langtext: Value(p['langtext']?.toString()),
            einheit: Value(p['einheit']?.toString()),
            einzelpreis: Value(ep is num ? ep.toDouble() : null),
            din276: Value(p['din276']?.toString()),
            gewerk: Value(p['gewerk']?.toString()),
            tags: Value(p['tags']?.toString()),
            quelle: const Value('seed'),
            preisstand: Value(DateTime.now()),
          ));
      neue++;
    }
    return neue;
  }

  /// Berechnet hierarchische OZ-Nummerierung neu („1", „1.1", „1.2",
  /// „2", …). Top-Level-Reihenfolge = sortIndex; Children dann in deren
  /// sortIndex-Reihenfolge. Schreibt die neuen OZ-Werte zurück.
  Future<void> renumberOz(int lvId) async {
    final all = await getPositionen(lvId);
    final byParent = <int?, List<LvPositionenData>>{};
    for (final p in all) {
      byParent.putIfAbsent(p.parentId, () => []).add(p);
    }
    for (final list in byParent.values) {
      list.sort((a, b) => a.sortIndex.compareTo(b.sortIndex));
    }
    final neueOz = <int, String>{};
    void recurse(int? parent, String prefix) {
      final list = byParent[parent] ?? [];
      for (var i = 0; i < list.length; i++) {
        final p = list[i];
        final selfOz =
            prefix.isEmpty ? '${i + 1}' : '$prefix.${i + 1}';
        neueOz[p.id] = selfOz;
        recurse(p.id, selfOz);
      }
    }
    recurse(null, '');
    for (final entry in neueOz.entries) {
      await (_db.update(_db.lvPositionen)
            ..where((t) => t.id.equals(entry.key)))
          .write(LvPositionenCompanion(
              oz: Value(entry.value), updatedAt: Value(DateTime.now())));
    }
  }

  /// Verschiebt eine Position innerhalb ihres parent-Containers eine
  /// Stelle nach oben (oder unten). Die sortIndex-Werte werden mit dem
  /// Nachbarn getauscht.
  Future<void> verschiebePosition({
    required int positionId,
    required bool nachOben,
  }) async {
    final pos = await (_db.select(_db.lvPositionen)
          ..where((t) => t.id.equals(positionId)))
        .getSingleOrNull();
    if (pos == null) return;
    final geschwister = await (_db.select(_db.lvPositionen)
          ..where((t) {
            final lv = t.lvId.equals(pos.lvId);
            return pos.parentId == null
                ? lv & t.parentId.isNull()
                : lv & t.parentId.equals(pos.parentId!);
          })
          ..orderBy([
            (t) => OrderingTerm(expression: t.sortIndex),
            (t) => OrderingTerm(expression: t.id),
          ]))
        .get();
    final idx = geschwister.indexWhere((g) => g.id == positionId);
    if (idx < 0) return;
    final ziel = nachOben ? idx - 1 : idx + 1;
    if (ziel < 0 || ziel >= geschwister.length) return;
    final nachbar = geschwister[ziel];
    // sortIndex tauschen
    await (_db.update(_db.lvPositionen)
          ..where((t) => t.id.equals(pos.id)))
        .write(LvPositionenCompanion(
            sortIndex: Value(nachbar.sortIndex),
            updatedAt: Value(DateTime.now())));
    await (_db.update(_db.lvPositionen)
          ..where((t) => t.id.equals(nachbar.id)))
        .write(LvPositionenCompanion(
            sortIndex: Value(pos.sortIndex),
            updatedAt: Value(DateTime.now())));
  }

  /// Drag-and-drop-Helper: verschiebt eine Position auf einen neuen
  /// Index in der flachen Anzeige-Reihenfolge. Berechnet automatisch
  /// den neuen `parentId` (= parent der Vor-Position) und einen neuen
  /// `sortIndex` (Mittelwert zwischen Vor- und Nach-Geschwister).
  ///
  /// `flacheReihenfolge` ist die aktuelle Liste in Druck-Reihenfolge
  /// (Top-Level + ihre Kinder rekursiv).
  Future<void> verschiebeAufIndex({
    required int positionId,
    required int neuerIndex,
    required List<LvPositionenData> flacheReihenfolge,
  }) async {
    final pos = flacheReihenfolge.firstWhere((p) => p.id == positionId);

    // Ohne die zu verschiebende Position betrachten — der Rest definiert
    // die Nachbarn am neuen Index.
    final ohne =
        flacheReihenfolge.where((p) => p.id != positionId).toList();
    final i = neuerIndex.clamp(0, ohne.length);

    // Neuer Parent: parent des direkten Vorgängers (oder dessen ID,
    // wenn Vorgänger ein Titel ist → Kind dieses Titels).
    int? neuerParent;
    if (i == 0) {
      neuerParent = null;
    } else {
      final vor = ohne[i - 1];
      if (vor.art == 'titel') {
        // Wenn die Drop-Stelle direkt nach einem Titel liegt, soll die
        // Position Kind dieses Titels werden — egal auf welcher Ebene
        // der Titel liegt.
        neuerParent = vor.id;
      } else {
        neuerParent = vor.parentId;
      }
    }

    // Titel-Positionen sind immer Top-Level (nicht in einen anderen
    // Titel verschachteln, das wäre verwirrend).
    if (pos.art == 'titel') {
      neuerParent = null;
    }

    // SortIndex bestimmen — Mittel zwischen Vor- und Nach-Position
    // mit gleichem parent.
    int? sortVor;
    int? sortNach;
    for (var j = i - 1; j >= 0; j--) {
      final p = ohne[j];
      if (p.parentId == neuerParent) {
        sortVor = p.sortIndex;
        break;
      }
      // Bei Titel-Drop: nicht über Titel-Grenze hinweg suchen.
      if (neuerParent == null && p.parentId == null) break;
    }
    for (var j = i; j < ohne.length; j++) {
      final p = ohne[j];
      if (p.parentId == neuerParent) {
        sortNach = p.sortIndex;
        break;
      }
    }

    int neuerSort;
    if (sortVor == null && sortNach == null) {
      neuerSort = 100;
    } else if (sortVor == null) {
      neuerSort = sortNach! - 10;
    } else if (sortNach == null) {
      neuerSort = sortVor + 10;
    } else if (sortNach - sortVor > 1) {
      neuerSort = (sortVor + sortNach) ~/ 2;
    } else {
      // Lücke zu klein — wir verschieben alle Geschwister-Sorts
      // um 100 nach oben, dann ist Platz.
      neuerSort = sortVor + 5;
    }

    await (_db.update(_db.lvPositionen)
          ..where((t) => t.id.equals(positionId)))
        .write(LvPositionenCompanion(
      parentId: Value(neuerParent),
      sortIndex: Value(neuerSort),
      updatedAt: Value(DateTime.now()),
    ));
  }

  /// Klont ein gesamtes LV (Kopf + Positionen + Mengenermittlung) als
  /// Bieter-Antwort zum gegebenen Original-LV. Liefert die neue ID.
  Future<int> kloneAlsBieter({
    required int basisLvId,
    required String bieterName,
    int? kundeId,
    DateTime? datum,
  }) async {
    final basis = await byId(basisLvId);
    if (basis == null) {
      throw StateError('Basis-LV nicht gefunden.');
    }
    final neueId = await _db.into(_db.lvKopf).insert(LvKopfCompanion.insert(
          bezeichnung: '${basis.bezeichnung} — Bieter $bieterName',
          untertitel: Value(basis.untertitel),
          nummer: Value('${basis.nummer ?? ""}-B'),
          auftragId: Value(basis.auftragId),
          datum: Value(datum ?? DateTime.now()),
          status: const Value('entwurf'),
          mwstSatz: Value(basis.mwstSatz),
          basisLvId: Value(basisLvId),
          bieterName: Value(bieterName),
          bieterKundeId: Value(kundeId),
        ));
    final positionen = await getPositionen(basisLvId);
    final idMap = <int, int>{};
    for (final p in positionen) {
      final neuerParent =
          p.parentId == null ? null : idMap[p.parentId];
      final neueP = await _db.into(_db.lvPositionen).insert(
            LvPositionenCompanion.insert(
              lvId: neueId,
              parentId: Value(neuerParent),
              sortIndex: Value(p.sortIndex),
              art: Value(p.art),
              oz: Value(p.oz),
              kurztext: p.kurztext,
              langtext: Value(p.langtext),
              einheit: Value(p.einheit),
              menge: Value(p.menge),
              // EP frei lassen — der Bieter trägt eigene Preise ein.
              einzelpreis: Value(p.einzelpreis),
              din276: Value(p.din276),
              gewerk: Value(p.gewerk),
              gaebUuid: Value(p.gaebUuid),
              ustSatz: Value(p.ustSatz),
            ),
          );
      idMap[p.id] = neueP;
    }
    return neueId;
  }

  /// Liefert alle Bieter-Antworten zu einem Basis-LV.
  Stream<List<LvKopfData>> watchBieter(int basisLvId) {
    return (_db.select(_db.lvKopf)
          ..where((t) => t.basisLvId.equals(basisLvId))
          ..orderBy([(t) => OrderingTerm(expression: t.bieterName)]))
        .watch();
  }

  /// Erhöht den Verwendungs-Zähler (für „Häufig verwendet"-Sortierung).
  Future<void> tickKatalog(int id) async {
    final entry = await (_db.select(_db.lvKatalog)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (entry == null) return;
    await (_db.update(_db.lvKatalog)..where((t) => t.id.equals(id)))
        .write(LvKatalogCompanion(
      verwendungsZaehler: Value(entry.verwendungsZaehler + 1),
      updatedAt: Value(DateTime.now()),
    ));
  }
}

final lvRepositoryProvider = Provider<LvRepository>((ref) {
  return LvRepository(ref.watch(appDatabaseProvider));
});

final lvListProvider = StreamProvider.autoDispose
    .family<List<LvKopfData>, int?>((ref, auftragId) {
  return ref.watch(lvRepositoryProvider).watchAll(auftragId: auftragId);
});

final lvPositionenProvider = StreamProvider.autoDispose
    .family<List<LvPositionenData>, int>((ref, lvId) {
  return ref.watch(lvRepositoryProvider).watchPositionen(lvId);
});

final lvMengenProvider = StreamProvider.autoDispose
    .family<List<LvMengenzeilenData>, int>((ref, positionId) {
  return ref.watch(lvRepositoryProvider).watchMengen(positionId);
});

final lvKatalogProvider = StreamProvider.autoDispose
    .family<List<LvKatalogData>, String>((ref, query) {
  return ref.watch(lvRepositoryProvider).watchKatalog(query: query);
});

final lvBieterProvider = StreamProvider.autoDispose
    .family<List<LvKopfData>, int>((ref, basisLvId) {
  return ref.watch(lvRepositoryProvider).watchBieter(basisLvId);
});

/// Wertet eine simple Mengenermittlungs-Formel aus. Erlaubt sind die
/// Operatoren `+ - * /`, Klammern und Komma als Dezimaltrenner.
/// Beispiele: `3,5*2,8`, `(12+8)*1,15`, `42 / 7`. Bei Fehlern → 0.
double evalFormel(String input) {
  if (input.trim().isEmpty) return 0;
  final s = input.replaceAll(',', '.').replaceAll(' ', '');
  try {
    return _Parser(s).expression();
  } catch (_) {
    return 0;
  }
}

/// Mini-Parser für arithmetische Ausdrücke (Recursive Descent).
class _Parser {
  _Parser(this._s);
  final String _s;
  int _i = 0;

  double expression() {
    var v = _term();
    while (_i < _s.length && (_s[_i] == '+' || _s[_i] == '-')) {
      final op = _s[_i++];
      final r = _term();
      v = op == '+' ? v + r : v - r;
    }
    return v;
  }

  double _term() {
    var v = _factor();
    while (_i < _s.length && (_s[_i] == '*' || _s[_i] == '/')) {
      final op = _s[_i++];
      final r = _factor();
      v = op == '*' ? v * r : (r == 0 ? 0 : v / r);
    }
    return v;
  }

  double _factor() {
    if (_i < _s.length && _s[_i] == '(') {
      _i++;
      final v = expression();
      if (_i < _s.length && _s[_i] == ')') _i++;
      return v;
    }
    final start = _i;
    while (_i < _s.length &&
        (_s.codeUnitAt(_i) >= 0x30 && _s.codeUnitAt(_i) <= 0x39 ||
            _s[_i] == '.')) {
      _i++;
    }
    return double.tryParse(_s.substring(start, _i)) ?? 0;
  }
}
