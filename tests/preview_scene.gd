extends SceneTree
## Visual QA with temporary input bindings, without modifying project settings.

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	preload("res://tests/input_fixture.gd").configure()
	var game := preload("res://scenes/game.tscn").instantiate()
	game.autoplay = true
	game.screenshot_path = "res://test-output/scene_preview.png"
	game.screenshot_at = 6.5
	root.add_child(game)
