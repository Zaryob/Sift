#!/usr/bin/env python3
"""Evaluate predicted story clusters against manually assigned gold story IDs.

Input is UTF-8 JSON Lines, one object per article, with articleID, goldStoryID,
and predictedClusterID string fields. See docs/STORY_CLUSTERING_ANNOTATION_GUIDE.md.
This tool measures labels; it does not create or validate human annotations.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


REQUIRED_FIELDS = ("articleID", "goldStoryID", "predictedClusterID")


class InputError(Exception):
    pass


def load_records(path: Path) -> list[dict[str, str]]:
    records: list[dict[str, str]] = []
    seen_article_ids: dict[str, int] = {}
    problems: list[str] = []

    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise InputError(f"Cannot read input file {path}: {exc}") from exc

    for line_number, raw_line in enumerate(lines, start=1):
        if not raw_line.strip():
            continue
        try:
            item: Any = json.loads(raw_line)
        except json.JSONDecodeError as exc:
            problems.append(f"line {line_number}: invalid JSON ({exc.msg})")
            continue
        if not isinstance(item, dict):
            problems.append(f"line {line_number}: expected a JSON object")
            continue

        normalized: dict[str, str] = {}
        for field in REQUIRED_FIELDS:
            value = item.get(field)
            if not isinstance(value, str) or not value.strip():
                problems.append(f"line {line_number}: missing or empty {field}")
            else:
                normalized[field] = value.strip()

        article_id = normalized.get("articleID")
        if article_id:
            if article_id in seen_article_ids:
                problems.append(
                    f"line {line_number}: duplicate articleID {article_id!r} "
                    f"(first seen on line {seen_article_ids[article_id]})"
                )
            else:
                seen_article_ids[article_id] = line_number

        if len(normalized) == len(REQUIRED_FIELDS):
            language = item.get("language", "und")
            if not isinstance(language, str) or not language.strip():
                problems.append(f"line {line_number}: language must be a non-empty string when provided")
            else:
                normalized["language"] = language.strip().lower()
            records.append(normalized)

    if problems:
        raise InputError("Input validation failed:\n- " + "\n- ".join(problems))
    if not records:
        raise InputError("Input contains no article records.")
    return records


def ratio(numerator: int | float, denominator: int | float) -> float | None:
    return numerator / denominator if denominator else None


def rounded(value: float | None) -> float | None:
    return round(value, 6) if value is not None and math.isfinite(value) else None


def pairwise_metrics(tp: int, fp: int, fn: int) -> dict[str, float | None]:
    precision = ratio(tp, tp + fp)
    recall = ratio(tp, tp + fn)
    if precision is not None and recall is not None and precision + recall:
        f1 = 2 * precision * recall / (precision + recall)
    else:
        f1 = 0.0 if precision == 0 or recall == 0 else None
    return {
        "precision": rounded(precision),
        "recall": rounded(recall),
        "f1": rounded(f1),
    }


def evaluate(records: list[dict[str, str]]) -> dict[str, Any]:
    predicted_members: dict[str, list[dict[str, str]]] = defaultdict(list)
    gold_members: dict[str, list[dict[str, str]]] = defaultdict(list)
    for record in records:
        predicted_members[record["predictedClusterID"]].append(record)
        gold_members[record["goldStoryID"]].append(record)

    tp = fp = fn = 0
    for members in predicted_members.values():
        counts = Counter(item["goldStoryID"] for item in members)
        tp += sum(n * (n - 1) // 2 for n in counts.values())
        total_pairs = len(members) * (len(members) - 1) // 2
        fp += total_pairs - sum(n * (n - 1) // 2 for n in counts.values())
    for members in gold_members.values():
        counts = Counter(item["predictedClusterID"] for item in members)
        total_pairs = len(members) * (len(members) - 1) // 2
        fn += total_pairs - sum(n * (n - 1) // 2 for n in counts.values())

    per_language_pair: dict[tuple[str, str], Counter[str]] = defaultdict(Counter)
    for left_index, left in enumerate(records):
        for right in records[left_index + 1 :]:
            language_pair = tuple(sorted((left.get("language", "und"), right.get("language", "und"))))
            counts = per_language_pair[language_pair]
            same_gold = left["goldStoryID"] == right["goldStoryID"]
            same_prediction = left["predictedClusterID"] == right["predictedClusterID"]
            counts["articlePairs"] += 1
            if same_gold and same_prediction:
                counts["tp"] += 1
            elif same_prediction:
                counts["fp"] += 1
            elif same_gold:
                counts["fn"] += 1

    language_pair_report = []
    for language_pair, counts in sorted(per_language_pair.items()):
        language_pair_report.append(
            {
                "languagePair": "|".join(language_pair),
                "articlePairs": counts["articlePairs"],
                "scoredPairs": counts["tp"] + counts["fp"] + counts["fn"],
                "counts": {"truePositivePairs": counts["tp"], "falsePositivePairs": counts["fp"], "falseNegativePairs": counts["fn"]},
                "pairwise": pairwise_metrics(counts["tp"], counts["fp"], counts["fn"]),
            }
        )

    contaminated: list[dict[str, Any]] = []
    contaminated_article_count = 0
    for cluster_id, members in sorted(predicted_members.items()):
        counts = Counter(item["goldStoryID"] for item in members)
        majority_size = max(counts.values())
        outside_majority = len(members) - majority_size
        contaminated_article_count += outside_majority
        if len(counts) > 1:
            contaminated.append(
                {
                    "predictedClusterID": cluster_id,
                    "articleCount": len(members),
                    "goldStoryCount": len(counts),
                    "goldStoryIDs": sorted(counts),
                    "contaminationRate": rounded(outside_majority / len(members)),
                }
            )

    split_gold = sorted(
        story_id
        for story_id, members in gold_members.items()
        if len({item["predictedClusterID"] for item in members}) > 1
    )
    predicted_pair_count = tp + fp

    return {
        "schemaVersion": 1,
        "input": {"articleCount": len(records)},
        "counts": {
            "truePositivePairs": tp,
            "falsePositivePairs": fp,
            "falseNegativePairs": fn,
            "predictedSameStoryPairs": predicted_pair_count,
            "goldSameStoryPairs": tp + fn,
            "predictedClusterCount": len(predicted_members),
            "goldStoryCount": len(gold_members),
        },
        "pairwise": {
            **pairwise_metrics(tp, fp, fn),
        },
        "perLanguagePair": language_pair_report,
        "falseMerge": {
            "definition": "fraction of predicted clusters containing articles from more than one goldStoryID",
            "contaminatedClusterCount": len(contaminated),
            "predictedClusterCount": len(predicted_members),
            "rate": rounded(ratio(len(contaminated), len(predicted_members))),
            "falsePositivePairRate": rounded(ratio(fp, predicted_pair_count)),
        },
        "falseSplits": {
            "definition": "gold stories whose articles were assigned to more than one predictedClusterID",
            "splitGoldStoryCount": len(split_gold),
            "goldStoryCount": len(gold_members),
            "rate": rounded(ratio(len(split_gold), len(gold_members))),
            "goldStoryIDs": split_gold,
        },
        "clusterContamination": {
            "definition": "article-weighted share outside each predicted cluster's majority goldStoryID",
            "contaminatedArticleCount": contaminated_article_count,
            "articleCount": len(records),
            "rate": rounded(ratio(contaminated_article_count, len(records))),
            "clusters": contaminated,
        },
    }


def percent(value: float | None) -> str:
    return "n/a" if value is None else f"{value * 100:.2f}%"


def human_summary(report: dict[str, Any]) -> str:
    counts = report["counts"]
    pairwise = report["pairwise"]
    false_merge = report["falseMerge"]
    false_splits = report["falseSplits"]
    contamination = report["clusterContamination"]
    return "\n".join(
        [
            "Story clustering evaluation",
            f"Articles: {report['input']['articleCount']} | predicted clusters: {counts['predictedClusterCount']} | gold stories: {counts['goldStoryCount']}",
            f"Pairwise precision: {percent(pairwise['precision'])} | recall: {percent(pairwise['recall'])} | F1: {percent(pairwise['f1'])}",
            f"Pair counts: TP {counts['truePositivePairs']} | FP {counts['falsePositivePairs']} | FN {counts['falseNegativePairs']}",
            "Language-pair F1: " + (
                ", ".join(
                    f"{item['languagePair']} {percent(item['pairwise']['f1'])}"
                    for item in report["perLanguagePair"]
                ) or "n/a"
            ),
            f"False-merge rate (clusters mixing gold stories): {percent(false_merge['rate'])} ({false_merge['contaminatedClusterCount']}/{false_merge['predictedClusterCount']})",
            f"False-positive pair rate: {percent(false_merge['falsePositivePairRate'])}",
            f"False splits (gold stories split across predictions): {false_splits['splitGoldStoryCount']}/{false_splits['goldStoryCount']} ({percent(false_splits['rate'])})",
            f"Cluster contamination (articles outside cluster majority story): {contamination['contaminatedArticleCount']}/{contamination['articleCount']} ({percent(contamination['rate'])})",
        ]
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="UTF-8 JSONL article records")
    parser.add_argument(
        "--json-output",
        type=Path,
        help="also write machine-readable report JSON to this path",
    )
    args = parser.parse_args()

    try:
        report = evaluate(load_records(args.input))
    except InputError as exc:
        print(str(exc), file=sys.stderr)
        return 2

    if args.json_output:
        try:
            args.json_output.write_text(
                json.dumps(report, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )
        except OSError as exc:
            print(f"Cannot write JSON report {args.json_output}: {exc}", file=sys.stderr)
            return 2

    print(human_summary(report))
    print("\nMachine-readable JSON:")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
