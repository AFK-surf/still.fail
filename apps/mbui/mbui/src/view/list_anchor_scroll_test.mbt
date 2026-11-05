// How far a scroll goes in a list laid out from its anchor: by the heights of the rows it passes, each measured as it
// is passed where it was not, never by what one is guessed to be; so where it stops is the same in one jump as in many
// (retained.md, "Layout read back": 258dee's −3000 wheel stopped 3 rows short of main's).

///|
/// The rows in sight, from the top, once `steps` wheels of `dy` each (toward its start) are done and the list is still.
fn wheeled_to(steps : Int, dy : Double) -> (Int, Double) {
  // (rows 40 and 80 tall in turn: what one is guessed to be, 80 said, the mean of those measured, 60, neither)
  let c = anchored_case(3000, tall_of=fn(k) { if k % 2 == 0 { 40.0 } else { 80.0 } })
  let mut t = 1000.0
  for _ in 0..<steps {
    c.tree.wheel_at(150.0, 50.0, 0.0, dy, 0, t) |> ignore
    t = t + 16.0
    c.tree.frame(390.0, 844.0, now=t) |> ignore
  }
  c.tree.frame(390.0, 844.0, now=t + 5000.0) |> ignore
  // (the row whose top is the nearest at or over the window's top, and where its top is)
  let mut best = -1
  let mut at = 0.0
  for k, v in c.live {
    let y = v.rect().1
    if y <= 0.001 && (best < 0 || y > at) {
      best = k
      at = y
    }
  }
  (best, at)
}

///|
test "scrolls_anchored: a wheel of 3000 toward its start stops on the same row as three hundred of 10, rows 40 and 80 tall in turn" {
  let one = wheeled_to(1, -3000.0)
  let many = wheeled_to(300, -10.0)
  assert_eq(one, many)
}
