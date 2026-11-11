// The library's lines to type in as nodes of the window's tree (input's and textarea's, their made-once form): ui's
// field (the tree's editor: its words, the input method, what is picked, undo, the focus, Enter) in a frame of the
// library's look, the frame's line the field's hover grey while the field is pointed at or written in, faded while
// it is disabled. What it holds is the Field it is given (what reads it follows its words, what writes it is shown);
// what changes it (Enter, a key, its words) told by callbacks at that input's moment; let go with its node.

///|
/// A line to type in in `parent` (input's look: a capsule as tall as the theme's controls, `small` as high as a small
/// panel's rows with a mouse, its ends round; 16 in, the strong grey's line, on the surface, its words the
/// body's), editing `field`: `placeholder` while empty (`shorter` ways of saying it where it has less room), as
/// dots where `secret`; Enter gives its words to `submitted`, once, at that key's moment; `leaves`: the keys it leaves
/// to what it offers as it is typed in; `edited`: its words as the person's edit changes them (ui's field's), never
/// as the app puts words in it; `placeholder_by`: its placeholder as it is now, followed (in place of
/// `placeholder`); `label`: what a screen reader calls it, where no placeholder does (it shows none). While
/// `disabled()`, faded, taking no press nor the focus (losing it then). `solid`: on a card's ground (input's
/// `solid`, field_solid): on the canvas's ground, its line the canvas's too, the field's hover grey while it is pointed
/// at or written in. `end`: what stands in the capsule after what is typed (a search's count), made in a box at its
/// end; `lead`: what stands in it before what is typed (a search's mark), made in a box at its start. `card_words`:
/// in a card's foot corners (over its buttons there), its words where the card's begin (button_node's,
/// card_foot_words's: as far in at its sides as that corner leaves a button's). The field's node (what the focus is
/// given to).
pub fn input_node(
  parent : @view.View,
  field : @ui.Field,
  placeholder? : String = "",
  label? : String = "",
  shorter? : Array[String] = [],
  secret? : Bool = false,
  placeholder_by? : () -> String,
  disabled? : () -> Bool = fn() { false },
  small? : Bool = false,
  solid? : Bool = false,
  leaves? : Array[Int] = [],
  submitted? : (String) -> Unit = fn(_) {  },
  edited? : (String) -> Unit,
  end? : (@view.View) -> Unit,
  lead? : (@view.View) -> Unit,
  card_words? : Bool = false,
) -> @view.View {
  let line = @signals.untracked(fn() { theme().t.body_line })
  let x = if card_words { card_foot_words_in(button_height()) } else { @ui.Space::px(S4) }
  field_frame(parent, disabled, row=true, solid~, fn(f) {
    f
    .padding(Is((x, @ui.Space::px(S1_5), x, @ui.Space::px(S1_5))))
    |> ignore
    if small {
      // (input_box_small: a small panel's row's height, a mouse's (menu_row_min), its ends round)
      f.height(Is(Some(menu_row_min))).radius(Is(1.0e6)) |> ignore
    } else {
      f.min_height(By(fn() { Some(theme().control_h) })).radius(By(fn() { field_round() })) |> ignore
    }
    // (what stands before what is typed, kept whole, as far from it as a row's parts are: its start's room the field's
    // own)
    match lead {
      Some(l) => f.box(fn(b) { b.shrink(Is(0.0)).margin(Is((0.0, 0.0, field_lead_gap, 0.0))) |> ignore; l(b) }) |> ignore
      None => ()
    }
    let typed = @ui.field(
      f,
      field,
      placeholder~,
      placeholder_by?,
      shorter~,
      line~,
      max_lines=1,
      enter_sends=true,
      label~,
      secret~,
      leaves~,
      submitted~,
      edited?,
      size_by=fn() { theme().t.body },
      colors_by=fn() {
        let th = @ui.tree_theme()
        (th.fg, th.subtle, th.accent)
      },
    )
    .grow(Is(1.0))
    .basis(Is(Some(0.0)))
    .shrink(Is(1.0))
    // (what stands at its end, after what is typed, kept whole)
    match end {
      Some(e) => f.box(fn(b) { b.shrink(Is(0.0)) |> ignore; e(b) }) |> ignore
      None => ()
    }
    typed
  })
}

///|
/// Lines to type in in `parent` (textarea's look: a one-line field grown taller, round as its ends are, or `corner`
/// round where said; 16 in and 8 under its top, the strong grey's line, on the surface; its words 14 on lines 1.6 of
/// them), editing `field`: at least `rows` lines high, growing to `most`, its words scrolling in it past them;
/// `placeholder` while empty (`placeholder_by`: as it is now, followed; `label`: as input_node's); Enter a new line;
/// `edited`: as input_node's.
/// While `disabled()`, as input_node's. `solid`, `card_words`: as input_node's. The field's node.
pub fn textarea_node(
  parent : @view.View,
  field : @ui.Field,
  rows? : Int = 3,
  most? : Int = 16,
  placeholder? : String = "",
  label? : String = "",
  corner? : Double,
  placeholder_by? : () -> String,
  disabled? : () -> Bool = fn() { false },
  edited? : (String) -> Unit,
  solid? : Bool = false,
  card_words? : Bool = false,
) -> @view.View {
  let x = if card_words { card_foot_words_in(button_height()) } else { @ui.Space::px(S4) }
  field_frame(parent, disabled, row=false, solid~, fn(f) {
    f
    .padding(Is((x, @ui.Space::px(S2), x, @ui.Space::px(S2))))
    .min_height(Is(Some(rows.to_double() * textarea_line + textarea_in)))
    |> ignore
    match corner {
      Some(k) => f.radius(Is(k)) |> ignore
      None => f.radius(By(fn() { field_round() })) |> ignore
    }
    @ui.field(
      f,
      field,
      placeholder~,
      placeholder_by?,
      font_size=input_size,
      line=textarea_line,
      label~,
      min_lines=rows,
      max_lines=most,
      enter_sends=false,
      edited?,
      colors_by=fn() {
        let p = theme().p
        (p.text, p.subtle, p.accent)
      },
    )
  })
}

