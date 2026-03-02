import 'package:flutter/material.dart';

import '../models/breadcrumb_entry.dart';
import '../models/career_node.dart';
import '../services/career_data_service.dart';

class SubOptionScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final children = careerDataService.getChildrenOf(nodeId);
    final currentNode = careerDataService.getNodeById(nodeId);

    return Scaffold(
      appBar: AppBar(
        title: Text(breadcrumbs.isNotEmpty ? breadcrumbs.last.label : ''),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Breadcrumb trail
          if (breadcrumbs.length > 1)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: _buildBreadcrumbs(context),
              ),
            ),
          // Content
          if (children.isEmpty)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_outline,
                          size: 64, color: Colors.green),
                      const SizedBox(height: 16),
                      Text(
                        currentNode?.name ?? '',
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'This is a final career option.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: children.length,
                itemBuilder: (context, index) {
                  final child = children[index];
                  return Card(
                    child: ListTile(
                      title: Text(child.name),
                      trailing: child.isLeaf
                          ? const Icon(Icons.star_outline, color: Colors.amber)
                          : const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SubOptionScreen(
                              careerDataService: careerDataService,
                              nodeId: child.id,
                              breadcrumbs: [
                                ...breadcrumbs,
                                BreadcrumbEntry(
                                    nodeId: child.id, label: child.name),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildBreadcrumbs(BuildContext context) {
    final widgets = <Widget>[];
    for (int i = 0; i < breadcrumbs.length; i++) {
      final crumb = breadcrumbs[i];
      final isLast = i == breadcrumbs.length - 1;

      if (i > 0) {
        widgets.add(const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey),
        ));
      }

      widgets.add(
        GestureDetector(
          onTap: isLast
              ? null
              : () {
                  // Pop back to the corresponding screen
                  final popCount = breadcrumbs.length - 1 - i;
                  for (int j = 0; j < popCount; j++) {
                    Navigator.pop(context);
                  }
                },
          child: Text(
            crumb.label,
            style: TextStyle(
              color: isLast
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey[600],
              fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      );
    }
    return widgets;
  }
}
