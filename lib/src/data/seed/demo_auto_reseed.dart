import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/user_approval_service.dart';
import '../../features/system/einstellungen/einstellungen_repository.dart';
import '../../features/system/einstellungen/stammdaten_seed.dart';
import '../../features/system/konten/debitor_service.dart';
import '../../features/system/konten/konten_repository.dart';
import '../database/app_database.dart';
import '../database/database_provider.dart';
import '../sync/org_service.dart';
import 'demo_seed.dart';

/// Wächter, der beim Mandanten-Wechsel stille Aufräumarbeiten erledigt
/// (Einstellungen pullen, DATEV-Konten, Debitor-Nummern) und — und NUR
/// dann — den Demo-Seed einmalig lädt:
///   1) der aktive Mandant der Demo-Mandant ist,
///   2) die lokale Drift-DB komplett leer ist,
///   3) der Demo-Seed für diesen Mandanten noch nie gelaufen ist.
///
/// Punkt 3 ist wichtig, damit ein User, der seine Demo-Daten absichtlich
/// gelöscht hat, nicht beim nächsten Mandanten-Wechsel wieder mit den
/// Demo-Daten überschrieben wird. Und natürlich: Im Produktiv-Mandanten
/// wird NIE auto-geseeded — das würde echte Kunden-Daten ruinieren.
final demoAutoReseedProvider = Provider<void>((ref) {
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

    // 2) Demo-Seed NUR im Demo-Mandanten, und nur ein einziges Mal pro
    //    Browser/Session. Produktiv-Mandanten werden NIEMALS auto-geseeded.
    if (orgId == UserApprovalService.demoOrgId) {
      final prefs = await SharedPreferences.getInstance();
      final flag = 'demo_seeded_for_${orgId}_v1';
      if (!(prefs.getBool(flag) ?? false)) {
        final db = ref.read(appDatabaseProvider);
        if (await _istDbLeer(db)) {
          try {
            await ref.read(demoSeederProvider).loadAll();
            await prefs.setBool(flag, true);
          } catch (_) {}
        } else {
          // DB hat bereits Daten (z.B. nach manuellem Backup-Import) —
          // flag trotzdem setzen, damit wir nicht später doch noch seeden.
          await prefs.setBool(flag, true);
        }
      }

      // 2b) Demo-Stammdaten (Firmenname/Anschrift/Logo/Bank) automatisch
      //     setzen, sobald der Demo-Mandant aktiv ist und noch keine
      //     Firmendaten gesetzt sind. Damit erscheinen Logo + Fußzeile
      //     auf den PDFs ohne dass der Anwender erst manuell laden muss.
      try {
        final repo = ref.read(einstellungenRepositoryProvider);
        final firma = await repo.get(SettingsKeys.firmaName);
        if (firma == null || firma.trim().isEmpty) {
          await applyStammdatenProfil(repo, stammdatenDemo);
        }
      } catch (_) {}
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
