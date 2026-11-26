import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import '../../../core/theme/aw_tokens.dart';

// ---------------------------------------------------------------------------
// 1. DATENMODELLE: TABELLE (AwTableData) & FORMELBLOCK (AwFormulaData)
// ---------------------------------------------------------------------------

class AwTableData {
  AwTableData({
    required this.rows,
    required this.alignments,
  });

  /// Zeile 0 = Kopfzeile, ab Zeile 1 = Datenzeilen.
  final List<List<String>> rows;

  /// Spaltenausrichtung pro Spalte: 'left', 'center' oder 'right'.
  final List<String> alignments;

  int get colCount => rows.isEmpty ? 0 : rows.first.length;
  int get rowCount => rows.length;

  factory AwTableData.empty({int cols = 4, int dataRows = 3}) {
    final headers = List<String>.generate(cols, (i) => 'Spalte ${i + 1}');
    final allRows = <List<String>>[
      headers,
      for (var r = 0; r < dataRows; r++) List<String>.filled(cols, ''),
    ];
    final aligns = List<String>.filled(cols, 'left');
    return AwTableData(rows: allRows, alignments: aligns);
  }

  factory AwTableData.fromJsonString(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final rawRows = (decoded['rows'] as List?) ?? const [];
        final parsedRows = rawRows
            .map((r) => (r as List).map((c) => c.toString()).toList())
            .toList();
        final rawAligns = (decoded['alignments'] as List?) ?? const [];
        final parsedAligns = rawAligns.map((a) => a.toString()).toList();
        if (parsedRows.isNotEmpty) {
          final cols = parsedRows.first.length;
          while (parsedAligns.length < cols) {
            parsedAligns.add('left');
          }
          return AwTableData(rows: parsedRows, alignments: parsedAligns);
        }
      }
    } catch (_) {}
    if (raw.trim().startsWith('|')) {
      return AwTableData.fromMarkdownLines(raw.trim().split('\n'));
    }
    return AwTableData.empty();
  }

  factory AwTableData.fromMarkdownLines(List<String> rawLines) {
    List<String> splitRow(String line) {
      var s = line.trim();
      if (s.startsWith('|')) s = s.substring(1);
      if (s.endsWith('|')) s = s.substring(0, s.length - 1);
      return s.split('|').map((c) => c.trim()).toList();
    }

    bool isSeparatorRow(List<String> cells) {
      if (cells.isEmpty) return false;
      return cells.every(
        (c) => c.isNotEmpty && RegExp(r'^:?-{2,}:?$').hasMatch(c),
      );
    }

    final parsedRows = rawLines
        .where((l) => l.trim().isNotEmpty)
        .map(splitRow)
        .toList();
    if (parsedRows.isEmpty) return AwTableData.empty();

    List<String>? sepRow;
    final cleanRows = <List<String>>[];
    for (final r in parsedRows) {
      if (isSeparatorRow(r)) {
        sepRow ??= r;
      } else {
        cleanRows.add(r);
      }
    }
    if (cleanRows.isEmpty) return AwTableData.empty();

    int numCols = 0;
    for (final r in cleanRows) {
      if (r.length > numCols) numCols = r.length;
    }
    if (numCols == 0) return AwTableData.empty();

    for (var i = 0; i < cleanRows.length; i++) {
      while (cleanRows[i].length < numCols) {
        cleanRows[i].add('');
      }
    }

    final aligns = List<String>.filled(numCols, 'left');
    if (sepRow != null) {
      for (var c = 0; c < numCols && c < sepRow.length; c++) {
        final s = sepRow[c].trim();
        if (s.startsWith(':') && s.endsWith(':')) {
          aligns[c] = 'center';
        } else if (s.endsWith(':')) {
          aligns[c] = 'right';
        }
      }
    }
    return AwTableData(rows: cleanRows, alignments: aligns);
  }

  String toJsonString() => jsonEncode({
        'rows': rows,
        'alignments': alignments,
      });

  String toMarkdown() {
    if (rows.isEmpty) return '';
    final cols = colCount;
    final buf = StringBuffer();

    String joinCells(List<String> r) {
      final padded = List<String>.generate(
        cols,
        (i) => (i < r.length ? r[i] : '').replaceAll('\n', ' ').trim(),
      );
      return '| ${padded.join(' | ')} |';
    }

    buf.writeln(joinCells(rows.first));
    final sepCells = List<String>.generate(cols, (c) {
      final a = c < alignments.length ? alignments[c] : 'left';
      if (a == 'center') return ':---:';
      if (a == 'right') return '---:';
      return '---';
    });
    buf.writeln('| ${sepCells.join(' | ')} |');

    for (var r = 1; r < rows.length; r++) {
      buf.writeln(joinCells(rows[r]));
    }
    return buf.toString().trimRight();
  }
}

class AwFormulaRow {
  const AwFormulaRow({
    required this.label,
    required this.expression,
  });

  final String label;
  final String expression;

  Map<String, dynamic> toJson() => {
        'label': label,
        'expression': expression,
      };

  factory AwFormulaRow.fromJson(Map<String, dynamic> json) => AwFormulaRow(
        label: (json['label'] ?? '').toString(),
        expression: (json['expression'] ?? '').toString(),
      );
}

class AwFormulaData {
  AwFormulaData({
    this.presetKey,
    this.title,
    required this.rows,
  });

  /// Falls unveränderter Standardblock: z.B. 'FORMEL_BLOCK_PFOSTEN_1'
  final String? presetKey;
  final String? title;
  final List<AwFormulaRow> rows;

  factory AwFormulaData.presetPfosten1() => AwFormulaData(
        presetKey: 'FORMEL_BLOCK_PFOSTEN_1',
        title: 'Querschnittswerte & Plastisches Grenzmoment (RR 50×30×2,9)',
        rows: const [
          AwFormulaRow(
            label: 'Flächenträgheitsmoment',
            expression: 'I = 9,32 cm⁴ (Tab. B.2)',
          ),
          AwFormulaRow(
            label: 'Elastisches Widerstands-\nmoment',
            expression: 'W_el = 4,66 cm³ (Tab. B.2)',
          ),
          AwFormulaRow(
            label: 'Plastisches Widerstands-\nmoment',
            expression: 'W_pl = 5,72 cm³ (Tab. B.2)',
          ),
          AwFormulaRow(
            label: 'Plastisches Grenzmoment',
            expression:
                'M_pl,Rd = (W_pl · f_y,k) / (γ_M0) = 5.720 · 235 Nmm ≈ 1,34 kNm',
          ),
        ],
      );

  factory AwFormulaData.presetPfosten2() => AwFormulaData(
        presetKey: 'FORMEL_BLOCK_PFOSTEN_2',
        title: 'Schnittgrößen & Auslastung bei Holmlast q_k = 1,0 kN/m',
        rows: const [
          AwFormulaRow(
            label: 'Einwirkende Last',
            expression: 'F_Ed = γ_Q · q_k · e = 1,5 · 1,0 · 1,10 = 1,65 kN',
          ),
          AwFormulaRow(
            label: 'Biegemoment',
            expression: 'M_Ed = F_Ed · h = 1,65 · 0,99 = 1,63 kNm',
          ),
          AwFormulaRow(
            label: 'Auslastung',
            expression:
                'η = (M_Ed) / (M_pl,Rd) = (1,63) / (1,34) = 1,22  (122 %)',
          ),
        ],
      );

  factory AwFormulaData.presetBetonausbruch() => AwFormulaData(
        presetKey: 'FORMEL_BLOCK_BETONAUSBRUCH',
        title: 'Geometrischer Betonausbruchnachweis nach DIN EN 1992-4',
        rows: const [
          AwFormulaRow(
            label: 'Projizierte Fläche Anker-\ngruppe',
            expression: 'A_c,N = (s_cr,N + s) · (c_1 + c_2)',
          ),
          AwFormulaRow(
            label: '',
            expression: 'A_c,N = (195 + 120) · (80 + 80) = 50.400 mm²',
          ),
          AwFormulaRow(
            label: 'Fläche Einzelanker ohne\nEinfluss',
            expression: 'A⁰_c,N = s²_cr,N = 195² = 38.025 mm²',
          ),
          AwFormulaRow(
            label: 'Flächenverhältnis Zweier-\ngruppe',
            expression:
                '(A_c,N) / (2 · A⁰_c,N) = (50.400) / (76.050) ≈ 0,66',
          ),
          AwFormulaRow(
            label: 'Randeinfluss',
            expression:
                'ψ_s,N = 0,7 + 0,3 · (c) / (c_cr,N) = 0,7 + 0,3 · (80) / (97,5) ≈ 0,95',
          ),
        ],
      );

