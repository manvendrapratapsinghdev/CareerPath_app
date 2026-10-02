import '../models/state_region.dart';

/// How specific a [ResolvedPlace] is. Districts come from the `districts`
/// table, which is still empty, so [PlaceLevel.district] is not produced yet.
enum PlaceLevel { state, district, city }

/// What part of the text matched: an official name, a known alias
/// ("Bangalore", "Orissa") or a state abbreviation ("RJ", "UP").
enum PlaceMatch { name, alias, abbreviation }

/// A place named in some text, from [LocationService.resolve].
class ResolvedPlace {
  final PlaceLevel level;

  /// The state or UT. Null only for a city found in more than one state
  /// (e.g. Bilaspur, in Chhattisgarh and Himachal Pradesh).
  final StateRegion? state;

  /// Reserved for the district level; null until `districts` is filled.
  final String? district;

  /// The city as shown to students ("Bengaluru"), for [PlaceLevel.city].
  final String? city;

  /// Every spelling counted as [city], compacted (lowercase letters and
  /// digits only): "bengaluru" and "bangalore" are the same city.
  final Set<String> cityKeys;

  final PlaceMatch via;

  const ResolvedPlace({
    required this.level,
    required this.via,
    this.state,
    this.district,
    this.city,
    this.cityKeys = const {},
  });

  /// What to show: the city, else the district, else the state name.
  String get label => city ?? district ?? state?.name ?? '';

  /// True when an institute stored with these location strings is in this
  /// place. A record with a city but no state still counts for a state its
  /// city is named after (New Delhi, Goa), as the catalog search does.
  bool matches({String? city, String? district, String? state}) {
    final stateKey = LocationService.compact(state);
    if (level == PlaceLevel.state) {
      final wanted = LocationService.compact(this.state?.name);
      if (stateKey.isNotEmpty) return stateKey == wanted;
      return wanted.isNotEmpty &&
          LocationService.compact(city).contains(wanted);
    }
    final inCity =
        cityKeys.contains(LocationService.compact(city)) ||
        cityKeys.contains(LocationService.compact(district));
    if (!inCity) return false;
    final region = this.state;
    return region == null ||
        stateKey.isEmpty ||
        stateKey == LocationService.compact(region.name);
  }

  @override
  String toString() => 'ResolvedPlace(${level.name}: $label, ${state?.code})';
}

/// Resolves place names in typed, chat and voice text to a state or city
/// (plan §6.6), so every entry point filters the same way.
///
/// States come from the `states` table; cities from the distinct
/// `institutes.city` values until `places` / `districts` are filled, when
/// the same API gains the district level.
class LocationService {
  /// Old or common names → (city as shown, state code). Matching either
  /// spelling finds rows stored under both ("Bangalore" and "Bengaluru").
  static const cityAliases = <String, (String, String)>{
    'bangalore': ('Bengaluru', 'IN-KA'),
    'bombay': ('Mumbai', 'IN-MH'),
    'madras': ('Chennai', 'IN-TN'),
    'calcutta': ('Kolkata', 'IN-WB'),
    'poona': ('Pune', 'IN-MH'),
    'gurgaon': ('Gurugram', 'IN-HR'),
    'mysore': ('Mysuru', 'IN-KA'),
    'mangalore': ('Mangaluru', 'IN-KA'),
    'belgaum': ('Belagavi', 'IN-KA'),
    'hubli': ('Hubballi', 'IN-KA'),
    'baroda': ('Vadodara', 'IN-GJ'),
    'trivandrum': ('Thiruvananthapuram', 'IN-KL'),
    'cochin': ('Kochi', 'IN-KL'),
    'calicut': ('Kozhikode', 'IN-KL'),
    'benares': ('Varanasi', 'IN-UP'),
    'banaras': ('Varanasi', 'IN-UP'),
    'allahabad': ('Prayagraj', 'IN-UP'),
    'vizag': ('Visakhapatnam', 'IN-AP'),
    'bhubaneshwar': ('Bhubaneswar', 'IN-OD'),
    'gauhati': ('Guwahati', 'IN-AS'),
    'simla': ('Shimla', 'IN-HP'),
  };

