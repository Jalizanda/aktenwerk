import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/norm_rag_service.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

/// Persistenz-Layer für gespeicherte Normen-Chat-Verläufe mit Cloud-Sync.
class NormChatHistoryRepository {
  NormChatHistoryRepository(this._db, [FirebaseFirestore? firestore])
      : _firestore = firestore ?? FirebaseFirestore.instance;
  final AppDatabase _db;
  final FirebaseFirestore _firestore;

  StreamSubscription? _cloudSub;

  Stream<List<NormChat>> watchAll() {
    // 1. Aus Firestore im Hintergrund nachladen & Live-Sync starten
    _syncFromFirestore();
    _starteLiveSync();

    return (_db.select(_db.normChats)
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .watch();
  }

  void _starteLiveSync() {
    if (_cloudSub != null) return;
    try {
      _cloudSub = _firestore
          .collection('norm_chats')
          .snapshots()
          .listen((snap) async {
        for (final doc in snap.docs) {
          final d = doc.data();
          final rawId = d['id'];
          final id = (rawId is num) ? rawId.toInt() : int.tryParse(doc.id);
          if (id == null) continue;
          final titel = d['titel']?.toString() ?? 'Normen-Chat';
          final json = d['nachrichtenJson']?.toString() ?? '[]';
          final ts = (d['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now();

          await _db.into(_db.normChats).insertOnConflictUpdate(
                NormChatsCompanion(
                  id: Value(id),
                  titel: Value(titel),
                  nachrichtenJson: Value(json),
                  updatedAt: Value(ts),
                ),
              );
        }
      }, onError: (_) {/* Offline / Best-effort */});
    } catch (_) {}
  }

  Future<void> _syncFromFirestore() async {
    try {
      // 1. Alle Cloud-Chats herunterladen und lokal integrieren (Cloud hat Vorrang)
      final snap = await _firestore
          .collection('norm_chats')
          .orderBy('updatedAt', descending: true)
          .get();
      for (final doc in snap.docs) {
        final d = doc.data();
        final rawId = d['id'];
        final id = (rawId is num) ? rawId.toInt() : int.tryParse(doc.id);
        if (id == null) continue;
        final titel = d['titel']?.toString() ?? 'Normen-Chat';
        final json = d['nachrichtenJson']?.toString() ?? '[]';
        final ts = (d['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now();

        await _db.into(_db.normChats).insertOnConflictUpdate(
              NormChatsCompanion(
                id: Value(id),
                titel: Value(titel),
                nachrichtenJson: Value(json),
                updatedAt: Value(ts),
              ),
            );
      }

      // 2. Lokale Chats in die Cloud hochladen, falls in der Cloud noch nicht vorhanden
      final localChats = await _db.select(_db.normChats).get();
      for (final c in localChats) {
        try {
          final cloudDoc = await _firestore.collection('norm_chats').doc('${c.id}').get();
          if (cloudDoc.exists) {
            final cloudTs = (cloudDoc.data()?['updatedAt'] as Timestamp?)?.toDate();
            if (cloudTs != null && !c.updatedAt.isAfter(cloudTs)) {
              // Cloud ist bereits gleich oder neuer -> nicht überschreiben
              continue;
            }
          }
          await _firestore.collection('norm_chats').doc('${c.id}').set({
            'id': c.id,
            'titel': c.titel,
            'nachrichtenJson': c.nachrichtenJson,
            'updatedAt': c.updatedAt,
          }, SetOptions(merge: true));
        } catch (_) {}
      }
    } catch (_) {/* Offline / Best-effort */}
  }

  Future<NormChat?> byId(int id) async {
    final local = await (_db.select(_db.normChats)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (local != null) return local;

    // Fallback Cloud-Abruf
    try {
      final doc = await _firestore.collection('norm_chats').doc('$id').get();
      if (doc.exists) {
        final d = doc.data()!;
        final titel = d['titel']?.toString() ?? 'Normen-Chat';
        final json = d['nachrichtenJson']?.toString() ?? '[]';
        final ts = (d['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now();
        await _db.into(_db.normChats).insertOnConflictUpdate(
              NormChatsCompanion(
                id: Value(id),
                titel: Value(titel),
                nachrichtenJson: Value(json),
                updatedAt: Value(ts),
              ),
            );
        return (_db.select(_db.normChats)..where((t) => t.id.equals(id))).getSingleOrNull();
      }
    } catch (_) {}
    return null;
  }

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
    int targetId;
    if (id == null) {
      targetId = await _db.into(_db.normChats).insert(NormChatsCompanion.insert(
            titel: autoTitel,
            nachrichtenJson: json,
          ));
    } else {
      targetId = id;
      await (_db.update(_db.normChats)..where((t) => t.id.equals(id))).write(
        NormChatsCompanion(
          titel: Value(autoTitel),
          nachrichtenJson: Value(json),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }

    // In Cloud Firestore sichern für alle Domains & Geräte
    try {
      await _firestore.collection('norm_chats').doc('$targetId').set({
        'id': targetId,
        'titel': autoTitel,
        'nachrichtenJson': json,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}

    return targetId;
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
    try {
      await _firestore.collection('norm_chats').doc('$id').set({
        'titel': t,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> delete(int id) async {
    await (_db.delete(_db.normChats)..where((t) => t.id.equals(id))).go();
    try {
      await _firestore.collection('norm_chats').doc('$id').delete();
    } catch (_) {}
  }

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
        'anhaenge': n.anhaenge.map((a) => a.toMap()).toList(),
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
    final anhaengeRaw = raw['anhaenge'];
    final anhaenge = (anhaengeRaw is List)
        ? anhaengeRaw
            .whereType<Map>()
            .map((a) => NormChatAnhang.fromMap(a))
            .toList()
        : <NormChatAnhang>[];
    final zeitStr = raw['zeit']?.toString();
    return NormChatNachricht(
      rolle: raw['rolle']?.toString() ?? 'user',
      text: raw['text']?.toString() ?? '',
      quellen: quellen,
      anhaenge: anhaenge,
      zeit: zeitStr != null
          ? (DateTime.tryParse(zeitStr) ?? DateTime.now())
          : DateTime.now(),
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