///|
/// A line to type in's frame in `parent` (a row where `row`, else a column): on the surface, a line round it, the
/// field's hover grey where what `body` makes in it (its field, the node it gives back) is written in, or pointed at
/// (a mouse's pointer on it or its field, nothing over it there; a finger pressing its field: Ctx::lit's); faded to
/// O55 (input_box's `disabled`) over dur_ms while `disabled()`, its field then taking no press nor the focus. `solid`:
/// on the canvas's ground, its line the canvas's but where it is pointed at or written in (field_solid). The field's
/// node.
#callsite(autofill(loc))
fn field_frame(
  parent : @view.View,
  disabled : () -> Bool,
  row~ : Bool,
  solid? : Bool = false,
  body : (@view.View) -> @view.View,
  loc~ : SourceLoc,
) -> @view.View {
  let made : Ref[@view.View?] = Ref(None)
  parent.box(made_for=loc, fn(f) {
    let live = fn() { !disabled() }
    let seen = EdgeWay::new(if @signals.untracked(disabled) { field_disabled_alpha } else { 1.0 })
    f.reacts(disabled, fn(off) { seen.go(f, if off { field_disabled_alpha } else { 1.0 }, dur_ms) })
    f
    .row(Is(row))
    .lines_up(Is(if row { Some(Middle) } else { None }))
    .ground(By(fn() { @ui.tree_theme().color(if solid { Bg } else { Surface }) }))
    .alpha(By(fn() { seen.shown(f) }))
    // (pointed at as a whole, as the old frame's box is by its id: lit with the pointer on its padding too, a press
    // there passing through to what is under it, as there)
    .points(Is(true))
    |> ignore
    let v = body(f)
    // (pointed at as the old frame lit its box: a mouse's on it or its field, nothing over it there; a finger's
    // pressing its field; written in)
    let hot = fn() {
      v.focused() ||
      (match @ui.pointing() {
        Mouse => f.pointed_in()
        Finger => v.pressed()
      })
    }
    f.edge(By(fn() { (1.0, @ui.tree_theme().color(if hot() { FieldHover } else if solid { Bg } else { Border })) }))
    |> ignore
    // (disabled: no press nor the focus its field's, said over what the field says of itself)
    v.presses(By(live)).focusable(By(live), keys=0) |> ignore
    made.val = Some(v)
  })
  |> ignore
  made.val.unwrap()
}

///|
/// How far what stands before a field's words is from them (input_node's `lead`).
let field_lead_gap : Double = 8.0

///|
/// How far a disabled field is seen (input_box's `disabled{opacity=O55}`).
let field_disabled_alpha : Double = 0.55

///|
/// A field (field's, as nodes) in `parent`: its `label` (13, 500) over what `body` makes in it (the input), 6 apart,
/// what `aside` makes at its head's end where it is given; under it what is wrong (`error`, 12 red) or else a `hint`
/// (12, muted), as each says it now (labelled_field_node's); on a wide page not in a panel as wide as what is typed in it
/// needs (field_box_wide), else as wide as where it is.
#callsite(autofill(loc))
pub fn field_node(
  parent : @view.View,
  label : () -> String,
  body : (@view.View) -> Unit,
  aside? : (@view.View) -> Unit,
  hint? : () -> String = fn() { "" },
  error? : () -> String = fn() { "" },
  loc~ : SourceLoc,
) -> Unit {
  parent.box(made_for=loc, fn(f) {
    // (in a panel's body: lent where it is, panel_in_lent)
    let wide_page = look_node(f) is Wide && f.lent(panel_in_lent) is None
    style_node(f, fn() { if wide_page { field_box_wide } else { field_box } })
    f.box(fn(top) {
      style_node(top, fn() { field_top })
      words_node(top, label, fn() { field_label }) |> ignore
      // (at the row's end, what is left of it before it: field_top's JBetween)
      match aside {
        Some(a) =>
          top.box(fn(e) {
            e.grow(Is(1.0)).row(Is(true)).lies_along(Is(End)) |> ignore
            a(e)
          })
          |> ignore
        None => ()
      }
    })
    |> ignore
    body(f)
    f.show(fn() { error() != "" }, fn(w) { words_node(w, error, fn() { field_error }) |> ignore })
    f.show(fn() { error() == "" && hint() != "" }, fn(w) { words_node(w, hint, fn() { field_hint }) |> ignore })
  })
  |> ignore
}
