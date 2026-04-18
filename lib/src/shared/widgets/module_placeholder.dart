import 'package:flutter/material.dart';

/// Einheitlicher Platzhalter für noch nicht implementierte Module.
/// Wird in Folge-Phasen durch echte Listen/Formulare ersetzt.
class ModulePlaceholder extends StatelessWidget {
  const ModulePlaceholder({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    this.features = const [],
  });

  final String title;
  final IconData icon;
  final String? subtitle;
  final List<String> features;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        Row(
          children: [
            Icon(icon, size: 32, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Text(title, style: theme.textTheme.headlineMedium),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(subtitle!, style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )),
        ],
        const SizedBox(height: 24),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.construction, color: theme.colorScheme.tertiary),
                    const SizedBox(width: 8),
                    Text(
                      'Modul noch in Portierung',
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Datenmodell und Navigation stehen bereits. '
                  'Die UI wird in einer der nächsten Phasen aus der '
                  'SV-Software übernommen.',
                  style: theme.textTheme.bodyMedium,
                ),
                if (features.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text('Geplanter Funktionsumfang:',
                      style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  for (final f in features)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('•  '),
                          Expanded(
                            child: Text(f,
                                style: theme.textTheme.bodyMedium),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
