import '../models/state_region.dart';
import '../models/district_region.dart';
import '../models/institute_campus.dart';
import '../models/institute_catalog.dart';
import '../models/institute_location_filter.dart';
import '../models/place_alias.dart';
import '../models/place_record.dart';

/// How specific a [ResolvedPlace] is.
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

  /// District label for a district match or an unambiguous mapped city.
  /// Null for a city spanning multiple districts or for state-only matches.
  final String? district;
  final int? districtLgd;
  final Set<int> districtLgds;

  /// The city as shown to students ("Bengaluru"), for [PlaceLevel.city].
  final String? city;

  /// Every spelling counted as [city], compacted (lowercase letters and
  /// digits only): "bengaluru" and "bangalore" are the same city.
  final Set<String> cityKeys;
  final Set<int> placeIds;

  final PlaceMatch via;

  const ResolvedPlace({
    required this.level,
    required this.via,
    this.state,
    this.district,
    this.districtLgd,
    this.districtLgds = const {},
    this.city,
    this.cityKeys = const {},
    this.placeIds = const {},
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
    if (level == PlaceLevel.district) {
      final wanted = LocationService.compact(this.district);
      final stored = LocationService.compact(district);
      return stored == wanted ||
          (stored.isEmpty &&
              stateKey.isNotEmpty &&
              stateKey == LocationService.compact(this.state?.name));
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

  bool matchesCampus(InstituteCampus campus) {
    if (level == PlaceLevel.state) {
      return campus.stateCode == state?.code ||
          LocationService.compact(campus.stateName) ==
              LocationService.compact(state?.name);
    }
    if (level == PlaceLevel.district) {
      if (districtLgds.isNotEmpty && campus.districtLgd != 0) {
        return districtLgds.contains(campus.districtLgd);
      }
      if (districtLgd != null && campus.districtLgd != 0) {
        return campus.districtLgd == districtLgd;
      }
      return LocationService.compact(campus.districtName) ==
          LocationService.compact(district);
    }
    if (placeIds.isNotEmpty && campus.placeId != 0) {
      return placeIds.contains(campus.placeId);
    }
    return matches(
      city: campus.placeName,
      district: campus.districtName,
      state: campus.stateName,
    );
  }

  @override
  String toString() => 'ResolvedPlace(${level.name}: $label, ${state?.code})';
}

/// Resolves place names in typed, chat and voice text to a state, district or
/// city (plan §6.6), so every entry point filters the same way. When location
/// tables are configured, filtering uses mapped campus links and does not
/// infer locations for institutes without one. Older callers without place
/// loaders retain the legacy distinct-`institutes.city` fallback.
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
  final Future<List<DistrictRegion>> Function()? _loadDistricts;
  final Future<List<PlaceRecord>> Function()? _loadPlaces;
  final Future<List<PlaceAlias>> Function()? _loadPlaceAliases;
  bool get hasCampusScopedLocationData => _loadPlaces != null;

  List<StateRegion> _states = const [];
  final _stateByKey = <String, StateRegion>{};
  final _stateByCode = <String, StateRegion>{};
  final _abbreviations = <String, StateRegion>{};
  final _cities = <String, _City>{};
  final _cityKeyToCanonical = <String, String>{};
  List<DistrictRegion> _districts = const [];
  List<PlaceRecord> _places = const [];
  final _districtByLgd = <int, DistrictRegion>{};
  final _districtByKey = <String, List<DistrictRegion>>{};
  final _placeById = <int, PlaceRecord>{};
  final _placeByKey = <String, List<PlaceRecord>>{};
  final _districtAliasKeys = <int, Set<String>>{};
  final _placeAliasKeys = <int, Set<String>>{};
  bool _loaded = false;
  Future<void>? _loading;

  LocationService({
    required Future<List<StateRegion>> Function() loadStates,
    required Future<List<({String city, String? state})>> Function() loadCities,
    Future<List<DistrictRegion>> Function()? loadDistricts,
    Future<List<PlaceRecord>> Function()? loadPlaces,
    Future<List<PlaceAlias>> Function()? loadPlaceAliases,
  }) : _loadStates = loadStates,
       _loadCities = loadCities,
       _loadDistricts = loadDistricts,
       _loadPlaces = loadPlaces,
       _loadPlaceAliases = loadPlaceAliases;

  /// All states and UTs, by name; empty until [ensureLoaded] completes.
  List<StateRegion> get states => _states;
  List<DistrictRegion> get districts => List.unmodifiable(_districts);
  List<PlaceRecord> get places => List.unmodifiable(_places);

  Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    return _loading ??= _loadData().whenComplete(() => _loading = null);
  }

  Future<void> _loadData() async {
    final futures = <Future<Object>>[_loadStates(), _loadCities()];
    final districtsIndex = _loadDistricts == null ? null : futures.length;
    if (_loadDistricts != null) futures.add(_loadDistricts());
    final placesIndex = _loadPlaces == null ? null : futures.length;
    if (_loadPlaces != null) futures.add(_loadPlaces());
    final aliasesIndex = _loadPlaceAliases == null ? null : futures.length;
    if (_loadPlaceAliases != null) futures.add(_loadPlaceAliases());
    final results = await Future.wait(futures);
    _index(
      results[0] as List<StateRegion>,
      results[1] as List<({String city, String? state})>,
      districts: districtsIndex != null
          ? results[districtsIndex] as List<DistrictRegion>
          : const [],
      places: placesIndex != null
          ? results[placesIndex] as List<PlaceRecord>
          : const [],
      aliases: aliasesIndex != null
          ? results[aliasesIndex] as List<PlaceAlias>
          : const [],
    );
    _loaded = true;
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

  List<DistrictRegion> districtsIn(String stateCode) {
    final code = stateCode.toUpperCase();
    return List.unmodifiable(
      _districts.where((district) => district.stateCode.toUpperCase() == code),
    );
  }

  List<PlaceRecord> placesInDistrict(int districtLgd) => List.unmodifiable(
    _places.where((place) => place.districtLgd == districtLgd),
  );

  DistrictRegion? districtByCode(int lgdCode) => _districtByLgd[lgdCode];

  PlaceRecord? placeById(int id) => _placeById[id];

  /// Match a saved location against mapped campus links. Legacy city/state
  /// values are used only when this service was created without place data.
  bool matchesFilter(InstituteLocationFilter filter, InstituteRecord record) {
    if (filter.isAllIndia) return true;
    if (filter.onlineOnly) {
      return (record.institute.city ?? '').toLowerCase().contains('online') ||
          record.courses.any(
            (course) => (course.mode ?? '').toLowerCase().contains('online'),
          );
    }

    bool campusMatches(InstituteCampus campus) {
      if (filter.placeId != null) {
        if (hasCampusScopedLocationData) {
          return campus.placeId == filter.placeId;
        }
        final aliasKeys =
            _placeAliasKeys[filter.placeId] ?? {compact(filter.placeName)};
        return campus.placeId == filter.placeId ||
            aliasKeys.contains(compact(campus.placeName));
      }
      if (filter.districtLgd != null) {
        if (hasCampusScopedLocationData) {
          return campus.districtLgd == filter.districtLgd;
        }
        final aliasKeys =
            _districtAliasKeys[filter.districtLgd] ??
            {compact(filter.districtName)};
        return campus.districtLgd == filter.districtLgd ||
            aliasKeys.contains(compact(campus.districtName));
      }
      if (hasCampusScopedLocationData) {
        return campus.stateCode.toUpperCase() ==
            filter.stateCode?.toUpperCase();
      }
      return campus.stateCode.toUpperCase() ==
              filter.stateCode?.toUpperCase() ||
          compact(campus.stateName) == compact(filter.stateName);
    }

    final institute = record.institute;
    if (record.campuses.any(campusMatches)) return true;
    if (hasCampusScopedLocationData) return false;
    if (record.campuses.isNotEmpty) return false;
    if (filter.placeId != null) {
      final keys =
          _placeAliasKeys[filter.placeId] ?? {compact(filter.placeName)};
      return keys.contains(compact(institute.city)) ||
          keys.contains(compact(institute.district));
    }
    if (filter.districtLgd != null) {
      final keys =
          _districtAliasKeys[filter.districtLgd] ??
          {compact(filter.districtName)};
      return keys.contains(compact(institute.district));
    }
    final selectedState = _stateByCode[filter.stateCode?.toUpperCase()];
    return selectedState != null &&
        (stateNamed(institute.state)?.code == selectedState.code ||
            compact(institute.city).contains(compact(selectedState.name)));
  }

  bool matchesRecord(ResolvedPlace place, InstituteRecord record) {
    if (hasCampusScopedLocationData) {
      return record.campuses.any(place.matchesCampus);
    }
    return place.matches(
          city: record.institute.city,
          district: record.institute.district,
          state: record.institute.state,
        ) ||
        record.campuses.any(place.matchesCampus);
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
    if (byName != null) {
      return _stateResult(
        byName,
        key == compact(byName.name) ? PlaceMatch.name : PlaceMatch.alias,
      );
    }
    final districtMatches = _districtByKey[key];
    // Prefer a named place when it shares a label with its district. A place
    // label may map to multiple districts; keeping all place IDs is safer
    // than silently narrowing the match to the district of the same name.
    if (districtMatches != null && _placeByKey[key] == null) {
      final states = districtMatches
          .map((district) => district.stateCode)
          .toSet();
      final lgdCodes = districtMatches
          .map((district) => district.lgdCode)
          .toSet();
      final state = states.length == 1
          ? _stateByCode[states.single.toUpperCase()]
          : null;
      return ResolvedPlace(
        level: PlaceLevel.district,
        state: state,
        district: districtMatches.first.name,
        districtLgd: lgdCodes.length == 1 ? lgdCodes.single : null,
        districtLgds: lgdCodes,
        via: districtMatches.any((district) => key == compact(district.name))
            ? PlaceMatch.name
            : PlaceMatch.alias,
      );
    }
    final placeMatches = _placeByKey[key];
    if (placeMatches != null) {
      final stateCodes = placeMatches.map((place) => place.stateCode).toSet();
      final districtLgds = placeMatches
          .map((place) => place.districtLgd)
          .toSet();
      final aliases = <String>{
        for (final place in placeMatches) ...?_placeAliasKeys[place.id],
      };
      final state = stateCodes.length == 1
          ? _stateByCode[stateCodes.single.toUpperCase()]
          : null;
      final district = districtLgds.length == 1
          ? placeMatches.first.districtName
          : null;
      return ResolvedPlace(
        level: PlaceLevel.city,
        state: state,
        district: district,
        districtLgd: districtLgds.length == 1 ? districtLgds.single : null,
        districtLgds: districtLgds,
        city: placeMatches.first.name,
        cityKeys: aliases,
        placeIds: {for (final place in placeMatches) place.id},
        via: placeMatches.any((place) => key == compact(place.name))
            ? PlaceMatch.name
            : PlaceMatch.alias,
      );
    }
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
    List<({String city, String? state})> cities, {
    List<DistrictRegion> districts = const [],
    List<PlaceRecord> places = const [],
    List<PlaceAlias> aliases = const [],
  }) {
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
    _districts = List.unmodifiable(
      [...districts]..sort((a, b) => a.name.compareTo(b.name)),
    );
    _places = List.unmodifiable(
      [...places]..sort((a, b) => a.name.compareTo(b.name)),
    );
    for (final district in districts) {
      _districtByLgd[district.lgdCode] = district;
      _addDistrictKey(compact(district.name), district);
      _districtAliasKeys[district.lgdCode] = {compact(district.name)};
    }
    for (final place in places) {
      _placeById[place.id] = place;
      _addPlaceKey(compact(place.name), place);
      _placeAliasKeys[place.id] = {compact(place.name)};
    }
    for (final alias in aliases) {
      final key = compact(alias.alias);
      if (alias.placeId != null) {
        final place = _placeById[alias.placeId];
        if (place != null) {
          _placeAliasKeys[place.id]!.add(key);
          _addPlaceKey(key, place);
        }
      } else if (alias.districtLgd != null) {
        final district = _districtByLgd[alias.districtLgd];
        if (district != null) {
          _districtAliasKeys[district.lgdCode]!.add(key);
          _addDistrictKey(key, district);
        }
      } else if (alias.stateCode != null) {
        final state = _stateByCode[alias.stateCode!.toUpperCase()];
        if (state != null) _stateByKey.putIfAbsent(key, () => state);
      }
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

  void _addDistrictKey(String key, DistrictRegion district) {
    final matches = _districtByKey.putIfAbsent(key, () => []);
    if (!matches.any((item) => item.lgdCode == district.lgdCode)) {
      matches.add(district);
    }
  }

  void _addPlaceKey(String key, PlaceRecord place) {
    final matches = _placeByKey.putIfAbsent(key, () => []);
    if (!matches.any((item) => item.id == place.id)) matches.add(place);
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
