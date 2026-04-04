import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../models/career_node.dart';
import '../models/leaf_details.dart';
import '../services/career_data_service.dart';
import '../widgets/shimmer_loading.dart';

class CompareScreen extends StatefulWidget {
  final CareerDataService careerDataService;
  final List<CareerNode> nodes;

  const CompareScreen({
    super.key,
    required this.careerDataService,
    required this.nodes,
  });

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  late final Future<List<LeafDetails?>> _detailsFuture;

  @override
  void initState() {
    super.initState();
    _detailsFuture = Future.wait(
      widget.nodes.map((n) => widget.careerDataService.getLeafDetails(n.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.compare_title),
      ),
      body: FutureBuilder<List<LeafDetails?>>(
        future: _detailsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: AppSpacing.pagePadding,
              child: SkeletonList(itemCount: 4),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                l.compare_failedToLoadDetails,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            );
          }
          final details = snapshot.data ?? [];
          return _buildComparison(context, details);
        },
      ),
    );
  }

  Widget _buildComparison(BuildContext context, List<LeafDetails?> details) {
    final l = AppLocalizations.of(context)!;
    final colors = [
      AppColors.science,
      AppColors.commerce,
      AppColors.art,
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Career names header
          _buildSection(
            context,
            icon: Icons.star_rounded,
            title: l.compare_careerPath,
            child: Row(
              children: List.generate(details.length, (i) {
                final d = details[i];
                final color = colors[i % colors.length];
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: i > 0 ? AppSpacing.sm : 0,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.08),
                        borderRadius: AppRadius.mdAll,
                        border: Border.all(
                          color: color.withValues(alpha: 0.2),
                          width: 0.5,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.emoji_events_rounded,
                              color: color, size: 28),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            d?.name ?? widget.nodes[i].name,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(color: color),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Institutes comparison
          _buildSection(
            context,
            icon: Icons.school_rounded,
            title: l.compare_topInstitutes,
            child: _buildComparisonRow(
              context,
              details,
              colors,
              (d) => d?.institutes
                      .take(3)
                      .map((i) =>
                          '${i.name}${i.city != null ? ' (${i.city})' : ''}')
                      .toList() ??
                  [],
              emptyLabel: l.compare_noInstitutes,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Job Sectors comparison
          _buildSection(
            context,
            icon: Icons.work_rounded,
            title: l.compare_jobSectors,
            child: _buildComparisonRow(
              context,
              details,
              colors,
              (d) => d?.jobSectors.take(3).map((s) => s.name).toList() ?? [],
              emptyLabel: l.compare_noSectors,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Books comparison
          _buildSection(
            context,
            icon: Icons.menu_book_rounded,
            title: l.compare_recommendedBooks,
            child: _buildComparisonRow(
              context,
              details,
              colors,
              (d) => d?.books.take(3).map((b) => b.title).toList() ?? [],
              emptyLabel: l.compare_noBooks,
            ),
          ),

          const SizedBox(height: AppSpacing.xxxl),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: AppSpacing.sm),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        child,
      ],
    );
  }

  Widget _buildComparisonRow(
    BuildContext context,
    List<LeafDetails?> details,
    List<Color> colors,
    List<String> Function(LeafDetails?) extractor, {
    required String emptyLabel,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(details.length, (i) {
        final items = extractor(details[i]);
        final color = colors[i % colors.length];
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: i > 0 ? AppSpacing.sm : 0),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: AppRadius.mdAll,
                border: Border.all(
                  color: color.withValues(alpha: 0.15),
                  width: 0.5,
                ),
              ),
              child: items.isEmpty
                  ? Text(
                      emptyLabel,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: items
                          .map((item) => Padding(
                                padding: const EdgeInsets.only(
                                    bottom: AppSpacing.xs),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('- ',
                                        style: TextStyle(
                                            color: color,
                                            fontWeight: FontWeight.w700)),
                                    Expanded(
                                      child: Text(
                                        item,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ))
                          .toList(),
                    ),
            ),
          ),
        );
      }),
    );
  }
}
