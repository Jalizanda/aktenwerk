import 'package:flutter/material.dart';

import '../../core/theme/aw_tokens.dart';

/// Page-Header nach AW-Guideline (handoff/README §5 „Page-Header").
///
/// Struktur:
///   eyebrow (optional, uppercase 11px mute, Icon davor 14px)
///   H1 (24px 600, -0.025em)
///   subtitle (13px mute)
///   rechts: Suche + Actions
///   (optional Filter-Chips darunter)
class ModuleHeader extends StatefulWidget {
  const ModuleHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.eyebrow,
    this.actions = const <Widget>[],
    this.filters = const <Widget>[],
    this.searchHint,
    this.onSearchChanged,
    this.searchInitial,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// Optionale Eyebrow-Zeile über dem Titel. Wenn `null`, wird das
  /// Icon allein als dezente Marker-Zeile gerendert.
  final String? eyebrow;

  final List<Widget> actions;
  final List<Widget> filters;

  final String? searchHint;
  final ValueChanged<String>? onSearchChanged;
  final String? searchInitial;

  @override
  State<ModuleHeader> createState() => _ModuleHeaderState();
}

class _ModuleHeaderState extends State<ModuleHeader> {
  late final TextEditingController _searchCtrl =
      TextEditingController(text: widget.searchInitial ?? '');

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 720;
    final pad = EdgeInsets.fromLTRB(
        isMobile ? 16 : 28, isMobile ? 14 : 22, isMobile ? 16 : 28, 12);

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.eyebrow != null) ...[
          Text(
            widget.eyebrow!.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 11 * 0.05,
              color: AwTokens.mute,
              height: 1,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(widget.icon,
                size: (isMobile ? 18 : AwTokens.textH1 * 0.92),
                color: AwTokens.orange),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                widget.title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: isMobile ? 19 : AwTokens.textH1,
                  fontWeight: FontWeight.w600,
                  letterSpacing:
                      (isMobile ? 19 : AwTokens.textH1) * -0.025,
                  color: AwTokens.ink,
                  height: 1.1,
                ),
              ),
            ),
          ],
        ),
        if (widget.subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            widget.subtitle!,
            style: const TextStyle(
              fontSize: AwTokens.textMd,
              color: AwTokens.mute,
              height: 1.35,
            ),
          ),
        ],
      ],
    );

    final searchField = widget.searchHint == null
        ? null
        : TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 18),
              hintText: widget.searchHint,
              suffixIcon: _searchCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        _searchCtrl.clear();
                        widget.onSearchChanged?.call('');
                        setState(() {});
                      },
                    ),
            ),
            onChanged: (v) {
              widget.onSearchChanged?.call(v);
              setState(() {});
            },
          );

    if (isMobile) {
      // Mobile: Titel oben, dann Such-Feld in voller Breite, dann Actions
      // als horizontal scrollbare Reihe — kein Overflow auf 360-px-Phones.
      return Padding(
        padding: pad,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            titleBlock,
            if (searchField != null) ...[
              const SizedBox(height: 12),
              searchField,
            ],
            if (widget.actions.isNotEmpty) ...[
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final a in widget.actions) ...[
                      a,
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            ],
            if (widget.filters.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: widget.filters,
              ),
            ],
          ],
        ),
      );
    }

    return Padding(
      padding: pad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(child: titleBlock),
              if (searchField != null) ...[
                const SizedBox(width: 24),
                SizedBox(width: 320, child: searchField),
              ],
              const Spacer(),
              for (final a in widget.actions) ...[
                const SizedBox(width: 8),
                a
              ],
            ],
          ),
          if (widget.filters.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: widget.filters,
            ),
          ],
        ],
      ),
    );
  }
}

/// Card um eine DataTable (konsistenter Look für alle Listen).
class DataTableCard extends StatelessWidget {
  const DataTableCard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AwTokens.radiusLg),
            side: const BorderSide(color: AwTokens.line),
          ),
          child: child,
        ),
      ),
    );
  }
}
