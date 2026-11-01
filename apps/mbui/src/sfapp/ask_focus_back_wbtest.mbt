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
  println("ASKFOCUS fixture \{fixture_first} drawn \{drawn}")
  assert_eq((fixture_first.2, drawn.2), ("TextField 发消息", "TextField 发消息"), msg="fixture \{fixture_first} drawn \{drawn}")
}
