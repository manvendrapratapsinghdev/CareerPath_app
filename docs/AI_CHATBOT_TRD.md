# CareerPath AI Guide — Product and Technical Requirements

| Field | Decision |
|---|---|
| Status | Prototype implementation |
| App | CareerPath Student Flutter app |
| Tab | AI Guide, between Explore and Saved |
| Initial provider | Google Gemini |
| Future providers | Replaceable through `AiChatRepository` |
| Knowledge source | Bundled data used by Explore |
| Backend | None for the prototype |
| Chat retention | Memory-only; no prior conversation list |
| Credential source | Remote configuration fetched at app startup |

## 1. Product summary

AI Guide gives students a conversational way to understand the career,
education, book, institute, and job-sector information already available in
Explore. It is a grounded assistant, not a general-purpose chatbot or web search.

The bottom navigation order is:

`For You → Explore → AI Guide → Saved`

The assistant answers only when local retrieval finds relevant Explore data. If
the product data does not support an answer, it returns a fixed fallback and
directs the student to Explore.

The prototype is backend-free. Flutter fetches the Gemini key configuration into
memory, retrieves Explore context locally, and calls Gemini directly. This
deliberately accepts that a public remote configuration endpoint cannot keep a
mobile credential secret. The key must be rotated and server-side mediation
introduced before billing or production-scale distribution.

## 2. Goals

1. Provide an approachable, polished student chat experience.
2. Ground displayed factual answers in local Explore records.
3. Make unsupported questions fail closed with a predictable response.
4. Apply local and provider safety controls appropriate for students.
5. Avoid persistent chat history and sensitive message logging.
6. Keep provider details outside the UI so OpenAI can be added later.
7. Preserve Explore and other current app functionality.

## 3. Non-goals

- General web search or unrestricted model knowledge.
- Saving, restoring, syncing, or sharing conversations.
- A conversation-history screen.
- File, image, audio, or document input.
- Guaranteed admission, salary, employment, medical, legal, or financial advice.
- A production-grade credential-security boundary.
- Replacing a parent, teacher, counselor, or emergency service.

## 4. User experience

### 4.1 Empty state

The tab shows:

- AI Guide title and concise scope notice;
- a friendly introductory panel;
- starter prompts derived from supported career questions;
- a multiline composer;
- a send action that is disabled for empty input; and
- a New Chat action.

### 4.2 Conversation

- User and assistant bubbles are visually distinct.
- Messages scroll naturally and remain readable with large text.
- A visible thinking state appears while a request is active.
- Only one request may be active at a time.
- The input is capped at 500 characters.
- Up to eight recent messages and 6,000 characters are sent for context.
- Suggested follow-up prompts may appear under a grounded response.
- Source chips open the corresponding record in Explore.
- Errors preserve the typed conversation and expose a retry action.

### 4.3 New and clear chat

New Chat and Clear Chat:

- remove all visible messages;
- rotate the ephemeral session ID;
- do not call a delete API because no chat is stored; and
- do not reset an active abuse block during the current app runtime.

Switching tabs keeps the current memory-only conversation while Home remains
alive. App termination removes it.

## 5. Knowledge and grounding

The authoritative source is `CareerDataService`, backed by the bundled Explore
database. Supported records include:

- streams and hierarchical career nodes;
- node names and introductory descriptions;
- related books;
- institutes; and
- job sectors.

For every student question:

1. normalize and tokenize the request;
2. match relevant local nodes;
3. optionally add the selected stream context;
4. add bounded leaf details;
5. assign stable source IDs;
6. send only that evidence to Gemini; and
7. accept only returned source IDs included in the retrieval result.

The app must not display an answer if the model returns no valid source. It
instead displays:

> Sorry, I don’t have enough information about that in CareerPath. Please visit
> the Explore tab to browse the available career paths.

This fallback is local and deterministic. Gemini is not called when retrieval
finds no evidence.

## 6. Provider design

The UI depends on `AiChatRepository`, not Gemini. Provider-specific code is
isolated in `GeminiAiChatRepository`; configuration is isolated in
`AiProviderConfig`.

The initial request uses Gemini `generateContent` with:

- the API key in `x-goog-api-key`;
- a strict system instruction;
- bounded conversation and local evidence;
- low temperature and bounded output;
- provider safety settings; and
- a structured JSON response schema.

Expected model result:

```json
{
  "status": "answered",
  "answer": "Grounded response text",
  "sourceIds": ["career_node:engineering"],
  "suggestedPrompts": ["Which institutes are listed?"]
}
```

