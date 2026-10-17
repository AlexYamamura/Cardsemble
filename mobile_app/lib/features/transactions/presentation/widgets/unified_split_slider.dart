import 'package:flutter/material.dart';
import 'package:cardsemble/features/transactions/domain/split_math.dart';

/// A unified slider for splitting transactions among 2-4 participants.
/// Each participant has a colored segment representing their percentage.
/// Dragging the boundaries between segments adjusts the split while
/// maintaining a total of 100%.
class UnifiedSplitSlider extends StatefulWidget {
  const UnifiedSplitSlider({
    super.key,
    required this.participants,
    required this.percentages,
    required this.onChanged,
  });

  /// Participants in order, each rendered as a colored segment.
  final List<ParticipantInfo> participants;

  /// Current percentage allocation keyed by participant id. Must sum to 100.
  final Map<String, double> percentages;

  /// Called whenever the boundaries are dragged, with the new allocation.
  final ValueChanged<Map<String, double>> onChanged;

  @override
  State<UnifiedSplitSlider> createState() => _UnifiedSplitSliderState();
}

/// A person taking part in a split, with the color used for their segment.
class ParticipantInfo {
  const ParticipantInfo({
    required this.id,
    required this.name,
    required this.color,
  });

  final String id;
  final String name;
  final Color color;
}

class _UnifiedSplitSliderState extends State<UnifiedSplitSlider> {
  late Map<String, double> _percentages;
  late List<String> _orderedParticipantIds;
  Offset? _dragStartPosition;
  double? _dragStartCumulative; // Boundary position (percent) when drag began
  int? _draggingBoundaryIndex; // Boundary between participant i and i+1

  @override
  void initState() {
    super.initState();
    _percentages = Map<String, double>.from(widget.percentages);
    _orderedParticipantIds = widget.participants.map((p) => p.id).toList();
  }

  @override
  void didUpdateWidget(covariant UnifiedSplitSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_participantsEqual(oldWidget.participants, widget.participants) ||
        !_percentagesEqual(oldWidget.percentages, widget.percentages)) {
      _percentages = Map<String, double>.from(widget.percentages);
      _orderedParticipantIds = widget.participants.map((p) => p.id).toList();
    }
  }

  bool _participantsEqual(List<ParticipantInfo> a, List<ParticipantInfo> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].name != b[i].name ||
          a[i].color != b[i].color) {
        return false;
      }
    }
    return true;
  }

  bool _percentagesEqual(Map<String, double> a, Map<String, double> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) return false;
    }
    return true;
  }

  void _handleDragUpdate(Offset position, double trackWidth, double inset) {
    if (_dragStartPosition == null ||
        _draggingBoundaryIndex == null ||
        _dragStartCumulative == null) {
      return;
    }

    final double deltaX = position.dx - _dragStartPosition!.dx;
    final double percentPerPixel = 100.0 / trackWidth;
    final double deltaPercent = deltaX * percentPerPixel;

    // Target is the boundary's position at drag start plus total displacement,
    // which avoids compounding the delta on every update.
    final double newCumulative = _dragStartCumulative! + deltaPercent;
    final double clampedCumulative = newCumulative.clamp(0.0, 100.0);

    // Snap to 25/50/75 guidelines when the boundary is near them.
    final double snappedCumulative = snapToGuideline(
      clampedCumulative,
      guidelines: const [25.0, 50.0, 75.0],
      tolerance: 5.0,
    );

    setState(() {
      _percentages = moveBoundary(
        _percentages,
        _orderedParticipantIds,
        _draggingBoundaryIndex!,
        snappedCumulative,
        minPercent: 0.0, // Allow 0% segments
      );
      widget.onChanged(_percentages);
    });
  }

  void _handleDragEnd() {
    _dragStartPosition = null;
    _dragStartCumulative = null;
    _draggingBoundaryIndex = null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.participants.length < 2 || widget.participants.length > 4) {
      return const Center(
        child: Text('Unified splitter supports 2-4 participants'),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        const double trackHeight = 40.0;
        const double thumbSize = 24.0; // visible circle
        const double thumbHitSize = 32.0; // gesture target
        final double inset = thumbHitSize / 2; // 16.0
        final double trackWidth = width - 2 * inset; // width available for the track

        return GestureDetector(
          onHorizontalDragStart: (details) {
            final double clickPercent =
                (details.localPosition.dx - inset) / trackWidth * 100.0;
            double cumulative = 0.0;

            for (int i = 0; i < _orderedParticipantIds.length - 1; i++) {
              cumulative += _percentages[_orderedParticipantIds[i]]!;
              if ((clickPercent - cumulative).abs() <= 5.0) {
                _draggingBoundaryIndex = i;
                _dragStartPosition = details.localPosition;
                _dragStartCumulative = cumulative;
                break;
              }
            }
          },
          onHorizontalDragUpdate: (details) {
            _handleDragUpdate(details.localPosition, trackWidth, inset);
          },
          onHorizontalDragEnd: (_) => _handleDragEnd(),
          onHorizontalDragCancel: _handleDragEnd,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Background track + colored segments, clipped to an oval so
              // segments never overflow the pill-shaped track corners.
              Align(
                alignment: Alignment.center,
                child: SizedBox(
                  width: width,
                  height: trackHeight,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(trackHeight / 2),
                    child: Container(
                      width: trackWidth,
                      height: trackHeight,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(trackHeight / 2),
                      ),
                      child: Stack(
                        children: [
                          // Colored segments proportional to each participant's share
                          for (int i = 0; i < widget.participants.length; i++)
                            Positioned(
                              left: (_getCumulativePercentage(i) / 100.0) * trackWidth,
                              width:
                                  ((_percentages[widget.participants[i].id] ?? 0.0) /
                                          100.0) *
                                      trackWidth,
                              height: trackHeight,
                              child: Container(
                                color: widget.participants[i].color
                                    .withValues(alpha: 0.3),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Draggable boundary handles rendered outside the clip so the
              // circular thumbs are never clipped at 0%/100%.
              for (int i = 0; i < widget.participants.length - 1; i++)
                Positioned(
                  left: inset +
                      (_getCumulativePercentage(i + 1) / 100.0) * trackWidth -
                      thumbHitSize / 2,
                  width: thumbHitSize,
                  height: trackHeight,
                  child: GestureDetector(
                    key: ValueKey('split-handle-$i'),
                    onHorizontalDragStart: (details) {
                      _draggingBoundaryIndex = i;
                      _dragStartPosition = details.localPosition;
                      _dragStartCumulative = _getCumulativePercentage(i + 1);
                    },
                    onHorizontalDragUpdate: (details) {
                      _handleDragUpdate(details.localPosition, trackWidth, inset);
                    },
                    onHorizontalDragEnd: (_) => _handleDragEnd(),
                    onHorizontalDragCancel: _handleDragEnd,
                    child: Stack(
                      children: [
                        // Invisible hit target for dragging
                        Positioned.fill(
                          child: Container(
                            color: Colors.transparent,
                          ),
                        ),
                        // Visible thumb (circle)
                        Center(
                          child: Container(
                            key: ValueKey('split-handle-thumb-$i'),
                            width: thumbSize,
                            height: thumbSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 2,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.drag_handle,
                              color: Colors.blue,
                              size: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  double _getCumulativePercentage(int index) {
    if (index <= 0) return 0.0;
    if (index >= _orderedParticipantIds.length) return 100.0;

    double sum = 0.0;
    for (int i = 0; i < index; i++) {
      sum += _percentages[_orderedParticipantIds[i]] ?? 0.0;
    }
    return sum;
  }
}
