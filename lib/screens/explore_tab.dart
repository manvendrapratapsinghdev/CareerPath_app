import 'package:flutter/material.dart';

import '../models/breadcrumb_entry.dart';
import '../models/career_node.dart';
import '../models/stream_model.dart';
import '../services/career_data_service.dart';
import 'sub_option_screen.dart';

class ExploreTab extends StatelessWidget {
  final CareerDataService careerDataService;

  const ExploreTab({super.key, required this.careerDataService});

  @override
  Widget build(BuildContext context) {
    final streams = careerDataService.getAllStreams();

    if (streams.isEmpty) {
      return const Center(child: Text('No streams available.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: streams.length,
      itemBuilder: (context, index) {
        final stream = streams[index];
        final categories = careerDataService.getCategoriesForStream(stream.id);
        return _StreamSection(
          stream: stream,
          categories: categories,
          careerDataService: careerDataService,
        );
      },
    );
  }
}

class _StreamSection extends StatelessWidget {
  final StreamModel stream;
  final List<CareerNode> categories;
  final CareerDataService careerDataService;

  const _StreamSection({
    required this.stream,
    required this.categories,
    required this.careerDataService,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            stream.name,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        ...categories.map((node) => Card(
              child: ListTile(
                title: Text(node.name),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SubOptionScreen(
                        careerDataService: careerDataService,
                        nodeId: node.id,
                        breadcrumbs: [
                          BreadcrumbEntry(nodeId: node.id, label: node.name),
                        ],
                      ),
                    ),
                  );
                },
              ),
            )),
        const SizedBox(height: 8),
      ],
    );
  }
}
