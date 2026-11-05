// Who decides a card (等 林 决定), its words as wide as they are at the card's start, as main's decision_box lines them
// up (align=AStart): not stretched across the message.

///|
test "who decides a card is as wide as its words, on a phone, the tape and a wide window" {
  for c in [(390.0, 844.0, 2), (390.0, 844.0, 0), (600.0, 900.0, 0), (1280.0, 800.0, 0)] {
    let (w, h, platform) = c
    let t = wide_tester([], mode="chat", w~, h~, platform~)
    t.run_for(@ui.move_most_ms * 2.0)
    let widths = t.words().filter(fn(x) { x.0 == "等 林 决定" }).map(fn(x) { x.3 < 80.0 })
    assert_eq(widths, [true], msg="\{w}/\{platform}")
  }
}
