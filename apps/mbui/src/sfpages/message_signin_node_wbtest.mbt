// An agent's ask to sign in to a site in place of its post's words, as nodes (message_signin_node.mbt), set beside the
// old view's (signin_card.mbt's signin_ask_card, in a list's row so that how it went is pressed for the card read
// again, as there) on the same fixture (chat-signin's post, its card as the core says it): waiting on a device with no
// password manager, with 1Password, with the system's autofill; 1Password asked, its logins to pick from, none for the
// site, its servers not reached, the autofill asked, not to be kept; a code asked, typed; a captcha, the agent's word
// for the person; filling, left, signed in and being kept, its keeping failed; another's; signed in and kept, not
// kept, refused, expired, ended; wide, narrow, at 1.3 (its foot's buttons on lines over one another, as the old).

///|
/// chat-signin's post, its sign-in as `more` says over the fixture's (waiting), `theirs`: 陈's to answer.
fn signin_post_with(more? : Map[String, Json] = {}, theirs? : Bool = false) -> Message {
  let j = @sffixture.signin_post("chat-signin")
  match j {
    Object(o) =>
      match o.get("card") {
        Some(Object(card)) => {
          if theirs {
            card["assignee"] = "chen@example.com"
            card["assigneeText"] = "等 陈 完成"
          }
          match card.get("signinAsk") {
            Some(Object(ask)) =>
              for k, v in more {
                ask[k] = v
              }
            _ => ()
          }
        }
        _ => ()
      }
    _ => ()
  }
  card_said_then(j)
}

///|
/// What the host has of a password manager in a case: none; 1Password, the site's logins it lists (`listed`, its
/// `op item list`'s answer; its runs under way and never ending where `slow`; its servers not reached where
/// `unreached`); the system's autofill.
priv enum SignInHost {
  NoManager
  OnePassword(String, Bool, Bool)
  Autofill
}

///|
/// Two logins of github.com, as `op item list` says them (one with its account).
// kept across runs: a value
let signin_two_logins : String = "[{\"id\":\"l1\",\"title\":\"GitHub\",\"additional_information\":\"lin\",\"urls\":[{\"href\":\"https://github.com\"}]},{\"id\":\"l2\",\"title\":\"GitHub 工作\",\"additional_information\":\"lin-work\",\"urls\":[{\"href\":\"https://github.com/login\"}]}]"

///|
/// One login of github.com, as `op item list` says it.
// kept across runs: a value
let signin_one_login : String = "[{\"id\":\"l1\",\"title\":\"GitHub\",\"additional_information\":\"lin\",\"urls\":[{\"href\":\"https://github.com\"}]}]"

///|
/// The host as `h` says, set as a run begins (card_old's `begun`); what was asked of the cards before let go of.
fn signin_host(h : SignInHost) -> () -> Unit {
  fn() {
    signin_reset()
    @sf.presenters_reset()
    match h {
      NoManager => ()
      Autofill => @ui.fake_autofill.val = true
      OnePassword(listed, slow, unreached) => {
        @ui.fake_op_pending.val = slow
        @ui.fake_op.val = Some(fn(args) {
          if unreached {
            (1, "", "[ERROR] 2026/11/03 16:43:31 Get \"https://my.1password.com/api/v2/account/keysets\": unexpected EOF\n")
          } else if args.contains("list") {
            (0, listed, "")
          } else if args.contains("--otp") {
            (1, "", "[ERROR] no one-time password")
          } else {
            (0, "[{\"id\":\"username\",\"label\":\"username\",\"value\":\"lin\"},{\"id\":\"password\",\"purpose\":\"PASSWORD\",\"label\":\"password\",\"value\":\"s3cret\"}]", "")
          }
        })
      }
    }
  }
}

///|
/// A case: its name, the post, the host, what is pressed in turn on its card (each the words drawn), whether the core
/// answers keeping it in the vault with an error (signin_src).
priv struct SignInCase {
  name : String
  post : Message
  host : SignInHost
  presses : Array[String]
  fails : Bool
}

