extends Area2D
## One timed attack target. Geometry and visuals belong to enemy.tscn.

signal defeated(event_index: int, timing_error: float)
signal missed(event_index: int)

var event_index := -1
var hit_time := 0.0
var resolved := false
var was_hit := false
var burst_age := 0.0

@onready var body: Polygon2D = $Body
@onready var core: Polygon2D = $Core
@onready var key_hint: Label = get_node_or_null("KeyHint")
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func try_hit(song_time: float, player_position: Vector2, player_bounds := Rect2(), attack_tip := Vector2.INF) -> bool:
	if resolved or not _has_attack_shape():
		return false
	# Horizontal reach spans center to fist. Vertical reach uses the body.
	var point := collision_shape.to_local(player_position)
	var rect := collision_shape.shape.get_rect()
	var tip_x := point.x
	if attack_tip.is_finite():
		tip_x = collision_shape.to_local(attack_tip).x
	if maxf(point.x, tip_x) < rect.position.x or minf(point.x, tip_x) > rect.end.x:
		return false
	var vertical_min := point.y
	var vertical_max := point.y
	if player_bounds.has_area():
		var local_bounds: Rect2 = collision_shape.global_transform.affine_inverse() * player_bounds
		vertical_min = local_bounds.position.y
		vertical_max = local_bounds.end.y
	if vertical_max < rect.position.y or vertical_min > rect.end.y:
		return false
	resolved = true
	was_hit = true
	body.hide()
	core.hide()
	if key_hint != null:
		key_hint.hide()
	defeated.emit(event_index, absf(song_time-hit_time))
	return true

func update_time(song_time: float, player_position: Vector2) -> void:
	# Entering the region is harmless. Only passing its right edge causes a miss.
	if not resolved and _has_attack_shape() and collision_shape.to_local(player_position).x > collision_shape.shape.get_rect().end.x:
		resolved = true
		body.color = Color("514153")
		if key_hint != null:
			key_hint.hide()
		missed.emit(event_index)
	burst_age = maxf(0, song_time-hit_time)
	queue_redraw()

func _has_attack_shape() -> bool:
	return not collision_shape.disabled and collision_shape.shape is RectangleShape2D

func _draw() -> void:
	if was_hit and burst_age < .3:
		draw_arc(Vector2.ZERO, 24+burst_age*70, 0, TAU, 28, Color("fff0ae"), 2)
