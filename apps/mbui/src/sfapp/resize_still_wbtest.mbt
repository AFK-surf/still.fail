// The window's width changed in one step (an edge dragged, a window made narrower or wider): nothing moves for it
// (apps/mbui/AGENTS.md, Motion: what the window does to a thing is no motion of its own; the owner, 2026-11-12: 「调整
// 宽度的时候，居然有过渡效果」). A chat open and Home, on 大屏 with a pointer and 中屏 with touch, the window taken across
// the widths a chat's list is laid out narrow and wide at (sfpages' chat_narrow_w) both ways and across the tiers: in
// the frame that takes the width, everything is where it is laid out, nothing on its way, and nothing drawn moves as
// long as the longest move would go after it.
// What the new width shows that the core is asked for then (the chat's outline rail, once there is room for it) comes
// as it is answered, a round trip after: that is no motion, and not held here.

///|
/// What is drawn where, as a person would see it move: what is read out and where it is drawn, and the glass grounds
/// (the composer's box, a capsule) by their rectangles: (what, where).
fn resize_still_seen(t : @ui.Tester) -> Array[(String, String)] {
  let out = t.semantics().map(fn(n) { (n.label, @ui.rect_text(n.rect)) })
  for g in t.drawn_glass() {
    let (x, y, w, h, _, _) = g
    out.push(("glass", @ui.rect_text((x, y, w, h))))
  }
  out
}

///|
/// How long after the width is taken what it asked the core for is answered: daily_open's core answers 60 ms on.
let resize_answered_ms : Double = 100.0

///|
test "the window resized: nothing moves for it, in a chat or on Home" {
  let faults : Array[String] = []
  for scr in [daily_large, daily_medium] {
    for mode in ["chat", "home"] {
      let t = daily_open(mode, scr, 1.0)
      // (the page's opening over first: its slide in, the pictures of its messages brushed in as they are decoded)
      t.run_for(@sf.reveal_ms)
      assert_eq(@ui.some_text(t.idle_said()), "None", msg="\{scr.name} \{mode}: still moving as it opened")
      let mut was = scr.w
      for w in [1100.0, 900.0, 700.0, 500.0, 1280.0] {
        t.resize(w, scr.h)
        let at = "\{scr.name} \{mode} \{was} → \{w}"
        was = w
        // (on its way: a motion, or a slide's end due; not the core's answer awaited, a timer)
        match t.idle_said() {
          Some(why) if why.contains("motion") || why.contains("a wake") => faults.push("\{at}: \{why}")
          _ => ()
        }
        // (what the new width asks the core for answered first, a round trip on)
        t.run_for(resize_answered_ms)
        let seen = resize_still_seen(t)
        // (nothing drawn elsewhere as long as the longest move would go)
        t.run_for(@ui.move_most_ms)
        // (what was drawn then, drawn elsewhere now)
        let moved = resize_still_seen(t).filter(fn(s) {
          !seen.contains(s) && seen.iter().any(fn(o) { o.0 == s.0 })
        })
        if !moved.is_empty() {
          faults.push(
            "\{at}: drawn elsewhere a move later: " +
            moved.iter().take(3).map(fn(m) { "\{m.0} \{m.1}" }).collect().join("; "),
          )
        }
        // (whatever was left moving, at rest before the next width: one width's fault not read as the next's)
        t.run_for(@ui.move_most_ms)
      }
    }
  }
  assert_eq(faults.join("\n"), "")
}
