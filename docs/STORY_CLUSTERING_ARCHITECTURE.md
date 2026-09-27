# Sift Story Clustering Architecture (Design Draft v0.2)

**Status:** Product direction and phased roadmap are approved. This clustering
design remains gated: story-primary UI and user-facing summaries do not ship until
the M0 evidence gate passes. See [`SIFT_PRODUCT_ROADMAP.md`](SIFT_PRODUCT_ROADMAP.md)
for the shared product contract, full milestones, behavioral personalization,
briefings, notifications, and release criteria. This document owns the clustering
data model and pipeline details; it extends `ARCHITECTURE.md` and `DATA_FLOW.md`.

**Scope.** This document specifies how ingested `FeedItem`s become source-linked
`StoryCluster`s. The product also includes conventional RSS reading, optional Apple
on-device synthesis, personalized morning/evening briefings, and separately gated
urgent notifications; those experiences are governed by the product roadmap. A
cluster's recency and coverage signals are inputs to those experiences, not proof
that publishers independently corroborate a claim.

## 0. Core Premise

The product's core story entity is **`StoryCluster`**, not `FeedItem`. `FeedItem` remains
the raw, effectively immutable ingestion unit (one row per publisher's article,
produced exactly as today by `FeedParser` + `FeedRefreshService`), but it is no
longer the primary thing a user reads. A `StoryCluster` groups the `FeedItem`s —
possibly from different feeds and different languages — that report the same
underlying story; Story mode uses it as the unit of navigation while By Feed keeps
`FeedItem` as the unit of reading.

Story mode presents "stories, each with sources" while By Feed mode preserves the
existing "feeds, each with items" experience. Story mode remains gated on M0; RSS
reading and feed management stay available on devices without Apple Intelligence.

## 1. Domain Model

The data model separates three levels which must never be collapsed into one
similarity cluster:

1. `StoryCluster` is one concrete event, announcement, decision, or bounded update
episode. Its members are source articles reporting that event.
2. `Storyline` is a broader issue or causal thread linking distinct event clusters
over time. Linking events to one storyline never makes their articles members of the
same event cluster.
3. `SourceClaim` is one attributed assertion from one article. `ClaimRelation` links
two claims as potentially conflicting, compatible at different scope, an update,
allegation/response, framing, syndicated repeat, or insufficient evidence. A relation
is a description of coverage, never an outlet-based truth verdict.

The following is the intended SwiftData schema (not yet applied to the live store;
the story data path remains shadow-only until the M0 gate passes). It adds
`StoryCluster`, `Storyline`, `SourceClaim`, and `ClaimRelation`, with links to the
existing `FeedItem` model:

```swift
@Model
public final class StoryCluster {
    @Attribute(.unique) public var id: UUID
    public var canonicalTitle: String        // copied from representativeItem.title verbatim — never translated
    public var summary: String?              // extractive, picked from the member nearest the centroid
    public var firstSeenDate: Date
    public var lastUpdatedDate: Date
    public var sourceCount: Int              // distinct publishers among current members — recomputed on every membership change, not time-dependent
    public var languages: [String]           // BCP-47 tags observed among members
    public var centroid: [Float]             // running mean embedding, in analysis-locale space
    public var representativeItem: FeedItem?  // drives display title/artwork/primary link
    public var storyline: Storyline?           // broader context; never merges events

    @Relationship(deleteRule: .nullify, inverse: \FeedItem.storyCluster)
    public var members: [FeedItem]
}

@Model
public final class Storyline {
    @Attribute(.unique) public var id: UUID
    public var canonicalTitle: String
    public var firstSeenDate: Date
    public var lastUpdatedDate: Date
    @Relationship(deleteRule: .nullify, inverse: \StoryCluster.storyline)
    public var events: [StoryCluster]
}

@Model
public final class SourceClaim {
    @Attribute(.unique) public var id: UUID
    public var feedItem: FeedItem               // exact source article
    public var speakerOrDocument: String?
    public var text: String                     // source-linked assertion/paraphrase
    public var claimType: String                // allegation, official statement, etc.
    public var subject: String?
    public var action: String?
    public var amount: String?
    public var assertedAt: Date?
    public var scope: String?
    public var sourcingMode: String?            // direct, attributed, syndicated, unclear
    public var syndicationOriginID: String?      // shared source/wire/statement identifier
}

@Model
public final class ClaimRelation {
    @Attribute(.unique) public var id: UUID
    public var leftClaim: SourceClaim
    public var rightClaim: SourceClaim
    public var kind: String                     // enum-backed relation label
    public var evidenceNote: String?
    public var pipelineVersion: String
}
```

