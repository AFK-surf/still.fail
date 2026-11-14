// A list card made of pieces, each a block of a page's list (group_node's card, narrow): a long list on a card made
// only as far as it shows (View::scrolls_window makes a block as it comes to show), where one card holding all of it
// is made whole in the frame it comes into view, as tall as it is where `est` was counted. The first piece is the
// card's top (its room over the rows, its top corners), the last its foot (its room under them, its foot corners, the
// room under the card), one alone the whole card, those between neither; what is on them the same as on group_node's.
// Laid out one under another they are that card, drawn the same.

///|
/// Which piece of a card a block of it is (card_piece_node): the whole card, its top, one between, its foot.
#derive(Eq, Debug)
pub(all) enum CardPiece {
  CardWhole
  CardTop
  CardBetween
  CardFoot
}

///|
/// The piece of a card the `i`th of `n` rows on it is (n at least 1).
pub fn card_piece_of(i : Int, n : Int) -> CardPiece {
  match (i == 0, i == n - 1) {
    (true, true) => CardWhole
    (true, false) => CardTop
    (false, true) => CardFoot
    (false, false) => CardBetween
  }
}

///|
/// A piece of a card (group_node's) as `piece` says it is now, `rows` made on it, made in `parent` (a block of a page's
/// list: page_block's room), as group_node lays out its three narrow forms: in a panel's body, the panel's card
/// (panel_card_group, its rows the ladder's inset in, `panel_card_in` from its sides); in a panel of its own (pane_lent),
/// a card's corner, the ladder's inset; else a list card (`list_pad` in, its corner), 10 under it. Its top and foot
/// rooms and corners only where it is the card's top or foot. It grows to what it is made in, as `parent` should to
/// its block (a page's block grows to its slot: page_node): where the page's list sets its slots on whole pixels
/// (Tree::set_rows_grid) each is whole pixels tall, and the grounds of pieces that meet meet there, with no seam. Wide,
/// its rows alone (a wide group's card is not one of pieces), or, `wide_card`, a piece of the wide page's card (a
/// section's, desk_card's: `card_pad` in, its corner Xl3, the section's foot under it), `wide_gap` over a piece that
/// is not its top (the rows' gap, part of the piece, so it goes with the row it is over).
#callsite(autofill(loc))
pub fn card_piece_node(
  parent : @view.View,
  piece : () -> CardPiece,
  rows : (@view.View) -> Unit,
  wide_card? : Bool = false,
  wide_gap? : Double = 0.0,
  loc~ : SourceLoc,
) -> Unit {
  let at = part_of(parent)
  let top = fn() { piece() is (CardWhole | CardTop) }
  let foot = fn() { piece() is (CardWhole | CardFoot) }
  // (top left, then round it)
  let corners = fn(r : Double) -> (Double, Double, Double, Double)? {
    let t = if top() { r } else { 0.0 }
    let f = if foot() { r } else { 0.0 }
    Some((t, t, f, f))
  }
  if parent.lent(panel_in_lent) is Some(p) && !p.small {
    parent.box(made_for=loc, fn(k) {
      style_node(k, fn() {
        let (t, f) = (if top() { corner_inset } else { 0.0 }, if foot() { corner_inset } else { 0.0 })
        panel_card_ground.then(@ui.style(px=room(corner_inset), pt=room(t), pb=room(f))).then(panel_card_out_node(k))
      })
      k.grow(Is(1.0)).corners(By(fn() { corners(card_corner) })).lends(on_card_lent, true).lends(part_at, { ..at, list: at.look is Wide })
      |> ignore
      rows(k)
    })
    |> ignore
    return
  }
  if at.look is Wide && wide_card {
    parent.box(made_for=loc, fn(room) {
      room.grow(Is(1.0)).padding(By(fn() { (0.0, 0.0, 0.0, if foot() { section_foot } else { 0.0 }) })) |> ignore
      room.box(fn(card) {
        card
        .grow(Is(1.0))
        .padding(By(fn() { (card_pad, if top() { card_pad } else { wide_gap }, card_pad, if foot() { card_pad } else { 0.0 }) }))
        .corners(By(fn() { corners(@ui.tree_theme().corner(Xl3)) }))
        .ground(By(fn() { @ui.tree_theme().color(Card) }))
        .clips(Is(true))
        |> ignore
        rows(card)
      })
      |> ignore
    })
    |> ignore
    return
  }
  if at.look is Wide {
    parent.box(made_for=loc, fn(k) { rows(k) }) |> ignore
    return
  }
  let (pad, corner) = if in_pane_node(parent) { (corner_inset, card_corner) } else { (list_pad, list_card_corner) }
  parent.box(made_for=loc, fn(room) {
    room.grow(Is(1.0)).padding(By(fn() { (0.0, 0.0, 0.0, if foot() { card_piece_under } else { 0.0 }) })) |> ignore
    room.box(fn(card) {
      card
      .grow(Is(1.0))
      .padding(By(fn() { (pad, if top() { pad } else { 0.0 }, pad, if foot() { pad } else { 0.0 }) }))
      .corners(By(fn() { corners(corner) }))
      .ground(By(fn() { @ui.tree_theme().color(Card) }))
      .clips(Is(true))
      .lends(on_card_lent, true)
      |> ignore
      rows(card)
    })
    |> ignore
  })
  |> ignore
}

///|
/// The room under a narrow list card (group_node's ListCard: 10).
let card_piece_under : Double = 10.0
