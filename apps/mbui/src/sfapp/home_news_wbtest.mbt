// What the last update brought at Home's top (home_news.mbt; PageParts.kt ChangelogNews), over the fixture's Home with
// the changelog's `news` said.

///|
/// Home over the fixture, the core's changelog with news (four changes), its calls kept.
fn news_home(calls : Array[String]) -> @ui.Tester {
  reset()
  let base = fixture("home")
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      if name == "changelog" {
        {
          value: Some({
            "build": 1310,
            "tabs": [],
            "news": {
              "build": "0.1.1310",
              "entries": [
                { "text": ["设置里可以注销账号", "聊天顶栏会提示 station 更新"] },
                { "text": ["执行历史里可以认领 Slack 用户", "后台任务的面板可以拖高"] },
              ],
            },
          }),
          error: None,
          version: 1,
        }
      } else {
        (base.topic)(name, params)
      }
    },
    call: fn(name, params, done) {
      calls.push(name)
      (base.call)(name, params, done)
    },
  }
  @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
}

///|
test "Home after an update: the build it is now, its first three changes, how many more" {
  let calls : Array[String] = []
  let t = news_home(calls)
  assert_true(t.find("已更新到 0.1.1310") is Some(_))
  assert_true(t.find("设置里可以注销账号") is Some(_))
  assert_true(t.find("后台任务的面板可以拖高") is None, msg="the fourth is not said")
  assert_true(t.find("还有 1 项") is Some(_))
  // above the first day's rows
  let (_, news) = t.find("已更新到 0.1.1310").unwrap()
  let (_, day) = t.find("今天").unwrap()
  assert_true(news < day)
}

///|
test "Home's news: tapped, the changelog; its × lets it go at once and tells the core" {
  let calls : Array[String] = []
  let t = news_home(calls)
  t.tap_text("设置里可以注销账号")
  assert_true(app.nav.top() == Setting(@settings.Route::Changelog))
  let calls : Array[String] = []
  let t = news_home(calls)
  let (x, y, w, _) = t.rect_of("已更新到 0.1.1310").unwrap()
  ignore(x)
  ignore(w)
  // the × at the card's right, on the head's line
  t.tap(390.0 - 12.0 - 6.0 - 16.0, y + 4.0)
  assert_true(calls.contains("changelog.seen"))
  assert_true(t.find("已更新到 0.1.1310") is None)
}
