# CareerPath — Voice Agent + Data Schema Context

> **Purpose:** a pre-digested map so a new Claude session does NOT re-scan the repo.
> Read this first; open source files only for the exact function you are changing.
> **Verified against:** branch `feature/voice-structured-search` (app version `1.5.0+17`), 2026-09-30.
> **Keep fresh:** if you change anything listed here, update this file in the same commit (see §12).

---

## 1. What the app is

`career_path` — Flutter app (Android/iOS) that helps Indian students (post-10th/12th) explore
**Streams → career paths → books / institutes / job sectors**, plus a Gemini-powered **AI Guide**
(typed chat + realtime **voice conversation**). Ships in 11 UI locales (en, hi, bn, gu, kn, ml, mr, or, pa, ta, te).

- **Offline-first**: all career content is a bundled SQLite DB (`assets/data/career_path.db`, 6.7 MB, read-only).
- **No app backend for AI**: the phone talks directly to Google Gemini (REST + Live WebSocket).
- State mgmt: plain `StatefulWidget` + `ChangeNotifier`; manual DI from `lib/main.dart` (no Provider/Bloc — project rule).

> ⚠️ `CLAUDE.md` "Project Profile" is stale in places (says ngrok API + 23 Dart files). Reality:
> `ApiClient`/ngrok `ApiUrls.baseUrl` still exist but `main.dart` wires `LocalDataSource(LocalDatabase)`
> into `CareerDataService`; the app runs from the bundled DB. `lib/` has ~90 non-l10n Dart files.

---

## 2. Voice agent — architecture at a glance

```
 AI Guide tab (lib/screens/ai_chat_tab.dart)
   │  Talk button → _toggleVoice()
   ▼
 AiVoiceServices.createController()                    lib/services/ai_voice_services.dart
   ▼
 LiveVoiceController (ChangeNotifier, state machine)   lib/controllers/live_voice_controller.dart
   │ mic frames ─(24k→16k resample)─▶ GeminiLiveClient ─wss─▶ Gemini Live (BidiGenerateContent, v1alpha)
   │ ◀─ audio(24k PCM) / transcripts / toolCall / turnComplete / interrupted / goAway ─
   │
   ├─ toolCall ─▶ LiveVoiceTools.execute()             lib/services/live_voice_tools.dart
   │                 route_query → guardrails / app-help / follow-up shortcut / else hybrid retrieval → records
   │                 search_careers (fallback) + prefetch → keyword (LocalAiGroundingService) + semantic (SemanticIndexService)
   │                 format_answer → AiResponseParser.parse(draft)         (sections + Q&A)
   │
   ├─ PCM playback / recording ─▶ VoiceAssistantAudioBridge  packages/live_audio (native Kotlin/Swift)
   └─ callbacks onQuestion/onAnswer/onWelcome/onUnavailable/onEnded ─▶ AiChatController.addVoiceQuestion/addVoiceAnswer
```

Key design facts:
- **No backend in between.** API key is fetched at startup from a public JSON (`ApiUrls.geminiKeyConfig`, npoint.io)
  by `GeminiKeyService` and held **in memory only**. Sent as `x-goog-api-key` header on the WebSocket.
  (Prototype credential handling — flagged in the class doc; a real backend/proxy is a known gap.)
- **Model does the talking; the phone does the knowledge.** Gemini Live never sees the DB — it calls 3 tools and
  the app answers them from local data (grounded, no invention of fees/cut-offs/salaries).
- **Same guardrails as typed chat** (`AiGuardrails`) are applied to the voice transcript inside `route_query`.
- The spoken answer is mirrored into the chat list as messages with `fromVoice: true`.

## 3. Voice files — exact responsibilities

| File | Lines | Role |
|---|---|---|
| `lib/controllers/live_voice_controller.dart` | 502 | Session lifecycle + state machine (`LiveVoiceState`: off, connecting, listening, thinking, speaking, reconnecting). Mic pump (80 ms timer), playback queue, turn/idle/drain timers, reconnect + replay, held-speech logic. |
| `lib/services/gemini_live_client.dart` | 250 | WebSocket client. `connect(apiKey, setup)` waits for `setupComplete`. Sends `realtimeInput` audio(16 kHz)/text/audioStreamEnd and `toolResponse`. `parse()` turns frames into sealed `LiveEvent`s. |
| `lib/services/live_voice_prompts.dart` | 236 | `VoiceIntent` enum-strings, `systemInstruction()`, tool declarations, `welcome()` prompt, `setup()` payload. **Prompt engineering lives here.** |
| `lib/services/live_voice_tools.dart` | ~250 | `LiveVoiceTools` (executes tool calls), `VoiceTurn` (per-turn result), 3-turn `_memory`, canned answers. |
| `lib/services/ai_voice_services.dart` | 39 | Bundle (key svc, grounding, settings, preview) created once in `main.dart`; `createController()` factory. |
| `lib/services/voice_settings_service.dart` | 32 | SharedPreferences: voice name, interruptions, spoken answers. |
| `lib/services/voice_preview_service.dart` | 101 | TTS sample per voice via REST `generateContent` (model `gemini-3.1-flash-tts-preview`), cached in memory. |
| `lib/config/ai_provider_config.dart` | 82 | All model names, timeouts, sample rates, voice list (30 voices), grounding limits. |
| `lib/config/api_urls.dart` | 68 | `geminiLiveWebSocket`, `geminiGenerateContent(model)`, `geminiBatchEmbed(model)`, `geminiKeyConfig`. |
| `lib/screens/ai_chat_tab.dart` | ~2100 | UI: `_toggleVoice`, `_typeInstead`, `_onVoiceQuestion/_Answer/_Unavailable/_Ended`, `_VoicePanel` (strip), `_VoiceOrb`, `_liveBubbles`, `_VoiceSettingsSheet`. Voice code ≈ lines 331–480, 1470+. |
| `lib/controllers/ai_chat_controller.dart` | 241 | `addVoiceQuestion()`, `addVoiceAnswer()` (l.157–195) insert `fromVoice` messages. |
| `packages/live_audio/` | — | Local plugin. Dart: `lib/audio_bridge.dart` (`VoiceAssistantAudioBridge`). Native: `android/.../LiveAudioPlugin.kt`, `WebRtcAec3Processor.kt`; `ios/Classes/LiveAudioPlugin.swift`. 24 kHz PCM16 capture with AEC + noise suppression; streaming playback with position reporting; audio focus; keep-screen-awake. |
| `assets/data/ai_guide_help.txt` | 1.9 KB | App-help Q&A returned to the model for the `app_help` intent. |

