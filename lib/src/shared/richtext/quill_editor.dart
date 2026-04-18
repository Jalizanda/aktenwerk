import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

/// Kompakter Quill-Editor mit Toolbar und JSON-Delta-Serialisierung.
class RichTextEditor extends StatefulWidget {
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
  State<RichTextEditor> createState() => _RichTextEditorState();
}

class _RichTextEditorState extends State<RichTextEditor> {
  late quill.QuillController _controller;

  @override
  void initState() {
    super.initState();
    _controller = _build(widget.initialDeltaJson);
    _controller.addListener(_emit);
  }

  quill.QuillController _build(String? json) {
    if (json == null || json.isEmpty) {
      return quill.QuillController.basic();
    }
    try {
      final decoded = jsonDecode(json);
      return quill.QuillController(
        document: quill.Document.fromJson(decoded as List),
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
            config: const quill.QuillSimpleToolbarConfig(
              multiRowsDisplay: false,
              showAlignmentButtons: true,
              showCodeBlock: false,
              showInlineCode: false,
              showFontFamily: false,
              showFontSize: false,
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
    if ((widget.deltaJson ?? '').isEmpty) {
      return quill.QuillController.basic();
    }
    try {
      final decoded = jsonDecode(widget.deltaJson!);
      return quill.QuillController(
        document: quill.Document.fromJson(decoded as List),
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
