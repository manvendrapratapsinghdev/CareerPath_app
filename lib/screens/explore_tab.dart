import 'package:flutter/material.dart';

import '../models/breadcrumb_entry.dart';
import '../models/career_node.dart';
import '../models/stream_model.dart';
import '../services/career_data_service.dart';
import 'sub_option_screen.dart';

class ExploreTab extends StatefulWidget {
  final CareerDataService careerDataService;

  const ExploreTab({super.key, required this.careerDataService});

  @override
  State<ExploreTab> createState() => _ExploreTabState();
}

class _ExploreTabState extends State<ExploreTab> {
  // Palettes cycle by index — driven entirely by API data, no slug hardcoding.
  static const _iconPalette = <IconData>[
    Icons.science,
    Icons.account_balance,
    Icons.palette,
    Icons.school,
    Icons.work_outline,
  ];

  static const _colorPalette = <Color>[
    Color(0xFF4CAF50),
    Color(0xFF2196F3),
    Color(0xFFFF9800),
    Color(0xFF9C27B0),
    Color(0xFF009688),
  ];

  late Map<String, bool> _expandedStreams;
  final Map<String, Future<List<CareerNode>>> _categoryFutures = {};
  late Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    _expandedStreams = {};
    _initFuture = widget.careerDataService.ensureInitialized().then((_) {
      if (!mounted) return;
      final streams = widget.careerDataService.getAllStreams();
      setState(() {
        if (streams.isNotEmpty) {
          _expandedStreams[streams[0].id] = true;
          _categoryFutures[streams[0].id] =
              widget.careerDataService.fetchStreamCategories(streams[0].id);
          for (int i = 1; i < streams.length; i++) {
            _expandedStreams[streams[i].id] = false;
          }
        }
      });
    });
  }

  Future<void> _refreshData() async {
    widget.careerDataService.reset();
    setState(() {
      _expandedStreams = {};
      _categoryFutures.clear();
      _initFuture = widget.careerDataService.ensureInitialized().then((_) {
        if (!mounted) return;
        final streams = widget.careerDataService.getAllStreams();
        setState(() {
          if (streams.isNotEmpty) {
            _expandedStreams[streams[0].id] = true;
            _categoryFutures[streams[0].id] =
                widget.careerDataService.fetchStreamCategories(streams[0].id);
            for (int i = 1; i < streams.length; i++) {
              _expandedStreams[streams[i].id] = false;
            }
          }
        });
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 12),
                const Text('Failed to load data',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _refreshData,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        final streams = widget.careerDataService.getAllStreams();
        if (streams.isEmpty) {
          return const Center(child: Text('No streams available.'));
        }

        return RefreshIndicator(
          onRefresh: _refreshData,
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: streams.length,
            itemBuilder: (context, index) {
              final stream = streams[index];
              return _StreamSection(
                stream: stream,
                categoryFuture: _categoryFutures[stream.id],
                careerDataService: widget.careerDataService,
                icon: _iconPalette[index % _iconPalette.length],
                color: _colorPalette[index % _colorPalette.length],
                isExpanded: _expandedStreams[stream.id] ?? false,
                onExpanded: () {
                  setState(() {
                    final willExpand = !(_expandedStreams[stream.id] ?? false);
                    _expandedStreams[stream.id] = willExpand;
                    if (willExpand) {
                      _categoryFutures[stream.id] ??=
                          widget.careerDataService
                              .fetchStreamCategories(stream.id);
                    }
                  });
                },
              );
            },
          ),
        );
      },
    );
  }
}

class _StreamSection extends StatelessWidget {
  final StreamModel stream;
  final Future<List<CareerNode>>? categoryFuture;
  final CareerDataService careerDataService;
  final IconData icon;
  final Color color;
  final bool isExpanded;
  final VoidCallback onExpanded;

  const _StreamSection({
    required this.stream,
    required this.categoryFuture,
    required this.careerDataService,
    required this.icon,
    required this.color,
    required this.isExpanded,
    required this.onExpanded,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        margin: EdgeInsets.zero,
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          title: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stream.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                    ),
                    Text(
                      '${stream.rootNodeCount} categor${stream.rootNodeCount != 1 ? 'ies' : 'y'}',
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
          onExpansionChanged: (_) => onExpanded(),
          children: [
            if (categoryFuture == null)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              FutureBuilder<List<CareerNode>>(
                future: categoryFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final categories = snapshot.data ?? [];
                  if (categories.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child: Text(
                          'No categories available',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ),
                        ),
                      ),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Column(
                      children: categories
                          .map(
                            (node) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Card(
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => SubOptionScreen(
                                          careerDataService: careerDataService,
                                          nodeId: node.id,
                                          breadcrumbs: [
                                            BreadcrumbEntry(
                                                nodeId: node.id, label: node.name),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 14),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: color.withValues(alpha: 0.1),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Icon(Icons.folder_outlined,
                                              color: color, size: 22),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(node.name,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleSmall),
                                              if (!node.isLeaf)
                                                Text(
                                                  '${node.childCount} sub-paths',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: colorScheme
                                                            .onSurfaceVariant,
                                                      ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        Icon(Icons.chevron_right,
                                            color: colorScheme.onSurfaceVariant),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
