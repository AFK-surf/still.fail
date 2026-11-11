# 自己回放不过的录像（不合并）

这个分支只放录像和这张表，不开 PR、不合并、不带工作流。迁移协调 2026-11-11 定：

- 一份录像的回放每次都一样。`scripts/rerecord.sh` 录出来的一遍，如果它自己的回放不过，那一遍就是那个时序下一个逐位可复现的故障；换一遍时序可能碰不到，所以仓库里碰巧过的那一遍不说明没有毛病。
- 每一处修的时候，对应的录像连同修复一起进 main，成为那个 PR 的回放测试（修之前不过、修之后过）；在那之前待在这里。
- 归某个改动的不过（用同一份录像关掉那个改动的开关回放就过）不进这张表，在那个改动合之前修掉。

| 录像 | 流程 | 哪份代码录的 | 回放的原话 | 归谁 |
|---|---|---|---|---|
| `traces/main-new-chat.trace` | new_chat | main（补齐线录的，#5135 之前的 main；具体提交待补） | 待补（补齐线当时读到的：返回箭头的 y 在某一帧差 0.01–0.03，行稳定一类的判定） | 待定（补齐线在 main 上见过；确认是同一处后归它） |

## 2026-11-11 量清楚的两处（main 的；假站点上带不带「按下就出处理中」数字逐位相同）

录像是带 `working-at-press`（`f4152a31e6`）的 app 录的：那个 app 在按下时订阅 agent 的 `live`，所以这三份只能在那个分支上回放（main 的 app 不订，回放卡住）。在 main 上复现用 `fixture-walks/` 里的假站点走法（放进 `apps/mbui/src/sfapp/`，`cardpace.patch` 让假站点的卡片回答按 `fix_pace` 和核心延迟走；`zz_probe.mbt` + `probe.patch` 每帧打印每一行的 key、顶边、高和起因）。

| 录像 / 走法 | 流程 | 原话 | 原因（量的） | 归谁 |
|---|---|---|---|---|
| `traces/wap-send-card-paced-1.trace`、`-2`；`fixture-walks/zz_cardfx_wbtest.mbt` | 答卡片（`send_card_paced`，半速那一遍 `AsRun(0.5)`） | `rows not steady`：`top` went 36.206581875453935 one way, stood 1377.767903645834 ms, came back 13.697991096516489 at 6000（第 2 遍 36.4、1411 ms、14.2 at 6033）。假站点上：row `m:ts8` went 26.781697193864204 one way, stood 1183.3333333333335 ms, came back 5.4266480355095155 at 3483.33，起因 `m:card-reply1=comes@3450/300 act:s-c1=goes@3450/300` | 选项点下、核心收到的那一帧：卡片折起 211.1 → 93.1（−118.0）、状态行走（−40）、发出的那一行来（+120.75）、「处理中」来（+44）、Foot 168.75 → 124.75（−44），净 −37.25，上面的行下去并停住；1.38 秒后回答来（+71.1）、状态行来（+40）、「处理中」走（−44），净 +67.1，又顶回去。行来自 `sfbase/chat_list.mbt` 的 `row_keys`，那一行走在 `sfpages/chat_list.mbt:189`，两条路在 `ui/list_size.mbt:556` 出发。判定的门槛是 `rows_return_ms` = 1500（`ui/rows_steady.mbt:285`、`:305`） | 消息列表动效线。**不在旧列表上修**（主人 2026-11-11 定先迁 chat）；节点列表要守的那句话见下 |
| `traces/wap-send-flying-2.trace`；`fixture-walks/zz_flyc_wbtest.mbt`、`zz_flyd_wbtest.mbt` | 连发两条（`send_flying`），第一条的回答在第二条的字还在飞时到 | `gaps not steady`：`正在启动 \| 紧跟着的一条 082947`: 29.986597376768373 → 10.769635283820776 → 27.74 at 2150。假站点上：飞着的字一帧退回 10.95（752.67 → 763.62 at 2200）；「处理中」那一行 moved 4.182373181702019 at 2350, back -8.434106273473617 at 2366.67, turned back at 2283.33 | 2150 核心的回答一批到：那个回合失败了，「处理中」原地淡出；一条消息插到第二条的字要飞去的那一行上面，另一条来在「处理中」下面。飞着的字一帧退 13.2（730.83 → 743.99）。假站点上「处理中」在 33 毫秒里被说成走、回来、又走（2200 / 2216 / 2233） | 同上。`zz_flyc` 那个变体只在带改动时不过、基线过，原因两轮没钉住（基线在另一个变体里有同样的表现，可能是假站点的节奏） |

