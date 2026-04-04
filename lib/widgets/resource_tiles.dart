import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../models/book.dart';
import '../models/institute.dart';
import '../models/job_sector.dart';
import '../screens/web_view_screen.dart';
import '../widgets/page_transitions.dart';
import 'accent_icon_box.dart';

/// An expandable card section for a group of resources (books, institutes, etc).
class ResourceSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool isExpanded;
  final VoidCallback onToggle;
  final List<Widget> children;

  const ResourceSection({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.isExpanded,
    required this.onToggle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.xs,
        ),
        title: Row(
          children: [
            AccentIconBox(icon: icon, color: color, size: 36, iconSize: 18),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
        initiallyExpanded: isExpanded,
        onExpansionChanged: (_) => onToggle(),
        children: [
          if (children.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Center(
                child: Text(
                  AppLocalizations.of(context)!.common_noneAvailableYet,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.base, 0, AppSpacing.base, AppSpacing.md,
              ),
              child: Column(children: children),
            ),
        ],
      ),
    );
  }
}

// ── Resource Tiles ──────────────────────────────────────────────────────────

class BookTile extends StatelessWidget {
  final Book book;
  const BookTile({super.key, required this.book});

  void _openBook(BuildContext context) {
    if (book.url == null || book.url!.isEmpty) return;
    Navigator.push(
      context,
      SmoothPageRoute(
        page: WebViewScreen(
          title: book.title,
          url: book.url!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF6366F1);
    final uri = book.url != null ? Uri.tryParse(book.url!) : null;
    final hasUrl = uri != null && uri.hasScheme && uri.host.isNotEmpty;

    return ResourceTileWrapper(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: AppRadius.smAll,
            ),
            child: const Icon(Icons.book_rounded, size: 16, color: color),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (book.author != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    AppLocalizations.of(context)!.common_byAuthor(book.author!),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (book.description != null &&
                    book.description!.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    book.description!,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (hasUrl)
            IconButton(
              onPressed: () => _openBook(context),
              icon: const Icon(Icons.chevron_right_rounded, color: color),
              tooltip: AppLocalizations.of(context)!.common_viewBook,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              padding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }
}

class InstituteTile extends StatelessWidget {
  final Institute institute;
  const InstituteTile({super.key, required this.institute});

  void _openWebsite(BuildContext context) {
    if (institute.website == null || institute.website!.isEmpty) return;
    Navigator.push(
      context,
      SmoothPageRoute(
        page: WebViewScreen(
          title: institute.name,
          url: institute.website!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF14B8A6);
    final hasWebsite = institute.website != null && institute.website!.isNotEmpty;

    return ResourceTileWrapper(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: AppRadius.smAll,
            ),
            child: const Icon(Icons.location_city_rounded, size: 16, color: color),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  institute.name,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (institute.city != null) ...[
                  const SizedBox(height: 2),
                  Text(institute.city!,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
                if (institute.description != null &&
                    institute.description!.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    institute.description!,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (hasWebsite)
            IconButton(
              onPressed: () => _openWebsite(context),
              icon: const Icon(Icons.chevron_right_rounded, color: color),
              tooltip: AppLocalizations.of(context)!.common_visitWebsite,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              padding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }
}

class JobSectorTile extends StatelessWidget {
  final JobSector sector;
  const JobSectorTile({super.key, required this.sector});

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFF59E0B);
    return ResourceTileWrapper(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: AppRadius.smAll,
            ),
            child:
                const Icon(Icons.trending_up_rounded, size: 16, color: color),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sector.name,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (sector.description != null &&
                    sector.description!.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    sector.description!,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ResourceTileWrapper extends StatelessWidget {
  final Widget child;
  const ResourceTileWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: child,
    );
  }
}
