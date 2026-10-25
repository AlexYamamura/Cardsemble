// 3D wallet card carousel for the Wallet tab.
//
// Renders connected cards as a horizontal [PageView.builder] with a 3D
// carousel effect: the active card is shown at full size with no transform,
// while the previous and next cards recede with scale, rotation, and
// perspective. This replaces the plain `PageView` that scrolled cards
// left/right without depth.
import 'package:flutter/material.dart';

import 'package:cardsemble/features/wallet/domain/wallet_card.dart';
import 'package:cardsemble/features/wallet/presentation/widgets/wallet_card_panel.dart';

/// Viewport fraction — 0.82 shows a peek of the next card while keeping the
/// active card dominant.
const double _kViewportFraction = 0.82;

/// Scale applied to the previous (left) card at maximum offset.
const double _kPrevCardScale = 0.84;

/// Scale applied to the next (right) card at maximum offset.
const double _kNextCardScale = 0.90;

/// Maximum rotation in radians (~0.22 rad ≈ 12.6°).
const double _kMaxRotation = 0.22;

/// Perspective factor for the 3D effect.
const double _kPerspective = 0.0015;

/// Maximum width for an individual card inside the carousel.
const double _kMaxCardWidth = 420;

/// Horizontal padding applied to each carousel page (smaller than the original
/// 16px so the peek of the adjacent card is visible on narrow phones).
const double _kCarouselHorizontalPadding = 8;

/// Vertical padding applied to each carousel page.
const double _kCarouselVerticalPadding = 6;

/// Immutable per-card transform style produced by [carouselCardStyleFor].
class CarouselCardStyle {
  const CarouselCardStyle({
    required this.scale,
    required this.rotation,
    required this.alignment,
  });

  final double scale;
  final double rotation;
  final Alignment alignment;

  bool get isIdentity => scale == 1.0 && rotation == 0.0;
}

/// Computes the 3D transform style for a card at [delta] pages away from the
/// current page.
///
/// `delta` is `index - controller.page`, so:
/// - `delta == 0` → active card (identity, full size)
/// - `delta < 0` → previous card (recedes more, hinges on right edge)
/// - `delta > 0` → next card (peeks from right, hinges on left edge)
///
/// Values are clamped to `[-1, 1]` so a card more than one page away behaves
/// the same as one page away.
CarouselCardStyle carouselCardStyleFor(double delta) {
  final clamped = delta.clamp(-1.0, 1.0);
  final t = clamped.abs();
  final isPrevious = clamped < 0;

  if (t == 0) {
    return const CarouselCardStyle(
      scale: 1.0,
      rotation: 0.0,
      alignment: Alignment.center,
    );
  }

  // Previous cards recede more (smaller scale) than next cards so the
  // "pushed back" effect is more pronounced.
  final targetScale = isPrevious ? _kPrevCardScale : _kNextCardScale;
  final scale = 1.0 - (1.0 - targetScale) * t;

  // Rotation direction: previous cards rotate one way, next cards the other,
  // so their outer edges recede into the distance.
  final direction = isPrevious ? 1.0 : -1.0;
  final rotation = direction * _kMaxRotation * t;

  // Hinge on the inner edge so the card rotates away from the center.
  final alignment = isPrevious
      ? Alignment.centerRight
      : Alignment.centerLeft;

  return CarouselCardStyle(
    scale: scale,
    rotation: rotation,
    alignment: alignment,
  );
}

/// Builds the [Matrix4] transform for a [CarouselCardStyle].
Matrix4 buildCarouselTransform(CarouselCardStyle style) {
  if (style.isIdentity) return Matrix4.identity();

  return Matrix4.identity()
    ..setEntry(3, 2, _kPerspective)
    ..rotateY(style.rotation)
    ..scale(style.scale, style.scale, 1.0);
}

/// 3D carousel widget for the Wallet tab's "Your Cards" section.
///
/// Shows connected cards with a 3D perspective effect: the active card is
/// full-size at the center, while adjacent cards peek from the sides and
/// recede with scale/rotation/perspective as the user scrolls.
class WalletCardCarousel extends StatefulWidget {
  const WalletCardCarousel({
    super.key,
    required this.cards,
    required this.onCardTap,
    required this.onResync,
    required this.carouselHeight,
  });

  final List<WalletCard> cards;
  final ValueChanged<WalletCard> onCardTap;
  final Future<void> Function(WalletCard) onResync;
  final double carouselHeight;

  @override
  State<WalletCardCarousel> createState() => _WalletCardCarouselState();
}

class _WalletCardCarouselState extends State<WalletCardCarousel> {
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: _kViewportFraction);
  }

  @override
  void didUpdateWidget(covariant WalletCardCarousel old) {
    super.didUpdateWidget(old);
    if (widget.cards.length != old.cards.length && _controller.hasClients) {
      final page = _controller.page ?? 0.0;
      final clampedPage = page.clamp(0.0, (widget.cards.length - 1).toDouble());
      if (page != clampedPage) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_controller.hasClients) {
            _controller.jumpToPage(clampedPage.toInt());
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return SizedBox(
      width: double.infinity,
      height: widget.carouselHeight,
      child: PageView.builder(
        controller: _controller,
        itemCount: widget.cards.length,
        itemBuilder: (context, index) {
            final card = widget.cards[index];
            final panel = WalletCardPanel(
              card: card,
              mode: WalletCardPanelMode.collapsed,
              onTap: () => widget.onCardTap(card),
              onResync: card.needsRelink ? () async => widget.onResync(card) : null,
            );

            if (reduceMotion) {
              return Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: _kCarouselHorizontalPadding,
                  vertical: _kCarouselVerticalPadding,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _kMaxCardWidth),
                    child: panel,
                  ),
                ),
              );
            }

            return AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final page = _controller.page ?? 0.0;
                final delta = (index - page).clamp(-1.0, 1.0);
                final style = carouselCardStyleFor(delta);
                final matrix = buildCarouselTransform(style);

                return Transform(
                  alignment: style.alignment,
                  transform: matrix,
                  child: child,
                );
              },
              child: RepaintBoundary(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: _kCarouselHorizontalPadding,
                    vertical: _kCarouselVerticalPadding,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(maxWidth: _kMaxCardWidth),
                      child: panel,
                    ),
                  ),
                ),
              ),
            );
           },
      ),
    );
  }
}
