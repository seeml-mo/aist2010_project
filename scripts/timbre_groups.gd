extends RefCounted
## Loads the timbre-group document written by scripts/export_timbre_groups.py
## (or by generate_chart.py --groups-json).
##
## The chart JSON stays the gameplay contract: it holds the notes Godot judges.
## This sidecar exposes the layer underneath it - which timbre groups exist,
## which lane each group drives, every onset each group contributed, and the
## per-frame dominant group - so gameplay or visuals can consult the analysis
## directly (enemy tint per group, background pulses per timbre, debug overlays).
##
## Usage:
##   const Timbre = preload("res://scripts/timbre_groups.gd")
##   var result := Timbre.load_document("res://assets/analysis/timbre_groups.json")
##   if result.ok:
##       var group := Timbre.group_for_lane(result.data, 2)
##       var lane_events := Timbre.events_for_lane(result.data, 2)

const VERSION := 1
const KIND := "timbre_groups"
const LANES := ["attack", "defend", "jump"]

static func load_document(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "Timbre document not found: " + path, "data": {}}

	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {"ok": false, "error": "Empty timbre document: " + path, "data": {}}

	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		return {"ok": false, "error": "Invalid JSON: " + path, "data": {}}

	var data: Dictionary = parsed
	if int(data.get("version", -1)) != VERSION:
		return {"ok": false, "error": "Unsupported timbre document version", "data": {}}
	if str(data.get("kind", "")) != KIND:
		return {"ok": false, "error": "Not a timbre group document", "data": {}}

	var raw_groups = data.get("groups")
	if not raw_groups is Array or raw_groups.is_empty():
		return {"ok": false, "error": "groups is missing", "data": {}}

	var groups: Array = []
	for raw in raw_groups:
		if not raw is Dictionary or not raw.has("id") or not raw.has("lane"):
			continue
		var lane := int(raw.lane)
		if lane < 0 or lane >= LANES.size():
			continue
		var group: Dictionary = raw.duplicate(true)
		group["id"] = int(raw.id)
		group["lane"] = lane
		group["lane_name"] = str(raw.get("lane_name", LANES[lane]))
		# JSON numbers arrive as floats; counts and weights are used arithmetically.
		group["weight"] = float(raw.get("weight", 0.0))
		group["centroid_hz"] = float(raw.get("centroid_hz", 0.0))
		group["percussive"] = float(raw.get("percussive", 0.0))
		group["flatness"] = float(raw.get("flatness", 0.0))
		group["onset_count"] = int(raw.get("onset_count", 0))
		group["note_count"] = int(raw.get("note_count", 0))
		groups.append(group)
	if groups.is_empty():
		return {"ok": false, "error": "No valid groups", "data": {}}

	var events: Array = []
	var raw_events = data.get("events", [])
	if raw_events is Array:
		for raw in raw_events:
			if not raw is Dictionary or not raw.has("time") or not raw.has("group"):
				continue
			events.append({
				"time": float(raw.time),
				"group": int(raw.group),
				"lane": int(raw.get("lane", -1)),
				"strength": float(raw.get("strength", 0.0)),
			})
	events.sort_custom(func(a, b): return float(a.time) < float(b.time))

	var timeline = data.get("timeline", {})
	if not timeline is Dictionary:
		timeline = {}

	var output: Dictionary = data.duplicate(true)
	output["groups"] = groups
	output["events"] = events
	output["timeline"] = timeline
	return {"ok": true, "error": "", "data": output}

## Dominant timbre group at a song time, or -1 when outside the timeline.
static func dominant_group_at(document: Dictionary, time: float) -> int:
	var timeline = document.get("timeline", {})
	if not timeline is Dictionary:
		return -1
	var rate := float(timeline.get("rate", 0.0))
	var dominant := str(timeline.get("dominant", ""))
	if rate <= 0.0 or dominant.is_empty():
		return -1
	var frame := int(round(time * rate))
	if frame < 0 or frame >= dominant.length():
		return -1
	return int(dominant[frame])

static func group_for_lane(document: Dictionary, lane: int) -> Dictionary:
	var groups = document.get("groups", [])
	if groups is Array:
		for group in groups:
			if int(group.lane) == lane:
				return group
	return {}

static func events_for_lane(document: Dictionary, lane: int) -> Array:
	var result: Array = []
	var events = document.get("events", [])
	if events is Array:
		for event in events:
			if int(event.lane) == lane:
				result.append(event)
	return result