  factory AwFormulaData.fromMarkerOrJson(String raw) {
    final t = raw.trim();
    if (t == '[[FORMEL_BLOCK_PFOSTEN_1]]' || t == 'FORMEL_BLOCK_PFOSTEN_1') {
      return AwFormulaData.presetPfosten1();
    }
    if (t == '[[FORMEL_BLOCK_PFOSTEN_2]]' || t == 'FORMEL_BLOCK_PFOSTEN_2') {
      return AwFormulaData.presetPfosten2();
    }
    if (t == '[[FORMEL_BLOCK_BETONAUSBRUCH]]' ||
        t == 'FORMEL_BLOCK_BETONAUSBRUCH') {
      return AwFormulaData.presetBetonausbruch();
    }
    var jsonCandidate = t;
    if (t.startsWith('[[FORMEL_BLOCK_JSON:') && t.endsWith(']]')) {
      jsonCandidate = t.substring('[[FORMEL_BLOCK_JSON:'.length, t.length - 2).trim();
    }
    try {
      final decoded = jsonDecode(jsonCandidate);
      if (decoded is Map<String, dynamic>) {
        final preset = decoded['presetKey'] as String?;
        final rowsList = (decoded['rows'] as List?)
                ?.whereType<Map>()
                .map((m) => AwFormulaRow.fromJson(Map<String, dynamic>.from(m)))
                .toList() ??
            const [];
        if (rowsList.isNotEmpty) {
          return AwFormulaData(
            presetKey: preset,
            title: decoded['title'] as String?,
            rows: rowsList,
          );
        }
        if (preset == 'FORMEL_BLOCK_PFOSTEN_1') {
          return AwFormulaData.presetPfosten1();
        }
        if (preset == 'FORMEL_BLOCK_PFOSTEN_2') {
          return AwFormulaData.presetPfosten2();
        }
        if (preset == 'FORMEL_BLOCK_BETONAUSBRUCH') {
          return AwFormulaData.presetBetonausbruch();
        }
      }
    } catch (_) {}

    // Fallback: Einzeilige oder mehrzeilige Formel in AwFormulaRow(s) wandeln
    final lines = t
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      return AwFormulaData(
        rows: const [
          AwFormulaRow(
            label: 'Berechnung',
            expression: 'M_Ed = F_Ed · h = 1,65 · 0,99 = 1,63 kNm',
          ),
        ],
      );
    }
    return AwFormulaData(
      rows: lines.map((l) {
        final colonIdx = l.indexOf(':');
        if (colonIdx > 0 && colonIdx < 34 && !l.substring(0, colonIdx).contains('=')) {
          return AwFormulaRow(
            label: l.substring(0, colonIdx).trim(),
            expression: l.substring(colonIdx + 1).trim(),
          );
        }
        return AwFormulaRow(label: '', expression: l);
      }).toList(),
    );
  }

  String toJsonString() => jsonEncode({
        if (presetKey != null) 'presetKey': presetKey,
        if (title != null && title!.isNotEmpty) 'title': title,
        'rows': rows.map((r) => r.toJson()).toList(),
      });

  /// Serialisiert für den Plain-Text / PDF-Parser.
  String toMarkerString() {
    if (presetKey == 'FORMEL_BLOCK_PFOSTEN_1') {
      return '[[FORMEL_BLOCK_PFOSTEN_1]]';
    }
    if (presetKey == 'FORMEL_BLOCK_PFOSTEN_2') {
      return '[[FORMEL_BLOCK_PFOSTEN_2]]';
    }
    if (presetKey == 'FORMEL_BLOCK_BETONAUSBRUCH') {
      return '[[FORMEL_BLOCK_BETONAUSBRUCH]]';
    }
    final payload = jsonEncode({
      if (title != null && title!.isNotEmpty) 'title': title,
      'rows': rows.map((r) => r.toJson()).toList(),
    });
    return '[[FORMEL_BLOCK_JSON:$payload]]';
  }
}

// ---------------------------------------------------------------------------
// 2. MATHEMATISCHER FORMEL-RENDERER FÜR FLUTTER (Echte Brüche & Indizes)
// ---------------------------------------------------------------------------

final _kUnitFractionExceptions = <String>{
  'kn/m',
  'n/mm²',
  'n/mm2',
  'mn/m²',
  'kg/m²',
  'kn/cm²',
  'w/(m²k)',
  'w/m²k',
  'm/s',
  'mm/m',
};

/// Rendert einen mathematischen Ausdruck wie
/// `M_pl,Rd = (W_pl · f_y,k) / (γ_M0) = 5.720 · 235 Nmm ≈ 1,34 kNm`
/// als echte visuelle Gleichung mit vertikal gestapelten Brüchen und
/// tiefgestellten Indizes.
class AwMathExpressionWidget extends StatelessWidget {
  const AwMathExpressionWidget({
    super.key,
    required this.expression,
    this.fontSize = 13.5,
    this.color = const Color(0xFF111827),
  });

