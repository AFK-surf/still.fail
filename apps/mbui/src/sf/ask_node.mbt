// A question (ask_centred's: the library's dialog with its line) as nodes of the window's tree: the presenters' dialog
// layer (dialog_layer_node: a press outside it closes it, as a dialog's does), its panel as dialog draws it (dialog_w wide
// at most, the window less dialog_margin, no taller than it less dialog_room; 24 in, a line round it, dialog_r round,
// the panel's ground and shadow; its title's row, then what it holds 18 under it, scrolling in itself where the panel
// is short of room (View::scrolls, as dialog's capped body), then its cancel and its action at its foot's end); its line the library's
// field (input) in an old view hosted in it, the way there: no editor of the tree's yet; its hint under it, its words.
// Its action can be pressed while the line, trimmed, differs from what it was given and is not empty (unless an empty
// one says something: `empty`), told as the line changes (its Field's words, a signal); said by its action or Enter in
// the field, once, after it has closed. Its field the keyboard's as it opens; closed, the focus back where it was.

///|
/// A question in `parent` while `open()` (going over pop_out_ms once not): `title`, its field (`line`, at first
/// `value`; `placeholder` while empty, as dots where `secret`), `hint` under it ("" none), the library's cancel and
/// `action`. `key`: what its old view and its field are named by (the presented's). `say` with the line, trimmed, once;
/// `cancel` as it is closed unsaid. `shown`, `gone`: as dialog_layer_node's.
pub fn ask_node(
  parent : @view.View,
  key : String,
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
  let words = fn() { line.text().trim(chars=" \t\n").to_string() }
  let can = fn() { ask_can(words(), value, empty) }
  let said = Ref(false)
  // (its field given the keyboard's focus as it opens, once, while it is open: then the person's; ask_centred's
  // focus_once, this opening's own)
  let focused = Ref(false)
  let go = fn() {
    if !said.val && @signals.untracked(can) {
      said.val = true
      say(@signals.untracked(words))
    }
  }
  dialog_layer_node(parent, open, cancel, outside=true, shown~, gone~, dims~, covered~, fn(across, layer, look, veil) {
    let theme = fn() { @ui.tree_theme() }
    let first : Ref[@view.View?] = Ref(None)
    across.box(fn(d) {
      d
      .width(By(fn() { Some(dmin(dialog_w, layer.window().0 - dialog_margin)) }))
      // (no taller than the window leaves it, dialog_room: what it holds scrolls in itself past that, its title and its
      // buttons staying)
      .max_height(By(fn() { Some(dmax(0.0, layer.window().1 - dialog_room)) }))
      // (dialog_box: 24 over its title; 24 in at its sides, each part's own, what it holds scrolling out to them)
      .padding(Is((0.0, dialog_pad, 0.0, 0.0)))
      .radius(Is(dialog_r))
      .ground(By(fn() { panel_ground() }))
      .edge(By(fn() { (1.0, theme().color(Line)) }))
      .shadow(By(fn() { (dialog_shadow, dialog_shadow_y, library_theme().p.shadow) }))
      .alpha(By(fn() { look().alpha }))
      .scale(By(fn() { look().sx }))
      .offset(By(fn() { (look().dx, look().dy) }))
      // (a press on it its own: not outside it)
      .presses(Is(true))
      .on_press(fn() {  })
      .says(Is(Some(@view.said(Dialog, label=title))))
      |> ignore
      let words_in = fn() { look().words }
      // (its title's row: dialog_head's, 1 under its padding's top, as tall as a close button's room at least)
      d.box(fn(h) {
        h
        .padding(Is((dialog_pad, dialog_head_over, dialog_head_end + dialog_pad, 0.0)))
        .min_height(Is(Some(dialog_close)))
        .lines_up(Is(Some(Middle)))
        .row(Is(true))
        |> ignore
        h.box(fn(t) {
          t
          .words(Is(title), look=toast_words_look(Heading, Font, 600, true))
          .ink(By(fn() { theme().color(Fg) }))
          .alpha(By(words_in))
          |> ignore
        })
        |> ignore
      })
      |> ignore
      // (what it holds: 18 under its title, 16 apart; its field an old view's, its hint under it; scrolling in itself
      // where the panel is short of room, out to its sides: dialog's capped body)
      d.box(fn(body) {
        body.scrolls(@view.Scroll::new(), slop=@ui.touch_slop(), bar=@ui.tree_scroll_bar(), fn(b) {
        b.padding(Is((dialog_pad, @ui.Space::px(S4_5), dialog_pad, 0.0))).gap(Is(@ui.Space::px(S4))) |> ignore
        @ui.old(b, fn(c) {
          let fid = c.id(key + "/line")
          let submitted = Ref(false)
          let held = c.box(style=ask_field_at, fn() {
            submitted.val = input(c, key + "/line", placeholder~, secret~, field=line).submitted
          })
          // (its words as far in as the panel's, its ground and edge with the panel: the old dialog's look's words,
          // Look's `words`, on what its field draws, as kit.dialog's c.look put them)
          let l = look()
          c.look(held, { alpha: 1.0, dx: 0.0, dy: 0.0, sx: 1.0, sy: 1.0, ox: 0.5, oy: 0.5, rot: 0.0, circle: 0.0, words: l.words })
          if !focused.val && @signals.untracked(open) {
            if c.has_focus(fid) {
              focused.val = true
            } else {
              c.focus_editor(key + "/line")
            }
          }
          if submitted.val {
            c.tell(key + "/said", go)
          }
        })
        // (as tall as the one-line field it holds, the theme's controls' (input_height): an old view hosted says
        // nothing of its height, its box cut to what the tree gives it)
        .height(Is(Some(input_height())))
        |> ignore
        if hint != "" {
          b.box(fn(t) {
            t.words(Is(hint), look=toast_words_look(Meta, L5, 400, true)).ink(By(fn() { theme().color(Muted) })).alpha(By(words_in)) |> ignore
          })
          |> ignore
        }
        })
        |> ignore
      })
      |> ignore
      // (its foot: its buttons at its end, 8 apart, 24 over them; as far from its foot and sides as its corner has them)
      d.box(fn(f) {
        let at = capsule_in(dialog_r, button_height())
        f.row(Is(true)).lines_up(Is(Some(Middle))).gap(Is(@ui.Space::px(S2))).padding(Is((at, @ui.Space::px(S6), at, at))) |> ignore
        f.box(fn(s) { s.grow(Is(1.0)) |> ignore }) |> ignore
        let no = button_node(f, fn() { t("common.cancel") }, cancel, tone=Ghost, words_in~)
        button_node(f, fn() { action }, go, tone=Primary, disabled=fn() { !can() }, words_in~) |> ignore
        first.val = Some(no)
      })
      |> ignore
      // (another dialog over it: dimmed over all of itself, its corners its own)
      d.box(fn(v) { v.over(Is(true)).radius(Is(dialog_r)).ground(By(veil)) |> ignore }) |> ignore
    })
    |> ignore
    first.val.unwrap()
  })
}

///|
/// Where a question's field stands in what it holds: as wide as it.
// kept across runs: a value (no field of it changes)
let ask_field_at : @ui.Style = @ui.css("w=Full")
