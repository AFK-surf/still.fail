// A toast (web/ui toast.tsx, toast.css.ts): a short line at the bottom of the window, in the middle, named after what
// happened; 2.6 s, then it goes. Where the frame puts them at the top (a phone's), it drops in from over the window's
// edge on a spring that goes a little past its place, growing from narrower as it lands, and goes back up. mbui's toast (@kit.toaster: paused while the pointer is on it, swiped away) in the
// web's look. The phone's own toast is the phone's (the web's ToastTo).

///|
/// How long a toast stays (Toast.Provider's duration: 2.6 s).
pub let toast_ms : Double = 2600.0

///|
/// How long a toast offering something to do stays (an archive's 撤销): long enough to reach for it.
pub let toast_action_ms : Double = 5000.0

///|
/// What a toast says (said): a write its station did not answer may have been done (the core's `unconfirmed`), said as
/// not known, whatever the page put before it ("没能固定：不确定做没做成：…" → "固定：不确定做没做成：…").
pub fn toast_said(message : String) -> String {
  for lead in ["没能", "无法"] {
    if message.has_prefix(lead) {
      let rest = message.unsafe_substring(start=lead.length(), end=message.length())
      for unknown in ["不确定做没做成：", "无法确认是否成功："] {
        match rest.find("：" + unknown) {
          // (what failed said before it, with no other ： in it)
          Some(i) if !rest.unsafe_substring(start=0, end=i).contains("：") => return rest
          _ => ()
        }
      }
    }
  }
  message
}

///|
/// A toast's look (toast.css.ts toast): its words 13 in the ink on the primary ink's ground (toast_r, toast_py,
/// toast_px: a capsule while they fit one line), 560 wide at most, a floating shadow; coming in from 8 below and going
/// as it fades (at the top: dropping in from toast_drop over its place, toast_narrow of its width at first). Its action (`action`'s words, "" none) a capsule in its end, concentric with it (toast_action_in from
/// its top, foot and end), its id `action_id` (the toaster's `<key>/<toast>/action`, so the focus on it holds the
/// toast); whether it was pressed.
pub fn toast_look(c : @ui.Ctx, s : @kit.ToastState, action? : String = "", action_id? : Int = 0) -> Bool {
  let mut pressed = false
  let k = if s.t > 1.0 { 1.0 } else if s.t < 0.0 { 0.0 } else { s.t }
  // (at the top: dropping in from over its place, there at once; at the foot, rising as it fades in)
  let (seen, rise) = if s.top {
    (dmin(1.0, k * 3.0), s.dy - (1.0 - s.t) * toast_drop)
  } else {
    (k, (1.0 - k) * toast_rise)
  }
  let i = c.box(
    style=if action == "" { toast_box } else { toast_acting_box },
    radius=toast_r,
    shadow=toast_shadow,
    shadow_y=toast_shadow_y,
    shadow_color=theme().p.shadow,
    opacity=seen,
    tx=s.dx,
    ty=rise,
    fn() {
      c.box(style=toast_row, fn() {
        // (its words as far from the toast's top and foot with a button beside them as without)
        c.box(style=toast_words_box, fn() { c.text(s.toast.title, style=toast_words) |> ignore }) |> ignore
        if action != "" {
          pressed = toast_button(c, action_id, action)
        }
      })
      |> ignore
    },
  )
  if s.top && s.t != 1.0 {
    // (about its top: past its place it is wider and flatter for a moment, as what lands is)
    let w = toast_narrow + (1.0 - toast_narrow) * s.t
    c.look(i, @ui.look(sx=w, sy=1.0 - (w - 1.0) * 0.5, oy=0.0))
  }
  pressed
}

///|
/// How far over its place a toast at the top drops in from, and how wide of its width it starts.
pub let toast_drop : Double = 72.0

///|
pub let toast_narrow : Double = 0.6

///|
/// The spring a toast at the top drops in on: a little past its place and back.
// kept across runs: a value (no field of it changes)
pub let toast_drop_spring : @motion.Spec = @motion.motion_spring(0.5, bounce=0.3)

///|
/// How long a toast takes to come in, at most: one at the top dropping in on its spring, to its end; one at the foot,
/// sooner (@kit.presence_in_ms).
pub let toast_in_ms : Double = toast_drop_spring.duration(0.0, 1.0, 0.0)

///|
/// A toast's button (toast_look's): its words in the toast's ink, bold, on a faint ground of it, a capsule
/// toast_action_h high; whether it was pressed.
pub fn toast_button(c : @ui.Ctx, id : Int, words : String) -> Bool {
  let r = c.interact(id)
  let i = c.box(style=toast_action_box, id~, fn() { c.text(words, style=toast_action_words) |> ignore })
  c.semantics(i, Button, id~, label=words, actions=[Activate])
  r.clicked
}

///|
/// A toast's words and its action beside them, in the middle of its height.
// kept across runs: a value (no field of it changes)
let toast_row : @ui.Style = @ui.css("row gap=S3 align=ACenter")

///|
/// (its button's words toast_px from the toast's end, as its words are from its start)
// kept across runs: a value (no field of it changes)
let toast_action_box : @ui.Style = @ui.style(
  h=Fixed(toast_action_h),
  px=room(toast_px - toast_action_in),
  radius=Full,
  align=ACenter,
  justify=JCenter,
  bg=A(OnPrimary, O15),
  hovered=@ui.patch(bg=A(OnPrimary, O5)),
  pressed=@ui.patch(bg=A(OnPrimary, O5)),
)

///|
// kept across runs: a value (no field of it changes)
let toast_action_words : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, leading=L5, color=OnPrimary, wrap=false)

///|
/// (toast_action_in over and under all it holds, its words' own room the rest of toast_py)
// kept across runs: a value (no field of it changes)
let toast_box : @ui.Style = @ui.style(
  px=room(toast_px),
  py=room(toast_action_in),
  bg=Primary,
  max_w=Fixed(toast_max),
)

///|
/// With a button in its end: toast_action_in from it there, as over and under it.
// kept across runs: a value (no field of it changes)
let toast_acting_box : @ui.Style = toast_box.then(@ui.style(pr=room(toast_action_in)))

///|
// kept across runs: a value (no field of it changes)
let toast_words_box : @ui.Style = @ui.style(py=room(toast_py - toast_action_in))

///|
// kept across runs: a value (no field of it changes)
let toast_words : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=OnPrimary)
