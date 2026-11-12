// A question (the library's dialog with its line) as nodes of the window's tree: the presenters' dialog
// layer (dialog_layer_node: a press outside it closes it, as a dialog's does), its panel as dialog draws it (dialog_w wide
// at most, the window less dialog_margin, no taller than it less dialog_room; 24 in, a line round it, dialog_r round,
// the panel's ground and shadow; its title's row, then what it holds 18 under it, scrolling in itself where the panel
// is short of room (View::scrolls, as dialog's capped body), then its cancel and its action at its foot's end); its line the library's
// (input_node: the tree's editor in the line's look); its hint under it, its words.
// Its action can be pressed while the line, trimmed, differs from what it was given and is not empty (unless an empty
// one says something: `empty`), told as the line changes (its Field's words, a signal); said by its action or Enter in
// the field, once, after it has closed. Its field the keyboard's as it opens; closed, the focus back where it was.

///|
/// A question in `parent` while `open()` (going over pop_out_ms once not): `title`, its field (`line`, at first
/// `value`; `placeholder` while empty, as dots where `secret`), `hint` under it ("" none), the library's cancel and
/// `action`. `say` with the line, trimmed, once;
/// `cancel` as it is closed unsaid. `shown`, `gone`: as dialog_layer_node's.
pub fn ask_node(
  parent : @view.View,
  open : () -> Bool,
  title : String,
  line : @ui.Field,
  value : String,
  placeholder : String,
  action : String,
  hint : String,
  secret : Bool,
  empty : Bool,
  cancel : () -> Unit,
  say : (String) -> Unit,
  shown? : () -> Unit = fn() {  },
  gone? : () -> Unit = fn() {  },
  dims? : () -> Bool = fn() { true },
  covered? : () -> Bool = fn() { false },
) -> Unit {
  // (the line as it is now, trimmed: followed as it changes)
  let words = fn() { line.text().trim(chars=" \t\n").to_owned() }
  let can = fn() { ask_can(words(), value, empty) }
  let said = Ref(false)
  let go = fn() {
    if !said.val && @signals.untracked(can) {
      said.val = true
      say(@signals.untracked(words))
    }
  }
  dialog_layer_node(parent, open, cancel, outside=true, shown~, gone~, dims~, covered~, fn(across, layer, look, veil) {
    let theme = fn() { @ui.tree_theme() }
    // (its field: given the keyboard's focus as it opens, back to what had it as it goes)
    let field : Ref[@view.View?] = Ref(None)
    across.box(fn(d) {
      d
      .width(By(fn() { Some(dmin(dialog_w, over_room(layer).0 - dialog_margin)) }))
      // (no taller than the window leaves it, dialog_room: what it holds scrolls in itself past that, its title and its
      // buttons staying)
      .max_height(By(fn() { Some(dmax(0.0, over_room(layer).1 - dialog_room)) }))
      // (dialog_box: 24 over its title; 24 in at its sides, each part's own, what it holds scrolling out to them)
      .padding(Is((0.0, dialog_pad, 0.0, 0.0)))
      .radius(Is(dialog_r))
      .ground(By(fn() { panel_ground() }))
      .edge(By(fn() { (1.0, theme().color(Line)) }))
      .shadow(By(fn() { (dialog_shadow, dialog_shadow_y, library_theme().p.shadow) }))
      .alpha(By(fn() { look().alpha }))
      .scale(By(fn() { look().sx }))
      .offset(By(fn() { (look().dx, look().dy) }))
      .says(Is(Some(@view.said(Dialog, label=title))))
      // (a press on it its own: not outside it)
      |> ground_node
      |> ignore
      let words_in = fn() { look().words }
      // (its title's row: dialog_head's, 1 under its padding's top, as tall as a close button's room at least)
      d.box(fn(h) {
        h
        // (its title on the panel's words' line, as every dialog's: panel_words)
        .padding(Is((panel_words, dialog_head_over, dialog_head_end + dialog_pad, 0.0)))
        .min_height(Is(Some(dialog_close)))
        .lines_up(Is(Some(Middle)))
        .row(Is(true))
        // (all it holds as far in as its look says, past its own ground, edge and shadow: its title's row, what it
        // holds, its foot, each the same, Look's `words` as a surface's are)
        .alpha(By(words_in))
        |> ignore
        h.box(fn(t) {
          t
          .words(Is(title), look=toast_words_look(Heading, Font, 600, true))
          .ink(By(fn() { theme().color(Fg) }))
          |> ignore
        })
        |> ignore
      })
      |> ignore
      // (what it holds: 18 under its title, 16 apart; its field an old view's, its hint under it; scrolling in itself
      // where the panel is short of room, out to its sides: dialog's capped body)
      d.box(fn(body) {
        body.alpha(By(words_in)) |> ignore
        body.scrolls(@view.Scroll::new(), slop=@ui.touch_slop(), bar=@ui.tree_scroll_bar(), fn(b) {
        b.padding(Is((panel_words, @ui.Space::px(S4_5), panel_words, 0.0))).gap(Is(@ui.Space::px(S4))) |> ignore
        // (its field the library's line, as wide as what it holds: Enter says it, at that key's moment; read out by the
        // question's title where it shows no placeholder)
        field.val = Some(
          input_node(b, line, placeholder~, label=if placeholder == "" { title } else { "" }, secret~, submitted=fn(_) {
            go()
          }),
        )
        if hint != "" {
          b.box(fn(t) {
            t.words(Is(hint), look=toast_words_look(Meta, L5, 400, true)).ink(By(fn() { theme().color(Muted) })) |> ignore
          })
          |> ignore
        }
        })
        |> ignore
      })
      |> ignore
      // (its foot: its buttons at its end, 8 apart, 24 over them; as far from its foot and sides as its corner has them)
      d.box(fn(f) {
        let at = @ui.capsule_in(dialog_r, button_height())
        f.row(Is(true)).lines_up(Is(Some(Middle))).gap(Is(@ui.Space::px(S2))).padding(Is((at, @ui.Space::px(S6), at, at))).alpha(By(words_in)) |> ignore
        f.box(fn(s) { s.grow(Is(1.0)) |> ignore }) |> ignore
        button_node(f, fn() { t("common.cancel") }, cancel, tone=Ghost) |> ignore
        button_node(f, fn() { action }, go, tone=Primary, disabled=fn() { !can() }) |> ignore
      })
      |> ignore
      // (another dialog over it: dimmed over all of itself, its corners its own)
      d.box(fn(v) { v.over(Is(true)).radius(Is(dialog_r)).ground(By(veil)) |> ignore }) |> ignore
    })
    |> ignore
    field.val.unwrap()
  })
}
