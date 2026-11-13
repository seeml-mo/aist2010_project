extends Node2D
## Chart preview: notes travel right-to-left, hit the centre line at their
## chart time, and audio is the master clock. Level generation is not involved.

const ChartLoader = preload("res://scripts/chart_loader.gd")

const LANE_NAMES := [
	"STRAIGHT  ·  HATS / SNARE",
	"UPPERCUT  ·  VOCAL / MELODY / PADS",
	"JUMP  ·  KICK / BASS",
]
const LANE_COLORS := [Color("ff4d5e"), Color("4da3ff"), Color("f2c14e")]
const TOP_Y := 72.0
const BOTTOM_Y := 468.0
const SCREEN_W := 960.0

@export var chart_path := "res://assets/maps/chart_band.json"
@export var scroll_speed := 240.0
@export var center_x := 480.0
@export var lane_ys: Array[float] = [170.0, 270.0, 370.0]

@onready var music: AudioStreamPlayer = $Music
@onready var title_label: Label = $HUD/TopPanel/TitleLabel
@onready var info_label: Label = $HUD/TopPanel/InfoLabel
@onready var status_label: Label = $HUD/TopPanel/StatusLabel
@onready var play_button: Button = $HUD/BottomPanel/PlayButton
@onready var progress: HSlider = $HUD/BottomPanel/Progress
@onready var time_label: Label = $HUD/BottomPanel/TimeLabel

var chart: Dictionary = {}
var notes: Array = []
var beats: Array = []
var duration := 0.0
var song_time := 0.0
var paused := true
var ended := false
var dragging := false
var resume_after_drag := false
var lane_glow: Array[float] = [0.0, 0.0, 0.0]

func _ready() -> void:
	progress.drag_started.connect(_on_progress_drag_started)
	progress.drag_ended.connect(_on_progress_drag_ended)
	progress.value_changed.connect(_on_progress_value_changed)
	play_button.pressed.connect(_toggle_pause)

	if not _load_chart(chart_path, 0.0, true):
		play_button.disabled = true
		progress.editable = false

func _load_chart(path: String, keep_time: float, keep_paused: bool) -> bool:
	var result: Dictionary = ChartLoader.load_chart(path)
	if not bool(result.get("ok", false)):
		_show_error(str(result.get("error", "Unknown chart error")))
		return false

	var data: Dictionary = result.chart
	var stream_path := str(data.audio.stream)
	var stream := load(stream_path) as AudioStream
	if stream == null:
		_show_error("Cannot load audio: " + stream_path)
		return false

	var chart_duration := float(data.audio.get("duration", 0.0))
	var stream_duration := stream.get_length()
	var new_duration := chart_duration
	if chart_duration > 0.0 and stream_duration > 0.0:
		new_duration = minf(chart_duration, stream_duration)
	elif stream_duration > 0.0:
		new_duration = stream_duration
	if new_duration <= 0.0:
		_show_error("Chart/audio duration is zero")
		return false

	music.stop()
	music.stream = stream
	chart = data
	notes = chart.chart.notes
	beats = chart.timing.get("beats", [])
	duration = new_duration
	song_time = clampf(keep_time, 0.0, maxf(0.0, duration - 0.01))
	ended = false
	paused = keep_paused
	dragging = false
	resume_after_drag = false
	lane_glow = [0.0, 0.0, 0.0]

	progress.min_value = 0.0
	progress.max_value = duration
	progress.step = 0.01
	progress.set_value_no_signal(song_time)
	progress.editable = true

	music.play(song_time)
	music.stream_paused = paused
	play_button.disabled = false
	play_button.text = "PLAY" if paused else "PAUSE"

	var bpm := float(chart.timing.get("bpm", 0.0))
	title_label.text = "%s  /  %s" % [str(chart.audio.get("title", "Untitled")), str(chart.audio.get("artist", "Unknown"))]
	info_label.text = "BAND   %d BPM   %d notes   %.2f s   %d lanes" % [
		roundi(bpm),
		notes.size(),
		duration,
		int(chart.chart.get("lanes", []).size()),
	]
	status_label.modulate = Color.WHITE
	status_label.text = "PAUSED  /  SPACE to play" if paused else "PLAYING  /  SPACE to pause"

	chart_path = path
	_update_time_label()
	queue_redraw()
	return true

func _show_error(message: String) -> void:
	status_label.text = "ERROR: " + message
	status_label.modulate = Color("b82143")
	push_error(message)

func _process(_delta: float) -> void:
	if chart.is_empty():
		return

	if not paused and not dragging and not ended and music.playing and not music.stream_paused:
		var clock := music.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
		song_time = clampf(clock, 0.0, duration)
		if song_time >= duration - 0.02:
			_finish()

	if not dragging:
		progress.set_value_no_signal(song_time)

	lane_glow = [0.0, 0.0, 0.0]
	for note in notes:
		var distance := absf(float(note.time) - song_time)
		if distance < 0.12:
			var lane := int(note.lane)
			lane_glow[lane] = maxf(lane_glow[lane], 1.0 - distance / 0.12)

	_update_time_label()
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return

	if event.keycode == KEY_SPACE or event.physical_keycode == KEY_SPACE:
		_toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_LEFT or event.physical_keycode == KEY_LEFT:
		seek_to(song_time - 5.0)
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_RIGHT or event.physical_keycode == KEY_RIGHT:
		seek_to(song_time + 5.0)
		get_viewport().set_input_as_handled()

