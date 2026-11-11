extends Node2D
## JSON supplies event times; this component instantiates and manages Enemy scenes.

signal enemy_defeated(event_index: int, timing_error: float)
signal enemy_missed(event_index: int)

@export var enemy_scene: PackedScene
@export var lookahead_seconds := 6.0
@export var cleanup_seconds := 2.0

var events: Array = []
var next_event := 0
var origin_x := 0.0
var speed := 150.0
var floor_y := 384.0
var results: Dictionary = {}
var spawned_count := 0

@onready var enemies: Node2D = $Enemies

func configure(attack_events: Array, start_x: float, run_speed: float, ground_y: float) -> void:
	for enemy in enemies.get_children():
		enemies.remove_child(enemy)
		enemy.queue_free()
	events = attack_events.duplicate(true)
	results.clear()
	next_event = 0
	spawned_count = 0
	origin_x = start_x
	speed = run_speed
	floor_y = ground_y
	update_time(0)

func update_time(song_time: float) -> void:
	while next_event < events.size() and float(events[next_event].time) <= song_time+lookahead_seconds:
		var enemy = enemy_scene.instantiate()
		enemy.event_index = next_event
		enemy.hit_time = float(events[next_event].time)
		enemy.defeated.connect(_on_enemy_defeated)
		enemy.missed.connect(_on_enemy_missed)
		enemies.add_child(enemy)
		enemy.global_position = Vector2(origin_x+enemy.hit_time*speed, floor_y-25)
		next_event += 1
		spawned_count += 1
	for enemy in enemies.get_children():
		enemy.update_time(song_time)
		if song_time > enemy.hit_time+cleanup_seconds:
			enemies.remove_child(enemy)
			enemy.queue_free()

func try_attack(song_time: float, player_position: Vector2) -> bool:
	for enemy in enemies.get_children():
		if enemy.try_hit(song_time, player_position):
			return true
	return false

func _on_enemy_defeated(event_index: int, timing_error: float) -> void:
	results[event_index] = true
	enemy_defeated.emit(event_index, timing_error)

func _on_enemy_missed(event_index: int) -> void:
	results[event_index] = false
	enemy_missed.emit(event_index)