Related non-voice (shared) pieces: `local_ai_grounding_service.dart` (retrieval), `guided_ai_chat_repository.dart` (typed chat),
`ai_guardrails.dart`, `ai_response_parser.dart`, `ai_language.dart`, `semantic_index_service.dart`, `institute_catalog_service.dart`.

## 4. Configuration constants (`AiProviderConfig`)

| Constant | Value | Notes |
|---|---|---|
| `liveModel` | `gemini-3.1-flash-live-preview` | override `--dart-define=GEMINI_LIVE_MODEL=` |
| `liveFallbackModel` / `liveFallbackAfterFailures` | `gemini-2.5-flash-native-audio-preview-09-2025` / 2 | after 2 consecutive `1011` closes with no student transcript in between, `LiveVoiceController` switches to this model for the rest of the app run (override `GEMINI_LIVE_FALLBACK_MODEL`) |
| `model` (typed chat) | `gemini-2.5-flash` | override `GEMINI_MODEL` |
| `voicePreviewModel` | `gemini-3.1-flash-tts-preview` | |
| `defaultVoice` | `Leda` | 30 prebuilt voices in `voices` |
| `liveTemperature` | 0.7 | |
| `liveInputSampleRate` | 16000 | mic is captured at 24 kHz then downsampled 3:2 |
| `liveConnectTimeout` / `liveTurnTimeout` / `liveIdleTimeout` | 20 s / 20 s / 60 s | |
| `liveMemoryTurns` | 3 | turns replayed on reconnect |
| `maxContextCharacters` / `maxGroundingNodes` / `maxDetailedNodes` | 18000 / 14 / 5 | grounding limits |
| `maxGroundingInstitutes` / `maxNarrowedInstitutes` | 4 / 8 | colleges in grounding; 8 when a place, level or course narrows the question |
| embeddings | `gemini-embedding-001`, 768 dims, cutoff 0.6, topK 4, batch 90 / 60 s pause | |

Session `setup` (in `LiveVoicePrompts.setup`): `responseModalities: [AUDIO]`, input+output transcription on,
`activityHandling` = `START_OF_ACTIVITY_INTERRUPTS` (barge-in) or `NO_INTERRUPTION`, VAD start/end sensitivity LOW,
prefixPadding 400 ms, silence 600 ms, tools = the 3 declarations below, system instruction from `systemInstruction()`.

## 5. One voice turn, step by step

1. User taps **Talk** → `_toggleVoice()` → `LiveVoiceController.start(voiceName, interruptions, playAudio, welcomeGreeting?, welcomeStarters)`.
   Requests audio focus (`continuous`), keeps screen awake, connects, starts recorder, 80 ms mic timer, state → `listening`, arms 60 s idle timer.
2. **Spoken welcome, by name** — once per tab visit, only when the chat is empty: `sendText('__CAREERPATH_WELCOME__')`; the model says
   `ai_voiceWelcomeNamed` ("Hi {name}! I am your CareerPath AI Guide.", name from the profile via `AiChatTab.studentName`; `ai_voiceWelcome`
   without a name), reads the starter questions, asks "What would you like to explore?" — **no tools** (tool calls answered
   `{error: no_tools_during_welcome}`). `onWelcome` adds the transcript to chat.
3. Student speaks → `LiveInputTranscript` chunks accumulate in `_heard`; `_beginTurn()` resets `VoiceTurn`.
4. Model calls **`route_query`** (mandatory first tool): args `query, intent, standalone_query, is_follow_up, requires_search, input_language`.
   `LiveVoiceTools._route` sets `turn.*`, then returns one of:
   - `direct_response {summary}` — for safety/prompt-injection/abusive/`unsafe`/unsupported-language/`off_topic`/`small_talk` (guardrail order: safety → injection → abusive/offensive → unsafe → unsupported lang → off_topic → small_talk)
   - `app_help_context` — full `ai_guide_help.txt` text (intent `app_help`)
   - `context_only: true` — follow-up needing no new search
   - **default: `records` + `record_count` + `next_step`** — retrieval runs *inside* `route_query` (hybrid keyword + semantic, see §6), so there is **no separate `search_careers` model round trip**. Controller sets `_holdSpeech = true` when a response contains `records`.
   While the student is still speaking, the controller debounces (450 ms) `LiveInputTranscript` and calls `tools.prefetch(_heard)` → speculative semantic lookup (≥3 words, max 3/turn, reused by `_retrieve` if it covered the final question within 3 words).
5. **`search_careers(query)`** — now only a *fallback* (declared as such in the prompt). Same `_records()` path; follow-ups get the previous question prepended.
6. Model must call **`format_answer(draft)`** — `<Title>…</Title>` sections + `Questions:`/`Answers:` numbered pairs.
   `AiResponseParser.parse` → `turn.sections`, `turn.suggestions` (≤3). Controller drops any speech held before this (`_discardHeldSpeech`).
   If the model never calls it, `_releaseHeldSpeech()` plays the held draft at `turnComplete`.
