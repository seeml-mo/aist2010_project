extends Node2D
## Audio is the master clock. Horizontal position is a function of song time.

const Player = preload("res://scripts/player.gd")
const Map = preload("res://scripts/json_map.gd")
const Spawner = preload("res://scripts/enemy_spawner.gd")

@onready var player: Player = $Player
@onready var world: Map = $World
@onready var enemy_spawner: Spawner = $EnemySpawner
@onready var audio: AudioStreamPlayer = $Music
@onready var camera: Camera2D = $Camera2D
@onready var status: Label = $HUD/TopPanel/StatusLabel
@onready var timer_label: Label = $HUD/TopPanel/TimerLabel

var music: Dictionary
var feedback := ""
var feedback_until := 0.0
var song_time := 0.0
var finished := false
var failed := false
var test_mode := false
var autoplay := false
var jump_hits := 0
var attack_hits := 0
var misses := 0
var screenshot_path := ""
var screenshot_at := 5.0
var screenshot_pending := false
var jump_attempts: Dictionary = {}
var bot_jumps: Dictionary = {}
var bot_attacks: Dictionary = {}
var beat_pulse := 0.0

func _ready() -> void:
	var path := "res://maps/music_demo.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			path = arg.trim_prefix("--map=")
		if arg == "--test-clock":
			test_mode = true
		if arg == "--autoplay":
			autoplay = true
		if arg.begins_with("--screenshot="):
			screenshot_path = arg.trim_prefix("--screenshot=")
		if arg.begins_with("--screenshot-at="):
			screenshot_at = float(arg.trim_prefix("--screenshot-at="))
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or not data.has("music"):
		# Keep the original JSON-only fixtures available via --map.
		add_child(preload("res://scripts/main.gd").new())
		player.hide()
		player.set_physics_process(false)
		player.set_process_unhandled_input(false)
		$HUD.hide()
		set_physics_process(false)
		return
	music = data.music
	if not world.load_map(path):
		push_error(world.last_error)
		get_tree().quit(1)
		return
	player.automatic = true
	player.music_controlled = true
	player.spawn = world.spawn
	player.position = world.spawn
	player.target_x = world.spawn.x
	camera.position = Vector2(player.position.x+256, 270)
	audio.stream = load(str(music.stream))
	enemy_spawner.configure(music.attacks, world.spawn.x, music.speed, music.floor_y)
	# Start only after at least one physics frame lets the character settle.
	await get_tree().physics_frame
	if not test_mode:
		audio.play()
	print("MUSIC_READY beats=", music.beats.size(), " jumps=", music.jumps.size(), " attacks=", music.attacks.size())

func _unhandled_input(event: InputEvent) -> void:
	if InputMap.has_action("restart") and event.is_action_pressed("restart") and not event.is_echo():
		get_tree().reload_current_scene()

func _physics_process(delta: float) -> void:
	if player == null:
		return
	if not finished and not failed:
		if test_mode:
			song_time += delta
		elif audio.playing:
			var audio_clock := audio.get_playback_position()+AudioServer.get_time_since_last_mix()-AudioServer.get_output_latency()
			song_time = maxf(song_time, maxf(0, audio_clock))
		elif song_time > float(music.duration)-.2:
			song_time = float(music.duration)
		player.target_x = world.spawn.x + song_time*float(music.speed)
		if autoplay:
			_autoplay()
		for i in range(music.jumps.size()):
			if song_time > float(music.jumps[i].time)+.25 and not jump_attempts.has(i):
				jump_attempts[i] = false
		enemy_spawner.update_time(song_time)
		if player.position.y > float(music.floor_y)+95:
			failed = true
			player.active = false
			audio.stop()
		elif song_time >= float(music.duration):
			finished = true
			player.active = false
			audio.stop()
	camera.position.x = player.position.x+256
	beat_pulse = 0
	for beat in music.beats:
		beat_pulse = maxf(beat_pulse, maxf(0, 1-absf(song_time-float(beat))/.13))
	_update_hud()
	queue_redraw()
	if not screenshot_path.is_empty() and song_time >= screenshot_at and not screenshot_pending:
		screenshot_pending = true
		_capture.call_deferred()

