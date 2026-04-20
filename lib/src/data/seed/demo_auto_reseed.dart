import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/user_approval_service.dart';
import '../../features/system/einstellungen/einstellungen_repository.dart';
import '../../features/system/konten/debitor_service.dart';
import '../../features/system/konten/konten_repository.dart';
import '../database/app_database.dart';
import '../database/database_provider.dart';
import '../sync/org_service.dart';
import 'demo_seed.dart';

/// Wächter, der den Demo-Seed automatisch einmal lädt, wenn:
///   1) der aktive Mandant der Demo-Mandant ist, UND
///   2) die lokale Drift-DB (im Browser: IndexedDB) leer ist.
///
/// Hintergrund: Bei einem Schema-Upgrade werden neue Spalten ergänzt, die
/// Daten bleiben grundsätzlich erhalten (echte Migration statt Drop-All).
/// Falls aber nach einem früheren Deploy Daten verloren gingen oder der
/// User frisch im Browser ist, sorgt dieser Provider dafür, dass der
/// Demo-Mandant sofort wieder mit Beispieldaten befüllt ist.
final demoAutoReseedProvider = Provider<void>((ref) {
  // Provider wird beim App-Start initialisiert (kein Build-Cycle nötig).
  ref.listen<AsyncValue<String?>>(currentOrgIdProvider, (prev, next) async {
    final orgId = next.valueOrNull;
    if (orgId == null) return;

    // 1) Einstellungen pullen bei jedem Mandanten-Wechsel. So bleibt die
    //    Firma/USt/Bank etc. pro Mandant konsistent über alle Geräte.
    try {
      await ref
          .read(einstellungenRepositoryProvider)
          .pullFromFirestore();
    } catch (_) {}

    // 2) Demo-Daten nachladen, wenn der Demo-Mandant aktiv und die lokale
    //    DB noch leer ist.
    if (orgId == UserApprovalService.demoOrgId) {
      final db = ref.read(appDatabaseProvider);
      if (await _istDbLeer(db)) {
        try {
          await ref.read(demoSeederProvider).loadAll();
        } catch (_) {}
      }
    }

    // 3) DATEV-Standard-Konten in jeder Organisation einmalig anlegen.
    try {
      await ref.read(kontenRepositoryProvider).seedDefaults();
    } catch (_) {}

    // 4) Debitor-/Kreditor-Nummern für alle Kunden/Lieferanten ohne
    //    Nummer einmalig vergeben.
    try {
      await ref.read(debitorKreditorServiceProvider).belegeAlleKunden();
      await ref
          .read(debitorKreditorServiceProvider)
          .belegeAlleLieferanten();
    } catch (_) {}
  }, fireImmediately: true);
});

Future<bool> _istDbLeer(AppDatabase db) async {
  // „Leer" = keine Aufträge UND keine Kunden vorhanden. Das Kriterium
  // reicht, weil der Demo-Seed immer Kunden + Aufträge als Basis anlegt.
  final auftragCount = await (db.select(db.auftraege)..limit(1)).get();
  if (auftragCount.isNotEmpty) return false;
  final kundenCount = await (db.select(db.kunden)..limit(1)).get();
  return kundenCount.isEmpty;
}
