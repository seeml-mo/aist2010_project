extends Node2D
## Renders a single interruptible action over the supplied world position.

const FIST := preload("res://assets/shape/pink_hand_closed.png")
const FOCUSED_EYE := preload("res://assets/shape/facial_part_eye_half_top.png")
const GRIT := preload("res://assets/shape/facial_part_mouth_angry.png")
const SMIRK := preload("res://assets/shape/facial_part_mouth_smirk.png")

const ACTION_LENGTHS := [0.24, 0.30, 0.46]

var action := -1
var elapsed := 0.0

@onready var visuals: Node2D = $Visuals
@onready var visuals_rest_rotation := visuals.rotation
@onready var rig: Node2D = $Visuals/BodyRig
@onready var front_hand: Sprite2D = $Visuals/FrontHand
@onready var front_rest := front_hand.position
@onready var rig_rest := rig.transform
@onready var left_eye: Sprite2D = $Visuals/BodyRig/LeftEye
@onready var right_eye: Sprite2D = $Visuals/BodyRig/RightEye
@onready var mouth_sprite: Sprite2D = $Visuals/BodyRig/Mouth
@onready var idle_textures := [left_eye.texture, right_eye.texture, mouth_sprite.texture, front_hand.texture]
@onready var idle_scales := [left_eye.scale, right_eye.scale, mouth_sprite.scale, front_hand.scale]

func set_walk_sway(angle: float) -> void:
	visuals.rotation = visuals_rest_rotation + angle

func play_action(next: int) -> void:
	action = next
	elapsed = 0.0
	_apply_pose()

func _process(delta: float) -> void:
	if action < 0:
		return
	elapsed += delta
	if elapsed >= ACTION_LENGTHS[action]:
		action = -1
	_apply_pose()

func _apply_pose() -> void:
	var phase := elapsed / float(ACTION_LENGTHS[action]) if action >= 0 else 0.0
	var drive := 0.0
	var windup := 0.0
	if action == 0 or action == 1:
		windup = smoothstep(0.0, 0.12, phase) * (1.0 - smoothstep(0.12, 0.32, phase))
		drive = smoothstep(0.10, 0.31, phase) * (1.0 - smoothstep(0.33, 1.0, phase))

	var lean := 0.0
	var shift := Vector2.ZERO
	var scale_y := 1.0
	var front := front_rest
	if action == 0:
		lean = 0.33 * drive - 0.15 * windup
		shift = Vector2(7.0 * drive - 5.0 * windup, 0)
		front += Vector2(35.0 * drive - 13.0 * windup, -7.0 * drive + 5.0 * windup)
	elif action == 1:
		lean = -0.22 * drive + 0.21 * windup
		shift = Vector2(-3.0 * drive, 6.0 * windup - 7.0 * drive)
		scale_y += 0.13 * drive - 0.12 * windup
		front += Vector2(8.0 * windup - 12.0 * drive, 13.0 * windup - 65.0 * drive)
	elif action == 2:
		var lift := sin(PI * phase)
		scale_y += 0.12 * lift * cos(PI * phase)
		front.y -= lift * 17.0

	var punching := action == 0 or action == 1
	rig.transform = rig_rest * Transform2D(lean, Vector2(1.0 / scale_y, scale_y), 0.0, shift)
	$Visuals/BodyRig/LeftBrow.visible = punching
	$Visuals/BodyRig/RightBrow.visible = punching
	front_hand.position = front
	_set_sprite(left_eye, 0, FOCUSED_EYE if punching else null)
	_set_sprite(right_eye, 1, FOCUSED_EYE if punching else null)
	_set_sprite(mouth_sprite, 2, (GRIT if action == 0 else SMIRK) if punching else null)
	_set_sprite(front_hand, 3, FIST if punching else null)

func _set_sprite(sprite: Sprite2D, index: int, action_texture: Texture2D) -> void:
	var idle_texture: Texture2D = idle_textures[index]
	var idle_scale: Vector2 = idle_scales[index]
	sprite.texture = action_texture if action_texture else idle_texture
	sprite.scale = idle_scale
	if action_texture and idle_texture:
		sprite.scale *= float(idle_texture.get_width()) / action_texture.get_width()
