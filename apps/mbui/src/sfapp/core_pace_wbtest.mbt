// What is sent keeps still whenever the core answers (the owner, 2026-11-12, of a chat: 「发消息后偶尔往上弹一下」, and
// 「合两个 PR，再加两条新检查」): the other tests' core answers 60 ms after it is asked, so a core slower than the words'
// flight was never run. Here words are sent in a chat and as a new chat's first, on each screen of daily_paths_wbtest,
// with the core answering at once, within a frame, before the flight lands, as it lands, and after; the Tester's
// own checks of every frame judge each (what moves only for its cause, rows and gaps steady), held to the bars of
// this file and of core_pace_rows_wbtest and core_pace_presets_wbtest, which hold the cells that do not now (each
// file's Testers its own, so a cell kept still here is held to none).

///|
/// The core's answers in each cell: at once, within a frame, short of the flight, at its landing (the desk's and
/// 小屏's), after it, and long after.
let pace_ms : Array[Double] = [
  0.0,
  16.0,
  300.0,
  @sfbase.flight_desk_ms,
  @sfbase.flight_ms,
  @sfbase.flight_ms + 100.0,
  1000.0,
]

///|
/// The source of `mode` whose core answers `ms` after it is asked: a Tester made of it in each file, as its bars are
/// that file's.
fn pace_src(mode : String, ms : Double) -> @sfbase.Source {
  @sffixture.round_trip(fixture_app(mode), ms)
}

///|
/// Words sent in a chat on `s` (`t`, of pace_src("chat", ms)) with the core answering `ms` after: its field empty and
/// they are seen once all of it has come.
fn pace_chat_send(t : @ui.Tester, s : Screen, ms : Double) -> Unit raise {
  println("CORE_PACE \{s.name} chat send, core \{ms} ms")
  t.run_for(@ui.move_most_ms + ms)
  t.tap_text("发消息")
  t.run_for(@ui.move_most_ms + ms)
  let words = "看下进度"
  t.type_text(words)
  t.draw()
  tap_send(t)
  t.run_for(@sfbase.flight_ms + @sfbase.sent_down_ms + ms + @ui.move_most_ms)
  let (_, field, _, _) = t.ime()
  assert_eq(field, "", msg="\{s.name}, core \{ms} ms")
  assert_true(t.find(words) is Some(_), msg="\{s.name}, core \{ms} ms: 「\{words}」 not seen")
}

///|
/// A new chat's first words sent from Home on `s` (`t`, of pace_src("home", ms)) with the core answering `ms` after:
/// the chat on top and its field empty once all of it has come.
fn pace_new_chat(t : @ui.Tester, s : Screen, ms : Double) -> Unit raise {
  println("CORE_PACE \{s.name} new chat, core \{ms} ms")
  t.run_for(@ui.move_most_ms + ms)
  if daily_has(t, "新建对话") {
    t.click(Button, label="新建对话")
  } else {
    // (小屏: the bar's 令, at its middle, as daily_new_chat)
    let (_, y) = bar_places_at()
    t.tap(s.w / 2.0, y - 28.0 - 4.0)
  }
  t.run_for(@ui.move_most_ms + ms)
  t.tap_text("做任何事")
  t.type_text("看下进度")
  t.draw()
  tap_send(t)
  t.run_for(@sfbase.flight_desk_ms + new_leave_ms + @sfbase.sent_down_ms + ms + @ui.move_most_ms)
  assert_true(app.nav.top() is Chat(_), msg="\{s.name}, core \{ms} ms: not the chat")
  let (_, field, _, _) = t.ime()
  assert_eq(field, "", msg="\{s.name}, core \{ms} ms")
}

///|
/// A Tester of `mode` on `s`, its core answering `ms` after it is asked (made here: this file's bars).
fn pace_here(mode : String, s : Screen, ms : Double) -> @ui.Tester {
  let src = pace_src(mode, ms)
  @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=s.w, h=s.h, platform=s.platform)
}

///|
/// The core's answers a send in a chat keeps still with: at once, within a frame, and long after the flight (between,
/// core_pace_rows_wbtest).
let pace_chat_still : Array[Double] = [0.0, 16.0, 1000.0]

///|
test "core pace: sent in a chat, 小屏" {
  for ms in pace_chat_still {
    pace_chat_send(pace_here("chat", daily_small, ms), daily_small, ms)
  }
}

///|
test "core pace: sent in a chat, 中屏" {
  for ms in pace_chat_still {
    pace_chat_send(pace_here("chat", daily_medium, ms), daily_medium, ms)
  }
}

///|
test "core pace: sent in a chat, 大屏" {
  for ms in pace_chat_still {
    pace_chat_send(pace_here("chat", daily_large, ms), daily_large, ms)
  }
}

///|
test "core pace: a new chat, 小屏, the core at once" {
  pace_new_chat(pace_here("home", daily_small, 0.0), daily_small, 0.0)
}

///|
test "core pace: a new chat, 中屏" {
  for ms in pace_ms {
    pace_new_chat(pace_here("home", daily_medium, ms), daily_medium, ms)
  }
}

///|
test "core pace: a new chat, 大屏" {
  for ms in pace_ms {
    pace_new_chat(pace_here("home", daily_large, ms), daily_large, ms)
  }
}
