import 'package:flutter/material.dart';

class DepthIndicator extends StatelessWidget {
  final int currentDepth;
  final int? maxDepth;

  const DepthIndicator({
    super.key,
    required this.currentDepth,
    this.maxDepth,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasMax = maxDepth != null;
    final label = hasMax ? 'Level $currentDepth of $maxDepth' : 'Level $currentDepth';
    final useCompact = hasMax && maxDepth! > 8;

    return Semantics(
      label: '$label in career path',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
          if (hasMax && !useCompact) ...[
            const SizedBox(width: 6),
            ...List.generate(maxDepth!, (i) {
              final isFilled = i < currentDepth;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isFilled
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant.withValues(alpha: 0.25),
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
