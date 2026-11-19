# samples/

Scratch space for test audio (e.g. `Lullaby.mp3`). Everything in here is
git-ignored except this README and `.gdignore`, so no audio ever enters the
repository.

`.gdignore` stops Godot from scanning the folder, so these files are never
imported as project resources.

## Charting a track from here

The game can only load audio from `res://`, so copy the file into `assets/`
first, then run the generator:

```powershell
copy samples\Lullaby.mp3 assets\
D:\Anaconda3\envs\Learn\python.exe scripts/generate_chart.py `
  --audio assets/Lullaby.mp3 `
  --output assets/maps/lullaby.json `
  --groups-json assets/analysis/lullaby_timbre.json `
  --title "Lullaby" --artist "" --license ""
```

Omit `--stream`: it defaults to the `--audio` file name, which is the path the
song menu will check. Open the project in Godot once after copying the audio so
it gets imported, otherwise the chart is skipped in the menu.