The app owns the final source validation. Provider output never creates arbitrary
Explore links.

To add OpenAI later, implement another `AiChatRepository`, introduce a
configuration selector, and leave the controller and tab unchanged.

## 7. Key loading and security boundary

At startup the app requests:

`GET https://api.npoint.io/aae9f0beb3e9b9c5d553`

Expected shape:

```json
{
  "g_api_key": "<runtime value>"
}
```

Requirements:

- do not hardcode the returned value;
- do not print it;
- do not send it to analytics or crash reporting;
- do not write it to preferences, secure storage, files, or SQLite;
- cache it in process memory only;
- retry a later load after a startup failure;
- send it to Gemini only as a header; and
- clear the in-memory value when its service is disposed.

The URL is a public distribution mechanism, not secret storage. The accepted
prototype has no billing exposure. Production hardening requires a backend proxy,
key restrictions where supported, rate limits, abuse controls, and key rotation.

## 8. Student safety and guardrails

Guardrails run before local retrieval and again through Gemini safety settings.

| Condition | Required behavior |
|---|---|
| Empty message | Ask the student to enter a question |
| Unsupported language | Ask the student to use English |
| Missing Explore evidence | Fixed Explore fallback; no Gemini call |
| Prompt/key extraction | Refuse and redirect to career questions |
| First abusive message | Warn and explain continued misuse may block chat |
| Second abusive message | Block chat for the current app runtime |
| Self-harm language | Supportive response and immediate trusted-adult/emergency escalation |
| Provider/network error | Generic retryable unavailable state |
| Invalid or ungrounded model response | Fixed Explore fallback |

Self-harm support takes priority even if the chat was previously blocked.
Conversation text must not enter analytics or ordinary logs.

The local profanity list is a first-release baseline, not comprehensive
moderation. It should evolve through policy review and testing without storing
student messages.

## 9. Offline-first behavior

The main career experience remains local:

- Explore data and navigation work from the bundled database.
- Retrieval, unsupported-topic fallback, and local guardrails do not need
  Gemini.
- Chat messages are stored only in memory.

Generated AI answers are network-assisted, not offline: the device must reach
the remote key configuration and Gemini. Network failures must not break Explore
and must produce a recoverable chat error.

## 10. Accessibility and visual requirements

- Meet touch-target and contrast expectations.
- Do not convey warning, blocked, loading, or error state by color alone.
- Support screen readers and text scaling.
- Label source chips and icon-only controls.
- Keep the composer visible above the software keyboard.
- Use the existing app theme, spacing, navigation, and typography conventions.
- Respect safe areas and Android back behavior.

## 11. Observability and privacy

Allowed analytics are content-free events such as:

- AI tab viewed;
- starter prompt selected;
- request started;
- response status;
- source opened;
- retry selected;
- new/clear chat selected; and
- chat blocked.

Never include:

- message or answer text;
- the Gemini credential;
- request headers or raw provider payloads;
- student names or profile fields; or
- raw model responses.

## 12. Testing and acceptance criteria

### Unit and widget tests

- startup key load succeeds, caches in memory, and retries after failure;
- invalid key response is rejected;
- local retrieval finds expected records and rejects unrelated topics;
- direct Gemini request uses the configured model and API-key header;
- prompt body contains local evidence but no credential field;
- invalid model citations fail closed;
- first abusive message warns and second blocks;
- a new session cannot bypass an active block;
- self-harm response is local and does not call Gemini;
- controller bounds history and clears messages;
- tab ordering, empty state, composer, sources, and blocked UI render correctly.

### Regression and runtime QA

- all Flutter tests pass;
- static analysis has no newly introduced errors or warnings;
- Android emulator installs and opens the app;
- AI Guide is between Explore and Saved;
- New Chat clears only in-memory conversation;
- profile and existing navigation behavior remain intact;
- Explore still works without the chat network; and
- a reachable configuration/Gemini service produces a grounded response.

## 13. Known limitations and future work

- The remote key can be discovered by a determined user.
- Model generation requires network access.
- English is the only enabled chat language.
- Local lexical retrieval is less capable than an indexed semantic retriever.
- The abuse block lasts only until app restart.
- The first release uses non-streaming responses.
- No cross-device throttling exists without a backend.

Production evolution should add a server proxy, authenticated quotas, a semantic
index generated from the same canonical data, broader language support, policy
review, streaming after safety validation, and key rotation.

For implementation-level details, see
[`AI_CHAT_DIRECT_GEMINI_ARCHITECTURE.md`](AI_CHAT_DIRECT_GEMINI_ARCHITECTURE.md).
