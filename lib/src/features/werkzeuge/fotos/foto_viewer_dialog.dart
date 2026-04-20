import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/database/app_database.dart';
import 'foto_exif.dart';
import 'foto_image.dart';

/// Full-screen Popup zum Anzeigen eines Fotos.
/// Schließen per X oben rechts oder Klick außerhalb des Bildes.
Future<void> showFotoViewer(BuildContext context, Foto foto,
    {AuftraegeData? auftrag}) async {
  await showDialog(
    context: context,
    useRootNavigator: true,
    barrierColor: Colors.black.withValues(alpha: 0.88),
    builder: (_) => _FotoViewerDialog(foto: foto, auftrag: auftrag),
  );
}

class _FotoViewerDialog extends StatefulWidget {
  const _FotoViewerDialog({required this.foto, this.auftrag});
  final Foto foto;
  final AuftraegeData? auftrag;
  @override
  State<_FotoViewerDialog> createState() => _FotoViewerDialogState();
}

class _FotoViewerDialogState extends State<_FotoViewerDialog> {
  /// 'aktuell' = aktuell gespeicherte Fassung (ggf. bemalt);
  /// 'original' = unverändertes Originalbild (nur bei bemalten Fotos).
  String _version = 'aktuell';

  double _kontrast = 1.0; // 0.5 … 2.0
  double _helligkeit = 0.0; // -1 … +1
  bool _monochrom = false;

  bool get _hasOriginal =>
      widget.foto.originalDaten != null ||
      (widget.foto.originalStorageUrl ?? '').isNotEmpty;

  Foto get _effectiveFoto {
    if (_version == 'original' && _hasOriginal) {
      return widget.foto.copyWith(
        daten: Value(widget.foto.originalDaten == null
            ? null
            : Uint8List.fromList(widget.foto.originalDaten!)),
        storageUrl: Value(widget.foto.originalStorageUrl),
        storagePfad: Value(widget.foto.originalStoragePfad),
      );
    }
    return widget.foto;
  }

  /// Berechnet eine ColorMatrix aus Kontrast, Helligkeit und Monochrom-Flag.
  List<double> get _colorMatrix {
    final c = _kontrast;
    final b = _helligkeit * 255.0;
    // Kontrast: Translate (128 - 128*c) + Scale c
    final trans = 128.0 * (1.0 - c);
    if (_monochrom) {
      // Graustufen-Koeffizienten (ITU-R BT.601)
      const r = 0.299;
      const g = 0.587;
      const bw = 0.114;
      return [
        r * c, g * c, bw * c, 0, trans + b,
        r * c, g * c, bw * c, 0, trans + b,
        r * c, g * c, bw * c, 0, trans + b,
        0, 0, 0, 1, 0,
      ];
    }
    return [
      c, 0, 0, 0, trans + b,
      0, c, 0, 0, trans + b,
      0, 0, c, 0, trans + b,
      0, 0, 0, 1, 0,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final foto = _effectiveFoto;
    final baseImage = FotoImage(foto: foto, fit: BoxFit.contain);
    final manipulatedImage = ColorFiltered(
      colorFilter: ColorFilter.matrix(_colorMatrix),
      child: baseImage,
    );
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () =>
                Navigator.of(context, rootNavigator: true).pop(),
            child: Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: manipulatedImage,
              ),
            ),
          ),
          // Oben rechts: Toolbar (Version-Switch + Bildmanipulation + X)
          Positioned(
            top: 12,
            right: 12,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_hasOriginal)
                  _DarkChip(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _VersionToggle(
                          active: _version == 'original',
                          label: 'Original',
                          onTap: () => setState(() => _version = 'original'),
                        ),
                        _VersionToggle(
                          active: _version == 'aktuell',
                          label: 'Bemalt',
                          onTap: () => setState(() => _version = 'aktuell'),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(width: 8),
                _DarkChip(
                  child: IconButton(
                    tooltip: 'Monochrom',
                    onPressed: () =>
                        setState(() => _monochrom = !_monochrom),
                    icon: Icon(
                      Icons.filter_b_and_w,
                      color: _monochrom
                          ? Colors.amber
                          : Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _DarkChip(
                  child: IconButton(
                    tooltip: 'Zurücksetzen',
                    icon: const Icon(Icons.restart_alt, color: Colors.white),
                    onPressed: () => setState(() {
                      _kontrast = 1.0;
                      _helligkeit = 0.0;
                      _monochrom = false;
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: Colors.black.withValues(alpha: 0.6),
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: 'Schließen',
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: true).pop(),
                  ),
                ),
              ],
            ),
          ),
          // Oben mittig: Slider für Kontrast + Helligkeit
          Positioned(
            top: 12,
            left: 12,
            child: _DarkChip(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.contrast,
                        size: 16, color: Colors.white70),
                    SizedBox(
                      width: 120,
                      child: Slider(
                        value: _kontrast,
                        min: 0.5,
                        max: 2.0,
                        onChanged: (v) => setState(() => _kontrast = v),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.brightness_6,
                        size: 16, color: Colors.white70),
                    SizedBox(
                      width: 120,
                      child: Slider(
                        value: _helligkeit,
                        min: -0.5,
                        max: 0.5,
                        onChanged: (v) => setState(() => _helligkeit = v),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Unten: Info-Leiste
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.75),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      if (widget.foto.reihenfolge > 0) ...[
                        Text('Nr. ${widget.foto.reihenfolge}',
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontFeatures: [
                                  FontFeature.tabularFigures()
                                ])),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Text(
                          [widget.foto.titel, widget.foto.raum]
                              .whereType<String>()
                              .where((s) => s.isNotEmpty)
                              .join(' · '),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  if ((widget.foto.beschreibung ?? '').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      widget.foto.beschreibung!,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13, height: 1.4),
                    ),
                  ],
                  if (widget.auftrag != null || widget.foto.aufnahmeAm != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      [
                        if (widget.auftrag?.aktenzeichen != null)
                          'Akte: ${widget.auftrag!.aktenzeichen}',
                        if (widget.foto.aufnahmeAm != null)
                          'Aufgenommen: ${widget.foto.aufnahmeAm!.day.toString().padLeft(2, '0')}.${widget.foto.aufnahmeAm!.month.toString().padLeft(2, '0')}.${widget.foto.aufnahmeAm!.year}',
                      ].join(' · '),
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 11),
                    ),
                  ],
                  if (widget.foto.lat != null && widget.foto.lon != null) ...[
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () => launchUrl(
                          mapUri(widget.foto.lat!, widget.foto.lon!),
                          mode: LaunchMode.externalApplication),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.place_outlined,
                              size: 14, color: Colors.white70),
                          const SizedBox(width: 4),
                          Text(
                            formatCoords(widget.foto.lat!, widget.foto.lon!),
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                decoration: TextDecoration.underline,
                                decorationColor: Colors.white38),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.open_in_new,
                              size: 12, color: Colors.white54),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DarkChip extends StatelessWidget {
  const _DarkChip({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
        ),
        child: child,
      );
}

class _VersionToggle extends StatelessWidget {
  const _VersionToggle(
      {required this.active, required this.label, required this.onTap});
  final bool active;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active ? Colors.white.withValues(alpha: 0.18) : null,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(label,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400)),
        ),
      );
}
