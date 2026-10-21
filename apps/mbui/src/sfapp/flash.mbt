// A message gone to flashing (ember apps/android chat/screens/ChatMotion.kt flash, flashed; Chat.kt SaidRow): the
// accent's ground round the message, reaching 10 past it on each side and 8 above and below (into the list's
// padding and half the gap between messages), corners of 14; your words' bubble takes it instead. Only drawn: under
// the list's rows (@ui.on_list_underlay), never laid out, nothing of it at rest.

///|
/// The message flashing in the chat drawn now (its ts, "" none) and how lit it is.
let flashing : Ref[(String, Double)] = Ref(("", 0.0))

///|
/// Its row: the frame it was built in, the node, the gap above its message, how lit.
let flash_row : Ref[(Int, Int, Double, Double)?] = Ref(None)

///|
// kept across runs: mbui keeps the underlay it installed (on_list_underlay) for the process too
let flash_installed : Ref[Bool] = Ref(false)

///|
/// The accent's ground in a chat (ChatMotion.kt accentBg: web --accent-bg).
fn flash_ground() -> Int64 {
  if @sf.theme().dark {
    0x43251AFFL
  } else {
    0xFFEFE6FFL
  }
}

///|
/// Row `ri` (its message `top` below its top) flashing, `lit` of the way: drawn under the rows as they are painted.
fn flash_under(c : @ui.Ctx, ri : Int, top : Double, lit : Double) -> Unit {
  if !flash_installed.val {
    flash_installed.val = true
    @ui.on_list_underlay(fn(c, li) {
      match flash_row.val {
        Some((frame, row, top, lit)) if frame == c.frame_number() && c.list_above(row) == li => {
          let (x, y, w, h) = c.drawn_rect(row)
          // the row's own padding: 14 each side, `top` over the message
          c.paint_rect(
            x + 4.0,
            y + top - 8.0,
            w - 8.0,
            h - top + 16.0,
            radius=14.0,
            @sf.alpha(flash_ground(), lit),
          )
        }
        _ => ()
      }
    })
  }
  flash_row.val = Some((c.frame_number(), ri, top, lit))
}