///|
/// chat-signin's source, its calls kept in `calls`; `vault.approve` answered at once with an error where `fails` (the
/// vault locked), every other call never.
fn signin_src(fails? : Bool = false, calls? : Array[(String, Json)] = []) -> Source {
  let base = card_src("chat-signin", calls~)
  {
    ..base,
    call: fn(name, params, done) {
      (base.call)(name, params, done)
      if fails && name == "vault.approve" {
        done(Err(Json::string("密钥库已锁定")))
      }
    },
  }
}

///|
/// The sign-in's states by name.
fn signin_cases() -> Array[SignInCase] {
  let op = OnePassword(signin_two_logins, false, false)
  let s = fn(v : String) { Json::string(v) }
  [
    { name: "on screen", post: signin_post_with(), host: NoManager, presses: [], fails: false },
    { name: "1Password", post: signin_post_with(), host: op, presses: [], fails: false },
    { name: "autofill", post: signin_post_with(), host: Autofill, presses: [], fails: false },
    { name: "1Password asked", post: signin_post_with(), host: OnePassword(signin_two_logins, true, false), presses: ["用 1Password 登录"], fails: false },
    { name: "logins to pick", post: signin_post_with(), host: op, presses: ["用 1Password 登录"], fails: false },
    { name: "sending", post: signin_post_with(), host: OnePassword(signin_one_login, false, false), presses: ["用 1Password 登录"], fails: false },
    { name: "none for the site", post: signin_post_with(), host: OnePassword("[]", false, false), presses: ["用 1Password 登录"], fails: false },
    { name: "not reached", post: signin_post_with(), host: OnePassword("[]", false, true), presses: ["用 1Password 登录"], fails: false },
    { name: "autofill asked", post: signin_post_with(), host: Autofill, presses: ["用密码管理器登录"], fails: false },
    { name: "not to keep", post: signin_post_with(), host: NoManager, presses: ["登录后存入密钥库", "不存入密钥库"], fails: false },
    { name: "code", post: signin_post_with(more={ "status": s("code") }), host: NoManager, presses: [], fails: false },
    { name: "person", post: signin_post_with(more={ "status": s("person"), "why": s("blocked") }), host: NoManager, presses: [], fails: false },
    { name: "agent's word", post: signin_post_with(more={ "status": s("person"), "why": s("agent"), "said": s("要先在手机上确认登录") }), host: NoManager, presses: [], fails: false },
    { name: "filling", post: signin_post_with(more={ "status": s("filling") }), host: NoManager, presses: [], fails: false },
    { name: "left", post: signin_post_with(more={ "status": s("left") }), host: NoManager, presses: [], fails: false },
    { name: "saving", post: signin_post_with(more={ "status": s("done"), "keep": Json::boolean(true), "save": s("r-save") }), host: NoManager, presses: [], fails: false },
    {
      name: "save failed",
      post: signin_post_with(more={ "status": s("done"), "keep": Json::boolean(true), "save": s("r-save") }),
      host: NoManager,
      presses: [],
      fails: true,
    },
    { name: "theirs", post: signin_post_with(theirs=true), host: NoManager, presses: [], fails: false },
    { name: "kept", post: signin_post_with(more={ "status": s("done"), "keep": Json::boolean(true), "save": s("r-save"), "kept": s("granted") }), host: NoManager, presses: [], fails: false },
    { name: "not kept", post: signin_post_with(more={ "status": s("done"), "keep": Json::boolean(false) }), host: NoManager, presses: [], fails: false },
    { name: "done", post: signin_post_with(more={ "status": s("done"), "keep": Json::boolean(true) }), host: NoManager, presses: [], fails: false },
    { name: "denied", post: signin_post_with(more={ "status": s("denied") }), host: NoManager, presses: [], fails: false },
    { name: "expired", post: signin_post_with(more={ "status": s("expired") }), host: NoManager, presses: [], fails: false },
    { name: "ended", post: signin_post_with(more={ "status": s("ended") }), host: NoManager, presses: [], fails: false },
  ]
}

