import 'package:flutter/material.dart';

import '../../core/theme/aw_tokens.dart';

/// Überschriftenblock innerhalb eines Formulars (AW-h3: 14 px 600
/// `-0.01em` Ink).
class FormSection extends StatelessWidget {
  const FormSection(this.title, {super.key, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: AwTokens.textLg,
                fontWeight: FontWeight.w600,
                letterSpacing: AwTokens.textLg * -0.01,
                color: AwTokens.ink,
              ),
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      );
}

/// Label oberhalb eines Feldes (handoff/DIALOGS §4 Felder):
/// 11 px 500 Mute, 4 px margin-bottom.
class LabeledField extends StatelessWidget {
  const LabeledField(this.label, this.child, {super.key, this.required = false});
  final String label;
  final Widget child;
  final bool required;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text.rich(
              TextSpan(
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AwTokens.mute,
                  height: 1,
                ),
                children: [
                  TextSpan(text: label),
                  if (required)
                    const TextSpan(
                      text: ' *',
                      style: TextStyle(
                        color: AwTokens.orange,
                        fontSize: 9,
                      ),
                    ),
                ],
              ),
            ),
          ),
          child,
        ],
      );
}

/// Zwei-Spalten-Row mit Standardabstand und optionalem Flex.
/// Auf schmalen Viewports (< 600 px) klappt sie automatisch in eine
/// Column um — sonst werden die Felder unlesbar schmal.
class Row2 extends StatelessWidget {
  const Row2({super.key, required this.left, required this.right, this.flex});
  final Widget left;
  final Widget right;
  final (int, int)? flex;
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 600) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          left,
          const SizedBox(height: 12),
          right,
        ],
      );
    }
    final (l, r) = flex ?? (1, 1);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: l, child: left),
        const SizedBox(width: 12),
        Expanded(flex: r, child: right),
      ],
    );
  }
}

/// Drei-Spalten-Row. Auf schmalen Viewports gestapelt.
class Row3 extends StatelessWidget {
  const Row3({super.key, required this.a, required this.b, required this.c});
  final Widget a;
  final Widget b;
  final Widget c;
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 600) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          a,
          const SizedBox(height: 12),
          b,
          const SizedBox(height: 12),
          c,
        ],
      );
    }
    if (w < 900) {
      // 2+1: erste zwei Felder nebeneinander, drittes darunter.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: a),
              const SizedBox(width: 12),
              Expanded(child: b),
            ],
          ),
          const SizedBox(height: 12),
          c,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: a),
        const SizedBox(width: 12),
        Expanded(child: b),
        const SizedBox(width: 12),
        Expanded(child: c),
      ],
    );
  }
}

/// Dialog-Header nach AW-Guideline (handoff/DIALOGS §3).
/// 52 px Höhe, `14px 20px` Padding, Status-Dot oder Icon links (klein),
/// optionale Eyebrow über dem Titel, Titel 15 px 600 `-0.015em`.
class DialogHeader extends StatelessWidget {
  const DialogHeader({
    super.key,
    required this.title,
    required this.onClose,
    this.trailing,
    this.icon,
    this.eyebrow,
    this.statusDot,
  });
  final String title;
  final VoidCallback? onClose;
  final Widget? trailing;
  final IconData? icon;

  /// Optionale Eyebrow-Zeile über dem Titel (z. B. „AUFTRAG AW-0046").
  final String? eyebrow;

  /// Wenn gesetzt, wird ein 8-px-Punkt in dieser Farbe links vom Titel
  /// gezeigt. Überschreibt das optionale [icon] in der gleichen Position.
  final Color? statusDot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AwTokens.line)),
      ),
      child: Row(
        children: [
          if (statusDot != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: statusDot,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 10),
          ] else if (icon != null) ...[
            Icon(icon, size: 16, color: AwTokens.mute),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      eyebrow!.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 10 * 0.05,
                        color: AwTokens.mute,
                        height: 1,
                      ),
                    ),
                  ),
                Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 15 * -0.015,
                    color: AwTokens.ink,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          ?trailing,
          IconButton(
            onPressed: onClose,
            iconSize: 16,
            icon: const Icon(Icons.close),
            color: AwTokens.mute,
            tooltip: 'Schließen',
          ),
        ],
      ),
    );
  }
}

/// Einheitliches Dialog-Footer mit Abbrechen/Speichern.
class DialogFooter extends StatelessWidget {
  const DialogFooter({
    super.key,
    required this.onCancel,
    required this.onSave,
    this.saving = false,
    this.saveLabel = 'Speichern',
    this.extraLeading,
  });
  final VoidCallback? onCancel;
  final VoidCallback? onSave;
  final bool saving;
  final String saveLabel;
  final Widget? extraLeading;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: const BoxDecoration(
          color: AwTokens.paper,
          border: Border(top: BorderSide(color: AwTokens.line)),
        ),
        child: Row(
          children: [
            ?extraLeading,
            const Spacer(),
            TextButton(
              onPressed: saving ? null : onCancel,
              child: const Text('Abbrechen'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: saving ? null : onSave,
              icon: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_outlined),
              label: Text(saveLabel),
            ),
          ],
        ),
      );
}