7. Model speaks the direct answer (2–4 sentences). `LiveAudio` (24 kHz PCM) → `_play()` (generation-guarded queue → `startPlayer(communication)` → `writePlayer`). `LiveOutputTranscript` builds `_spoken`.
8. `LiveTurnComplete` → `_finishTurn()`: `tools.remember(q, a)`, `onAnswer(VoiceAnswer)`, `_beginTurn()`, drain-poll playback (200 ms, max 300 checks) then state → `listening`.
   **Voice UI (ai_chat_tab.dart):** `_VoicePanel` replaces the composer at the **same size** (`AnimatedSwitcher` + `SizeTransition`):
   [keyboard button → end voice + focus composer] [pill: small rotating `_VoiceOrb` + status label] [X to end, in Send's spot]. The pill covers
   the Talk button's spot so a double-tap on Talk can't end voice. The strip shows **no text**: the turn in progress streams into the chat above as
   live bubbles (`_liveBubbles`: `heardTranscript` as a user bubble until `onQuestion` records it, then `liveTranscript` as the guide's bubble, with
   `_ThinkingIndicator` while `thinking`). Every voice turn is kept in the chat: `onQuestion` → `addVoiceQuestion`, `onAnswer` → `addVoiceAnswer`
   (≤3 source chips; `noRecordsFound` → insufficient-data status with Explore fallback). No end-of-call summary.
   **Barge-in gate** (`_gate` in the controller): while `speaking`, mic frames are dropped unless ≥ `liveBargeInFrames` (3 × 80 ms) consecutive frames reach
   `liveBargeInLevel` (0.6); then held frames are flushed and the gate stays open for the turn. Input transcripts during speech are ignored until it opens.
   This stops the guide's own voice (speaker echo) from triggering `interrupted`, which used to cut answers off after a few words.

**Failure/edge handling** (all in the controller):
- `LiveInterrupted` → stop playback, finish turn, back to listening.
- `LiveGoAway` / `LiveClosed` → `_reconnect()` with `tools.sessionContext()` ("RECENT CONVERSATION: …") injected into the system instruction.
- Turn timeout (20 s, no audio/text after a tool response): first time → reconnect **and replay** `_lastQuestion`; second time → `onUnavailable`.
- Idle 60 s while listening → `stop()` + `onEnded('idle')`. Reconnect failure → `onEnded('connection_lost')`.
- `interruptions == false` → mic frames and transcripts are dropped while `speaking`.
- `interruptions == true` → **echo-aware barge-in** (`LiveVoiceController._gate`, tuning in `AiProviderConfig.liveBargeIn*`).
  The mic also hears the guide through the speaker (AEC removes most, none on the iOS simulator) and Gemini treats any voice as the student
  cutting in → the guide interrupted itself and answered its own words in a loop. While `speaking`, mic audio is **held back**: the first
  ~0.5 s only learns the echo level; the gate opens when the mic is ≥1.8× the loudest echo of the last ~1.6 s for ~250 ms, then sends the
  held ~0.4 s pre-roll + live audio so Gemini interrupts. If Gemini hasn't interrupted within ~1.6 s it was a false alarm → gate closes.
  Transcripts while the gate is closed are ignored.
  **Second guard:** right after a barge-in, if `route_query.query` is ≥80% the guide's own recent words (`isOwnEcho`, Unicode incl.
  Devanagari marks), the turn is an echo: route_query replies `{ignored: true}` (`LiveVoicePrompts.echoIgnored`) and the turn's audio/text
  never play or reach chat. Do **not** replace this with a fixed loudness threshold (tried 2026-09-30: needed shouting) or with an ungated
  mic (loops). Verified on the simulator with `say` as the student: no self-loop; interruption heard.
  **After Gemini has sent the whole answer** (`LiveTurnComplete` while the phone still plays the queue — Gemini sends audio faster than
  real time) Gemini has nothing to interrupt and never sends `LiveInterrupted`. The controller then stops playback itself
  (`_interruptLocally`) on the first input transcript with a word the guide did not just say (`isStudentSpeech`); in gated mode that
  barge-in waits up to `liveBargeInTranscriptConfirmFrames` (~3.2 s) for the transcript instead of closing at ~1.6 s. The good-AEC echo
  probe runs once at the first quiet frame from ~0.8 s (not exactly frame 10, which a loud frame used to skip).
  **Automatic fallback:** the 3.1 preview is intermittently broken on Google's side (2026-09-30: fine at 17:35, `1011` at 18:22, fine at 18:30), so `1011` closes are counted and the controller falls back to the 2.5 native-audio model (heard the same test audio correctly).
  Debugging "not listening": first check Gemini itself — on 2026-09-30 `gemini-3.1-flash-live-preview` briefly returned no input
  transcripts for any audio and closed sessions with `1011 Internal error encountered` (app and mic were fine); a desktop probe that sends
  a `say`-recorded WAV over the same WebSocket setup isolates this in a minute.
- `playAudio == false` (Spoken answers off) → transcripts only.

