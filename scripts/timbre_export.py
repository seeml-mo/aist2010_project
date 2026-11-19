"""Serialise the timbre-group analysis to JSON for the game.

The chart JSON stays the gameplay contract: it holds the notes Godot judges.
This document is the layer underneath it - which timbre groups exist, which
gameplay lane each one feeds, and every onset each group contributed before
playability filtering. That is what "map shaping" actually consumes:

  * groups[i].lane      -> which lane the group drives (0 attack, 1 defend, 2 jump)
  * events[]            -> every candidate onset with its group and strength
  * timeline            -> per-frame dominant group, for visuals or debugging

The document is a sidecar. It lives outside assets/maps/ so the song menu,
which scans that folder for charts, never tries to load it as playable.
"""
from __future__ import annotations

import json
from pathlib import Path

LANE_LABELS = [
    "hats / snare",
    "vocal / melody / pads",
    "kick / bass",
]
VERSION = 1
KIND = "timbre_groups"


def _quantise(values, low: float = 0.0, high: float = 1.0) -> str:
    """Pack normalised floats into one digit each, 0-9."""
    if len(values) == 0:
        return ""
    span = max(high - low, 1e-9)
    digits = []
    for value in values:
        scaled = (float(value) - low) / span
        digits.append(str(int(round(min(max(scaled, 0.0), 1.0) * 9.0))))
    return "".join(digits)


def build_document(features, model, descriptions, lane_map, bpm: float,
                   beats, downbeats, candidates: list[dict], notes: list[dict],
                   stream: str, title: str, method: str) -> dict:
    """Assemble the timbre-group document from an analysis context."""
    frame_rate = 1.0 / float(features.times[1] - features.times[0]) \
        if features.times.size > 1 else 0.0

    onset_counts = {group: 0 for group in range(model.count)}
    for candidate in candidates:
        onset_counts[candidate["group"]] = onset_counts.get(candidate["group"], 0) + 1
    note_counts = {group: 0 for group in range(model.count)}
    for note in notes:
        group = next((g for g, lane in lane_map.items() if lane == note["lane"]), None)
        if group is not None:
            note_counts[group] = note_counts.get(group, 0) + 1

    groups = []
    for index, description in enumerate(descriptions):
        lane = int(lane_map.get(description["group"], -1))
        groups.append({
            "id": index,
            "lane": lane,
            "lane_name": LANE_LABELS[lane] if 0 <= lane < len(LANE_LABELS) else "",
            "weight": round(float(description["weight"]), 4),
            "centroid_hz": round(float(description["centroid"]), 1),
            "percussive": round(float(description["percussive"]), 4),
            "flatness": round(float(description["flatness"]), 5),
            "low": round(float(description["low_ratio"]), 4),
            "mid": round(float(description["mid_ratio"]), 4),
            "high": round(float(description["high_ratio"]), 4),
            "onset_count": int(onset_counts.get(index, 0)),
            "note_count": int(note_counts.get(index, 0)),
        })

    labels = model.labels()
    confidence = model.confidence()

    return {
        "version": VERSION,
        "kind": KIND,
        "audio": {
            "stream": stream,
            "title": title,
            "duration": round(float(features.duration), 3),
            "samplerate": int(features.samplerate),
            "frame": int(features.times.size),
            "hop": 512,
            "frame_rate": round(frame_rate, 4),
        },
        "timing": {
            "bpm": round(float(bpm), 3),
            "beats": [round(float(value), 5) for value in beats],
            "downbeats": [round(float(value), 5) for value in downbeats],
        },
        "groups": groups,
        "events": [
            {
                "time": round(float(candidate["time"]), 5),
                "group": int(candidate["group"]),
                "lane": int(candidate.get("lane", -1)),
                "strength": round(float(candidate["strength"]), 4),
            }
            for candidate in sorted(candidates, key=lambda item: item["time"])
        ],
        "timeline": {
            "rate": round(frame_rate, 4),
            "dominant": "".join(str(int(value)) for value in labels),
            "confidence": _quantise(confidence),
        },
        "analysis": {
            "method": method,
            "groups_requested": int(model.count),
            "iterations": int(model.iterations),
            "log_likelihood_per_frame": round(float(model.log_likelihood), 4),
        },
    }


def write_document(path: Path, document: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")


def dominant_group_at(document: dict, time: float) -> int:
    """Reference implementation of the lookup the GDScript loader mirrors."""
    timeline = document.get("timeline", {})
    rate = float(timeline.get("rate", 0.0))
    dominant = str(timeline.get("dominant", ""))
    if rate <= 0.0 or not dominant:
        return -1
    frame = int(round(time * rate))
    if frame < 0 or frame >= len(dominant):
        return -1
    return int(dominant[frame])
