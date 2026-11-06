// A row's card ground and content share its opening room, but only the content fades and scales in it.

///|
test "windowed row rooms keep the ground whole and clip it while transforming only the content" {
  let moving = @signals.signal("")
  let grounds : Map[String, View] = {}
  let ground_parts : Map[String, View] = {}
  let bodies : Map[String, View] = {}
  let keys = ["first", "middle", "last"]
  let tree = Tree::new(fn(root) {
    root.width(Is(Some(100.0))).height(Is(Some(300.0))).scrolls_window(
      Scroll::list(), fn() { keys }, est=80.0, room_transforms=false,
      rooms=fn() {
        let current = moving.get()
        fn(k, h) {
          if current == k {
            { height: h / 2.0, offset: -h / 4.0, clip: true, soft: true, scale: 0.5, alpha: 0.5, presses: false }
          } else {
            list_room(h)
          }
        }
      },
      fn(row, k) {
        row.width(Is(Some(100.0))).height(Is(Some(80.0))) |> ignore
        grounds[k] = row.box(fn(ground) {
          ground.over(Is(true)).ground(Is(0xFFFFFFFFL)).list_room_ground() |> ignore
          ground_parts[k] = ground.box(fn(part) { part.over(Is(true)) |> ignore })
        })
        bodies[k] = row.box(fn(body) {
          body.width(Is(Some(100.0))).height(Is(Some(80.0))).ground(Is(0x3366CCFFL)).list_room_content() |> ignore
        })
      },
    ) |> ignore
  })
  tree.frame(100.0, 300.0) |> ignore
  for i, k in keys {
    tree.event((i + 1).to_double() * 10.0, fn() { moving.set(k) })
    tree.frame(100.0, 300.0) |> ignore
    let ground = grounds[k]
    let body = bodies[k]
    let (slot, _, _) = ground.lent(windowed_room).unwrap()
    let g = tree.drawn_of(ground.id()).unwrap()
    let b = tree.drawn_of(body.id()).unwrap()
    assert_eq((g.w, g.alpha), (100.0, 1.0), msg="\{k}: ground remains whole")
    assert_eq((b.w, b.alpha), (50.0, 0.5), msg="\{k}: only content scales and fades")
    assert_eq(slot.rect().3, 40.0, msg="\{k}: both are clipped to the opening room")
    assert_true(tree.cuts_softly(slot.id()))
    assert_true(tree.drawn_clear_of(ground.id(), slot.id()))
    assert_true(tree.drawn_clear_of(ground_parts[k].id(), slot.id()))
    assert_false(tree.drawn_clear_of(body.id(), slot.id()))
  }
}

///|
test "room helpers leave an ordinary list's own transforms alone" {
  let result : Ref[View?] = Ref(None)
  let tree = Tree::new(fn(root) {
    root.width(Is(Some(100.0))).height(Is(Some(100.0))).scrolls_window(Scroll::list(), fn() { ["one"] },
      fn(row, _) {
        result.val = Some(row)
        row.width(Is(Some(100.0))).height(Is(Some(80.0))).ground(Is(0xFFFFFFFFL))
        .alpha(Is(0.7)).scale(Is(0.8)).offset(Is((3.0, 0.0)))
        .list_room_content().list_room_ground() |> ignore
      }) |> ignore
  })
  tree.frame(100.0, 100.0) |> ignore
  let row = result.val.unwrap()
  let d = tree.drawn_of(row.id()).unwrap()
  assert_eq((d.w, d.alpha), (80.0, 0.7))
  let (slot, _, _) = row.lent(windowed_room).unwrap()
  assert_false(tree.drawn_clear_of(row.id(), slot.id()))
}
