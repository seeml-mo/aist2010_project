extends SceneTree

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game := preload("res://scripts/music_game.gd").new()
	game.test_mode = true
	game.autoplay = true
	root.add_child(game)
	await physics_frame
	check(game.audio.stream != null and absf(game.audio.stream.get_length()-30) < .1, "30s playable audio imported")
	for code in [KEY_F, KEY_SPACE]:
		var key := InputEventKey.new()
		key.physical_keycode = code
		check(InputMap.event_is_action(key, "jump"), "Jump alias registered")
	for code in [KEY_J, KEY_K]:
		var key := InputEventKey.new()
		key.physical_keycode = code
		check(InputMap.event_is_action(key, "attack"), "Attack alias registered")
	# A mistimed attack animates but cannot remove an upcoming target.
	game._inject_key(KEY_J)
	await physics_frame
	check(game.attack_hits == 0, "Early attack cannot score")
	for i in range(1900):
		await physics_frame
		if game.failed or game.finished:
			break
	check(not game.failed, "All beat-timed gaps traversed using real collision")
	check(game.finished, "Auto-run reaches end of music")
	check(game.jump_hits == game.music.jumps.size(), "All scheduled jumps accept alternating F and Space input")
	check(game.attack_hits == game.music.attacks.size(), "All onset targets accept alternating J and K input")
	check(game.misses == 0, "No targets missed in scheduled play")
	check(absf(game.player.position.x-(game.world.spawn.x+game.song_time*game.music.speed)) < 3, "Horizontal distance follows song clock")
	print("MUSIC_TEST completed=", game.finished, " failed=", game.failed, " jumps=", game.jump_hits, " hits=", game.attack_hits, " t=", game.song_time)
	game.queue_free()
	await process_frame
	var idle_game := preload("res://scripts/music_game.gd").new()
	idle_game.test_mode = true
	root.add_child(idle_game)
	for i in range(600):
		await physics_frame
		if idle_game.failed:
			break
	check(idle_game.failed, "Ordinary play requires user jump input; no hidden autoplay")
	print("MUSIC_SMOKE_RESULT failures=", failures)
	quit(0 if failures == 0 else 1)
