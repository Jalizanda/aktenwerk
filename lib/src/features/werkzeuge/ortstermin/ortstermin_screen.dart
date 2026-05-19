import 'dart:async';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'ortstermin_audio_stub.dart'
    if (dart.library.html) 'ortstermin_audio_web.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/ai/audio_transkript_service.dart';
import '../../../core/ai/rechtschreibung_service.dart';
import '../../../core/geo/geo_service.dart';
import '../../../core/theme/aw_tokens.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../../data/sync/auth_service.dart';
import '../../../data/sync/storage_service.dart';
import '../../../features/akten/auftraege/auftrag_picker.dart';
import '../../../features/akten/auftraege/auftraege_repository.dart';
import '../../../features/kalkulation/stunden/stunden_repository.dart';
import '../../../features/akten/protokolle/protokolle_tab.dart';
import '../../../features/werkzeuge/fotos/foto_exif.dart';
import '../../../features/werkzeuge/fotos/fotos_repository.dart';
import '../../../shared/widgets/module_scaffold.dart';

enum _FotoQuelle { kamera, galerie, datei }

/// Eintrag im Ortstermin-Journal. Text, Foto oder Audio.
class _NotizEintrag {
  final DateTime zeit;
  final String? text;
  final Uint8List? fotoBytes;
  final String? fotoMime;
  final int? fotoDbId;
  final Uint8List? audioBytes;
  final String? audioMime;
  /// DB-ID des sofort gespeicherten Foto-Eintrags für das Audio (zum späteren Update mit Transkription).
  final int? audioDbId;
  const _NotizEintrag({
    required this.zeit,
    this.text,
    this.fotoBytes,
    this.fotoMime,
    this.fotoDbId,
    this.audioBytes,
    this.audioMime,
    this.audioDbId,
  });

  bool get isFoto => fotoBytes != null;
  bool get isAudio => audioBytes != null;
}

class OrtsterminScreen extends ConsumerStatefulWidget {
  const OrtsterminScreen({super.key});
  @override
  ConsumerState<OrtsterminScreen> createState() => _OrtsterminScreenState();
}

class _OrtsterminScreenState extends ConsumerState<OrtsterminScreen> {
  int? _auftragId;
  final _notizController = TextEditingController();
  final List<_NotizEintrag> _eintraege = [];

  /// Fortlaufender Zähler für die Audio-Nummerierung in den Transkript-
  /// Titeln ("Transkript von Audio-Aufnahme 1" etc.).
  int _audioCounter = 0;

  /// Blockiert den Notiz-Speichern-Button während die KI-Korrektur läuft.
  bool _notizKiLaeuft = false;

  /// Menge der gerade transkribierten Audios (für Spinner-Anzeige in der
  /// Journal-Zeile), geschlüsselt auf den Entry-Zeitstempel.
  final Set<DateTime> _transkribiereLaeuft = {};

  /// Spinner-Flag für den „Hier bin ich"-Button.
  bool _geoSucheLaeuft = false;

  /// Sekunden-Ticker damit die Timer-Anzeige live aktualisiert wird.
  Timer? _elapsedTicker;