  final String expression;
  final double fontSize;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final segments = _parseFractions(expression);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 2,
      runSpacing: 4,
      children: [
        for (final seg in segments)
          if (seg.isFraction)
            _buildFraction(seg.numerator!, seg.denominator!)
          else
            _buildMathText(seg.text!),
      ],
    );
  }

  Widget _buildFraction(String numStr, String denStr) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 2, left: 3, right: 3),
              child: _buildMathText(numStr, scale: 0.94),
            ),
            Container(
              height: 1.15,
              color: color,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 3, right: 3),
              child: _buildMathText(denStr, scale: 0.94),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMathText(String chunk, {double scale = 1.0}) {
    if (chunk.isEmpty) return const SizedBox.shrink();
    final effectiveSize = fontSize * scale;
    final spans = _buildSubscriptSpans(chunk, effectiveSize);
    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontSize: effectiveSize,
          color: color,
          height: 1.25,
        ),
        children: spans,
      ),
    );
  }

  List<InlineSpan> _buildSubscriptSpans(String input, double size) {
    final regex = RegExp(
      r'([A-Za-zθψγΗησλμρτφω])(?:\^0|⁰|²|\^2)?_([A-Za-z0-9,+-]+)',
    );
    final matches = regex.allMatches(input).toList();
    if (matches.isEmpty) {
      return [TextSpan(text: input)];
    }

    final out = <InlineSpan>[];
    var curr = 0;
    for (final m in matches) {
      if (m.start > curr) {
        out.add(TextSpan(text: input.substring(curr, m.start)));
      }
      final fullMatch = m.group(0)!;
      final underIdx = fullMatch.indexOf('_');
      final basePart = fullMatch.substring(0, underIdx);
      final subPart = fullMatch.substring(underIdx + 1);
      final isGreek = RegExp(r'^[θψγΗησλμρτφω]').hasMatch(basePart);

      out.add(
        TextSpan(
          text: basePart,
          style: TextStyle(
            fontStyle: isGreek ? FontStyle.normal : FontStyle.italic,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
      out.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.bottom,
          child: Transform.translate(
            offset: const Offset(0, 2.0),
            child: Text(
              subPart,
              style: TextStyle(
                fontSize: size * 0.72,
                color: color,
                fontStyle: FontStyle.normal,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      );
      curr = m.end;
    }
    if (curr < input.length) {
      out.add(TextSpan(text: input.substring(curr)));
    }
    return out;
  }

  List<_MathSegment> _parseFractions(String expr) {
    final out = <_MathSegment>[];
    // 1. Klammer-Brüche: (Zähler) / (Nenner)
    final parenFracRegex = RegExp(
      r'\(([^()]+)\)\s*\/\s*\(([^()]+)\)',
    );
    var curr = 0;
    for (final m in parenFracRegex.allMatches(expr)) {
      final before = expr.substring(0, m.end).trim().toLowerCase();
      if (before.endsWith('w/(m²k)')) continue;
      if (m.start > curr) {
        out.addAll(_parseInlineSimpleFractions(expr.substring(curr, m.start)));
      }
      out.add(_MathSegment.fraction(m.group(1)!.trim(), m.group(2)!.trim()));
      curr = m.end;
    }
    if (curr < expr.length) {
      out.addAll(_parseInlineSimpleFractions(expr.substring(curr)));
    }
    return out;
  }

  List<_MathSegment> _parseInlineSimpleFractions(String text) {
    // Erkennt auch einfache Brüche mit Leerzeichen drumherum: "M_Ed / W_el" oder "150 kNcm / 4,85 cm³"
    final simpleFrac = RegExp(
      r'([A-Za-z0-9θψγ⁰²,_.,]+)\s+\/\s+([A-Za-z0-9θψγ⁰²,_.,]+)',
    );
    final matches = simpleFrac.allMatches(text).toList();
    if (matches.isEmpty) {
      return [_MathSegment.text(text)];
    }
    final out = <_MathSegment>[];
    var curr = 0;
    for (final m in matches) {
      final candidate = m.group(0)!.replaceAll(' ', '').toLowerCase();
      if (_kUnitFractionExceptions.contains(candidate)) continue;
      if (m.start > curr) {
        out.add(_MathSegment.text(text.substring(curr, m.start)));
      }
      out.add(_MathSegment.fraction(m.group(1)!.trim(), m.group(2)!.trim()));
      curr = m.end;
    }
    if (curr < text.length) {
      out.add(_MathSegment.text(text.substring(curr)));
    }
    return out;
  }
}

class _MathSegment {
  const _MathSegment._({
    this.text,
    this.numerator,
    this.denominator,
    required this.isFraction,
  });

  factory _MathSegment.text(String t) =>
      _MathSegment._(text: t, isFraction: false);

  factory _MathSegment.fraction(String num, String den) => _MathSegment._(
        numerator: num,
        denominator: den,
        isFraction: true,
      );

  final String? text;
  final String? numerator;
  final String? denominator;
  final bool isFraction;
}

// ---------------------------------------------------------------------------
// 3. QUILL EMBED BUILDERS: TABELLE, FORMELBLOCK, SEITENUMBRUCH
// ---------------------------------------------------------------------------

class AwTableEmbedBuilder extends quill.EmbedBuilder {
  const AwTableEmbedBuilder();

  @override
  String get key => 'aw_table';

  @override
  bool get expanded => true;

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final raw = embedContext.node.value.data as String;
    final data = AwTableData.fromJsonString(raw);
    final isReadOnly = embedContext.readOnly;

    Future<void> editTable() async {
      final updated = await showTabellenEditorDialog(context, initial: data);
      if (updated == null) return;
      final offset = embedContext.node.documentOffset;
      embedContext.controller.replaceText(
        offset,
        1,
        quill.BlockEmbed.custom(
          quill.CustomBlockEmbed('aw_table', updated.toJsonString()),
        ),
        null,
      );
    }

    void deleteTable() {
      final offset = embedContext.node.documentOffset;
      embedContext.controller.replaceText(offset, 1, '', null);
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFCBD5E1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Dezente Kopfzeile des WYSIWYG-Blocks
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              borderRadius: BorderRadius.vertical(top: Radius.circular(5)),
              border: Border(
                bottom: BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.table_chart_outlined,
                  size: 14,
                  color: Color(0xFF1E3552),
                ),
                const SizedBox(width: 6),
                Text(
                  'Tabelle (${data.rowCount} Zeilen × ${data.colCount} Spalten)',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E3552),
                  ),
                ),
                const Spacer(),
                if (!isReadOnly) ...[
                  InkWell(
                    onTap: editTable,
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit_outlined,
                              size: 13, color: Color(0xFF1A56DB)),
                          SizedBox(width: 4),
                          Text(
                            'Tabelle bearbeiten',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1A56DB),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: deleteTable,
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(
                        Icons.delete_outline,
                        size: 14,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Echte Tabellen-Darstellung wie im Gutachten-PDF
          InkWell(
            onTap: isReadOnly ? null : editTable,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: _buildVisualTable(data),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisualTable(AwTableData data) {
    if (data.rows.isEmpty || data.colCount == 0) {
      return const Text('Leere Tabelle');
    }
    final numCols = data.colCount;
    final tableRows = <TableRow>[];

    for (var r = 0; r < data.rows.length; r++) {
      final rowCells = data.rows[r];
      final isHeader = r == 0;
      final rowHasTotal = rowCells.any(
        (c) =>
            c.contains('Zwischensumme') ||
            c.contains('Gesamtsumme') ||
            c.contains('Nettosumme') ||
            c.contains('Bruttosumme'),
      );
      final bgColor = isHeader
          ? const Color(0xFFEDF0F4)
          : (rowHasTotal
              ? const Color(0xFFF4F6F9)
              : (r.isEven ? const Color(0xFFFAFBFD) : Colors.white));

      tableRows.add(
        TableRow(
          decoration: BoxDecoration(color: bgColor),
          children: List<Widget>.generate(numCols, (c) {
            final rawCell = c < rowCells.length ? rowCells[c].trim() : '';
            final alignStr =
                c < data.alignments.length ? data.alignments[c] : 'left';
            final textAlign = alignStr == 'right'
                ? TextAlign.right
                : (alignStr == 'center' ? TextAlign.center : TextAlign.left);
            final isBold = isHeader ||
                rowHasTotal ||
                (rawCell.startsWith('**') && rawCell.endsWith('**'));
            final cleanText = rawCell.replaceAll('**', '');

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(
                cleanText,
                textAlign: textAlign,
                style: TextStyle(
                  fontSize: isHeader ? 12.0 : 11.5,
                  fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
                  color: isHeader
                      ? const Color(0xFF1E3552)
                      : const Color(0xFF111827),
                  height: 1.3,
                ),
              ),
            );
          }),
        ),
      );
    }

    return Table(
      border: const TableBorder(
        top: BorderSide(color: Color(0xFF334155), width: 1.2),
        bottom: BorderSide(color: Color(0xFF334155), width: 1.2),
        left: BorderSide(color: Color(0xFFCBD5E1), width: 0.7),
        right: BorderSide(color: Color(0xFFCBD5E1), width: 0.7),
        horizontalInside: BorderSide(color: Color(0xFFCBD5E1), width: 0.7),
        verticalInside: BorderSide(color: Color(0xFFCBD5E1), width: 0.7),
      ),
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: tableRows,
    );
  }
}

class AwFormulaEmbedBuilder extends quill.EmbedBuilder {
  const AwFormulaEmbedBuilder();

  @override
  String get key => 'aw_formula';

  @override
  bool get expanded => true;

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final raw = embedContext.node.value.data as String;
    final data = AwFormulaData.fromMarkerOrJson(raw);
    final isReadOnly = embedContext.readOnly;

    Future<void> editFormula() async {
      final updated = await showFormelBlockEditorDialog(context, initial: data);
      if (updated == null) return;
      final offset = embedContext.node.documentOffset;
      embedContext.controller.replaceText(
        offset,
        1,
        quill.BlockEmbed.custom(
          quill.CustomBlockEmbed('aw_formula', updated.toJsonString()),
        ),
        null,
      );
    }

    void deleteFormula() {
      final offset = embedContext.node.documentOffset;
      embedContext.controller.replaceText(offset, 1, '', null);
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: const BoxDecoration(
              color: Color(0xFFEDF2F7),
              borderRadius: BorderRadius.vertical(top: Radius.circular(5)),
              border: Border(
                bottom: BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.functions,
                  size: 15,
                  color: Color(0xFF1E3552),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    data.title != null && data.title!.isNotEmpty
                        ? 'Mathematischer Nachweis: ${data.title}'
                        : 'Mathematischer Formel- & Nachweisblock',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E3552),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!isReadOnly) ...[
                  InkWell(
                    onTap: editFormula,
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit_outlined,
                              size: 13, color: Color(0xFF1A56DB)),
                          SizedBox(width: 4),
                          Text(
                            'Formel bearbeiten',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1A56DB),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: deleteFormula,
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(
                        Icons.delete_outline,
                        size: 14,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          InkWell(
            onTap: isReadOnly ? null : editFormula,
            child: Container(
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: Color(0xFF1E3552), width: 3.5),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final row in data.rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (data.rows.any((r) => r.label.trim().isNotEmpty))
                            SizedBox(
                              width: 175,
                              child: Text(
                                row.label,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF4A5E78),
                                  height: 1.25,
                                ),
                              ),
                            ),
                          Expanded(
                            child: AwMathExpressionWidget(
                              expression: row.expression,
                              fontSize: 13.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AwPageBreakEmbedBuilder extends quill.EmbedBuilder {
  const AwPageBreakEmbedBuilder();

  @override
  String get key => 'aw_pagebreak';

  @override
  bool get expanded => true;

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final isReadOnly = embedContext.readOnly;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: const Color(0xFFCBD5E1),
          style: BorderStyle.solid,
        ),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Divider(color: Color(0xFF94A3B8), thickness: 1),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.content_cut, size: 13, color: Color(0xFF475569)),
                SizedBox(width: 6),
                Text(
                  'Seitenumbruch im PDF',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF475569),
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          const Expanded(
            child: Divider(color: Color(0xFF94A3B8), thickness: 1),
          ),
          if (!isReadOnly)
            InkWell(
              onTap: () {
                final offset = embedContext.node.documentOffset;
                embedContext.controller.replaceText(offset, 1, '', null);
              },
              child: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Tooltip(
                  message: 'Seitenumbruch entfernen',
                  child: Icon(Icons.close, size: 14, color: Color(0xFF64748B)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4. PARSER & SERIALIZER: PLAIN-TEXT / MARKDOWN ↔ QUILL DOCUMENT (WYSIWYG)
// ---------------------------------------------------------------------------

/// Prüft, ob ein Text Tabellen, Formelblöcke, Seitenumbrüche oder Formatierungen
/// enthält, die im WYSIWYG-Modus dargestellt werden.
bool hasStructuredGutachtenContent(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return false;
  if (t.contains('[[NEWPAGE]]') ||
      t.contains('[[FORMEL_BLOCK') ||
      t.contains('**') ||
      RegExp(r'^\|.+\|$', multiLine: true).hasMatch(t)) {
    return true;
  }
  return false;
}

/// Wandelt sowohl Plain-Text (mit Markdown-Tabellen `| ... |`, `[[NEWPAGE]]`,
/// `[[FORMEL_BLOCK_...]]`, Überschriften und `**fett**`) als auch bestehende
/// Quill-Delta-JSON-Strings in ein reichhaltiges [quill.Document] mit visuellen
/// WYSIWYG-Embeds um.
quill.Document parseGutachtenSectionToQuillDocument(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return quill.Document();

  // Falls bereits Quill-Delta-JSON vorliegt: prüfen, ob darin noch rohe
  // Tabellen/Marker stecken oder ob Bild-Embeds enthalten sind.
  if (t.startsWith('[') || t.startsWith('{')) {
    try {
      final decoded = jsonDecode(t);
      if (decoded is List) {
        final upgradedOps = _upgradeDeltaOpsWithEmbeds(decoded);
        return quill.Document.fromJson(upgradedOps);
      }
    } catch (_) {}
  }

  final ops = _plainTextLinesToDeltaOps(raw.split('\n'));
  if (ops.isEmpty) return quill.Document();
  return quill.Document.fromJson(ops);
}

List<Map<String, dynamic>> _upgradeDeltaOpsWithEmbeds(List<dynamic> rawOps) {
  // Wenn das Delta keine Bilder oder Custom-Embeds hat, prüfen wir, ob im
  // Text unformatierte Markdown-Tabellen oder [[FORMEL_BLOCK...]] stecken.
  bool hasCustomOrImage = false;
  final textBuf = StringBuffer();
  bool hasInlineFormatting = false;

  for (final op in rawOps) {
    if (op is! Map) continue;
    final ins = op['insert'];
    if (ins is Map) {
      hasCustomOrImage = true;
    } else if (ins is String) {
      textBuf.write(ins);
    }
    if (op['attributes'] != null) {
      hasInlineFormatting = true;
    }
  }

  final fullText = textBuf.toString();
  final containsRawMarkers = fullText.contains('[[NEWPAGE]]') ||
      fullText.contains('[[FORMEL_BLOCK') ||
      RegExp(r'^\|.+\|$', multiLine: true).hasMatch(fullText);

  if (!hasCustomOrImage && !hasInlineFormatting && containsRawMarkers) {
    return _plainTextLinesToDeltaOps(fullText.split('\n'));
  }

  // Falls bereits Formatierungen oder Bilder vorhanden sind, aber trotzdem
  // einzelne Zeilen [[NEWPAGE]], [[FORMEL_BLOCK_...]] oder | ... | enthalten,
  // wandeln wir diese gezielt um.
  if (!containsRawMarkers) {
    return rawOps.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  final out = <Map<String, dynamic>>[];
  for (final op in rawOps) {
    if (op is! Map) continue;
    final ins = op['insert'];
    final attrs = op['attributes'];
    if (ins is String &&
        attrs == null &&
        (ins.contains('[[NEWPAGE]]') ||
            ins.contains('[[FORMEL_BLOCK') ||
            RegExp(r'^\|.+\|$', multiLine: true).hasMatch(ins))) {
      out.addAll(_plainTextLinesToDeltaOps(ins.split('\n')));
    } else {
      out.add(Map<String, dynamic>.from(op));
    }
  }
  if (out.isEmpty ||
      (out.last['insert'] is! String) ||
      !(out.last['insert'] as String).endsWith('\n')) {
    out.add({'insert': '\n'});
  }
  return out;
}

List<Map<String, dynamic>> _plainTextLinesToDeltaOps(List<String> lines) {
  final ops = <Map<String, dynamic>>[];

  void appendInlineText(String line) {
    if (!line.contains('**')) {
      if (line.isNotEmpty) {
        ops.add({'insert': line});
      }
      return;
    }
    final boldRegex = RegExp(r'\*\*(.+?)\*\*');
    var curr = 0;
    for (final m in boldRegex.allMatches(line)) {
      if (m.start > curr) {
        ops.add({'insert': line.substring(curr, m.start)});
      }
      ops.add({
        'insert': m.group(1)!,
        'attributes': {'bold': true},
      });
      curr = m.end;
    }
    if (curr < line.length) {
      ops.add({'insert': line.substring(curr)});
    }
  }

  int? detectHeaderLevel(String trimmedLine) {
    final clean = trimmedLine.replaceAll('**', '').trim();
    if (clean.isEmpty) return null;
    if (RegExp(r'^([AB]\.)\s+.+$').hasMatch(clean) && clean.length < 95) {
      return 2;
    }
    if (RegExp(r'^(IV\.\d+|2\.[12])\s+.+$').hasMatch(clean) &&
        clean.length < 95) {
      return 2;
    }
    if (clean == 'Feststellungen' ||
        clean == 'Bewertung' ||
        clean == 'Technische Bewertung' ||
        clean == 'Maßnahmen' ||
        clean == 'Wirtschaftliche Bewertung' ||
        clean == 'Schlusserklärung (§ 407a ZPO)' ||
        clean.startsWith('Beantwortung der Beweisfrage ')) {
      return 3;
    }
    return null;
  }

  int i = 0;
  while (i < lines.length) {
    final rawLine = lines[i];
    final trimmed = rawLine.trim();

    // 1. Seitenumbruch [[NEWPAGE]]
    if (trimmed == '[[NEWPAGE]]') {
      ops.add({
        'insert': {'custom': jsonEncode({'aw_pagebreak': '1'})},
      });
      ops.add({'insert': '\n'});
      i++;
      continue;
    }

    // 2. Formelblock [[FORMEL_BLOCK_...]]
    if (trimmed == '[[FORMEL_BLOCK_PFOSTEN_1]]' ||
        trimmed == '[[FORMEL_BLOCK_PFOSTEN_2]]' ||
        trimmed == '[[FORMEL_BLOCK_BETONAUSBRUCH]]' ||
        (trimmed.startsWith('[[FORMEL_BLOCK_JSON:') && trimmed.endsWith(']]'))) {
      final formulaData = AwFormulaData.fromMarkerOrJson(trimmed);
      ops.add({
        'insert': {
          'custom': jsonEncode({'aw_formula': formulaData.toJsonString()}),
        },
      });
      ops.add({'insert': '\n'});
      i++;
      continue;
    }

    // 3. Markdown-Tabelle (aufeinanderfolgende Zeilen mit | ... |)
    if (trimmed.startsWith('|') && trimmed.endsWith('|') && trimmed.length > 2) {
      final tableLines = <String>[];
      while (i < lines.length) {
        final tl = lines[i].trim();
        if (tl.startsWith('|') && tl.endsWith('|') && tl.length > 2) {
          tableLines.add(tl);
          i++;
        } else {
          break;
        }
      }
      final tableData = AwTableData.fromMarkdownLines(tableLines);
      ops.add({
        'insert': {
          'custom': jsonEncode({'aw_table': tableData.toJsonString()}),
        },
      });
      ops.add({'insert': '\n'});
      continue;
    }

    // 4. Normale Textzeile (inkl. **fett** und automatischer Überschrift-Optik)
    final headerLvl = detectHeaderLevel(trimmed);
    if (headerLvl != null) {
      final cleanHeader = rawLine.replaceAll('**', '');
      ops.add({'insert': cleanHeader});
      ops.add({
        'insert': '\n',
        'attributes': {'header': headerLvl},
      });
    } else {
      appendInlineText(rawLine);
      ops.add({'insert': '\n'});
    }
    i++;
  }

  if (ops.isEmpty) {
    ops.add({'insert': '\n'});
  }
  return ops;
}

/// Konvertiert ein [quill.Document] zurück in den kanonischen Gutachten-Text
/// (mit Markdown-Tabellen, `[[FORMEL_BLOCK_...]]`, `[[NEWPAGE]]` und `**fett**`).
/// Falls das Dokument eingebettete Bilder (`image`) enthält, liefert
/// [serializeQuillDocumentForStorage] stattdessen das Delta-JSON, damit keine
/// Bilder verloren gehen.
String quillDocumentToGutachtenPlainText(quill.Document doc) {
  final deltaJson = doc.toDelta().toJson();
  final buf = StringBuffer();

  for (final op in deltaJson) {
    final ins = op['insert'];
    final attrs = op['attributes'] as Map<String, dynamic>?;

    if (ins is Map) {
      Map<String, dynamic>? customMap;
      if (ins['custom'] is String) {
        try {
          customMap =
              jsonDecode(ins['custom'] as String) as Map<String, dynamic>?;
        } catch (_) {}
      } else if (ins['aw_table'] != null ||
          ins['aw_formula'] != null ||
          ins['aw_pagebreak'] != null) {
        customMap = Map<String, dynamic>.from(ins);
      }

      if (customMap != null) {
        if (customMap.containsKey('aw_pagebreak')) {
          if (buf.isNotEmpty && !buf.toString().endsWith('\n')) {
            buf.write('\n');
          }
          buf.write('[[NEWPAGE]]\n');
          continue;
        }
        if (customMap.containsKey('aw_formula')) {
          if (buf.isNotEmpty && !buf.toString().endsWith('\n')) {
            buf.write('\n');
          }
          final fData = AwFormulaData.fromMarkerOrJson(
            customMap['aw_formula'].toString(),
          );
          buf.write('${fData.toMarkerString()}\n');
          continue;
        }
        if (customMap.containsKey('aw_table')) {
          if (buf.isNotEmpty && !buf.toString().endsWith('\n')) {
            buf.write('\n');
          }
          final tData = AwTableData.fromJsonString(
            customMap['aw_table'].toString(),
          );
          buf.write('${tData.toMarkdown()}\n');
          continue;
        }
      }
      continue;
    }

    if (ins is String) {
      final isBold = attrs?['bold'] == true;
      if (isBold && ins.trim().isNotEmpty && !ins.contains('\n')) {
        buf.write('**$ins**');
      } else if (isBold && ins.contains('\n')) {
        final parts = ins.split('\n');
        for (var i = 0; i < parts.length; i++) {
          if (parts[i].trim().isNotEmpty) {
            buf.write('**${parts[i]}**');
          } else {
            buf.write(parts[i]);
          }
          if (i < parts.length - 1) buf.write('\n');
        }
      } else {
        buf.write(ins);
      }
    }
  }

  var res = buf.toString();
  // Doppelte Leerzeilen nach Block-Embeds glätten, aber Absätze erhalten
  if (res.endsWith('\n')) {
    res = res.substring(0, res.length - 1);
  }
  return res;
}

/// Wenn das Dokument echte Bild-Embeds (`image`) enthält, speichern wir das
/// Quill-Delta-JSON; andernfalls speichern wir den sauberen kanonischen
/// Gutachten-Text (sodass der PDF-Generator, der Verzeichnisse-Generator, der
/// Sprach-Check und die Hauptmaske verlustfrei zusammenarbeiten).
String serializeQuillDocumentForStorage(quill.Document doc) {
  final deltaJson = doc.toDelta().toJson();
  final hasImages = deltaJson.any((op) {
    final ins = op['insert'];
    return ins is Map && ins['image'] != null;
  });
  if (hasImages) {
    return jsonEncode(deltaJson);
  }
  return quillDocumentToGutachtenPlainText(doc);
}

/// Hilfsfunktion zum Einfügen eines CustomBlockEmbeds an der aktuellen Cursor-Position.
void insertAwCustomEmbed(
  quill.QuillController controller,
  String embedKey,
  String payload,
) {
  final sel = controller.selection;
  final docLen = controller.document.length;
  final offset = (sel.isValid && sel.start >= 0 && sel.start < docLen)
      ? sel.start
      : (docLen > 0 ? docLen - 1 : 0);

  controller.replaceText(
    offset,
    0,
    quill.BlockEmbed.custom(quill.CustomBlockEmbed(embedKey, payload)),
    TextSelection.collapsed(offset: offset + 1),
  );
  controller.replaceText(
    offset + 1,
    0,
    '\n',
    TextSelection.collapsed(offset: offset + 2),
  );
}

// ---------------------------------------------------------------------------
// 5. INTERAKTIVER TABELLEN-EDITOR-DIALOG
// ---------------------------------------------------------------------------

Future<AwTableData?> showTabellenEditorDialog(
  BuildContext context, {
  AwTableData? initial,
}) {
  return showDialog<AwTableData>(
    context: context,
    useRootNavigator: true,
    builder: (_) => _TabellenEditorDialog(initial: initial),
  );
}

class _TabellenEditorDialog extends StatefulWidget {
  const _TabellenEditorDialog({this.initial});
  final AwTableData? initial;

  @override
  State<_TabellenEditorDialog> createState() => _TabellenEditorDialogState();
}

class _TabellenEditorDialogState extends State<_TabellenEditorDialog> {
  late List<List<TextEditingController>> _ctrls;
  late List<String> _alignments;

  @override
  void initState() {
    super.initState();
    final init = widget.initial ??
        AwTableData(
          rows: [
            ['Prüfkriterium / Bauteil', 'Soll-Wert (Regelwerk)', 'Ist-Wert (Ortstermin)', 'Bewertung'],
            ['', '', '', ''],
            ['', '', '', ''],
          ],
          alignments: ['left', 'left', 'left', 'left'],
        );
    _initFromData(init);
  }

  void _initFromData(AwTableData data) {
    _alignments = List<String>.from(data.alignments);
    _ctrls = data.rows
        .map(
          (row) => row
              .map((cell) => TextEditingController(text: cell))
              .toList(),
        )
        .toList();
  }

  void _disposeControllers() {
    for (final r in _ctrls) {
      for (final c in r) {
        c.dispose();
      }
    }
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  int get _colCount => _ctrls.isEmpty ? 0 : _ctrls.first.length;
  int get _rowCount => _ctrls.length;

  void _applyPreset(AwTableData preset) {
    setState(() {
      _disposeControllers();
      _initFromData(preset);
    });
  }

  void _addRow({List<String>? values}) {
    setState(() {
      final cols = _colCount;
      _ctrls.add(
        List<TextEditingController>.generate(
          cols,
          (i) => TextEditingController(
            text: values != null && i < values.length ? values[i] : '',
          ),
        ),
      );
    });
  }

  void _removeRow(int rowIdx) {
    if (_rowCount <= 2 || rowIdx == 0) return;
    setState(() {
      final removed = _ctrls.removeAt(rowIdx);
      for (final c in removed) {
        c.dispose();
      }
    });
  }

  void _addColumn() {
    if (_colCount >= 8) return;
    setState(() {
      for (var r = 0; r < _ctrls.length; r++) {
        _ctrls[r].add(
          TextEditingController(
            text: r == 0 ? 'Spalte ${_colCount + 1}' : '',
          ),
        );
      }
      _alignments.add('left');
    });
  }

  void _removeColumn(int colIdx) {
    if (_colCount <= 2) return;
    setState(() {
      for (final row in _ctrls) {
        final ctrl = row.removeAt(colIdx);
        ctrl.dispose();
      }
      if (colIdx < _alignments.length) {
        _alignments.removeAt(colIdx);
      }
    });
  }

  void _cycleAlignment(int colIdx) {
    setState(() {
      final curr = _alignments[colIdx];
      _alignments[colIdx] = curr == 'left'
          ? 'center'
          : (curr == 'center' ? 'right' : 'left');
    });
  }

  AwTableData _buildResult() {
    return AwTableData(
      rows: _ctrls
          .map((row) => row.map((c) => c.text.trim()).toList())
          .toList(),
      alignments: List<String>.from(_alignments),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1020, maxHeight: 780),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                color: Color(0xFF1E3552),
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.table_chart, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Visueller Tabellen-Editor (WYSIWYG)',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Vorlagen-Leiste & Aktionen
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: const Color(0xFFF8FAFC),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'Vorlagen:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF475569),
                    ),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.fact_check_outlined, size: 15),
                    label: const Text('Soll-/Ist-Befundtabelle',
                        style: TextStyle(fontSize: 12)),
                    onPressed: () => _applyPreset(
                      AwTableData(
                        rows: [
                          ['Bauteil / Merkmal', 'Soll-Anforderung (Norm)', 'Ist-Befund (Ortstermin)', 'Bewertung'],
                          ['Geländerhöhe', 'mind. 1.000 mm', '969 mm', 'unzulässig (−31 mm)'],
                          ['Befestigung', 'ETA-Zulassung', 'Randabstand unterschritten', 'Mangel'],
                        ],
                        alignments: ['left', 'left', 'left', 'left'],
                      ),
                    ),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.euro, size: 15),
                    label: const Text('Kostentabelle (Pos. / Menge / EP / GP)',
                        style: TextStyle(fontSize: 12)),
                    onPressed: () => _applyPreset(
                      AwTableData(
                        rows: [
                          ['Pos.', 'Leistungsbeschreibung', 'Menge', 'Einheit', 'EP (€)', 'GP (€)'],
                          ['1', 'Demontage und Entsorgung Bestandskonstruktion', '1,00', 'psch.', '850,00', '850,00'],
                          ['2', 'Neuherstellung und Montage nach Regelwerk', '10,00', 'm', '420,00', '4.200,00'],
                          ['', '**Zwischensumme (netto)**', '', '', '', '**5.050,00**'],
                        ],
                        alignments: ['center', 'left', 'right', 'center', 'right', 'right'],
                      ),
                    ),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.compare_arrows, size: 15),
                    label: const Text('Variantenvergleich',
                        style: TextStyle(fontSize: 12)),
                    onPressed: () => _applyPreset(
                      AwTableData(
                        rows: [
                          ['Kriterium', 'Variante A (Ertüchtigung)', 'Variante B (Neuherstellung)'],
                          ['Technische Machbarkeit', 'eingeschränkt', 'uneingeschränkt regelkonform'],
                          ['Korrosionsschutz', 'Nacharbeit vor Ort', 'Werkseitige Feuerverzinkung'],
                          ['Kosten (netto)', 'ca. 8.500,00 €', 'ca. 9.200,00 €'],
                        ],
                        alignments: ['left', 'left', 'left'],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () => _addRow(),
                    icon: const Icon(Icons.add, size: 15),
                    label: const Text('+ Zeile'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      final cols = _colCount;
                      final row = List<String>.filled(cols, '');
                      if (cols >= 2) {
                        row[1] = '**Gesamtsumme (netto)**';
                        row[cols - 1] = '**0,00 €**';
                      } else {
                        row[0] = '**Gesamtsumme**';
                      }
                      _addRow(values: row);
                    },
                    icon: const Icon(Icons.functions, size: 15),
                    label: const Text('+ Summenzeile'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _addColumn,
                    icon: const Icon(Icons.view_column_outlined, size: 15),
                    label: const Text('+ Spalte'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Tabellen-Raster
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Spalten-Steuerung (Ausrichtung & Löschen)
                    Row(
                      children: [
                        const SizedBox(width: 34),
                        for (var c = 0; c < _colCount; c++)
                          Expanded(
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  InkWell(
                                    onTap: () => _cycleAlignment(c),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _alignments[c] == 'right'
                                              ? Icons.format_align_right
                                              : (_alignments[c] == 'center'
                                                  ? Icons.format_align_center
                                                  : Icons.format_align_left),
                                          size: 14,
                                          color: const Color(0xFF475569),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _alignments[c] == 'right'
                                              ? 'Rechts'
                                              : (_alignments[c] == 'center'
                                                  ? 'Mitte'
                                                  : 'Links'),
                                          style: const TextStyle(
                                            fontSize: 10.5,
                                            color: Color(0xFF475569),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (_colCount > 2)
                                    InkWell(
                                      onTap: () => _removeColumn(c),
                                      child: const Tooltip(
                                        message: 'Spalte löschen',
                                        child: Icon(
                                          Icons.close,
                                          size: 13,
                                          color: Color(0xFF94A3B8),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(width: 34),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Zeilen
                    for (var r = 0; r < _rowCount; r++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 34,
                              height: 38,
                              child: Center(
                                child: Text(
                                  r == 0 ? 'Kopf' : '$r.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: r == 0
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: r == 0
                                        ? const Color(0xFF1E3552)
                                        : const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            ),
                            for (var c = 0; c < _colCount; c++)
                              Expanded(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 2),
                                  child: TextField(
                                    controller: _ctrls[r][c],
                                    minLines: 1,
                                    maxLines: 3,
                                    textAlign: _alignments[c] == 'right'
                                        ? TextAlign.right
                                        : (_alignments[c] == 'center'
                                            ? TextAlign.center
                                            : TextAlign.left),
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: r == 0
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                      color: r == 0
                                          ? const Color(0xFF1E3552)
                                          : Colors.black87,
                                    ),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      filled: true,
                                      fillColor: r == 0
                                          ? const Color(0xFFEDF0F4)
                                          : (r.isEven
                                              ? const Color(0xFFFAFBFD)
                                              : Colors.white),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 9,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(4),
                                        borderSide: const BorderSide(
                                          color: Color(0xFFCBD5E1),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            SizedBox(
                              width: 34,
                              height: 38,
                              child: r == 0 || _rowCount <= 2
                                  ? null
                                  : IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        size: 16,
                                        color: Color(0xFF94A3B8),
                                      ),
                                      tooltip: 'Zeile entfernen',
                                      onPressed: () => _removeRow(r),
                                    ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 15, color: Color(0xFF64748B)),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Tipp: Die Kopfzeile wird im PDF automatisch dunkelblau hinterlegt. Zeilen mit „Zwischensumme" oder „Gesamtsumme" werden automatisch hervorgehoben.',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Tabelle übernehmen'),
                    onPressed: () => Navigator.pop(context, _buildResult()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 6. INTERAKTIVER FORMELBLOCK- & NACHWEIS-EDITOR-DIALOG (WYSIWYG)
// ---------------------------------------------------------------------------

Future<AwFormulaData?> showFormelBlockEditorDialog(
  BuildContext context, {
  AwFormulaData? initial,
}) {
  return showDialog<AwFormulaData>(
    context: context,
    useRootNavigator: true,
    builder: (_) => _FormelBlockEditorDialog(initial: initial),
  );
}

class _FormelBlockEditorDialog extends StatefulWidget {
  const _FormelBlockEditorDialog({this.initial});
  final AwFormulaData? initial;

  @override
  State<_FormelBlockEditorDialog> createState() =>
      _FormelBlockEditorDialogState();
}

class _FormelBlockEditorDialogState extends State<_FormelBlockEditorDialog> {
  late TextEditingController _titleCtrl;
  late List<(TextEditingController, TextEditingController)> _rowCtrls;
  TextEditingController? _activeExprCtrl;

  @override
  void initState() {
    super.initState();
    final init = widget.initial ?? AwFormulaData.presetPfosten2();
    _titleCtrl = TextEditingController(text: init.title ?? '');
    _initRows(init.rows);
  }

  void _initRows(List<AwFormulaRow> rows) {
    _rowCtrls = rows.map((r) {
      final lCtrl = TextEditingController(text: r.label);
      final eCtrl = TextEditingController(text: r.expression);
      eCtrl.addListener(() {
        if (mounted) setState(() {});
      });
      lCtrl.addListener(() {
        if (mounted) setState(() {});
      });
      return (lCtrl, eCtrl);
    }).toList();
    if (_rowCtrls.isNotEmpty) {
      _activeExprCtrl = _rowCtrls.first.$2;
    }
  }

  void _disposeRows() {
    for (final pair in _rowCtrls) {
      pair.$1.dispose();
      pair.$2.dispose();
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _disposeRows();
    super.dispose();
  }

  void _applyPreset(AwFormulaData preset) {
    setState(() {
      _titleCtrl.text = preset.title ?? '';
      _disposeRows();
      _initRows(preset.rows);
    });
  }

  void _insertSymbol(String text) {
    final ctrl = _activeExprCtrl ??
        (_rowCtrls.isNotEmpty ? _rowCtrls.last.$2 : null);
    if (ctrl == null) return;
    final sel = ctrl.selection;
    if (sel.isValid && sel.start >= 0) {
      final newText = ctrl.text.replaceRange(sel.start, sel.end, text);
      ctrl.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: sel.start + text.length),
      );
    } else {
      ctrl.text += text;
    }
    setState(() {});
  }

  AwFormulaData _buildCurrentData() {
    final rows = _rowCtrls
        .map(
          (p) => AwFormulaRow(
            label: p.$1.text.trim(),
            expression: p.$2.text.trim(),
          ),
        )
        .where((r) => r.label.isNotEmpty || r.expression.isNotEmpty)
        .toList();

    return AwFormulaData(
      title: _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim(),
      rows: rows.isEmpty
          ? const [AwFormulaRow(label: '', expression: '')]
          : rows,
    );
  }

  @override
  Widget build(BuildContext context) {
    final previewData = _buildCurrentData();
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 820),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                color: Color(0xFF1E3552),
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.functions, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Mathematischer Formel- & Nachweis-Baukasten (WYSIWYG)',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. Live WYSIWYG-Vorschau (exakt wie im PDF!)
                    const Text(
                      'LIVE-VORSCHAU (SO ERSCHEINT DER FORMELBLOCK IM TEXT & PDF):',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: Container(
                        decoration: const BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: Color(0xFF1E3552),
                              width: 4,
                            ),
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final row in previewData.rows)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    if (previewData.rows
                                        .any((r) => r.label.isNotEmpty))
                                      SizedBox(
                                        width: 180,
                                        child: Text(
                                          row.label,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF4A5E78),
                                          ),
                                        ),
                                      ),
                                    Expanded(
                                      child: AwMathExpressionWidget(
                                        expression: row.expression,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 2. Fertige Vorlagen
                    const Text(
                      'FERTIGE NACHWEIS-VORLAGEN (1-KLICK LADEN):',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.architecture, size: 15),
                          label: const Text(
                            'Pfosten: Querschnitt & Grenzmoment M_pl,Rd',
                            style: TextStyle(fontSize: 12),
                          ),
                          onPressed: () =>
                              _applyPreset(AwFormulaData.presetPfosten1()),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.analytics_outlined, size: 15),
                          label: const Text(
                            'Pfosten: Schnittgrößen & Auslastung η',
                            style: TextStyle(fontSize: 12),
                          ),
                          onPressed: () =>
                              _applyPreset(AwFormulaData.presetPfosten2()),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.foundation, size: 15),
                          label: const Text(
                            'Dübel: Betonausbruchnachweis (DIN EN 1992-4)',
                            style: TextStyle(fontSize: 12),
                          ),
                          onPressed: () => _applyPreset(
                            AwFormulaData.presetBetonausbruch(),
                          ),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.thermostat, size: 15),
                          label: const Text(
                            'Bauphysik: Temperaturfaktor f_Rsi (DIN 4108-2)',
                            style: TextStyle(fontSize: 12),
                          ),
                          onPressed: () => _applyPreset(
                            AwFormulaData(
                              title: 'Temperaturfaktor f_Rsi nach DIN 4108-2',
                              rows: const [
                                AwFormulaRow(
                                  label: 'Temperaturfaktor',
                                  expression:
                                      'f_Rsi = (θ_si - θ_e) / (θ_i - θ_e) ≥ 0,70',
                                ),
                                AwFormulaRow(
                                  label: 'Randbedingungen',
                                  expression:
                                      'θ_i = 20,0 °C,  θ_e = -5,0 °C,  R_si = 0,25 (m²·K)/W',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 3. Symbol- & Bruch-Baukasten
                    const Text(
                      'SCHNELL-EINFÜGEN IN AKTIVE FORMELZEILE (BRUCH, INDIZES, SONDERZEICHEN):',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () => _insertSymbol('(Zähler) / (Nenner)'),
                          icon: const Icon(Icons.horizontal_split, size: 14),
                          label: const Text('Bruch (a)/(b)',
                              style: TextStyle(fontSize: 12)),
                        ),
                        _symChip('·', 'Multiplikationspunkt'),
                        _symChip('≈', 'Ungefähr gleich'),
                        _symChip('≤', 'Kleiner gleich'),
                        _symChip('≥', 'Größer gleich'),
                        _symChip('≠', 'Ungleich'),
                        _symChip('±', 'Plus/Minus'),
                        _symChip('√', 'Wurzel'),
                        _symChip('∑', 'Summe'),
                        _symChip('Δ', 'Delta'),
                        _symChip('γ_M0', 'Teilsicherheitsbeiwert Stahl'),
                        _symChip('γ_Q', 'Teilsicherheitsbeiwert Last'),
                        _symChip('η', 'Auslastungsgrad eta'),
                        _symChip('σ_Ed', 'Bemessungsspannung'),
                        _symChip('ψ_s,N', 'Randeinflussfaktor psi'),
                        _symChip('M_Ed', 'Bemessungsmoment'),
                        _symChip('M_pl,Rd', 'Plastisches Grenzmoment'),
                        _symChip('W_pl', 'Plastisches Widerstandsmoment'),
                        _symChip('A_c,N', 'Projizierte Fläche'),
                        _symChip('A⁰_c,N', 'Einzelanker-Fläche'),
                        _symChip('cm⁴', 'cm hoch 4'),
                        _symChip('cm³', 'cm hoch 3'),
                        _symChip('mm²', 'mm hoch 2'),
                        _symChip('kN/m', 'kN pro m'),
                        _symChip('kNm', 'kNm'),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 4. Zeilen-Editor
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'FORMELZEILEN BEARBEITEN (LINKS BEZEICHNUNG, RECHTS FORMEL):',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: Color(0xFF475569),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              final l = TextEditingController();
                              final e = TextEditingController();
                              e.addListener(() {
                                if (mounted) setState(() {});
                              });
                              l.addListener(() {
                                if (mounted) setState(() {});
                              });
                              _rowCtrls.add((l, e));
                              _activeExprCtrl = e;
                            });
                          },
                          icon: const Icon(Icons.add, size: 15),
                          label: const Text('+ Formelzeile hinzufügen'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    for (var i = 0; i < _rowCtrls.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: _rowCtrls[i].$1,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  labelText: 'Bezeichnung (links, optional)',
                                  hintText: 'z. B. Plastisches Grenzmoment',
                                  border: OutlineInputBorder(),
                                ),
                                style: const TextStyle(fontSize: 12.5),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 4,
                              child: Focus(
                                onFocusChange: (hasFocus) {
                                  if (hasFocus) {
                                    _activeExprCtrl = _rowCtrls[i].$2;
                                  }
                                },
                                child: TextField(
                                  controller: _rowCtrls[i].$2,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    labelText:
                                        'Gleichung (Brüche mit (Zähler)/(Nenner), Indizes mit _ )',
                                    hintText:
                                        'z. B. M_pl,Rd = (W_pl · f_y,k) / (γ_M0) ≈ 1,34 kNm',
                                    border: OutlineInputBorder(),
                                  ),
                                  style: const TextStyle(
                                    fontFamily: 'Courier',
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                            if (_rowCtrls.length > 1)
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 18, color: Color(0xFF64748B)),
                                tooltip: 'Formelzeile entfernen',
                                onPressed: () {
                                  setState(() {
                                    final removed = _rowCtrls.removeAt(i);
                                    removed.$1.dispose();
                                    removed.$2.dispose();
                                  });
                                },
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 15, color: Color(0xFF64748B)),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Tipp: Schreibe `(Zähler) / (Nenner)` für einen echten Bruchstrich und `M_Ed` für tiefgestellte Indizes.',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Formelblock übernehmen'),
                    onPressed: () => Navigator.pop(context, _buildCurrentData()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _symChip(String sym, String tooltip) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => _insertSymbol(sym),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          child: AwMathExpressionWidget(
            expression: sym,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 7. INLINE-WYSIWYG-EDITOR FÜR DIE HAUPTMASKE (gutachten_screen.dart)
// ---------------------------------------------------------------------------

/// Eingebetteter WYSIWYG-Editor für einen Gutachten-Abschnitt in der Hauptmaske.
/// Synchronisiert bidirektional mit dem übergebenen [TextEditingController],
/// zeigt Tabellen, Formeln und Seitenumbrüche direkt visuell an und erlaubt
/// direktes Tippen sowie das Einfügen von Tabellen, Formeln und Seitenumbrüchen.
class GutachtenInlineWysiwygField extends StatefulWidget {
  const GutachtenInlineWysiwygField({
    super.key,
    required this.controller,
    required this.embedBuilders,
    required this.minLines,
    required this.placeholder,
    required this.onChanged,
    required this.onOpenFullscreen,
  });

  final TextEditingController controller;
  final List<quill.EmbedBuilder> embedBuilders;
  final int minLines;
  final String placeholder;
  final ValueChanged<String> onChanged;
  final VoidCallback onOpenFullscreen;

  @override
  State<GutachtenInlineWysiwygField> createState() =>
      _GutachtenInlineWysiwygFieldState();
}

class _GutachtenInlineWysiwygFieldState
    extends State<GutachtenInlineWysiwygField> {
  late quill.QuillController _quillCtrl;
  late ScrollController _scrollCtrl;
  late FocusNode _focusNode;
  bool _updatingFromQuill = false;
  bool _showRawText = false;
  String _lastSyncedText = '';

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController();
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (mounted) setState(() {});
    });
    _lastSyncedText = widget.controller.text;
    _quillCtrl = _createQuillController(_lastSyncedText);
    widget.controller.addListener(_onExternalControllerChanged);
  }

  quill.QuillController _createQuillController(String raw) {
    final doc = parseGutachtenSectionToQuillDocument(raw);
    final ctrl = quill.QuillController(
      document: doc,
      selection: const TextSelection.collapsed(offset: 0),
    );
    ctrl.document.changes.listen((_) {
      if (_updatingFromQuill) return;
      _updatingFromQuill = true;
      try {
        final serialized = serializeQuillDocumentForStorage(ctrl.document);
        _lastSyncedText = serialized;
        if (widget.controller.text != serialized) {
          widget.controller.text = serialized;
        }
        widget.onChanged(serialized);
      } finally {
        _updatingFromQuill = false;
      }
    });
    return ctrl;
  }

  void _onExternalControllerChanged() {
    if (_updatingFromQuill) return;
    final newText = widget.controller.text;
    if (newText == _lastSyncedText) return;
    _lastSyncedText = newText;
    final oldCtrl = _quillCtrl;
    _quillCtrl = _createQuillController(newText);
    oldCtrl.dispose();
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant GutachtenInlineWysiwygField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onExternalControllerChanged);
      widget.controller.addListener(_onExternalControllerChanged);
      _onExternalControllerChanged();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onExternalControllerChanged);
    _quillCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _insertTable() async {
    final table = await showTabellenEditorDialog(context);
    if (!mounted || table == null) return;
    insertAwCustomEmbed(_quillCtrl, 'aw_table', table.toJsonString());
    setState(() {});
  }

  Future<void> _insertFormula() async {
    final formula = await showFormelBlockEditorDialog(context);
    if (!mounted || formula == null) return;
    insertAwCustomEmbed(_quillCtrl, 'aw_formula', formula.toJsonString());
    setState(() {});
  }

  void _insertPageBreak() {
    insertAwCustomEmbed(_quillCtrl, 'aw_pagebreak', '1');
    setState(() {});
  }

  void _toggleBold() {
    final style = _quillCtrl.getSelectionStyle();
    final isBold = style.attributes.containsKey(quill.Attribute.bold.key);
    _quillCtrl.formatSelection(
      isBold ? quill.Attribute.clone(quill.Attribute.bold, null) : quill.Attribute.bold,
    );
  }

  void _toggleItalic() {
    final style = _quillCtrl.getSelectionStyle();
    final isItalic = style.attributes.containsKey(quill.Attribute.italic.key);
    _quillCtrl.formatSelection(
      isItalic
          ? quill.Attribute.clone(quill.Attribute.italic, null)
          : quill.Attribute.italic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final minHeight = (widget.minLines * 22.0).clamp(90.0, 260.0);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AwTokens.radiusSm),
        border: Border.all(
          color: _focusNode.hasFocus ? AwTokens.amber : AwTokens.line,
          width: _focusNode.hasFocus ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Kompakte WYSIWYG-Formatierungs- & Einfügeleiste
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(AwTokens.radiusSm - 1),
              ),
              border: Border(
                bottom: BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _miniBtn(
                        icon: Icons.format_bold,
                        tooltip: 'Fett (Strg+B)',
                        onTap: _toggleBold,
                      ),
                      _miniBtn(
                        icon: Icons.format_italic,
                        tooltip: 'Kursiv (Strg+I)',
                        onTap: _toggleItalic,
                      ),
                      Container(
                        width: 1,
                        height: 16,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        color: const Color(0xFFCBD5E1),
                      ),
                      _miniLabelBtn(
                        icon: Icons.table_chart_outlined,
                        label: '+ Tabelle',
                        tooltip: 'Tabelle visuell einfügen & bearbeiten',
                        onTap: _insertTable,
                      ),
                      _miniLabelBtn(
                        icon: Icons.functions,
                        label: '+ Formel / Nachweis',
                        tooltip: 'Mathematischen Formelblock visuell einfügen',
                        onTap: _insertFormula,
                      ),
                      _miniLabelBtn(
                        icon: Icons.content_cut,
                        label: '+ Seitenumbruch',
                        tooltip: 'Expliziten Seitenumbruch fürs PDF einfügen',
                        onTap: _insertPageBreak,
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () => setState(() => _showRawText = !_showRawText),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(
                      _showRawText ? 'WYSIWYG-Ansicht' : 'Text-Ansicht',
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                ),
                InkWell(
                  onTap: widget.onOpenFullscreen,
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.open_in_full,
                            size: 12, color: Color(0xFF1E3552)),
                        SizedBox(width: 4),
                        Text(
                          'Vollbild-Editor',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E3552),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Inhalt: Entweder WYSIWYG-Quill-Editor oder (optional) Raw-TextFormField
          if (_showRawText)
            Padding(
              padding: const EdgeInsets.all(8),
              child: TextFormField(
                controller: widget.controller,
                minLines: widget.minLines,
                maxLines: widget.minLines + 8,
                decoration: InputDecoration(
                  hintText: widget.placeholder,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                onChanged: widget.onChanged,
              ),
            )
          else
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                if (!_focusNode.hasFocus) {
                  _focusNode.requestFocus();
                }
              },
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: minHeight,
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: quill.QuillEditor(
                    controller: _quillCtrl,
                    focusNode: _focusNode,
                    scrollController: _scrollCtrl,
                    config: quill.QuillEditorConfig(
                      scrollable: false,
                      expands: false,
                      placeholder: widget.placeholder,
                      padding: EdgeInsets.zero,
                      embedBuilders: widget.embedBuilders,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _miniBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 15, color: const Color(0xFF334155)),
        ),
      ),
    );
  }

  Widget _miniLabelBtn({
    required IconData icon,
    required String label,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: const Color(0xFF1E3552)),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E3552),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
