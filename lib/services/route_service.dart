import '../data/local_database.dart';
import '../models/domain.dart';
import '../models/domain_tier.dart';
import '../models/sqlite_values.dart';

/// How a domain is entered (`domains.route_type`).
enum RouteType {
  /// A college degree ladder (engineering, law …).
  degree,

  /// A statutory body's stages (CA / CMA / CS).
  professionalBody,

  /// Recruitment exams (civil services, banking, defence).
  exam,

  /// Both colleges and exams (aviation and maritime).
  mixed;

  /// Parses the DB value; unknown values read as [degree].
  static RouteType parse(String? value) => switch (value) {
    'professional_body' => professionalBody,
    'exam' => exam,
    'mixed' => mixed,
    _ => degree,
  };
}

/// The route into a career: its domain, how it is entered, the domain's
/// college ladder and the exams on the way.
class CareerRoute {
  final Domain domain;
  final RouteType type;

  /// The ladder, tier 1 (top) first; may be empty for exam routes.
  final List<DomainTier> tiers;

  /// The domain's entrance exams, then any tier-specific ones, each once.
  final List<String> entryExams;

  const CareerRoute({
    required this.domain,
    required this.type,
    required this.tiers,
    required this.entryExams,
  });

  List<String> get tierLabels =>
      tiers.map((tier) => tier.label).toList(growable: false);

  /// A college ladder is worth showing (degree or mixed routes).
  bool get hasCollegeLadder =>
      type == RouteType.degree || type == RouteType.mixed;
}

/// Looks up the route into a career node's domain (plan §9 `RouteService`).
class RouteService {
  final LocalDatabase _db;

  RouteService(this._db);

  /// The route for a career node, via its own or nearest ancestor's domain.
  /// Null when the node has no domain.
  Future<CareerRoute?> routeForNode(int nodeId) async {
    final slug = await _db.getDomainSlugForNode(nodeId);
    return slug == null ? null : routeForDomain(slug);
  }

  /// Looks up a route using the public career-node key. The Flutter career
  /// tree uses slugs, while older callers may still provide numeric IDs.
  Future<CareerRoute?> routeForNodeKey(String nodeKey) async {
    final slug = await _db.getDomainSlugForNodeKey(nodeKey);
    return slug == null ? null : routeForDomain(slug);
  }

  /// The route for a domain slug ("law"), or null if there is no such domain.
  Future<CareerRoute?> routeForDomain(String domainSlug) async {
    final domain = await _db.getDomain(domainSlug);
    if (domain == null) return null;
    final tiers = await _db.getDomainTiers(domainSlug);
    final exams = <String>{
      ...domain.entranceExamList,
      for (final tier in tiers) ...splitSqliteList(tier.entryExams),
    };
    return CareerRoute(
      domain: domain,
      type: RouteType.parse(domain.routeType),
      tiers: tiers,
      entryExams: List.unmodifiable(exams),
    );
  }
}
