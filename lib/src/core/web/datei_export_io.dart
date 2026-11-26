import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Speichert [bytes] unter [dateiname]. Desktop: „Speichern unter“-Dialog und
/// (optional) Öffnen mit der Standard-App. Mobil: Teilen-Dialog.
/// Rückgabe: gespeicherter Pfad bzw. Dateiname, `null` bei Abbruch.
Future<String?> dateiSpeichern(
  Uint8List bytes,
  String dateiname, {
  String mime = 'application/octet-stream',
  bool oeffnen = true,
}) async {
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    final ext = dateiname.contains('.') ? dateiname.split('.').last : null;
    final pfad = await FilePicker.platform.saveFile(
      dialogTitle: 'Speichern unter',
      fileName: dateiname,
      type: ext == null ? FileType.any : FileType.custom,
      allowedExtensions: ext == null ? null : [ext],
      bytes: bytes,
    );
    if (pfad == null) return null;
    final f = File(pfad);
    if (!f.existsSync() || f.lengthSync() == 0) {
      await f.writeAsBytes(bytes, flush: true);
    }
    if (oeffnen) {
      await launchUrl(Uri.file(pfad));
    }
    return pfad;
  }
  await Share.shareXFiles(
    [XFile.fromData(bytes, name: dateiname, mimeType: mime)],
    fileNameOverrides: [dateiname],
  );
  return dateiname;
}

/// Wandelt ein HEIC-Foto in JPEG um (nur macOS, über das Systemwerkzeug
/// `sips`). Gibt `null` zurück, wenn das nicht möglich ist.
Future<Uint8List?> heicZuJpeg(Uint8List bytes) async {
  if (!Platform.isMacOS) return null;
  try {
    final tmp = await getTemporaryDirectory();
    final id = DateTime.now().microsecondsSinceEpoch;
    final ein = File('${tmp.path}/aw_heic_$id.heic');
    final aus = File('${tmp.path}/aw_heic_$id.jpg');
    await ein.writeAsBytes(bytes, flush: true);
    final r = await Process.run('/usr/bin/sips', [
      '-s', 'format', 'jpeg',
      '-s', 'formatOptions', '85',
      ein.path,
      '--out', aus.path,
    ]);
    Uint8List? out;
    if (r.exitCode == 0 && aus.existsSync()) out = await aus.readAsBytes();
    for (final f in [ein, aus]) {
      try {
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    return out;
  } catch (_) {
    return null;
  }
}
