extends Node2D
## Visual component only. Replace this child with sprites/animations in the editor.

@export var tint := Color("6ce4c0")
@onready var player: CharacterBody2D = get_parent()

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var white := Color("eef4ff")
	var stride := sin(player.animation_time * 20) * 4 if player.is_on_floor() else 2.0
	draw_line(Vector2(-4, 9), Vector2(-8-stride, 20), white, 4)
	draw_line(Vector2(4, 9), Vector2(8+stride, 20), white, 4)
	draw_style_box(_rounded(white, 4), Rect2(-9, -12, 18, 21))
	draw_style_box(_rounded(white, 5), Rect2(-10, -30, 22, 20))
	draw_style_box(_rounded(Color("173e49"), 3), Rect2(-2, -23, 14, 8))
	draw_line(Vector2(3, -21), Vector2(9, -21), tint, 2)
	draw_colored_polygon(PackedVector2Array([Vector2(-8, -9), Vector2(-33, -4+sin(player.animation_time*10)*3), Vector2(-27, -14)]), tint)
	if player.swing > 0:
		draw_arc(Vector2(8, -9), 42, -1.1, 1.15, 20, Color("fff0ae"), 5, true)

func _rounded(color: Color, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	return box
