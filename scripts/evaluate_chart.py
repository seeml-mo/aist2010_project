#!/usr/bin/env python3
"""Offline evaluation for the timbre-grouped chart pipeline.

Reports the measurements the proposal lists:

  * chart validity and playability (the same rules Godot's chart_loader applies)
  * pooled vs grouped onset detection
  * temporal smoothing on vs off
  * label stability across GMM seeds (adjusted Rand index)
  * event diversity and note/beat F1 when a reference chart is supplied

No ground-truth annotation ships with the project, so F1 is only printed when
--reference points at a chart. Everything else is intrinsic.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))

import audio_features as features_lib  # noqa: E402
import timbre_grouping  # noqa: E402

CANONICAL_LANES = ["attack", "defend", "jump"]


def load_chart(path: Path) -> dict:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def validate_chart(data: dict) -> list[str]:
    """Mirror of chart_loader.gd so a bad chart fails here, not in Godot."""
    problems: list[str] = []
    if int(data.get("version", -1)) != 2:
        problems.append("version must be 2")

    audio = data.get("audio")
    if not isinstance(audio, dict) or not str(audio.get("stream", "")):
        problems.append("audio.stream is missing")

    chart = data.get("chart")
    if not isinstance(chart, dict) or not isinstance(chart.get("notes"), list):
        problems.append("chart.notes is missing")
        return problems

    lanes = chart.get("lanes", CANONICAL_LANES)
    previous = -1.0
    for index, note in enumerate(chart["notes"]):
        if not isinstance(note, dict) or "time" not in note or "lane" not in note:
            problems.append(f"note {index}: missing time/lane")
            continue
        note_time, lane = float(note["time"]), int(note["lane"])
        if note_time < 0:
            problems.append(f"note {index}: negative time")
        if lane < 0 or lane >= len(lanes) or lanes[lane] not in CANONICAL_LANES:
            problems.append(f"note {index}: lane out of range")
            continue
        if lanes[lane] == "jump" and "duration" in note:
            problems.append(f"note {index}: hold on the jump lane")
        if "duration" in note and float(note["duration"]) <= 0:
            problems.append(f"note {index}: non-positive hold")
        if note_time < previous:
            problems.append(f"note {index}: notes not sorted")
        previous = note_time
    return problems


def playability(notes: list[dict], duration: float) -> dict:
    times = np.array([float(note["time"]) for note in notes])
    lanes = np.array([int(note["lane"]) for note in notes])
    hops = np.diff(times) if times.size > 1 else np.zeros(1)

    per_lane = []
    for lane in range(3):
        lane_times = times[lanes == lane]
        gaps = np.diff(lane_times) if lane_times.size > 1 else np.zeros(0)
        per_lane.append({
            "lane": CANONICAL_LANES[lane],
            "count": int(lane_times.size),
            "min_gap": float(gaps.min()) if gaps.size else 0.0,
        })

    worst_window = 0
    for start in range(times.size):
        inside = int(np.searchsorted(times, times[start] + 2.0, side="right") - start)
        worst_window = max(worst_window, inside)

    return {
        "notes": int(times.size),
        "notes_per_second": float(times.size / duration) if duration > 0 else 0.0,
        "first_note": float(times.min()) if times.size else 0.0,
        "last_note": float(times.max()) if times.size else 0.0,
        "min_gap": float(hops.min()) if hops.size else 0.0,
        "mean_gap": float(hops.mean()) if hops.size else 0.0,
        "max_notes_in_2s": worst_window,
        "per_lane": per_lane,
    }


def adjusted_rand(a: np.ndarray, b: np.ndarray) -> float:
    """Adjusted Rand index between two label vectors."""
    n = a.size
    if n == 0:
        return 1.0
    contingency = np.zeros((int(a.max()) + 1, int(b.max()) + 1), dtype=np.int64)
    np.add.at(contingency, (a, b), 1)

    def pairs(values: np.ndarray) -> float:
        values = values.astype(np.float64)
        return float((values * (values - 1.0) / 2.0).sum())

    sum_cells = pairs(contingency.ravel())
    sum_rows = pairs(contingency.sum(axis=1))
    sum_cols = pairs(contingency.sum(axis=0))
    total = n * (n - 1.0) / 2.0
    expected = sum_rows * sum_cols / total if total else 0.0
    maximum = 0.5 * (sum_rows + sum_cols)
    if maximum == expected:
        return 1.0
    return float((sum_cells - expected) / (maximum - expected))


def label_stability(matrix: np.ndarray, groups: int, seeds: list[int]) -> dict:
    labels = [timbre_grouping.fit_groups(matrix, groups=groups, seed=seed).labels()
              for seed in seeds]
    scores = [
        adjusted_rand(labels[i], labels[j])
        for i in range(len(labels))
        for j in range(i + 1, len(labels))
    ]
    return {
        "pairs": len(scores),
        "mean_ari": float(np.mean(scores)) if scores else 1.0,
        "min_ari": float(np.min(scores)) if scores else 1.0,
        "max_ari": float(np.max(scores)) if scores else 1.0,
    }


def entropy(counts: np.ndarray) -> float:
    total = counts.sum()
    if total <= 0:
        return 0.0
    probabilities = counts[counts > 0] / total
    return float(-(probabilities * np.log2(probabilities)).sum())


def onset_f1(predicted: np.ndarray, reference: np.ndarray, tolerance: float) -> dict:
    if predicted.size == 0 or reference.size == 0:
        return {"precision": 0.0, "recall": 0.0, "f1": 0.0}

    matched_reference = np.zeros(reference.size, dtype=bool)
    hits = 0
    for time in predicted:
        distances = np.abs(reference - time)
        distances[matched_reference] = np.inf
        index = int(np.argmin(distances))
        if distances[index] <= tolerance:
            matched_reference[index] = True
            hits += 1

    precision = hits / predicted.size
    recall = hits / reference.size
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
    return {"precision": precision, "recall": recall, "f1": f1}


def main() -> int:
    parser = argparse.ArgumentParser(description="Evaluate a generated chart.")
    parser.add_argument("--chart", type=Path, default=Path("assets/maps/chart_timbre.json"))
    parser.add_argument("--audio", type=Path, default=Path("assets/voxel_30s.ogg"))
    parser.add_argument("--reference", type=Path, default=None,
                        help="Optional reference chart for note F1.")
    parser.add_argument("--groups", type=int, default=3)
    parser.add_argument("--components", type=int, default=8)
    parser.add_argument("--tolerance", type=float, default=0.05)
    args = parser.parse_args()

    chart = load_chart(args.chart)
    problems = validate_chart(chart)
    print(f"chart: {args.chart}")
    print("  validity:", "PASS" if not problems else "FAIL")
    for problem in problems[:8]:
        print("   -", problem)

    notes = chart["chart"]["notes"]
    duration = float(chart["audio"].get("duration", 0.0))
    stats = playability(notes, duration)
    print("  notes=%d  nps=%.2f  min_gap=%.3fs  mean_gap=%.3fs  worst_2s=%d"
          % (stats["notes"], stats["notes_per_second"], stats["min_gap"],
             stats["mean_gap"], stats["max_notes_in_2s"]))
    print("  first=%.2fs last=%.2fs" % (stats["first_note"], stats["last_note"]))
    for lane in stats["per_lane"]:
        print("   lane %-6s count=%3d min_gap=%.3fs"
              % (lane["lane"], lane["count"], lane["min_gap"]))

    holds = sum(1 for note in notes if "duration" in note)
    lane_counts = np.zeros(3, dtype=int)
    for note in notes:
        lane_counts[int(note["lane"])] += 1
    print("  holds=%d  lane_entropy=%.2f bits (max %.2f)"
          % (holds, entropy(lane_counts), np.log2(3)))

    if args.reference is not None:
        reference = load_chart(args.reference)
        predicted_times = np.array([float(note["time"]) for note in notes])
        reference_times = np.array([float(n["time"]) for n in reference["chart"]["notes"]])
        scores = onset_f1(predicted_times, reference_times, args.tolerance)
        print("  note F1 vs %s (tol %.2fs): P=%.3f R=%.3f F1=%.3f"
              % (args.reference.name, args.tolerance, scores["precision"],
                 scores["recall"], scores["f1"]))

    if args.audio.exists():
        features = features_lib.extract(args.audio)
        matrix = features_lib.whiten(features_lib.grouping_matrix(features), args.components)
        model = timbre_grouping.fit_groups(matrix, groups=args.groups, seed=0)

        grouped = timbre_grouping.detect_grouped(features, model)
        pooled = timbre_grouping.detect_pooled(features, model)
        plain = timbre_grouping.detect_grouped(features, model, sigma=0.0)
        print("\nablation (onset candidates, before playability filtering)")
        print("  grouped  sigma=1.5: %4d  per-group=%s"
              % (len(grouped), np.bincount([c["group"] for c in grouped],
                                           minlength=args.groups).tolist()))
        print("  grouped  sigma=0.0: %4d" % len(plain))
        print("  pooled   (baseline): %4d  per-group=%s"
              % (len(pooled), np.bincount([c["group"] for c in pooled],
                                          minlength=args.groups).tolist()))

        grouped_times = np.array(sorted(c["time"] for c in grouped))
        pooled_times = np.array(sorted(c["time"] for c in pooled))
        covered = onset_f1(grouped_times, pooled_times, args.tolerance)
        print("  grouped covers pooled peaks: P=%.3f R=%.3f F1=%.3f"
              % (covered["precision"], covered["recall"], covered["f1"]))

        stability = label_stability(matrix, args.groups, [0, 1, 2, 3, 4])
        print("\nlabel stability over %d seed pairs: mean ARI=%.3f (min %.3f, max %.3f)"
              % (stability["pairs"], stability["mean_ari"],
                 stability["min_ari"], stability["max_ari"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
