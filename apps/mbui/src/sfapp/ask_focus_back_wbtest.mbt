// A question opened over a chat on 大屏, started with keyboard and mouse, then closed by Escape: what has the focus
// after, as the old dialog left it (the chat's message field). Opened as a film opens its fixture's (sffilm's main: the
// source made, the question asked, as the Tester's first frame begins) or once the chat is drawn.

///|
/// How long a film's run waits round each of its steps (corners.sh's drive: its wait 1200), as these go.
let film_step_ms : Double = 1200.0

///|
/// 大屏 started with keyboard and mouse (macOS), chat A open; the question chat-ask's asked as the fixture asks it (the
/// source made as the Tester's first frame begins, as sffilm's is: `fixture`) or once the chat is drawn; closed by
/// Escape. What had the focus before it opened (the fixture's: none read, it opens before any frame), inside it, and
/// after, each with whether the message field says its key puts the cursor there.
fn ask_focus_round(fixture_first : Bool) -> (String, String, String) {
  let src : Ref[Source?] = Ref(None)
  let source = fn() {
    match src.val {
      Some(s) => s
      None => {
        let s = if fixture_first {
          fixture_app("chat-ask")
        } else {
          new_run()
          let s = fixture("chat")
          open_chat(chat_a)
          s
        }
        src.val = Some(s)
        s
      }
    }
  }
  let t = @ui.Tester::new(fn(c) { view(c, source()) }, tree=fn(root) { app_tree(source())(root) }, w=1280.0, h=800.0, platform=0)
  let said = fn() {
    let f = t.focused().map(fn(s) { "\{s.role} \{s.label}" }).unwrap_or("none")
    // (and whether the chat's message field says its key puts the cursor there: none of what takes keys focused)
    f + (if t.find("按空格输入") is Some(_) { " / 按空格输入 shown" } else { "" })
  }
  t.run_for(film_step_ms)
  let before = if fixture_first {
    "(asked before any frame)"
  } else {
    let b = said()
    @sf.ask("重新命名这个对话", "保存", fn(_) {  }, value="周报整理", hint="名字会同步给所有成员。")
    t.run_for(film_step_ms)
    b
  }
  let inside = said()
  t.key(@ui.key_escape)
  t.run_for(film_step_ms)
  (before, inside, said())
}

///|
test "大屏, keyboard and mouse: a question asked over a chat as a film's fixture asks it, or once the chat is drawn, closed by Escape: the chat's message field has the focus after, as the old dialog left it" {
  let fixture_first = ask_focus_round(true)
  let drawn = ask_focus_round(false)
  assert_eq((fixture_first.2, drawn.2), ("TextField 发消息", "TextField 发消息"), msg="fixture \{fixture_first} drawn \{drawn}")
}

///|
test "大屏, keyboard and mouse: Space puts the cursor in a new chat's composer when its hint says it does" {
  new_run()
  let src = fixture("home")
  @sfbase.open_page(NewChat)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(film_step_ms)
  let focused = fn() { t.focused().map(fn(s) { "\{s.role} \{s.label}" }).unwrap_or("none") }
  t.ctx().blur()
  t.run_for(film_step_ms)
  assert_true(app.nav.top() == NewChat && t.find("按空格输入") is Some(_), msg="before: \{focused()}")
  t.key(@ui.key_space)
  t.run_for(film_step_ms)
  assert_true(t.ctx().focused_id() != 0 && t.find("按空格输入") is None, msg="after Space: \{focused()}")
  assert_true(focused().has_prefix("TextField"), msg="after Space: \{focused()}")
  t.type_text("ab")
  t.run_for(film_step_ms)
  assert_eq(@sfbase.writing(src, "new:ws1").field.text(), "ab")
}

///|
test "大屏, keyboard and mouse: Space in the switcher stays there instead of focusing the new chat under it" {
  new_run()
  let src = fixture("home")
  @sfbase.open_page(NewChat)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(film_step_ms)
  @sfdesk.switcher_toggle(t.ctx())
  t.run_for(film_step_ms)
  let switcher_focus = t.ctx().focused_id()
  assert_true(@sfdesk.switcher_open() && switcher_focus != 0)
  t.key(@ui.key_space)
  t.run_for(film_step_ms)
  assert_true(@sfdesk.switcher_open())
  assert_eq(t.ctx().focused_id(), switcher_focus)
  assert_eq(@sfbase.writing(src, "new:ws1").field.text(), "")
}

