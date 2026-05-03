import 'einstellungen_repository.dart';

/// Liefert den hinterlegten JVEG-Stundensatz pro Honorargruppe.
///
/// Wird sowohl im Kostenvorschuss-Dialog als auch im Stunden-Editor
/// genutzt, damit der Satz nicht händisch eingetragen werden muss.
Future<double> stundensatzFuerHonorargruppe(
  EinstellungenRepository repo,
  String? gruppe,
) async {
  String? key;
  switch ((gruppe ?? '').toUpperCase()) {
    case 'M1':
      key = SettingsKeys.honorargruppeM1Satz;
      break;
    case 'M2':
      key = SettingsKeys.honorargruppeM2Satz;
      break;
    case 'M3':
      key = SettingsKeys.honorargruppeM3Satz;
      break;
    default:
      key = SettingsKeys.honorargruppeSonstigesSatz;
  }
  final raw = await repo.get(key);
  final parsed =
      double.tryParse((raw ?? '').replaceAll(',', '.').trim());
  if (parsed != null && parsed > 0) return parsed;
  // Fallback: JVEG 2021 Default-Sätze.
  return switch ((gruppe ?? '').toUpperCase()) {
    'M1' => 70,
    'M2' => 95,
    'M3' => 130,
    _ => 95,
  };
}