///|
/// The old view's sign-in card for post `m` (signin_ask_card).
fn signin_old_card(c : @ui.Ctx, here : MessageHere, m : Message) -> Unit {
  match m.card {
    Some({ signin: Some(ask), .. } as card) => signin_ask_card(c, here, m, card, ask)
    _ => ()
  }
}

///|
/// What `t` draws (head_drawn's words and grounds), each place and size to a billionth: the old view's sums and the
/// nodes' come to the same places by other ways, a last digit apart (a foot's lines at 1.3, 216.8 and
/// 216.79999999999998).
fn signin_drawn(t : @ui.Tester) -> String {
  let r = fn(x : Double) { (x * 1.0e9).round() / 1.0e9 }
  t.words().map(fn(w) { "\{w.0}@\{r(w.1)},\{r(w.2)} \{r(w.3)}x\{r(w.4)} a\{w.5}" }).join("\n") +
  "\n" +
  t.drawn_rects().map(fn(g) { "\{r(g.0)},\{r(g.1)} \{r(g.2)}x\{r(g.3)} \{g.4}" }).join("\n")
}

///|
/// The old view's drawing of case `c`, `w` wide at `scale`, its presses made; then the same drawn by the nodes: both,
/// and the new one's Tester.
fn signin_both(
  c : SignInCase,
  w : Double,
  scale? : Double = 1.0,
) -> (String, String, @ui.Tester) {
  let at = "signin \{c.name} \{w} \{scale}"
  let old = card_old(w, signin_src(fails=c.fails), c.post, at, fn(x, here) { signin_old_card(x, here, c.post) }, begun=signin_host(c.host))
  old.set_font_scale(scale)
  old.run_for(@ui.move_most_ms)
  for p in c.presses {
    old.tap_text(p)
    old.run_for(@ui.move_most_ms)
  }
  let was = signin_drawn(old)
  let t = card_new(w, signin_src(fails=c.fails), fn() { c.post }, begun=signin_host(c.host))
  t.set_font_scale(scale)
  t.run_for(@ui.move_most_ms)
  for p in c.presses {
    t.tap_text(p)
    t.run_for(@ui.move_most_ms)
  }
  (was, signin_drawn(t), t)
}

///|
/// How many of card_audit's rooms case `name` has: none while its card shows; decided, the head's name and time, and
/// the line saying how it went where its middle is under the time (「已登录 github.com」 118 wide, 「已拒绝登录
/// github.com」 142, from 40; the others' are longer).
fn signin_rooms(_name : String) -> Int {
  0
}

///|
/// Case `c` drawn `w` wide at `scale` by both views, the same: the new one's Tester.
fn signin_held(c : SignInCase, w : Double, scale? : Double = 1.0) -> @ui.Tester raise {
  let (was, now, t) = signin_both(c, w, scale~)
  assert_eq(now, was, msg="\{c.name} at \{w} \{scale}")
  t
}

///|
test "a sign-in in place of its post's words, made once as nodes, is drawn as the old view drew it: waiting with no password manager, 1Password, the autofill; 1Password asked, its logins to pick, sending, none for the site, its servers not reached, the autofill asked, not to be kept; a code asked, a captcha, the agent's word, filling, left, being kept, its keeping failed, another's; kept, not kept, signed in, refused, expired, ended; wide and narrow, at 1.3" {
  for w in [760.0, 390.0] {
    let drawn : Map[String, String] = Map([])
    for c in signin_cases() {
      let t = signin_held(c, w)
      drawn[c.name] = head_drawn(t)
      card_audit(t, "\{c.name} at \{w}", signin_rooms(c.name))
    }
    // (each state drawn as it is, not as the one it is told from: waiting on its host)
    for c in signin_cases() {
      let from = match c.host {
        OnePassword(_, _, _) => "1Password"
        Autofill => "autofill"
        NoManager => "on screen"
      }
      if c.name != from {
        assert_true(drawn.get(c.name) != drawn.get(from), msg="\{c.name} at \{w}: drawn as \{from}")
      }
    }
  }
  // (at 1.3, narrow: what fits holds its words, nothing over another)
  let cases = signin_cases()
  for i in [1, 4, 8, 9] {
    let t = signin_held(cases[i], 390.0, scale=1.3)
    assert_eq(t.fixed_outgrown(), [], msg=cases[i].name)
    card_audit(t, "\{cases[i].name} at 1.3", 0)
  }
}

