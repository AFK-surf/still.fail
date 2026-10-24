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
let mark_other : @ui.Style = @ui.css("w=S2_5 h=S2_5 radius=Full border=B2 border_color=Subtle")

///|
// kept across runs: a value (no field of it changes)
let mark_busy : @ui.Style = @ui.css("w=S2_5 h=S2_5")

///|
/// A row's mark (ChatMark.tsx ChatMark, its row's `key`): one that comes while the chat is in view (a new message, work
/// begun) pops in (scale 0, 1.3 at 60%, 1: 320 ms, ease-out); one there as the list is first drawn does not.
pub fn row_mark(c : @ui.Ctx, key : String, tone : String) -> Unit {
  let pop = @motion.anim(c, "side/mark-pop/" + key, 1.0, global=true)
  match marks_seen.get(key) {
    Some(was) if was != tone => {
      marks_seen[key] = tone
      if tone != "" && !@ui.reduced_motion() {
        pop.snap(0.0)
        pop.animate(1.0, @motion.tween(mark_pop_ms, ease=CssOut))
      }
    }
    None => marks_seen[key] = tone
    _ => ()
  }
  let mark = chat_mark(c, tone)
  let v = pop.get()
  if mark != 0 && v < 1.0 {
    c.look(mark, @ui.look(scale=pop_scale(v)))
  }
}

///|
/// The mark each chat has had, as its row was last drawn (ChatMark.tsx `shown`).
let marks_seen : Map[String, String] = {}

///|
fn marks_reset() -> Unit {
  marks_seen.clear()
}

///|
/// The pop's length, and its size at `v` of the way (0, 1.3 at 60%, 1).
let mark_pop_ms : Double = 320.0

///|
fn pop_scale(v : Double) -> Double {
  if v < mark_pop_peak_at {
    mark_pop_peak * v / mark_pop_peak_at
  } else {
    mark_pop_peak - (mark_pop_peak - 1.0) * (v - mark_pop_peak_at) / (1.0 - mark_pop_peak_at)
  }
}

///|
let mark_pop_peak : Double = 1.3

///|
let mark_pop_peak_at : Double = 0.6
