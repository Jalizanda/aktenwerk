import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/norm_rag_service.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

/// Persistenz-Layer für gespeicherte Normen-Chat-Verläufe.
class NormChatHistoryRepository {
  NormChatHistoryRepository(this._db);
  final AppDatabase _db;

  Stream<List<NormChat>> watchAll() {
    return (_db.select(_db.normChats)
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .watch();
  }

  Future<NormChat?> byId(int id) =>
      (_db.select(_db.normChats)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  /// Speichert einen Verlauf — neu oder aktualisiert (id != null).
  /// Titel wird beim ersten Speichern automatisch aus der ersten Frage
  /// gebildet, falls leer. Liefert die ID des gespeicherten Eintrags.
  Future<int> save({
    int? id,
    required List<NormChatNachricht> nachrichten,
    String? titel,
  }) async {
    final json = jsonEncode(nachrichten.map(_nachrichtZuJson).toList());
    final autoTitel = (titel ?? '').trim().isEmpty
        ? _autoTitel(nachrichten)
        : titel!.trim();
    if (id == null) {
      return _db.into(_db.normChats).insert(NormChatsCompanion.insert(
            titel: autoTitel,
            nachrichtenJson: json,
          ));
    }
    await (_db.update(_db.normChats)..where((t) => t.id.equals(id))).write(
      NormChatsCompanion(
        titel: Value(autoTitel),
        nachrichtenJson: Value(json),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return id;
  }

  Future<void> rename(int id, String neuerTitel) async {
    final t = neuerTitel.trim();
    if (t.isEmpty) return;
    await (_db.update(_db.normChats)..where((t) => t.id.equals(id))).write(
      NormChatsCompanion(
        titel: Value(t),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> delete(int id) =>
      (_db.delete(_db.normChats)..where((t) => t.id.equals(id))).go();

  List<NormChatNachricht> ladeNachrichten(NormChat chat) {
    try {
      final list = jsonDecode(chat.nachrichtenJson);
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map(_nachrichtAusJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  String _autoTitel(List<NormChatNachricht> nachrichten) {
    final ersteUserFrage = nachrichten.firstWhere(
      (m) => m.rolle == 'user' && m.text.trim().isNotEmpty,
      orElse: () => NormChatNachricht(
          rolle: 'user', text: 'Neuer Chat', zeit: DateTime.now()),
    );
    final t = ersteUserFrage.text.trim();
    return t.length > 80 ? '${t.substring(0, 77)}…' : t;
  }

  Map<String, Object?> _nachrichtZuJson(NormChatNachricht n) => {
        'rolle': n.rolle,
        'text': n.text,
        'zeit': n.zeit.toIso8601String(),
        'quellen': n.quellen
            .map((q) => {
                  'chunkId': q.chunkId,
                  'normId': q.normId,
                  'nummer': q.nummer,
                  'titel': q.titel,
                  'page': q.page,
                  'snippet': q.snippet,
                })
            .toList(),
      };

  NormChatNachricht _nachrichtAusJson(Map raw) {
    final quellenRaw = raw['quellen'];
    final quellen = (quellenRaw is List)
        ? quellenRaw
            .whereType<Map>()
            .map((q) => NormChatQuelle(
                  chunkId: q['chunkId']?.toString() ?? '',
                  normId: (q['normId'] is num)
                      ? (q['normId'] as num).toInt()
                      : null,
                  nummer: q['nummer']?.toString() ?? '',
                  titel: q['titel']?.toString() ?? '',
                  page: (q['page'] is num) ? (q['page'] as num).toInt() : 0,
                  snippet: q['snippet']?.toString() ?? '',
                ))
            .toList()
        : <NormChatQuelle>[];
    final zeitStr = raw['zeit']?.toString();
    return NormChatNachricht(
      rolle: raw['rolle']?.toString() ?? 'user',
      text: raw['text']?.toString() ?? '',
      quellen: quellen,
      zeit: zeitStr == null
          ? DateTime.now()
          : (DateTime.tryParse(zeitStr) ?? DateTime.now()),
    );
  }
}

final normChatHistoryRepositoryProvider =
    Provider<NormChatHistoryRepository>(
  (ref) => NormChatHistoryRepository(ref.watch(appDatabaseProvider)),
);

final normChatHistoryListProvider =
    StreamProvider<List<NormChat>>((ref) {
  return ref.watch(normChatHistoryRepositoryProvider).watchAll();
});
