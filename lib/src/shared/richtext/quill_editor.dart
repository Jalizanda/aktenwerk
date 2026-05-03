import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/system/einstellungen/einstellungen_repository.dart';

/// Standard-Mappings für Schriftarten und -größen, die alle RichText-
/// Editoren der App teilen — Konsistenz zwischen Gutachten, Anschreiben,
/// Serienbriefen etc.
const kRichTextFontFamilies = <String, String>{
  'Standard (Inter)': 'Inter',
  'Arial': 'Arial',
  'Times New Roman': 'Times New Roman',
  'Helvetica': 'Helvetica',
  'Courier New': 'Courier New',
  'Georgia': 'Georgia',
  'Verdana': 'Verdana',
  'Zurücksetzen': 'Clear',
};

const kRichTextFontSizes = <String, String>{
  '6 pt': '6',
  '8 pt': '8',
  '10 pt': '10',
  '11 pt': '11',
  '12 pt': '12',
  '14 pt': '14',
  '16 pt': '16',
  '18 pt': '18',
  '20 pt': '20',
  '24 pt': '24',
  'Zurücksetzen': '0',
};

/// Extrahiert den reinen Text aus einem Quill-Delta-JSON-String. Wenn der
/// String kein Delta ist, wird er unverändert zurückgegeben — so kann
/// bestehender Plaintext-Inhalt weiterhin gelesen werden.
String plainTextFromDeltaJson(String? json) {
  final raw = (json ?? '').trim();
  if (raw.isEmpty) return '';
  if (!raw.startsWith('[')) return raw;
  try {
    final decoded = jsonDecode(raw);
    final doc = quill.Document.fromJson(decoded as List);
    return doc.toPlainText().trimRight();
  } catch (_) {
    return raw;
  }
}

/// Kompakter Quill-Editor mit Toolbar und JSON-Delta-Serialisierung.
class RichTextEditor extends ConsumerStatefulWidget {
  const RichTextEditor({
    super.key,
    required this.initialDeltaJson,
    required this.onChanged,
    this.minHeight = 300,
    this.placeholder,
    this.showToolbar = true,
  });

  final String? initialDeltaJson;
  final ValueChanged<String> onChanged;
  final double minHeight;
  final String? placeholder;
  final bool showToolbar;

  @override
  ConsumerState<RichTextEditor> createState() => _RichTextEditorState();
}

class _RichTextEditorState extends ConsumerState<RichTextEditor> {
  late quill.QuillController _controller;
  String _einstStandardFont = 'Standard (Inter)';
  String _einstStandardSize = '11';

  @override
  void initState() {
    super.initState();
    _controller = _build(widget.initialDeltaJson);
    _controller.addListener(_emit);
    _ladeStandardSchrift();
  }

  Future<void> _ladeStandardSchrift() async {
    final repo = ref.read(einstellungenRepositoryProvider);
    final font = await repo.get(SettingsKeys.gutachtenFontFamily);
    final size = await repo.get(SettingsKeys.gutachtenFontSize);
    if (!mounted) return;
    setState(() {
      // Settings-Wert kann „Standard" oder ein konkreter Familienname
      // sein — wir mappen auf die Toolbar-Labels.
      if (font != null && font.isNotEmpty) {
        if (font == 'Standard' || font == 'Inter') {
          _einstStandardFont = 'Standard (Inter)';
        } else {
          _einstStandardFont = font;
        }
      }
      if (size != null && size.isNotEmpty) {
        _einstStandardSize = size;
      }
    });
  }