Persisted relation kinds correspond to the closed labels in
[`SOURCE_CONFLICT_ANNOTATION.md`](SOURCE_CONFLICT_ANNOTATION.md). Unknown or
unsupported claim fields stay empty. In particular, `direct_conflict_candidate` is
not a decision that either claim is false.

New `FeedItem` fields:

```swift
public var storyCluster: StoryCluster?
@Relationship(deleteRule: .cascade, inverse: \SourceClaim.feedItem)
public var sourceClaims: [SourceClaim]
public var detectedLanguage: String?           // BCP-47, from NLLanguageRecognizer
public var analysisText: String?               // title+summary translated into the pivot locale — internal only, never rendered
public var embedding: [Float]?
public var clusterAssignmentAttemptedAt: Date?

// Derived-data provenance — required to know which rows must be recomputed
// when the pipeline changes (see §5, M3).
public var analysisLocale: String?             // pivot locale actually used for this item, recorded per-row since the global default can change over time
public var analysisPipelineVersion: Int?
public var embeddingModelVersion: Int?
public var translationReadiness: TranslationReadiness?
```

```swift
public enum TranslationReadiness: String, Codable {
    case notNeeded        // detectedLanguage == analysisLocale, no translation required
    case installed        // pairing was ready; analysisText was produced
    case waitingForAsset  // pairing is supported but the on-device model isn't downloaded yet
    case unsupported      // pairing is not supported — article remains unassigned
}
```

New `Feed` field:

```swift
public var publisherKey: String   // registrable domain of siteURL (fallback: url host), e.g. "arstechnica.com" — used to count distinct *publishers*, not distinct feeds, when several feeds (News/Tech/Breaking) come from the same site
```

### Fix: deletion semantics (was `.cascade`, is now `.nullify`)

`StoryCluster.members` must **not** cascade-delete. A `StoryCluster` is a derived,
disposable grouping — it can be deleted and rebuilt at will (pipeline version bump,
bad-cluster cleanup, etc.) and that must never take the underlying raw `FeedItem`
rows with it. `.nullify` means deleting a `StoryCluster` only clears
`FeedItem.storyCluster` back to `nil`, leaving the ingested article intact and
eligible for reassignment on the next pipeline pass. `Feed`'s existing `.cascade`
toward its own `FeedItem`s is unrelated and unchanged — deleting a feed the user
removed should still delete its articles.

### Migration note

`PersistenceController` currently builds `Schema([Feed.self, FeedItem.self])` with no
versioned migration plan. Adding `StoryCluster`, the new `FeedItem` fields, and
`Feed.publisherKey` is the first schema change this project has needed — M1 must
introduce a `SchemaMigrationPlan` (lightweight migration is sufficient; all new
fields are optional/defaulted) rather than relying on SwiftData's implicit
best-effort migration, since that's the only path that's inspectable and testable.

### UI note

`ArticleListView` becomes StoryCluster-primary (one row per story, expandable to its
member sources). The existing per-feed list is kept as a "By Feed" view for users who
disable clustering or want the old behavior — this is a toggle, not a removed
capability.

## 2. Clustering Pipeline

Runs as an actor (same shape as `FeedRefreshService`), invoked after every ingestion
batch — from the foreground app, from the iOS `BGAppRefreshTask` handler, and from
`SiftAgent.app` (§3).

```mermaid
graph TD
    A["New FeedItem rows from FeedRefreshService"] --> B["NLLanguageRecognizer: detectedLanguage"]
    B --> C{"detectedLanguage == analysisLocale?"}
    C -->|"yes"| D0["translationReadiness = notNeeded"]
    C -->|"no"| P["Translation Preflight (foreground app only): LanguageAvailability status(from:to:)"]
    P -->|".installed"| E["Translate title+summary -> analysisLocale"]
    P -->|".supported, not downloaded"| W["translationReadiness = waitingForAsset — retried next pipeline pass, no headless download attempted"]
    P -->|"unsupported"| U["translationReadiness = unsupported — keep unassigned; do not compare across incompatible embedding spaces"]
    E --> D1["translationReadiness = installed; analysisText set"]
    D0 --> F
    D1 --> F
    F["NLContextualEmbedding over analysisText; stamp analysisPipelineVersion + embeddingModelVersion"]
    F --> G["Candidate clusters: centroids updated in last 72h"]
    G --> H{"centroid passes AND representative/recent members support AND headline actions are compatible?"}
    H -->|"yes"| I["Assign to existing StoryCluster, update centroid + sourceCount"]
    H -->|"no"| J["Spawn new singleton StoryCluster"]
    W --> Z["Item stays unassigned until asset installs"]
```

