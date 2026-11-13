extends Node2D

const ChartLoader = preload("res://scripts/chart_loader.gd")
const ChartRun = preload("res://scripts/chart_level.gd")
const ACTION_LABELS := ["STRAIGHT", "UPPERCUT", "JUMP"]
const ENEMY_SPEED := 380.0
const ENEMY_AXES := [Vector2.RIGHT, Vector2.UP]
const ENEMY_FLOAT := 9.0
const WALK_FLOAT := 4.0
const ENEMY_SWAY := deg_to_rad(9.0)
const WALK_SWAY := deg_to_rad(4.0)
const SPEED := 220.0
const JUMP_DURATION := 0.46

@export var chart_path := "res://assets/maps/chart_band.json"
@export var ground_surface: Texture2D
@export var ground_fill: Texture2D
@export var ground_edge: Texture2D
const TILE_SIZE := 46.0
const MISSED_GROUND_ALPHA := 0.60

@onready var music: AudioStreamPlayer = $Music
@onready var performer = $Performer
@onready var anchor: Vector2 = performer.position
@onready var targets: Array[Node2D] = [$Performer/StraightTarget, $Performer/UppercutTarget]
@onready var enemy_art: Array[Sprite2D] = [$EnemyArt/Red, $EnemyArt/Blue]
@onready var far_scenery: Parallax2D = $FarScenery
@onready var near_scenery: Parallax2D = $NearScenery
@onready var status: Label = $HUD/Status
@onready var jump_arrow: Sprite2D = $GroundPreview/JumpArrow

var run: ChartRun
var time := 0.0
var duration := 0.0
var ended := false
var feedback := ""
var jump_started_at := -10.0
var enemy_sprites: Dictionary = {}

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--chart="):
			chart_path = arg.trim_prefix("--chart=")
	var result := ChartLoader.load_chart(chart_path)
	if not result.ok:
		status.text = result.error
		return
	music.stream = load(str(result.chart.audio.stream)) as AudioStream
	if music.stream == null:
		status.text = "Could not load chart audio."
		return
	duration = music.stream.get_length()
	run = ChartRun.new(result.chart.chart.notes)
	run.judged.connect(func(lane: int, hit: bool, perfect: bool):
		var result_label := "PERFECT" if perfect else ("HIT" if hit else "MISS")
		feedback = "%s · %s" % [result_label, ACTION_LABELS[lane]]
		if run.health == 0:
			music.stop())
	music.finished.connect(_finish)
	for template in enemy_art:
		template.hide()
	$GroundPreview.hide()
	music.play()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_tree().reload_current_scene()
		return
	if run == null or ended or run.health <= 0:
		return
	for lane in range(ChartRun.ACTIONS.size()):
		if event.is_action_pressed(ChartRun.ACTIONS[lane]):
			_sample_clock()
			performer.play_action(lane)
			if lane == 2:
				jump_started_at = time
			run.press(lane, time)
			return

func _sample_clock() -> void:
	if music.playing:
		var clock := music.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
		time = maxf(time, clampf(clock, 0.0, duration))

func _held_actions() -> Array[bool]:
	return [Input.is_action_pressed("attack"), Input.is_action_pressed("defend"), Input.is_action_pressed("jump")]

func _finish() -> void:
	time = duration
	run.advance(time, _held_actions(), true)
	ended = true

func _process(_delta: float) -> void:
	if run == null:
		return
	if not ended and run.health > 0:
		_sample_clock()
		run.advance(time, _held_actions())
	var jump := clampf((time - jump_started_at) / JUMP_DURATION, 0.0, 1.0)
	var lift := 48.0 * 4.0 * jump * (1.0 - jump)
	var walk_wave := -cos(TAU * 4.0 * time)
	var walk_weight := 1.0 - sin(PI * jump)
	var walk_bob := WALK_FLOAT * (0.5 + 0.5 * walk_wave) * walk_weight
	performer.position = anchor - Vector2(0, lift + walk_bob)
	performer.set_walk_sway(WALK_SWAY * walk_wave * walk_weight)
	_update_scene_art()
	var message := feedback
	if run.health == 0:
		message = "OUT OF HEALTH · R to restart"
	elif ended:
		message = "TRACK COMPLETE · R to replay"
	status.text = "HP %d/5   HIT %d   MISS %d   %.1f / %.1fs\nJ Straight   K Uppercut   F / Space Jump   R Restart\n%s" % [
		run.health, run.hits, run.misses, time, duration, message]
	queue_redraw()

