///|
/// A card as wide as what it holds in a column that lines it up at its start (align-items: flex-start), a row across
/// it (stretched) whose words take what the row leaves (flex: 1 1 0): the card as tall as the words at the width it
/// is laid at, not at the none a flex basis of 0 gives them while the card's width is worked out.
test "a fit-content card's growing words: as tall as they are at its width" {
  let root = @flex.Node::new()
  root.style.position = Absolute
  root.style.set_width(Pt(358.0))
  root.style.align_items = FlexStart
  let card = @flex.Node::new()
  card.style.set_max_width(Pct(100.0))
  card.style.set_padding(Pt(10.0))
  root.add(card)
  let head = @flex.Node::new()
  head.style.direction = Row
  head.style.align_self = Stretch
  card.add(head)
  let words = @flex.Node::new()
  words.style.grow = 1.0
  words.style.set_basis(Pt(0.0))
  words.measure = Some(text_measure("Sign in to gh on Studio", row=true))
  head.add(words)
  @flex.compute(root)
  check("card", card, 0.0, 0.0, 250.0, 30.0)
  check("head", head, 10.0, 10.0, 230.0, 10.0)
  check("words", words, 0.0, 0.0, 230.0, 10.0)
}
