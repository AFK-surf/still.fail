// The wide frame off the tape, the sidebar folded and shown a while as the chat put in the page's place waits for what
// it shows, the chat before kept in its place meanwhile (sfdesk's page_pane.mbt, page_wait.mbt): what is kept moved
// aside as the sidebar comes, and the chat come once it has its view moved aside as far.

///|
/// Where words `w` are drawn across in the page (the rightmost of them: the sidebar shown a while may show them too);
/// -1 where nowhere.
fn page_word_x(t : @ui.Tester, w : String) -> Double {
  t.locate(w).fold(init=-1.0, fn(m, p) { if p.0 > m { p.0 } else { m } })
}

///|
test "大屏: the sidebar shown a while while the chat put in place waits for its view: the chat before kept and moved aside; the chat come moved aside as far" {
  new_run()
  let answered = @signals.signal(false)
  let src = over_source(answered)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.draw()
  t.key(@ui.key_of_char('\\'), mods=@ui.mod_cmd)
  t.move_to(1000.0, 400.0)
  t.run_for(@ui.move_most_ms)
  let kept_rest = page_word_x(t, "发消息")
  assert_true(kept_rest > 0.0 && page_word_x(t, "做完了：") > 0.0)
  // (the chat put in place waits: the one before kept)
  @sfbase.open_page(Chat(over_chat))
  t.frame()
  assert_true(app.nav.top() is Chat({ session: "s-c2", .. }))
  assert_eq(page_word_x(t, "发消息"), kept_rest)
  assert_true(page_word_x(t, "做完了：") > 0.0)
  assert_eq(page_word_x(t, "好的，我来处理。"), -1.0)
  // (shown a while, the pointer on the folded bar kept there: what is kept moved aside)
  let (rx, ry, rw, rh) = t.query(Button, label="文件").unwrap().rect
  t.move_to(rx + rw / 2.0, ry + rh / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_true(@sfdesk.wide.peeking.get())
  assert_true(page_word_x(t, "做完了：") > 0.0)
  let aside = page_word_x(t, "发消息") - kept_rest
  assert_true(aside > 0.0, msg="\{aside}")
  let said = @sfdesk.pane_reach_at(t.time()).map(fn(f) { f.1 }).unwrap_or(-1.0)
  assert_true((aside - said).abs() < 1.0e-6, msg="drawn \{aside}, said \{said}")
  // (its view given: the chat come, as far aside)
  answered.set(true)
  t.run_for(@ui.move_most_ms)
  assert_eq(page_word_x(t, "做完了："), -1.0)
  assert_true(page_word_x(t, "好的，我来处理。") > 0.0)
  let come_aside = page_word_x(t, "发消息")
  let said_come = @sfdesk.pane_reach_at(t.time()).map(fn(f) { f.1 }).unwrap_or(-1.0)
  assert_true(@sfdesk.wide.peeking.get())
  // (the pointer off it: let go, a while after)
  t.move_to(1000.0, 400.0)
  t.run_for(@ui.move_most_ms * 4.0)
  assert_false(@sfdesk.wide.peeking.get())
  let come_rest = page_word_x(t, "发消息")
  assert_true(come_rest > 0.0)
  assert_true(
    (come_aside - come_rest - aside).abs() < 1.0e-6,
    msg="come \{come_aside - come_rest} (\{come_aside}, said \{said_come}), kept \{aside}",
  )
}
