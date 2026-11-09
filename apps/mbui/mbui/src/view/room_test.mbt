// What is made by the room it is given (View::by_room): made by the width what holds it gives it as the layout comes
// to it, laid out in that same layout, what is under it placed by what it came to, nothing laid out again after.

///|
/// A tree whose column holds a box made by its room (`tiles` tiles of 100 a line, 10 tall each line, as many lines as
/// `lines` says) and a box under it; the ids of the box under it and of each tile made, as they are made.
fn room_tree(lines : @signals.Signal[Int]) -> (@view.Tree, Ref[@view.NodeId?], Array[@view.NodeId], Ref[Int]) {
  let under : Ref[@view.NodeId?] = Ref(None)
  let tiles : Array[@view.NodeId] = []
  let makes = Ref(0)
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(col) {
        col.padding(Is((10.0, 0.0, 10.0, 0.0))) |> ignore
        col.by_room(fn(held, room) {
          makes.val = makes.val + 1
          held.pick(fn() { ((room.width() / 100.0).to_int(), lines.get()) }, fn(v, k) {
            tiles.clear()
            for _ in 0..<k.1 {
              v.box(fn(line) {
                line.row(Is(true)) |> ignore
                for _ in 0..<k.0 {
                  line.box(fn(tile) {
                    tiles.push(tile.id())
                    tile.width(Is(Some(100.0))).height(Is(Some(10.0))).ground(Is(0xFF0000FFL)) |> ignore
                  })
                  |> ignore
                }
              })
              |> ignore
            }
          })
        })
        |> ignore
        col.box(fn(u) {
          under.val = Some(u.id())
          u.height(Is(Some(5.0))).ground(Is(0x00FF00FFL)) |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  (t, under, tiles, makes)
}

///|
test "by_room: made by the width it is given as it is first laid out, what is under it placed by that in the same layout" {
  let lines = @signals.signal(2)
  let (t, under, tiles, makes) = room_tree(lines)
  assert_eq(makes.val, 0, msg="made as it is first laid out, not before: its room is not known before")
  let computes = t.work().computes
  t.frame(470.0, 300.0) |> ignore
  assert_eq(t.work().computes - computes, 1, msg="one layout")
  assert_eq(makes.val, 1)
  // (450 across: four of 100 a line)
  assert_eq(tiles.length(), 8)
  assert_eq(t.drawn_of(tiles[3]).map(fn(d) { d.x }), Some(310.0))
  assert_eq(t.drawn_of(under.val.unwrap()).map(fn(d) { d.y }), Some(20.0), msg="under its two lines")
}

///|
test "by_room: given another width, made again by it and laid out in that one layout; what it reads otherwise as ever" {
  let lines = @signals.signal(2)
  let (t, under, tiles, makes) = room_tree(lines)
  t.frame(470.0, 300.0) |> ignore
  let computes = t.work().computes
  t.frame(270.0, 300.0) |> ignore
  assert_eq(t.work().computes - computes, 1, msg="one layout for the window made narrower")
  assert_eq(tiles.length(), 4, msg="two a line")
  assert_eq(makes.val, 1, msg="made once: what read the room made again by it")
  assert_eq(t.drawn_of(tiles[1]).map(fn(d) { d.x }), Some(110.0))
  lines.set(3)
  let computes = t.work().computes
  t.frame(270.0, 300.0) |> ignore
  assert_eq(t.work().computes - computes, 1)
  assert_eq(tiles.length(), 6)
  assert_eq(t.drawn_of(under.val.unwrap()).map(fn(d) { d.y }), Some(30.0))
}

///|
test "by_room: as wide as it is still, nothing made again as the window grows taller" {
  let lines = @signals.signal(1)
  let (t, _, tiles, _) = room_tree(lines)
  t.frame(470.0, 300.0) |> ignore
  let first = tiles.copy()
  t.frame(470.0, 500.0) |> ignore
  assert_eq(tiles, first, msg="the same tiles")
}

///|
test "Room::tall: how tall what it holds comes to at its width, read in the same layout by what shows beside it" {
  // (words of 30 points a line, three lines at 100 across, one at 300: a toggle under them where they pass two lines)
  let wide = @signals.signal(100.0)
  let toggle : Ref[@view.NodeId?] = Ref(None)
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(col) {
        col.width(By(fn() { Some(wide.get()) })) |> ignore
        col.by_room(fn(held, room) {
          let body = held.box(fn(b) {
            b.measured(Is(0), fn(_, w) {
              let w = w.unwrap_or(300.0)
              (w, if w < 300.0 { 90.0 } else { 30.0 })
            })
            |> ignore
          })
          held.show(fn() { room.tall(body) > 60.0 }, fn(m) {
            toggle.val = Some(m.id())
            m.height(Is(Some(20.0))).ground(Is(0x0000FFFFL)) |> ignore
          })
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  let computes = t.work().computes
  t.frame(400.0, 300.0) |> ignore
  assert_eq(t.work().computes - computes, 1, msg="one layout")
  assert_eq(t.drawn_of(toggle.val.unwrap()).map(fn(d) { d.y }), Some(90.0), msg="under its three lines")
  wide.set(300.0)
  let computes = t.work().computes
  t.frame(400.0, 300.0) |> ignore
  assert_eq(t.work().computes - computes, 1, msg="one layout")
  assert_eq(t.drawn_of(toggle.val.unwrap()), None, msg="one line: no toggle")
}

///|
test "panic by_room: what it makes saying its own box by its room is a fault" {
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(col) {
        col.by_room(fn(held, room) {
          match held.parent() {
            Some(own) => own.height(By(fn() { Some(room.width() / 2.0) })) |> ignore
            None => ()
          }
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(400.0, 300.0) |> ignore
}