  /// Former or informal state names → state code.
  static const stateAliases = <String, String>{
    'orissa': 'IN-OD',
    'pondicherry': 'IN-PY',
    'uttaranchal': 'IN-UK',
    'ncr': 'IN-DL',
    'delhincr': 'IN-DL',
    'nctofdelhi': 'IN-DL',
    'jammukashmir': 'IN-JK',
    'andaman': 'IN-AN',
    'andamannicobar': 'IN-AN',
    'damandiu': 'IN-DH',
    'dadranagarhaveli': 'IN-DH',
  };

  /// Abbreviations beyond the ISO code suffixes (`IN-RJ` → "rj").
  static const extraAbbreviations = <String, String>{
    'ts': 'IN-TG',
    'ua': 'IN-UK',
    'or': 'IN-OD',
    'ct': 'IN-CG',
  };

  /// Abbreviations safe to pick out of a longer sentence; the rest
  /// ("as", "or", "ga", "an" …) are ordinary words there and only count
  /// when they are the whole text.
  static const sentenceAbbreviations = {
    'ap',
    'br',
    'cg',
    'dl',
    'gj',
    'hp',
    'hr',
    'jh',
    'jk',
    'ka',
    'kl',
    'mh',
    'mp',
    'od',
    'pb',
    'rj',
    'tg',
    'tn',
    'ts',
    'ua',
    'uk',
    'up',
    'wb',
  };

  /// Placeholder city values that are not places.
  static const _notPlaces = {'various', 'online', 'multiple', 'panindia'};

  /// Longest phrase tried when scanning a sentence ("andaman and nicobar
  /// islands" is four words).
  static const _maxWords = 4;

  final Future<List<StateRegion>> Function() _loadStates;
  final Future<List<({String city, String? state})>> Function() _loadCities;

  List<StateRegion> _states = const [];
  final _stateByKey = <String, StateRegion>{};
  final _stateByCode = <String, StateRegion>{};
  final _abbreviations = <String, StateRegion>{};
  final _cities = <String, _City>{};
  final _cityKeyToCanonical = <String, String>{};
  bool _loaded = false;
  Future<void>? _loading;

  LocationService({
    required Future<List<StateRegion>> Function() loadStates,
    required Future<List<({String city, String? state})>> Function() loadCities,
  }) : _loadStates = loadStates,
       _loadCities = loadCities;

