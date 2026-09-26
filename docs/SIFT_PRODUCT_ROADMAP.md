# Sift Product Roadmap: On-Device News Briefing + RSS Reader

**Status:** Product direction approved; M0 evidence gate is not yet satisfied. Do not ship story-primary UI, personalized briefings, or urgent alerts until their stated quality gates pass.

**Audience:** One product for overlapping modes of use: executives who need a fast daily briefing and multi-source readers who want full control over their feeds. These are modes, not separate products or mutually exclusive personas.

**Source of truth:** This document owns product scope, milestones, experience contracts, and release gates. [`STORY_CLUSTERING_ARCHITECTURE.md`](STORY_CLUSTERING_ARCHITECTURE.md) owns the detailed clustering data model and pipeline. If they conflict, this roadmap owns product behavior; update both documents when changing a contract.

## Product promise

Sift helps people understand important news quickly by bringing coverage of the same underlying story together, showing its sources, and offering short morning and evening briefings. It can raise a separate urgent alert when a developing story is important, relevant to the person, and time-sensitive. People can also use Sift as a conventional RSS reader: feed subscriptions, filters, article reading, and source-level control remain available whether or not Apple Intelligence is available.

All model inference and learned preference data stay on the person’s device. Feed polling and optional publisher-page extraction use the network as they do today; article text is not sent to a remote model. The AI integration uses Apple’s system on-device model through `SystemLanguageModel.default`, plus Apple’s Natural Language and Translation frameworks. Do not add a third-party, bundled, or server-side model as a fallback.

## Experience and data contracts

- **Reader mode:** Preserve the existing RSS/Atom experience, including OPML, feed selection, search/filtering, read/star state, and article reading. It must remain usable when Apple Intelligence is disabled, unavailable, still preparing, or does not support the content language.
- **Story mode:** Show one durable story identity with a representative title, distinct publisher coverage, a chronological list of member articles, and direct links to each source. Keep “By Feed” as a first-class view. Coverage count describes how many publishers covered a story; it is not a claim that those publishers independently corroborate its truth.
- **Briefing:** Offer user-configured morning and evening local briefings. Each entry separates what happened from what changed, cites its source `FeedItem`s, and exposes source differences where evidence conflicts. State when only feed excerpts are available. Do not present unsupported model prose as fact.
- **Urgent alerts:** Evaluate three distinct signals: story importance, personal relevance, and time sensitivity. Send an urgent notification only when all exceed their configured threshold. Keep ordinary new-article alerts as an explicit user option, not the default briefing path. Honor quiet hours, OS notification permission, and the user’s Time Sensitive setting.
- **Local preference profile:** Ask for starter topics, sources, and briefing times. On device, learn topic/source relevance from opens, reading, stars/saves, and revisits; learn interruption preference from notification opens, response delay, dismissals, snoozes, and mutes; learn time sensitivity from responses to developing stories. A skip or a single dismissal is not evidence of disinterest. Let people inspect, edit, reset, and disable learning.
- **SwiftUI:** Keep story/briefing sections in small view types with narrow inputs, stable model identity in data-driven lists, and localizable full-string messages. These implementation constraints follow the supplied SwiftUI specialist references for structure, dataflow, `ForEach`, and localization.

## Milestones and gates

### M0 — Product and quality evidence (blocking)

1. Run short task sessions with 6 executive/CEO-style readers and 6 multi-source RSS readers; participants may belong to both groups. Follow with a one-week diary of briefing use, story grouping, and notification preferences. Use [`SIFT_M0_RESEARCH_PROTOCOL.md`](SIFT_M0_RESEARCH_PROTOCOL.md); it is a collection plan, not user evidence.
2. Build a manually labeled corpus of 300–500 real articles from at least 20 publishers, covering at least three languages including Turkish. Include syndicated copies, similar headlines about different events, continuing stories, and late-arriving coverage. External benchmark candidates and their limits are recorded in [`M0_DATASET_OPTIONS.md`](M0_DATASET_OPTIONS.md); none replaces this target corpus.
3. Report pairwise precision, recall, and F1, false-merge rate as its own metric, false splits, per-language-pair results, on-device latency, and Translation asset readiness. Define and record the false-merge bound before scoring the corpus.
4. **Gate:** pairwise F1 ≥ 0.75, false-merge rate under the pre-recorded bound, acceptable latency on representative target hardware, and required translation pairs actually installed and usable. An unsupported or not-yet-installed pairing must not silently enter a low-confidence cluster. If any gate fails, revise the language-normalization strategy and rerun M0; do not proceed to story-primary UI.

