extends CharacterBody2D

signal attack_pressed
signal jump_pressed

@export var jump_speed := 330.0
@export var gravity := 900.0
@export var attack_duration := 0.2
## Center-to-fist distance in sprite pixels, measured from attack.png at alpha >= 128.
@export var attack_reach := 24.0

var spawn := Vector2.ZERO
var automatic := false
var music_controlled := false
var target_x := 0.0
var active := true
var jump_buffer := 0.0
var coyote := 0.0
var attack_time_left := 0.0

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

func _unhandled_input(event: InputEvent) -> void:
	if not active or not music_controlled:
		return
	if InputMap.has_action("jump") and event.is_action_pressed("jump") and not event.is_echo():
		jump_buffer = .12
		jump_pressed.emit()
	if InputMap.has_action("attack") and event.is_action_pressed("attack") and not event.is_echo():
		attack_time_left = attack_duration
		_play_animation("attack", true)
		attack_pressed.emit()

func _physics_process(delta: float) -> void:
	attack_time_left = maxf(0, attack_time_left-delta)
	if not active:
		animated_sprite.pause()
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
	_update_animation()

func get_collision_bounds() -> Rect2:
	if collision_shape.shape == null or collision_shape.disabled:
		return Rect2()
	return collision_shape.global_transform * collision_shape.shape.get_rect()

func get_attack_tip() -> Vector2:
	# Sprite transform applies editor position/scale without changing body collision.
	return animated_sprite.to_global(animated_sprite.offset + Vector2(attack_reach, 0))

func _update_animation() -> void:
	if attack_time_left > 0:
		_play_animation("attack")
	elif not is_on_floor():
		_play_animation("jump")
	elif absf(velocity.x) > 1:
		_play_animation("walk")
	else:
		_play_animation("idle")

func _play_animation(animation_name: StringName, restart := false) -> void:
	# SpriteFrames are assigned manually in the editor, never generated at runtime.
	var frames := animated_sprite.sprite_frames
	if frames == null or not frames.has_animation(animation_name):
		return
	if restart:
		animated_sprite.stop()
	if animated_sprite.animation != animation_name or restart or not animated_sprite.is_playing():
		# Non-looping animations stay on their final frame until state changes.
		if animated_sprite.animation == animation_name and not frames.get_animation_loop(animation_name) and not restart:
			return
		animated_sprite.play(animation_name)
