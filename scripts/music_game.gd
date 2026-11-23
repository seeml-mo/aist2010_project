extends Node2D

const ChartLoader = preload("res://scripts/chart_loader.gd")
const ChartRun = preload("res://scripts/chart_level.gd")
const HoldTail = preload("res://scenes/hold_tail.tscn")
const HitFeedback = preload("res://scenes/hit_feedback.tscn")
const MENU_SCENE := "res://scenes/song_menu.tscn"
const ENEMY_SPEED := 380.0
const ENEMY_AXES := [Vector2.RIGHT, Vector2.UP]
const ENEMY_FLOAT := 9.0
const WALK_FLOAT := 4.0
const ENEMY_SWAY := deg_to_rad(9.0)
const WALK_SWAY := deg_to_rad(4.0)
const SPEED := 220.0
const JUMP_DURATION := 0.46
const AUTOPLAY_LEAD := 0.03

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
@onready var hud := $HUD
@onready var jump_arrow: Sprite2D = $GroundPreview/JumpArrow

var run: ChartRun
var time := 0.0
var duration := 0.0
var ended := false
var autoplay := false
var jump_started_at := -10.0
var enemy_sprites: Dictionary = {}

func _ready() -> void:
	hud.pause_requested.connect(_toggle_pause)
	hud.resume_requested.connect(_toggle_pause)
	hud.restart_requested.connect(_restart)
	hud.menu_requested.connect(_return_to_menu)
	autoplay = bool(get_tree().root.get_meta("autoplay_mode", false))
	for arg in OS.get_cmdline_user_args():
		if arg == "--autoplay":
			autoplay = true
	hud.set_autoplay(autoplay)
	for template in enemy_art:
		template.hide()
	$GroundPreview.hide()

	var selected := str(get_tree().root.get_meta("selected_chart", ""))
	if not selected.is_empty():
		chart_path = selected
	else:
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--chart="):
				chart_path = arg.trim_prefix("--chart=")
	var result := ChartLoader.load_chart(chart_path)
	if not result.ok:
		hud.show_error(result.error)
		return
	var audio_path := str(result.chart.audio.stream)
	if ResourceLoader.exists(audio_path, "AudioStream"):
		music.stream = load(audio_path) as AudioStream
	if music.stream == null:
		hud.show_error("Could not load chart audio.")
		return
	duration = music.stream.get_length()
	run = ChartRun.new(result.chart.chart.notes)
	hud.set_track(str(result.chart.audio.get("title", chart_path.get_file().get_basename())), duration)
	hud.update_counts(run)
	run.judged.connect(_on_judged)
	music.finished.connect(_finish)
	music.play()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("autoplay") and not event.is_echo() and run != null and not ended:
		get_viewport().set_input_as_handled()
		_set_autoplay(not autoplay)
	elif event.is_action_pressed("ui_cancel") and run != null and not ended:
		get_viewport().set_input_as_handled()
		_toggle_pause()
	elif event.is_action_pressed("restart") and run != null:
		get_viewport().set_input_as_handled()
		_restart()

func _unhandled_input(event: InputEvent) -> void:
	if run == null or ended or autoplay or get_tree().paused or event.is_echo():
		return
	for lane in range(ChartRun.ACTIONS.size()):
		if lane < targets.size() and event.is_action_released(ChartRun.ACTIONS[lane]):
			_sample_clock()
			run.release(lane, time)
			return
		if event.is_action_pressed(ChartRun.ACTIONS[lane]):
			_sample_clock()
			performer.play_action(lane)
			if lane == 2:
				jump_started_at = time
			run.press(lane, time)
			return

func _toggle_pause() -> void:
	if run == null or ended:
		return
	if get_tree().paused:
		hud.hide_pause()
		get_tree().paused = false
	else:
		_sample_clock()
		get_tree().paused = true
		hud.show_pause()

func _restart() -> void:
	music.stop()
	get_tree().paused = false
	get_tree().reload_current_scene()

func _return_to_menu() -> void:
	music.stop()
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)