///|
/// What was asked of the core, each call's name and its params as text (a test compares them).
fn signin_asked(calls : Array[(String, Json)]) -> Array[String] {
  calls.map(fn(c) { c.0 + " " + c.1.stringify() })
}

///|
/// Post `m` on a host `h`, `w` wide, `act` done on the old view's drawing, then on the nodes': what each asked of the
/// core, and the new one's Tester.
fn signin_act_both(
  m : Message,
  h : SignInHost,
  w : Double,
  act : (@ui.Tester) -> Unit,
) -> (Array[String], Array[String], @ui.Tester) {
  let was : Array[(String, Json)] = []
  let old = card_old(w, card_src("chat-signin", calls=was), m, "signin act", fn(x, here) { signin_old_card(x, here, m) }, begun=signin_host(h))
  old.run_for(@ui.move_most_ms)
  act(old)
  let now : Array[(String, Json)] = []
  let t = card_new(w, card_src("chat-signin", calls=now), fn() { m }, begun=signin_host(h))
  t.run_for(@ui.move_most_ms)
  act(t)
  (signin_asked(was), signin_asked(now), t)
}

///|
/// `words` pressed on `t`'s card, then its moment.
fn signin_press(t : @ui.Tester, words : String) -> Unit {
  t.tap_text(words)
  t.run_for(@ui.move_most_ms)
}

///|
test "a sign-in on its card, made once as nodes, asks what the old view's asked: on screen, signin.self; 1Password's login picked, its account and password sent with signin.fill, kept or not as chosen; the autofill's login as it comes; a code typed, by 继续 and by Enter; the person's step said done; signed in, kept by vault.approve once" {
  let none = signin_post_with()
  let op = OnePassword(signin_two_logins, false, false)
  let s = fn(v : String) { Json::string(v) }
  let cases : Array[(String, Message, SignInHost, (@ui.Tester) -> Unit, String)] = [
    ("on screen", none, NoManager, fn(t) { signin_press(t, "在画面中登录") }, "signin.self"),
    ("1Password, the second login", none, op, fn(t) {
      signin_press(t, "用 1Password 登录")
      signin_press(t, "GitHub 工作 · lin-work")
    }, "signin.fill"),
    ("not to keep, 1Password's only login", none, OnePassword(signin_one_login, false, false), fn(t) {
      signin_press(t, "登录后存入密钥库")
      signin_press(t, "不存入密钥库")
      signin_press(t, "用 1Password 登录")
    }, "signin.fill"),
    ("1Password slow, on screen instead", none, OnePassword(signin_two_logins, true, false), fn(t) {
      signin_press(t, "用 1Password 登录")
      signin_press(t, "在画面中登录")
    }, "signin.self"),
    ("autofill", none, Autofill, fn(t) {
      signin_press(t, "用密码管理器登录")
      @ui.fake_autofill_picks("github.com", "lin", "pw")
      t.run_for(@ui.move_most_ms)
    }, "signin.fill"),
    ("the autofill's login of another site", none, Autofill, fn(t) {
      signin_press(t, "用密码管理器登录")
      @ui.fake_autofill_picks("gitlab.com", "lin", "pw")
      t.run_for(@ui.move_most_ms)
    }, ""),
    ("a code by 继续", signin_post_with(more={ "status": s("code") }), NoManager, fn(t) {
      let (x, y) = t.find_last("验证码").unwrap()
      t.tap(x, y)
      t.type_text("123456")
      t.run_for(@ui.move_most_ms)
      signin_press(t, "继续")
    }, "signin.fill"),
    ("a code by Enter", signin_post_with(more={ "status": s("code") }), NoManager, fn(t) {
      let (x, y) = t.find_last("验证码").unwrap()
      t.tap(x, y)
      t.type_text("654321")
      t.enter()
      t.run_for(@ui.move_most_ms)
    }, "signin.fill"),
    ("the person's step", signin_post_with(more={ "status": s("person"), "why": s("blocked") }), NoManager, fn(t) {
      signin_press(t, "我已登录")
    }, "signin.self"),
    ("saving", signin_post_with(more={ "status": s("done"), "keep": Json::boolean(true), "save": s("r-save") }), NoManager, fn(t) {
      t.run_for(@ui.move_most_ms)
    }, "vault.approve"),
  ]
  for c in cases {
    let (was, now, t) = signin_act_both(c.1, c.2, 760.0, c.3)
    assert_eq(now, was, msg=c.0)
    let named = now.filter(fn(a) { a.has_prefix("signin.") || a.has_prefix("vault.") })
    if c.4 == "" {
      assert_eq(named, [], msg=c.0)
    } else {
      assert_eq(named.length(), 1, msg=c.0 + ": " + now.join(" | "))
      assert_true(named[0].has_prefix(c.4 + " "), msg=c.0 + ": " + named[0])
    }
    card_audit(t, c.0, 0)
  }
}

