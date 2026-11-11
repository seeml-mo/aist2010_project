# Timbre / Quest — Godot playable baseline

Godot 4.5+。30 秒音乐自动横版跑酷，角色和地形风格对齐之前的离线 demo。地图布局来自 JSON，运行时创建 `TileMapLayer`、atlas 和碰撞。目前接入基础 onset/beat，尚未接入 timbre 路线、wing 连跳或 glide。

## 运行

在此目录运行 `./run.ps1`，或使用 Godot 导入 `project.godot` 后按 **F5**（运行整个项目）。

默认运行 `maps/music_demo.json`，播放与 integrated video 相同的 Voxel Revolution 00:28–00:58 片段。横向位置由音乐时钟决定，角色固定在屏幕左侧，摄像机自动跟随。

- **F / Space：跳跃；J / K：攻击；R：从音乐开头重新开始。** 两种核心动作，每种各有两个等效键；无需控制左右移动。
- 绿色弧线和 F 标记预告缺口起跳位置，红色菱形和 J/K 标记预告攻击目标。
- 跳跃有 120ms input buffer 和 80ms coyote time；攻击命中窗口 ±160ms，±75ms 显示 PERFECT HIT。
- 缺口需要实际跳跃才能越过；攻击目标为可击破的计分目标，漏打记 MISS，不阻挡角色。
- 掉落后停止音乐，按 R 重来；30 秒结束后显示完成。
- `./run.ps1 -Editor` 打开编辑器。
- `./run.ps1 -Test` 运行 JSON/物理回归测试和完整 30 秒节奏关卡测试。
- 换地图：`./run.ps1 -Map res://maps/your_map.json`。
- 第一次使用新安装的引擎，先打开编辑器导入资源，再运行测试。

## 数据流

音乐流程：`python tools/analyze_music.py` → `assets/voxel_30s.ogg` + `maps/music_demo.json` → `music_game.gd` → 音乐播放、TileMap 碰撞、自动前进与动作判定。

- **Onset**：STFT 正向 log spectral flux，局部中值基线扣除、平滑、peak picking。
- **Beat**：onset envelope 自相关估计周期，105–143 BPM 搜索先验；全片段周期/phase 搜索降低累积漂移，再在 ±35ms 内微调到局部 transient。
- **映射**：每隔四拍选一个 beat 创建跳跃缺口；距跳跃足够远的候选拍附近，选择 ±100ms 内检测到的 onset 作为攻击时刻。只选择部分事件，控制密度和可玩性。没有手工逐个填入事件时间，也不声称转录了所有鼓点。
- **同步**：`get_playback_position() + time_since_last_mix - output_latency` 驱动横向距离 `spawn_x + time * speed`。正式运行以音频为主时钟，测试模式才使用模拟时间。
- **画面**：与原视频相同的白色头盔、护目镜、飘带角色，深蓝背景、mint 地形和粉色攻击目标；基础地面由自编 atlas 生成，仍使用 JSON → TileMap 管线。

生成脚本需要 Python 的 numpy、scipy、Pillow，以及 FFmpeg。默认复用上级工作区现有音乐和 `tools/ffmpeg.exe`；也支持 `--audio` 和 `--ffmpeg` 指定路径。已有生成结果随仓库保存，**正常运行游戏不需要 Python 或 FFmpeg**。

QA 用的 `--autoplay` 会注入交替的 F/Space 和 J/K 输入；普通 F5 启动不启用它。`tests/music_smoke.gd` 检查全部缺口实际可通过、两组按键有效、过早攻击不能得分，以及不按键确实会掉落。

旧的纯地图流程保持可用：`./run.ps1 -Map res://maps/demo.json`（台阶/悬浮平台，A/D 左右移动），或 `./run.ps1 -Map res://maps/platform.kenney.json`（公开地图适配）。

`maps/platform.original.json`（网上原始样例）→ `python tools/adapt_map.py` → `maps/platform.kenney.json` → `scripts/json_map.gd` → TileMapLayer + collision。

原始地图为 Phaser examples 中的 Tiled platform map。适配脚本将 GID 0/1 当作空白/背景，其余已有图块位置映射到 Kenney 的表面/填充块，标为 solid。原始装饰图块也当作实体，这是验证管线的简化测试地图，不是最终关卡设计。

## 给后续音乐分析脚本的接口

输出与 `platform.kenney.json` 相同的 Tiled JSON：

- `width/height`：列数/行数；`tilewidth/tileheight`：16。
- `layers[].data`：长度为 width × height 的一维数组，按行排列，索引 `y * width + x`。
- 数值 0 是空白；46 是本样例表面图块，126 是填充图块。
- GID 是 **1-based**：`local_id = gid - firstgid`；atlas 坐标为 `(local_id % 20, local_id / 20)`。
- tilelayer 的 `properties` 中设置 `{ "name": "solid", "type": "bool", "value": true }` 即生成碰撞。
- objectgroup 的 point object `name: "spawn"` 设置玩家起点，x/y 为像素坐标（角色中心）。

Kenney 地图接口如上。新音乐关卡额外带 `music` 对象，保存 stream、duration、speed、floor_y、beats、onsets、jumps 和 attacks。自编 runner atlas 采用 GID 1 表面、GID 2 填充；其余空白仍为 0。无需手动在编辑器画地形。

支持：有限 orthogonal 地图、单个内嵌 atlas、多 tile layers、visibility/opacity、像素 offsetx/offsety、solid layer、spawn marker。
不支持：infinite/chunks、外部 TSX/TSJ、压缩/base64、翻转 GID、非正交地图。会明确报错。

## 来源

- 原始 JSON：https://github.com/phaserjs/examples/blob/master/public/assets/tilemaps/maps/platform.json
- 下载地址：https://raw.githubusercontent.com/phaserjs/examples/master/public/assets/tilemaps/maps/platform.json
- 公开地图只作学习和输入格式测试，保留原始来源；未使用原始图片素材。仓库根目录未提供可确认的许可证，因此不将该地图声明为 CC0，也不建议随正式发行版分发。默认 demo.json 为本项目自编布局。
- Kenney 1-Bit Platformer Pack：https://kenney.nl/assets/1-bit-platformer-pack ，CC0，见 `assets/KENNEY_LICENSE.txt`。
- 音乐来源、许可与修改信息见 `assets/MUSIC_LICENSE.md`。
- Godot 引擎便携版放在仓库外 `../tools/godot_4.5.2/`，不提交到 Git。
