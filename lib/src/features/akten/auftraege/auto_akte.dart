import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../system/einstellungen/nummernkreis_service.dart';
import 'auftraege_repository.dart';

/// Legt automatisch eine neue Akte an, wenn beim Anlegen eines
/// Folge-Dokuments (Angebot, Rechnung, Gutachten, Anschreiben …) noch keine
/// Akte gewählt ist.
///
/// Gibt die neue Auftrag-ID zurück. Wenn `auftragId` bereits gesetzt ist,
/// passiert nichts und die bestehende ID wird zurückgegeben.
Future<int?> ensureAkte(
  WidgetRef ref, {
  required int? auftragId,
  required int? kundeId,
  String? betreff,
}) async {
  if (auftragId != null) return auftragId;

  final aktenzeichen = await ref
      .read(nummernkreisServiceProvider)
      .nextNumber(NummernkreisTyp.akte);
  final repo = ref.read(auftraegeRepositoryProvider);
  final id = await repo.upsert(
    AuftraegeCompanion.insert(
      aktenzeichen: Value(aktenzeichen),
      betreff: Value(
          (betreff != null && betreff.trim().isNotEmpty)
              ? betreff.trim()
              : 'Neue Akte'),
      kundeId: Value(kundeId),
      status: const Value('offen'),
    ),
  );
  return id;
}
