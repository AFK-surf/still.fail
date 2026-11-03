// What a section says where it has none (section_none_node) and a row's tag after its title (row_tag_node), made once:
// narrow, 12 from the page's sides, none over and 8 under, the meta's muted; wide, as it is; a tag on its title's line.

///|
/// A page's room 390 wide in look `look`: a section's say of none, then a box 20 high under it; where each is drawn.
fn none_drawn(look : Look) -> ((Double, Double, Double, Double), Double) raise {
  let t = @ui.Tester::new(fn(_c) {  }, w=390.0, h=400.0)
  @ui.set_view_app(fn(root) {
    root.box(fn(b) {
      b.lends(part_at, { look, section: false, list: false }) |> ignore
      section_none_node(b, fn() { "这里还没有内容" })
      b.box(fn(under) { under.height(Is(Some(20.0))).words(Is("下一节"), look=@view.words_plain) |> ignore }) |> ignore
    })
    |> ignore
  })
  t.draw()
  guard t.rect_of("这里还没有内容") is Some(r) else { fail("not drawn") }
  guard t.rect_of("下一节") is Some(u) else { fail("what is under it not drawn") }
  (r, u.1)
}

///|
test "a section's say of none, narrow: 12 in from the page's sides, none over, 8 under; wide: as it is" {
  let (r, under) = none_drawn(Narrow)
  assert_eq(r.0, 12.0, msg="from its side: \{r}")
  assert_eq(r.1, 0.0, msg="over it: \{r}")
  assert_eq(under - (r.1 + r.3), 8.0, msg="under it: \{r} then \{under}")
  let (r, under) = none_drawn(Wide)
  assert_eq((r.0, r.1), (0.0, 0.0), msg="wide: \{r}")
  assert_eq(under, r.1 + r.3, msg="wide, nothing under it: \{r} then \{under}")
}

///|
test "a row's tag after its title, on its line, in the meta's size: shown while it says so" {
  let shown = @signals.signal(true)
  let t = @ui.Tester::new(fn(_c) {  }, w=390.0, h=200.0)
  @ui.set_view_app(fn(root) {
    root.box(fn(b) {
      b.lends(part_at, { look: Narrow, section: false, list: false }) |> ignore
      group_node(b, fn(g) {
        link_row_node(
          g,
          fn() { "发布流程" },
          fn() {  },
          title_after=fn(a) { row_tag_node(a, fn() { "已分享" }) },
          title_after_shown=fn() { shown.get() },
        )
      })
    })
    |> ignore
  })
  t.draw()
  guard t.rect_of("发布流程") is Some(title) else { fail("no title") }
  guard t.rect_of("已分享") is Some(tag) else { fail("no tag") }
  assert_true(tag.0 > title.0 + title.2 && tag.1 + tag.3 <= title.1 + title.3 + 1.0, msg="after it on its line: \{title} \{tag}")
  assert_true(tag.3 < title.3, msg="smaller than its title: \{title} \{tag}")
  shown.set(false)
  t.draw()
  assert_true(t.rect_of("已分享") is None, msg="not shown")
}
