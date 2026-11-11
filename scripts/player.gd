extends CharacterBody2D

var spawn := Vector2.ZERO
var automatic := false

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(10, 14)
	shape.shape = rectangle
	add_child(shape)
	var sprite := Sprite2D.new()
	sprite.texture = load("res://assets/kenney_tiles.png")
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 192, 16, 16)
	sprite.modulate = Color("72e5da")
	add_child(sprite)

func _physics_process(delta: float) -> void:
	velocity.y += 900 * delta
	if not automatic:
		velocity.x = Input.get_axis("ui_left", "ui_right") * 120
		if Input.is_physical_key_pressed(KEY_A):
			velocity.x = -120
		if Input.is_physical_key_pressed(KEY_D):
			velocity.x = 120
		if Input.is_action_just_pressed("ui_accept") and is_on_floor():
			velocity.y = -330
		if Input.is_physical_key_pressed(KEY_R) or position.y > 800:
			position = spawn
			velocity = Vector2.ZERO
	move_and_slide()