/// AW-Dialog-Grundgrößen (handoff/DIALOGS §1). Verwende bevorzugt
/// [AwDialogSize.lg] für Editor-Dialoge.
enum AwDialogSize {
  sm,  // 420 — Bestätigungen, 1–3 Felder
  md,  // 640 — Standard-Formulare
  lg,  // 880 — Editor-Dialoge
  xl,  // 1120 — Mehrspaltige Editoren
}

extension AwDialogSizeWidth on AwDialogSize {
  double get width => switch (this) {
        AwDialogSize.sm => AwTokens.dialogSm,
        AwDialogSize.md => AwTokens.dialogMd,
        AwDialogSize.lg => AwTokens.dialogLg,
        AwDialogSize.xl => AwTokens.dialogXl,
      };
}

/// Standardhalter um Dialoge (Header + Divider + Inhalt + Divider + Footer).
///
/// Verwende entweder [size] (empfohlen, AW-konform) oder [maxWidth]
/// (Legacy, bleibt kompatibel).
class StandardFormDialog extends StatelessWidget {
  const StandardFormDialog({
    super.key,
    required this.title,
    required this.body,
    required this.onCancel,
    this.onSave,
    this.saving = false,
    this.size,
    this.maxWidth = 760,
    this.maxHeight = 760,
    this.footerLeading,
    this.onDelete,
    this.deleteConfirmText,
    this.icon,
  });

  /// Bevorzugte AW-Größenstufe. Wenn gesetzt, überschreibt [maxWidth].
  final AwDialogSize? size;

  final String title;
  final Widget body;
  final IconData? icon;
  final VoidCallback onCancel;
  final VoidCallback? onSave;
  final bool saving;
  final double maxWidth;
  final double maxHeight;

  /// Zusätzliche Aktionen links im Footer (z.B. „Drucken" / „In Auftrag umwandeln").
  final Widget? footerLeading;

  /// Löschen-Callback (Papierkorb unten links). Wenn gesetzt, zeigt der Dialog
  /// einen Löschen-Button mit Bestätigungs-Dialog. Nach dem Löschen wird der
  /// Form-Dialog automatisch geschlossen (der Callback muss das nicht selbst tun).
  final Future<void> Function()? onDelete;

  /// Text der Löschen-Bestätigung (Standard: „Eintrag wirklich löschen?").
  final String? deleteConfirmText;

  Widget _buildLeading(BuildContext context) {
    final trash = onDelete == null
        ? null
        : IconButton(
            tooltip: 'Löschen',
            icon: const Icon(Icons.delete_outline),
            color: Theme.of(context).colorScheme.error,
            onPressed: saving
                ? null
                : () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      useRootNavigator: true,
                      builder: (_) => AlertDialog(
                        title: const Text('Löschen?'),
                        content: Text(deleteConfirmText ??
                            'Eintrag wirklich löschen?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context,
                                    rootNavigator: true)
                                .pop(false),
                            child: const Text('Abbrechen'),
                          ),
                          FilledButton.tonal(
                            style: FilledButton.styleFrom(
                                foregroundColor: Theme.of(context)
                                    .colorScheme
                                    .error),
                            onPressed: () => Navigator.of(context,
                                    rootNavigator: true)
                                .pop(true),
                            child: const Text('Löschen'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await onDelete!();
                      if (context.mounted) {
                        Navigator.of(context, rootNavigator: true).pop(true);
                      }
                    }
                  },
          );
    if (trash == null && footerLeading == null) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ?trash,
        if (footerLeading != null) ...[
          if (trash != null) const SizedBox(width: 4),
          footerLeading!,
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final isMobile = screen.width < 600;
    return Dialog(
      // Mobile: nimmt fast den ganzen Screen, weniger Inset, kleinere
      // Radius (Sheet-ähnlich); Desktop: zentriertes Card-Modal.
      insetPadding: isMobile
          ? const EdgeInsets.all(0)
          : const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(
            isMobile ? 0 : AwTokens.radiusXl),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isMobile ? screen.width : (size?.width ?? maxWidth),
          maxHeight: isMobile ? screen.height : maxHeight,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(
              isMobile ? 0 : AwTokens.radiusXl),
          child: SafeArea(
            top: isMobile,
            bottom: false,
            child: Column(
              children: [
                DialogHeader(
                    title: title,
                    icon: icon,
                    onClose: saving ? null : onCancel),
                Expanded(
                  child: Container(color: AwTokens.white, child: body),
                ),
                DialogFooter(
                  onCancel: onCancel,
                  onSave: onSave,
                  saving: saving,
                  extraLeading: _buildLeading(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Kompakter "Empty State" für Listen.
class EmptyListState extends StatelessWidget {
  const EmptyListState({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
  });
  final IconData icon;
  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium),
            if (hint != null) ...[
              const SizedBox(height: 8),
              Text(
                hint!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
