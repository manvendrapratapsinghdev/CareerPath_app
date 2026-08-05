# AI Guide direct Gemini architecture

## Decision

The first release is a backend-free prototype. The Flutter application:

1. loads the bundled CareerPath Explore data locally;
2. fetches the Gemini API key at app startup from:
   `https://api.npoint.io/aae9f0beb3e9b9c5d553`;
3. keeps the returned `g_api_key` value in memory only;
4. retrieves relevant Explore records on-device;
5. calls Gemini `generateContent` directly with that bounded context; and
6. validates model citations against the local retrieval allow-list.

No CareerPath server, chat database, or conversation API is used.

## Credential handling

- The credential value is never present in source code, assets, tests, build
  arguments, analytics, crash reports, or logs.
- The remote configuration response is held only in process memory.
- The app does not write the value to SharedPreferences, secure storage, files,
  SQLite, or another persistence mechanism.
- Failed key loads are retryable; a successful value is cached until app
  termination.
- Gemini receives the value in the `x-goog-api-key` request header, never in the
  URL.

This is suitable only for the explicitly accepted prototype threat model. A
public configuration URL can be inspected by an app user and therefore does not
make the API key secret. Before enabling billing or broad production
distribution, move Gemini access behind an authenticated server and rotate the
prototype key.

## Runtime flow

```text
App start
  ├─ Load local Explore database
  └─ Preload public key configuration into memory

Student sends a message
  ├─ Validate length/language
  ├─ Run local safety and abuse checks
  ├─ Retrieve matching local Explore records
  ├─ No evidence → deterministic Explore fallback (no Gemini call)
  └─ Evidence found
       ├─ Get cached key (or retry key fetch)
       ├─ Call configured Gemini model directly
       ├─ Require structured JSON
       ├─ Keep only source IDs from the retrieval allow-list
       └─ Missing answer/source → deterministic Explore fallback
```

## Provider configuration

Provider-specific values live in `AiProviderConfig`, separate from UI and
grounding:

- provider: `gemini`
- model: `GEMINI_MODEL` compile-time environment value, with the current default
- remote-key timeout
- generation timeout
- local context and node limits

`AiChatRepository` is the provider-neutral UI boundary. A future OpenAI
implementation can implement the same interface without changing the tab or
controller.

## Grounding

`LocalAiGroundingService` searches the same `CareerDataService` records used by
Explore. It builds a bounded prompt from matching career nodes and, for selected
leaf nodes, related books, institutes, and job sectors.

Each context item has a stable local source ID. Gemini must return one or more of
those IDs for an answer to be displayed. Unknown or invented IDs are discarded;
if none remain, the app displays:

> Sorry, I don’t have enough information about that in CareerPath. Please visit
> the Explore tab to browse the available career paths.

## Guardrails

- Empty input: request is rejected locally.
- Unsupported language: English-only message for the first release.
- Out-of-scope or missing local evidence: deterministic fallback; no Gemini
  request.
- Prompt/credential extraction: local refusal; no Gemini request.
- First abusive-language occurrence: warning.
- Second occurrence: chat is blocked for the remaining app runtime. Starting a
  new ephemeral conversation does not bypass it.
- Self-harm language: immediate supportive escalation to a trusted adult,
  counselor, emergency service, or equivalent; no Gemini request.
- Gemini safety filters are also configured for harassment, hate, sexual, and
  dangerous content.

## Retention and offline behavior

- Conversation messages and guardrail counters are memory-only.
- New/Clear Chat removes the current visible conversation.
- App termination clears all chat state and the fetched key.
- Explore browsing, local retrieval, and deterministic guardrail/fallback
  responses remain local.
- A generated AI answer requires internet access to both the key endpoint and
  Gemini. The feature must show a retryable unavailable state when either cannot
  be reached.

## Verification

Required checks:

- key endpoint is called at startup;
- key value is never logged or persisted;
- direct Gemini request uses the header;
- prompts contain only bounded local evidence and chat history;
- no Gemini call occurs for blocked, unsafe, injected, or unsupported requests;
- returned citations are allow-listed;
- new chat does not restore prior messages;
- new chat does not bypass an active abuse block;
- full Flutter tests, static analysis, and Android emulator smoke pass.
