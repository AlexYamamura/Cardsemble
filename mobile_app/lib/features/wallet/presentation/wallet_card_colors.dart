import 'package:flutter/material.dart';

import 'package:cardsemble/features/wallet/domain/wallet_card.dart';
import 'package:cardsemble/theme/app_colors.dart';

/// Derives the accent color used to theme a wallet card panel from the card's
/// issuer (bank) and catalog reference data.
///
/// Known issuers map to their brand color so familiar banks are instantly
/// recognizable. Unknown issuers get a deterministic color derived from the
/// issuer name, so the same card always renders the same color while different
/// cards are visually distinct.
class WalletCardColors {
  const WalletCardColors._();

  static const Color _chase = Color(0xFF005A9C);
  static const Color _amex = Color(0xFF0062A8);
  static const Color _capitalOne = Color(0xFF0054A6);
  static const Color _citi = Color(0xFF0085CA);
  static const Color _bankOfAmerica = Color(0xFF007DC5);
  static const Color _wellsFargo = Color(0xFF7E2F2E);
  static const Color _discover = Color(0xFFFF6F00);
  static const Color _barclays = Color(0xFF005DAA);
  static const Color _synchrony = Color(0xFFC41E3A);
  static const Color _usBank = Color(0xFF545454);
  static const Color _tdBank = Color(0xFF0066CC);

  /// The accent color for [card], drawn from its issuer when known and derived
  /// from the issuer name otherwise.
  static Color accentColor(WalletCard card) {
    final issuer = (card.issuer ?? '').toLowerCase().trim();
    return _known[issuer] ??
        _hashColor(issuer.isEmpty ? card.displayName : issuer);
  }

  static final Map<String, Color> _known = <String, Color>{
    'chase': _chase,
    'jpmorgan chase': _chase,
    'chase bank': _chase,
    'american express': _amex,
    'amex': _amex,
    'capital one': _capitalOne,
    'capitalone': _capitalOne,
    'citibank': _citi,
    'citi': _citi,
    'bank of america': _bankOfAmerica,
    'bofa': _bankOfAmerica,
    'wells fargo': _wellsFargo,
    'discover': _discover,
    'barclays': _barclays,
    'barclaycard': _barclays,
    'synchrony': _synchrony,
    'synchrony bank': _synchrony,
    'u.s. bank': _usBank,
    'us bank': _usBank,
    'td bank': _tdBank,
    'td': _tdBank,
  };

  /// Light tint of [color] for use as the details-pane background over a
  /// white surface.
  static Color paneBackground(Color color) => color.withValues(alpha: 0.10);

  /// Foreground text/icon color (white or black) chosen for contrast against
  /// [color].
  static Color onColor(Color color) => color.computeLuminance() > 0.55 ? Colors.black : Colors.white;

  /// Deterministic, reasonably saturated accent color derived from [name].
  static Color _hashColor(String name) {
    if (name.isEmpty) return AppColors.primary;
    var hash = 0x811C9DC5; // FNV-1a offset basis
    for (var i = 0; i < name.length; i++) {
      hash = ((hash * 0x01000193) ^ name.codeUnitAt(i)) & 0xFFFFFFFF; // FNV prime
    }
    final hue = (hash % 360).toDouble().abs();
    return HSLColor.fromAHSL(1.0, hue, 0.50, 0.55).toColor();
  }
}
