// One line asked of the viewer on an option's ground (ask_line_card's: what a chat needs, at its end, with 忽略), its
// mark where an option's number is, and the quiet words ending it that are pressed (ask_line_button's), as nodes of the
// window's tree, made once; and an answered card's result that opens its history (ask_history_trigger's). Their
// measures, grounds and inks the old ones' (parts.mbt, ask.mbt), what the hand does to them eased over dur_ms from the
// moment it did it.

///|
/// One line asked of the viewer in `parent` (ask_line_card's, as nodes): a row laid as an option's alone, pad_in in on
/// every side, an option row's corner, on the text at 5%; a column instead where the system lays out the app's tabs
/// itself (the native bars: @sf.native_on) and where it is is `narrow` (as its caller's width says), at once as that
/// changes (an arrangement, not a coming or a going). `body` makes what it holds, told whether it is a column. The
/// node.
#callsite(autofill(loc))
pub fn ask_line_card_node(
  parent : @view.View,
  narrow : () -> Bool,
  body : (@view.View, Bool) -> Unit,
  loc~ : SourceLoc,
) -> @view.View {
  parent.box(made_for=loc, fn(holder) {
    holder.pick(at_once=true, fn() { native_on() && narrow() }, fn(v, column) {
      style_node(v, fn() {
        (if column { ask_line_column } else { ask_line_row })
        .then(ask_line_ground)
        .then(@ui.style(p=room(option_type().pad_in)))
      })
      body(v, column)
    })
  })
}

///|
/// What leads ask_line_card_node's words (ask_line_mark's) in `parent`: a column as wide and as high as an option's
/// disc, `body` in its middle. The node.
#callsite(autofill(loc))
pub fn ask_line_mark_node(parent : @view.View, body : (@view.View) -> Unit, loc~ : SourceLoc) -> @view.View {
  parent.box(made_for=loc, fn(v) {
    style_node(v, fn() { ask_line_mark() }, in_row=true)
    body(v)
  })
}

///|
/// Words to press ending ask_line_card_node's row (ask_line_button's, as nodes: 忽略 ending what a chat needs) in
/// `parent`: `label` quiet, the line's own ink under the hand or the finger (dur_ms, eased out), its room a button's
/// reaching out to the row's end corner, its ground then concentric with it; its words as far in as the row's start
/// mark `mark` wide is from its start. While `disabled`: faded to 45%, taking no press. `press` done as it is pressed.
/// Read out a button named `label`. The node.
#callsite(autofill(loc))
pub fn ask_line_button_node(
  parent : @view.View,
  label : () -> String,
  mark : Double,
  disabled : () -> Bool,
  press : () -> Unit,
  loc~ : SourceLoc,
) -> @view.View {
  let live = fn() { !disabled() }
  @headless.button(made_for=loc, parent, label, fn(_) { press() }, disabled~, fn(b, _) {
    style_node(b, fn() {
      let h = button_height()
      let out = option_type().pad_in - @ui.capsule_in(option_row_corner, h)
      let side = (ask_line_disc() - mark) / 2.0
      @ui.style(
        row=true,
        h=Fixed(h),
        px=room(out + side),
        mt=room(-out),
        mb=room(-out),
        mr=room(-out),
        radius=Full,
        align=ACenter,
      )
    })
    let on = fn() { live() && (lit_node(b) || b.pressed()) }
    let lit = EdgeWay::new(if @signals.untracked(on) { 1.0 } else { 0.0 })
    let seen = EdgeWay::new(if @signals.untracked(disabled) { 0.45 } else { 1.0 })
    b.reacts(on, fn(o) { lit.go(b, if o { 1.0 } else { 0.0 }, dur_ms) })
    b.reacts(disabled, fn(off) { seen.go(b, if off { 0.45 } else { 1.0 }, dur_ms) })
    b
    .ground(By(fn() { alpha(theme().p.hover, lit.shown(b)) }))
    .alpha(By(fn() { seen.shown(b) }))
    |> ignore
    b.box(fn(w) {
      let words = fn() { ask_line_words(theme().chat_list.state_quiet.then(ask_line_button_words)) }
      w
      .words(By(label))
      .words_look(By(fn() { @ui.style_words(words()) }))
      .ink(By(fn() {
        let p = theme().p
        mix(p.text, lit.shown(w), p.muted)
      }))
      |> ignore
    })
    |> ignore
  })
}

///|
/// An answered card's result in `parent` (ask_history_trigger's, as nodes): `words` in `style`, a small chevron after
/// them centred on their first line (`line`: its height as said, at the system's size of words as it is drawn),
/// muted, the text's ink under the hand or with the keyboard's focus (dur_ms, eased out); pressed, `open` given it (what
/// its history opens from). Read out a button: its words and 详情. The node.
#callsite(autofill(loc))
pub fn ask_history_trigger_node(
  parent : @view.View,
  words : () -> Array[@ui.Run],
  style : () -> @ui.TextStyle,
  line : Double,
  open : (@view.View) -> Unit,
  loc~ : SourceLoc,
) -> @view.View {
  @headless.button(
    made_for=loc,
    parent,
    fn() { words().map(fn(w) { w.text }).join("") + " · " + t("web-main.history.details") },
    open,
    fn(b, _) {
      style_node(b, fn() { ask_history_line })
      let on = fn() { lit_node(b) || b.focus_shown() }
      let lit = EdgeWay::new(if @signals.untracked(on) { 1.0 } else { 0.0 })
      b.reacts(on, fn(o) { lit.go(b, if o { 1.0 } else { 0.0 }, dur_ms) })
      b.box(fn(w) {
        // (giving way to the chevron where the line has not the room for both: its words wrap, as the old row's do)
        w
        .shrink(Is(1.0))
        .min_width(Is(Some(0.0)))
        .words_runs(By(words))
        .words_look(By(fn() { @ui.style_words(style()) }))
        .ink(By(fn() { @ui.style_ink(style()) }))
        |> ignore
      })
      |> ignore
      b.box(fn(m) {
        style_node(m, fn() { ask_history_mark.then(@ui.style(h=Fixed(node_sp(m, line)))) })
        icon_node(m, "chevron-right", 12.0, By(fn() {
          let p = theme().p
          mix(p.text, lit.shown(m), p.muted)
        }))
        |> ignore
      })
      |> ignore
    },
  )
}