Key decisions:

- **Common analysis locale (M0 hypothesis).** Every `FeedItem`, regardless of source
  language, may be normalized into one pivot language before embedding. The v0
  candidate is English, but M0 must validate translation coverage and quality for
  the target languages before this becomes a shipped default. Embedding spaces
  are not reliably aligned across languages, and simple lexical signals (shared named
  entities, TF-IDF overlap) that we want as a cheap first-pass filter only work when
  both sides are in the same language. `analysisText` is stored separately from
  `title`/`summary` precisely so translation quality never touches what the user
  reads.
- **Unsupported language pairs stay unassigned.** Do not embed raw text from an
  unsupported translation pair into a pivot-locale cluster: that mixes embedding
  spaces and can create silent false matches. Preserve the source article and retry
  only after a supported on-device path is available.
  **Translation asset provisioning is a foreground-only concern (fix 3).**
  Apple's Translation framework distinguishes a language pair being *supported*
  from actually being *installed* on-device; installing an uninstalled pairing can
  require user-facing download consent. `SiftAgent.app` runs headless and must never
  attempt to trigger that UI. Instead, the main app runs a **Translation Preflight**
  step whenever it's foregrounded: it looks at the languages actually seen across the
  user's feeds, diffs them against `analysisLocale`, and — while the user is present
  — prepares/downloads the needed pairings. `SiftAgent.app` only ever consumes items
  already `.installed`; anything still `.waitingForAsset` is simply retried on the
  next pipeline pass rather than blocking or erroring.
- **Bounded candidate set.** New items are only compared against clusters updated in
  the last 72h, not the full corpus — keeps assignment O(recent clusters), not
  O(history).
- **Centroid drift control.** Centroid is a running mean weighted toward recent
  members (or recomputed from the top-K freshest members) so a cluster doesn't
  ossify around its oldest items.
- **Concrete-event boundary (M0 spike v8).** A centroid match alone is not enough.
  Candidate assignments also need support from the event's fixed representative and
  recent member vectors. Natural Language lemmatizes action verbs in the normalized
  headline; clearly disjoint representative/candidate actions block an event merge,
  except for near-identical representative matches (≥0.985 cosine) that are likely
  headline paraphrases of the same event.
  The semantic vector keeps headline and article body as separate inputs, with 40%
  headline and 60% body weight when body text exists; the body prefers extracted
  publisher text and falls back to the feed summary. This keeps context and reported
  details central while using the headline as an event cue.
  This deliberately prefers a visible false split over quietly combining different
  developments about the same person, organization, or issue. Related developments
  belong on a `Storyline` timeline after a separately evaluated issue-linking step.
  The current shadow spike retains at most 12 recent vectors per candidate and
  requires the configured centroid threshold plus representative/recent support
  within 0.055 cosine slack. This setting is experimental, not a production default.
  The benchmark export records the ten nearest candidate checks per article, including
  separate headline and body cosine similarities, normalized headline action terms,
  accept/reject reason, and selected candidate. These traces are diagnostic and are
  not part of the saved user data model.
- **Publisher diversity is not corroboration.** Distinct publisher count remains a
  coverage measure only. `SourceClaim` records attribution and syndication origin so
  repeated copies of one statement are not presented as independent evidence.
- **Distinct-publisher counting, not distinct-feed counting (fix 5b).** `sourceCount`
  counts distinct `Feed.publisherKey` values among current members, not distinct
  `Feed.id`s — three feeds from the same outlet (News/Technology/Breaking) must not
  look like three independent corroborating sources.
- **Derived-data versioning (fix 6).** `analysisLocale`, `analysisPipelineVersion`,
  and `embeddingModelVersion` are stamped on every `FeedItem` when its
  `analysisText`/`embedding` are computed. This is the only reliable way to know,
  after a threshold/model/pivot change, exactly which rows are stale and need
  reclustering rather than reprocessing the entire corpus blindly.
- **Clustering does not author the briefing.** This subsystem may expose an
  extractive representative sentence for diagnostics or a non-generative fallback.
  Apple on-device synthesis and source-linked claims are governed by
  [`SIFT_PRODUCT_ROADMAP.md`](SIFT_PRODUCT_ROADMAP.md) and must pass M2's gate.