### Tool contract (declared to Gemini)
| Tool | Args (all required) | Returns |
|---|---|---|
| `route_query` | `query`, `intent` ∈ `VoiceIntent.all`, `standalone_query`, `search_keywords` (1-5 English keywords — **used for retrieval**, same as typed chat's classifier `search_query`; the prompt makes both keep every named place, course and level, and on a follow-up like "and in Jodhpur?" keep course/level and swap only the place), `is_follow_up`, `requires_search`, `input_language` ∈ {english, hindi, bengali, punjabi, gujarati, odia, tamil, telugu, kannada, malayalam, unsupported} | see step 4 |
| `search_careers` | `query` (English keywords; transliterate Hindi/regional names, include state) | records text |
| `format_answer` | `draft` | `{status:'formatted'}` or `{error:'empty_draft'}` |

`VoiceIntent.all`: offensive, unsafe, app_help, overview, career, question, follow_up, clarification, advice, small_talk, off_topic.
Unknown tool → `{error:'unknown_tool'}`; exception → `{error:'tool_failed'}` (logged by runtime type only).

## 6. Retrieval / grounding (what `search_careers` actually does)

`LocalAiGroundingService.retrieve({query, streamId})` (`lib/services/local_ai_grounding_service.dart`):
Voice and typed chat now share one hybrid path: `AiGroundingContext.merge(keyword, semantic)` (keyword first, semantic de-duplicated by `sourceId`).
Voice: `LiveVoiceTools._retrieve` = `LocalAiGroundingService.retrieve` **+** `extraGrounding` (`SemanticIndexService.search`, injected via `AiVoiceServices.extraGrounding` from `main.dart`). A semantic failure silently falls back to keyword-only.
Keyword step details:
1. `CareerDataService.ensureInitialized()` — all 380 nodes are eager-loaded into memory from SQLite; catalog loaded.
   **Query normalisation (shared by voice + typed chat):** `SearchAliases.expand` → `SearchSpellCorrector.correctQuery` → `expand` again
   (so a misspelled alias like "docter" still expands). Both are built once in `warmUp()` (called from `main.dart`), the corrector in a
   background isolate (`compute`). If an asset fails to load, that step is skipped and words match as written.
   - **Aliases** (`search_aliases.dart`, asset `assets/data/search_aliases.json`, ~480 keys): adds expansions after the student's words
     (`engg`→engineering, `mbbs`→medical, `bhu`→Banaras Hindu University, `vakil`→lawyer, `up`→Uttar Pradesh). Longest key wins
     ("sarkari naukri" as a phrase). **Never hand-edit the JSON:** edit `tooling/search_aliases.txt`, run `python3 tooling/build_search_aliases.py`
     (merges DB-derived "Name (ABBR)" pairs whose letters spell the name + institute initials used on their own in the same city; drops
     everyday-word keys like it/me/see; warns on expansions that match no data word). Re-run after any DB change.
   - **Spelling** (`search_spell_corrector.dart`): snaps unknown words ≥4 letters to the closest word in names (careers, colleges,
     places, courses); edit distance in half units (vowel / c-k / s-z / v-w changes cost half); first letter may change only in words ≥6.
     Real words are never touched: data words, alias keys, a Hinglish/modern list, and `assets/data/english_words.txt`
     (public-domain Webster's web2, 174k words, built by `tooling/build_english_wordlist.py`; plurals/-ed/-ing handled).
   - `searchFillerWords` (Hinglish hai/ke/se/kya/kaise…) are skipped in matching — node matching is **substring**, so "hai" would hit "blockc**hai**n".
2. Tokenise query (lowercase `[a-z0-9]+`, len>1, minus stop-words and fillers). Score each node: exact name 12, name contains 6, intro contains 2.
   Lowercase/compact node text is cached per node (`Expando`).
   Top **14** nodes + all category nodes of any stream named in the query (or the active `streamId` when career-intent words are present).
   Fallback: if nothing matched but career-intent words exist → stream categories.
3. `InstituteCatalogService.search(query, limit 4)` and, if the query asks about rankings, `rankings(query)` (NIRF).
   A named **state, city or district filters** colleges (else "medical college, Lucknow" outranks Bhopal ones for "MBBS in Bhopal").
   Matching = a word *starts with* the token (dots ignored); per-record search text is prepared once (`Expando`) and matched with `contains(' token')`.
   `search` wraps `find(query, limit)`, which also returns the matched courses per institute and the total institutes/courses matched.
   **Every** course is searched (name + specialization). A level word (UG/PG/bachelor/masters/PhD/diploma/certificate/integrated,
   `course_levels.dart` `CourseLevels`) keeps only institutes with a course at that level; stored `level` strings are reduced by
   `CourseLevels.ofCourse` (mixed ones like "postgraduate_diploma" name several). With a place named, colleges that match none of the
   other (subject) words are dropped once any college does — a place word inside a name ("Delhi School of…") is not a subject.
   A state-less record still matches a state whose name is in its city (New Delhi → Delhi).
   `describe(record, matched:)` lists "Matching courses (n)" first, then "Other courses: n".
4. For up to **5 leaf** nodes: `getLeafDetails` (cached per node — data is read-only) → books (≤12), institutes (≤12), job sectors (≤12).
   **Books directly:** when the *original* question has a book word (book/books/kitab/kitaben/pustak/textbook/author…, checked before
   spelling correction), `BookCatalogService.search` (all 1 111 books, loaded once via `LocalDatabase.getBookCatalog`) scores title 10,
   author or linked career-path name 6, description 2 (min 6; tokens <3 letters must be whole words). Up to 6 books →
   `SOURCE book:<id>` blocks; up to 3 `book` source chips whose `exploreNodeId` is the book's first career path.
5. Output text `CAREERPATH EXPLORE DATA…` with `SOURCE nirf_rankings`, `SOURCE institute:<id>`, `SOURCE career_node:<id>` blocks, truncated to 18 000 chars;
   `sources` = `AiChatSource(sourceId, sourceType: ranking|institute|career_node, title, exploreNodeId?)`.
   The text opens with `MATCH SUMMARY:` ("10 institutes in Jaipur match, with 10 matching courses; showing 8." / "N books match; showing K.")
   so the guide can say how many matched. When a named place yields no institute, a `COVERAGE:` note says so ("CareerPath has no
   institutes in Goa yet. It lists institutes in: Rajasthan (123), …" — states computed from the catalog — or "lists N in Indore, but
   none offer what was asked") and no college from elsewhere is cited.
   Empty → `AiGroundingContext(text: <coverage note or ''>, sources:[])` → `noRecordsFound`; voice then sends
   `NO RECORDS FOUND\n<note>`. `merge` keeps a keyword-side note even when only semantic search found records.

Semantic search keeps institute hits inside a place the query names: `SemanticIndexService(catalog:)` asks
`InstituteCatalogService.idsInPlace(query)` (same state/city/district rules as `find`), looks 3× deeper (top 12) and keeps the top 4
that pass; career-path hits always pass.
Semantic search only works once `SemanticIndexService` has vectors (built in background after first launch, paced to the embedding quota, persisted to `ai_semantic_index.*`).
Before that, both typed chat and voice degrade to keyword-only. Keyword tokens are `[a-z0-9]` so **non-English transcripts only match via the semantic part or the model's English `search_keywords`**.

Measured on the real data (desktop debug, 2026-09-30): retrieve avg **2.7 ms** (was 8.5), warm-up 144 ms once in background.
20 realistic misspelled/abbreviated/Hinglish questions: **20/20** find the right records (8/20 before spelling + aliases).

## 7. Data layer & bootstrapping (`lib/main.dart`)

Order of construction: `SharedPreferences` → repositories/services (bookmarks, exploration, recently viewed, rate prompt) →
`LocalDatabase().init()` (copies asset DB to `getDatabasesPath()/career_path.db` **on every launch**, opens `readOnly`) →
`CareerDataService(LocalDataSource(localDb))` → `GeminiKeyService` (+ background `preload()`) →
`InstituteCatalogService(localDb.getInstituteCatalog)` → `LocalAiGroundingService(careerData, catalog:, books: BookCatalogService(localDb.getBookCatalog))` →
`SemanticIndexService` (background build, paced to quota) → `GuidedAiChatRepository` → `AiGeminiJson`/`AiGuideExtras` →
**`AiVoiceServices`** → `CareerPathApp(...)` which passes `aiVoiceServices` down to the AI Guide tab.

`DataSource` interface (`lib/services/data_source.dart`) has two impls: `ApiClient` (legacy REST, 30-min cache) and `LocalDataSource` (active).
`LocalDatabase` query methods: `getStreams`, `getStreamRootNodes(streamId)`, `getNodeChildren(nodeId)`, `getNodeDetails(nodeId)`,
`getInstituteCatalog()` (5 parallel queries, joined in Dart), `getAllNodes()`, private `_buildChildMap`.

## 8. DATABASE SCHEMA — `assets/data/career_path.db` (SQLite, read-only in app)

Row counts as of this commit: streams 3 · career_nodes 380 · books 1 111 · institutes 869 · job_sectors 476 ·
institute_courses 8 376 · node_books 2 751 · node_institutes 5 958 · node_job_sectors 1 375 · course_career_nodes 9 495
· institute_categories 409 · institute_rankings 350 · institution_groups 13 · families 114 · institute_classification
349 · institute_verifications 285 · institute_accreditations 0 · countries 1 · states 36 · districts 0 · places 0 ·
place_aliases 0 · campuses 0 · domains 27 · domain_nodes 90 · domain_tiers 276 · institute_domain_tiers 424.

### 8.1 Tables (DDL, condensed from `sqlite3 .schema`)

```sql
CREATE TABLE streams (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  slug TEXT UNIQUE NOT NULL,            -- science | commerce | art
  name TEXT NOT NULL,
  intro TEXT
);

CREATE TABLE career_nodes (             -- self-referencing tree, one tree per stream
  id INTEGER PRIMARY KEY,               -- NOT autoincrement; explicit ids
  slug TEXT UNIQUE NOT NULL,
  stream_id INTEGER NOT NULL REFERENCES streams(id) ON DELETE CASCADE,
  parent_id INTEGER REFERENCES career_nodes(id) ON DELETE CASCADE,   -- NULL = root
  name TEXT NOT NULL,
  intro TEXT
);
-- leaf = node with no children (derived, there is no is_leaf column)

CREATE TABLE books (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL, author TEXT, url TEXT, description TEXT
);                                       -- UNIQUE INDEX idx_books_title(title)

CREATE TABLE job_sectors (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL, description TEXT
);                                       -- UNIQUE INDEX idx_job_sectors_name(name)

CREATE TABLE institutes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL, city TEXT, website TEXT, description TEXT,
  source_id TEXT,                        -- external id (e.g. NIRF/verification run); UNIQUE where NOT NULL
  district TEXT, state TEXT,
  institution_type TEXT,                 -- see §8.3
  institution_type_source_url TEXT,
  institution_type_confidence TEXT,      -- high | medium | NULL
  institution_type_notes TEXT,
  institution_type_verified_at TEXT
);                                       -- UNIQUE idx_institutes_name(name); idx_institutes_source_id;
                                         -- idx_institutes_location(state,district,city); idx_institutes_type(institution_type)

CREATE TABLE institute_courses (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  source_id TEXT UNIQUE NOT NULL,
  institute_id INTEGER NOT NULL REFERENCES institutes(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  level TEXT NOT NULL,                   -- free text, MESSY (see §8.3)
  credential TEXT, specialization TEXT, duration TEXT,
  mode TEXT,                             -- free text, MESSY
  eligibility TEXT,
  official_course_url TEXT NOT NULL,
  verification_status TEXT NOT NULL,     -- verified | verified_programme_family
  mapping_gap TEXT
);                                       -- idx_institute_courses_institute(institute_id)

-- ── junction tables ──
CREATE TABLE node_books        (node_id INT NOT NULL → career_nodes(id) CASCADE, book_id INT NOT NULL → books(id) CASCADE,           PRIMARY KEY (node_id, book_id));
CREATE TABLE node_institutes   (node_id INT NOT NULL → career_nodes(id) CASCADE, institute_id INT NOT NULL → institutes(id) CASCADE, PRIMARY KEY (node_id, institute_id));
CREATE TABLE node_job_sectors  (node_id INT NOT NULL → career_nodes(id) CASCADE, job_sector_id INT NOT NULL → job_sectors(id) CASCADE, PRIMARY KEY (node_id, job_sector_id));

CREATE TABLE course_career_nodes (       -- links a course to the career tree
  course_id INTEGER NOT NULL REFERENCES institute_courses(id) ON DELETE CASCADE,
  node_id   INTEGER NOT NULL REFERENCES career_nodes(id)      ON DELETE CASCADE,
  relation TEXT NOT NULL,                -- MESSY (direct_discipline / direct discipline / direct-discipline / closest_specialization / nearest_parent …)
  confidence TEXT NOT NULL,              -- high | medium
  mapping_status TEXT NOT NULL,          -- e.g. reviewed_against_local_tree
  PRIMARY KEY (course_id, node_id)
);                                       -- idx_course_career_nodes_node(node_id)

CREATE TABLE institute_categories (
  institute_id INTEGER NOT NULL REFERENCES institutes(id) ON DELETE CASCADE,
  category TEXT NOT NULL,
  PRIMARY KEY (institute_id, category)
);

CREATE TABLE institute_rankings (
  institute_id INTEGER NOT NULL REFERENCES institutes(id) ON DELETE CASCADE,
  system TEXT NOT NULL,                  -- only 'NIRF' today
  year INTEGER NOT NULL,                 -- only 2025 today
  category TEXT NOT NULL,                -- Overall, Engineering, Management, Pharmacy, Medical, Law, University, …
  nirf_institute_id TEXT,
  rank INTEGER, rank_band TEXT, score REAL,
  source_url TEXT NOT NULL,
  PRIMARY KEY (institute_id, system, year, category)
);                                       -- idx_institute_rankings_order(year,category,rank,rank_band)

-- ── institution taxonomy (tooling/institution_taxonomy.py; NOT read by the app yet) ──
-- Plan: docs/plans/INSTITUTION_HIERARCHY_PLAN.md. Additive; existing tables unchanged.
institution_groups (code PK: G1..G9, G10a, G10b, G11, X; name, description, sort_order)
families (slug PK: iit, nit, aiims, nlu, iti, …; name, group_code → institution_groups,
          regulators, official_list_url, national_count, national_count_as_of)  -- every Indian family, even with 0 rows
institute_classification (institute_id PK → institutes; group_code; family_slug → families;
          ownership central_govt|state_govt|govt_aided|private|trust|ppp; statutory_basis; regulators;
          admits_students; parent_institute_id → institutes (department/centre rows); is_family_record ("IITs");
          listed; ugc_verified 1|0 (PRIVATE only, CHECK-enforced; NULL = government); ugc_* source fields;
          confidence high|medium|low; source_url; verified_at; notes)
institute_verifications (institute_id, authority, list_name PK; list_url, list_as_of, reference_id, verified_at)
institute_accreditations (institute_id, body NAAC|NBA, programme PK; grade, status, valid_until, source_url)
countries (code PK 'IN') → states (code PK ISO 3166-2 'IN-RJ'; lgd_code; name; kind state|ut; zone)
  → districts (lgd_code PK) → places (city/town) → place_aliases; campuses (institute_id, place_id, is_main)

-- ── domain tiers (tooling/domain_tiers.py; NOT read by the app yet) ──
domains (slug PK: engineering, medical, law, ca_cma_cs … 27; name; route_type degree|professional_body|exam|mixed;
         regulators; entrance_exams; sort_order)
domain_nodes (node_id PK → career_nodes; domain_slug)          -- 89 career nodes; descendants inherit the domain
domain_tiers (domain_slug, tier PK; label; group_codes; family_slugs)  -- ladder: apex families (NLUs in Law, ICAI in
                                                                    -- CA, NSD/Kalakshetra in arts) then G1 → G9
institute_domain_tiers (institute_id, domain_slug PK; tier)    -- DERIVED, rebuilt by every batch load: one row per
                                                                    -- classified top-level institute per domain it is
                                                                    -- linked to (department links count for the parent)
```

### 8.2 ER diagram

```
streams 1───∞ career_nodes ∞───1 career_nodes (parent_id, self-tree; roots have parent_id NULL)
                  │
      ┌───────────┼───────────────┬────────────────────┐
  node_books  node_institutes  node_job_sectors  course_career_nodes
      │            │                 │                    │
    books     institutes        job_sectors       institute_courses ∞───1 institutes
                  │                                                         │
                  ├── institute_categories (∞)                              │
                  ├── institute_rankings   (∞, PK institute+system+year+category)
                  ├── institute_classification (0..1) ── families ── institution_groups
                  ├── institute_verifications (∞) · institute_accreditations (∞)
                  └── campuses (∞) ── places ── districts ── states ── countries
```

### 8.3 Shape of the data (useful when writing queries / prompts)

- **Streams:** 1 science, 2 commerce, 3 art.
- **Tree depth:** L1 = 17 roots, L2 = 84, L3 = 241, L4 = 38 → **275 leaves**, 17 root nodes.
  Books/institutes/sectors hang off nodes (mostly leaves) via junction tables.
- **institutes.state:** filled for 844 of 869 (34 states/UTs; Andaman and Nicobar and Lakshadweep still have none; Rajasthan 126, Maharashtra 104, Uttar Pradesh 92, Madhya Pradesh 86, Delhi 77, Tamil Nadu 55, …). Only city "Various" (24) and "Online" (1) stay NULL. Courses exist only for the researched
  Rajasthan/MP/UP institutes. Hand-added institutes had a city but no state; `tooling/fill_institute_states.py` fills it from the city
  (curated `CITY_STATES`; add a row when a new city appears). **districts** are still NULL for those rows — never guessed.
- **institutes.institution_type:** ~119 NULL. Values include government_college, specialized, state_university, central_institute,
  iit, iim, nit, iiit, medical, law, agriculture, central_university, deemed_university, private_university, other, …
- **institute_courses.level / mode / relation:** free-text with **inconsistent casing & spelling**
  (`Undergraduate`/`UG`/`Under Graduate`, `not_stated`/`Not stated`/`not stated`, `direct_discipline`/`direct-discipline`…).
  **Always normalise (lower + collapse `_`/`-`/space) before comparing.** `mode` is mostly "not stated".
- **Name misspellings are fixed in the asset** ("Psycology", "Enginneering", a Cyrillic "у" in "Therapу", "M.A.Economics"…)
  by `tooling/fix_data_spellings.py` (80 values, 56 words). The source websites keep them, so the importer re-applies it.
  Look-alike real names stay as they are: Kannur, Lovely Professional, Bhupal Nobles', Narsee Monjee, Sanskriti.
  `SearchSpellCorrector` trusts every data word as spelled.
- **institute_categories:** ~35 distinct labels (College 92, Engineering 63, Management 63, Overall 61, Pharmacy 28, Law 23, …).
- **institute_rankings:** 350 rows, NIRF 2025 only (incl. Research, Innovation, SDG Institutions). `rank` may be NULL with
  `rank_band` set (e.g. IIT Goa Engineering 101-150). Batch loads replace an institute's rows for the snapshot year.
- **Taxonomy coverage (Wave A, batches A1–A5b, done — every G1 family):** all 23 IITs + IISc (A1), all 22 IIMs (A2, incl. IIM Guwahati, added
  to the IIM Act in 2025, no NIRF rank, website NULL), all 23 AIIMS + JIPMER, PGIMER, NIMHANS (A3), the 7 IISERs,
  NISER and ISI (A4) the 7 NIPERs and 3 SPAs (A5a) and the 5 NIDs, 2 NIFTEMs, ITRA Jamnagar, NFSU (with its LNJN NICFS Delhi campus
  as a child row), RRU and Kalakshetra (A5b) are classified G1 (AIIA New Delhi, loaded with A5b, is G3: an
  autonomous Ministry of Ayush institute, not an INI), and Wave B has started: the 31 NITs and IIEST Shibpur (B1, all NIRF-ranked) and the
  25 IIITs (B2: 5 under the IIIT Act 2014, 20 PPP IIITs with `ownership = ppp`) are classified G2 (NITs ranked by NIRF in Architecture also link to B.Arch); Wave C has started with
  the 57 central universities on UGC's list (C1, G3; IGNOU is G9; three Sanskrit and three agricultural central
  universities have their own families; universities link only to the career nodes their NIRF categories show) and C2: one row per
  campus for the 20 NIFT and 12 FDDI campuses (Acts of 2006 / 2017, but G3 as the plan lists them) and the 6 IIMC campuses, plus NSD, FTII and
  SRFTI (family `national_arts_film`; FTII, SRFTI and IIMC are government deemed universities since 2024–25, still G3); none is in
  NIRF; "NIFT (all campuses)" is the family record; C3: the 21 central IHMs on NCHMCT's list plus NCHM-IH Noida (family
  `central_ihm`) and IITTM's 5 degree centres (Gwalior, Bhubaneswar, Noida, Nellore, Goa; Bodh Gaya and Shillong camps not loaded),
  none in NIRF. Each has a verification row. AIIMS Darbhanga, Rewari and Awantipora have `admits_students = 0`,
  `confidence = medium` (no MBBS intake in the latest official status read, Lok Sabha 2022 — re-check); PGIMER and
  NIMHANS are not linked to MBBS (no MBBS course). 55
  department/centre rows ("IIT Bombay (Civil)", "IIM Lucknow - PGP-SM" which stays in Noida, "AIIMS Nursing College") have
  `parent_institute_id`; "IITs", "IITs (Data Science programs)", "IITs (Statistics Dept)", "IIM (MBA Marketing)",
  "IIM A/B/C (MBA Finance)", "AIIMS (All Campuses)", "NIFT (all campuses)" are `is_family_record` rows. Cities follow NIRF ("Bengaluru", Bodh Gaya → "Gaya",
  Ropar → "Rupnagar"). All other institutes are not classified yet. IIT/IIM/medical short forms (iitkgp, iima, pgimer, nimhans …) are
  hand-written in `tooling/search_aliases.txt`, because official renames drop the "(IIMA)"-style names they were
  derived from.
  Tiers are never a quality score (only group + family); they inherit any noise in `node_institutes` (e.g. IISc is
  linked to an AYUSH career leaf, so it gets an AYUSH tier). Batch-inserted institutes have `source_id` NULL (source_id still means "state research import").

### 8.4 How the app maps DB → Dart

| DB | Dart | Notes |
|---|---|---|
| `streams` (+ root ids) | `StreamModel` (`lib/models/stream_model.dart`) | ids become **strings** in models (`stream.id`, `node.id` are `String`) |
| `career_nodes` | `CareerNode` (`career_node.dart`) | `isLeaf`, child ids computed in `LocalDatabase` |
| `books`, `institutes`, `job_sectors` (+junctions) | `Book`, `Institute`, `JobSector`, aggregated in `LeafDetails` (`leaf_details.dart`) | via `getNodeDetails` |
| `books` + `node_books` + `career_nodes` | `BookRecord` (`book_record.dart`: `Book` + `nodeIds` slugs + `nodeNames`) | `getBookCatalog`, loaded whole by `BookCatalogService` |
| institutes + courses + rankings + categories | `InstituteRecord`, `InstituteCourse`, `InstituteRanking` (`institute_catalog.dart`) | loaded whole into memory by `InstituteCatalogService.ensureLoaded()` |
| — | `AiChatMessage`, `AiChatSource`, `AiAnswerSection`, `AiChatRequest/Response` (`ai_chat.dart`) | chat models; **chat is in-memory only, never persisted** |

### 8.5 Non-SQLite local storage

| Store | Key / file | Owner |
|---|---|---|
| SharedPreferences | `ai_voice_name`, `ai_voice_interruptions`, `ai_voice_spoken_answers` | `VoiceSettingsService` |
| SharedPreferences | `ai_answer_feedback` | `AiFeedbackService` |
| SharedPreferences | `ai_trending_questions`, `ai_trending_date` | `AiTrendingService` |
| SharedPreferences | `bookmarked_nodes`, `recently_viewed_nodes`, `visited_nodes` | bookmark / recently-viewed / exploration repos |
| SharedPreferences | `locale_code`, `theme_mode`, `onboarding_seen` | locale / theme / onboarding |
| SharedPreferences | `rate_session_count`, `rate_first_session_date`, `rate_dont_ask_again` | `RatePromptRepository` |
| SharedPreferences | `profile_name`, `profile_stream` | `ProfileRepository` |
| Files in app-support dir | `ai_semantic_index.json` + `ai_semantic_index.bin` (768-d Float32 vectors, hash-keyed) | `SemanticIndexService` |
| In-memory only | Gemini API key; voice preview audio cache; conversation memory (3 turns); chat messages | — |

> There is **no** server-side or persisted store for voice conversations, transcripts or analytics of content.
> Analytics = Firebase Analytics events via `AnalyticsService` (voice: `ai_chat_voice_started`, `ai_chat_voice_ended`).

### 8.6 Where the DB comes from (only touch when changing data)
Built offline by Python in `tooling/` (`import_verified_institutions.py`, `enrich_institution_types.py`,
`backfill_institution_types.py`, `discover_nirf_state_inventory.py`, `college_agents/`, `college_batches/`) from research outputs in `research/`.
`fix_data_spellings.py` and `fill_institute_states.py` run at the end of every import; after any other script that writes names, run it with no arguments.
Official-list batches: `nirf_rankings.py` snapshots NIRF into `research/official_lists/nirf/`, and
`load_family_batch.py research/batches/<batch>.json` loads one family batch (A1 = IITs + IISc, A2 = IIMs, A3 = AIIMS + JIPMER/PGIMER/NIMHANS, A4 = IISERs + NISER + ISI, A5a = NIPERs + SPAs, A5b = NIDs, NIFTEMs, ITRA, NFSU, RRU, Kalakshetra + AIIA, B1 = NITs + IIEST, B2 = IIITs, C1 = central universities) in one transaction;
the official lists it cites live in `research/official_lists/`. Then run the two scripts above and `build_search_aliases.py`.
The app **overwrites its on-device copy from the asset on every start** → shipping a new `.db` asset is the only way to change data;
bump the version in `pubspec.yaml` when you do. Schema changes require matching edits in `LocalDatabase` queries + models + tests.

## 9. Tests covering the voice path (all under `test/`)

| Test | Covers |
|---|---|
| `controllers/live_voice_controller_test.dart` | 24k→16k downsample; one question + one answer per turn; premature draft dropped |
| `services/live_voice_tools_test.dart` | route→search→format flow; guardrails on transcripts; off-topic/unsupported/app-help; no-records flag; memory→reconnect context; `setup()` uses configured model/interruptions |
| `services/gemini_live_client_test.dart` | frame parsing (audio, transcripts, turnComplete, setup, toolCall, interrupted) |
| `services/voice_settings_service_test.dart`, `voice_preview_service_test.dart` | prefs defaults/unknown voice; TTS request/decoding/HTTP errors |
| `screens/ai_chat_tab_test.dart` (1 002 lines) | chat tab incl. voice UI + source summary |
| `services/search_spell_corrector_test.dart`, `search_aliases_test.dart` | corrections, protected words, bundled dictionary/alias sanity |
| Also relevant | `local_ai_grounding_service_test.dart` (misspellings, aliases, fillers, leaf cache), `institute_catalog_service_test.dart` (word-start matching, city filter), `ai_response_parser_test.dart`, `ai_guardrails_test.dart` |

Fakes: the controller accepts injected `client` (`GeminiLiveClient`) and `audio` (`VoiceAssistantAudioBridge`) — use those to test without network/native.

## 10. Platform notes
- Android: `RECORD_AUDIO` permission. iOS: `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription` in `ios/Runner/Info.plist`.
- `ai_http_client_factory{,_io,_stub}.dart` build the `HttpClient`/`http.Client` (a debug CA cert from `assets/certificates` is added to the trust context — see `ai_http_client_factory_io.dart`); `createIoFactory()` feeds the Live WebSocket `customClient`.
- Typed-chat voice input (mic icon in composer) uses `speech_to_text` (`speech_recognition_service.dart`); read-aloud uses `flutter_tts` (`text_to_speech_service.dart`). These are separate from the Live voice path.

## 11. Status, known gaps, gotchas
- `FUTURE_PLAN.md` §11 — voice is "in progress": missing transcript revealed in step with audio, rotating landing titles, animated hint text, Lottie loaders, auto-start voice after welcome.
- Semantic search quota: the shared key allows ~100 embedded items/min; voice prefetch is capped at 3 query embeddings per turn for that reason.
- API key from a public URL, held in memory: prototype-grade; do not log or persist it.
- Gemini Live model is a **preview** (`gemini-3.1-flash-live-preview`) on `v1alpha` — expect API drift.
- `search_careers` sets `_holdSpeech`; changing tool order/names requires updating `LiveVoicePrompts` **and** controller hold/discard logic **and** tests.
- Prompt says the model must never speak before `format_answer`; the controller is the safety net if it does.
- Search assets must be rebuilt when their sources change: DB → `build_search_aliases.py`; never edit `search_aliases.json` by hand.
- Keyword grounding drops stop-words and only matches node names/intros: a sentence like "what can I do after twelfth" leaves just `twelfth` (0 matches). Retrieval therefore uses `search_keywords`, `broad: true` for overview/advice intents, and `10th/12th/tenth/twelfth/graduation` count as career-intent words (→ stream roots).
- Both prompts tell the model to say the `MATCH SUMMARY` count and, on a `COVERAGE` note, to say plainly what CareerPath does not list (and which states it does) without naming colleges from elsewhere.
- Coverage limits to expect in answers: courses exist only for the researched Rajasthan/MP/UP institutes, so level/course questions elsewhere get the "lists N institutes in <place>, but none offer…" note; districts are NULL outside those states.
- Data-quality traps: messy `level`/`mode`/`relation` strings (compare via `CourseLevels`); NULL `institution_type`; 25 institutes (city "Various"/"Online") have no state; node ids are ints in SQLite but strings in Dart models.
- Project rules (from `CLAUDE.md`): no new state-management libs; manual DI in `main.dart`; URLs only in `ApiUrls`; new services need tests; new models need `fromJson/toJson`; run `flutter analyze` + `flutter test` before commit.

## 12. Maintenance protocol for this file
Update this doc in the same commit when you: add/rename a voice tool or intent; change `AiProviderConfig` voice/model values;
change any DB table/column or ship a new `career_path.db` (then also re-run `tooling/build_search_aliases.py`); add a SharedPreferences key;
change the search pipeline in §6; move/rename a file listed in §3.
Re-verify counts with:
```bash
for t in $(sqlite3 assets/data/career_path.db "select name from sqlite_master where type='table' and name not like 'sqlite_%'"); do echo "$t: $(sqlite3 assets/data/career_path.db "select count(*) from $t")"; done
sqlite3 assets/data/career_path.db ".schema"
```