func _draw() -> void:
	if run == null:
		return
	var segment_start := 0.0
	var left_edge := false
	for note in run.notes:
		if note.lane != 2:
			continue
		var x := anchor.x + (float(note.time) - time) * SPEED
		var gap_start := x + SPEED * 0.14
		var gap_end := gap_start + SPEED * 0.18
		if gap_end <= 0 or gap_start >= 960:
			continue
		_draw_solid_ground(segment_start, gap_start, left_edge, true)
		if note.state == ChartRun.State.MISSED:
			_draw_ground(maxf(segment_start, gap_start), gap_end, MISSED_GROUND_ALPHA)
		segment_start = maxf(segment_start, gap_end)
		left_edge = true
	_draw_solid_ground(segment_start, 960.0, left_edge, false)
	for note in run.notes:
		if note.lane != 2 or note.state != ChartRun.State.PENDING:
			continue
		var x := anchor.x + (float(note.time) - time) * SPEED
		var center := Vector2(x, anchor.y + jump_arrow.position.y)
		var size := jump_arrow.texture.get_size() * jump_arrow.scale
		var rect := Rect2(center - size * 0.5, size)
		if rect.end.x > 0 and rect.position.x < 960:
			draw_texture_rect(jump_arrow.texture, rect, false, jump_arrow.modulate)

func _update_scene_art() -> void:
	far_scenery.scroll_offset.x = -time * 15.0
	near_scenery.scroll_offset.x = -time * 38.0

	for target in targets:
		target.modulate.a = 0.66
	for index in range(run.notes.size()):
		var note: Dictionary = run.notes[index]
		var lane := int(note.lane)
		if lane == 2:
			continue
		var remaining := float(note.time) - time
		var hit: bool = note.state == ChartRun.State.HIT
		var age := time - float(note.get("resolved_at", time))
		if remaining > 0.9 or note.state == ChartRun.State.MISSED or (hit and age > 0.27):
			if enemy_sprites.has(index):
				enemy_sprites[index].queue_free()
				enemy_sprites.erase(index)
			continue

		var target := targets[lane]
		var axis: Vector2 = ENEMY_AXES[lane]
		var offset := remaining * ENEMY_SPEED
		var flight_wave := 0.0
		if hit:
			var impact_offset := 0.0 if note.has("duration") else offset + age * ENEMY_SPEED
			offset = impact_offset + age * 620.0
		elif note.state == ChartRun.State.HOLDING:
			offset = 0.0
		elif absf(remaining) <= ChartRun.PERFECT_WINDOW:
			target.modulate.a = 1.0
		else:
			var float_weight := smoothstep(ChartRun.PERFECT_WINDOW, 0.18, absf(remaining))
			flight_wave = float_weight * sin(TAU * 2.5 * remaining)

		if not enemy_sprites.has(index):
			var sprite := enemy_art[lane].duplicate() as Sprite2D
			$EnemyArt.add_child(sprite)
			sprite.show()
			enemy_sprites[index] = sprite
		var sprite: Sprite2D = enemy_sprites[index]
		sprite.global_position = target.global_position + axis * offset + axis.orthogonal() * ENEMY_FLOAT * flight_wave
		sprite.rotation = enemy_art[lane].rotation + (age * 13.0 if hit else ENEMY_SWAY * flight_wave)

func _draw_solid_ground(from_x: float, to_x: float, left_edge: bool, right_edge: bool) -> void:
	_draw_ground(from_x, to_x)
	var edge_width := minf(ground_edge.get_width(), (to_x - from_x) * 0.5)
	if edge_width <= 0:
		return
	var edge_size := Vector2(edge_width, TILE_SIZE * 3.0)
	if left_edge:
		draw_set_transform(Vector2(from_x + edge_width, anchor.y), 0.0, Vector2(-1.0, 1.0))
		draw_texture_rect(ground_edge, Rect2(Vector2.ZERO, edge_size), false)
		draw_set_transform(Vector2.ZERO)
	if right_edge:
		draw_texture_rect(ground_edge, Rect2(Vector2(to_x - edge_width, anchor.y), edge_size), false)

func _draw_ground(from_x: float, to_x: float, opacity: float = 1.0) -> void:
	var left := maxf(0.0, from_x)
	var right := minf(960.0, to_x)
	if right <= left:
		return
	var scroll := fposmod(time * SPEED - anchor.x, TILE_SIZE)
	var first := floori((left + scroll) / TILE_SIZE)
	var last := ceili((right + scroll) / TILE_SIZE)
	for column in range(first, last):
		var tile_x := column * TILE_SIZE - scroll
		var start := maxf(tile_x, left)
		var width := minf(tile_x + TILE_SIZE, right) - start
		for row in range(3):
			var texture := ground_surface if row == 0 else ground_fill
			var ratio := float(texture.get_width()) / TILE_SIZE
			var source := Rect2((start - tile_x) * ratio, 0, width * ratio, texture.get_height())
			var destination := Rect2(start, anchor.y + row * TILE_SIZE, width, TILE_SIZE)
			draw_texture_rect_region(texture, destination, source, Color(1, 1, 1, opacity))
