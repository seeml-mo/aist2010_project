extends RefCounted
## Evaluates input and note deadlines against song time.

const ACTIONS := [&"attack", &"defend", &"jump"]
const WINDOWS := [0.12, 0.12, 0.09]
const PERFECT_WINDOW := 0.055
enum State { PENDING, HOLDING, HIT, MISSED }
signal judged(lane: int, hit: bool, perfect: bool)

var notes: Array
var health := 5
var hits := 0
var misses := 0

func _init(chart_notes: Array) -> void:
	notes = chart_notes.duplicate(true)
	for note in notes:
		note.state = State.PENDING

func press(lane: int, time: float) -> void:
	if health <= 0:
		return
	var best: Dictionary = {}
	var distance := float(WINDOWS[lane])
	for note in notes:
		var error := absf(float(note.time) - time)
		if note.lane == lane and note.state == State.PENDING and error <= distance:
			best = note
			distance = error
	if best.is_empty():
		return
	best.perfect = distance <= PERFECT_WINDOW
	if best.has("duration"):
		best.state = State.HOLDING
	else:
		_resolve(best, true, time)

func advance(time: float, held: Array[bool], ended: bool = false) -> void:
	for note in notes:
		if health <= 0:
			break
		if note.state == State.HOLDING:
			var complete := time >= float(note.time) + float(note.duration)
			if complete or not held[note.lane] or ended:
				_resolve(note, complete and held[note.lane], time)
		elif note.state == State.PENDING and (ended or time > float(note.time) + WINDOWS[note.lane]):
			_resolve(note, false, time)

func _resolve(note: Dictionary, hit: bool, time: float) -> void:
	note.state = State.HIT if hit else State.MISSED
	note.resolved_at = time
	if hit:
		hits += 1
	else:
		misses += 1
		health -= 1
	judged.emit(note.lane, hit, hit and note.get("perfect", false))
