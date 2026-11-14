// Things to pick one of on a page made once, each by its mark and its name (a new profile's providers, the ways to
// connect one): wide, the web's tiles and cards (pages.css.ts group, tiles, tile, methods, method); narrow, the rows of a
// group's card (a list row each, its mark before its name). Laid out by the arrangement of the page they are in
// (look_node), what they show followed as it changes.

///|
/// A group of things to pick from under its small heading (`title`), `items` (an id and a name each) as they are now,
/// each by its mark (what `mark` makes for its id) and its name; pressed, `pick` given its id. Wide (group, groupHead,
/// tiles): its heading 8 over its tiles, three a row 4 apart, a tile its mark in a 28 square and its name, flat, the
/// hover's ground, 28 under the group. Narrow: its heading muted, a group's card of rows, each its mark, its name and a
/// chevron.
#callsite(autofill(loc))
pub fn pick_tiles_node(
  parent : @view.View,
  title : () -> String,
  items : () -> Array[(String, String)],
  mark : (@view.View, String) -> Unit,
  pick : (String) -> Unit,
  loc~ : SourceLoc,
) -> Unit {
  match look_node(parent) {
    Wide =>
      parent.box(made_for=loc, fn(g) {
        style_node(g, fn() { tile_group })
        words_node(g, title, fn() { tile_group_head }) |> ignore
        g.box(fn(rows) {
          style_node(rows, fn() { tile_rows })
          rows.each(
            fn() {
              let all = items()
              Array::makei((all.length() + 2) / 3, fn(r) { (r, Array::makei(3, fn(k) { all.get(r * 3 + k) })) })
            },
            fn(x) { x.0 },
            fn(row, x) {
              style_node(row, fn() { tile_row })
              for k in 0..<3 {
                row.pick(fn() { x.get().1[k] }, fn(slot, it) {
                  style_node(slot, fn() { tile_room }, in_row=true)
                  match it {
                    Some((id, name)) => tile_node(slot, id, name, mark, pick)
                    None => ()
                  }
                })
              }
            },
          )
        })
        |> ignore
      })
      |> ignore
    Narrow =>
      parent.box(fn(g) {
        style_node(g, fn() { tile_group_narrow })
        g.box(fn(h) {
          style_node(h, fn() { tile_group_head_narrow })
          words_node(h, title, fn() { tile_group_head_words }) |> ignore
        })
        |> ignore
        group_node(g, fn(card) {
          card.each(items, fn(it) { it.0 }, fn(r, it) {
            let id = @signals.untracked(fn() { it.get().0 })
            link_row_node(r, fn() { it.get().1 }, fn() { pick(id) }, lead=LeadMade(fn(l) {
              l.row(Is(true)).lines_up(Is(Some(Middle))) |> ignore
              mark(l, id)
            }))
          })
        })
      })
      |> ignore
  }
}

///|
/// A tile of pick_tiles_node's, wide: its mark in a 28 square, its name, 10 by 12 in, 12 apart, flat, the hover's ground
/// under the hand; read out a button by its name, pressed `pick` given its id.
#callsite(autofill(loc))
fn tile_node(
  slot : @view.View,
  id : String,
  name : String,
  mark : (@view.View, String) -> Unit,
  pick : (String) -> Unit,
  loc~ : SourceLoc,
) -> Unit {
  slot.box(made_for=loc, fn(t) {
    style_node(t, fn() { tile_look })
    t.ground(By(fn() { if lit_node(t) { @ui.tree_theme().color(Hover) } else { 0L } })) |> ignore
    pressed_node(t, fn() { pick(id) }, By(fn() { @ui.tree_theme().corner(Lg) }), Button, fn() { name })
    t.box(fn(m) {
      style_node(m, fn() { tile_mark })
      mark(m, id)
    })
    |> ignore
    words_node(t, fn() { name }, fn() { tile_name }) |> ignore
  })
  |> ignore
}