func _autoplay() -> void:
	# Explicit QA/demo option only; ordinary play never supplies these inputs.
	for i in range(music.jumps.size()):
		if song_time >= float(music.jumps[i].time) and not bot_jumps.has(i):
			bot_jumps[i] = true
			_inject_key(KEY_F if i % 2 == 0 else KEY_SPACE)
	for i in range(music.attacks.size()):
		if song_time >= float(music.attacks[i].time) and not bot_attacks.has(i):
			bot_attacks[i] = true
			_inject_key(KEY_J if i % 2 == 0 else KEY_K)

func _inject_key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	var release := InputEventKey.new()
	release.physical_keycode = code
	Input.parse_input_event(release)

func _jump() -> void:
	var best := -1
	var distance := .18
	for i in range(music.jumps.size()):
		var d := absf(float(music.jumps[i].time)-song_time)
		if d < distance and not jump_attempts.has(i):
			best = i
			distance = d
	if best >= 0 and (player.is_on_floor() or player.coyote > 0):
		jump_attempts[best] = true
		jump_hits += 1
		_feedback("ON BEAT" if distance < .08 else "JUMP", Color("6ce4c0"))

func _attack() -> void:
	if not enemy_spawner.try_attack(song_time, player.position):
		_feedback("NO TARGET IN REACH", Color("8d9db3"))

func _on_enemy_defeated(_event_index: int, timing_error: float) -> void:
	attack_hits += 1
	_feedback("PERFECT HIT" if timing_error < .075 else "HIT", Color("fff0ae"))

func _on_enemy_missed(_event_index: int) -> void:
	misses += 1
	_feedback("MISSED TARGET", Color("fb818f"))

func _feedback(text: String, color: Color) -> void:
	feedback = text
	feedback_until = song_time+.45
	status.modulate = color

func _update_hud() -> void:
	timer_label.text = "%04.1f / 30s   |   %.1f BPM\nJUMP %d   HIT %d   MISS %d" % [song_time, music.bpm, jump_hits, attack_hits, misses]
	if failed:
		status.text = "FELL INTO GAP  /  Press R to retry"
		status.modulate = Color("fb818f")
	elif finished:
		status.text = "TRACK COMPLETE  /  Press R to play again"
		status.modulate = Color("6ce4c0")
	elif song_time < feedback_until:
		status.text = feedback
	else:
		var next_time := INF
		var message := "FOLLOW THE MUSIC"
		for event in music.jumps:
			var t := float(event.time)
			if t > song_time and t < next_time:
				next_time = t
				message = "GAP AHEAD  /  F or SPACE"
		for event in music.attacks:
			var t := float(event.time)
			if t > song_time and t < next_time:
				next_time = t
				message = "TARGET AHEAD  /  J or K"
		status.text = message if next_time-song_time < 2.0 else "FOLLOW THE MUSIC"
		status.modulate = Color("6ce4c0")

func _draw() -> void:
	if player == null:
		return
	var left := camera.position.x-480
	var right := left+960
	var floor_y := float(music.floor_y)
	# Quiet background contours retain the visual language of the video.
	for y in [205, 260, 315]:
		var points := PackedVector2Array()
		for x in range(int(left)-30, int(right)+40, 24):
			points.append(Vector2(x, y+sin(x*.008)*8+sin(x*.023)*3))
		draw_polyline(points, Color("182b3a"), 1.5, true)
	for beat in music.beats:
		var x := world.spawn.x+float(beat)*float(music.speed)
		if x < left or x > right:
			continue
		draw_circle(Vector2(x, floor_y+48), 3, Color("52716f"))
	for event in music.jumps:
		var x := world.spawn.x+float(event.time)*float(music.speed)
		if x < left-100 or x > right+100:
			continue
		var faded := float(event.time) < song_time-.2
		var color := Color("42645f") if faded else Color("6ce4c0")
		draw_line(Vector2(x, floor_y-10), Vector2(x, floor_y+12), color, 2)
		draw_string(ThemeDB.fallback_font, Vector2(x-7, floor_y+32), "F", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, color)
		var points := PackedVector2Array()
		for k in range(22):
			var t := float(k)/21*.73
			points.append(Vector2(x+t*float(music.speed), floor_y-22-330*t+450*t*t))
		draw_polyline(points, Color(color, .26), 1.0, true)
	draw_line(Vector2(player.position.x, 124), Vector2(player.position.x, 446), Color("314e60"), 1)
	draw_circle(Vector2(player.position.x, floor_y+48), 6+beat_pulse*4, Color("6ce4c0"))

func _capture() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(screenshot_path)
	print("CAPTURE ", screenshot_path)
	get_tree().quit()
