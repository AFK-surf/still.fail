// A chat's state as a mark in a line (ember web/src/ChatMark.tsx ChatMark `inline`, ChatMark.css.ts chatMarkInline):
// before a row's title, on the rail's lists and workspaces. Three colours, bright in both themes: yellow at work, blue
// done and not yet read, red to be seen now; a blue ring when something waits on the viewer, a grey one when only on
// others.

///|
/// A chat's mark `tone` (the core's: busy, done, alert, wait, other; anything else none), the row's ground behind it:
/// a dot 8 across done (blue) or to be seen now (red, a soft halo 3 past it), a ring 10 across and 2 thick waiting (on
/// the viewer blue, on others grey), at work yellow spokes stepping round in 10. Its node (0 for none).
pub fn chat_mark(c : @ui.Ctx, tone : String) -> Int {
  let label = match tone {
    "busy" | "done" | "alert" | "wait" | "other" => @sf.t("web-main.chatMark." + tone)
    _ => return 0
  }
  match tone {
    "done" => c.box(style=mark_done, label~, fn() {  })
    "alert" =>
      c.box(style=mark_alert, label~, fn() {
        // (::after: inset -3, the red at 25% over the dot)
        c.layer(fn() { c.box(style=mark_halo, tx=-mark_halo_out, ty=-mark_halo_out, fn() {  }) |> ignore }) |> ignore
      })
    "wait" => c.box(style=mark_wait, label~, fn() {  })
    "other" => c.box(style=mark_other, label~, fn() {  })
    _ => c.box(style=mark_busy, label~, fn() { @sf.spokes(c, mark_busy_side, @sf.mark_yellow) |> ignore })
  }
}

///|
/// How far the alert's halo reaches past its dot, and the spokes' box.
let mark_halo_out : Double = 3.0

///|
let mark_busy_side : Double = 10.0

///|
// kept across runs: a value (no field of it changes)
let mark_done : @ui.Style = @ui.style(w=S2, h=S2, radius=Full, bg=@sf.mark_blue)

///|
// kept across runs: a value (no field of it changes)
let mark_alert : @ui.Style = @ui.style(w=S2, h=S2, radius=Full, bg=@sf.mark_red)

///|
// kept across runs: a value (no field of it changes)
let mark_halo : @ui.Style = @ui.style(w=S3_5, h=S3_5, radius=Full, bg=@sf.mark_halo)

///|
// kept across runs: a value (no field of it changes)
let mark_wait : @ui.Style = @ui.style(w=S2_5, h=S2_5, radius=Full, border=B2, border_color=@sf.mark_blue)

///|
// kept across runs: a value (no field of it changes)
let mark_other : @ui.Style = @ui.style(w=S2_5, h=S2_5, radius=Full, border=B2, border_color=Subtle)

///|
// kept across runs: a value (no field of it changes)
let mark_busy : @ui.Style = @ui.style(w=S2_5, h=S2_5)