### The "briefing-worthy" signal is computed, not stored (fix 5a)

Whether a cluster currently qualifies as notable (e.g. "≥2 distinct publishers within
a rolling recency window") is **time-dependent** — it can flip from true to false
purely because a clock advanced, with no write to the row. Persisting it as a stored
`Bool` on `StoryCluster` would silently go stale. This subsystem therefore does not
store an `isBriefingWorthy` field at all; it exposes `sourceCount`, `languages`, and
timestamps, and leaves the recency-windowed "is this notable right now" query to
whatever consumes the cluster (a `BriefingPlanner` or similar, computed at query
time). Its product behavior and scheduling contract are defined in
[`SIFT_PRODUCT_ROADMAP.md`](SIFT_PRODUCT_ROADMAP.md).

## 3. Background Execution: SiftAgent.app via `SMAppService.loginItem`

Today's background story is two overlapping, partly-redundant mechanisms:

- `LoginItemManager` — `SMAppService.mainApp`, toggles whether *Sift.app itself*
  relaunches at login. Still valid, unrelated to background refresh.
- `LaunchAgentManager` — hand-writes a `launchd` plist to `~/Library/LaunchAgents`
  and shells out to `launchctl load/unload` to run `Sift --background-refresh`
  periodically. Fragile: manual plist bookkeeping, shells out to a CLI tool, doesn't
  track status other than file-existence, and doesn't play well with sandboxing or
  notarization changes over time.

**Point 1 change:** introduce a real second bundle, `SiftAgent.app`, embedded at
`Sift.app/Contents/Library/LoginItems/SiftAgent.app` with its own bundle identifier
(e.g. `io.github.zaryob.sift.Agent`) and `LSUIElement = true` (no Dock icon).

Registered as:

```swift
if #available(macOS 13.0, *) {
    let service = SMAppService.loginItem(identifier: "io.github.zaryob.sift.Agent")
    try service.register()
}
```

### Fix: resolving the scheduling contradiction (fix 2)

`SMAppService.loginItem` registers exactly that — a login item. It gives no
`StartInterval`-style periodic scheduling contract the way a real `launchd` agent
plist does; Apple treats `.loginItem` and `.agent(plistName:)` as distinct service
types with distinct guarantees. Since point 1 fixes `SiftAgent` as an `.app` bundle
(not a plist-only helper), the correct model is a **resident `LSUIElement` helper**,
not a fire-once-and-exit task and not a `launchd`-interval-scheduled process:

- `SiftAgent.app` launches at login and **stays resident** — it does not idle-exit
  after one run.
- It owns its own in-process scheduler: the same bounded `Task` + `Task.sleep` loop
  pattern `BackgroundFeedScheduler` already uses for its in-app timer, running
  ingestion + the clustering pipeline on an interval.
- It observes `NSWorkspace` sleep/wake notifications to suspend its timer during
  system sleep and run an immediate refresh on wake, rather than trying to catch up
  missed intervals.
- **Accepted limitation:** a login item has no `KeepAlive`/crash-restart semantics
  the way a `launchd` agent would. If `SiftAgent.app` is force-quit or crashes, it
  will not restart until the next login. This is a deliberate tradeoff of staying on
  `.loginItem` per point 1, not an oversight — recorded as an accepted risk in §6
  rather than solved by falling back to `SMAppService.agent(plistName:)`.

Its job once running: open the shared SwiftData store through the existing
`group.io.github.zaryob.sift` App Group container, run ingestion + the clustering
pipeline headlessly (using only `.installed` translation pairings, per §2), refresh
`WidgetSnapshotManager`'s JSON snapshot, and post notifications for cluster changes a
downstream consumer flags as relevant.

Status is observable via `service.status` (`.enabled` / `.requiresApproval` /
`.notFound`) instead of inferred from file existence; `.requiresApproval` should
drive a prompt to open System Settings via `SMAppService.openSystemSettingsLoginItems()`.

This fully replaces `LaunchAgentManager` (delete the manual plist writer and the
`launchctl` `Process` shell-outs). `LoginItemManager`'s `.mainApp` toggle is unrelated
and stays as-is — it controls whether the main UI app opens at login, a separate user
preference from whether the background agent runs.

## 4. Cross-Document Principle Carried Forward

This subsystem does not schedule or deliver anything to the user directly, but any
future consumer of `StoryCluster`/`sourceCount` — a briefing, a notification, a
digest — must treat delivery as **best-effort, never exact-time**, the same way
`BackgroundFeedScheduler`'s existing `BGAppRefreshTaskRequest` usage already is (it
only ever sets `earliestBeginDate` as a floor, never a promise). The full scheduling
and notification contract for the downstream product is defined in
[`SIFT_PRODUCT_ROADMAP.md`](SIFT_PRODUCT_ROADMAP.md).

