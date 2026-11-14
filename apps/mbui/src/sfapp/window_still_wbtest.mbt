// What the window does sets nothing moving (src/sf/motion.mbt: "what the window, the sidebar, a keyboard or the tier
// does to a thing is no motion of its own"; the owner, 2026-11-12, of 0.1.8704: 「调整宽度的时候，动得很奇怪，居然有过渡
// 效果」, and 「合两个 PR，再加两条新检查」): Home and a chat on each screen of daily_paths_wbtest, at rest, the window
// made wider and narrower across the tiers' edges, shorter and taller, a soft keyboard up and down over a chat's field
// with touch, a phone turned; on the frame each is drawn nothing is said to move (Tester::moving). What does now is
// `window_still_known`, a cell a line, which only falls: a cell mended fails here till it is taken off.

///|
/// A change of the window: its name, the size it comes to and the keyboard's height over its foot (0 none).
priv struct Step {
  name : String
  w : Double
  h : Double
  ime : Double
}

///|
/// The cells that set something moving now, `screen page step` (what moved, a cell's first line, said as it fails).
let window_still_known : Array[String] = [
  // (the bar's springs, sfapp/bar.mbt:170)
  "小屏 home upright",
  // (chat-askfade, motion/layer.mbt:1325)
  "小屏 chat turned", "小屏 chat upright",
]

///|
/// The steps walked on `s`, in order, each from where the one before left it, at rest.
fn still_steps(s : Screen, mode : String) -> Array[Step] {
  let steps = []
  let kb = 300.0
  if s.platform != 0 && mode == "chat" {
    steps.push({ name: "keyboard up", w: s.w, h: s.h - kb, ime: kb })
    steps.push({ name: "keyboard down", w: s.w, h: s.h, ime: 0.0 })
  }
  if s.w < 600.0 {
    // (a phone turned and back)
    steps.push({ name: "turned", w: s.h, h: s.w, ime: 0.0 })
    steps.push({ name: "upright", w: s.w, h: s.h, ime: 0.0 })
  } else {
    for w in [1100.0, 900.0, 700.0, 500.0] {
      steps.push({ name: "to \{w.to_int()} wide", w, h: s.h, ime: 0.0 })
    }
    steps.push({ name: "back to \{s.w.to_int()} wide", w: s.w, h: s.h, ime: 0.0 })
    steps.push({ name: "to 600 tall", w: s.w, h: 600.0, ime: 0.0 })
    steps.push({ name: "back to \{s.h.to_int()} tall", w: s.w, h: s.h, ime: 0.0 })
  }
  steps
}

///|
/// `mode`'s page on `s` walked through still_steps: the cells that set something moving, and what (its first line).
fn still_walk(s : Screen, mode : String) -> Array[(String, String)] {
  let t = daily_open(mode, s, 1.0)
  if mode == "chat" {
    t.tap_text("发消息")
    t.run_for(@ui.move_most_ms)
  }
  let moved = []
  for step in still_steps(s, mode) {
    if s.platform != 0 {
      t.set_ime_inset(step.ime)
    }
    t.resize(step.w, step.h)
    let m = t.moving()
    if m.length() > 0 {
      moved.push(("\{s.name} \{mode} \{step.name}", m[0]))
    }
    t.run_for(@ui.move_most_ms)
  }
  moved
}

///|
/// `mode`'s page on `s` holds window_still_known: a cell not in it that moved fails, as does one in it that no longer
/// does (its line comes off).
fn still_held(s : Screen, mode : String) -> Unit raise {
  let moved = still_walk(s, mode)
  let prefix = "\{s.name} \{mode} "
  let said = []
  for c in moved {
    println("WINDOW_STILL \{c.0}: \{c.1}")
    if !window_still_known.contains(c.0) {
      said.push("\{c.0} sets something moving: \{c.1}")
    }
  }
  for k in window_still_known {
    if k.has_prefix(prefix) && !moved.iter().any(fn(c) { c.0 == k }) {
      said.push("\{k} sets nothing moving now: take it off window_still_known")
    }
  }
  if said.length() > 0 {
    fail(said.join("\n"))
  }
}

///|
test "window still: Home, 小屏" {
  still_held(daily_small, "home")
}

///|
test "window still: a chat, 小屏" {
  still_held(daily_small, "chat")
}

///|
test "window still: Home, 中屏" {
  still_held(daily_medium, "home")
}

///|
test "window still: a chat, 中屏" {
  still_held(daily_medium, "chat")
}

///|
test "window still: Home, 大屏" {
  still_held(daily_large, "home")
}

///|
test "window still: a chat, 大屏" {
  still_held(daily_large, "chat")
}
