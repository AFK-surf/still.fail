// A round button floating over a page's list (sfpages' float_button, chatToBottom: the way to a chat's newest) as a
// node of the window's tree, made once: 32 high and round, a line round it on the canvas, a shadow under it, its icon
// and the words beside it it says; the hover ground under the hand; pressed in 44 by 44 round it at the least.

///|
/// The round button in `parent` showing icon `icon` and, where `count` says any, those words after it; named `label`
/// (read out a button, its tip in `tips` on its top, `shortcut`'s keys after it); `press` done as it is pressed. Pressed
/// in its room (`float_button_reach` round what is drawn). The node: its room.
#callsite(autofill(loc))
pub fn float_button_node(
  parent : @view.View,
  icon : String,
  label : () -> String,
  press : () -> Unit,
  count? : () -> String = fn() { "" },
  tips? : TipLayer,
  shortcut? : String = "",
  loc~ : SourceLoc,
) -> @view.View {
  @headless.button(made_for=loc, parent, label, fn(_) { press() }, fn(o, _) {
    let room = float_button_reach
    o
    .padding(Is((room, room, room, room)))
    .min_width(Is(Some(float_button_side + 2.0 * room)))
    |> ignore
    o.box(fn(b) {
      style_node(b, fn() { if lit_node(o) { float_button_lit } else { float_button_look } })
      icon_node(b, icon, float_button_icon, By(fn() { theme().p.text })) |> ignore
      b.show(fn() { count() != "" }, fn(w) { words_node(w, count, fn() { float_button_count }) |> ignore })
    })
    |> ignore
    match tips {
      Some(t) => tip_node(t, o, label, side=Top, shortcut~) |> ignore
      None => ()
    }
  })
}

///|
/// How high the button is drawn (float_side), its icon, and the room round it it is pressed in too (44 in all).
let float_button_side : Double = 32.0

///|
let float_button_icon : Double = 16.0

///|
pub let float_button_reach : Double = 6.0

///|
/// The button (float_button's): 32 high, round, a line round it on the canvas, a shadow under it; its count beside its
/// arrow; the hover ground under the hand.
// kept across runs: a value (no field of it changes)
let float_button_look : @ui.Style = @ui.css((
  #|row h=S8 min_w=S8 px=S2 gap=S1 radius=Full border=B1 border_color=Line bg=Surface shadow=Md align=ACenter justify=JCenter
))

///|
// kept across runs: a value (no field of it changes)
let float_button_lit : @ui.Style = float_button_look.then(@ui.css("bg=Over(Surface, Hover)"))

///|
// kept across runs: a value (no field of it changes)
let float_button_count : @ui.TextStyle = @ui.text_style(size=Ui, weight=Medium, color=Fg, wrap=false)
