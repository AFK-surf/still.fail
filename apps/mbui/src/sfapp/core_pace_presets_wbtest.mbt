// A new chat's first words sent on 小屏 with the core answering a frame or more after it is asked (core_pace_wbtest
// holds it at once): the column of 预设 under the field comes to its height of 52 in one frame (sizes_steady, at 60
// and 120 a second); this file's bar holds it and only falls.

///|
/// The core's answers a new chat on 小屏 jumps with now.
let pace_presets_ms : Array[Double] = [
  16.0,
  300.0,
  @sfbase.flight_desk_ms,
  @sfbase.flight_ms,
  @sfbase.flight_ms + 100.0,
  1000.0,
]

///|
test "core pace, late: a new chat, 小屏" {
  for ms in pace_presets_ms {
    let src = pace_src("home", ms)
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=daily_small.w, h=daily_small.h, platform=daily_small.platform)
    pace_new_chat(t, daily_small, ms)
  }
}
