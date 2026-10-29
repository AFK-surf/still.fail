///|
/// Film 5's story (scripts/story/iduo-slack-en.json): a chat that came from Slack, its row marked so at the list's top,
/// its agent's card answered here with one tap; its fix and its asker's answer from Slack after it.
test "story slack: a chat from Slack, its card answered here, its asker answering after the fix" {
  reset()
  @sffixture.fix_story.val = Some(
    @json.parse(
      #|{"title": "Checkout fails for EU cards", "lang": "en", "words": {"整理发布清单": "Prepare the release checklist", "正在核对第三项：安装包的签名": "Checking item 3: the installer's signature", "首页的列表改成按天分组": "Group the home list by day", "奏 · 分组的标题用相对日期还是具体日期？": "Asks · Relative or exact dates for the group headers?", "奏": "Asks", " · 分组的标题用相对日期还是具体日期？": " · Relative or exact dates for the group headers?", "夜里的构建又失败了": "The nightly build failed again", "要你帮忙：测试机的磁盘满了，要不要清理旧的缓存？": "Needs you: the test machine's disk is full. Clear the old caches?", "测试机的磁盘满了，要不要清理旧的缓存？": "The test machine's disk is full. Clear the old caches?", "给设置页加一个深色模式开关": "Add a dark mode switch to settings", "做完了：开关和三处颜色都改好了": "Done: the switch and three colors are in", "开关和三处颜色都改好了": "The switch and three colors are in", "盯着 CI，绿了告诉我": "Watch CI and tell me when it's green", "监控中：每 5 分钟看一次主干的构建": "Watching: checks the main build every 5 minutes", "监控中：主干构建": "Watching: main build", "它会在归档里继续盯着。": "It keeps watching from the archive.", "和 Ana 一起看新版的引导页": "Review the new onboarding with Ana", "Ana：第二屏的插画可以再小一点": "Ana: the second screen's illustration could be smaller", "Slack 里问的报销流程": "The expenses question from Slack", "Slack · 星火 · #行政": "Slack · Spark · #ops", "已经把三个步骤整理成一页文档": "Wrote the three steps up as a one-page doc", "把旧的截图都换成新的": "Replace the old screenshots", "做完了": "Done", "迁移数据库的演练": "Database migration rehearsal", "MBA 离线": "MBA offline", "演练到第二步时 MBA 断开了": "MBA dropped at step two", "周报的模板": "Weekly report template", "模板放在共享文件夹的第一层": "The template is at the top of the shared folder", "2 分钟前": "2 min ago", "8 分钟前": "8 min ago", "15 分钟前": "15 min ago", "40 分钟前": "40 min ago", "1 小时前": "1 hr ago", "昨天 21:14": "Yesterday 21:14", "昨天 18:02": "Yesterday 18:02", "昨天 10:30": "Yesterday 10:30", "星期三": "Wednesday", "昨天": "Yesterday", "刚刚": "Just now", "待你决定": "Waiting on you", "未开始": "Not started", "星火工作室": "Spark Studio", "个人": "Personal", "林": "Lin", "周": "Zhou", "安娜": "Anna", "周宁": "Zhou Ning", "今天": "Today", "你 选择了「Merge」": "You chose “Merge”", "你 选择了「Not yet」": "You chose “Not yet”", "在线": "Running", " · 3 小时": " · just now"}, "place": "#support", "row": {"title": "Checkout fails for EU cards", "connect": "slack-1", "originText": "Slack · Acme · #support", "last": "still.fail: Found it. @Lin, ship it?", "unread": true, "agents": [{"runtime": "claude", "agentText": "anthropic · claude", "maker": {"id": "anthropic", "name": "anthropic"}}]}, "before": [{"kind": "person", "by": "Ana", "text": "@still.fail EU cards get a 500 at checkout, can you look?", "when": "2 min ago"}, {"kind": "agent", "text": "Found it: the 3-D Secure redirect drops the locale. The fix touches payments. @Lin, ship it?", "when": "Just now", "options": [{"label": "Not yet", "detail": "Leave it for review"}, {"label": "Fix and deploy", "detail": "Patch, test, deploy", "recommended": true}]}], "sent": [], "answered": [[{"at": 200, "working": true, "activity": "Fixing the 3-D Secure redirect"}, {"at": 2200, "post": {"text": "Fixed and live. @Ana Costa can you try again?"}}, {"at": 2400, "working": false}, {"at": 4000, "post": {"by": "Ana", "text": "Works now, thanks! 🙌"}}]]}
    ),
  )
  @sf.set_language(Some("en"))
  let src = fixture("chat-story")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "Checkout fails for EU cards", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=466.0, h=678.0, platform=2)
  t.run_for(@ui.nav_push_ms)
  let deploy = t.locate("=Fix and deploy")
  println("slack: deploy \{deploy} found \{t.rect_of("ship it")}")
  if deploy.length() > 0 {
    t.tap(deploy[0].0, deploy[0].1)
  }
  t.run_for(14000.0)
  let fixed = t.rect_of("Fixed and live")
  let ana = t.rect_of("Works now")
  println("slack: fixed \{fixed} ana \{ana}")
  @sffixture.fix_story.val = None
  @sf.set_language(None)
  assert_true(deploy.length() > 0)
  assert_true(fixed is Some(_) || ana is Some(_))
}
