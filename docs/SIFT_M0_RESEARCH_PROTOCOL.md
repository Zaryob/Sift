# Sift M0 user research protocol

This protocol collects the user evidence required by [`SIFT_PRODUCT_ROADMAP.md`](SIFT_PRODUCT_ROADMAP.md). It is a study plan, not a report of completed research. Do not write participant findings until sessions and diaries have actually happened.

## Research questions

1. How do people who manage a high volume of work-related news decide what deserves attention today?
2. How do multi-source RSS readers move between feeds, recognize duplicate coverage, and follow a developing story?
3. When does a short briefing save time, and when do readers need the original article or several source perspectives?
4. Which events warrant an interruption, at what time, and how do people want to control it?
5. Which parts of a grouped-story and briefing experience should remain optional beside ordinary feed reading?

Treat these as open questions. Do not lead participants toward AI summaries, clustering, or notifications as the expected answer.

## Participants and schedule

- Recruit at least 6 people who regularly make or support executive/organizational decisions using news, and at least 6 people who regularly follow news across multiple RSS/news sources. A person can qualify for both groups; record both qualifications. Aim for 12 distinct participants when feasible so the two use cases are not represented by the same small set.
- Exclude team members who already know the roadmap from the primary sample. Record relevant role, news sources/tools, daily reading frequency, and accessibility/language needs without collecting employer-confidential information.
- Run one 25–35 minute session per participant, followed by a 7-day diary. Ask participants to record actual news-reading moments, including days when they did not use a briefing or notification.
- Use participant IDs (P01…) in notes. Get explicit consent before recording; recording is optional. Do not collect account credentials, private feed URLs, or article contents unless the participant chooses to share them and the study owner has approved storage.

## Session guide (25–35 minutes)

### Opening (3 minutes)

Explain that this is research about news habits, not a test of the participant. Ask them to describe a recent day when news affected a decision or changed what they did. Ask permission for notes and separately for any recording.

### Recent behavior (8–10 minutes)

Ask for concrete examples from the last seven days:

- “Walk me through the last time you checked news. What did you open first, and what happened next?”
- “Tell me about a story you followed across more than one source. How did you decide it was the same story?”
- “What do you do when two sources disagree or a story changes during the day?”
- “What did you skip, save, or come back to? What made that useful or not useful?”
- “When did a notification help you? When did one interrupt you without helping?”

Prefer “show me what you did” over opinions about hypothetical features. Do not infer disinterest from a skipped story or dismissed alert.

### Short task (8–10 minutes)

Ask the participant to use their own news workflow (or a neutral, researcher-provided set of public article links if they do not have one):

1. Find the most consequential story from a small set of recent items and explain the choice.
2. Find whether multiple items cover the same event; explain which evidence made them group together.
3. State what changed since the previous update and open the source they would rely on.
4. Choose which, if any, item would justify an immediate alert and explain why.

Observe time, backtracking, source-switching, uncertainty, and whether the participant asks for more context. Do not present a generated summary as factual study material. If a static concept sketch is used, label it as hypothetical and record the response separately from observed behavior.

### Preferences and closing (5–8 minutes)

- “If you received a short briefing, when would you read it and what would make you trust it enough to act?”
- “Which sources or topics would you want to control directly?”
- “What should the app do when it cannot group a story confidently or cannot access the full article?”
- “What controls would you expect for briefing times, interruptions, and anything the app learns about your interests?”

Ask the participant to correct the researcher's summary of their needs. End by explaining the diary and how to stop or delete their contribution.

## Seven-day diary template

One entry per meaningful news-checking moment; a “nothing today” entry is useful too.

```text
Participant ID:
Date and approximate time:
What prompted you to check news?
Which app, feeds, sites, or sources did you use?
What story or decision were you trying to understand?
Did you see the same event in more than one source? How did you tell?
What was the most useful new fact or change?
Did you open a source article, save something, or share it? Why?
Did a notification arrive? Helpful, irrelevant, late, or disruptive?
Would a briefing have helped at this moment? What should it include?
What did you still need to look up afterward?
Anything else / “no news use today”:
```

At the end of the week, conduct a 10–15 minute follow-up: review two or three entries chosen by the participant, ask what they remembered, and clarify any changes in notification or briefing preferences.

## Synthesis and evidence handling

- Keep observed behavior, participant statements, and researcher interpretation in separate columns.
- Use a simple evidence table: participant ID, segment qualifications, observed task, direct paraphrase, need/job, current workaround, failure/risk, and confidence (`single`, `repeated`, `contradictory`). Record counterexamples, not only repeated themes.
- Compare executive and multi-source-reader patterns, then note where the same person needs both. Do not turn a preference from one participant into a product default.
- Summarize the diary with counts and examples (for example, when briefings would have been useful, what prompted cross-source reading, and which interruptions were unwanted). Do not claim causality from a one-week diary.
- Store notes in an access-controlled location chosen by the study owner. Keep the participant-ID key separate from notes; remove raw recordings after transcription/verification according to the consented retention period.
- The study owner records limitations, missing segments, and a product decision for each major finding. The roadmap's M0 exit artifact is incomplete until actual sessions and diaries are summarized alongside the clustering benchmark.
