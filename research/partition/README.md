# Wave D partition of UGC's State Universities list

`ugc_state_universities_partition.csv` assigns every row of
`research/official_lists/ugc/ugc_state_universities.json` (523 rows, fetched 2026-10-02) to exactly one batch,
so batches prepared in parallel never claim the same university:

| batch | meaning |
|---|---|
| D1 | already loaded: NLUs and state law universities |
| D2 | state technical universities (name rule: technolog/technical/engineering/IT) |
| D3, D3b | already loaded from ICAR's list; D3b = UAS Mandya, not on ICAR's page |
| D4 | state health-science and AYUSH universities |
| D5 | state general universities (loaded state by state) |
| D6 | state sports, music/arts and women's universities |
| I1 | state open universities (G9, Wave I) |

The assignment is a name rule, reviewed by hand; a batch author who finds a row in the wrong batch moves it here
in the same commit.
