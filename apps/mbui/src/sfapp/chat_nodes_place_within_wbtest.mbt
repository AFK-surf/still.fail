// Going to something low in a long message on a chat's page made as nodes (sfbase's chat_page_nodes) brings it before
// the eyes and shows what was meant (the chat's sixth principle): a quote's passage, a search's words, deep in an
// agent's long answer (the fixture's long_reply, its last line), come to rest between the bar and the composer, not
// only the message's top under the bar with what was meant under the composer (ListPlace::bring's `sought`,
// View::sought). 小屏's search from Home is search_wbtest's; here a quote's card's go-to on 小屏 and 大屏 and a
// search's on 大屏.

///|
/// Where the line holding `words` is drawn, its top and foot.
fn place_within_line(t : @ui.Tester, words : String) -> (Double, Double)? {
  t.text_runs().iter().find_first(fn(r) { r.text.contains(words) }).map(fn(r) { (r.top, r.bottom) })
}

///|
test "a quote's passage low in a long message, gone to on a chat's page made as nodes, 小屏 and 大屏: brought between the bar and the composer, lit there" {
  for s in [("小屏", 390.0, 844.0, 2), ("大屏", 1280.0, 800.0, 0)] {
    let (name, w, h, platform) = s
    let (t, _) = chat_nodes_calling(w, h, platform, [])
    let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
    // (as a quote's card pressed goes there: message_quotes_node's press, in its handler's change)
    @signals.start_batch()
    @sfbase.go_to(r, 3.0, passage="有问题随时说")
    @signals.end_batch()
    t.run_for(@sfbase.flash_in_ms + (@sfbase.flash_held_ms - @sfbase.flash_in_ms) / 2.0)
    guard place_within_line(t, "有问题随时说") is Some((top, foot)) else { fail("\{name}: the passage not drawn") }
    guard composer_top(t) is Some(under) else { fail("\{name}: no composer") }
    assert_true(top > 120.0 && foot < under, msg="\{name}: the passage at \{top}…\{foot}, the composer at \{under}")
    // (lit, as a passage picked is: the accent's ground over its words)
    let lit = grounds_in(t, @sf.theme().p.accent).filter(fn(g) { g.1 < foot && g.1 + g.3 > top })
    assert_true(lit.length() >= 1, msg="\{name}: the passage not lit")
  }
}

///|
test "a search's words low in a long message, the chat opened at it on a chat's page made as nodes, 大屏: brought between the bar and the composer, stroked there" {
  let (t, _) = chat_nodes_calling(1280.0, 800.0, 0, [])
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  @sfbase.open_chat_found(r, 3.0, ["有问题随时说"])
  t.run_for(@sfpages.found_draw_ms)
  guard place_within_line(t, "有问题随时说") is Some((top, foot)) else { fail("the match not drawn") }
  guard composer_top(t) is Some(under) else { fail("no composer") }
  assert_true(top > 120.0 && foot < under, msg="the match at \{top}…\{foot}, the composer at \{under}")
  assert_true(search_stroke_under(t, "有问题随时说", @sf.theme().p.accent, @sf.message_stroke.width))
}
