// 账号 (account.mbt) alone, at each width, with a finger and with a mouse: who is signed in, where, another added;
// its picture changed; signing out and deleting asked first.

///|
test "账号, at each width and with either hand: who it is, where it is signed in, another to add; deleting asked first" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(Me, w, platform~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("lin@example.com") is Some(_), msg=at)
    assert_true(t.find("Google 账号") is Some(_), msg=at)
    assert_true(t.find("Chrome · macOS") is Some(_), msg=at)
    assert_true(t.find("登录另一个账号") is Some(_), msg=at)
    assert_false(@sf.presenting(), msg=at)
    scrolled_to(t, w, "注销")
    let (x, y) = t.find_last("注销").unwrap()
    t.tap(x, y)
    t.frame()
    assert_true(@sf.presenting(), msg=at)
    assert_true(t.find("注销后无法恢复") is Some(_), msg=at)
  }
}

///|
/// 账号 over the made-up core, its account's `workspaces` entry saying it shows a picture of its own where `own`, the
/// calls made of the core kept in `calls` (`account.*` answered at once).
fn own_picture_tester(w : Double, platform : Int, own : Bool, calls : Array[(String, Json)]) -> @ui.Tester {
  setting_tester(Me, w, platform~, over=fn(s) {
    {
      ..s,
      topic: fn(name, params) {
        let got = (s.topic)(name, params)
        match got.value {
          Some(Array(entries)) if name == "workspaces" && own =>
            {
              ..got,
              value: Some(
                Json::array(
                  entries.map(fn(e) {
                    match e {
                      Object(m) => {
                        let o = m.copy()
                        o["ownPicture"] = Json::boolean(true)
                        Json::object(o)
                      }
                      _ => e
                    }
                  }),
                ),
              ),
            }
          _ => got
        }
      },
      call: fn(name, params, done) {
        calls.push((name, params))
        if name.has_prefix("account.") {
          done(Ok(obj([])))
        } else {
          (s.call)(name, params, done)
        }
      },
    }
  })
}

///|
test "账号's picture, at each width and with either hand: one picked from the system's photos made its face and put up; its sign-in's again only once it has one of its own" {
  for case in page_cases {
    let (w, platform) = case
    let at = "\{w} platform \{platform}"
    let calls : Array[(String, Json)] = []
    let t = own_picture_tester(w, platform, false, calls)
    assert_true(t.find("更换头像") is Some(_), msg=at)
    assert_true(t.find("恢复默认头像") is None, msg=at)
    // pressed: the system's photo picker asked; called off, nothing put up
    t.picks([])
    let (x, y) = t.find("更换头像").unwrap()
    t.tap(x, y)
    t.frame()
    assert_eq(t.pick_asks().length(), 1, msg=at)
    assert_true(t.pick_asks()[0] == Photos, msg=at)
    assert_true(calls.iter().all(fn(c) { !c.0.has_prefix("account.") }), msg=at)
    // pressed again, a picture picked: read, made its face and put up as its own
    t.picks([("face.jpg", b"\xFF\xD8\xFF\xE0")])
    t.tap(x, y)
    t.frame()
    assert_eq(t.pick_asks().length(), 2, msg=at)
    let put = calls.filter(fn(c) { c.0 == "account.setPicture" })
    assert_eq(put.length(), 1, msg=at)
    assert_eq(@sfbase.text(Some(put[0].1), "account"), "u1", msg=at)
    assert_true(@sfbase.text(Some(put[0].1), "picture").has_prefix("data:image/jpeg;base64,"), msg=at)
    assert_eq(@sfbase.toast_words(), "已更换头像", msg=at)
  }
}

///|
test "账号's picture of its own taken away, at each width and with either hand: its sign-in's again" {
  for case in page_cases {
    let (w, platform) = case
    let at = "\{w} platform \{platform}"
    let calls : Array[(String, Json)] = []
    let t = own_picture_tester(w, platform, true, calls)
    assert_true(t.find("更换头像") is Some(_), msg=at)
    let (x, y) = t.find("恢复默认头像").unwrap()
    t.tap(x, y)
    t.frame()
    let removed = calls.filter(fn(c) { c.0 == "account.removePicture" })
    assert_eq(removed.length(), 1, msg=at)
    assert_eq(@sfbase.text(Some(removed[0].1), "account"), "u1", msg=at)
    assert_eq(@sfbase.toast_words(), "已恢复默认头像", msg=at)
    assert_eq(t.pick_asks().length(), 0, msg=at)
  }
}
