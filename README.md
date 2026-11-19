# Beat Trail — music-driven rhythm platformer

Godot 4.7 project for the AIST2010 audio-analysis coursework. The music is the master
clock: the level is not authored, it is generated at runtime from a *chart* that a Python
pipeline derives from the audio file.

- Main scene: `scenes/song_menu.tscn` → `scenes/game.tscn`
- Chart preview scene: `scenes/chart_preview.tscn`

## Quick start

1. Open the project folder in Godot 4.7.x (the project file is `project.godot`).
2. Press **F5** → the song menu lists every valid chart in `assets/maps/`.
3. Pick a track and play.

| Key | Action |
|---|---|
| `J` | straight punch (lane 0, attack) |
| `K` | uppercut (lane 1, defend) |
| `F` / `Space` | jump (lane 2) |
| `R` | restart |
| `Esc` | pause / resume |

## How a run works

The player auto-runs; the song clock drives everything. Each chart note becomes level
geometry:

- **lane 2 (jump)** → a gap in the ground; the yellow ↑ marks the timing
- **lane 0 (attack)** → a red target flying in from the right
- **lane 1 (defend)** → a blue target coming from above
- **note with `duration`** → a hold, drawn as a tail behind the target

Lane ↔ timbre intent: `0` mid/high percussive (hats, snare), `1` harmonic (vocal,
melody, pads), `2` low percussive (kick, bass).

Judgement (`scripts/chart_level.gd`): **Perfect** within ±55 ms, **Good** inside the
lane window (attack/defend ±120 ms, jump ±90 ms), **Miss** on timeout. A hold needs 50 %
of its length held for Good and 90 % for Perfect, so releasing early costs the note.

## Repository layout

```
project.godot          project settings, input map
scenes/                song_menu, game, chart_preview, hud, player, targets
scripts/
  *.gd                 runtime: chart loading, judging, audio clock, drawing, HUD
  *.py                 offline chart pipeline (see below)
assets/
  maps/                playable charts (chart v2 JSON)
  analysis/            timbre-group documents written next to a chart
  voxel_30s.ogg        demo track
  shape/, kenney_.../  art used by the game
  MUSIC_LICENSE.md     attribution for the demo track
samples/               local test audio, git-ignored, not imported by Godot
```

## Chart pipeline (Python)

Offline only — the game never runs Python. Requires Python 3.10+ with `numpy`, `scipy`
and `soundfile` (`requirements.txt`); FFmpeg is **not** needed, `soundfile` decodes
Ogg/MP3/WAV/FLAC directly.

```
audio ──► audio_features ──► timbre_grouping ──► notes ──► chart JSON ──► Godot
              │                    ▲                                     │
              └──► beat_tracker ───┘                     (gaps/targets at runtime)
                                   └──► timbre_export ──► timbre document ──► timbre_groups.gd
```

| File | Kind | Purpose |
|---|---|---|
| `audio_features.py` | library | decode, 22.05 kHz mono, Hann 2048/hop 512, MFCC 0–12, flatness, log-RMS, attack slope, SuperFlux |
| `beat_tracker.py` | library | autocorrelation tempo (80–180 BPM) + DP beat backtrace, downbeats |
| `timbre_grouping.py` | library | k-means++ → diagonal GMM (EM), `q_g(t)`, smoothing, `o_g(t)=q_g(t)·SF(t)`, adaptive per-group peak picking, group→lane naming |
| `timbre_export.py` | library | builds the timbre document |
| `generate_chart.py` | **CLI** | full chain → chart JSON (+ timbre document with `--groups-json`) |
| `export_timbre_groups.py` | **CLI** | analysis only → timbre document |
| `evaluate_chart.py` | **CLI** | validation, playability, pooled/grouped + smoothing ablations, label stability (ARI), optional F1 |

### Generate a chart

```powershell
python scripts/generate_chart.py `
  --audio assets/voxel_30s.ogg `
  --output assets/maps/chart_timbre.json `
  --groups-json assets/analysis/voxel_30s_timbre.json `
  --title "Voxel Revolution" --artist "Kevin MacLeod" --license "CC BY 4.0"
```

Useful flags: `--difficulty easy|normal|hard` (density, default `normal`), `--groups 3`,
`--seed`, `--sigma` (group smoothing), `--min-spacing`, `--no-holds`,
`--mode pooled` (ablation baseline), `--map "0:1,1:2,2:0"` (override lane naming).