**Exit artifact:** labeled corpus and annotation rules, reproducible benchmark report, observed user needs, and a recorded go/no-go decision. Do not substitute synthetic examples or model-generated labels for this evidence.

### M1 — Source-backed story pipeline (after M0 passes)

- Add durable `StoryCluster` and per-article language, embedding, assignment, and pipeline provenance. Add a versioned SwiftData migration; deleting a derived cluster must never delete its articles.
- Add bounded background article extraction for new items. Keep the RSS title/summary as a supported input when the publisher blocks extraction, content is absent, or extraction fails.
- Run language detection, Translation availability checks, and Apple Natural Language embedding/clustering on device in shadow mode. Record the used analysis language and pipeline/model versions per article. Compare the 72-hour candidate window against M0’s continuing-story examples.
- **Exit gate:** benchmark remains within all M0 limits on the same labeled corpus; refresh/extraction failures leave the normal RSS reader intact; an inspectable report includes language coverage, asset state, latency, assignments, and errors.

### M2 — Story and synthesis experience (after M1 passes)

- Add Story and By Feed modes without removing existing feed controls or article reading.
- Generate a concise “what happened / what changed” synthesis from the story’s member content with `SystemLanguageModel.default` only. Check model availability and supported language before generation; treat generated claims as source-backed records that reference member `FeedItem` IDs.
- **Exit gate:** every factual claim can be opened at its supporting source; source-conflict and excerpt-only states are explicit; unavailable model/language produces a useful non-generative story view; RSS reader tests still pass.

### M3 — Briefings and notification policy (after M2 passes)

- Add local morning/evening schedules, separate urgent-alert settings, quiet hours, starter topic/source choices, and a visible/editable on-device preference profile.
- Replace default per-article interruption with the briefing and urgent-alert paths; keep individual new-article alerts opt-in.
- Schedule briefings as local notifications, but describe delivery as best-effort. iOS `BGTaskRequest.earliestBeginDate` is a lower bound, not an execution promise. Describe urgent alerts as “when Sift detects an update and the system allows processing,” not guaranteed instant delivery.
- Use the Time Sensitive interruption level only when the user opted in and OS settings allow it. Never claim source count proves truth or use learned relevance alone to declare an event urgent.
- **Exit gate:** separate permissions/settings work; quiet hours and duplicate suppression work; model unavailable and background-task-delayed paths are clear; dismissal and mute affect interruption preferences without deleting topic interest.

### M4 — Pilot and iteration

- First expose shadow results to a small opt-in pilot, then turn on briefings and alerts for pilot users.
- Review weekly: pairwise quality and false merges, factual support rate, recall of key briefing stories in task sessions, morning/evening return use, correction rate, and unwanted alerts per person.
- Version user corrections and pipeline provenance. Rerun the M0 corpus whenever the embedding model, analysis locale, pipeline, candidate window, or similarity threshold changes.

## Required implementation contracts

- Domain concepts: `StoryCluster`, time-bounded `Briefing`, source-linked generated claim, and on-device `PreferenceProfile`. Use durable IDs; generated claims retain the IDs of supporting `FeedItem`s.
- Inference boundary: only `SystemLanguageModel.default` for Apple’s system model. Never select a cloud model through a generalized model API. Keep inference and preference learning local; network access is limited to feeds and optional publisher pages.
- Availability boundary: Apple Intelligence can be off, unsupported by the device/language, or not ready. Gate the generative feature independently; do not gate feed reading, story membership, source links, or feed management on that state.
- Scheduling boundary: local notifications may be scheduled at a calendar time, but background work and fresh-news detection are best-effort. Do not promise exact refresh or urgent-alert timing.
- Notification migration: the current implementation sends up to five immediate article notifications per feed refresh. Replace that default with the policy in M3 while preserving an explicit “New Article Alerts” preference.

## Evidence and assumptions

- Repository evidence: current `FeedItem` stores extracted article text, but extraction is initiated when an article is opened; current feed refresh emits individual notifications. Existing app targets include iOS and macOS, and iOS refresh uses `BGAppRefreshTask`.
- Platform evidence: Apple documents Foundation Models availability and language checks, on-device generation, local notifications, and best-effort background scheduling. Verify API and supported-language details against the SDK used for each implementation.
- User evidence: no Sift user interviews, behavior data, or support records are currently available. The audience shape, learning signals, and briefing usefulness remain hypotheses until M0. Do not report them as validated findings.
- Product default: support both executive briefing and free-form RSS reading in one app; present the reader as the universal fallback and the on-device AI layer as an optional enhancement.
