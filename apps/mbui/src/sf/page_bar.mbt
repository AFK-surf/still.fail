// A page's bar of keys over what it shows (web Preview.tsx PreviewBar, Preview.css.ts previewBar, previewAddress; the
// phone's Preview.kt PreviewBar alike): a row of round keys and one capsule where it is, the same on every screen. Its
// room the theme's (Bars): a key's, an icon's, the capsule's; a finger reaches a key from round it all the same
// (mbui's press_reach), so none is drawn larger for a phone.

///|
/// The bar: 8 in, 6 over and under, a press's room high at least, its keys apart by keys_gap (8 with keyboard and
/// mouse, 16 with touch), in their middle.
pub fn page_bar(c : @ui.Ctx, body : () -> Unit) -> Unit {
  // (its keys as far apart as makes each a press's room across (keys_gap), and as high: a touch's 28 keys 6 over and
  // under are 40, under its 44)
  c.box(style=page_bar_box.then(@ui.style(min_h=Fixed(@ui.room_least()), gap=keys_gap(size=theme().bars.key))), body)
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let page_bar_box : @ui.Style = @ui.css("row w=Full px=S2 py=S1_5 align=ACenter")

///|
/// A key of the bar (PreviewBar's iconBtn, Preview.kt BarIcon): round, its icon in the ink, faint when it cannot be
/// pressed, the hover grey under the hand; its name told a screen reader and shown on hover. Whether it was pressed.
pub fn bar_key(c : @ui.Ctx, key : String, icon : String, label : String, enabled? : Bool = true) -> Bool {
  let t = theme()
  let b = t.bars
  let id = c.id(key)
  let k = c.box(style=bar_key_box.then(@ui.style(w=Fixed(b.key), h=Fixed(b.key))), id=if enabled { id } else { 0 }, fn() {
    if enabled {
      draw_icon(c, icon, b.icon, t.p.text)
    } else {
      c.box(style=bar_key_off, fn() { draw_icon(c, icon, b.icon, t.p.text) }) |> ignore
    }
  })
  c.semantics(k, Button, id=if enabled { id } else { 0 }, label~, disabled=!enabled)
  if enabled {
    tip(c, key + "/tip", id, label)
  }
  enabled && c.clicked(id)
}

///|
// kept across runs: a value (no field of it changes)
let bar_key_box : @ui.Style = @ui.css("radius=Full align=ACenter justify=JCenter hovered{bg=Hover} pressed{bg=Hover}")

///|
// kept across runs: a value (no field of it changes)
let bar_key_off : @ui.Style = @ui.css("opacity=O35")

///|
/// Where the page is (previewAddress): one capsule taking what the bar leaves, 160 at least (where the bar has less,
/// what may leave it does first: its page's drop), 4 in from what is beside it, its words 12 in and 6 apart, on the
/// chip's ground; typed in, on the card's with the focus's ring (`editing`). `id`: pressed anywhere, what its page says
/// to do (typing in it); `end`, a key of its own at its end, in a press's room across (Safari's reload in its
/// address), the rest `id`'s; `part`, how far what the page waits on has come, a line along its foot that far across in
/// its colour (Safari's, its address's).
pub fn bar_field(
  c : @ui.Ctx,
  id : Int,
  editing : Bool,
  body : () -> Unit,
  end? : (() -> Unit)? = None,
  part? : (Double, @ui.Color)? = None,
) -> Unit {
  let b = theme().bars
  let look = (if editing { bar_field_editing } else { bar_field_box }).then(@ui.style(h=Fixed(b.field)))
  c.box(style=bar_field_room, fn() {
    match end {
      None =>
        c.box(style=look, id~, fn() {
          body()
          field_part(c, part)
        })
        |> ignore
      Some(end) =>
        c.box(style=look.then(bar_field_ended), fn() {
          c.box(style=bar_field_words, id~, body) |> ignore
          c.box(style=bar_field_end.then(@ui.style(w=Fixed(@ui.room_least()))), end) |> ignore
          field_part(c, part)
        })
        |> ignore
    }
  })
  |> ignore
}

///|
/// How far it has come along the capsule's foot (bar_field's `part`), over what is in it, cut to its round.
fn field_part(c : @ui.Ctx, part : (Double, @ui.Color)?) -> Unit {
  match part {
    Some((k, color)) => {
      let across = k * 100.0
      c.box(style=bar_field_line.then(@ui.style(w=Pct(across), bg=color)), left=field_edge, bottom=field_edge, fn() {  })
      |> ignore
    }
    None => ()
  }
}

///|
/// Where the line of how far it has come lies: at the capsule's left and foot.
let field_edge : Double = 0.0

///|
// kept across runs: a value (no field of it changes)
let bar_field_line : @ui.Style = @ui.css("h=S0_5")

///|
/// With a key at its end: its words' room the rest, the key's own after it, the capsule's right its own.
// kept across runs: a value (no field of it changes)
let bar_field_ended : @ui.Style = @ui.css("pr=S0 gap=S0")

///|
// kept across runs: a value (no field of it changes)
let bar_field_words : @ui.Style = @ui.css("row w=Full h=Full gap=S1_5 align=ACenter")

///|
/// The key at its end: in a press's room across, at its right 4 in, so its icon stands as far in from the capsule's
/// end as the place's icon from its start (12).
// kept across runs: a value (no field of it changes)
let bar_field_end : @ui.Style = @ui.css("row h=Full pr=S1 align=ACenter justify=JEnd")

///|
// kept across runs: a value (no field of it changes)
let bar_field_room : @ui.Style = @ui.style(w=Full, min_w=Fixed(bar_field_least), px=S1)

///|
/// The least the place's room is wide before what beside it that may leave the bar does: its capsule 160 (as the find
/// field's least, find.mbt), 4 either side of it.
let bar_field_least : Double = 168.0

///|
// kept across runs: a value (no field of it changes)
let bar_field_box : @ui.Style = @ui.css("row w=Full radius=Full bg=Faint px=S3 gap=S1_5 align=ACenter clip")

///|
// kept across runs: a value (no field of it changes)
let bar_field_editing : @ui.Style = bar_field_box.then(@ui.css("bg=Card border=B1_5 border_color=A(Accent,O50)"))
