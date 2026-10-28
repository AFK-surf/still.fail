///|
/// Film 3's story (scripts/story/iduo-vault-en.json): the agent asks to use a key kept in the vault; allowed from its
/// card, it goes on with it, and its work is merged.
test "story vault: a key in the vault allowed from the agent's card, the agent going on with it" {
  reset()
  @sffixture.fix_story.val = Some(
    @json.parse(
      #|{"title": "Acme Shop", "lang": "en", "words": {"整理发布清单": "Prepare the release checklist", "正在核对第三项：安装包的签名": "Checking item 3: the installer's signature", "首页的列表改成按天分组": "Group the home list by day", "奏 · 分组的标题用相对日期还是具体日期？": "Asks · Relative or exact dates for the group headers?", "奏": "Asks", " · 分组的标题用相对日期还是具体日期？": " · Relative or exact dates for the group headers?", "夜里的构建又失败了": "The nightly build failed again", "要你帮忙：测试机的磁盘满了，要不要清理旧的缓存？": "Needs you: the test machine's disk is full. Clear the old caches?", "测试机的磁盘满了，要不要清理旧的缓存？": "The test machine's disk is full. Clear the old caches?", "给设置页加一个深色模式开关": "Add a dark mode switch to settings", "做完了：开关和三处颜色都改好了": "Done: the switch and three colors are in", "开关和三处颜色都改好了": "The switch and three colors are in", "盯着 CI，绿了告诉我": "Watch CI and tell me when it's green", "监控中：每 5 分钟看一次主干的构建": "Watching: checks the main build every 5 minutes", "监控中：主干构建": "Watching: main build", "它会在归档里继续盯着。": "It keeps watching from the archive.", "和 Ana 一起看新版的引导页": "Review the new onboarding with Ana", "Ana：第二屏的插画可以再小一点": "Ana: the second screen's illustration could be smaller", "Slack 里问的报销流程": "The expenses question from Slack", "Slack · 星火 · #行政": "Slack · Spark · #ops", "已经把三个步骤整理成一页文档": "Wrote the three steps up as a one-page doc", "把旧的截图都换成新的": "Replace the old screenshots", "做完了": "Done", "迁移数据库的演练": "Database migration rehearsal", "MBA 离线": "MBA offline", "演练到第二步时 MBA 断开了": "MBA dropped at step two", "周报的模板": "Weekly report template", "模板放在共享文件夹的第一层": "The template is at the top of the shared folder", "2 分钟前": "2 min ago", "8 分钟前": "8 min ago", "15 分钟前": "15 min ago", "40 分钟前": "40 min ago", "1 小时前": "1 hr ago", "昨天 21:14": "Yesterday 21:14", "昨天 18:02": "Yesterday 18:02", "昨天 10:30": "Yesterday 10:30", "星期三": "Wednesday", "昨天": "Yesterday", "刚刚": "Just now", "待你决定": "Waiting on you", "未开始": "Not started", "星火工作室": "Spark Studio", "个人": "Personal", "林": "Lin", "周": "Zhou", "安娜": "Anna", "周宁": "Zhou Ning", "今天": "Today", "你 选择了「Merge」": "You chose “Merge”", "你 选择了「Not yet」": "You chose “Not yet”", "在线": "Running", " · 3 小时": " · just now"}, "before": [{"kind": "person", "text": "Add Stripe checkout to the shop", "when": "Yesterday"}, {"kind": "agent", "text": "Checkout is in on the `stripe-checkout` branch: cart, card form and the order page. The payment tests are next.", "when": "Yesterday"}], "sent": [[{"at": 300, "working": true, "activity": "Reading tests/payments"}, {"at": 1500, "activity": "Looking for a Stripe key"}, {"at": 2800, "post": {"text": "Asking to use “Stripe test key” from your vault to run the payment tests", "vault": {"request": "r-stripe", "name": "Stripe test key", "mode": "proxy", "hosts": ["api.stripe.com"], "command": "pnpm test payments", "reason": "Run the payment tests against Stripe's test mode", "answer": "approve", "lasts": "chat"}}}, {"at": 3100, "working": false}]], "answered": [[{"at": 300, "working": true, "activity": "Running the payment tests through the vault's proxy"}, {"at": 1700, "activity": "14 of 14 passed"}, {"at": 3000, "post": {"text": "All 14 payment tests pass against Stripe's test mode: card, 3-D Secure, refund and webhook. The key came through your vault's proxy to api.stripe.com only; I never saw it, and it's not in the repo, the logs or this chat.", "options": [{"label": "Not yet", "detail": "Keep it on its branch"}, {"label": "Merge", "detail": "Squash into main", "recommended": true}]}}, {"at": 3300, "working": false}], [{"at": 300, "working": true, "activity": "Merging into main"}, {"at": 1900, "post": {"text": "Merged into main (`9c3e1f7`). Checkout goes out with the next deploy.", "ending": "all_done"}}, {"at": 2300, "working": false}]]}
    ),
  )
  @sf.set_language(Some("en"))
  let src = fixture("chat-story")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "Acme Shop", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=951.0, h=669.0, platform=2)
  t.run_for(@ui.nav_push_ms)
  println("vault: open, message \{t.locate("Message")} 发消息 \{t.locate("发消息")}")
  let m = either(t, "Message", "发消息")
  t.tap(m[0].0, m[0].1)
  t.type_text("Run the payment tests")
  let send = t.locate("icon:arrow-up")
  println("vault: send \{send}")
  t.tap(send[0].0, send[0].1)
  t.run_for(8000.0)
  let allow = either(t, "=Allow", "=允许")
  println("vault: allow \{allow} title \{t.rect_of("Stripe test key")} scope \{t.rect_of("In this chat")}")
  if allow.length() > 0 {
    t.tap(allow[0].0, allow[0].1)
  }
  t.run_for(8000.0)
  let merge = t.locate("=Merge")
  println("vault: merge \{merge} saved key shown \{t.rect_of("4eC39")}")
  if merge.length() > 0 {
    t.tap(merge[0].0, merge[0].1)
  }
  t.run_for(6000.0)
  let merged = t.rect_of("9c3e1f7")
  println("vault: merged \{merged}")
  @sffixture.fix_story.val = None
  @sf.set_language(None)
  assert_true(allow.length() > 0)
  assert_true(merge.length() > 0)
  assert_true(merged is Some(_))
}

///|
/// Where the words are on screen, in English or else in Chinese (the app's words as its language is read).
fn either(t : @ui.Tester, en : String, zh : String) -> Array[(Double, Double)] {
  let at = t.locate(en)
  if at.length() > 0 {
    at
  } else {
    t.locate(zh)
  }
}
