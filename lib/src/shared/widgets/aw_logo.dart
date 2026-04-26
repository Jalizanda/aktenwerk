import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/theme/aw_tokens.dart';

/// Welche Logo-Variante gerendert werden soll.
enum AwLogoVariant {
  /// Nur das Symbol (dunkler Container mit orangefarbenem Layer).
  mark,

  /// Symbol + Wortmarke „Akten**werk**" + Subline „SACHVERSTÄNDIGEN-SUITE".
  lockup,

  /// Einfarbige Variante (Fax, Stempel, Mono-Print).
  mono,

  /// Variante für sehr helle Flächen mit sichtbarem Rahmen.
  light,
}

/// Aktenwerk-Logo nach Design-Guideline v1.0 (`handoff/`).
///
/// Die Lockup-Variante wird als Flutter-Komposition gerendert
/// (Mark-SVG + Text-Widgets für Wortmarke & Subline), damit die Geist-
/// Schriftart aus `web/index.html` sauber übernommen wird — `flutter_svg`
/// rendert `<text>`-Elemente nicht zuverlässig.
class AwLogo extends StatelessWidget {
  const AwLogo({
    super.key,
    this.size = 32,
    this.variant = AwLogoVariant.mark,
    this.wortmarkeScale = 0.44,
  });

  /// Höhe des Mark-Symbols (bei `lockup` gleich Höhe des gesamten Blocks).
  final double size;
  final AwLogoVariant variant;

  /// Skalierungsfaktor der Wortmarke „Akten**werk**" relativ zu [size].
  /// Default 0.44 aus der Lockup-SVG (28 / 64). Nur für `lockup`-Variante.
  final double wortmarkeScale;

  String get _markAsset => switch (variant) {
        AwLogoVariant.lockup => 'assets/images/logo/aktenwerk-mark.svg',
        AwLogoVariant.mark => 'assets/images/logo/aktenwerk-mark.svg',
        AwLogoVariant.mono => 'assets/images/logo/aktenwerk-mark-mono.svg',
        AwLogoVariant.light => 'assets/images/logo/aktenwerk-mark-light.svg',
      };

  @override
  Widget build(BuildContext context) {
    final mark = SvgPicture.asset(
      _markAsset,
      height: size,
      fit: BoxFit.contain,
      semanticsLabel: 'Aktenwerk',
    );
    if (variant != AwLogoVariant.lockup) return mark;

    // Proportionen aus handoff/logo/aktenwerk-lockup.svg abgeleitet
    // (Mark 64 px, Wortmarke 28 px, Subline 8 px). Wortmarke per
    // [wortmarkeScale] optional skalierbar.
    final wortSize = size * wortmarkeScale;
    final sublineSize = (size * 0.125).clamp(7.0, 11.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        mark,
        SizedBox(width: size * 0.22),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                style: TextStyle(
                  fontFamily: AwTokens.fontSans,
                  fontSize: wortSize,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -wortSize * 0.025,
                  color: AwTokens.ink,
                  height: 1,
                ),
                children: const [
                  TextSpan(text: 'Akten'),
                  TextSpan(
                    text: 'werk',
                    style: TextStyle(color: AwTokens.orange),
                  ),
                ],
              ),
            ),
            SizedBox(height: size * 0.09),
            Text(
              'SACHVERSTÄNDIGEN-SUITE',
              style: TextStyle(
                fontFamily: AwTokens.fontSans,
                fontSize: sublineSize,
                fontWeight: FontWeight.w500,
                letterSpacing: sublineSize * 0.22,
                color: AwTokens.mute,
                height: 1,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Wortmarke „Akten**werk**" als Text-Widget — orange Hervorhebung auf „werk".
/// Nur dort verwenden, wo die Lockup-Variante nicht passt.
class AwWordmark extends StatelessWidget {
  const AwWordmark({super.key, this.fontSize = 17});
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: TextStyle(
          fontFamily: AwTokens.fontSans,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.025 * fontSize,
          color: AwTokens.ink,
          height: 1,
        ),
        children: const [
          TextSpan(text: 'Akten'),
          TextSpan(
            text: 'werk',
            style: TextStyle(color: AwTokens.orange),
          ),
        ],
      ),
    );
  }
}
