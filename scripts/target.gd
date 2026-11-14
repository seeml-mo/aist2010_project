@tool
extends Node2D
## Target reticle drawn as four spinning quarter arcs with a fixed center dot.

@export var ring_color := Color(0.875, 0.286, 0.243):
	set(value):
		ring_color = value
		queue_redraw()
@export var radius := 20.9:
	set(value):
		radius = value
		queue_redraw()
@export var line_width := 2.5:
	set(value):
		line_width = value
		queue_redraw()
@export var center_radius := 2.8:
	set(value):
		center_radius = value
		queue_redraw()
@export_range(0.0, 45.0, 0.5) var gap_degrees := 12.0:
	set(value):
		gap_degrees = value
		queue_redraw()
@export var spin_degrees_per_second := 100.0
@export_range(0.0, 6.0, 0.1) var pulse_hz := 1.2
@export_range(0.0, 0.5, 0.01) var pulse_amplitude := 0.18

var _elapsed := 0.0

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_elapsed += delta
	queue_redraw()

func _draw() -> void:
	var pulse := 1.0 + pulse_amplitude * sin(TAU * pulse_hz * _elapsed)
	var spin := deg_to_rad(spin_degrees_per_second) * _elapsed
	var gap := deg_to_rad(gap_degrees)
	for quarter in range(4):
		var start := spin + quarter * PI * 0.5 + gap * 0.5
		var end := spin + (quarter + 1) * PI * 0.5 - gap * 0.5
		draw_arc(Vector2.ZERO, radius * pulse, start, end, 24, ring_color, line_width * pulse, true)
	# The center dot keeps its size while the arcs breathe.
	draw_circle(Vector2.ZERO, center_radius, ring_color, true, -1.0, true)