## 5. Claim disagreements and source diversity

Story identity is separate from claim agreement. Articles can belong to the same
event cluster while using different frames; related developments can share an
`issueID` timeline while remaining separate event clusters. A cluster's `sourceCount`
measures distinct publishers, not independent corroboration or truth.

Briefing synthesis must preserve each material claim's speaker, article, timestamp,
and source link. Compare claims only after checking that they address the same
subject, proposition, time, and scope. Separate direct conflict candidates from
different-scope but compatible claims, updates, allegation/response pairs,
framing differences, syndicated repeats, and insufficient evidence. Foundation
Models may identify and summarize these relationships locally; they do not decide
which outlet or claim is true. When the relationship is unclear, show the source
articles without declaring a conflict. If Apple Intelligence is unavailable, keep
the cluster and source list usable and omit generated synthesis.

The annotation taxonomy and product treatment are specified in
[`SOURCE_CONFLICT_ANNOTATION.md`](SOURCE_CONFLICT_ANNOTATION.md). The active local
silver example is intentionally ignored by Git; never commit its feed records or
source text.

## 6. Milestones

| # | Milestone | Exit Criteria |
|---|---|---|
| **M0** | **Blocking evidence and feasibility gate** — blocks story-primary UI, synthesis, briefings, and urgent alerts. | The current native spike (`Sift/Clustering/StoryClusteringSpike.swift`) runs language detection → installed-asset Translation preflight → on-device embedding → sliding-window clustering without changing shipped data or UI. Run it against a hand-collected corpus of 300–500 real articles from ≥20 publishers and ≥3 languages, manually labeled under [`STORY_CLUSTERING_ANNOTATION_GUIDE.md`](STORY_CLUSTERING_ANNOTATION_GUIDE.md). Evaluate with [`tools/evaluate_story_clusters.py`](../tools/evaluate_story_clusters.py). **Metrics:** pairwise precision/recall/F1; false-merge rate = contaminated predicted clusters / all predicted clusters; false-positive pair rate and false splits reported separately. Record a numeric false-merge bound before scoring. **Go/no-go:** pairwise F1 ≥ 0.75, false-merge rate below that bound, acceptable per-item latency on representative devices, and required translation pairs actually `.installed`. Measure `lowLatency` and `highFidelity` separately. User sessions and a one-week diary are also required by the roadmap; repository code does not substitute for those evidence. If a gate fails, revise the on-device strategy and rerun M0 before moving forward. |
| **M1–M4** | Product delivery milestones | Defined by [`SIFT_PRODUCT_ROADMAP.md`](SIFT_PRODUCT_ROADMAP.md), the product source of truth. M1 adds durable story pipeline after M0; M2 adds story/synthesis; M3 adds briefing and notification policy; M4 pilots and iterates. Keep technical schema and migration details in this architecture document. |

### Current development diagnostic (2026-09-27)

The same 66-row, agent-provisional silver sample was run with analysis locale `en`,
`highFidelity`, a 72-hour window, and threshold `0.96`. Spike v7 introduced separate
translated headline and article-body vectors weighted 40/60; its F1 was 0.548, recall
0.426, precision 0.768, and contaminated-cluster rate 12.5%. Spike v10 retained that
body-first weighting and added an on-device Foundation Models event signature as a
boundary signal. It scored precision 0.704, recall 0.595, F1 0.645, false-merge rate
20% (5/25 clusters), false-positive pair rate 29.6%, and 7/22 split gold stories.
The eager-signature run took 246 seconds on the recorded Mac16,1 host.

Spike v11 uses the same policy and data but calls Foundation Models only after the
Natural Language embeddings shortlist at least one candidate that passes centroid,
representative, and recent-member cohesion checks. It produced the same assignments
and quality metrics, called the model for 50/66 rows, and took 204 seconds (about
17% faster than the eager run). This is progress but still about 3.1 seconds per row
on this host; it does not establish acceptable production latency. Do not block feed
refresh on this model call.

