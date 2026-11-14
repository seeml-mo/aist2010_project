# Rhythm Platformer

Godot 4.7.2 项目。主场景是 `scenes/game.tscn`；谱面预览场景是 `scenes/chart_preview.tscn`。

## 玩法

- `F / Space`：跳跃
- `J`：直拳
- `K`：上勾拳
- `R`：重新开始

玩家自动向右跑。关卡完全由 `assets/maps/chart_band.json` 生成：

- 黄色 ↑ 提示跳跃时机。地面和坑洞是谱面可视化，跳跃用音频时钟驱动的动画表现
- 从右方飞入的红色敌人对应中高频打击乐（如军鼓、踩镲），从正上方飞入的蓝色敌人对应中高频谐波（如人声、旋律、铺底音色），黄色箭头对应低频打击瞬态（如底鼓）
- 长按节点显示为长条。判定分为 Perfect / Good / Miss 三档：误差在 ±55 ms 内为 Perfect，在对应输入窗口内（直拳/上勾拳 ±120 ms，跳跃 ±90 ms）为 Good，超时漏按或长按提前松开为 Miss。左上角显示三档计数、进度和操作键

## 目录

- `scenes/game.tscn`：主游戏
- `scenes/chart_preview.tscn`：谱面预览
- `scenes/player.tscn`、`scenes/hud.tscn`
- `scripts/generate_chart.py`：分带 onset 谱面生成器（唯一算法）
- `scripts/chart_loader.gd`：chart JSON 加载与校验
- `scripts/chart_level.gd`：独立于场景的谱面判定（Perfect / Good / Miss）
- `scripts/music_game.gd`：音频时钟、输入、关卡绘制和左上角文字
- `scripts/chart_preview.gd`：谱面预览
- `scripts/player.gd`：纯显示的角色动画
- `assets/maps/chart_band.json`：当前谱面
- `assets/shape/`：游戏内使用的 Kenney Shape Characters 素材子集（Double 分辨率）与自定义 SVG
- `assets/kenney_shape_characters/`：完整的 Kenney Shape Characters 素材包（Default / Double PNG、Spritesheet、Vector 与授权文件）
- `assets/voxel_30s.ogg`：音乐

## 谱面生成

需要 Python 3、FFmpeg，以及 `.venv` 中的 numpy/scipy：

```text
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python scripts/generate_chart.py --output assets/maps/chart_band.json
```

`--difficulty easy|normal|hard` 控制密度，默认 `normal`。选点时优先考虑接近拍点、半拍和小节首拍的音频起音，并保留起音的时间。Normal 在任意半开 2 秒窗口内最多放 4 个节点。

谱面 JSON 只包含谱面关键信息：

- `audio`：音频路径、时长、标题、许可
- `timing`：BPM、beats、downbeats
- `chart.notes`：每个 note 只有 `time`、`lane`（0=attack、1=defend、2=jump）和可选的 `duration`（攻击或防御长按）

主场景根据谱面时间绘制地面、缺口和炮弹。角色节点不参与物理、输入或判定。

## 预览

打开 `scenes/chart_preview.tscn` 后按 F6。预览中：

- 谱面从右往左移动
- Space 暂停/继续
- ← / → 前后 5 秒
- 拖动底部进度条调整位置

## 音乐

Music: Voxel Revolution - Kevin MacLeod | CC BY 4.0。完整许可见 `MUSIC_LICENSE.md`。
