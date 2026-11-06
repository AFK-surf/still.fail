// The list cuts a card's ground and content to the same room, but softens the content alone.

///|
test "a row's ground stays solid under its softly cut opening content" {
  let ground : Ref[@view.NodeId?] = Ref(None)
  let body : Ref[@view.NodeId?] = Ref(None)
  let t = Tester::new(fn(_) { }, w=100.0, h=100.0)
  set_view_app(fn(root) {
    root.height(Is(Some(100.0))).scrolls_window(@view.Scroll::list(), fn() { ["row"] }, est=80.0,
      room_transforms=false, rooms=fn() {
        fn(_, h) { { height: h / 2.0, offset: -h / 4.0, clip: true, soft: true, scale: 0.5, alpha: 0.5, presses: true } }
      }, fn(row, _) {
        row.width(Is(Some(100.0))).height(Is(Some(80.0))) |> ignore
        row.box(fn(g) {
          ground.val = Some(g.id())
          g.over(Is(true)).ground(Is(0xFFFFFFFFL)).list_room_ground() |> ignore
        }) |> ignore
        row.box(fn(b) {
          body.val = Some(b.id())
          b.width(Is(Some(100.0))).height(Is(Some(80.0))).ground(Is(0x3366CCFFL)).list_room_content() |> ignore
        }) |> ignore
      }) |> ignore
  })
  inst_owners.track = true
  t.draw()
  let c = g()
  let mut gi = -1
  let mut bi = -1
  for i in 0..<c.ninst {
    if inst_by(i) == Node(ground.val.unwrap()) { gi = i }
    if inst_by(i) == Node(body.val.unwrap()) { bi = i }
  }
  assert_true(gi >= 0 && bi >= 0, msg="the ground and the content are both drawn")
  let ga = gi * inst_size
  let ba = bi * inst_size
  assert_eq((c.inst[ga + 53], c.inst[ga + 55]), (0.0, 0.0), msg="the ground has no soft edge")
  assert_true(c.inst[ba + 53] > 0.0 || c.inst[ba + 55] > 0.0, msg="the content fades towards the room")
  assert_eq(c.inst[ga + 19] - c.inst[ga + 17], 40.0, msg="the ground is cut to the room")
  inst_owners.track = false
}
