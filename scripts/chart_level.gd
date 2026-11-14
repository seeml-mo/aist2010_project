extends RefCounted
## Evaluates input and note deadlines against song time.

const ACTIONS := [&"attack", &"defend", &"jump"]
const WINDOWS := [0.12, 0.12, 0.09]
const PERFECT_WINDOW := 0.055
const GOOD_HOLD_RATIO := 0.50
const PERFECT_HOLD_RATIO := 0.90
enum State { PENDING, HOLDING, HIT, MISSED }
enum Judgment { MISS, GOOD, PERFECT }
signal judged(lane: int, judgement: int)

var notes: Array
var perfects := 0
var goods := 0
var misses := 0

func _init(chart_notes: Array) -> void:
	notes = chart_notes.duplicate(true)
	for note in notes:
		note.state = State.PENDING

func press(lane: int, time: float) -> void:
	var best: Dictionary = {}
	var distance := float(WINDOWS[lane])
	for note in notes:
		var error := absf(float(note.time) - time)
		if note.lane == lane and note.state == State.PENDING and error <= distance:
			best = note
			distance = error
	if best.is_empty():
		return
	best.judgement = Judgment.PERFECT if distance <= PERFECT_WINDOW else Judgment.GOOD
	if best.has("duration"):
		best.pressed_at = time
		best.state = State.HOLDING
	else:
		_resolve(best, best.judgement, time)

func release(lane: int, time: float) -> void:
	for note in notes:
		if note.lane == lane and note.state == State.HOLDING:
			_resolve_hold(note, time)

func advance(time: float, held: Array[bool], ended: bool = false) -> void:
	for note in notes:
		if note.state == State.HOLDING:
			var complete := time >= float(note.time) + float(note.duration)
			if complete or not held[note.lane] or ended:
				_resolve_hold(note, time)
		elif note.state == State.PENDING and (ended or time > float(note.time) + WINDOWS[note.lane]):
			_resolve(note, Judgment.MISS, time)

func _resolve_hold(note: Dictionary, time: float) -> void:
	var start := float(note.time)
	var duration := float(note.duration)
	# Credit only the part of the hold within the charted interval.
	var held_start := maxf(start, float(note.pressed_at))
	var held_end := minf(time, start + duration)
	var ratio := clampf((held_end - held_start) / duration, 0.0, 1.0)
	var judgement := Judgment.MISS
	if ratio >= GOOD_HOLD_RATIO or is_equal_approx(ratio, GOOD_HOLD_RATIO):
		judgement = Judgment.GOOD
	if note.judgement == Judgment.PERFECT and (
		ratio >= PERFECT_HOLD_RATIO or is_equal_approx(ratio, PERFECT_HOLD_RATIO)
	):
		judgement = Judgment.PERFECT
	_resolve(note, judgement, time)

func _resolve(note: Dictionary, judgement: int, time: float) -> void:
	note.judgement = judgement
	note.state = State.MISSED if judgement == Judgment.MISS else State.HIT
	note.resolved_at = time
	match judgement:
		Judgment.PERFECT:
			perfects += 1
		Judgment.GOOD:
			goods += 1
		Judgment.MISS:
			misses += 1
	judged.emit(note.lane, judgement)

func score() -> int:
	return perfects * 1000 + goods * 600

func accuracy() -> float:
	return float(score()) / float(notes.size() * 1000) if not notes.is_empty() else 0.0
