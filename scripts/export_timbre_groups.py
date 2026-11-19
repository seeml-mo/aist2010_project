#!/usr/bin/env python3
"""Export the timbre-group analysis as JSON, without writing a chart.

Use this when you only want the grouping layer (for map shaping experiments,
visualisation, or a custom Godot loader). ``generate_chart.py --groups-json``
produces the same document alongside a chart, from a single analysis pass.

    python scripts/export_timbre_groups.py \
        --audio assets/voxel_30s.ogg \
        --output assets/analysis/voxel_30s_timbre.json
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parent))

import generate_chart  # noqa: E402
import timbre_export  # noqa: E402

DEFAULT_OUTPUT = Path("assets/analysis/timbre_groups.json")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Export MFCC/GMM timbre groups and their onset events to JSON."
    )
    parser.add_argument("--audio", type=Path, default=Path("assets/voxel_30s.ogg"))
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--stream", default=None, help="Audio path recorded in the document.")
    parser.add_argument("--title", default="Voxel Revolution")
    parser.add_argument("--groups", type=int, default=3)
    parser.add_argument("--components", type=int, default=8)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--sigma", type=float, default=1.5)
    parser.add_argument("--min-spacing", type=float, default=0.06)
    parser.add_argument("--delta", type=float, default=0.03)
    parser.add_argument("--map", default=None, help='Lane override, e.g. "0:1,1:2,2:0".')
    parser.add_argument("--mode", choices=["grouped", "pooled"], default="grouped")
    parser.add_argument("--difficulty", choices=["easy", "normal", "hard"], default="normal")
    parser.add_argument("--bpm-min", type=float, default=80.0)
    parser.add_argument("--bpm-max", type=float, default=180.0)
    args = parser.parse_args()

    if not args.audio.exists():
        parser.error(f"audio file not found: {args.audio}")

    # analyse() only reads the fields it needs; reuse the chart pipeline so the
    # exported groups are identical to the ones that shaped the chart.
    context = generate_chart.analyse(args)
    notes = generate_chart.select_notes(
        context["candidates"], context["features"].duration, args.difficulty,
        context["beats"], context["downbeats"],
    )

    document = timbre_export.build_document(
        context["features"], context["model"], context["descriptions"],
        context["lane_map"], context["bpm"], context["beats"], context["downbeats"],
        context["candidates"], notes,
        stream=args.stream or f"res://assets/{args.audio.name}",
        title=args.title,
        method=generate_chart.METHOD,
    )
    timbre_export.write_document(args.output, document)

    print(
        f"groups={document['analysis']['groups_requested']} "
        f"events={len(document['events'])} notes={len(notes)} "
        f"bpm={document['timing']['bpm']:.2f} "
        f"frames={len(document['timeline']['dominant'])}"
    )
    for group in document["groups"]:
        print(
            "  group {id} -> lane {lane} ({name}) weight={w:.2f} "
            "centroid={c:.0f}Hz percussive={p:.2f} features={o} notes={n}".format(
                id=group["id"], lane=group["lane"], name=group["lane_name"],
                w=group["weight"], c=group["centroid_hz"], p=group["percussive"],
                o=group["onset_count"], n=group["note_count"],
            )
        )
    print(f"wrote {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
