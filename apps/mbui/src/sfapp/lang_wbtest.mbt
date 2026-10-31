///|
/// The app over a fixture, the device's language `locale` (its host's MBUI_LOCALE), the core's prefs saying `lang` when
/// given.
fn lang_tester(mode : String, locale : String, lang? : String) -> @ui.Tester {
  new_run()
  let base = fixture(mode)
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      let got = (base.topic)(name, params)
      match (name, lang, got.value) {
        ("prefs", Some(l), Some(Object(m))) => {
          let o = m.copy()
          o["lang"] = Json::string(l)
          { ..got, value: Some(Json::object(o)) }
        }
        _ => got
      }
    },
  }
  @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, env=[("MBUI_LOCALE", locale)], platform=2)
}

///|
test "English: the sign-in page of a phone in English, as still.fail's Android app says it" {
  let t = lang_tester("signin", "en-US")
  assert_true(t.find("Keep your agents working") is Some(_))
  assert_true(t.find("Sign in or sign up") is Some(_))
  assert_true(t.find("让 agent 持续工作") is None)
}

///|
test "Chinese: a phone in Chinese, or one that says no language" {
  for locale in ["zh-Hans-CN", ""] {
    let t = lang_tester("signin", locale)
    assert_true(t.find("让 agent 持续工作") is Some(_))
    assert_true(t.find("登录或注册") is Some(_))
  }
}

///|
test "English: chosen in the core's prefs (its `lang`), over a phone in Chinese; Home and its words" {
  let t = lang_tester("home", "zh-CN", lang="en")
  assert_true(t.find("Search everything") is Some(_))
  assert_true(t.find("搜索全部内容") is None)
  // the core's own words (the rows', the days', the workspace's name) as it said them
  assert_true(t.find("整理发布清单") is Some(_))
  assert_true(t.find("今天") is Some(_))
  // and back to Chinese as the core says so
  let t = lang_tester("home", "en-US", lang="zh")
  assert_true(t.find("搜索全部内容") is Some(_))
}
