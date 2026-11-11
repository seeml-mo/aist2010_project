# Player assets

当前 Player scene 使用手动配置的 AnimatedSprite2D：

- idle/idle.png → idle
- walk/walk_0.png、walk/walk_1.png → walk
- jump/jump.png → jump
- attack/attack.png → attack

帧顺序、FPS、Loop、碰撞形状在 scenes/player.tscn 中编辑。角色 PNG 均为 96×64。
攻击图片拳头距中心 24px，对应 Player 的 Inspector 参数 Attack Reach；无需切换身体碰撞形状。
