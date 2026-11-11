extends Node2D
## Audio is the master clock. Horizontal position is a function of song time.

const Player = preload("res://scripts/player.gd")
const Map = preload("res://scripts/json_map.gd")
var player: Player
var world: Map
var music: Dictionary
var audio: AudioStreamPlayer
var camera: Camera2D
var heading: Label
var status: Label
var controls: Label
var timer_label: Label
var title_panel: ColorRect
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
var attack_results: Dictionary = {}
var bot_jumps: Dictionary = {}
var bot_attacks: Dictionary = {}
var beat_pulse := 0.0

func _ready() -> void:
	_configure_input()
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
		set_physics_process(false)
		return
	music = data.music
	world = Map.new()
	add_child(world)
	if not world.load_map(path):
		push_error(world.last_error)
		get_tree().quit(1)
		return
	player = Player.new()
	player.automatic = true
	player.music_controlled = true
	player.spawn = world.spawn
	player.position = world.spawn
	player.target_x = world.spawn.x
	player.attack_pressed.connect(_attack)
	player.jump_pressed.connect(_jump)
	add_child(player)
	camera = Camera2D.new()
	camera.position = Vector2(player.position.x+256, 270)
	add_child(camera)
	audio = AudioStreamPlayer.new()
	audio.stream = load(str(music.stream))
	audio.volume_db = -4
	add_child(audio)
	_build_hud()
	# Start only after at least one physics frame lets the character settle.
	await get_tree().physics_frame
	if not test_mode:
		audio.play()
	print("MUSIC_READY beats=", music.beats.size(), " jumps=", music.jumps.size(), " attacks=", music.attacks.size())

func _configure_input() -> void:
	for action in ["jump", "attack", "restart"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	var keys := {"jump": [KEY_F, KEY_SPACE], "attack": [KEY_J, KEY_K], "restart": [KEY_R]}
	for action in keys:
		for code in keys[action]:
			var event := InputEventKey.new()
			event.physical_keycode = code
			if not InputMap.action_has_event(action, event):
				InputMap.action_add_event(action, event)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart") and not event.is_echo():
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
		for i in range(music.attacks.size()):
			if song_time > float(music.attacks[i].time)+.16 and not attack_results.has(i):
				attack_results[i] = false
				misses += 1
				_feedback("MISSED TARGET", Color("fb818f"))
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
	var best := -1
	var distance := .16
	for i in range(music.attacks.size()):
		var d := absf(float(music.attacks[i].time)-song_time)
		if d < distance and not attack_results.has(i):
			best = i
			distance = d
	if best >= 0 and absf(player.position.y-(float(music.floor_y)-21)) < 45:
		attack_results[best] = true
		attack_hits += 1
		_feedback("PERFECT HIT" if distance < .075 else "HIT", Color("fff0ae"))
	else:
		_feedback("NO TARGET IN REACH", Color("8d9db3"))

func _feedback(text: String, color: Color) -> void:
	feedback = text
	feedback_until = song_time+.45
	status.modulate = color

func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	title_panel = ColorRect.new()
	title_panel.color = Color("091321")
	title_panel.size = Vector2(960, 112)
	title_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(title_panel)
	heading = _label(canvas, Vector2(28, 14), "TIMBRE / QUEST", 28)
	_label(canvas, Vector2(30, 50), "RHYTHM RUNNER  /  BEAT + ONSET BASELINE", 12).modulate = Color("8d9db3")
	timer_label = _label(canvas, Vector2(630, 20), "", 16)
	status = _label(canvas, Vector2(30, 78), "", 15)
	var bottom := ColorRect.new()
	bottom.color = Color("091321")
	bottom.position = Vector2(0, 462)
	bottom.size = Vector2(960, 78)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(bottom)
	controls = _label(canvas, Vector2(30, 478), "F / SPACE   JUMP          J / K   ATTACK          R   RESTART", 15)
	_label(canvas, Vector2(30, 506), "Music: Voxel Revolution - Kevin MacLeod | CC BY 4.0   /   AUTO-RUN", 11).modulate = Color("8d9db3")

func _label(parent: Node, pos: Vector2, text: String, size: int) -> Label:
	var label := Label.new()
	label.position = pos
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.modulate = Color("eef4ff")
	parent.add_child(label)
	return label

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
	for i in range(music.attacks.size()):
		var event = music.attacks[i]
		var x := world.spawn.x+float(event.time)*float(music.speed)
		if x < left-40 or x > right+40:
			continue
		if attack_results.get(i, false):
			if song_time-float(event.time) < .3:
				draw_arc(Vector2(x, floor_y-25), 24+maxf(0, song_time-float(event.time))*70, 0, TAU, 28, Color("fff0ae"), 2)
			continue
		var y := floor_y-25
		var color := Color("fb818f") if not attack_results.has(i) else Color("514153")
		draw_colored_polygon(PackedVector2Array([Vector2(x, y-17), Vector2(x+15, y), Vector2(x, y+17), Vector2(x-15, y)]), color)
		draw_circle(Vector2(x, y), 5, Color("091321"))
		draw_string(ThemeDB.fallback_font, Vector2(x-13, y-32), "J/K", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)
	draw_line(Vector2(player.position.x, 124), Vector2(player.position.x, 446), Color("314e60"), 1)
	draw_circle(Vector2(player.position.x, floor_y+48), 6+beat_pulse*4, Color("6ce4c0"))

func _capture() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(screenshot_path)
	print("CAPTURE ", screenshot_path)
	get_tree().quit()