节点列表要守的三句话（由这两处来）：
1. 答一张卡片是一个回合，列表只朝这个回合结束时的位置走：卡片折起时腾出的地方，如果回答马上要占，就不能先收拢再顶开。
2. 一行来在「字正在飞去的那一行」上面时，飞着的字跟着自己的路往前走，不许一帧退回去。
3. 原地淡出的那一行保持它的位置，来在它下面的行不许挪它；同一行不许在几十毫秒里被说成走、回来、又走。

## 已经丢了的（旧脚本删掉了录像，只剩原话）

2026-11-11，五条发送流程各录两遍：

| 流程 | 哪份代码录的 | 回放的原话 | 归谁 |
|---|---|---|---|
| send_paced | `working-at-press`（带「按下就出处理中」） | `tester_looks.mbt:202`：留着的部分是「好的 064618」，同一处整搭出来的是 agent 那一行「默认模型」（头像在 16,696），从 1568 ms 起 | chatlist 线（留着的东西和重搭的不一样）；是否归这次改动未分清，录像没留下 |
| send_card_paced | `working-at-press` | `rows not steady`：`top` 行 went 36.034204322984635 one way, stood 1442.6683349609375 ms, came back 14.168266942155583 at 6032.791666666666；起因 `m:…=comes@5998.12/300 state=comes@5998.12/300 act:…=goes@5998.12/300` | 后来留下了同样的两遍并量清楚了，是 main 的（见上） |
| send_flying | `activity-fades` 的头（不带「按下就出处理中」） | 待补（日志在 Studio 的 `b-base/apps/mbui/out/rerecord.*/`） | 待定 |
| new_chat | `activity-fades` 的头 | 待补（同上） | 待定 |

#5446 之后 `rerecord.sh` 不再删：不过的那一遍留在 `out/rerecord.*/NAME.failed.trace`。

## main 上 60/120 帧逐帧判定下不过的（在 `motion_counted` 里被数着、CI 不红）

2026-11-11，main `f611394ac0`，Studio 上 wasm-gc 跑单个文件（`MBUI_TEST_FPS=60|120 MBUI_TEST_MOTION=judge`）。没有录像：这些是仓库里已有的测试和回放，按下面的帧率跑就复现。迁移协调：不要让它们只是计数里的一个数。

| 测试 | 帧率 | 原话 | 归谁 |
|---|---|---|---|
| `src/sfapp/composer_wbtest.mbt`（Tester 建在 `:368` 那条，#5450 之后是 `:427`） | 60 | `rows not steady`：row `m:ts8` went -0.23902829762847394 a frame between -0.3113047038570983 and 13.1137079477179 at 4750；seen −144.00、−144.31、−144.55、然后 4760 处 −136.68；causes `o:local:2=comes@4384.8/395.2 foot=changed@4384.8/395.2`，way 4384.8–4780 | 待定（看着是路的最后一帧一步到位） |
| 同上 | 120 | 同一行：-0.11159721517879413 a frame between -0.1274310824496798 and 6.55685397385895 at 4750 | 同上 |
| `mbui/src/motion/motion_test.mbt:555` | 60、120 | `sizes_steady`：−40 at 1083.33 | 待定（sizes_steady 的已知条数 1） |
| 回放 `send_paced` | 60 | `sizes_steady`：height step at 1104.09（早先一次记的是 "height went 0 a frame"） | 待定 |
| 回放 `offline_retry` | 60 | `rows not steady`：row `top` went -6.661377287408474 a frame between -2.5274687069706037 and -4.6578095707352825 at 2250；seen 456.65、454.12、447.46（2216.67、2233.33、2250） | 待定（看着是「起因的时刻」或「掉头」） |
| 回放 `offline_retry` | 120 | `rows not steady`：row `o:local:1` went 59.877135951566174 one way, stood 33.33333333333303 ms, came back 3.4296286847662714 at 3216.6666666666665 | 待定 |
| 回放 `chinese_enter` | 120 | `sizes_steady`：发消息 的输入框 at 2227.73 | 待定 |

早先（main `1609696a9c`）同样方式量到、这次没有重跑的：`activity_wbtest:152`@60（stop dead）、`emit_wbtest:59`@60（一行一帧 −246）、回放 `new_chat`@60（间距 37.9 → 43.6 → 40.7）、回放 `send_card_paced`@120（foot went 6.9, stood 33 ms, back 4.6）、`cards_wbtest`@60（row `m:ts6` went 29.486785119823537 one way, stood 1366 ms, came back 4.967318880290122 at 3116）。
