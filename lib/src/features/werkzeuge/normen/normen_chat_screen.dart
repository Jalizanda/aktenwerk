import 'package:flutter/material.dart';

import 'normen_chat_dialog.dart';

/// Eigener Screen für den Normen-KI-Chat. Wird per Route `/normen/chat`
/// erreicht — typischerweise in einem neuen Browser-Tab, damit der
/// Nutzer parallel im Hauptfenster weiterarbeiten kann.
class NormenChatScreen extends StatelessWidget {
  const NormenChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Der bestehende [NormenChatDialog] liefert das fertige Chat-UI.
    // Wir packen es in ein volles Scaffold statt eines Dialogs, damit
    // es in einem eigenen Fenster/Tab funktioniert.
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints.expand(),
            child: const NormenChatDialog(),
          ),
        ),
      ),
    );
  }
}