///|
test "窄屏, keyboard and mouse: Space puts the cursor in a new chat's composer when its hint says it does" {
  new_run()
  let src = fixture("home")
  @sfbase.open_page(NewChat)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=0)
  t.run_for(film_step_ms)
  t.ctx().blur()
  t.run_for(film_step_ms)
  assert_true(t.find("按空格输入") is Some(_))
  t.key(@ui.key_space)
  t.run_for(film_step_ms)
  assert_true(t.focused().map(fn(s) { s.role == TextField }).unwrap_or(false))
  t.type_text("ab")
  assert_eq(@sfbase.writing(src, "new:ws1").field.text(), "ab")
}

///|
fn new_chat_without_composer(kind : String) -> Source {
  let base = fixture("home")
  {
    ..base,
    topic: fn(name, params) {
      let t = (base.topic)(name, params)
      match (name, t.value) {
        ("newChat", Some(Object(v))) => {
          let m = v.copy()
          if kind == "no station" {
            m["stations"] = Json::array([])
            m["station"] = Json::null()
            m["any"] = Json::boolean(false)
          } else if kind == "blocked" {
            m["blocked"] = Json::string("profile")
          } else {
            m["runtime"] = Json::string("")
          }
          { ..t, value: Some(Json::object(m)) }
        }
        _ => t
      }
    },
  }
}

///|
test "大屏, keyboard and mouse: Space does not focus an absent composer" {
  for kind in ["no station", "blocked", "locked"] {
    new_run()
    let src = new_chat_without_composer(kind)
    @sfbase.open_page(NewChat)
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
    t.run_for(film_step_ms)
    assert_true(t.find("按空格输入") is None, msg=kind)
    t.ctx().blur()
    t.run_for(film_step_ms)
    t.key(@ui.key_space)
    assert_eq(t.ctx().focused_id(), 0, msg=kind)
  }
}

///|
test "大屏, keyboard and mouse: Space leaves the focus on a button when the new chat has no composer" {
  new_run()
  let src = new_chat_without_composer("blocked")
  @sfbase.open_page(NewChat)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(film_step_ms)
  t.act(Button, Focus, label="添加 Profile")
  assert_true(t.focused().map(fn(s) { s.label == "添加 Profile" }).unwrap_or(false))
  let before = t.ctx().focused_id()
  t.key(@ui.key_space)
  assert_eq(t.ctx().focused_id(), before)
  assert_true(t.focused().map(fn(s) { s.label == "添加 Profile" }).unwrap_or(false))
}

///|
test "keyboard and mouse: Space on the preset button opens its menu instead of focusing the composer" {
  for width in [390.0, 1280.0] {
    new_run()
    let src = fixture("newchat")
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=width, h=844.0, platform=0)
    open_mode("newchat")
    t.run_for(film_step_ms)
    t.ctx().blur()
    t.run_for(film_step_ms)
    t.act(Button, Focus, label="预设")
    t.key(@ui.key_space)
    t.run_for(film_step_ms)
    assert_true(t.find("不用预设") is Some(_) && t.find("新预设") is Some(_), msg="width \{width}: \{t.semantics_dump()}")
  }
}

///|
fn new_chat_words_after_space(width : Double, frame_between : Bool) -> (String, Bool) {
  new_run()
  let src = fixture("home")
  @sfbase.open_page(NewChat)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=width, h=844.0, platform=0)
  t.run_for(film_step_ms)
  t.ctx().blur()
  t.run_for(film_step_ms)
  let at = t.time()
  t.key_told(@ui.key_space, 0, at)
  if frame_between { t.draw() }
  let (ime_active, _, _, _) = t.ime()
  t.text_told("ab", at)
  t.draw()
  (@sfbase.writing(src, "new:ws1").field.text(), ime_active)
}

///|
test "keyboard and mouse: words after Space reach a new chat with or without an intervening frame" {
  let narrow = (new_chat_words_after_space(390.0, false), new_chat_words_after_space(390.0, true))
  let wide = (new_chat_words_after_space(1280.0, false), new_chat_words_after_space(1280.0, true))
  assert_eq((narrow, wide), ((("ab", true), ("ab", true)), (("ab", true), ("ab", true))), msg="narrow \{narrow}, wide \{wide}")
}

///|
test "keyboard and mouse: composition after Space reaches a new chat without an intervening frame" {
  for width in [390.0, 1280.0] {
    new_run()
    let src = fixture("home")
    @sfbase.open_page(NewChat)
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=width, h=844.0, platform=0)
    t.run_for(film_step_ms)
    t.ctx().blur()
    t.run_for(film_step_ms)
    t.key_told(@ui.key_space, 0, t.time())
    t.compose("ni")
    let f = @sfbase.writing(src, "new:ws1").field
    assert_eq(f.composed_said(), "ni", msg="width \{width}")
    t.type_text("你")
    assert_eq(f.text(), "你", msg="width \{width}")
  }
}
