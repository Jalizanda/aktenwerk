import 'package:flutter/material.dart';

/// Wertet eine einfache arithmetische Formel aus — Unterstützte Operatoren:
/// `+`, `-`, `*`, `/` sowie Klammern. Komma wird als Dezimaltrennzeichen
/// akzeptiert. Gibt `null` zurück bei Syntaxfehlern oder Division durch 0.
double? evalFormel(String expr) {
  final t = expr.replaceAll(',', '.').replaceAll(' ', '');
  if (t.isEmpty) return null;
  try {
    final parser = FormelParser(t);
    final result = parser.parseAusdruck();
    if (!parser.atEnd) return null;
    if (result.isNaN || result.isInfinite) return null;
    return result;
  } catch (_) {
    return null;
  }
}

/// Rekursiver-Abstiegs-Parser für „Term (+|-) Term", „Faktor (*|/) Faktor",
/// „( … )" und Zahlen. Kein Exponent, keine Funktionen — reicht für die
/// üblichen Mengen-/Preisangaben.
class FormelParser {
  FormelParser(this.text);
  final String text;
  int pos = 0;

  bool get atEnd => pos >= text.length;

  String _peek() => atEnd ? '' : text[pos];
  String _read() => text[pos++];

  double parseAusdruck() {
    var v = _parseTerm();
    while (!atEnd && (_peek() == '+' || _peek() == '-')) {
      final op = _read();
      final r = _parseTerm();
      v = op == '+' ? v + r : v - r;
    }
    return v;
  }

  double _parseTerm() {
    var v = _parseFaktor();
    while (!atEnd && (_peek() == '*' || _peek() == '/')) {
      final op = _read();
      final r = _parseFaktor();
      v = op == '*' ? v * r : v / r;
    }
    return v;
  }

  double _parseFaktor() {
    if (_peek() == '(') {
      _read();
      final v = parseAusdruck();
      if (atEnd || _read() != ')') {
        throw const FormatException('fehlende Klammer');
      }
      return v;
    }
    if (_peek() == '-') {
      _read();
      return -_parseFaktor();
    }
    final start = pos;
    while (!atEnd && RegExp(r'[0-9.]').hasMatch(_peek())) {
      _read();
    }
    if (start == pos) {
      throw const FormatException('Zahl erwartet');
    }
    return double.parse(text.substring(start, pos));
  }
}

/// Interpretiert einen Text-Eingabewert als Zahl. Beginnt der Text mit `=`,
/// wird der Rest als Formel ausgewertet. Andernfalls als normale
/// Dezimalzahl (Komma erlaubt).
double parseMengeOrFormel(String raw) {
  final t = raw.trim();
  if (t.startsWith('=')) {
    final r = evalFormel(t.substring(1));
    if (r != null) return r;
  }
  return double.tryParse(t.replaceAll(',', '.')) ?? 0;
}

String _stripZeros(double v) {
  final s = v.toStringAsFixed(2);
  if (s.endsWith('.00')) return s.substring(0, s.length - 3);
  if (s.endsWith('0')) return s.substring(0, s.length - 1);
  return s;
}

/// TextField-Drop-in-Replacement, das `=`-Formeln auswertet, sobald das
/// Feld den Fokus verliert oder `Enter` gedrückt wird. Erwartet eine
/// Zahl als Nutzwert — `onChanged` bekommt den Roh-Text, das ausgewertete
/// Ergebnis wird in den Controller zurückgeschrieben.
class FormelTextField extends StatelessWidget {
  const FormelTextField({
    super.key,
    required this.controller,
    this.decoration,
    this.textAlign = TextAlign.start,
    this.keyboardType,
    this.style,
    this.onChanged,
    this.onSubmitted,
    this.enabled,
  });

  final TextEditingController controller;
  final InputDecoration? decoration;
  final TextAlign textAlign;
  final TextInputType? keyboardType;
  final TextStyle? style;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool? enabled;

  void _evaluate() {
    final t = controller.text.trim();
    if (!t.startsWith('=')) return;
    final r = evalFormel(t.substring(1));
    if (r == null) return;
    final s = _stripZeros(r);
    controller.text = s;
    controller.selection = TextSelection.collapsed(offset: s.length);
    onChanged?.call(s);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (hasFocus) {
        if (!hasFocus) _evaluate();
      },
      child: TextField(
        controller: controller,
        decoration: decoration,
        textAlign: textAlign,
        keyboardType: keyboardType ?? TextInputType.text,
        style: style,
        enabled: enabled,
        onChanged: onChanged,
        onSubmitted: (v) {
          _evaluate();
          onSubmitted?.call(controller.text);
        },
      ),
    );
  }
}