  /// Holt die aktuelle GPS-Position.
  /// - Ist bereits eine Akte ausgewählt: speichert die Position auf dieser Akte
  ///   (Geo-Tagging), damit sie bei künftigen Besuchen automatisch erkannt wird.
  /// - Sonst: sucht die nächstgelegene Akte (nur Akten mit objektLat/Lon;
  ///   Radius bis 5 km). Auf größerer Distanz erscheint ein Dialog mit Top-3.
  Future<void> _akteUeberGpsFinden() async {
    setState(() => _geoSucheLaeuft = true);
    try {
      final pos = await aktuellePosition();
      if (pos == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Standort nicht verfügbar — bitte Berechtigung prüfen.'),
          ));
        }
        return;
      }

      bool success = false;
      String msg = '';

      // Akte bereits gewählt → Koordinaten auf dieser Akte speichern.
      if (_auftragId != null) {
        final db = ref.read(appDatabaseProvider);
        await (db.update(db.auftraege)..where((t) => t.id.equals(_auftragId!)))
            .write(AuftraegeCompanion(
          objektLat: Value(pos.lat),
          objektLon: Value(pos.lon),
        ));
        success = true;
        msg = 'Standort für diese Akte gespeichert.';
      } else {
        final db = ref.read(appDatabaseProvider);
        final auftraege = await db.select(db.auftraege).get();
        final kandidaten = <(AuftraegeData, double)>[];
        for (final a in auftraege) {
          if (a.objektLat == null || a.objektLon == null) continue;
          final d = distanzKm(pos, LatLon(a.objektLat!, a.objektLon!));
          kandidaten.add((a, d));
        }
        kandidaten.sort((x, y) => x.$2.compareTo(y.$2));
        if (kandidaten.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Keine Akten mit Geo-Daten gefunden. Adresse in der Akte hinterlegen.'),
            ));
          }
          return;
        }
        final naechste = kandidaten.first;
        // Bis 0.3 km automatisch wählen — mehr Distanz → User bestätigen.
        if (naechste.$2 <= 0.3) {
          setState(() => _auftragId = naechste.$1.id);
          success = true;
          msg = 'Akte „${naechste.$1.aktenzeichen ?? naechste.$1.id}" gewählt (≈${(naechste.$2 * 1000).round()} m).';
        } else {
          // Auswahl-Dialog mit Top-3.
          if (!mounted) return;
          final picked = await showDialog<int>(
            context: context,
            useRootNavigator: true,
            builder: (_) => SimpleDialog(
              title: const Text('Akte in der Nähe wählen'),
              children: [
                for (final (a, km) in kandidaten.take(3))
                  SimpleDialogOption(
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: true).pop(a.id),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on_outlined,
                            size: 18, color: AwTokens.orange),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                a.aktenzeichen ?? '(o. A.)',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AwTokens.orange,
                                ),
                              ),
                              if ((a.bezeichnung ?? '').isNotEmpty)
                                Text(a.bezeichnung!,
                                    style: const TextStyle(fontSize: 12)),
                              Text(
                                [
                                  a.objektStrasse,
                                  [a.objektPlz, a.objektOrt]
                                      .whereType<String>()
                                      .where((s) => s.isNotEmpty)
                                      .join(' '),
                                ]
                                    .whereType<String>()
                                    .where((s) => s.isNotEmpty)
                                    .join(', '),
                                style: const TextStyle(
                                    fontSize: 11, color: AwTokens.mute),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          km < 1
                              ? '${(km * 1000).round()} m'
                              : '${km.toStringAsFixed(1)} km',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AwTokens.mute,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
          if (picked != null) {
            setState(() => _auftragId = picked);
            success = true;
            msg = 'Akte aus der Nähe gewählt.';
          }
        }
      }

      if (success && mounted) {
        final w = await wetterNotiz(pos);
        if (w != null && mounted) {
          setState(() {
            _eintraege.insert(0, _NotizEintrag(zeit: DateTime.now(), text: w));
          });
          msg += ' Wetterdaten geladen.';
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        }
      }
    } finally {
      if (mounted) setState(() => _geoSucheLaeuft = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _elapsedTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && ref.read(stundenTimerProvider).running) setState(() {});
    });
  }

  @override
  void dispose() {
    _elapsedTicker?.cancel();
    _notizController.dispose();
    super.dispose();
  }

  String _mimeFor(String name) {
    final ext = name.toLowerCase().split('.').last;
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      _ => 'application/octet-stream',
    };
  }

  Future<void> _fotoHinzufuegen() async {
    // Quelle wählen (Kamera/Galerie) — auf dem Web zeigt der ImagePicker
    // direkt den Datei-Dialog; auf Mobile/iPad bekommt man Kamera & Galerie.
    final quelle = await _zeigeFotoQuelleDialog();
    if (quelle == null) return;

    Uint8List? bytes;
    String name = 'foto_${DateTime.now().millisecondsSinceEpoch}.jpg';
    if (quelle == _FotoQuelle.kamera || quelle == _FotoQuelle.galerie) {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: quelle == _FotoQuelle.kamera
            ? ImageSource.camera
            : ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 2400,
      );
      if (picked == null) return;
      bytes = await picked.readAsBytes();
      name = picked.name;
    } else {
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.image,
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final f = res.files.first;
      if (f.bytes == null) return;
      bytes = f.bytes!;
      name = f.name;
    }
    if (!mounted) return;

    final beschreibung = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _FotoTextDialog(bytes: bytes!),
    );
    if (beschreibung == null) return;

    final mime = _mimeFor(name);
    final fotoRepo = ref.read(fotosRepositoryProvider);
    final storage = ref.read(storageServiceProvider);
    final auth = ref.read(authServiceProvider);
    final cloudReady = storage.enabled && auth.currentUser != null;

    String? storageUrl;
    String? storagePfad;
    if (cloudReady && _auftragId != null) {
      try {
        storagePfad =
            'fotos/ortstermin_${DateTime.now().millisecondsSinceEpoch}_$name';
        storageUrl = await storage.uploadBytes(
          storagePfad,
          bytes: bytes,
          contentType: mime,
        );
      } catch (_) {
        storageUrl = null;
        storagePfad = null;
      }
    }

    int? fotoId;
    if (_auftragId != null) {
      final exif = await readExif(bytes);
      final reihenfolge = await nextReihenfolgeFor(
          ref.read(appDatabaseProvider), _auftragId);
      fotoId = await fotoRepo.upsert(FotosCompanion.insert(
        auftragId: Value(_auftragId),
        titel: Value(name),
        beschreibung:
            beschreibung.isEmpty ? const Value.absent() : Value(beschreibung),
        aufnahmeAm: Value(exif.aufnahmeAm ?? DateTime.now()),
        lat: Value(exif.lat),
        lon: Value(exif.lon),
        reihenfolge: Value(reihenfolge),
        mimeType: Value(mime),
        storageUrl: Value(storageUrl),
        storagePfad: Value(storagePfad),
        daten: Value(bytes),
      ));
    }

    setState(() {
      _eintraege.insert(
          0,
          _NotizEintrag(
            zeit: DateTime.now(),
            text: beschreibung.isEmpty ? null : beschreibung,
            fotoBytes: bytes,
            fotoMime: mime,
            fotoDbId: fotoId,
          ));
    });
  }

  Future<void> _openProtokoll() async {
    final id = _auftragId;
    if (id == null) return;
    final list =
        await ref.read(auftraegeRepositoryProvider).watchAll().first;
    final auftrag =
        list.where((a) => a.auftrag.id == id).firstOrNull?.auftrag;
    if (auftrag == null || !mounted) return;
    await showDialog(
      context: context,
      useRootNavigator: true,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820, maxHeight: 780),
          child: ProtokolleTab(auftrag: auftrag),
        ),
      ),
    );
  }

  Future<_FotoQuelle?> _zeigeFotoQuelleDialog() async {
    return showModalBottomSheet<_FotoQuelle>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Kamera'),
              subtitle: const Text('Foto jetzt aufnehmen'),
              onTap: () => Navigator.pop(context, _FotoQuelle.kamera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galerie / Dateien'),
              subtitle: const Text('Vorhandenes Foto wählen'),
              onTap: () => Navigator.pop(context, _FotoQuelle.galerie),
            ),
            if (kIsWeb)
              ListTile(
                leading: const Icon(Icons.folder_open_outlined),
                title: const Text('Datei-Dialog (Web)'),
                subtitle: const Text('Vom Rechner hochladen'),
                onTap: () => Navigator.pop(context, _FotoQuelle.datei),
              ),
          ],
        ),
      ),
    );
  }

  /// Notiz sofort 1:1 ins Journal — kein KI-Durchlauf.
  void _notizSpeichernDirekt() {
    final text = _notizController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _eintraege.insert(0, _NotizEintrag(zeit: DateTime.now(), text: text));
      _notizController.clear();
    });
  }

  /// Notiz mit KI-Rechtschreibkorrektur ins Journal.
  Future<void> _notizSpeichern() async {
    final text = _notizController.text.trim();
    if (text.isEmpty) return;

    setState(() => _notizKiLaeuft = true);
    String korrigiert = text;
    try {
      korrigiert = await kiAnwenden(ref, text, KiModus.korrektur)
          .timeout(const Duration(seconds: 10), onTimeout: () => text);
    } catch (_) {
      korrigiert = text;
    }
    if (!mounted) return;
    setState(() {
      _eintraege.insert(
          0, _NotizEintrag(zeit: DateTime.now(), text: korrigiert));
      _notizController.clear();
      _notizKiLaeuft = false;
    });
  }

  void _timerStart() {
    if (_auftragId == null) return;
    ref.read(stundenTimerProvider.notifier).update((s) => s.copyWith(
          startedAt: DateTime.now(),
          auftragId: _auftragId,
          taetigkeit: 'Ortstermin',
        ));
  }

  Future<void> _timerStop() async {
    final state = ref.read(stundenTimerProvider);
    if (!state.running || state.auftragId == null) return;
    final elapsed = DateTime.now().difference(state.startedAt!).inMinutes;
    await ref.read(stundenRepositoryProvider).upsert(StundenCompanion.insert(
          auftragId: Value(state.auftragId),
          datum: Value(DateTime.now()),
          beginn: Value(state.startedAt),
          ende: Value(DateTime.now()),
          minuten: Value(elapsed == 0 ? 1 : elapsed),
          taetigkeit: const Value('Ortstermin'),
        ));
    ref.read(stundenTimerProvider.notifier).update((s) => s.copyWith(reset: true));
  }

  Future<void> _audioHinzufuegen() async {
    Uint8List? audioBytes;
    String audioMime = 'audio/webm';

    if (kIsWeb) {
      final result = await showDialog<_AudioErgebnis?>(
        context: context,
        useRootNavigator: true,
        builder: (_) => const _WebAudioDialog(),
      );
      if (result == null) return;
      audioBytes = result.bytes;
      audioMime = result.mime;
    } else {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final f = res.files.first;
      if (f.bytes == null) return;
      audioBytes = f.bytes!;
    }

    final audioZeit = DateTime.now();
    _audioCounter += 1;
    final aufnahmeNummer = _audioCounter;

    // Sofort in die lokale DB schreiben — unabhängig von Netz oder KI.
    int? audioDbId;
    if (_auftragId != null) {
      try {
        final fotoRepo = ref.read(fotosRepositoryProvider);
        final reihenfolge = await nextReihenfolgeFor(
            ref.read(appDatabaseProvider), _auftragId);
        final dateiname =
            'Sprachnotiz_${DateFormat('yyyyMMdd_HHmmss').format(audioZeit)}';
        audioDbId = await fotoRepo.upsert(FotosCompanion.insert(
          auftragId: Value(_auftragId),
          titel: Value(dateiname),
          mimeType: Value(audioMime),
          daten: Value(audioBytes),
          reihenfolge: Value(reihenfolge),
          aufnahmeAm: Value(audioZeit),
        ));
      } catch (_) {
        // DB-Fehler dürfen die Aufnahme nicht blockieren — weiter mit Memory-only.
      }
    }

    setState(() {
      _eintraege.insert(
          0,
          _NotizEintrag(
            zeit: audioZeit,
            audioBytes: audioBytes,
            audioMime: audioMime,
            audioDbId: audioDbId,
          ));
      _transkribiereLaeuft.add(audioZeit);
    });

    // Transkription läuft im Hintergrund — Nutzer kann weiterarbeiten.
    _transkribiereImHintergrund(
      bytes: audioBytes,
      mime: audioMime,
      audioZeit: audioZeit,
      nummer: aufnahmeNummer,
      audioDbId: audioDbId,
    );
  }

  Future<void> _transkribiereImHintergrund({
    required Uint8List bytes,
    required String mime,
    required DateTime audioZeit,
    required int nummer,
    int? audioDbId,
  }) async {
    try {
      final ergebnis = await transkribiereAudio(ref, bytes, mime);
      final text = ergebnis.kombiniert(nummer);

      // Transkription im DB-Eintrag nachholen, falls Audio bereits gespeichert.
      if (audioDbId != null) {
        try {
          await ref.read(fotosRepositoryProvider).upsert(
                FotosCompanion(
                  id: Value(audioDbId),
                  beschreibung: Value(text),
                ),
              );
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _transkribiereLaeuft.remove(audioZeit);
        _eintraege.insert(
          0,
          _NotizEintrag(zeit: DateTime.now(), text: text),
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _transkribiereLaeuft.remove(audioZeit));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('Transkription von Aufnahme $nummer fehlgeschlagen: $e')),
      );
    }
  }

  Future<void> _alleInAuftragUebernehmen() async {
    if (_auftragId == null || _eintraege.isEmpty) return;
    final repo = ref.read(auftraegeRepositoryProvider);
    final auftrag = await repo.byId(_auftragId!);
    if (auftrag == null) return;
    final oldNotiz = auftrag.notiz ?? '';
    final fmt = DateFormat('dd.MM.yyyy HH:mm');
    final texte = _eintraege.where((e) => (e.text ?? '').isNotEmpty).toList();
    final neueNotiz = texte
        .map((n) =>
            '[${fmt.format(n.zeit)}${n.isFoto ? ' · 📷 Foto' : ''}] ${n.text}')
        .join('\n');
    if (neueNotiz.isEmpty) return;
    await repo.upsert(AuftraegeCompanion(
      id: Value(auftrag.id),
      notiz: Value('$oldNotiz\n\n$neueNotiz'.trim()),
    ));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('${texte.length} Einträge in Auftrag übernommen')),
      );
      setState(_eintraege.clear);
    }
  }

  @override
  Widget build(BuildContext context) {
    final timer = ref.watch(stundenTimerProvider);
    final elapsed = timer.startedAt == null
        ? Duration.zero
        : DateTime.now().difference(timer.startedAt!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.place_outlined,
          title: 'Ortstermin-Modus',
          subtitle: 'Vor Ort: Fotos mit Text, Notizen, Audio, Zeiterfassung',
          actions: [
            OutlinedButton.icon(
              icon: const Icon(Icons.my_location, size: 16),
              label: const Text('Hier bin ich'),
              onPressed: _geoSucheLaeuft ? null : _akteUeberGpsFinden,
            ),
            FilledButton.icon(
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Protokoll erfassen'),
              onPressed: _auftragId == null ? null : () => _openProtokoll(),
            ),
          ],
          filters: [
            SizedBox(
              width: 360,
              child: AuftragPickerField(
                auftragId: _auftragId,
                onChanged: (id) => setState(() => _auftragId = id),
              ),
            ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: LayoutBuilder(
              builder: (context, c) {
                final wide = c.maxWidth > 900;
                final left = _ActionsColumn(
                  timer: timer,
                  elapsed: elapsed,
                  notizCtrl: _notizController,
                  auftragSelected: _auftragId != null,
                  onFoto: _fotoHinzufuegen,
                  onNotiz: _notizSpeichern,
                  onNotizDirekt: _notizSpeichernDirekt,
                  onTimer:
                      _auftragId == null ? null : (timer.running ? _timerStop : _timerStart),
                  onAudio: _audioHinzufuegen,
                  notizKiLaeuft: _notizKiLaeuft,
                );
                final right = _JournalPanel(
                  eintraege: _eintraege,
                  transkribiereLaeuft: _transkribiereLaeuft,
                  onUebernehmen: _auftragId == null || _eintraege.isEmpty
                      ? null
                      : _alleInAuftragUebernehmen,
                  onRemove: (i) => setState(() => _eintraege.removeAt(i)),
                );
                if (!wide) {
                  return ListView(
                    children: [left, const SizedBox(height: 20), right],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: left),
                    const SizedBox(width: 20),
                    Expanded(flex: 3, child: right),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionsColumn extends StatelessWidget {
  const _ActionsColumn({
    required this.timer,
    required this.elapsed,
    required this.notizCtrl,
    required this.auftragSelected,
    required this.onFoto,
    required this.onNotiz,
    required this.onNotizDirekt,
    required this.onTimer,
    required this.onAudio,
    required this.notizKiLaeuft,
  });
  final TimerState timer;
  final Duration elapsed;
  final TextEditingController notizCtrl;
  final bool auftragSelected;
  final VoidCallback? onFoto;
  final VoidCallback onNotiz;
  final VoidCallback onNotizDirekt;
  final VoidCallback? onTimer;
  final VoidCallback onAudio;
  final bool notizKiLaeuft;

  String _fmt(Duration d) =>
      '${d.inHours.toString().padLeft(2, '0')}:'
      '${(d.inMinutes % 60).toString().padLeft(2, '0')}:'
      '${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ActionCard(
          icon: Icons.photo_camera_outlined,
          title: 'Foto mit Text',
          subtitle: auftragSelected
              ? 'Bild wählen → Beschreibung → Journal'
              : 'Bitte zuerst Auftrag auswählen',
          onTap: auftragSelected ? onFoto : null,
        ),
        const SizedBox(height: 12),
        _ActionCard(
          icon: Icons.mic_none_outlined,
          title: 'Audio-Aufnahme',
          subtitle: kIsWeb
              ? 'Mikrofon mit Pause (Browser/iPad/iPhone)'
              : 'Audio-Datei wählen',
          onTap: onAudio,
        ),
        const SizedBox(height: 12),
        _ActionCard(
          icon: timer.running
              ? Icons.stop_circle_outlined
              : Icons.play_circle_outline,
          title: timer.running ? 'Timer stoppen' : 'Timer starten',
          subtitle: timer.running
              ? 'Läuft ${_fmt(elapsed)}'
              : 'Zeit für Ortstermin erfassen',
          onTap: onTimer,
        ),
        const SizedBox(height: 12),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text('Schnell-Notiz',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(width: 8),
                    Tooltip(
                      message:
                          'Beim Hinzufügen prüft die KI den Text einmal auf '
                          'Rechtschreibung und Grammatik.',
                      child: Icon(Icons.auto_fix_high,
                          size: 16,
                          color:
                              Theme.of(context).colorScheme.primary),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: notizCtrl,
                  minLines: 6,
                  maxLines: 14,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText:
                        'Was soll festgehalten werden? (freier Text, die KI korrigiert beim Hinzufügen)',
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: notizKiLaeuft ? null : onNotizDirekt,
                      icon: const Icon(Icons.save_outlined, size: 16),
                      label: const Text('Direkt speichern'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: notizKiLaeuft ? null : onNotiz,
                      icon: notizKiLaeuft
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white),
                            )
                          : const Icon(Icons.auto_fix_high, size: 16),
                      label: Text(notizKiLaeuft ? 'KI prüft …' : 'Mit KI'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _JournalPanel extends StatelessWidget {
  const _JournalPanel({
    required this.eintraege,
    required this.onUebernehmen,
    required this.onRemove,
    required this.transkribiereLaeuft,
  });
  final List<_NotizEintrag> eintraege;
  final VoidCallback? onUebernehmen;
  final void Function(int index) onRemove;

  /// Zeiten der Audio-Einträge, für die gerade transkribiert wird.
  final Set<DateTime> transkribiereLaeuft;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('HH:mm:ss');
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side:
            BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Gesammelte Notizen',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (onUebernehmen != null)
                  TextButton.icon(
                    onPressed: onUebernehmen,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('In Auftrag übernehmen'),
                  ),
              ],
            ),
            const Divider(),
            if (eintraege.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Text(
                      'Noch keine Einträge. Füge Fotos, Audios oder Notizen hinzu.'),
                ),
              )
            else
              for (var i = 0; i < eintraege.length; i++)
                _JournalItem(
                  eintrag: eintraege[i],
                  timeFmt: fmt,
                  onDelete: () => onRemove(i),
                  transkribiert:
                      transkribiereLaeuft.contains(eintraege[i].zeit),
                ),
          ],
        ),
      ),
    );
  }
}

class _JournalItem extends StatelessWidget {
  const _JournalItem({
    required this.eintrag,
    required this.timeFmt,
    required this.onDelete,
    this.transkribiert = false,
  });
  final _NotizEintrag eintrag;
  final DateFormat timeFmt;
  final VoidCallback onDelete;
  final bool transkribiert;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (eintrag.isFoto)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                eintrag.fotoBytes!,
                width: 72,
                height: 72,
                fit: BoxFit.cover,
              ),
            )
          else if (eintrag.isAudio)
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.graphic_eq,
                  size: 32,
                  color: Theme.of(context).colorScheme.onPrimaryContainer),
            )
          else
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.notes,
                  size: 20,
                  color: Theme.of(context).colorScheme.onPrimaryContainer),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  timeFmt.format(eintrag.zeit),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
                if ((eintrag.text ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(eintrag.text!),
                ],
                if (eintrag.isAudio) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Audio-Aufnahme · ${(eintrag.audioBytes!.lengthInBytes / 1024).toStringAsFixed(0)} KB',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (transkribiert) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 6),
                        Text('KI transkribiert …',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                      fontStyle: FontStyle.italic,
                                    )),
                      ],
                    ),
                  ],
                ],
                if (eintrag.isFoto && eintrag.fotoDbId != null) ...[
                  const SizedBox(height: 4),
                  Text('→ im Modul Fotos gespeichert',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          )),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Aus Journal entfernen',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _FotoTextDialog extends StatefulWidget {
  const _FotoTextDialog({required this.bytes});
  final Uint8List bytes;
  @override
  State<_FotoTextDialog> createState() => _FotoTextDialogState();
}

