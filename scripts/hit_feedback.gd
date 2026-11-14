extends Node2D

const ChartRun = preload("res://scripts/chart_level.gd")

@export var good_color := Color("#77e4f4")
@export var perfect_color := Color("#ffe184")
@export var miss_color := Color("#ffadae")
@export var outline_color := Color("#243439")
@export var lifetime := 0.48

var judgement := ChartRun.Judgment.GOOD
var age := 0.0

func _process(delta: float) -> void:
	age += delta
	if age >= lifetime:
		queue_free()
	queue_redraw()

func _draw() -> void:
	var t := clampf(age / lifetime, 0.0, 1.0)
	var expansion := 1.0 - pow(1.0 - t, 3.0)
	var color := good_color
	var word := "GOOD"
	match judgement:
		ChartRun.Judgment.GOOD:
			_draw_ring(13.0 + expansion * 30.0, 3.0, _fade(good_color, 1.0 - t))
			for i in range(4):
				var direction := Vector2.from_angle(PI / 4.0 + i * TAU / 4.0)
				var center := direction * (18.0 + expansion * 33.0)
				draw_circle(center, 3.8 * (1.0 - t), _fade(good_color, 1.0 - t), true, -1, true)
		ChartRun.Judgment.PERFECT:
			color = perfect_color
			word = "PERFECT"
			_draw_ring(14.0 + expansion * 46.0, 4.0, _fade(color, 1.0 - t))
			_draw_ring(8.0 + expansion * 24.0, 2.0, _fade(Color.WHITE, (1.0 - t) * 0.84))
			for i in range(8):
				var angle := i * TAU / 8.0 + t * 0.28
				var center := Vector2.from_angle(angle) * (23.0 + expansion * 49.0)
				var size := (9.0 if i % 2 == 0 else 5.0) * (1.0 - t)
				_draw_spark(center, angle, size, _fade(color if i % 2 == 0 else Color.WHITE, 1.0 - t))
			draw_circle(Vector2.ZERO, 19.0 * maxf(0.0, 1.0 - t * 5.0), _fade(Color.WHITE, 0.8), true, -1, true)
		ChartRun.Judgment.MISS:
			color = miss_color
			word = "MISS"
			var size := 10.0 + expansion * 6.0
			var tint := _fade(color, 1.0 - t)
			draw_line(Vector2(-size, -size), Vector2(size, size), tint, 3.0, true)
			draw_line(Vector2(-size, size), Vector2(size, -size), tint, 3.0, true)

	var alpha := 1.0 - smoothstep(0.52, 1.0, t)
	var font := ThemeDB.fallback_font
	var font_size := 24 if judgement == ChartRun.Judgment.PERFECT else 19
	var width := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var origin := Vector2(-width * 0.5, -24.0 - expansion * 29.0)
	draw_string_outline(font, origin, word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 6, _fade(outline_color, alpha))
	draw_string(font, origin, word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, _fade(color, alpha))

func _draw_ring(radius: float, width: float, color: Color) -> void:
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, color, width, true)

func _draw_spark(center: Vector2, angle: float, size: float, color: Color) -> void:
	if size < 0.5:
		return
	var points := PackedVector2Array()
	for i in range(8):
		var radius := size if i % 2 == 0 else size * 0.24
		points.append(center + Vector2.from_angle(angle + i * TAU / 8.0) * radius)
	draw_colored_polygon(points, color)

func _fade(color: Color, alpha: float) -> Color:
	return Color(color, alpha)
