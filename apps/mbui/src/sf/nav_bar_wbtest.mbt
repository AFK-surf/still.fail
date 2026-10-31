// The nav bar's back (nav_bar.mbt) short of room: its word whole or not at all.

///|
test "back whose word has not the room: the chevron alone, the word not cut, the button still called by it; given the room, the word whole" {
  let went = Ref::new(0)
  let room = Ref::new(40.0)
  let t = @ui.Tester::new(
    fn(c) {
      begin(c) |> ignore
      c.with_theme(ui_theme(), fn() {
        c.box(style=nav_back_test_room, fn() {
          if nav_back(c, "back", "A folder with a long name", max_w=room.val) {
            went.val = went.val + 1
          }
        })
        |> ignore
      })
    },
    w=390.0,
    h=200.0,
    platform=2,
  )
  t.draw()
  // (its word left out whole, not cut)
  let ctx = t.ctx()
  assert_true(ctx.left_out(ctx.id("back/word")))
  let b = t.get(@ui.Role::Button, label="A folder with a long name")
  assert_true(b.rect.2 > 0.0)
  assert_eq(t.squeeze_faults(), [])
  t.click(@ui.Role::Button, label="A folder with a long name")
  assert_eq(went.val, 1)
  // given the room: the word whole, on one line
  room.val = 300.0
  t.draw()
  assert_true(!ctx.left_out(ctx.id("back/word")))
  assert_eq(t.lines_of("A folder with a long name"), ["A folder with a long name"])
}

///|
// kept across runs: a value (no field of it changes)
let nav_back_test_room : @ui.Style = @ui.css("row w=Full px=S4")
