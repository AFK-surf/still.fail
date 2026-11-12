// The cards over the links of a node's words in pieces (sfpages' link_peek over an old view's paragraph, each link's
// card while the pointer rests on it) as nodes of the window's tree, made once: what the page says is which card each
// link has (`card_of`); the rest is here. A link's card is made as its link comes (by where it starts and where it
// leads: View::each) and let go as it goes; each a hover card (hover_card_node) of the words, beside its link's piece
// of them (@ui.runs_link_piece), opened as a mouse's pointer rests on that piece alone (@ui.runs_links' `pointed`) and
// closed as it leaves it and the card, each at its cause's moment. A finger's hold and a right click are the words'
// links' own (runs_links' `hold`: what holds the words says them); nothing of the hand is put on the words here.

///|
/// A link of a node's words as its card is asked for (link_cards_node's `card_of`): where it leads, what its words say
/// of it (as that changes), its first run; the node it is made with (let go as its link goes: what reads for it reacts
/// on it); whether a mouse's pointer is on it now and whether it is read for now (on it, or its card made), each
/// followed: what its card shows is read from the moment the pointer comes onto it while either, let go once neither.
pub(all) struct LinkOf {
  href : String
  words : () -> String
  first : Int
  node : @view.View
  pointed : () -> Bool
  reading : () -> Bool
}

///|
/// A link's card: as wide as what it holds (a page's tile, 220 to 420) or a card's 320 (`tile`), and what it holds
/// (`body`, made as it opens).
pub(all) struct LinkCard {
  tile : Bool
  body : (@view.View) -> Unit
}

///|
/// The cards over the links of node `words` (its words in pieces, their links pressed by `links`: @ui.runs_links'),
/// each link `shown` (runs_links' `shown`: where it leads, its words, its first run, as they change) given the card
/// `card_of` says (None: none), drawn in `layer`. What is made for them is made in `v` (over it, taking no room: nothing
/// of it drawn there). The hands of the cards made now, by their links' first runs.
#callsite(autofill(loc))
pub fn link_cards_node(
  v : @view.View,
  layer : TipLayer,
  words : @view.View,
  links : @ui.RunsLinks,
  shown : () -> Array[(String, String, Int)],
  card_of : (LinkOf) -> LinkCard?,
  loc~ : SourceLoc,
) -> Map[Int, HoverHand] {
  let hands : Map[Int, HoverHand] = Map([])
  v.box(made_for=loc, fn(h) {
    h.over(Is(true)) |> ignore
    h.each(shown, fn(l) { (l.2, l.0) }, fn(row, l) {
      let (href, _, first) = l.untracked()
      let pointed = fn() { links.pointed.get() == first }
      let made : @signals.Signal[Bool] = @signals.signal(false, same=fn(a, b) { a == b })
      let link : LinkOf = {
        href,
        words: fn() { l.get().1 },
        first,
        node: row,
        pointed,
        reading: fn() { pointed() || made.get() },
      }
      guard card_of(link) is Some(card) else { return }
      let hand = hover_card_node(
        layer,
        words,
        card.body,
        tile=card.tile,
        piece=@ui.runs_link_piece(words, first, href),
        pointed~,
        owner=row,
      )
      row.reacts(fn() { (hand.card)() is Some(_) }, fn(m) { made.set(m) })
      hands[first] = hand
      row.owns(fn() { if hands.get(first).map(fn(x) { physical_equal(x, hand) }).unwrap_or(false) { hands.remove(first) } })
      |> ignore
    })
  })
  |> ignore
  hands
}