class _FotoTextDialogState extends State<_FotoTextDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.photo_camera_outlined),
                  const SizedBox(width: 10),
                  Text('Foto mit Text',
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  widget.bytes,
                  fit: BoxFit.contain,
                  height: 260,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ctrl,
                minLines: 2,
                maxLines: 4,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Beschreibung / Anmerkung',
                  border: OutlineInputBorder(),
                  hintText:
                      'z. B. Salzausblühungen Sockel · Fassade Süd · …',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Spacer(),
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Abbrechen')),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('Hinzufügen'),
                    onPressed: () =>
                        Navigator.pop(context, _ctrl.text.trim()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AudioErgebnis {
  final Uint8List bytes;
  final String mime;
  const _AudioErgebnis(this.bytes, this.mime);
}

/// Web-Dialog zum Aufnehmen/Pausieren über die MediaRecorder-API.
/// Die eigentliche JS-Integration liegt in `ortstermin_audio_web.dart`.
class _WebAudioDialog extends StatefulWidget {
  const _WebAudioDialog();
  @override
  State<_WebAudioDialog> createState() => _WebAudioDialogState();
}

class _WebAudioDialogState extends State<_WebAudioDialog> {
  bool _recording = false;
  bool _paused = false;
  Duration _duration = Duration.zero;
  String? _error;
  Object? _recorder; // platform-specific handle

  @override
  void dispose() {
    _stopRecorder(discard: true);
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final handle = await ortsterminAudioStart((d) {
        if (mounted) setState(() => _duration = d);
      });
      setState(() {
        _recorder = handle;
        _recording = true;
        _paused = false;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'Mikrofon nicht verfügbar: $e');
    }
  }

  void _pause() {
    if (_recorder == null) return;
    try {
      ortsterminAudioPause(_recorder!);
      setState(() => _paused = true);
    } catch (_) {}
  }

  void _resume() {
    if (_recorder == null) return;
    try {
      ortsterminAudioResume(_recorder!);
      setState(() => _paused = false);
    } catch (_) {}
  }

  Future<void> _stopAndReturn() async {
    if (_recorder == null) {
      Navigator.pop(context);
      return;
    }
    final result = await ortsterminAudioStop(_recorder!);
    _recorder = null;
    if (!mounted) return;
    Navigator.pop(
        context,
        result == null
            ? null
            : _AudioErgebnis(result.$1, result.$2));
  }

  Future<void> _stopRecorder({bool discard = false}) async {
    if (_recorder == null) return;
    try {
      await ortsterminAudioStop(_recorder!);
    } catch (_) {}
    _recorder = null;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.mic_none_outlined),
                  const SizedBox(width: 10),
                  Text('Audio-Aufnahme',
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _fmt(_duration),
                style: const TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()]),
              ),
              const SizedBox(height: 4),
              Text(
                _recording
                    ? (_paused ? 'pausiert' : 'aufnahme läuft')
                    : 'bereit',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12)),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  if (!_recording)
                    FilledButton.icon(
                      icon: const Icon(Icons.fiber_manual_record,
                          color: Colors.red),
                      label: const Text('Start'),
                      onPressed: _start,
                    )
                  else ...[
                    if (!_paused)
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.pause),
                        label: const Text('Pause'),
                        onPressed: _pause,
                      )
                    else
                      FilledButton.icon(
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Weiter'),
                        onPressed: _resume,
                      ),
                    FilledButton.icon(
                      icon: const Icon(Icons.stop),
                      label: const Text('Speichern'),
                      onPressed: _stopAndReturn,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final color = enabled
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side:
            BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(icon, size: 36, color: color),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context).textTheme.titleMedium),
                    Text(subtitle,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
