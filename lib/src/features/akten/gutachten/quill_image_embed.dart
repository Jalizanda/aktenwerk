import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_svg/flutter_svg.dart';

/// Quill-Embed-Builder, der `{insert: {image: 'data:image/...;base64,...'}}`
/// als reales Bild rendert. Ohne diesen Builder zeigt Flutter Quill nur
/// einen leeren Platzhalter (graues Rechteck), weil das image-Embed
/// standardmäßig nicht aufgelöst wird.
class QuillImageEmbedBuilder extends quill.EmbedBuilder {
  const QuillImageEmbedBuilder();

  @override
  String get key => quill.BlockEmbed.imageType;

  @override
  bool get expanded => true;

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final raw = embedContext.node.value.data;
    if (raw is! String) return const SizedBox.shrink();
    final bytes = _decode(raw);
    final mime = _mime(raw);
    if (bytes != null) {
      return _ImageBox(
        bytesBuilder: () => bytes,
        isSvg: mime == 'image/svg+xml' || _looksLikeSvg(bytes),
      );
    }
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return _ImageBox(networkUrl: raw);
    }
    return const SizedBox.shrink();
  }

  Uint8List? _decode(String src) {
    if (!src.startsWith('data:')) return null;
    final comma = src.indexOf(',');
    if (comma < 0) return null;
    try {
      return base64Decode(src.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  String? _mime(String src) {
    if (!src.startsWith('data:')) return null;
    final comma = src.indexOf(',');
    if (comma < 0) return null;
    final header = src.substring(5, comma);
    final semi = header.indexOf(';');
    return semi < 0 ? header : header.substring(0, semi);
  }
}

bool _looksLikeSvg(Uint8List bytes) {
  if (bytes.length < 5) return false;
  final head = String.fromCharCodes(
      bytes.take(200).where((b) => b > 0 && b < 128));
  return head.contains('<svg') || head.trimLeft().startsWith('<?xml');
}

class _ImageBox extends StatelessWidget {
  const _ImageBox({
    this.bytesBuilder,
    this.networkUrl,
    this.isSvg = false,
  });
  final Uint8List Function()? bytesBuilder;
  final String? networkUrl;
  final bool isSvg;

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width * 0.7;
    final Widget image;
    if (bytesBuilder != null) {
      final bytes = bytesBuilder!();
      if (isSvg) {
        image = SvgPicture.memory(
          bytes,
          fit: BoxFit.contain,
          placeholderBuilder: (_) => _errBox('SVG …'),
        );
      } else {
        image = Image.memory(
          bytes,
          fit: BoxFit.contain,
          errorBuilder: _errBuilder,
        );
      }
    } else {
      image = Image.network(
        networkUrl!,
        fit: BoxFit.contain,
        errorBuilder: _errBuilder,
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: 420),
        child: image,
      ),
    );
  }

  Widget _errBuilder(BuildContext _, Object _, StackTrace? _) =>
      _errBox('(Bild nicht ladbar)');

  Widget _errBox(String text) => Container(
        height: 80,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text,
            style: const TextStyle(fontStyle: FontStyle.italic)),
      );
}

const List<quill.EmbedBuilder> kAktenwerkEmbedBuilders = [
  QuillImageEmbedBuilder(),
];
