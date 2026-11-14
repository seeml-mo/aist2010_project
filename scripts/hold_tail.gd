@tool
extends Node2D

@export var color := Color("#df493e")
@export var preview_length := 125.0

const OUTLINE := Color("#263b40")

var tail_offset := Vector2.RIGHT * 125.0
var holding := false

func update_tail(offset: Vector2, active: bool) -> void:
	tail_offset = offset
	holding = active
	queue_redraw()

func _draw() -> void:
	var tip := Vector2.RIGHT * preview_length if Engine.is_editor_hint() else tail_offset
	var tint := color.lightened(0.38 if holding else 0.14)
	if tip.length_squared() > 0.25:
		draw_line(Vector2.ZERO, tip, OUTLINE, 11.0, true)
		draw_line(Vector2.ZERO, tip, tint, 7.0, true)
	draw_circle(tip, 10.0, OUTLINE, true, -1.0, true)
	draw_circle(tip, 7.5, tint, true, -1.0, true)
	draw_circle(tip, 3.0, Color("#fff7de"), true, -1.0, true)
