// An agent's card over its picture beside its messages (hover.mbt's agent_hover, AgentHover), for a message drawn by
// nodes: opened once the pointer has rested on the picture hover_open_ms, closed hover_close_ms after it has left both
// the picture and the card; under the picture and at its start, hover_offset away, over the chat's messages and its
// composer (its page's flight layer: chat_flight_layer). What the card holds, the old view it is (agent_card), an island
// as tall as it is, built again as the chat's agent changes.

///|
/// Agent `agent()`'s card over picture `pic` of a message of chat `here()`, while the pointer rests on it.
fn agent_hover_node(pic : @view.View, src : Source, here : () -> MessageHere, agent : () -> String) -> Unit {
  // (pointed at as the pointer is over it, nothing pressed for it: what takes a press under it takes it as ever)
  pic.points(Is(true)) |> ignore
  let open = @signals.signal(false, same=fn(a, b) { a == b })
  let card_on : Ref[@view.View?] = Ref(None)
  let due : Ref[() -> Unit] = Ref(fn() {  })
  let on_it = fn() {
    @sf.pointer_rests() && (pic.pointed() || card_on.val.map(pointer_over).unwrap_or(false))
  }
  // (rested on, opened; left, both it and the card, closed: each from the moment the pointer came or went)
  pic.reacts(fn() { agent() != "" && on_it() }, fn(on) {
    (due.val)()
    // There is nothing to close until a card has opened. In particular a sample's pictures, whose agent is not
    // named and which take no input, schedule no close timer when first made.
    guard on || @signals.untracked(fn() { open.get() }) else { return }
    let wait = if on { hover_open_ms } else { hover_close_ms }
    due.val = pic.at_moment(pic.cause_at() + wait, fn() { open.set(on) })
  })
  pic.owns(fn() { (due.val)() }) |> ignore
  let r = fn() { here_ref(here()) }
  let layer = fn() { chat_flight_layer(r()) }
  pic.show(fn() { open.get() && layer() is Some(_) }, fn(anchor) {
    guard @signals.untracked(layer) is Some(l) else { return }
    // (in the layer, let go as it closes: what holds it here)
    l.box(fn(card) {
      // (as wide as what it holds, 420 at most, 220 at least: hover_tile's, as the old view laid it out)
      let card_w : @signals.Signal[Double?] = @signals.signal(None, same=fn(a, b) { a == b })
      card.owns(fn() { card_on.val = None }) |> ignore
      card.beside(pic.id(), side=Bottom, along=Start, offset=hover_offset, padding=8.0) |> ignore
      @ui.old(card, fn(c) {
        let rr = r()
        c.box(style=hover_tile, fn() {
          @sf.small_panel(c, w=Fill(1.0), fn() {
            // (what it holds 10 in from its padding, as hover's within_room)
            c.box(style=hover_inner, fn() {
              match agent_json((src.topic)("chat", chat_params(rr)).value, agent()) {
                Some(j) => agent_card(c, src, rr, j)
                None => ()
              }
            })
            |> ignore
          })
          |> ignore
        })
        |> ignore
      }, natural=true, fits=(agent_card_most, card_w))
      // (as wide as the old frame lays what it holds out: it takes presses and the pointer there, all of it, its own
      // lighting and tips by it)
      .width(By(fn() { card_w.get() }))
      |> fn(island) { card_on.val = Some(island) }
    })
    .lives_with(anchor)
    |> ignore
  })
}

///|
/// An agent's card as wide as what it holds at most (hover_tile_most's 420).
let agent_card_most : Double = 420.0

///|
/// Whether the pointer is over card `v` (where it is laid out, what it holds the old view's: its own hover and tips
/// by it, so not pointed at as a node of the tree's is), followed as it moves.
fn pointer_over(v : @view.View) -> Bool {
  match (v.pointer_here_told(), v.laid_size_told()) {
    (Some((x, y)), Some((w, h))) => x >= 0.0 && y >= 0.0 && x < w && y < h
    _ => false
  }
}