  quill.QuillController _build(String? json) {
    if (json == null || json.isEmpty) {
      return quill.QuillController.basic();
    }
    final trimmed = json.trim();
    // Quill-Delta ist JSON-Array; alles andere wird als Plaintext interpretiert.
    if (trimmed.startsWith('[')) {
      try {
        final decoded = jsonDecode(trimmed);
        return quill.QuillController(
          document: quill.Document.fromJson(decoded as List),
          selection: const TextSelection.collapsed(offset: 0),
        );
      } catch (_) {}
    }
    // Legacy-Plaintext: als simple Delta mit einem Insert hochziehen.
    try {
      final doc = quill.Document.fromJson([
        {'insert': trimmed.endsWith('\n') ? trimmed : '$trimmed\n'}
      ]);
      return quill.QuillController(
        document: doc,
        selection: const TextSelection.collapsed(offset: 0),
      );
    } catch (_) {
      return quill.QuillController.basic();
    }
  }

  @override
  void didUpdateWidget(covariant RichTextEditor old) {
    super.didUpdateWidget(old);
    if (old.initialDeltaJson != widget.initialDeltaJson) {
      _controller.removeListener(_emit);
      _controller.dispose();
      _controller = _build(widget.initialDeltaJson);
      _controller.addListener(_emit);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_emit);
    _controller.dispose();
    super.dispose();
  }

  void _emit() {
    final json = jsonEncode(_controller.document.toDelta().toJson());
    widget.onChanged(json);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showToolbar)
          quill.QuillSimpleToolbar(
            controller: _controller,
            config: quill.QuillSimpleToolbarConfig(
              buttonOptions: quill.QuillSimpleToolbarButtonOptions(
                fontFamily: quill.QuillToolbarFontFamilyButtonOptions(
                  initialValue: _einstStandardFont,
                  defaultDisplayText: _einstStandardFont,
                  items: kRichTextFontFamilies,
                  renderFontFamilies: true,
                ),
                fontSize: quill.QuillToolbarFontSizeButtonOptions(
                  initialValue: _einstStandardSize,
                  defaultDisplayText: _einstStandardSize,
                  items: kRichTextFontSizes,
                ),
              ),
              multiRowsDisplay: false,
              showAlignmentButtons: true,
              showCodeBlock: false,
              showInlineCode: false,
              showFontFamily: true,
              showFontSize: true,
              showSearchButton: false,
              showBackgroundColorButton: false,
              showListCheck: true,
            ),
          ),
        Container(
          constraints: BoxConstraints(minHeight: widget.minHeight),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border:
                Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(6),
          ),
          child: quill.QuillEditor.basic(
            controller: _controller,
            config: quill.QuillEditorConfig(
              placeholder: widget.placeholder,
            ),
          ),
        ),
      ],
    );
  }
}

/// Nur-Lese Preview des Rich-Texts.
class RichTextPreview extends StatefulWidget {
  const RichTextPreview({super.key, required this.deltaJson, this.maxLines});
  final String? deltaJson;
  final int? maxLines;
  @override
  State<RichTextPreview> createState() => _RichTextPreviewState();
}

class _RichTextPreviewState extends State<RichTextPreview> {
  late quill.QuillController _controller;
  @override
  void initState() {
    super.initState();
    _controller = _build();
  }

  quill.QuillController _build() {
    final raw = (widget.deltaJson ?? '').trim();
    if (raw.isEmpty) return quill.QuillController.basic();
    if (raw.startsWith('[')) {
      try {
        final decoded = jsonDecode(raw);
        return quill.QuillController(
          document: quill.Document.fromJson(decoded as List),
          selection: const TextSelection.collapsed(offset: 0),
        );
      } catch (_) {}
    }
    try {
      final doc = quill.Document.fromJson([
        {'insert': raw.endsWith('\n') ? raw : '$raw\n'}
      ]);
      return quill.QuillController(
        document: doc,
        selection: const TextSelection.collapsed(offset: 0),
      );
    } catch (_) {
      return quill.QuillController.basic();
    }
  }

  @override
  void didUpdateWidget(covariant RichTextPreview old) {
    super.didUpdateWidget(old);
    if (old.deltaJson != widget.deltaJson) {
      _controller.dispose();
      _controller = _build();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      child: quill.QuillEditor.basic(
        controller: _controller,
        config: const quill.QuillEditorConfig(
          showCursor: false,
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
