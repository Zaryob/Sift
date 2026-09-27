# M0 story-labeling workflow

This plan gets a defensible gold set without asking the product owner to label
hundreds of articles alone. The owner approves the annotation rules; qualified
reviewers perform the bulk labeling, and a reviewer adjudicates disputed examples.

## Feed pool and collection

- Use the local, ignored RSS manifest as a source pool. It contains only feed names
  and URLs, including working candidates selected from the [Plenary Awesome RSS
  Feeds repository](https://github.com/plenaryapp/awesome-rss-feeds). That repository
  organizes feeds by topic and country and reports roughly 500 recommended feeds and
  over 250 news sources.
- Collect only the fields needed for annotation: stable article ID, title, RSS
  excerpt, publisher, source URL, publication time, and detected language. Keep the
  snapshot and labels outside Git. Fetch full text only when an annotator needs it
  and the publisher permits access.
- Sample 300–500 distinct items across at least 20 publishers and at least three
  languages including Turkish. Include syndicated copies, continuing coverage,
  multiple developments about the same people or organizations, and similar
  headlines about different events.
- Remove exact duplicate feed entries, but keep publisher copies when they are
  separate articles. Preserve feed and publisher identity so the benchmark can
  distinguish source diversity from duplicate subscriptions.

## Human review that scales

1. Run a 30-item pilot with two reviewers who can read the sampled languages. Measure
   review time and identify confusing boundaries before freezing the instructions.
2. Have the native on-device spike propose candidate neighbors for navigation. The
   review screen may surface likely matches, hard negatives, and random comparisons,
   but it must hide the model's cluster ID and score. Reviewers create the groups
   themselves from article evidence.
3. Reviewers assign the same `goldStoryID` only when items cover the same concrete
   event or episode under [`STORY_CLUSTERING_ANNOTATION_GUIDE.md`](STORY_CLUSTERING_ANNOTATION_GUIDE.md).
   Record “related but different event” separately as an adjudication note; it does
   not become a same-event gold pair.
4. Double-review the pilot, a stratified portion of the corpus, and every uncertain
   or conflicting pair. A third reviewer adjudicates disagreements. Do not settle
   disagreements by accepting the model's cluster.
5. Keep a blind holdout in which reviewers do not see predicted cluster membership.
   Split calibration and holdout by whole `goldStoryID` groups, then select the
   threshold and false-merge bound using calibration only.

The local review page is [`tools/m0-labeler.html`](../tools/m0-labeler.html). A
reviewer opens it in a browser, chooses a JSONL snapshot from disk, assigns each
article to a story group, and explicitly downloads either a checkpoint or completed
gold JSONL. The page has no server connection and does not persist the article data
in browser storage. It does not show clustering predictions, which makes it suitable
for blind holdout labeling.

Build a balanced recent snapshot with the native Swift collector. Its default output
is stdout; the redirect below is an explicit local-only choice needed to give the
review page a file. Keep the destination outside Git and share it only with approved
reviewers:

```sh
swiftc -parse-as-library tools/CollectM0FeedSnapshot.swift \
  -framework NaturalLanguage -o /tmp/CollectM0FeedSnapshot

/tmp/CollectM0FeedSnapshot \
  --manifest tools/local/sift-feed-sample.json \
  --since-hours 168 --limit 30 --per-publisher 3 --per-feed 20 \
  > /tmp/sift-m0-pilot.jsonl
```

The collector keeps feed text in memory and writes only JSONL to stdout. Its balanced
selection caps repeated coverage from any one publisher; check the reported language
and publisher mix before using the pilot. `--limit 300` or `--limit 500` builds a
larger review set. Feed errors and counts are written to stderr, without headlines.

This changes the workload from searching every item manually into checking a ranked
set of article pairs and building groups from confirmed links. The 30-item pilot
provides a measured effort estimate before expanding to the full corpus.
Active-learning suggestions reduce search effort; they do not count as gold labels.

## Agent-created seed labels

To keep implementation moving before reviewer recruitment, an agent may create a
small, high-confidence **silver** set from recent feed snapshots. The agent should
group clear coverage of one concrete event, retain separate labels for related but
independent developments, and add a short rationale to each record. Mark these rows
`annotationStatus: "agent-provisional"`. Do not describe these labels as human gold,
use them to claim the M0 accuracy gate, or tune a final threshold as if the set were
an independent holdout.

The current local seed is `tools/local/sift-m0-agent-labeled-seed.jsonl`; exploratory
reports are in `tools/local/sift-m0-seed-threshold-sweep*.json` and
`tools/local/sift-m0-multilingual-seed-report.json`. These files are intentionally
excluded through the checkout-local `.git/info/exclude` and are not part of a commit.
The seed now has 54 records from 29 publishers across Turkish (30), English (12),
German (4), Spanish (4), and French (4), grouped into 17 provisional story IDs.
The 24 added records cover three multilingual events and three separate Apple-topic
hard negatives. Their labels and rationales remain local. The multilingual set
contains no same-event Turkish/non-Turkish pair yet, so it does not measure
Turkish-to-other-language clustering.

Use the silver seed to expose obvious pipeline failures and compare representation
or candidate-generation variants. The original `m0-spike-1` representation assigned
all 30 seed records to one predicted cluster at threshold 0.82. Revision
`m0-spike-2` combines separate unit-normalized title and excerpt vectors at 0.7/0.3.
On the 30-row Turkish-only seed, threshold 0.96 reached exploratory pairwise F1 0.83.
After adding the multilingual rows, the same threshold yielded F1 0.53, precision
0.73, recall 0.42, a 12.5% contaminated-cluster rate, and a 27.1% false-positive-pair
rate. Four gold IDs were split. Translation reported `installed` for 42 non-English
rows; the 12 English rows needed no translation. The run took about 102 seconds for
54 rows on the recorded Mac16,1 / macOS 27.0 machine (about 1.9 seconds per article).
These are silver-set diagnostics only: the threshold was not independently chosen,
the labels were agent-created, and this is not an M0 pass. In particular, the seed
shows that the current cross-language approach misses some clear matches and that
per-article Translation latency needs work. Keep the failing multilingual cases as
regression examples; test batching/caching and representation changes against the
same private seed, then validate the decision on human-reviewed calibration and
holdout data before making a quality claim. Do not require a person to label hundreds
of articles before implementation work can proceed.

## Who supplies the labels

The product owner does not need to label the full corpus. Use two paid bilingual
reviewers or a university/newsroom research collaborator, then reserve owner time
for the pilot rule review and adjudication. Keep source text and annotation work
local or within the reviewers' approved environment; do not upload the feed snapshot
to a model service. A model suggestion counts as gold only after a reviewer confirms
it from the source evidence.

The [Turkish Story-Based News Dataset paper](https://doi.org/10.1109/ACCESS.2024.3435343)
describes 2,031 Turkish event articles grouped into 168 stories and checked by two
human validators. The repository investigation recorded that its institutional
record currently exposes no downloadable dataset files. Ask the authors for access
and reuse terms; do not assume article-text rights from the paper's license.

The [OG2021 multilingual Olympic news dataset](https://github.com/E3-JSI/dataset-OG2021)
can supplement regression checks. It is topic-limited, its public version omits
article bodies, and its license/use restrictions do not make it a substitute for
Sift's Turkish, multi-publisher target corpus.

## Exit artifacts

- Versioned article metadata and human `goldStoryID` assignments kept outside Git.
- Reviewer instructions, pilot feedback, disagreement/adjudication log, and a
  recorded false-merge bound.
- A reproducible holdout report with pairwise metrics, false merges, false splits,
  language-pair coverage, Translation readiness, and on-device latency.
- A go/no-go decision against M0. If labels or language coverage are missing, the
  milestone remains open; a feed list or unlabeled shadow preview alone cannot pass.
