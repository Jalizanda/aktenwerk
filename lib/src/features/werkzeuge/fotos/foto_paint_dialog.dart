import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Einfaches Bemal-Werkzeug für Fotos — Stift mit Farbe und Strichstärke,
/// mit Rückgängig-Schritt, Leeren und Speichern. Das gespeicherte Bild
/// enthält das Original plus aller Striche als gerendertes PNG.
///
/// Rückgabe: `Uint8List?` — PNG-Bytes oder `null` (Abbruch).
Future<Uint8List?> showFotoPaintDialog(
    BuildContext context, Uint8List photoBytes) {
  return showDialog<Uint8List?>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (_) => _FotoPaintDialog(photoBytes: photoBytes),
  );
}

enum _Tool { stift, radiergummi, rechteck, ellipse }

class _Stroke {
  final _Tool tool;
  final List<Offset> points;
  final Color color;
  final double width;
  Offset? rectStart;
  Offset? rectEnd;
  _Stroke(this.tool, this.color, this.width) : points = [];
}

bool _looksLikeSvg(List<int> bytes) {
  if (bytes.length < 5) return false;
  final head = String.fromCharCodes(
      bytes.take(200).where((b) => b > 0 && b < 128));
  return head.contains('<svg') || head.trimLeft().startsWith('<?xml');
}

