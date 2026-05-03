import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/aw_tokens.dart';

/// In-App-Vorschau eines PDFs mit Zoom +/− und "Drucken / speichern"-Button.
/// Alternative zum nativen [Printing.layoutPdf] wenn ein integrierter Dialog
/// gewünscht wird.
Future<void> showPdfPreviewDialog(
  BuildContext context, {
  required String title,
  required Future<Uint8List> Function() builder,
  String? dateiname,
  /// Optional: zusätzlicher CSV-Export-Button. Wenn gesetzt, erscheint
  /// rechts neben dem Drucken-Symbol ein „Excel"-Button, der die per
  /// `csvBuilder` gelieferten Bytes als `.csv`-Datei zum Download anbietet.
  Future<Uint8List> Function()? csvBuilder,
  String? csvDateiname,
  /// Optional: Obergrenze für die Dialog-Breite. Ohne Wert spannt sich der
  /// Dialog wie bisher fast über die volle Bildschirmbreite. Praktisch
  /// für Vorschauen, die schmaler dargestellt werden sollen (z. B.
  /// Gutachten — DIN-A4-PDFs sehen schmaler natürlicher aus).
  double? maxWidth,
}) async {
  await showDialog(
    context: context,
    useRootNavigator: true,
    builder: (_) => _PdfPreviewDialog(
      title: title,
      builder: builder,
      dateiname: dateiname,
      csvBuilder: csvBuilder,
      csvDateiname: csvDateiname,
      maxWidth: maxWidth,
    ),
  );
}

class _PdfPreviewDialog extends StatefulWidget {
  const _PdfPreviewDialog({
    required this.title,
    required this.builder,
    this.dateiname,
    this.csvBuilder,
    this.csvDateiname,
    this.maxWidth,
  });
  final String title;
  final Future<Uint8List> Function() builder;
  final String? dateiname;
  final Future<Uint8List> Function()? csvBuilder;
  final String? csvDateiname;
  final double? maxWidth;

  @override
  State<_PdfPreviewDialog> createState() => _PdfPreviewDialogState();
}

class _PdfPreviewDialogState extends State<_PdfPreviewDialog> {
  @override
  Widget build(BuildContext context) {
    final dialog = Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
            child: Row(
              children: [
                const Icon(Icons.picture_as_pdf_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(widget.title,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                IconButton(
                  tooltip: 'Drucken / als PDF speichern',
                  icon: const Icon(Icons.print_outlined),
                  onPressed: () async {
                    await Printing.layoutPdf(
                      onLayout: (_) async => await widget.builder(),
                      name: widget.dateiname ?? 'dokument.pdf',
                    );
                  },
                ),
                if (widget.csvBuilder != null)
                  IconButton(
                    tooltip: 'CSV-Export für Excel',
                    icon: const Icon(Icons.table_chart_outlined),
                    onPressed: () async {
                      final bytes = await widget.csvBuilder!();
                      await Printing.sharePdf(
                        bytes: bytes,
                        filename:
                            widget.csvDateiname ?? 'export.csv',
                      );
                    },
                  ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () =>
                      Navigator.of(context, rootNavigator: true).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Container(
              color: AppTheme.slate100,
              child: PdfPreview(
                build: (_) async => await widget.builder(),
                allowPrinting: false,
                allowSharing: false,
                canChangePageFormat: false,
                canChangeOrientation: false,
                canDebug: false,
                useActions: false,
                maxPageWidth: 800,
                scrollViewDecoration: const BoxDecoration(
                  color: AwTokens.paper,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (widget.maxWidth == null) return dialog;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.maxWidth!),
        child: dialog,
      ),
    );
  }
}