///|
test "a sign-in asked of 1Password, made once as nodes: what it is at said as the host's word comes, never asked of it each frame; let go of for the screen, what it would have said taken no more" {
  let t = card_new(760.0, card_src("chat-signin"), fn() { signin_post_with() }, begun=signin_host(OnePassword(signin_two_logins, true, false)))
  t.run_for(@ui.move_most_ms)
  signin_press(t, "用 1Password 登录")
  assert_true(card_has(t, "正在问 1Password…"))
  assert_true(t.get(Button, label="用 1Password 登录").disabled)
  // (while it runs: nothing built again for it, the app at rest)
  assert_true(t.at_rest(), msg=t.rest_why())
  // its list comes: the logins to pick from, at that moment
  @ui.fake_op_pending.val = false
  t.run_for(@ui.move_most_ms)
  assert_true(card_has(t, "选一个 github.com 的登录"))
  assert_true(card_has(t, "GitHub · lin"))
  assert_true(card_has(t, "GitHub 工作 · lin-work"))
  card_audit(t, "picking", 0)
  // asked again, slow, and let go of for the screen: its note gone, nothing it says after taken
  let t = card_new(760.0, card_src("chat-signin"), fn() { signin_post_with() }, begun=signin_host(OnePassword(signin_two_logins, true, false)))
  t.run_for(@ui.move_most_ms)
  signin_press(t, "用 1Password 登录")
  signin_press(t, "在画面中登录")
  assert_false(card_has(t, "正在问 1Password…"))
  @ui.fake_op_pending.val = false
  t.run_for(@ui.move_most_ms)
  assert_false(card_has(t, "选一个 github.com 的登录"))
  assert_false(t.get(Button, label="用 1Password 登录").disabled)
  card_audit(t, "let go", 0)
}

///|
test "a sign-in decided as its card shows, made once as nodes: the card goes, the line saying how it went in its place; pressed, what was asked read again" {
  @sf.presenters_reset()
  let m = @signals.signal(signin_post_with())
  let t = card_new(390.0, card_src("chat-signin"), fn() { m.get() }, begun=signin_host(NoManager))
  t.run_for(@ui.move_most_ms)
  assert_true(card_has(t, "在画面中登录"))
  m.set(signin_post_with(more={ "status": Json::string("done"), "keep": Json::boolean(true), "save": Json::string("r-save"), "kept": Json::string("granted") }))
  t.run_for(@ui.move_most_ms)
  assert_false(card_has(t, "在画面中登录"))
  assert_false(card_has(t, "查看 PR #512 的 Actions 日志"))
  let line = "已登录 github.com · 已存入密钥库"
  assert_true(card_has(t, line))
  card_audit(t, "decided", signin_rooms("kept"))
  t.click(Button, label=line + " · " + @sf.t("web-main.history.details"))
  t.run_for(@ui.move_most_ms)
  assert_true(@sf.presenting())
  assert_true(card_has(t, "登录 github.com"))
  assert_true(card_has(t, "查看 PR #512 的 Actions 日志"))
  @sf.close_all_presented()
  t.run_for(@ui.move_most_ms)
  assert_false(@sf.presenting())
}

