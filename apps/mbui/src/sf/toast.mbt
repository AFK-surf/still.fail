// A toast (web/ui toast.tsx, toast.css.ts): a short line at the bottom of the window, in the middle, named after what
// happened; 2.6 s, then it goes. mbui's toast (@kit.toaster: paused while the pointer is on it, swiped away) in the
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
/// as it fades. Its action (`action`'s words, "" none) a capsule in its end, concentric with it (toast_action_in from
/// its top, foot and end), its id `action_id` (the toaster's `<key>/<toast>/action`, so the focus on it holds the
/// toast); whether it was pressed.
pub fn toast_look(c : @ui.Ctx, s : @kit.ToastState, action? : String = "", action_id? : Int = 0) -> Bool {
  let mut pressed = false
  let k = if s.t > 1.0 { 1.0 } else if s.t < 0.0 { 0.0 } else { s.t }
  // (its ground whole by half its way in, its words from there, as a panel's: motion's Trans `ground_first`; never
  // its words and what it is over both seen in one place, docs/motion.md rule 4)
  let ground = if 2.0 * k > 1.0 { 1.0 } else { 2.0 * k }
  let words = if ground > 0.0 && 2.0 * k > 1.0 { (2.0 * k - 1.0) / ground } else { 0.0 }
  let tb = c.box(
    style=if action == "" { toast_box } else { toast_acting_box },
    radius=toast_r,
    shadow=toast_shadow,
    shadow_y=toast_shadow_y,
    shadow_color=theme().p.shadow,
    tx=s.dx,
    ty=(1.0 - k) * toast_rise,
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
  c.look(tb, @ui.look(alpha=ground, words~))
  pressed
}

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
/// (its button's words toast_px from the toast's end, as its words are from its start; a row, so that it is never
/// narrower than its words need: a title too long for the toast's line gives way and wraps, the button keeps its
/// width. In a column the words would be cut to the column's width, the button's least its padding alone, and the
/// row's room short would come off both by their width: 「撤销」 cut to its ellipsis beside a two-line title)
// kept across runs: a value (no field of it changes)
let toast_action_box : @ui.Style = @ui.style(
  row=true,
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
