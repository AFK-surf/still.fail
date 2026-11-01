// A long pick of the presenters' (pick_popover's long one: the web's chooser with its search) as nodes of the window's
// tree: a modal layer over the window, nothing under it dimmed, its small panel beside what opened it (as menu_node's:
// View::beside, grown out of that side as it comes, gone at once as it closes, as the old presenter lets it go), chooser
// wide. Over its list its search, the library's field (input) in an old view hosted in it, the way there (no editor of
// the tree's yet), the keyboard's as it opens; what is typed finds by the words (pick_found: a choice's label, note
// and value), Enter in it picks the first found, none found said so (common.noMatch). Its list scrolls past
// pick_list_most (View::scrolls), each choice a row of its own as menu_item draws it (its mark or icon in a column
// before its words, its value after them, its note under them, the one chosen in the accent): pressed, chosen. Escape,
// back and a press outside close it.

///|
/// A long pick in `parent` while `open()` (let go of at once once not): `title` (what it is called), `choices`, the one
/// `chosen`, its search's field `line`, named by `key` (the presented's); beside what `anchor` makes in its layer,
/// `offset` off it, lined up `along` it. `choose` with a choice's key, once; `cancel` as it is closed unchosen.
/// `shown`, `gone`: as dialog_layer_node's.
pub fn pick_node(
  parent : @view.View,
  key : String,
  open : () -> Bool,
  anchor : (@view.View) -> @view.View,
  title : String,
  choices : Array[Choice],
  chosen : String,
  line : @ui.Field,
  along : @ui.Along,
  offset : Double,
  choose : (String) -> Unit,
  cancel : () -> Unit,
  shown? : () -> Unit = fn() {  },
  gone? : () -> Unit = fn() {  },
) -> Unit {
  parent.show(open, fn(layer) {
    shown()
    layer.owns(gone) |> ignore
    let th = theme()
    // (how far in it is, from the moment it opened)
    let way = EdgeWay::new(0.0)
    way.go(layer, 1.0, @kit.pop_ms)
    let look = fn() {
      let p = way.shown(layer)
      @kit.pop_in.at(p, p)
    }
    let words_in = fn() { look().words }
    // (what is found by the words typed, as they are now)
    let found = fn() { pick_found(choices, line.text()) }
    // (said once: the first choice, or a close)
    let said = Ref(false)
    let go = fn(k : String) {
      if !said.val {
        said.val = true
        choose(k)
      }
    }
    // (its field given the keyboard's focus as it opens, once: then the person's; pick_popover's focus_once)
    let focused = Ref(false)
    layer
    .over(Is(true))
    .modal(Is(true))
    .held_back_goes_on()
    // (a press outside its panel its own, nothing under it pressed: closing it as it goes down)
    .presses(Is(true))
    .on_drag(fn(d) {
      if d.kind == Down {
        cancel()
      }
    })
    .on_key(fn(k) {
      if k.code == @ui.key_escape {
        cancel()
        true
      } else {
        false
      }
    })
    .takes_back(fn() { cancel() })
    |> ignore
    // (what opened it, where it is drawn: what its panel goes beside)
    let at = anchor(layer)
    let reach = menu_row_reach(th.rows.pick)
    let list = @view.Scroll::new()
    layer.box(fn(p) {
      p
      .beside(at.id(), side=Bottom, along=view_along(along), offset~, padding=8.0)
      .width(Is(Some(chooser_menu_w)))
      .max_height(By(fn() { Some(dmax(0.0, layer.window().1 - 16.0)) }))
      // (small_panel: its padding; its search and rows reaching past it to stand concentric with its corners)
      // (small_panel's padding: its search and rows reaching past it at its sides and top to stand concentric with its
      // corners, its last row at its foot, menu_item's at_foot)
      .padding(Is((panel_pad - reach, panel_pad - reach, panel_pad - reach, panel_pad)))
      .radius(Is(r_menu))
      .ground(By(fn() { panel_ground() }))
      .edge(By(fn() { (1.0, library_theme().p.line) }))
      .shadow(By(fn() { (16.0, 12.0, library_theme().p.shadow) }))
      .clips(Is(true))
      .alpha(By(fn() { look().alpha }))
      .scale(By(fn() { look().sx }), about=FromBeside)
      .says(Is(Some(@view.said(Dialog, label=title))))
      // (a press on it its own: on what of it takes none, nothing, not outside it)
      .presses(Is(true))
      .on_press(fn() {  })
      |> ignore
      // (its search, a capsule in its top corners, the library's field in an old view: Enter in it picks the first
      // found)
      @ui.old(p, fn(c) {
        let fid = c.id(key + "/search")
        let submitted = Ref(false)
        let held = c.box(style=pick_search_at, fn() {
          submitted.val = input(c, key + "/search", placeholder=t("common.search"), small=true, field=line).submitted
        })
        // (its words as far in as the panel's, its ground and edge with the panel: the old popover's look's words, as
        // @kit.beside put them on what it holds)
        let l = look()
        c.look(held, { alpha: 1.0, dx: 0.0, dy: 0.0, sx: 1.0, sy: 1.0, ox: 0.5, oy: 0.5, rot: 0.0, circle: 0.0, words: l.words })
        if !focused.val && @signals.untracked(open) {
          if c.has_focus(fid) {
            focused.val = true
          } else {
            c.focus_editor(key + "/search")
          }
        }
        if submitted.val {
          match @signals.untracked(found).get(0) {
            Some(x) => c.tell(key + "/first", fn() { go(x.key) })
            None => ()
          }
        }
      })
      .height(Is(Some(menu_row_min)))
      |> ignore
      // (none found: said so)
      p.show(fn() { found().is_empty() }, fn(e) {
        e.padding(Is((@ui.Space::px(S2_5) + reach, @ui.Space::px(S2), @ui.Space::px(S2_5) + reach, @ui.Space::px(S2)))) |> ignore
        e.box(fn(w) {
          w
          .words(Is(t("common.noMatch")), look=toast_words_look(Meta, L5, 400, true))
          .ink(By(fn() { @ui.tree_theme().color(Muted) }))
          .alpha(By(words_in))
          |> ignore
        })
        |> ignore
      })
      // (its list, scrolling past its most)
      p.box(fn(l) {
        l.max_height(Is(Some(pick_list_most))) |> ignore
        l.scrolls(list, slop=@ui.touch_slop(), bar=@ui.tree_scroll_bar(), fn(b) {
          b.each(fn() { found().map(fn(x) { x.key }) }, fn(k) { k }, fn(cell, k) {
            let k = @signals.untracked(fn() { k.get() })
            match choices.iter().find_first(fn(x) { x.key == k }) {
              Some(x) => {
                // (the last found reaching into the panel's padding at its foot, as menu_item's at_foot)
                let last = fn() { found().last().map(fn(l) { l.key }) == Some(x.key) }
                pick_row_node(cell, x, x.key == chosen, fn() { go(x.key) }, words_in, last, reach)
              }
              None => ()
            }
          })
        })
        // (cut at its box while what it holds is taller than it, as @kit.in_room's held list: else what reaches past
        // it, its last row into the panel's padding, drawn whole; what it paints alone, nothing laid out by it)
        .clips(By(fn() { list.goes() }))
        // (and taking presses within its box alone then too: else its last row's reach its own, as drawn)
        .bounds_input(By(fn() { list.goes() }))
        |> ignore
      })
      |> ignore
      // (the focus its field's as it opens, given by the old view it is in; what had it given back as it goes)
      layer.focus_returns() |> ignore
    })
    |> ignore
  })
}

