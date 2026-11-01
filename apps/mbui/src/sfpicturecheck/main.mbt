// Real offscreen checks for a picture of the current tree, a prepared scene and a named time.

///|
let picture_transition_ms : Double = 50.0

///|
let picture_exact_ms : Double = 20.0

///|
fn main {
  let mode = @film.arg("MBUI_PICTURE_CHECK")
  let out = @film.arg("MBUI_PICTURE_CHECK_OUT")
  let use_tree = mode == "tree" || mode == "prepared" || mode == "failed" || mode.has_prefix("frame-")
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let made = Ref(false)
  let view = fn(c : @ui.Ctx) {
    if mode == "time-start" || mode == "time-end" {
      let motion = @motion.anim(c, "picture-test-time", 0.0)
      if !made.val {
        made.val = true
        motion.animate(1.0, @motion.tween_to(duration=picture_transition_ms))
      }
      @figure.canvas(c, 100.0, 100.0, if motion.get() >= 1.0 { 0x00FF00FFL } else { 0xFF0000FFL }, fn() {})
    }
    if mode.has_prefix("time-exact-") {
      let motion = @motion.anim(c, "picture-test-exact", 0.0)
      if !made.val {
        made.val = true
        motion.animate(1.0, @motion.tween_to(duration=picture_exact_ms, ease=@motion.linear))
      }
      // The midpoint is between the two capture times and before the next 60 Hz frame.
      let green = motion.get() >= 0.5
      @figure.canvas(c, 100.0, 100.0, if green { 0x00FF00FFL } else { 0xFF0000FFL }, fn() {})
    }
    if mode == "transparent" {
      @figure.canvas(c, 50.0, 50.0, 0xFF0000FFL, fn() {})
    }
    if mode == "native" {
      @figure.canvas(c, 100.0, 100.0, if @ui.native_pointing() is Finger { 0xFF0000FFL } else { 0x00FF00FFL }, fn() {})
    }
  }
  let tree = fn(root : @view.View) {
    if use_tree {
      root.box(fn(n) {
        n.width(Is(Some(100.0)))
          .height(Is(Some(100.0)))
          .ground(By(fn() { if on.get() { 0x00FF00FFL } else { 0xFF0000FFL } }))
          .presses(Is(true))
          .says(Is(Some(@view.said(Button, label="Switch"))))
          .on_press(fn() { on.set(true) })
        |> ignore
      }) |> ignore
    }
  }
  let prepare = match mode {
    "prepared" => "tap Switch\nexit"
    "failed" => "no-such-step"
    _ => ""
  }
  let script = if mode == "frame-failed" {
    "no-such-step"
  } else if mode.has_prefix("frame-") {
    "wait 80\ntap Switch\nwait 200\nexit"
  } else {
    ""
  }
  let frame = match mode {
    "frame-start" => Some(0)
    "frame-middle" => Some(15)
    "frame-after" => Some(100)
    "frame-failed" => Some(1)
    _ => None
  }
  let ok = @film.picture(
    view,
    tree?=if use_tree { Some(tree) } else { None },
    path=out,
    w=100.0,
    h=100.0,
    scale=1.0,
    prepare~,
    script~,
    frame?,
    at=match mode {
      "time-end" => picture_transition_ms * 2.0
      "time-exact-early" => 5.0
      "time-exact-late" => 15.0
      _ => 0.0
    },
    transparent=mode == "transparent",
  )
  @film.exit(if ok { 0 } else { 1 })
}
