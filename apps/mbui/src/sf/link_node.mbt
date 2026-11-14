// An inline navigation or action link as a node of the window's tree: Link ink at rest, underlined under the hand,
// with an optional leading icon or trailing disclosure chevron so clickable text never blends into static labels.

///|
/// An inline link in `parent`: `words` in `style` (default Meta + Link, single line) and `ink` (default theme's link
/// blue), underlined under the hand while active (`on`), optional leading `icon` and trailing `chevron-right` in `ink`.
/// `press` runs when pressed while `on`. Returns the link node.
#callsite(autofill(loc))
pub fn link_node(
  parent : @view.View,
  words : () -> String,
  press : () -> Unit,
  icon? : String = "",
  chevron? : Bool = false,
  style? : () -> @ui.TextStyle = fn() { link_words },
  ink? : () -> Int64 = fn() { theme().p.blue },
  on? : () -> Bool = fn() { true },
  shrink? : Double = 0.0,
  role? : @view.Role = Button,
  loc~ : SourceLoc,
) -> @view.View {
  link_made(loc~, parent, words, fn(_) { press() }, icon, chevron, style, ink, on, shrink, role)
}

///|
/// link_node's link that opens what goes beside it (a popover or detail panel): `open` given the link node itself as
/// it is pressed.
#callsite(autofill(loc))
pub fn link_opens_node(
  parent : @view.View,
  words : () -> String,
  open : (@view.View) -> Unit,
  icon? : String = "",
  chevron? : Bool = false,
  style? : () -> @ui.TextStyle = fn() { link_words },
  ink? : () -> Int64 = fn() { theme().p.blue },
  on? : () -> Bool = fn() { true },
  shrink? : Double = 0.0,
  role? : @view.Role = Button,
  loc~ : SourceLoc,
) -> @view.View {
  link_made(loc~, parent, words, open, icon, chevron, style, ink, on, shrink, role)
}

///|
#callsite(autofill(loc))
fn link_made(
  parent : @view.View,
  words : () -> String,
  press : (@view.View) -> Unit,
  icon : String,
  chevron : Bool,
  style : () -> @ui.TextStyle,
  ink : () -> Int64,
  on : () -> Bool,
  shrink : Double,
  role : @view.Role,
  loc~ : SourceLoc,
) -> @view.View {
  parent.box(made_for=loc, fn(b) {
    style_node(b, fn() { link_box }, in_row=true)
    b.shrink(Is(shrink)) |> ignore
    presses_node(b, fn() { press(b) }, on~)
    b.says(By(fn() { Some(@view.said(role, label=words())) })) |> ignore
    if icon != "" {
      icon_node(b, icon, link_icon, By(ink)) |> ignore
    }
    b.box(fn(w) {
      w
      .words_runs(By(fn() { [@ui.span(words(), underline=on() && lit_node(b))] }))
      .words_look(By(fn() { @ui.style_words(style()) }))
      .ink(By(fn() { @ui.style_ink(style()) }))
      |> ignore
    })
    |> ignore
    if chevron {
      icon_node(b, "chevron-right", link_icon, By(ink)) |> ignore
    }
  })
}

///|
let link_icon : Double = 12.0

///|
// kept across runs: a value (no field of it changes)
let link_box : @ui.Style = @ui.css("row gap=S0_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let link_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Link, wrap=false)
