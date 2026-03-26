import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/book.dart';
import '../models/breadcrumb_entry.dart';
import '../models/career_node.dart';
import '../models/institute.dart';
import '../models/job_sector.dart';
import '../models/leaf_details.dart';
import '../services/career_data_service.dart';

class SubOptionScreen extends StatefulWidget {
  final CareerDataService careerDataService;
  final String nodeId;
  final List<BreadcrumbEntry> breadcrumbs;

  const SubOptionScreen({
    super.key,
    required this.careerDataService,
    required this.nodeId,
    required this.breadcrumbs,
  });

  @override
  State<SubOptionScreen> createState() => _SubOptionScreenState();
}

class _SubOptionScreenState extends State<SubOptionScreen> {
  late Future<List<CareerNode>> _childrenFuture;
  late final CareerNode? _currentNode;
  Future<LeafDetails?>? _leafDetailsFuture;
  bool _booksExpanded = false;
  bool _institutesExpanded = false;
  bool _jobSectorsExpanded = false;

  @override
  void initState() {
    super.initState();
    _currentNode = widget.careerDataService.getNodeById(widget.nodeId);
    _childrenFuture = _loadChildren();
  }

  Future<List<CareerNode>> _loadChildren({bool forceRefresh = false}) async {
    final children = await widget.careerDataService
        .fetchChildrenOf(widget.nodeId, forceRefresh: forceRefresh);
    if (children.isEmpty && mounted) {
      setState(() {
        _leafDetailsFuture = widget.careerDataService
            .getLeafDetails(widget.nodeId, forceRefresh: forceRefresh);
      });
    }
    return children;
  }

