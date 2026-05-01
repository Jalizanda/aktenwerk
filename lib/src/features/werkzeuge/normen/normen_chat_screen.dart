import 'package:flutter/material.dart';

import 'normen_chat_dialog.dart';
import 'normen_rag_chat_dialog.dart';

/// Eigener Screen für den Normen-KI-Chat. Wird per Route `/normen/chat`
/// erreicht — typischerweise in einem neuen Browser-Tab, damit der
/// Nutzer parallel im Hauptfenster weiterarbeiten kann.
///
/// Bietet zwei Reiter:
///  - **RAG-Chat (neu)**: Vector-Search gegen vorab indexierte PDF-Chunks
///    + Quellen-Highlighting (Cloud Function `norm_chat`).
///  - **Klassisch**: bisheriger Chat, der bis zu drei komplette Norm-PDFs
///    in jeden Turn an Gemini schickt — bleibt als Fallback erhalten.
class NormenChatScreen extends StatefulWidget {
  const NormenChatScreen({super.key});

  @override
  State<NormenChatScreen> createState() => _NormenChatScreenState();
}

class _NormenChatScreenState extends State<NormenChatScreen>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Normen-Chat'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.auto_awesome), text: 'RAG (neu)'),
            Tab(icon: Icon(Icons.chat_bubble_outline), text: 'Klassisch'),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabs,
          children: const [
            NormenRagChatDialog(embedded: true),
            NormenChatDialog(embedded: true),
          ],
        ),
      ),
    );
  }
}