/// Rastert SVG-Bytes in ein PNG-Bild, damit das Paint-Tool damit arbeiten
/// kann. Liefert die gerenderten Pixel-Bytes (PNG).
Future<Uint8List?> _svgToPng(Uint8List svgBytes,
    {int width = 1200, int height = 900}) async {
  try {
    final info = await vg.loadPicture(SvgBytesLoader(svgBytes), null);
    final size = info.size;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    // Weißer Hintergrund, damit das Bild nicht transparent ist.
    canvas.drawRect(
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        Paint()..color = Colors.white);
    final scaleX = width / (size.width == 0 ? 1 : size.width);
    final scaleY = height / (size.height == 0 ? 1 : size.height);
    final scale = scaleX < scaleY ? scaleX : scaleY;
    final offX = (width - size.width * scale) / 2;
    final offY = (height - size.height * scale) / 2;
    canvas.translate(offX, offY);
    canvas.scale(scale);
    canvas.drawPicture(info.picture);
    info.picture.dispose();
    final picture = recorder.endRecording();
    final img = await picture.toImage(width, height);
    final byteData =
        await img.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    img.dispose();
    return byteData?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

class _FotoPaintDialog extends StatefulWidget {
  const _FotoPaintDialog({required this.photoBytes});
  final Uint8List photoBytes;
  @override
  State<_FotoPaintDialog> createState() => _FotoPaintDialogState();
}

class _FotoPaintDialogState extends State<_FotoPaintDialog> {
  final _boundaryKey = GlobalKey();
  final List<_Stroke> _strokes = [];
  Color _color = Colors.red;
  double _width = 4.0;
  _Tool _tool = _Tool.stift;
  ui.Image? _image;
  Uint8List? _rasterBytes;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _decodeImage();
  }

  Future<void> _decodeImage() async {
    Uint8List bytes = widget.photoBytes;
    if (_looksLikeSvg(bytes)) {
      final png = await _svgToPng(bytes);
      if (png != null) bytes = png;
    }
    _rasterBytes = bytes;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (mounted) setState(() => _image = frame.image);
    } catch (_) {
      // Bild kann nicht dekodiert werden — Overlay bleibt leer.
      if (mounted) setState(() => _image = null);
    }
  }

  bool get _isShapeTool =>
      _tool == _Tool.rechteck || _tool == _Tool.ellipse;

  void _startStroke(Offset p) {
    setState(() {
      final s = _Stroke(_tool, _color, _width);
      if (_isShapeTool) {
        s.rectStart = p;
        s.rectEnd = p;
      } else {
        s.points.add(p);
      }
      _strokes.add(s);
    });
  }

  void _extendStroke(Offset p) {
    if (_strokes.isEmpty) return;
    setState(() {
      final s = _strokes.last;
      if (_isShapeTool) {
        s.rectEnd = p;
      } else {
        s.points.add(p);
      }
    });
  }

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() => _strokes.removeLast());
  }

  void _clear() => setState(_strokes.clear);

  Future<void> _save() async {
    if (_image == null) return;
    setState(() => _saving = true);
    try {
      final boundary = _boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final captured = await boundary.toImage(pixelRatio: 2.0);
      final byteData =
          await captured.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData?.buffer.asUint8List();
      if (!mounted) return;
      Navigator.pop(context, bytes);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final img = _image;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 800),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.brush_outlined),
                  const SizedBox(width: 10),
                  Text('Foto bemalen',
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.undo),
                    tooltip: 'Rückgängig',
                    onPressed: _strokes.isEmpty ? null : _undo,
                  ),
                  IconButton(
                    icon: const Icon(Icons.clear_all),
                    tooltip: 'Alles löschen',
                    onPressed: _strokes.isEmpty ? null : _clear,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Abbrechen',
                    onPressed: () => Navigator.pop(context, null),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _ToolRow(
                tool: _tool,
                onToolChanged: (t) => setState(() => _tool = t),
              ),
              const SizedBox(height: 8),
              _Toolbar(
                color: _color,
                width: _width,
                onColorChanged: (c) => setState(() => _color = c),
                onWidthChanged: (w) => setState(() => _width = w),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Center(
                  child: img == null
                      ? const CircularProgressIndicator()
                      : AspectRatio(
                          aspectRatio: img.width / img.height,
                          child: RepaintBoundary(
                            key: _boundaryKey,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.memory(_rasterBytes ?? widget.photoBytes,
                                    fit: BoxFit.contain),
                                GestureDetector(
                                  onPanStart: (d) =>
                                      _startStroke(d.localPosition),
                                  onPanUpdate: (d) =>
                                      _extendStroke(d.localPosition),
                                  child: CustomPaint(
                                    painter: _StrokesPainter(_strokes),
                                    size: Size.infinite,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.pop(context, null),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_outlined),
                    label: const Text('Übernehmen'),
                    onPressed: _saving || img == null ? null : _save,
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

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.color,
    required this.width,
    required this.onColorChanged,
    required this.onWidthChanged,
  });
  final Color color;
  final double width;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<double> onWidthChanged;

  static const _palette = [
    Colors.red,
    Color(0xFFFF9800),
    Color(0xFFFFEB3B),
    Color(0xFF4CAF50),
    Color(0xFF2196F3),
    Color(0xFF9C27B0),
    Colors.black,
    Colors.white,
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final c in _palette)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: InkWell(
              onTap: () => onColorChanged(c),
              customBorder: const CircleBorder(),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: c == color
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outlineVariant,
                    width: c == color ? 3 : 1,
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(width: 12),
        const Icon(Icons.line_weight, size: 18),
        Expanded(
          child: Slider(
            value: width,
            min: 1,
            max: 20,
            divisions: 19,
            label: width.toStringAsFixed(0),
            onChanged: onWidthChanged,
          ),
        ),
      ],
    );
  }
}

class _StrokesPainter extends CustomPainter {
  _StrokesPainter(this.strokes);
  final List<_Stroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      switch (s.tool) {
        case _Tool.stift:
          _drawStift(canvas, s);
        case _Tool.radiergummi:
          _drawRadiergummi(canvas, s);
        case _Tool.rechteck:
          _drawRechteck(canvas, s);
        case _Tool.ellipse:
          _drawEllipse(canvas, s);
      }
    }
  }

  void _drawStift(Canvas c, _Stroke s) {
    final paint = Paint()
      ..color = s.color
      ..strokeWidth = s.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (var i = 1; i < s.points.length; i++) {
      c.drawLine(s.points[i - 1], s.points[i], paint);
    }
    if (s.points.length == 1) {
      c.drawCircle(s.points.first, s.width / 2,
          Paint()..color = s.color);
    }
  }

  void _drawRadiergummi(Canvas c, _Stroke s) {
    // Radiergummi malt in Hintergrundweiß mit dickerem Strich.
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = s.width * 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (var i = 1; i < s.points.length; i++) {
      c.drawLine(s.points[i - 1], s.points[i], paint);
    }
    if (s.points.length == 1) {
      c.drawCircle(s.points.first, s.width * 1.5,
          Paint()..color = Colors.white);
    }
  }

  Rect? _rect(_Stroke s) {
    final a = s.rectStart;
    final b = s.rectEnd;
    if (a == null || b == null) return null;
    return Rect.fromPoints(a, b);
  }

  void _drawRechteck(Canvas c, _Stroke s) {
    final r = _rect(s);
    if (r == null) return;
    c.drawRect(
      r,
      Paint()
        ..color = s.color
        ..strokeWidth = s.width
        ..style = PaintingStyle.stroke,
    );
  }

  void _drawEllipse(Canvas c, _Stroke s) {
    final r = _rect(s);
    if (r == null) return;
    c.drawOval(
      r,
      Paint()
        ..color = s.color
        ..strokeWidth = s.width
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _StrokesPainter oldDelegate) => true;
}

class _ToolRow extends StatelessWidget {
  const _ToolRow({required this.tool, required this.onToolChanged});
  final _Tool tool;
  final ValueChanged<_Tool> onToolChanged;

  static const _tools = <(_Tool, IconData, String)>[
    (_Tool.stift, Icons.draw_outlined, 'Stift'),
    (_Tool.rechteck, Icons.crop_square, 'Rechteck'),
    (_Tool.ellipse, Icons.circle_outlined, 'Ellipse'),
    (_Tool.radiergummi, Icons.auto_fix_normal_outlined, 'Radierer'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (t, icon, label) in _tools)
          ChoiceChip(
            selected: tool == t,
            onSelected: (_) => onToolChanged(t),
            avatar: Icon(icon,
                size: 16,
                color: tool == t ? scheme.onPrimary : scheme.onSurface),
            label: Text(label,
                style: TextStyle(
                    color:
                        tool == t ? scheme.onPrimary : scheme.onSurface)),
            selectedColor: scheme.primary,
            showCheckmark: false,
          ),
      ],
    );
  }
}
