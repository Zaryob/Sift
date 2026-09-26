# Story clustering annotation protocol (M0)

This guide supports the manually labeled 300–500 article M0 corpus described in [`SIFT_PRODUCT_ROADMAP.md`](SIFT_PRODUCT_ROADMAP.md). Human annotators assign `goldStoryID`; the benchmark compares those labels with `predictedClusterID`. A script can calculate agreement metrics, but **it does not create, review, or substitute for human labels**.

## Unit and required fields

Use one record per distinct article/feed item. Give each record a stable, unique `articleID`, a `goldStoryID` shared only by articles about the same underlying event, and the clusterer's `predictedClusterID`. Keep the article title, publisher, publication time, language, available excerpt/full text, and source URL in the corpus working sheet for annotation and adjudication; those context fields are not required by the evaluator.

## Assigning story identity

- **Same underlying event: same ID.** Group coverage that reports the same concrete occurrence, announcement, decision, incident, or match, even when headlines and framing differ.
- **Syndicated or republished coverage: same ID.** A wire story and publisher copies remain one story when they describe the same event. Publisher count must not turn copies into independent events.
- **Ongoing story: use continuity, not topic similarity.** Keep articles together when later coverage updates or adds consequences to the same identifiable event or unfolding episode. Create a new ID when a later development is a distinct event that can be understood and reported independently, even if it concerns the same people, organization, place, or broad issue.
- **Similar headline, different event: different IDs.** Shared entities, topic, wording, or date alone do not establish story identity. For example, separate elections, court rulings, product launches, or incidents involving the same organization remain separate events.
- **Ambiguous boundary: adjudicate.** Annotators record a short rationale and escalate uncertain pairs to a designated adjudicator. Do not force a merge to avoid an “unknown” label; resolve the record before scoring or explicitly exclude it under a documented corpus policy.

The annotation question is: **Could a careful reader treat these articles as coverage or updates of the same concrete event/episode, rather than merely the same subject?** If not, assign separate IDs.

## Review and corpus hygiene

1. Annotate independently before discussion where staffing allows; include at least one second review of boundary cases and a recorded adjudication decision.
2. Include hard negatives (similar headlines about distinct events), continuing coverage, syndicated copies, late-arriving coverage, and multiple languages. Preserve source and language metadata so results can be stratified.
3. Freeze the gold labels and record the corpus version before evaluating a pipeline. Do not change labels to improve a model score; corrections require a rationale, version increment, and rerun.
4. Record the false-merge acceptance bound before scoring, as required by M0. The evaluator reports a cluster-level false-merge rate: contaminated predicted clusters divided by all predicted clusters. It also reports the false-positive same-cluster pair rate separately.

## Evaluator input and metric definitions

The standalone [`evaluate_story_clusters.py`](../tools/evaluate_story_clusters.py) reads UTF-8 JSON Lines with these required non-empty string fields:

```json
{"articleID":"a-001","goldStoryID":"story-12","predictedClusterID":"cluster-4","language":"tr"}
```

It rejects malformed records, missing/empty required fields, and duplicate `articleID`s. `language` is optional for hand-built evaluation files; when present, it enables pairwise precision/recall/F1 stratified by unordered language pair (for example `en|tr`). The native runner writes the detected source language or `und` when detection fails. Pairwise true positives are article pairs with the same gold and predicted IDs; false positives share only the predicted ID; false negatives share only the gold ID. False splits count gold stories appearing in multiple predicted clusters; the reported rate divides by the number of gold stories. Cluster contamination is the article-weighted share outside each predicted cluster's majority gold story.

Example invocation:

```sh
python3 tools/evaluate_story_clusters.py corpus.jsonl --json-output report.json
```

The tool prints a human-readable summary and machine-readable JSON; `--json-output` also saves the JSON report. A zero denominator is reported as `null`/`n/a`, rather than being silently treated as perfect performance.

## Running the native M0 spike on macOS

The runner invokes the same Swift spike compiled into Sift; it does not embed Python
or use a network model. Prepare a UTF-8 JSONL corpus with one manually adjudicated
article per line. Use stable UUIDs for `id`, and keep `goldStoryID` aligned with the
annotation sheet:

```json
{"id":"B6D29022-219C-4725-AE16-D7CF89BAA157","title":"Example headline","summary":"Feed excerpt","fullText":"Optional extracted text","publisherKey":"publisher.example","publishedAt":"2026-09-27T07:30:00Z","goldStoryID":"event-001"}
```

Compile and run from the repository root. The spike may ask Natural Language to
make its Apple embedding asset available; it uses a Translation language pair only
when the operating system reports that pair as already installed. It does not start
Translation asset downloads for the benchmark:

```sh
swiftc -parse-as-library Sift/Clustering/StoryClusteringSpike.swift \
  tools/StoryClusteringBenchmark.swift \
  -framework NaturalLanguage -framework Translation \
  -o /tmp/StoryClusteringBenchmark

/tmp/StoryClusteringBenchmark \
  --input /path/to/adjudicated-corpus.jsonl \
  --evaluator-output /tmp/sift-predictions.jsonl \
  --assignments-output /tmp/sift-assignments.json \
  --locale en --threshold 0.82 --window-hours 72 \
  --translation-strategy highFidelity

python3 tools/evaluate_story_clusters.py /tmp/sift-predictions.jsonl
```

Run `--translation-strategy lowLatency` as a separate benchmark; do not combine
results from different strategies. The assignments file records each row's detected
language, Translation readiness, assignment, similarity, publisher count, latency,
and pipeline/model version. Unassigned articles are retained as unique singleton
predictions so unsupported languages and unavailable assets count as false splits
instead of disappearing from the score. A synthetic smoke-test corpus can check the
runner but cannot satisfy M0's real-corpus gate.

The runner requires `--threshold` explicitly; the sample value above is only a
command example, not a validated recommendation. Divide the annotated corpus by
whole `goldStoryID` groups into calibration and holdout sets, keeping language-pair
and publisher coverage visible in both. Choose the similarity threshold on the
calibration set, write down the false-merge acceptance bound and selected pipeline
settings before scoring the holdout, and report the holdout once. Never split articles
from the same gold story across calibration and holdout, or use a tuned holdout score
as an unbiased quality estimate.
