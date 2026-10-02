# Location data sources and review notes

## LGD state and district master

The database uses the May 2026 Local Government Directory export for state and
district codes. The archive contains snapshots through **31 May 2026**:

- State snapshot: `states.31May2026.csv` (36 state/UT rows)
- District snapshot: `districts.31May2026.csv` (784 district rows)
- [State archive](https://github.com/ramSeraph/opendata/releases/download/lgd-archive-extra1/states.May2026.7z)
- [District archive](https://github.com/ramSeraph/opendata/releases/download/lgd-archive-extra1/districts.May2026.7z)
- Archive manifest: <https://ramseraph.github.io/opendata/lgd/archives/listing_files.csv>
- Ministry of Panchayati Raj LGD overview: <https://panchayat.gov.in/en/lgd/>
- Open Government Data LGD catalog: <https://data.gov.in/catalog/local-government-directory-lgd>

The archive project describes the files as data collected from the Government
of India's LGD directory. LGD assigns a unique code to each location entity.
The importer joins district rows to the app's already seeded 36 states/UTs by
LGD state code, validates state names and state/UT type, then upserts districts
by district LGD code.

The May snapshot is the latest monthly state/district export available in the
public archive manifest at the time of this import. The OGD catalog reports
monthly updates, so refresh this snapshot when a newer LGD export is available.

## Institute places and campus links

`tooling/import_locations.py` creates an institute's main campus only when all
of these existing fields are present and consistent: `institutes.state`,
`institutes.district`, and `institutes.city`. The state and district must match
the imported LGD master. Generic summary locations such as `Various` and
`Online`, family summary rows, and non-listed/non-admitting entries are skipped.

The legacy institute table does not retain a location-specific source URL.
Therefore imported campus rows deliberately have `source_url = NULL` and
`verified_at = NULL`; the location fields are usable for filtering but must not
be displayed as separately verified. `places.kind` is `city` because the input
field is the legacy `city` field. `is_district_hq` remains false because the
source does not identify district headquarters. No district is inferred from a
city name.

The plan's former city names (for example, Bangalore → Bengaluru) are added to
`place_aliases` only when there is exactly one matching canonical place in the
database. Alias strings are stored lowercase. Alias targets are omitted when
the target city is missing or ambiguous.

## Unresolved locations

See [`location_review.csv`](location_review.csv). It lists physical institute
rows that could not be linked safely, along with the missing or conflicting
field and the institute website to use as a review starting point. It does not
include intentionally locationless summary, online, or excluded records.
