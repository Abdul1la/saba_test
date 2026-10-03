import 'package:flutter/material.dart';

import '../theme/app_dimensions.dart';
import '../theme/saba_icons.dart';
import '../utils/context_extensions.dart';

/// One stop on a trail: what happened, when, and whether it has happened yet.
@immutable
class TimelineEntry {
  const TimelineEntry({
    required this.label,
    required this.isDone,
    this.caption,
    this.note,
    this.color,
  });

  final String label;

  /// Reached already. A pending stop is drawn hollow and quiet — the customer
  /// should be able to tell at a glance where the parcel actually is.
  final bool isDone;

  /// The timestamp, or whatever dates this stop.
  final String? caption;

  /// A free line from the seller or the courier.
  final String? note;

  /// Overrides the dot colour for a stop that carries its own meaning, such as
  /// a cancellation.
  final Color? color;
}

/// The shared progress trail.
///
/// An order's history and a return's progress are the same drawing — a column
/// of dots joined by a line — so they are the same widget. The difference is
/// only which entries are marked done.
///
/// The last completed stop is filled and carries a check; everything after it
/// is a hollow ring in the border colour, and the joining line changes colour
/// at exactly that point, so "where am I" is answered without reading a word.
class StatusTimeline extends StatelessWidget {
  const StatusTimeline({super.key, required this.entries});

  final List<TimelineEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();

    final market = context.market;
    final lastDone = entries.lastIndexWhere((entry) => entry.isDone);

    return Column(
      children: [
        for (var index = 0; index < entries.length; index++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Rail(
                  entry: entries[index],
                  isLast: index == entries.length - 1,
                  // The line below a stop is live only while the trail is
                  // still live below it.
                  isLineDone: index < lastDone,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: index == entries.length - 1
                          ? 0
                          : AppSpacing.lg + 2,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entries[index].label,
                          style: context.textStyles.bodyMedium?.copyWith(
                            fontSize: 14,
                            fontWeight: entries[index].isDone
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: entries[index].isDone
                                ? context.colors.onSurface
                                : market.textMuted,
                          ),
                        ),
                        if (entries[index].caption != null) ...[
                          const SizedBox(height: AppSpacing.xxs - 1),
                          Text(
                            entries[index].caption!,
                            style: context.textStyles.labelSmall,
                          ),
                        ],
                        if (entries[index].note != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            entries[index].note!,
                            style: context.textStyles.bodySmall?.copyWith(
                              height: 1.45,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The dot and the line beneath it.
class _Rail extends StatelessWidget {
  const _Rail({
    required this.entry,
    required this.isLast,
    required this.isLineDone,
  });

  final TimelineEntry entry;
  final bool isLast;
  final bool isLineDone;

  @override
  Widget build(BuildContext context) {
    final market = context.market;
    final color = entry.color ?? context.colors.primary;

    return SizedBox(
      width: 22,
      child: Column(
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: entry.isDone ? color : Colors.transparent,
              border: entry.isDone
                  ? null
                  : Border.all(color: market.border, width: 2),
            ),
            child: entry.isDone
                ? SabaIcon(
                    SabaIcons.check,
                    size: 13,
                    color: context.colors.onPrimary,
                  )
                : null,
          ),
          if (!isLast)
            Expanded(
              child: Container(
                width: 2,
                margin: const EdgeInsets.symmetric(vertical: 2),
                color: isLineDone ? color : market.border,
              ),
            ),
        ],
      ),
    );
  }
}