  /// All states and UTs, by name; empty until [ensureLoaded] completes.
  List<StateRegion> get states => _states;

  Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    return _loading ??= Future.wait([_loadStates(), _loadCities()])
        .then((results) {
          _index(
            results[0] as List<StateRegion>,
            results[1] as List<({String city, String? state})>,
          );
          _loaded = true;
        })
        .whenComplete(() => _loading = null);
  }

  /// The place [text] names, or null. Loads the data on first use.
  Future<ResolvedPlace?> resolve(String text) async {
    await ensureLoaded();
    return resolveLoaded(text);
  }

  /// Like [resolve], synchronously, once [ensureLoaded] has completed
  /// (returns null before that).
  ///
  /// The whole text is tried first: state name → city → city alias →
  /// state alias → state abbreviation. Otherwise the words are scanned,
  /// longest phrase first, and a city wins over a state (its state must
  /// agree when both are named: "Jodhpur, Rajasthan").
  ResolvedPlace? resolveLoaded(String text) {
    final words = _words(text);
    if (words.isEmpty) return null;
    final whole = _match(words.join(''), sentence: false);
    if (whole != null) return whole;

    ResolvedPlace? city;
    ResolvedPlace? state;
    final used = List.filled(words.length, false);
    for (var size = _maxWords; size >= 1; size--) {
      for (var i = 0; i + size <= words.length; i++) {
        if (used.sublist(i, i + size).any((u) => u)) continue;
        final found = _match(
          words.sublist(i, i + size).join(''),
          sentence: true,
        );
        if (found == null) continue;
        used.fillRange(i, i + size, true);
        if (found.level == PlaceLevel.city) {
          city ??= found;
        } else {
          state ??= found;
        }
      }
    }
    if (city != null &&
        (state == null ||
            city.state == null ||
            city.state!.code == state.state!.code)) {
      return city;
    }
    return state ?? city;
  }

  /// The [StateRegion] for a stored state name ("Tamil Nadu"), or null.
  StateRegion? stateNamed(String? name) => _stateByKey[compact(name)];

  /// The state for an ISO code ("IN-RJ"), or null.
  StateRegion? stateByCode(String code) => _stateByCode[code.toUpperCase()];

  /// Cities with institutes in [stateCode], by name (the level below the
  /// state until districts are loaded).
  List<String> citiesIn(String stateCode) {
    final code = stateCode.toUpperCase();
    final names = [
      for (final city in _cities.values)
        if (city.listed && city.stateCodes.contains(code)) city.name,
    ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  /// Lowercase letters and digits only: "Tamil Nadu" → "tamilnadu".
  static String compact(String? text) =>
      (text ?? '').toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

  static List<String> _words(String text) => text
      .toLowerCase()
      .replaceAll('.', '')
      .split(RegExp('[^a-z0-9]+'))
      .where((w) => w.isNotEmpty && w != 'and')
      .toList(growable: false);

  ResolvedPlace? _match(String key, {required bool sentence}) {
    if (key.isEmpty) return null;
    final byName = _stateByKey[key];
    if (byName != null) return _stateResult(byName, PlaceMatch.name);
    final canonical = _cityKeyToCanonical[key];
    if (canonical != null) {
      final city = _cities[canonical]!;
      return ResolvedPlace(
        level: PlaceLevel.city,
        via: key == canonical ? PlaceMatch.name : PlaceMatch.alias,
        city: city.name,
        cityKeys: city.keys,
        state: city.stateCodes.length == 1
            ? _stateByCode[city.stateCodes.single]
            : null,
      );
    }
    final aliased = _stateByCode[stateAliases[key]];
    if (aliased != null) return _stateResult(aliased, PlaceMatch.alias);
    if (!sentence || sentenceAbbreviations.contains(key)) {
      final abbreviated = _abbreviations[key];
      if (abbreviated != null) {
        return _stateResult(abbreviated, PlaceMatch.abbreviation);
      }
    }
    return null;
  }

  static ResolvedPlace _stateResult(StateRegion state, PlaceMatch via) =>
      ResolvedPlace(level: PlaceLevel.state, via: via, state: state);

  void _index(
    List<StateRegion> states,
    List<({String city, String? state})> cities,
  ) {
    _states = List.unmodifiable(
      [...states]..sort((a, b) => a.name.compareTo(b.name)),
    );
    for (final state in states) {
      // State names without "and" too, as [_words] drops it.
      _stateByKey[compact(state.name)] = state;
      _stateByKey[compact(state.name.replaceAll(' and ', ' '))] = state;
      _stateByCode[state.code.toUpperCase()] = state;
      final suffix = state.code.split('-').last.toLowerCase();
      _abbreviations[suffix] = state;
    }
    for (final entry in extraAbbreviations.entries) {
      final state = _stateByCode[entry.value];
      if (state != null) _abbreviations[entry.key] = state;
    }
    for (final entry in cityAliases.entries) {
      final (name, code) = entry.value;
      final canonical = compact(name);
      final city = _cities[canonical] ??= _City(name);
      city.keys.addAll({canonical, entry.key});
      if (_stateByCode.containsKey(code)) city.stateCodes.add(code);
      _cityKeyToCanonical[entry.key] = canonical;
      _cityKeyToCanonical[canonical] = canonical;
    }
    for (final row in cities) {
      final key = compact(row.city);
      if (key.isEmpty || _notPlaces.contains(key)) continue;
      final canonical = _cityKeyToCanonical[key] ?? key;
      final name = row.city.trim();
      final city = _cities[canonical] ??= _City(name);
      // Prefer "Jodhpur" over a shouted "JODHPUR" for display.
      if (city.name == city.name.toUpperCase() && name != name.toUpperCase()) {
        city.name = name;
      }
      city.keys.add(key);
      city.listed = true;
      _cityKeyToCanonical[key] = canonical;
      final state = stateNamed(row.state);
      if (state != null) city.stateCodes.add(state.code);
    }
  }
}

class _City {
  String name;
  final Set<String> keys = {};
  final Set<String> stateCodes = {};

  /// Some institute is stored in this city (alias-only cities are not).
  bool listed = false;

  _City(this.name);
}