### Evaluate

```powershell
python scripts/evaluate_chart.py --chart assets/maps/chart_timbre.json --audio assets/voxel_30s.ogg
```

Reports the same validity rules Godot's loader applies, note/beat density, minimum gaps
per lane, hold count, lane entropy and onset counts before playability filtering.

## Adding a track

1. Put the audio inside the project (e.g. `assets/mysong.ogg`) — the game can only load
   `res://` resources. Formats: OGG, MP3, WAV, FLAC.
2. Run `generate_chart.py` as above with `--output assets/maps/mysong.json`.
3. Open the project in Godot **once** so the audio is imported.
4. F5 — the track appears in the menu.

Two things that silently hide a chart from the menu:

- **Never pass `--stream` with a made-up filename.** It defaults to the `--audio` file
  name, which is exactly the path the menu validates. The generator now prints a warning
  when the stream does not exist.
- **Audio must be imported first.** `song_menu.gd` skips charts whose `audio.stream`
  is not an imported `AudioStream`.

One JSON per difficulty; give each a distinct `--title`, otherwise the menu shows
identical-looking entries.

## Chart JSON (version 2)

```jsonc
{
  "version": 2,
  "audio":   { "stream": "res://assets/voxel_30s.ogg", "title": "...",
               "artist": "...", "license": "...", "duration": 30.0, "offset": 0.0 },
  "timing":  { "bpm": 123.047, "beats": [...], "downbeats": [...] },
  "chart":   { "lanes": ["attack", "defend", "jump"],
               "notes": [ { "time": 1.76, "lane": 2 },
                          { "time": 19.71, "lane": 1, "duration": 0.418 } ] }
}
```

`lane` is an index into `lanes`; `duration` (seconds) marks a hold and is ignored on the
jump lane. An extra `analysis` block records how the chart was produced.

## Timbre-group document

`assets/analysis/*_timbre.json` is the analysis layer under a chart: the groups that were
found, which lane each drives, every candidate onset and the per-frame dominant group.
It is optional for gameplay and loaded on demand:

```gdscript
const Timbre = preload("res://scripts/timbre_groups.gd")
var result := Timbre.load_document("res://assets/analysis/voxel_30s_timbre.json")
if result.ok:
    var jump_group := Timbre.group_for_lane(result.data, 2)
    var group_now := Timbre.dominant_group_at(result.data, 5.0)
```

## Chart preview

Open `scenes/chart_preview.tscn` and press **F6**. Notes scroll right-to-left and hit the
centre line at their chart time. `Space` pauses/resumes, `←`/`→` seek ±5 s, and the bottom
slider scrubs.

## Local test audio

`samples/` is a git-ignored scratch folder for audio you do not want to commit. It holds a
`.gdignore` so Godot never imports it, and only that file is tracked. Copy a file into
`assets/` before charting:

```powershell
copy samples\Lullaby.mp3 assets\
python scripts/generate_chart.py --audio assets/Lullaby.mp3 `
  --output assets/maps/lullaby.json `
  --groups-json assets/analysis/lullaby_timbre.json `
  --title "Lullaby"
```

## Music and art licences

- Demo track: **Voxel Revolution — Kevin MacLeod**, CC BY 4.0. Full attribution in
  `assets/MUSIC_LICENSE.md`; the 30 s excerpt is the original 00:28–00:58 with fades.
- Art: Kenney *Shape Characters*, see `assets/kenney_shape_characters/License.txt`.

## 中文速览

- 主场景 `scenes/song_menu.tscn`，选曲后进入 `scenes/game.tscn`；`F5` 运行。
- 操作：`J` 直拳，`K` 上勾拳，`F`/`Space` 跳跃，`R` 重开，`Esc` 暂停。
- 关卡由谱面生成：lane 2 生成地面缺口，lane 0/1 生成左右/上方飞来的目标，带
  `duration` 的 note 为长按。判定 Perfect ±55 ms，Good 直拳/上勾拳 ±120 ms、跳跃 ±90 ms。
- 谱面由离线 Python 生成：`python scripts/generate_chart.py --audio assets/xxx.ogg
  --output assets/maps/xxx.json --groups-json assets/analysis/xxx_timbre.json`。
  不需要 FFmpeg；音频放入 `assets/` 后需先用 Godot 打开一次完成导入，否则菜单不会显示。
- 音乐许可见 `assets/MUSIC_LICENSE.md`（CC BY 4.0）。