func _toggle_pause() -> void:
	if chart.is_empty():
		return

	if ended:
		ended = false
		seek_to(0.0)

	if paused:
		if not music.playing:
			music.play(song_time)
		music.stream_paused = false
		paused = false
		play_button.text = "PAUSE"
		status_label.text = "PLAYING  /  SPACE to pause"
	else:
		music.stream_paused = true
		paused = true
		play_button.text = "PLAY"
		status_label.text = "PAUSED  /  SPACE to resume"

func seek_to(target: float) -> void:
	if chart.is_empty():
		return

	song_time = clampf(target, 0.0, duration)
	ended = false

	if music.playing:
		music.seek(song_time)
		music.stream_paused = paused
	else:
		music.play(song_time)
		music.stream_paused = paused

	progress.set_value_no_signal(song_time)
	_update_time_label()
	queue_redraw()

func _finish() -> void:
	song_time = duration
	paused = true
	ended = true
	music.stop()
	music.stream_paused = false
	play_button.text = "REPLAY"
	status_label.text = "END  /  SPACE to replay"
	progress.set_value_no_signal(duration)
	_update_time_label()
	queue_redraw()

func _on_progress_drag_started() -> void:
	dragging = true
	resume_after_drag = not paused and not ended
	if resume_after_drag:
		music.stream_paused = true

func _on_progress_value_changed(value: float) -> void:
	if dragging:
		song_time = clampf(value, 0.0, duration)
		ended = false
		_update_time_label()
		queue_redraw()
	else:
		seek_to(value)

func _on_progress_drag_ended(_value_changed: bool) -> void:
	dragging = false
	seek_to(song_time)
	if resume_after_drag:
		music.stream_paused = false
		paused = false
		play_button.text = "PAUSE"
		status_label.text = "PLAYING  /  SPACE to pause"
	resume_after_drag = false

func _update_time_label() -> void:
	time_label.text = "%s / %s" % [_format_time(song_time), _format_time(duration)]

func _format_time(value: float) -> String:
	var minutes := int(value / 60.0)
	var seconds := value - float(minutes) * 60.0
	return "%d:%05.2f" % [minutes, seconds]

func _draw() -> void:
	if chart.is_empty():
		return

	# Lane bands, gently lit while a note is close to the hit line.
	for i in range(LANE_NAMES.size()):
		var y := lane_ys[i]
		var color: Color = LANE_COLORS[i]
		var glow := lane_glow[i]
		draw_rect(Rect2(0.0, y - 32.0, SCREEN_W, 64.0), Color(color, 0.035 + 0.09 * glow), true)
		draw_line(Vector2(0.0, y), Vector2(SCREEN_W, y), Color(color, 0.22 + 0.55 * glow), 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(18.0, y - 10.0), LANE_NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(color, 0.85))
		if glow > 0.0:
			draw_circle(Vector2(center_x, y), 9.0 + 13.0 * glow, Color(color, 0.22 * glow))

	# Beat ticks near the bottom edge of the playfield.
	for beat in beats:
		var beat_x := center_x + (float(beat) - song_time) * scroll_speed
		if beat_x >= 0.0 and beat_x <= SCREEN_W:
			draw_line(Vector2(beat_x, BOTTOM_Y - 18.0), Vector2(beat_x, BOTTOM_Y), Color("314e60"), 1.0)

	# Hit line.
	draw_line(Vector2(center_x, TOP_Y), Vector2(center_x, BOTTOM_Y), Color("294766"), 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(center_x + 8.0, TOP_Y + 18.0), "HIT", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("294766"))

	# Notes. A note is exactly on the hit line when song_time == note.time.
	for note in notes:
		var y: float = lane_ys[int(note.lane)]
		var color: Color = LANE_COLORS[int(note.lane)]
		var head_x := center_x + (float(note.time) - song_time) * scroll_speed

		if note.has("duration"):
			var tail_x := head_x + float(note.duration) * scroll_speed
			if tail_x < -80.0 or head_x > SCREEN_W + 80.0:
				continue

			var left := minf(head_x, tail_x)
			var right := maxf(head_x, tail_x)
			draw_rect(Rect2(left, y - 9.0, right - left, 18.0), Color(color, 0.22), true)
			draw_line(Vector2(left, y), Vector2(right, y), Color(color, 0.75), 2.0)
			draw_colored_polygon(_diamond(head_x, y, 13.0), color)
			draw_rect(Rect2(tail_x - 2.0, y - 8.0, 4.0, 16.0), Color(color, 0.9), true)
		else:
			if head_x < -40.0 or head_x > SCREEN_W + 40.0:
				continue
			draw_colored_polygon(_diamond(head_x, y, 13.0), color)

func _diamond(x: float, y: float, radius: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(x, y - radius),
		Vector2(x + radius, y),
		Vector2(x, y + radius),
		Vector2(x - radius, y),
	])
