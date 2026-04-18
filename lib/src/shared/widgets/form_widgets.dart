import 'package:flutter/material.dart';

/// Überschriftenblock innerhalb eines Formulars.
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
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      );
}

/// Label oberhalb eines Feldes.
class LabeledField extends StatelessWidget {
  const LabeledField(this.label, this.child, {super.key});
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          child,
        ],
      );
}

/// Zwei-Spalten-Row mit Standardabstand und optionalem Flex.
class Row2 extends StatelessWidget {
  const Row2({super.key, required this.left, required this.right, this.flex});
  final Widget left;
  final Widget right;
  final (int, int)? flex;
  @override
  Widget build(BuildContext context) {
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

/// Drei-Spalten-Row.
class Row3 extends StatelessWidget {
  const Row3({super.key, required this.a, required this.b, required this.c});
  final Widget a;
  final Widget b;
  final Widget c;
  @override
  Widget build(BuildContext context) => Row(
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

/// Kopfzeile von Dialogen.
class DialogHeader extends StatelessWidget {
  const DialogHeader({
    super.key,
    required this.title,
    required this.onClose,
    this.trailing,
  });
  final String title;
  final VoidCallback? onClose;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ?trailing,
            IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close),
              tooltip: 'Schließen',
            ),
          ],
        ),
      );
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
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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

/// Standardhalter um Dialoge (Header + Divider + Inhalt + Divider + Footer).
class StandardFormDialog extends StatelessWidget {
  const StandardFormDialog({
    super.key,
    required this.title,
    required this.body,
    required this.onCancel,
    required this.onSave,
    this.saving = false,
    this.maxWidth = 760,
    this.maxHeight = 760,
  });

  final String title;
  final Widget body;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final bool saving;
  final double maxWidth;
  final double maxHeight;

  @override
  Widget build(BuildContext context) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
          child: Column(
            children: [
              DialogHeader(title: title, onClose: saving ? null : onCancel),
              const Divider(height: 1),
              Expanded(child: body),
              const Divider(height: 1),
              DialogFooter(
                onCancel: onCancel,
                onSave: onSave,
                saving: saving,
              ),
            ],
          ),
        ),
      );
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
