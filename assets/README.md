# Rhythm Platformer

Godot 4.7.2 项目。导入 project.godot 后按 F5；主场景是 scenes/game.tscn。

- F / Space：跳跃；J / K：攻击；R：重新开始。Input Map 在编辑器中配置。
- 音乐驱动自动前进；JSON 生成 TileMap、缺口和 Enemy。
- Enemy 的矩形宽高在 scene 中调整；Player 的 Attack Reach 默认为 24px。

## 目录

- scenes/：game、player、enemy、enemy_spawner、hud。
- scripts/：music_game.gd、player.gd、enemy.gd、enemy_spawner.gd、json_map.gd。
- scripts/analyze_music.py：离线 onset/beat 分析与 JSON 生成。
- assets/：音乐、角色图片、地形 atlas、maps/music_demo.json、许可与使用说明。

## 音乐分析

游戏直接读取已生成的 JSON 和 Ogg，正常运行不需要 Python。
需要重新分析时，安装 numpy、scipy、Pillow 和 FFmpeg，然后在项目根目录运行：

```text
python scripts/analyze_music.py --audio "path/to/Voxel Revolution.mp3" --ffmpeg "path/to/ffmpeg.exe"
```

当前脚本使用原曲 00:28–00:58 的 30 秒片段，提取 spectral-flux onset 和 beat，生成 music_demo.json、voxel_30s.ogg 及 runner_tiles.png。不会修改手动配置的角色 scene、Input Map 或角色素材。
音乐许可见 MUSIC_LICENSE.md。

.gitignore 已排除 Godot 缓存、IDE 设置和 Python 缓存。分享时保留 .gd.uid、图片 .import 及素材许可。