///|
/// Ways to go on, one to be chosen (the ways to connect a vendor that has both), `ways` (an id, its title, what it is)
/// as they are now; pressed, `choose` given its id. Wide (methods, method): side by side, 12 apart, each its title and
/// what it is on a card, the hover's ground under the hand. Narrow: a group's card of rows, each `mark` before its title,
/// what it is under it.
#callsite(autofill(loc))
pub fn ways_node(
  parent : @view.View,
  ways : () -> Array[(String, String, String)],
  choose : (String) -> Unit,
  mark? : (@view.View, String) -> Unit,
  loc~ : SourceLoc,
) -> Unit {
  match look_node(parent) {
    Wide =>
      parent.box(made_for=loc, fn(r) {
        style_node(r, fn() { way_cards })
        r.each(ways, fn(w) { w.0 }, fn(card, w) {
          let id = @signals.untracked(fn() { w.get().0 })
          style_node(card, fn() { way_card }, in_row=true)
          card.ground(By(fn() { @ui.tree_theme().color(if lit_node(card) { Hover } else { Card }) })) |> ignore
          pressed_node(card, fn() { choose(id) }, By(fn() { @ui.tree_theme().corner(Xl3) }), Button, fn() { w.get().1 })
          words_node(card, fn() { w.get().1 }, fn() { desk_strong }) |> ignore
          words_node(card, fn() { w.get().2 }, fn() { desk_muted }) |> ignore
        })
      })
      |> ignore
    Narrow =>
      group_node(parent, fn(card) {
        card.each(ways, fn(w) { w.0 }, fn(r, w) {
          let id = @signals.untracked(fn() { w.get().0 })
          let lead = match mark {
            Some(f) =>
              LeadMade(fn(l) {
                l.row(Is(true)).lines_up(Is(Some(Middle))) |> ignore
                f(l, id)
              })
            None => NoLead
          }
          link_row_node(r, fn() { w.get().1 }, fn() { choose(id) }, note=fn() { w.get().2 }, lead~)
        })
      })
  }
}

///|
/// A group of tiles (group: 28 under it; its heading 8 over its tiles).
// kept across runs: a value (no field of it changes)
let tile_group : @ui.Style = @ui.css("w=Full pb=S7 gap=S2")

///|
// kept across runs: a value (no field of it changes)
let tile_group_head : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Medium, color=Muted, w=Full)

///|
/// Its tiles, three a row, 4 apart, their ground out to the column's sides (outset 12).
// kept across runs: a value (no field of it changes)
let tile_rows : @ui.Style = outset(desk_list_out).then(@ui.css("gap=S1"))

///|
// kept across runs: a value (no field of it changes)
let tile_row : @ui.Style = @ui.css("row w=Full gap=S1")

///|
/// A tile's room in its row (a third of it).
// kept across runs: a value (no field of it changes)
let tile_room : @ui.Style = @ui.style(w=grow)

///|
/// A tile (its mark and its name, 10 by 12 in, 12 apart, flat, round as Lg).
// kept across runs: a value (no field of it changes)
let tile_look : @ui.Style = @ui.css("row w=Full px=S3 py=S2_5 gap=S3 align=ACenter radius=Lg")

///|
/// Its mark in a 28 square (pages.css.ts mark).
// kept across runs: a value (no field of it changes)
let tile_mark : @ui.Style = @ui.css("w=S7 h=S7 radius=Base bg=Neutral align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let tile_name : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Fg, wrap=false)

///|
/// A group of rows to pick from, narrow (pick_group_room: 8 under what is over it, its parts 12 apart).
// kept across runs: a value (no field of it changes)
let tile_group_narrow : @ui.Style = @ui.css("w=Full pt=S2 gap=S3")

///|
/// Its heading, 6 in and over (pick_group's).
// kept across runs: a value (no field of it changes)
let tile_group_head_narrow : @ui.Style = @ui.css("w=Full pl=S1_5 pt=S1_5")

///|
// kept across runs: a value (no field of it changes)
let tile_group_head_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, w=Full)

///|
/// The ways side by side (methods: 12 apart, as tall as the tallest).
// kept across runs: a value (no field of it changes)
let way_cards : @ui.Style = @ui.css("row w=Full gap=S3 align=AStretch")

///|
/// A way (method: 18 in, 6 apart, on a card, round as Xl3).
// kept across runs: a value (no field of it changes)
let way_card : @ui.Style = @ui.style(w=grow).then(@ui.css("p=S4_5 gap=S1_5 radius=Xl3"))
