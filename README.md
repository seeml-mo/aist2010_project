# JSON → Godot TileMap pipeline

Godot 4.5+。地图布局来自 JSON，运行时创建 `TileMapLayer`、atlas 和方形碰撞，玩家可以移动和跳跃。

## 运行

在此目录运行 `./run.ps1`，或使用 Godot 导入 `project.godot` 后按 F6/F5。

默认展示自编 `maps/demo.json`，包含高低台阶、缺口和第二层悬浮平台。公开地图适配样例可用 `./run.ps1 -Map res://maps/platform.kenney.json` 单独运行。

- A/D 或左右方向键：移动；Space：跳跃；R：重置。
- `./run.ps1 -Editor` 打开编辑器。
- `./run.ps1 -Test` 运行 Godot 实际 TileMap 和物理碰撞测试。
- 换地图：`./run.ps1 -Map res://maps/your_map.json`。
- 第一次使用新安装的引擎，先打开编辑器导入资源，再运行测试。

## 数据流

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

因此之后的分析程序只需生成 data 数组和 spawn；无需手动在编辑器画地形。此次暂未接入音乐分析或自动前进。

支持：有限 orthogonal 地图、单个内嵌 atlas、多 tile layers、visibility/opacity、像素 offsetx/offsety、solid layer、spawn marker。
不支持：infinite/chunks、外部 TSX/TSJ、压缩/base64、翻转 GID、非正交地图。会明确报错。

## 来源

- 原始 JSON：https://github.com/phaserjs/examples/blob/master/public/assets/tilemaps/maps/platform.json
- 下载地址：https://raw.githubusercontent.com/phaserjs/examples/master/public/assets/tilemaps/maps/platform.json
- 公开地图只作学习和输入格式测试，保留原始来源；未使用原始图片素材。仓库根目录未提供可确认的许可证，因此不将该地图声明为 CC0，也不建议随正式发行版分发。默认 demo.json 为本项目自编布局。
- Kenney 1-Bit Platformer Pack：https://kenney.nl/assets/1-bit-platformer-pack ，CC0，见 `assets/KENNEY_LICENSE.txt`。
- Godot 引擎便携版放在仓库外 `../tools/godot_4.5.2/`，不提交到 Git。
