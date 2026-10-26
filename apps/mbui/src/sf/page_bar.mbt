// A page's bar of keys over what it shows (web Preview.tsx PreviewBar, Preview.css.ts previewBar, previewAddress; the
// phone's Preview.kt PreviewBar alike): a row of round keys and one capsule where it is, the same on every screen. Its
// room the theme's (Bars): a key's, an icon's, the capsule's; a finger reaches a key from round it all the same
// (mbui's press_reach), so none is drawn larger for a phone.

///|
/// The bar: 8 in, 6 over and under, its keys 2 apart, in their middle.
pub fn page_bar(c : @ui.Ctx, body : () -> Unit) -> Unit {
  c.box(style=page_bar_box, body) |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let page_bar_box : @ui.Style = @ui.css("row w=Full px=S2 py=S1_5 gap=S0_5 align=ACenter")

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
/// Where the page is (previewAddress): one capsule taking what the bar leaves, 4 in from what is beside it, its words
/// 12 in and 6 apart, on the chip's ground; typed in, on the card's with the focus's ring (`editing`). `id`: pressed
/// anywhere, what its page says to do (typing in it).
pub fn bar_field(c : @ui.Ctx, id : Int, editing : Bool, body : () -> Unit) -> Unit {
  let b = theme().bars
  c.box(style=bar_field_room, fn() {
    c.box(style=(if editing { bar_field_editing } else { bar_field_box }).then(@ui.style(h=Fixed(b.field))), id~, body)
    |> ignore
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let bar_field_room : @ui.Style = @ui.css("w=Full px=S1")

///|
// kept across runs: a value (no field of it changes)
let bar_field_box : @ui.Style = @ui.css("row w=Full radius=Full bg=Faint px=S3 gap=S1_5 align=ACenter clip")

///|
// kept across runs: a value (no field of it changes)
let bar_field_editing : @ui.Style = bar_field_box.then(@ui.css("bg=Card border=B1_5 border_color=A(Accent,O50)"))
