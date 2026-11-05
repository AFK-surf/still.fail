// What a sweep of the app's pages found worse than before the chats' lists and the chat page were made once
// (d540841ab1^, zz_sweep_wbtest's steps on both, 2026-11-05), each held to what the build before did: frames drawn
// over the whole window where it drew a part, nodes made between frames where it made none.

///|
/// A page in `mode` at `w` × `h` on `platform`, as a host draws it (Tester::run_as_host, recorded).
fn swept(mode : String, w : Double, h : Double, platform : Int) -> @ui.Tester {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode~, w~, h~, platform~)
  t.set_frame_period(if platform == 0 { 1000.0 / 60.0 } else { 1000.0 / 120.0 })
  t.record_host()
  t.run_as_host(@ui.move_most_ms)
  t
}

///|
/// A step's frames: `f` done, then the display's frames for `ms` as a host draws them.
fn swept_step(t : @ui.Tester, ms : Double, f : () -> Unit) -> Array[@ui.HostFrame] {
  t.host_frames() |> ignore
  f()
  t.run_as_host(ms)
  t.host_frames()
}

///|
fn whole_frames(frames : Array[@ui.HostFrame]) -> Int {
  frames.filter(fn(f) { f.damage_share >= 1.0 }).length()
}

///|
fn made_between(frames : Array[@ui.HostFrame]) -> Int {
  frames.iter().fold(init=0, fn(a, f) {
    a + f.between.iter().fold(init=0, fn(b, c) { if c.0 == "made" { b + c.1 } else { b } })
  })
}

///|
/// A chat holding a visualization (chat-viz), on a desktop: what it draws is drawn again where it changes, not over the
/// whole window each frame. Before (d540841ab1^): 0–3 frames whole of 30–104 for each step; 2026-11-05 every frame.
test "a chat holding a visualization, on a desktop, is not drawn over the whole window frame after frame" {
  let out : Array[String] = []
  for w in [740.0, 1280.0] {
    let t = swept("chat-viz", w, if w < 840.0 { 900.0 } else { 800.0 }, 0)
    let scrolled = swept_step(t, 1500.0, fn() { t.wheel(w * 0.6, 400.0, -600.0) })
    let hovered = swept_step(t, 1200.0, fn() { t.move(w * 0.6, 320.0) })
    for s in [("scrolled", scrolled), ("hovered", hovered)] {
      let whole = whole_frames(s.1)
      if whole > 3 {
        out.push("\{s.0} at \{w}: \{whole} of \{s.1.length()} frames over the whole window")
      }
    }
  }
  assert_eq(out, [])
}

///|
/// A chat's messages scrolled on a large screen: their rows come and go as they show, nothing else made between frames.
/// Before (d540841ab1^): no node made between frames; 2026-11-05: 584.
test "a chat's messages scrolled on a large screen make no nodes between frames" {
  let t = swept("chat", 1280.0, 800.0, 0)
  let frames = swept_step(t, 1500.0, fn() { t.wheel(1280.0 * 0.6, 400.0, -600.0) })
  assert_eq(made_between(frames), 0)
}

///|
/// Another chat chosen in a large screen's sidebar: its page made in its frames, not as a heap of nodes between them.
/// Before (d540841ab1^): 6–7 nodes made between frames; 2026-11-05: 193–195.
test "another chat chosen on a large screen makes no more nodes between frames than before" {
  let out : Array[String] = []
  for mode in ["home", "chat"] {
    let t = swept(mode, 1280.0, 800.0, 0)
    match t.find("夜里的构建又失败了") {
      Some((x, y)) => {
        let frames = swept_step(t, @ui.move_most_ms, fn() {
          t.touch_at(0, x, y, t.time())
          t.touch_at(2, x, y, t.time())
        })
        let made = made_between(frames)
        if made > 7 {
          out.push("from \{mode}: \{made} nodes made between frames")
        }
      }
      None => out.push("from \{mode}: no other chat in the sidebar")
    }
  }
  assert_eq(out, [])
}

///|
/// The chats' list on a medium and a large screen, hovered and scrolled: drawn again where it changes. Before
/// (d540841ab1^): no frame over the whole window for either; 2026-11-05: 4–5.
test "the chats' list on a medium or large screen, hovered or scrolled, is never drawn over the whole window" {
  let out : Array[String] = []
  for w in [740.0, 1280.0] {
    let t = swept("home", w, if w < 840.0 { 900.0 } else { 800.0 }, 0)
    let scrolled = swept_step(t, 1500.0, fn() { t.wheel(w * 0.6, 400.0, -600.0) })
    let hovered = swept_step(t, 1200.0, fn() { t.move(w * 0.6, 320.0) })
    for s in [("scrolled", scrolled), ("hovered", hovered)] {
      let whole = whole_frames(s.1)
      if whole > 0 {
        out.push("\{s.0} at \{w}: \{whole} of \{s.1.length()} frames over the whole window")
      }
    }
  }
  assert_eq(out, [])
}
