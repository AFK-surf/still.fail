// What scrolls in itself in a panel whose body is nodes (panel_nodes), its head and foot standing where they are: a long
// list (panel_list's, an old view's Ctx::list in a panel) and a box kept to a height (an old view's Ctx::capped), as
// nodes of the window's tree on the tree's own scrolling (View::scrolls_window, View::scrolls), laid out one way: as
// tall as what they hold where there is the room, giving way where what holds them is short of it, never telling the
// panel how tall to be (one whose body is as tall as what it holds up to its share says so itself: panel_nodes' `hugs`).

///|
/// A long list in a panel's body in `parent` (panel_list's): the blocks `keys` names, each made by `row` in a node of its
/// own (given its key: what it binds read from what the key names, so a row stays as what it shows changes) only while
/// it shows, as tall as it was last measured meanwhile (`est` where it never was), scrolling up and down in itself as a
/// page's list does on its platform (Scroll::list), its bar along its right. It reaches out across the room the panel
/// leaves its rows (rows_out: what scrolls cuts what it holds to itself), its rows' words that much further in, so a
/// row's ground reaches the panel's sides as it does outside a list. As tall as its rows laid end to end where there is
/// the room, giving way where there is not; `fills`: the room the panel gives it, whatever it holds (one gone about in,
/// a folder after another, each holding more or less: not a list growing and shrinking at each step); `most`: no taller
/// than that. `place`: what asks it to show a row (ListPlace: one brought to its middle as it opens). Its node (what
/// scrolls).
#callsite(autofill(loc))
pub fn[K : Hash + Eq] panel_list_node(
  parent : @view.View,
  keys : () -> Array[K],
  row : (@view.View, K) -> Unit,
  est~ : Double,
  fills? : Bool = false,
  most? : () -> Double,
  place? : @view.ListPlace[K],
  loc~ : SourceLoc,
) -> @view.View {
  let at = panel_in_of(parent)
  let look = look_node(parent)
  let out = at.rows_out
  parent.box(made_for=loc, fn(room) {
    room.margin(Is((-out, 0.0, -out, 0.0))) |> ignore
    if fills {
      room.grow(Is(1.0)).basis(Is(Some(0.0))) |> ignore
    }
    match most {
      Some(m) => room.max_height(By(fn() { Some(m()) })) |> ignore
      None => ()
    }
    room.scrolls_window(
      @view.Scroll::list(),
      keys,
      fn(b, k) {
        // (its rows laid out as the panel's are, their words further in by as far as it reaches out)
        panel_in_lend(b, look, at.words + out, sides=at.sides - out, small=at.small, clear=at.clear, listed=true)
        row(b, k)
      },
      est~,
      slop=@ui.touch_slop(),
      bar=@ui.tree_scroll_bar(),
      place?,
      // (at once, as it was: a debt of 方案 A, given its way list by list, shown to the owner: list-comes-off)
      at_once=true,
    )
    |> ignore
  })
}

///|
/// A box in `parent` (an old view's Ctx::capped) no taller than `most`, what `body` makes in it (all of it, made once)
/// scrolling up and down in it where it is taller, faded towards an end it goes on past, its bar along its right; as
/// tall as what it holds where that is less, and shorter still where what holds it is short of room. Its node.
#callsite(autofill(loc))
pub fn capped_node(
  parent : @view.View,
  most : () -> Double,
  body : (@view.View) -> Unit,
  loc~ : SourceLoc,
) -> @view.View {
  parent.box(made_for=loc, fn(b) {
    b.max_height(By(fn() { Some(most()) })) |> ignore
    b.scrolls(@view.Scroll::new(), slop=@ui.touch_slop(), bar=@ui.tree_scroll_bar(), body) |> ignore
  })
}
