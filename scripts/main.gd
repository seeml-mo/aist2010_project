extends Node2D

func _ready() -> void:
	var path := "res://maps/demo.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			path = arg.trim_prefix("--map=")
	var world := preload("res://scripts/json_map.gd").new()
	add_child(world)
	if not world.load_map(path):
		push_error(world.last_error)
		get_tree().quit(1)
		return
	var player := preload("res://scripts/player.gd").new()
	player.spawn = world.spawn
	player.position = world.spawn
	add_child(player)
	var camera := Camera2D.new()
	camera.zoom = Vector2(2, 2)
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(world.map_size.x)
	camera.limit_bottom = int(world.map_size.y)
	player.add_child(camera)
	var hud := CanvasLayer.new()
	var label := Label.new()
	label.position = Vector2(20, 16)
	label.text = "JSON -> TileMapLayer -> collision\nA/D or arrows: move | Space: jump | R: reset\n%s | %d tiles" % [path.get_file(), world.cell_count]
	hud.add_child(label)
	add_child(hud)
	print("MAP_LOADED ", world.cell_count, " cells; spawn=", world.spawn)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			await get_tree().create_timer(1.0).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--screenshot="))
			get_tree().quit()
