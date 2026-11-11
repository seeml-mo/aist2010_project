extends CharacterBody2D

signal attack_pressed
signal jump_pressed

var spawn := Vector2.ZERO
var automatic := false
var music_controlled := false
var target_x := 0.0
var active := true
var jump_buffer := 0.0
var coyote := 0.0
var swing := 0.0
var animation_time := 0.0
var jump_speed := 330.0
var gravity := 900.0
var tint := Color("6ce4c0")

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(16, 42)
	shape.shape = rectangle
	add_child(shape)

func _unhandled_input(event: InputEvent) -> void:
	if not active or not music_controlled:
		return
	if event.is_action_pressed("jump") and not event.is_echo():
		jump_buffer = .12
		jump_pressed.emit()
	if event.is_action_pressed("attack") and not event.is_echo():
		swing = .18
		attack_pressed.emit()

func _physics_process(delta: float) -> void:
	animation_time += delta
	swing = maxf(0, swing-delta)
	if not active:
		queue_redraw()
		return
	velocity.y += gravity * delta
	if music_controlled:
		velocity.x = (target_x-position.x) / delta
		jump_buffer = maxf(0, jump_buffer-delta)
		coyote = .08 if is_on_floor() else maxf(0, coyote-delta)
		if jump_buffer > 0 and coyote > 0:
			velocity.y = -jump_speed
			jump_buffer = 0
			coyote = 0
	elif not automatic:
		velocity.x = Input.get_axis("ui_left", "ui_right") * 120
		if Input.is_physical_key_pressed(KEY_A):
			velocity.x = -120
		if Input.is_physical_key_pressed(KEY_D):
			velocity.x = 120
		if Input.is_action_just_pressed("ui_accept") and is_on_floor():
			velocity.y = -jump_speed
		if Input.is_physical_key_pressed(KEY_R) or position.y > 800:
			position = spawn
			velocity = Vector2.ZERO
	move_and_slide()
	queue_redraw()

func _draw() -> void:
	var white := Color("eef4ff")
	var stride := sin(animation_time*20)*4 if is_on_floor() else 2.0
	draw_line(Vector2(-4, 9), Vector2(-8-stride, 20), white, 4)
	draw_line(Vector2(4, 9), Vector2(8+stride, 20), white, 4)
	draw_style_box(_rounded(white, 4), Rect2(-9, -12, 18, 21))
	draw_style_box(_rounded(white, 5), Rect2(-10, -30, 22, 20))
	draw_style_box(_rounded(Color("173e49"), 3), Rect2(-2, -23, 14, 8))
	draw_line(Vector2(3, -21), Vector2(9, -21), tint, 2)
	draw_colored_polygon(PackedVector2Array([Vector2(-8, -9), Vector2(-33, -4+sin(animation_time*10)*3), Vector2(-27, -14)]), tint)
	if swing > 0:
		draw_arc(Vector2(8, -9), 42, -1.1, 1.15, 20, Color("fff0ae"), 5, true)

func _rounded(color: Color, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	return box
