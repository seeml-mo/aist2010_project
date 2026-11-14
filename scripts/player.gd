extends Node2D
## Animates the two fists independently from the body and jump pose.

const FOCUSED_EYE := preload("res://assets/shape/facial_part_eye_half_top.png")
const GRIT := preload("res://assets/shape/facial_part_mouth_angry.png")
const SMIRK := preload("res://assets/shape/facial_part_mouth_smirk.png")

const PUNCH_OFFSETS := [Vector2(35, -7), Vector2(21, -63)]
const PUNCH_EXTEND_TIME := 0.065
const PUNCH_RETURN_TIME := 0.115
const JUMP_DURATION := 0.46

var punch_drive := [0.0, 0.0]
var punch_latched := [false, false]
var jump_elapsed := JUMP_DURATION

@onready var visuals: Node2D = $Visuals
@onready var visuals_rest_rotation := visuals.rotation
@onready var rig: Node2D = $Visuals/BodyRig
@onready var fists: Array[Sprite2D] = [$Visuals/StraightFist, $Visuals/UppercutFist]
@onready var fist_rests: Array[Vector2] = [fists[0].position, fists[1].position]
@onready var rig_rest := rig.transform
@onready var left_eye: Sprite2D = $Visuals/BodyRig/LeftEye
@onready var right_eye: Sprite2D = $Visuals/BodyRig/RightEye
@onready var mouth_sprite: Sprite2D = $Visuals/BodyRig/Mouth
@onready var idle_textures := [left_eye.texture, right_eye.texture, mouth_sprite.texture]
@onready var idle_scales := [left_eye.scale, right_eye.scale, mouth_sprite.scale]

func set_walk_sway(angle: float) -> void:
	visuals.rotation = visuals_rest_rotation + angle

func play_action(lane: int) -> void:
	if lane == 2:
		jump_elapsed = 0.0
	else:
		punch_latched[lane] = true

func _process(delta: float) -> void:
	for lane in range(fists.size()):
		var held := Input.is_action_pressed(&"attack" if lane == 0 else &"defend")
		# Show even very short taps that start and end between rendered frames.
		var extending: bool = held or punch_latched[lane]
		var step := delta / (PUNCH_EXTEND_TIME if extending else PUNCH_RETURN_TIME)
		punch_drive[lane] = move_toward(punch_drive[lane], 1.0 if extending else 0.0, step)
		if punch_drive[lane] >= 1.0:
			punch_latched[lane] = false
	jump_elapsed = minf(jump_elapsed + delta, JUMP_DURATION)
	_apply_pose()

func _apply_pose() -> void:
	var phase := jump_elapsed / JUMP_DURATION
	var lift := sin(PI * phase)
	var straight := smoothstep(0.0, 1.0, punch_drive[0])
	var uppercut := smoothstep(0.0, 1.0, punch_drive[1])
	var lean := 0.33 * straight - 0.22 * uppercut
	var shift := Vector2(7.0 * straight - 3.0 * uppercut, -7.0 * uppercut)
	var scale_y := 1.0 + 0.13 * uppercut + 0.12 * lift * cos(PI * phase)
	rig.transform = rig_rest * Transform2D(lean, Vector2(1.0 / scale_y, scale_y), 0.0, shift)

	for lane in range(fists.size()):
		var drive := smoothstep(0.0, 1.0, punch_drive[lane])
		fists[lane].position = fist_rests[lane] + PUNCH_OFFSETS[lane] * drive
		fists[lane].position.y -= 17.0 * lift * (1.0 - drive)

	var punching := maxf(straight, uppercut) > 0.05
	$Visuals/BodyRig/LeftBrow.visible = punching
	$Visuals/BodyRig/RightBrow.visible = punching
	_set_sprite(left_eye, 0, FOCUSED_EYE if punching else null)
	_set_sprite(right_eye, 1, FOCUSED_EYE if punching else null)
	_set_sprite(mouth_sprite, 2, (GRIT if straight >= uppercut else SMIRK) if punching else null)

func _set_sprite(sprite: Sprite2D, index: int, action_texture: Texture2D) -> void:
	var idle_texture: Texture2D = idle_textures[index]
	var idle_scale: Vector2 = idle_scales[index]
	sprite.texture = action_texture if action_texture else idle_texture
	sprite.scale = idle_scale
	if action_texture and idle_texture:
		sprite.scale *= float(idle_texture.get_width()) / action_texture.get_width()
