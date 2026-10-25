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
/// A toast's look (toast.css.ts toast): 9 by 18 in, 20 round, the primary ink's ground, its words 13 in the ink on it,
/// 560 wide at most, a floating shadow; coming in from 8 below and going as it fades.
/// Its action (`action`'s words, "" none) at its end, its id `action_id` (the toaster's `<key>/<toast>/action`, so the
/// focus on it holds the toast); whether it was pressed.
pub fn toast_look(c : @ui.Ctx, s : @kit.ToastState, action? : String = "", action_id? : Int = 0) -> Bool {
  let mut pressed = false
  let k = if s.t > 1.0 { 1.0 } else if s.t < 0.0 { 0.0 } else { s.t }
  c.box(
    style=toast_box,
    pady=toast_py,
    radius=toast_r,
    shadow=toast_shadow,
    shadow_y=toast_shadow_y,
    shadow_color=theme().p.shadow,
    opacity=k,
    tx=s.dx,
    ty=(1.0 - k) * toast_rise,
    fn() {
      if action == "" {
        c.text(s.toast.title, style=toast_words) |> ignore
      } else {
        c.box(style=toast_row, fn() {
          c.text(s.toast.title, style=toast_words) |> ignore
          pressed = toast_button(c, action_id, action)
        })
        |> ignore
      }
    },
  )
  |> ignore
  pressed
}

///|
/// A toast's button (toast.tsx ToastAction): its words in the toast's ink, bold, on a faint ground of it, 28 high and
/// round; whether it was pressed.
pub fn toast_button(c : @ui.Ctx, id : Int, words : String) -> Bool {
  let r = c.interact(id)
  let i = c.box(style=toast_action_box, id~, fn() { c.text(words, style=toast_action_words) |> ignore })
  c.semantics(i, Button, id~, label=words, actions=[Activate])
  r.clicked
}

///|
/// A toast's words and its action beside them (toast_look's, the phone's).
// kept across runs: a value (no field of it changes)
pub let toast_row : @ui.Style = @ui.css("row gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let toast_action_box : @ui.Style = @ui.css(
  "h=S7 px=S3 radius=Full align=ACenter justify=JCenter bg=A(OnPrimary, O15) hovered{bg=A(OnPrimary, O20)} pressed{bg=A(OnPrimary, O25)}",
)

///|
// kept across runs: a value (no field of it changes)
let toast_action_words : @ui.TextStyle = @ui.text_style(size=Sm, weight=Semibold, leading=L5, color=OnPrimary, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let toast_box : @ui.Style = @ui.style(px=S4_5, bg=Primary, max_w=Fixed(toast_max))

///|
// kept across runs: a value (no field of it changes)
let toast_words : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=OnPrimary)
