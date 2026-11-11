extends SceneTree

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world := preload("res://scripts/json_map.gd").new()
	root.add_child(world)
	check(world.load_map("res://maps/platform.kenney.json"), "Public adapted fixture loads")
	check(world.cell_count == 443, "443 occupied cells survive adapter")
	check(world.get_child_count() == 1, "One TileMapLayer")
	var layer = world.get_child(0)
	check(layer.get_used_cells().size() == 443, "Actual TileMap has 443 cells")
	check(layer.get_cell_atlas_coords(Vector2i(3, 32)) == Vector2i(5, 2), "Tiled GID 46 maps to atlas (5,2)")
	check(world.load_map("res://maps/platform.kenney.json"), "Reload succeeds")
	check(world.get_child_count() == 1, "Reload does not duplicate layers")
	DirAccess.make_dir_recursive_absolute("res://test-output")
	var invalid = JSON.parse_string(FileAccess.get_file_as_string("res://maps/platform.kenney.json"))
	invalid.layers[0].data.pop_back()
	var file := FileAccess.open("res://test-output/invalid.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(invalid))
	file.close()
	# Keep image resolution valid so this test reaches data validation.
	invalid.tilesets[0].image = "../assets/kenney_tiles.png"
	check(not world.load_map("res://test-output/invalid.json"), "Truncated JSON tile array rejected")
	check(world.cell_count == 443 and world.get_child_count() == 1, "Failed load preserves previous map")
	var player := preload("res://scripts/player.gd").new()
	player.automatic = true
	player.position = world.spawn
	root.add_child(player)
	for i in range(90):
		await physics_frame
	check(player.is_on_floor(), "Character lands on generated collision")
	check(absf(player.position.y - 505.0) < 1.0, "Floor height matches JSON row 32")
	var ground_y := player.position.y
	player.velocity.y = -330
	for i in range(15):
		await physics_frame
	check(player.position.y < ground_y - 30, "Jump leaves generated floor")
	for i in range(100):
		await physics_frame
	check(player.is_on_floor(), "Character lands after jumping")
	player.queue_free()
	check(world.load_map("res://maps/demo.json"), "Controlled demo loads")
	check(world.get_child_count() == 2 and world.cell_count == 588, "Two layers contain 588 tiles")
	check(world.get_child(0).get_cell_source_id(Vector2i(23, 19)) == -1, "JSON gap remains empty")
	check(world.get_child(1).get_cell_source_id(Vector2i(14, 14)) == 0, "Floating platform placed from second layer")
	print("SMOKE_RESULT failures=", failures)
	quit(0 if failures == 0 else 1)
