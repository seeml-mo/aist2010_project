extends Control

const ChartLoader = preload("res://scripts/chart_loader.gd")
const GAME_SCENE := "res://scenes/game.tscn"
const MAPS_DIR := "res://assets/maps"

@onready var songs: ItemList = %Songs
@onready var song_title: Label = %SongTitle
@onready var song_artist: Label = %SongArtist
@onready var song_info: Label = %SongInfo
@onready var start: Button = %Start
@onready var auto_play: Button = %AutoPlay

var charts: Array[Dictionary] = []

func _ready() -> void:
	start.pressed.connect(_play_selected.bind(false))
	auto_play.pressed.connect(_play_selected.bind(true))
	songs.item_selected.connect(_show_track)
	songs.item_activated.connect(func(index: int): _open_chart(charts[index].path))
	var paths := DirAccess.get_files_at(MAPS_DIR)
	paths.sort()
	for file in paths:
		if file.get_extension().to_lower() != "json":
			continue
		var path := MAPS_DIR.path_join(file)
		var result := ChartLoader.load_chart(path)
		if not result.ok:
			continue
		var chart: Dictionary = result.chart
		var audio_path := str(chart.audio.stream)
		if not ResourceLoader.exists(audio_path, "AudioStream"):
			continue
		chart["path"] = path
		charts.append(chart)
		songs.add_item(str(chart.audio.get("title", file.get_basename())))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--chart="):
			# The game scene also accepts this option when run directly from the editor.
			if not get_tree().root.has_meta("opened_command_line_chart"):
				get_tree().root.set_meta("opened_command_line_chart", true)
				_open_chart.call_deferred(arg.trim_prefix("--chart="))
				return
	if charts.is_empty():
		song_title.text = "No playable tracks"
		song_artist.text = "Add a chart and its audio to load a track."
		start.disabled = true
		auto_play.disabled = true
		return
	var previous_path := str(get_tree().root.get_meta("selected_chart", ""))
	var selected := 0
	for index in range(charts.size()):
		if charts[index].path == previous_path:
			selected = index
			break
	songs.select(selected)
	songs.ensure_current_is_visible()
	_show_track(selected)
	start.grab_focus()

func _show_track(index: int) -> void:
	var chart := charts[index]
	var audio: Dictionary = chart.audio
	song_title.text = songs.get_item_text(index)
	song_artist.text = str(audio.get("artist", "Unknown artist"))
	var details := PackedStringArray()
	var bpm := float(chart.timing.get("bpm", 0))
	var duration := float(audio.get("duration", 0))
	if bpm > 0.0:
		details.append("%d BPM" % roundi(bpm))
	if duration > 0.0:
		details.append("%d:%02d" % [floori(duration / 60.0), int(duration) % 60])
	details.append("%d NOTES" % chart.chart.notes.size())
	song_info.text = "  ·  ".join(details)

func _play_selected(autoplay: bool) -> void:
	var selected := songs.get_selected_items()
	if not selected.is_empty():
		_open_chart(charts[selected[0]].path, autoplay)

func _open_chart(path: String, autoplay: bool = false) -> void:
	get_tree().root.set_meta("selected_chart", path)
	get_tree().root.set_meta("autoplay_mode", autoplay)
	get_tree().change_scene_to_file(GAME_SCENE)
