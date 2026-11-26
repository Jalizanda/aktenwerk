import '../../../core/jveg/jveg_tabelle.dart';
import 'einstellungen_repository.dart';

/// Liefert den JVEG-Stundensatz zu einer Honorargruppe bzw. einem Sachgebiet.
///
/// Unterstützte Codes:
/// * `SG 4.3` (Sachgebiet nach Anlage 1 Teil 1 JVEG – für Bausachverständige)
/// * `M1`, `M2`, `M3` (medizinische/psychologische Gutachten, Anlage 1 Teil 2)
/// * alles andere → Satz „Sonstige“ aus den Einstellungen
///
/// Reihenfolge: individueller Satz aus den Einstellungen (falls gepflegt) →
/// gesetzlicher Satz aus [jvegSachgebiete]/[jvegMedizinischeGruppen] →
/// Standard-Stundensatz.
///
/// Wird im Kostenvorschuss-Dialog, im Stunden-Editor, bei Erläuterungsterminen
/// und in der JVEG-Liquidation genutzt, damit überall derselbe Satz gilt.
Future<double> stundensatzFuerHonorargruppe(
  EinstellungenRepository repo,
  String? gruppe,
) async {
  final code = (gruppe ?? '').trim();
  final upper = code.toUpperCase();

  String? overrideKey;
  switch (upper) {
    case 'M1':
      overrideKey = SettingsKeys.honorargruppeM1Satz;
      break;
    case 'M2':
      overrideKey = SettingsKeys.honorargruppeM2Satz;
      break;
    case 'M3':
      overrideKey = SettingsKeys.honorargruppeM3Satz;
      break;
    default:
      final sg = jvegSachgebietFuer(code);
      overrideKey = sg != null
          ? 'honorar.sg.${sg.nr}'
          : SettingsKeys.honorargruppeSonstigesSatz;
  }
  final raw = await repo.get(overrideKey);
  final parsed = double.tryParse((raw ?? '').replaceAll(',', '.').trim());
  if (parsed != null && parsed > 0) return parsed;

  final gesetzlich = jvegGesetzlicherSatz(code);
  if (gesetzlich != null) return gesetzlich;

  final standard = await repo.getDouble(SettingsKeys.standardStundensatz);
  return (standard != null && standard > 0) ? standard : 114;
}

/// Synchrone Variante ohne Einstellungs-Overrides (für Anzeigen/Dropdowns).
double? gesetzlicherSatzFuerHonorargruppe(String? gruppe) =>
    jvegGesetzlicherSatz(gruppe);