///|
/// A choice of a long pick's (menu_item's look) in `b`: its mark or icon in a column before its words, its value after
/// them, its note under them, in the accent where it is the one chosen; lit under the pointer or the keyboard's focus;
/// pressed, `go`.
fn pick_row_node(
  b : @view.View,
  x : Choice,
  on : Bool,
  go : () -> Unit,
  words_in : () -> Double,
  last : () -> Bool,
  reach : Double,
) -> Unit {
  let t = theme()
  let panel = x.icon != "" || x.mark is Some(_)
  let gap = if panel { panel_row_gap } else { menu_row_gap }
  let said = [x.label, x.value, x.note].filter(fn(s) { s != "" })
  b.box(fn(r) {
    r
    .row(Is(true))
    .lines_up(Is(Some(Middle)))
    .min_height(Is(Some(t.rows.pick)))
    .margin(By(fn() { (0.0, 0.0, 0.0, if last() { -reach } else { 0.0 }) }))
    .padding(Is((text_in + reach, menu_row_over, text_in + reach, menu_row_over)))
    .gap(Is(gap))
    .radius(Is(small_panel_inner(r_menu)))
    .ground(By(fn() { if r.pointed() || (r.focused() && r.focus_shown()) { library_theme().p.hover } else { 0L } }))
    .presses(Is(true))
    .focusable(Is(true))
    .on_press(go)
    .says(Is(Some(@view.said(Button, label=said.join(" ")))))
    |> ignore
    let first_line = fn(into : @view.View) {
      if panel {
        into.box(fn(col) {
          col.width(Is(Some(panel_icon_col))).lines_up(Is(Some(Middle))).alpha(By(words_in)) |> ignore
          match x.mark {
            Some(m) =>
              @ui.old(col, fn(c) { m(c, panel_icon) })
              .width(Is(Some(panel_icon)))
              .height(Is(Some(panel_icon)))
              |> ignore
            None => icon_node(col, x.icon, panel_icon, By(fn() { library_theme().p.muted })) |> ignore
          }
        })
        |> ignore
      }
      into.box(fn(w) {
        w
        .grow(Is(1.0))
        // (20 a line, as menu_item sets its words)
        .words(Is(x.label), look={ ..toast_words_look(Ui, L5, if on { 500 } else { 400 }, false), line: pick_row_line })
        .ink(By(fn() { if on { library_theme().p.accent_text } else { library_theme().p.text } }))
        .alpha(By(words_in))
        |> ignore
      })
      |> ignore
      if x.value != "" {
        into.box(fn(w) {
          w
          // (its line the theme's for words of no line of their own, as menu_item's note at its end has it)
          .words(Is(x.value), look={
            let l = toast_words_look(Meta, L5, 400, false)
            { ..l, line: @ui.tree_theme().text_line * l.size }
          })
          .ink(By(fn() { library_theme().p.muted }))
          .alpha(By(words_in))
          |> ignore
        })
        |> ignore
      }
    }
    if x.note == "" {
      first_line(r)
    } else {
      // (its note under its words, as far in as they are; what leads it by its first line: lead_by_first_line)
      r.box(fn(lines) {
        lines.grow(Is(1.0)) |> ignore
        lines.box(fn(l) {
          l.row(Is(true)).lines_up(Is(Some(Middle))).gap(Is(gap)) |> ignore
          first_line(l)
        })
        |> ignore
        lines.box(fn(u) {
          u.padding(Is((if panel { panel_icon_col + gap } else { 0.0 }, 0.0, 0.0, 0.0))) |> ignore
          u.box(fn(w) {
            w
            .words(Is(x.note), look=toast_words_look(Meta, L5, 400, true))
            .ink(By(fn() { library_theme().p.muted }))
            .alpha(By(words_in))
            |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let pick_search_at : @ui.Style = @ui.css("w=Full")

///|
/// A long pick's row's words' line (menu_item's: 20).
let pick_row_line : Double = 20.0
