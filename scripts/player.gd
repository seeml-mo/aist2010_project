extends CharacterBody2D

signal attack_pressed
signal jump_pressed

@export var jump_speed := 330.0
@export var gravity := 900.0

var spawn := Vector2.ZERO
var automatic := false
var music_controlled := false
var target_x := 0.0
var active := true
var jump_buffer := 0.0
var coyote := 0.0
var swing := 0.0
var animation_time := 0.0

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var visual: Node2D = $Visual

func _unhandled_input(event: InputEvent) -> void:
	if not active or not music_controlled:
		return
	if InputMap.has_action("jump") and event.is_action_pressed("jump") and not event.is_echo():
		jump_buffer = .12
		jump_pressed.emit()
	if InputMap.has_action("attack") and event.is_action_pressed("attack") and not event.is_echo():
		swing = .18
		attack_pressed.emit()

func _physics_process(delta: float) -> void:
	animation_time += delta
	swing = maxf(0, swing-delta)
	if not active:
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
