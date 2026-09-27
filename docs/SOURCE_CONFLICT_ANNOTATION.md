# Source diversity and claim conflict protocol

This protocol extends the M0 article-clustering labels with a second, independent
annotation layer for briefings. Clustering answers **which coverage reports the same
concrete event**. Conflict analysis answers **what claims each source makes and how
those claims relate**. Do not make one label stand in for the other.

## Keep event clusters separate from issue threads

- `goldStoryID` means the same concrete occurrence, announcement, decision, incident,
  or follow-up event. Different articles about one announcement share an ID even when
  headlines or emphasis differ.
- `issueID` may link several event clusters into a longer-running subject or causal
  thread. It helps build a briefing timeline; it must not cause articles from distinct
  events to be merged into one story cluster.
- Syndicated copies keep the same event ID, but share an origin ID when they repeat
  one wire report, press release, interview, or official statement. Five publishers
  repeating one speaker is five publications, not five independent confirmations.

## Describe claims before comparing them

For each material assertion, retain:

- the article and exact source link;
- the speaker or document making the assertion;
- the claim as written or a close, source-linked paraphrase;
- whether it is a reported event, official statement, allegation, denial, eyewitness
  account, analysis/opinion, forecast, or later correction;
- the claim's subject, action, amount, time period, and scope when available;
- whether the reporting is direct, attributed, syndicated, or unclear.

Do not label a claim true because a prominent outlet reports it. Do not assign an
outlet-level political label and use it as a truth score; annotate the article's
assertions and attribution. Preserve uncertainty and leave unsupported fields empty.

## Relationship labels

Use one of these labels between claims or coverage items:

| Label | Use when |
|---|---|
| `direct_conflict_candidate` | Claims cannot both be true about the same subject, time, proposition, and scope. Keep both attributed; this is a detected disagreement, not a verdict. |
| `different_scope_compatible` | Claims appear opposed but answer different questions, such as system-level risk versus one person's loss of access. |
| `different_time_or_update` | A later report changes, narrows, or corrects an earlier state. Preserve the timeline. |
| `allegation_and_response` | One source reports an allegation and another carries a response. A response is not a rebuttal unless it addresses the same proposition. |
| `framing_or_emphasis` | Sources select different language, context, or consequences while the stated event is compatible. |
| `syndicated_repeat` | Multiple outlets repeat the same underlying source or wire copy. |
| `insufficient_evidence` | Feed excerpts do not support a safe comparison. Do not synthesize a conflict. |

Only `direct_conflict_candidate` should generate a “sources disagree” treatment, and
only after a review step verifies that the claims share the same subject, time,
proposition, and scope. Otherwise show the distinction precisely: “different scope,”
“later update,” or “one source reports an allegation.” The app never decides which
side is true from outlet identity or article count.

## Product treatment

1. Cluster source articles by concrete event and retain the related `issueID` timeline.
2. Extract source-linked claims locally. Keep article text and model inputs on device.
3. Compare claim pairs and show both attributions, publication times, and source links.
4. Show a material disagreement as unresolved unless primary evidence settles it; if
   evidence is unavailable, say so.
5. If Foundation Models are unavailable, keep the event/source list usable and omit
   the generated comparison. Do not block conventional RSS reading.

The local agent-labeled RSS case used to refine this protocol is kept in ignored
`tools/local/sift-m0-source-conflict-cases.json`; its annotations are provisional and
must not be described as reviewed fact-checks or M0 gold labels.
