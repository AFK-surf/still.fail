// Where two rooms meet (rooms.mbt, Ctx::room_faults): each has its own side of the line between them, whichever way the
// layout's rounding has them touch.

///|
test "rooms: keys in thirds of a row and a column, the layout's rounding running one a hair past the next, each keeps its side" {
  let ids : Array[Int] = []
  let key = fn(c : Ctx, name : String, w : Size, h : Size) {
    let id = c.id(name)
    ids.push(id)
    c.clicked(id) |> ignore
    c.box(id~, w~, h~, fn() {  }) |> ignore
  }
  let t = Tester::new(
    fn(c) {
      c.box(dir=Row, align=AStart, fn() {
        // rows of three, 245 and more across, each standing a little further in (where they start: a fraction of a point)
        c.box(fn() {
          for k in 0..<8 {
            c.box(dir=Row, pl=76.0 + 0.782 * k.to_double(), w=Px(76.0 + 245.0 + 0.782 * k.to_double() + 1.3 * k.to_double()), fn() {
              for i in 0..<3 {
                key(c, "across/\{k}/\{i}", Fill(1.0), Px(44.0))
              }
            })
            |> ignore
          }
        })
        |> ignore
        // and columns of three, 180 down, so
        for k in 0..<8 {
          c.box(pt=0.782 + 0.1 * k.to_double(), h=Px(180.0 + 0.782 + 0.1 * k.to_double()), fn() {
            for i in 0..<3 {
              key(c, "down/\{k}/\{i}", Px(44.0), Fill(1.0))
            }
          })
          |> ignore
        }
      })
      |> ignore
    },
    w=800.0,
    h=400.0,
  )
  t.draw()
  let c = g()
  let nodes : Array[Node] = []
  for id in ids {
    for i in 0..<c.count {
      if c.nodes[i].id == id {
        nodes.push(c.nodes[i])
      }
    }
  }
  // (as laid out: somewhere one runs past where the next starts, by less than the rules see)
  let mut across = false
  let mut down = false
  for j in 0..<(nodes.length() - 1) {
    let (a, b) = (nodes[j], nodes[j + 1])
    if a.y == b.y && a.x + a.fw > b.x && a.x < b.x {
      across = true
    }
    if a.x == b.x && a.y + a.fh > b.y && a.y < b.y {
      down = true
    }
  }
  assert_true(across && down, msg="none runs past the next: across \{across}, down \{down}")
  assert_eq(t.room_faults(), [])
}
