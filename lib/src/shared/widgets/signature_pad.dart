import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Eigene Signatur-Pad-Implementierung ohne externe Abhängigkeiten.
/// Zeichnet Striche per `GestureDetector` + `CustomPainter` und kann das
/// Ergebnis als PNG-`Uint8List` oder Data-URL exportieren.
class SignaturePadController extends ChangeNotifier {
  final List<List<Offset>> _strokes = [];
  Size _canvasSize = Size.zero;

  List<List<Offset>> get strokes => List.unmodifiable(_strokes);
  bool get isEmpty => _strokes.every((s) => s.length < 2);

  void _startStroke(Offset p) {
    _strokes.add([p]);
    notifyListeners();
  }

  void _appendStroke(Offset p) {
    if (_strokes.isEmpty) {
      _strokes.add([p]);
    } else {
      _strokes.last.add(p);
    }
    notifyListeners();
  }

  void _setCanvasSize(Size s) {
    _canvasSize = s;
  }

  void clear() {
    _strokes.clear();
    notifyListeners();
  }

  /// Rendert die aktuellen Striche als PNG. Liefert null wenn leer.
  Future<Uint8List?> toPngBytes({double pixelRatio = 2.0}) async {
    if (isEmpty || _canvasSize == Size.zero) return null;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    // Weißer Hintergrund — sonst wird das PNG transparent.
    final bgPaint = Paint()..color = Colors.white;
    canvas.drawRect(
        Rect.fromLTWH(0, 0, _canvasSize.width, _canvasSize.height), bgPaint);
    for (final stroke in _strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (var i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
    final picture = recorder.endRecording();
    final width = (_canvasSize.width * pixelRatio).round();
    final height = (_canvasSize.height * pixelRatio).round();
    final image = await picture.toImage(width, height);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  }

  /// Exportiert die Signatur als `data:image/png;base64,…`-URL.
  Future<String?> toDataUrl({double pixelRatio = 2.0}) async {
    final bytes = await toPngBytes(pixelRatio: pixelRatio);
    if (bytes == null) return null;
    return 'data:image/png;base64,${base64Encode(bytes)}';
  }
}

class SignaturePad extends StatefulWidget {
  const SignaturePad({
    super.key,
    required this.controller,
    this.height = 180,
    this.backgroundColor,
    this.borderColor,
  });
  final SignaturePadController controller;
  final double height;
  final Color? backgroundColor;
  final Color? borderColor;

  @override
  State<SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<SignaturePad> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: widget.backgroundColor ?? Colors.white,
        border: Border.all(
            color: widget.borderColor ?? theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          widget.controller._setCanvasSize(size);
          return GestureDetector(
            onPanStart: (d) => widget.controller._startStroke(d.localPosition),
            onPanUpdate: (d) =>
                widget.controller._appendStroke(d.localPosition),
            child: AnimatedBuilder(
              animation: widget.controller,
              builder: (_, _) => CustomPaint(
                painter: _SigPainter(widget.controller._strokes),
                size: size,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SigPainter extends CustomPainter {
  _SigPainter(this.strokes);
  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.length < 2) {
        if (stroke.length == 1) {
          canvas.drawCircle(stroke.first, 1.2, paint);
        }
        continue;
      }
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (var i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SigPainter old) => true;
}