The same v11 build with `--event-signatures disabled` is the signature-free Apple
Natural Language baseline: precision 0.768, recall 0.426, F1 0.548, false-merge rate
12.5% (4/32 clusters), and 119 seconds. Enabling signatures raised recall by 17
points and F1 by about 10 points, but lowered precision by 6 points and raised
false-merge rate by 7.5 points, with 85 seconds more processing time. The trace shows
that a compatible Foundation Models signature can override the Natural Language
headline-action mismatch. Spike v12 removes that positive override: signatures can
reject incompatible candidates, but cannot overrule an action mismatch. Quality then
returned exactly to the signature-free baseline (precision 0.768, recall 0.426,
F1 0.548, false-merge rate 12.5%), while 51 signatures were still generated and the
run took 163 seconds. The Foundation Models signature therefore added no clustering
quality on this corpus and is disabled by default in spike v13. Keep the enabled path
as an explicit experiment only.

The decision trace records body and headline similarity independently, plus overall
signature similarity and actor/action/object compatibility evidence. Action/object
word overlap did not separate accepted true-positive pairs from false-positive pairs
(median overlap was zero for both), while actor overlap was populated for only two
accepted pairs. This does not support actor/action/object overlap as a hard gate.
The current evidence supports using Apple Natural Language for event clustering and
reserving Foundation Models for user-facing, source-linked “what happened/what
changed?” synthesis, where it can produce a cited briefing rather than decide event
identity. The clustering work remains below the M0 quality and latency gates.

All rows were assigned after Translation preflight, but this sample does not prove
language-independent clustering: it contains cross-language same-event pairs, and
many were missed. M0 still needs deliberately assembled and adjudicated same-event
coverage across language pairs before this pipeline can pass its gate. The corpus
and detailed assignments are local and excluded from Git. This agent-provisional
sample is diagnostic only; do not use it to declare a quality gate passed or as the
sole basis for a production threshold.

### Larger multilingual shadow attempt (2026-09-27)

A balanced 300-row sample was collected locally across 44 feeds and 43 publishers:
120 Turkish, 120 English, and 20 each German, Spanish, and French. Full-text
extraction succeeded for 195 rows (65%). Agent-provisional labels identify 18
clear multi-source event candidates (63 rows); remaining rows are provisional
singletons. Google News' mixed-headline aggregate entries were excluded. None of
these annotations are human gold.

Spike v15 uses body-first 60/40 body/headline weighting and caps the source context
at 4,000 characters, the maximum used by embedding generation. The benchmark ran
with English analysis, threshold 0.96, 72-hour candidate window, low-latency
translation, and event signatures disabled. It assigned 120/300 rows. The
strategy-matched Translation preflight reported 177 rows waiting for language
assets and 3 rows with insufficient text. Its silver-label diagnostic was P 0.060,
R 0.026, F1 0.036, false-merge rate 2.89% (8/277), and false-positive pair rate
94%. This score is not a valid model quality estimate because most non-English
rows were unassigned and the singleton labels have not been reviewed. It does,
however, establish that story-first UI must remain gated and that translation
readiness is an actual prerequisite for the intended cross-language test.

The earlier preflight used the default Translation strategy even when a different
strategy was selected. On this host that mismatch said assets were installed, but
the `lowLatency` Translation session threw `notInstalled`. Preflight now uses the
selected strategy and session failures are surfaced as
`translationSessionUnavailable` instead of being reported as a generic processing
failure. A one-item rerun with strategy-matched preflight correctly reported
`translationNotInstalled` / `waitingForAsset`. Apple documents `.installed` as
ready for the requested language pair, and warns that readiness may change before
translation; keep the runtime error path as well as preflight checks
([status](https://developer.apple.com/documentation/translation/languageavailability/status),
[session readiness](https://developer.apple.com/documentation/translation/translationsession/isready)).

All RSS snapshots, publisher text, silver labels, predictions, and reports remain
checkout-local and are excluded from Git. The native extractor source is committed
so the body-availability measurement can be reproduced from the ignored feed
manifest.

## 7. Non-Goals and Accepted Risks for v0

- Cross-publisher fact-checking or claims that source count proves truth.
- User-facing cluster correction before benchmark quality is established. When
  correction UI ships, corrections must be durable and included in later evaluation.
- Server-side/cloud clustering, synthesis, or preference learning. If M0 fails,
  revisit the on-device strategy rather than silently routing content to a server.
- Per-user analysis-locale selection is not assumed; M0 determines whether a
  single validated pivot can meet the language quality gate.
- **Accepted:** `SiftAgent.app` as a `SMAppService.loginItem` has no crash-restart
  guarantee and will not resume until next login if killed — a deliberate tradeoff of
  point 1's requirement, not something M1–M3 need to solve.
