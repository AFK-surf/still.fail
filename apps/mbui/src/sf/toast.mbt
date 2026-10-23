// A toast (web/ui toast.tsx, toast.css.ts): a short line at the bottom of the window, in the middle, named after what
// happened; 2.6 s, then it goes. mbui's toast (@kit.toaster: paused while the pointer is on it, swiped away) in the
// web's look. The phone's own toast is the phone's (the web's ToastTo).

///|
/// How long a toast stays (Toast.Provider's duration: 2.6 s).
pub let toast_ms : Double = 2600.0

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
pub fn toast_look(c : @ui.Ctx, s : @kit.ToastState) -> Unit {
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
      c.text(s.toast.title, style=toast_words) |> ignore
    },
  )
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let toast_box : @ui.Style = @ui.style(px=S4_5, bg=Primary, max_w=Fixed(toast_max))

///|
// kept across runs: a value (no field of it changes)
let toast_words : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=OnPrimary)