func _set_autoplay(enabled: bool) -> void:
	if autoplay == enabled:
		return
	autoplay = enabled
	get_tree().root.set_meta("autoplay_mode", autoplay)
	hud.set_autoplay(autoplay)

func _on_judged(lane: int, judgement: int) -> void:
	hud.update_counts(run)
	if ended:
		return
	var effect := HitFeedback.instantiate()
	effect.judgement = judgement
	var impact := to_local(targets[lane].global_position) if lane < targets.size() else anchor + Vector2(0, jump_arrow.position.y)
	effect.position = impact
	$Feedback.add_child(effect)

func _sample_clock() -> void:
	if music.playing:
		var clock := music.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
		time = maxf(time, clampf(clock, 0.0, duration))

func _held_actions() -> Array[bool]:
	if autoplay:
		return _auto_held_actions()
	return [Input.is_action_pressed("attack"), Input.is_action_pressed("defend"), Input.is_action_pressed("jump")]

func _auto_held_actions() -> Array[bool]:
	var held: Array[bool] = [false, false, false]
	for note in run.notes:
		if note.state == ChartRun.State.HOLDING:
			held[int(note.lane)] = true
	return held

## Plays the chart itself: presses each pending note just before its time and
## keeps held notes down until they resolve. Notes are time-sorted, so the first
## eligible note per lane is also the earliest one.
func _autoplay_step() -> void:
	var pressed: Array[bool] = [false, false, false]
	for note in run.notes:
		var lane := int(note.lane)
		if note.state == ChartRun.State.HOLDING:
			performer.play_action(lane)
			continue
		if note.state != ChartRun.State.PENDING or pressed[lane]:
			continue
		var note_time := float(note.time)
		if time < note_time - AUTOPLAY_LEAD or time > note_time + ChartRun.WINDOWS[lane]:
			continue
		pressed[lane] = true
		performer.play_action(lane)
		if lane == 2:
			jump_started_at = time
		run.press(lane, time)

func _finish() -> void:
	time = duration
	ended = true
	run.advance(time, _held_actions(), true)
	hud.update_counts(run)
	hud.update_time(time)
	_update_scene_art()
	queue_redraw()
	hud.show_results(run)

func _process(_delta: float) -> void:
	if run == null or ended or get_tree().paused:
		return
	_sample_clock()
	if autoplay:
		_autoplay_step()
	run.advance(time, _held_actions())
	var jump := clampf((time - jump_started_at) / JUMP_DURATION, 0.0, 1.0)
	var lift := 48.0 * 4.0 * jump * (1.0 - jump)
	var walk_wave := -cos(TAU * 4.0 * time)
	var walk_weight := 1.0 - sin(PI * jump)
	var walk_bob := WALK_FLOAT * (0.5 + 0.5 * walk_wave) * walk_weight
	performer.position = anchor - Vector2(0, lift + walk_bob)
	performer.set_walk_sway(WALK_SWAY * walk_wave * walk_weight)
	_update_scene_art()
	hud.update_time(time)
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
		var holding: bool = note.state == ChartRun.State.HOLDING
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
		elif holding:
			offset = 0.0
			target.modulate.a = 1.0
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
			if note.has("duration"):
				var tail := HoldTail.instantiate()
				tail.name = "HoldTail"
				tail.color = target.ring_color
				sprite.add_child(tail)
		var sprite: Sprite2D = enemy_sprites[index]
		var lane_position := target.global_position + axis * offset
		sprite.global_position = lane_position + axis.orthogonal() * ENEMY_FLOAT * flight_wave
		sprite.rotation = enemy_art[lane].rotation + (age * 13.0 if hit else ENEMY_SWAY * flight_wave)
		var tail := sprite.get_node_or_null("HoldTail")
		if tail != null:
			tail.visible = not hit
			if not hit:
				var tail_time := float(note.time) + float(note.duration)
				var tail_end := target.global_position + axis * maxf(tail_time - time, 0.0) * ENEMY_SPEED
				tail.global_transform = Transform2D(0.0, sprite.global_position)
				tail.update_tail(tail_end - lane_position, holding)


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
