// A send in a chat with the core answering after it is asked but before the words' flight has long landed
// (core_pace_wbtest: what the owner saw, 2026-11-12, 「发消息后偶尔往上弹一下」): a row above the words sent goes 82
// points in one frame as the answer comes (rows_steady, at 60 and 120 a second; at the default rate at 520 ms on
// 中屏), on every screen; this file's bars hold it and only fall.

///|
/// The core's answers a send in a chat jumps with now (core_pace_wbtest's pace_chat_still keep still).
let pace_rows_ms : Array[Double] = [300.0, @sfbase.flight_desk_ms, @sfbase.flight_ms, @sfbase.flight_ms + 100.0]

///|
/// A Tester of a chat on `s`, its core answering `ms` after it is asked (made here: this file's bars).
fn pace_rows_here(s : Screen, ms : Double) -> @ui.Tester {
  let src = pace_src("chat", ms)
  @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=s.w, h=s.h, platform=s.platform)
}

///|
test "core pace, late: sent in a chat, 小屏" {
  for ms in pace_rows_ms {
    pace_chat_send(pace_rows_here(daily_small, ms), daily_small, ms)
  }
}

///|
test "core pace, late: sent in a chat, 中屏" {
  for ms in pace_rows_ms {
    pace_chat_send(pace_rows_here(daily_medium, ms), daily_medium, ms)
  }
}

///|
test "core pace, late: sent in a chat, 大屏" {
  for ms in pace_rows_ms {
    pace_chat_send(pace_rows_here(daily_large, ms), daily_large, ms)
  }
}