  Future<void> _refreshData() async {
    setState(() {
      _leafDetailsFuture = null;
      _childrenFuture = _loadChildren(forceRefresh: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.breadcrumbs.isNotEmpty
            ? widget.breadcrumbs.last.label
            : ''),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Breadcrumb trail
          if (widget.breadcrumbs.length > 1)
            Container(
              width: double.infinity,
              color: colorScheme.surfaceContainerLow,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(children: _buildBreadcrumbs(context, colorScheme)),
              ),
            ),
          // Content
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshData,
              child: FutureBuilder<List<CareerNode>>(
                future: _childrenFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Error loading data.\nCheck your connection and try again.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colorScheme.error,
                            ),
                      ),
                    );
                  }
                  final children = snapshot.data ?? [];
                  if (children.isEmpty) {
                    return FutureBuilder<LeafDetails?>(
                      future: _leafDetailsFuture,
                      builder: (context, leafSnapshot) {
                        return _buildLeafView(
                          context,
                          _currentNode,
                          colorScheme,
                          leafSnapshot.data,
                          leafSnapshot.connectionState ==
                              ConnectionState.waiting,
                        );
                      },
                    );
                  }
                  return _buildChildList(context, children, colorScheme);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Leaf view ──────────────────────────────────────────────────────────────

  Widget _buildLeafView(
    BuildContext context,
    CareerNode? node,
    ColorScheme colorScheme,
    LeafDetails? details,
    bool loading,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero header
          Center(
            child: Column(
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.emoji_events,
                      size: 44, color: Colors.green),
                ),
                const SizedBox(height: 16),
                Text(
                  node?.name ?? '',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    '🎯 Final Career Option',
                    style: TextStyle(
                        color: Colors.green, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),

          // Intro text (if any)
          if (node?.intro != null && node!.intro!.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              node.intro!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ],

          const SizedBox(height: 24),

          // Loading spinner / detail sections
          if (loading)
            const Center(child: CircularProgressIndicator())
          else if (details != null) ...[
            _buildBooksSection(
              context,
              books: details.books,
              isExpanded: _booksExpanded,
              onExpanded: () {
                setState(() => _booksExpanded = !_booksExpanded);
              },
            ),
            const SizedBox(height: 12),
            _buildInstitutesSection(
              context,
              institutes: details.institutes,
              isExpanded: _institutesExpanded,
              onExpanded: () {
                setState(() => _institutesExpanded = !_institutesExpanded);
              },
            ),
            const SizedBox(height: 12),
            _buildJobSectorsSection(
              context,
              jobSectors: details.jobSectors,
              isExpanded: _jobSectorsExpanded,
              onExpanded: () {
                setState(() => _jobSectorsExpanded = !_jobSectorsExpanded);
              },
            ),
          ] else ...[
            Center(
              child: Text(
                'More details coming soon!',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
          ],

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildBooksSection(
    BuildContext context, {
    required List<Book> books,
    required bool isExpanded,
    required VoidCallback onExpanded,
  }) {
    const color = Colors.indigo;
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.menu_book_rounded, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recommended Books',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  Text(
                    books.isEmpty
                        ? 'No books available right now'
                        : '${books.length} book${books.length != 1 ? 's' : ''}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
        initiallyExpanded: isExpanded,
        onExpansionChanged: (_) => onExpanded(),
        children: [
          if (books.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  'No books available right now',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: books
                    .map(
                      (book) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.circle, size: 7, color: color),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: book.url != null
                                      ? InkWell(
                                          onTap: () async {
                                            final uri = Uri.tryParse(book.url!);
                                            if (uri != null && await canLaunchUrl(uri)) {
                                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                                            }
                                          },
                                          child: Text(
                                            book.title,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: color,
                                                  decoration: TextDecoration.underline,
                                                  decorationColor: color,
                                                ),
                                          ),
                                        )
                                      : Text(
                                          book.title,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(fontWeight: FontWeight.w600),
                                        ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            if (book.author != null)
                              Padding(
                                padding: const EdgeInsets.only(left: 15),
                                child: Text(
                                  'by ${book.author}',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                              ),
                            if (book.description != null && book.description!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4, left: 15),
                                child: Text(
                                  book.description!,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInstitutesSection(
    BuildContext context, {
    required List<Institute> institutes,
    required bool isExpanded,
    required VoidCallback onExpanded,
  }) {
    const color = Colors.teal;
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.school_rounded, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Top Institutes',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  Text(
                    institutes.isEmpty
                        ? 'No institutes available right now'
                        : '${institutes.length} institute${institutes.length != 1 ? 's' : ''}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
        initiallyExpanded: isExpanded,
        onExpansionChanged: (_) => onExpanded(),
        children: [
          if (institutes.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  'No institutes available right now',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: institutes
                    .map(
                      (institute) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.circle, size: 7, color: color),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    institute.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            if (institute.city != null)
                              Padding(
                                padding: const EdgeInsets.only(left: 15),
                                child: Text(
                                  institute.city!,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                              ),
                            if (institute.website != null && institute.website!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2, left: 15),
                                child: InkWell(
                                  onTap: () async {
                                    final uri = Uri.tryParse(institute.website!);
                                    if (uri != null && await canLaunchUrl(uri)) {
                                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                                    }
                                  },
                                  child: Text(
                                    institute.website!,
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: color,
                                          decoration: TextDecoration.underline,
                                          decorationColor: color,
                                        ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            if (institute.description != null && institute.description!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4, left: 15),
                                child: Text(
                                  institute.description!,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildJobSectorsSection(
    BuildContext context, {
    required List<JobSector> jobSectors,
    required bool isExpanded,
    required VoidCallback onExpanded,
  }) {
    const color = Colors.orange;
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.work_rounded, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Job Sectors',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  Text(
                    jobSectors.isEmpty
                        ? 'No job sectors available right now'
                        : '${jobSectors.length} sector${jobSectors.length != 1 ? 's' : ''}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
        initiallyExpanded: isExpanded,
        onExpansionChanged: (_) => onExpanded(),
        children: [
          if (jobSectors.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  'No job sectors available right now',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: jobSectors
                    .map(
                      (sector) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.circle, size: 7, color: color),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    sector.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                            if (sector.description != null && sector.description!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4, left: 15),
                                child: Text(
                                  sector.description!,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  // ── Child list ─────────────────────────────────────────────────────────────

  Widget _buildChildList(
    BuildContext context,
    List<CareerNode> children,
    ColorScheme colorScheme,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: children.length,
      itemBuilder: (context, index) {
        final child = children[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SubOptionScreen(
                      careerDataService: widget.careerDataService,
                      nodeId: child.id,
                      breadcrumbs: [
                        ...widget.breadcrumbs,
                        BreadcrumbEntry(nodeId: child.id, label: child.name),
                      ],
                    ),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: child.isLeaf
                            ? Colors.amber.withValues(alpha: 0.12)
                            : colorScheme.primaryContainer
                                .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        child.isLeaf
                            ? Icons.star_rounded
                            : Icons.account_tree_outlined,
                        color: child.isLeaf
                            ? Colors.amber[700]
                            : colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            child.name,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            child.isLeaf
                                ? 'Career endpoint'
                                : '${child.childCount} options ahead',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      child.isLeaf
                          ? Icons.arrow_forward_ios
                          : Icons.chevron_right,
                      size: child.isLeaf ? 16 : 24,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Breadcrumbs ────────────────────────────────────────────────────────────

  List<Widget> _buildBreadcrumbs(
      BuildContext context, ColorScheme colorScheme) {
    final widgets = <Widget>[];
    for (int i = 0; i < widget.breadcrumbs.length; i++) {
      final crumb = widget.breadcrumbs[i];
      final isLast = i == widget.breadcrumbs.length - 1;

      if (i > 0) {
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Icon(Icons.chevron_right,
              size: 16, color: colorScheme.onSurfaceVariant),
        ));
      }

      widgets.add(
        GestureDetector(
          onTap: isLast
              ? null
              : () {
                  final popCount = widget.breadcrumbs.length - 1 - i;
                  for (int j = 0; j < popCount; j++) {
                    Navigator.pop(context);
                  }
                },
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isLast
                  ? colorScheme.primaryContainer
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              crumb.label,
              style: TextStyle(
                fontSize: 13,
                color: isLast
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
                fontWeight:
                    isLast ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ),
      );
    }
    return widgets;
  }
}
