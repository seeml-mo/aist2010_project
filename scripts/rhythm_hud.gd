extends CanvasLayer

const ChartRun = preload("res://scripts/chart_level.gd")
const JUDGMENTS := ["MISS", "GOOD", "PERFECT"]

signal pause_requested
signal resume_requested
signal restart_requested
signal menu_requested

@onready var counters: Array[Label] = [%Miss, %Good, %Perfect]
@onready var score: Label = %Score
@onready var progress: ProgressBar = %Progress
@onready var pause_button: Button = %Pause
@onready var auto_badge: Label = %AutoBadge
@onready var overlay: Control = %Overlay
@onready var panel_title: Label = %PanelTitle
@onready var panel_detail: Label = %PanelDetail
@onready var results: Control = %Results
@onready var result_score: Label = %ResultScore
@onready var result_counts: Label = %ResultCounts
@onready var primary: Button = %Primary
@onready var replay: Button = %Replay

var track_title := ""
var last_focus: Control

func _ready() -> void:
	pause_button.pressed.connect(func(): pause_requested.emit())
	primary.pressed.connect(func():
		if results.visible:
			restart_requested.emit()
		else:
			resume_requested.emit())
	replay.pressed.connect(func(): restart_requested.emit())
	%Menu.pressed.connect(func(): menu_requested.emit())

func set_track(title: String, duration: float) -> void:
	track_title = title
	%Track.text = title
	progress.max_value = duration
	update_time(0.0)

func update_time(time: float) -> void:
	progress.value = time
	%Clock.text = "%s / %s" % [_format_time(time), _format_time(progress.max_value)]

func update_counts(run: ChartRun) -> void:
	var values := [run.misses, run.goods, run.perfects]
	for i in range(counters.size()):
		counters[i].text = "%s  %02d" % [JUDGMENTS[i], values[i]]
	score.text = "%07d" % run.score()

func set_autoplay(enabled: bool) -> void:
	auto_badge.visible = enabled

func show_pause() -> void:
	_show_panel("Paused", track_title)
	results.hide()
	%PauseHint.show()
	primary.text = "Resume"
	primary.show()
	replay.show()
	primary.grab_focus()

func hide_pause() -> void:
	overlay.hide()
	if is_instance_valid(last_focus):
		last_focus.grab_focus()

func show_results(run: ChartRun) -> void:
	_show_panel("Track complete", track_title)
	result_score.text = "%07d" % run.score()
	result_counts.text = "Perfect %d     Good %d     Miss %d\n%.1f%% accuracy" % [
		run.perfects, run.goods, run.misses, run.accuracy() * 100.0]
	results.show()
	%PauseHint.hide()
	primary.text = "Play again"
	primary.show()
	replay.hide()
	pause_button.disabled = true
	primary.grab_focus()

func show_error(message: String) -> void:
	_show_panel("Track unavailable", message)
	pause_button.disabled = true
	results.hide()
	%PauseHint.hide()
	primary.hide()
	replay.hide()
	%Menu.grab_focus()

func is_overlay_open() -> bool:
	return overlay.visible

func _show_panel(title: String, detail: String) -> void:
	last_focus = get_viewport().gui_get_focus_owner()
	panel_title.text = title
	panel_detail.text = detail
	overlay.show()

func _format_time(seconds: float) -> String:
	return "%d:%02d" % [floori(seconds / 60.0), int(seconds) % 60]
