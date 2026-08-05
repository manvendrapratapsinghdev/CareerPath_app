import 'package:career_path/models/career_node.dart';
import 'package:career_path/models/stream_model.dart';
import 'package:career_path/services/api_client.dart';
import 'package:career_path/services/career_data_service.dart';
import 'package:career_path/services/local_ai_grounding_service.dart';
import 'package:flutter_test/flutter_test.dart';

CareerDataService _careerService() {
  final service = CareerDataService(ApiClient());
  service.initializeWithData(
    [
      StreamModel(id: 'science', name: 'Science', categoryIds: ['engineering']),
    ],
    {
      'engineering': CareerNode(
        id: 'engineering',
        name: 'Engineering',
        intro: 'Study technology and solve practical problems.',
        childIds: const ['computer-science'],
      ),
      'computer-science': CareerNode(
        id: 'computer-science',
        name: 'Computer Science',
        intro: 'Learn software, algorithms, and computing.',
      ),
      'bsc-computer-science': CareerNode(
        id: 'bsc-computer-science',
        name: 'B.Sc Computer Science',
        intro: 'An undergraduate computer science course.',
      ),
      'precision-farming': CareerNode(
        id: 'precision-farming',
        name: 'AgriTech / Precision Farming Specialist',
      ),
      'novelist': CareerNode(id: 'novelist', name: 'Author / Novelist'),
      'journalist': CareerNode(id: 'journalist', name: 'Broadcast Journalist'),
    },
  );
  return service;
}

void main() {
  test('retrieves matching bundled Explore nodes with source IDs', () async {
    final grounding = LocalAiGroundingService(_careerService());

    final result = await grounding.retrieve(
      query: 'Tell me about engineering',
      streamId: 'science',
    );

    expect(result.isEmpty, isFalse);
    expect(result.text, contains('SOURCE career_node:engineering'));
    expect(result.text, contains('Computer Science'));
    expect(result.sources.first.exploreNodeId, 'engineering');
  });

  test('uses selected stream roots for a general career request', () async {
    final grounding = LocalAiGroundingService(_careerService());

    final result = await grounding.retrieve(
      query: 'Suggest a career option',
      streamId: 'science',
    );

    expect(
      result.sources.map((source) => source.exploreNodeId),
      contains('engineering'),
    );
  });

  test('returns no context for an unrelated request', () async {
    final grounding = LocalAiGroundingService(_careerService());

    final result = await grounding.retrieve(
      query: 'What is the weather tomorrow?',
      streamId: 'science',
    );

    expect(result.isEmpty, isTrue);
  });

  test('matches compact course aliases such as BSC to B.Sc', () async {
    final grounding = LocalAiGroundingService(_careerService());

    final result = await grounding.retrieve(
      query: 'List colleges for BSC',
      streamId: 'science',
    );

    expect(result.sources.first.exploreNodeId, 'bsc-computer-science');
    expect(
      result.sources.map((source) => source.exploreNodeId),
      isNot(contains('novelist')),
    );
  });
}
