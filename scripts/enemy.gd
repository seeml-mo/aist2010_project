extends Area2D
## One timed attack target. Geometry and visuals belong to enemy.tscn.

signal defeated(event_index: int, timing_error: float)
signal missed(event_index: int)

@export var hit_window := 0.16
@export var vertical_reach := 45.0

var event_index := -1
var hit_time := 0.0
var resolved := false
var was_hit := false
var burst_age := 0.0

@onready var body: Polygon2D = $Body
@onready var core: Polygon2D = $Core
@onready var key_hint: Label = $KeyHint

func try_hit(song_time: float, player_position: Vector2) -> bool:
	if resolved or absf(song_time-hit_time) > hit_window:
		return false
	if absf(player_position.y-(global_position.y+4)) >= vertical_reach:
		return false
	resolved = true
	was_hit = true
	body.hide()
	core.hide()
	key_hint.hide()
	defeated.emit(event_index, absf(song_time-hit_time))
	return true

func update_time(song_time: float) -> void:
	if not resolved and song_time > hit_time+hit_window:
		resolved = true
		body.color = Color("514153")
		key_hint.hide()
		missed.emit(event_index)
	burst_age = maxf(0, song_time-hit_time)
	queue_redraw()

func _draw() -> void:
	if was_hit and burst_age < .3:
		draw_arc(Vector2.ZERO, 24+burst_age*70, 0, TAU, 28, Color("fff0ae"), 2)
