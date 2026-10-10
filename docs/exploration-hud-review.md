# 探索 HUD 一屏改版

基线：`Furfur01/Hotel`，`271c67f`。范围：大厅 / 走廊探索时的屏幕信息。生产代码只修改 `hud.gd`，不改输入、控制器、游戏状态、场景几何、光照、音效或项目版本。

## 查看与操作

- 随本次交付附带的 `exploration-hud.html`：独立浏览器预览，可触摸 / 点击选择物品，调整体力、切换提示、对照原界面，以及查看原生渲染截图。背景取自实际运行的酒店场景；网页交互是演示，未运行 Godot 游戏逻辑。
- Godot 打开 `previews/exploration_hud.tscn`，按 F6 运行：真实游戏场景及 HUD，固定种子 424242，携带工作卡、拍立得及占两格的折叠陷阱。仅预览场景冻结时钟及巡逻，便于检查界面。WASD 移动、E 交互、R 切换动作、1–4 选物品、F 使用、G 放下、N 手记、按住 T 手表、I 整理附近已放下的旅行箱，沿用原输入。
- 正常 F5 运行 `hotel.tscn`：原有游戏流程，应用新的探索 HUD。冻结时间及预置物品不会进入主游戏。

## 当前 HUD 的完整连接

`game_root.gd` 实例化 `HotelHUD` 和玩家，再将 HUD 注入 `run_controller.configure()` / `player.configure_runtime()`。HUD 不处理游戏输入，控件默认忽略鼠标。玩家每帧更新体力、携带槽和地图；控制器每帧更新回合时间与领先倒计时。

| 界面 / 数据 | 来源与接口 | 现有操作 / 回传 | 本次处理 |
| --- | --- | --- | --- |
| 昼夜、天数、剩余时间、被抓次数 | 控制器 → `set_run_status()` → `watch_dial.set_state()` | 按住 T 看表，松开收起 | 手表完整保留；`_build_status()` 原本未调用，继续不显示顶部条 |
| 被抓红色暗角 | `set_run_status()` → `_run_strikes` → `_process()` | 0–3 次的透明度 | 保留 |
| 准星 / 当前操作 | 玩家射线和上下文动作 → `set_prompt()` | E 执行，R 切换；计时动作直接传入剩余秒数 | 缩小准星，提示置于中心下方，保留原始提示字符串；新目标淡入 0.16 秒 |
| 夜晚领先倒计时 | 控制器 → `set_head_start()`；兼容 `set_lead_time()` | 屏幕顶部红色秒数 | 保留 |
| 体力 | 玩家 → `set_stamina(value, max, sprinting)` | Shift 奔跑；低于 25% 变红 | 左下 210×4 细条，保留平滑更新、数值范围与透明度规则 |
| 四格携带栏 | 控制器状态 → `get_carry_slots_for_ui()` → 玩家 → `set_inventory()` | 1–4 选择，F 使用，G 放下 | 移至右下；去掉方框，保留 64×64 像素图标；编号、选中线、物品名、操作提示；选中图标移动 5 像素 |
| 双手 / 两格物品 | `uid`、`anchor`、`reserved`、`slot_cost` 和 `two_handed` | 两格共用一个物品，副格变淡 | 共用 uid 的两个选中标记保留；无图标的尸体显示“双手”；保留“放下”提示 |
| 帮助消息 | 控制器 / 玩家 → `show_help(text, duration)` | 原时长后淡出 | 改为左上细竖线通知，长文换行 |
| 笔记本 | 玩家 → `set_notebook(entries, open)` | N 开合，Esc 关闭；不暂停时钟 | 14 行、每行 4 条原始证据、56 个标记和现有纸张全部保留 |
| 笔记本地图 | 地图纹理、位置、朝向与探索雾 → `set_map_texture/marker()` | 随探索更新 | 保留迷雾和 14 个门牌位置绑定 |
| 旅行箱 | 控制器 → 玩家 → `set_suitcase()` | I 开关；1–4 存入；Shift+1–4 取出 | 保留四格和图标绑定 |
| 开发地图 | 玩家 → `set_debug_map()`；旧接口 `set_map_open/texture/marker/level_info()` | 调试构建 F3 | 保留 |
| 结算 | 控制器 → `show_end()` / `hide_end()` | 结束后 R 重新开始由原控制器处理 | 保留 |
| 惊吓动画 | 控制器 → `play_capture_scare()` | `capture_scare_finished` 是 HUD 唯一对外信号，控制器一次性连接并继续结算 | 保留动画、音效、信号时机 |

## 视觉实现

画面中心留给场景与当前操作，物品信息放在右下。暖白文字和黄铜选中线沿用酒店配色；保留原有像素图标、字体、手表、笔记本资产。底部局部渐变为文字和图标提供对比，不改场景光照。携带栏停止变化三秒后降至 84% 不透明度；选择变化恢复显示。每帧只更新已有四个样式对象，不再每帧为携带槽生成新 `StyleBoxFlat`。

地图、笔记本、旅行箱、结束界面或手表打开时，新快捷提示、渐变、携带栏、体力和准星遵循原遮挡规则。没有新增游戏输入、HUD 对外信号或推断式任务目标。当前操作保留原样，避免通过解析中文文案改变动作语义。

## 验证与边界

- Godot 4.6 stable (`89cea1439`)，Linux 软件图形驱动，OpenGL 兼容渲染器。
- 原 `tests/run_controller_test.gd`：24 个场景，149 条断言，0 失败；涵盖昼夜、物品、动作、界面与计时等现有流程。
- 原 `tests/watch_dial_test.gd`：10 条断言，0 失败。
- 新 `tests/exploration_hud_test.gd`：28 条断言，0 失败；无窗口及原生窗口渲染均运行。覆盖按键选物品、两格联动、N/T 切换、箱子 / 地图 / 结算遮挡、空槽、无图标双手物品、低体力、倒计时文案、惊吓完成信号。
- 网页在桌面及 390 像素手机宽度下检查；选择、双格联动、前后对照、动作计时、手表切换和体力滑块均通过自动操作检查，无脚本错误及横向溢出。内嵌中文字体，离线可用。
- 在 1920×1080 和 1280×720 下检查布局，原生截图中未发现越界或文字覆盖。
- 实际渲染截图：随交互预览附带的原生截图（网页底部可切换）。同一场景和相机下的旧版 / 新版对照，另有双格、低体力、手表、笔记本状态。
- 项目仍标记 Godot 4.7 / Forward Plus；没有为了测试更改 `project.godot`。此环境未验证 4.7 和 Forward+；兼容渲染器不显示项目中的体积雾，场景光影不代表目标渲染器的最终效果。
- 没有把这套样式推广到其他界面；此提交是供视觉评审的一屏原型。请先评审探索屏，再决定后续方向。

复现：

```sh
godot --headless --path . --script res://tests/run_controller_test.gd
godot --headless --path . --script res://tests/watch_dial_test.gd
godot --headless --path . --script res://tests/exploration_hud_test.gd
godot --path . --rendering-method gl_compatibility --script res://tests/exploration_hud_test.gd
```

有窗口运行最后一个测试时，PNG 写至 `/tmp/hotel_exploration_*.png`。`-- --capture-only` 只输出探索屏和无 HUD 场景，用于视觉对照。正式运行与预览场景请优先使用项目指定的引擎版本及渲染器。
