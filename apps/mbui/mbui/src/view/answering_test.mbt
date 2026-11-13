// What an answer tells comes at once, whatever else the change it is in does and in whatever order (answering.mbt): a
// pick by an answer's value and by an event's, in a column with a line under it, its picked box 20 tall and 10 more
// for each of the two that is set; told in one change each way round, at 7, 24, 60 and 120 frames a second.

///|
priv struct AnswerCase {
  tree : @view.Tree
  clock : Ref[Double]
  answer : @signals.Signal[Int]
  event : @signals.Signal[Int]
  /// what the pick made last
  made : Ref[@view.View?]
}

///|
fn answer_case() -> AnswerCase {
  let clock = Ref(0.0)
  let answer = @signals.signal(0)
  let event = @signals.signal(0)
  let made : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(time=fn() { clock.val }, fn(root) {
    root.box(fn(col) {
      col.pick(fn() { (answer.get(), event.get()) }, fn(p, which) {
        let (a, e) = which
        made.val = Some(p)
        p.box(fn(b) { b.height(Is(Some(20.0 + 10.0 * (a + e).to_double()))) |> ignore }) |> ignore
      })
      col.box(fn(line) { line.height(Is(Some(40.0))) |> ignore }) |> ignore
    })
    |> ignore
  })
  { tree, clock, answer, event, made }
}

///|
/// `case` drawn at rest every `period`, told `tell` between two frames, and drawn on: whether what the pick made then
/// makes its way in.
fn answer_told(period : Double, tell : (AnswerCase) -> Unit) -> Bool raise {
  let case = answer_case()
  // (drawn at rest every `period` till 400 ms)
  while case.clock.val + period <= 400.0 {
    case.tree.frame(390.0, 844.0, now=case.clock.val) |> ignore
    case.clock.val += period
  }
  case.clock.val += period / 2.0
  tell(case)
  case.clock.val += period / 2.0
  case.tree.frame(390.0, 844.0, now=case.clock.val) |> ignore
  assert_true(!@view.answer_marks_left(), msg="an answer's marks left set")
  match case.made.val {
    Some(v) => v.comes_end() >= 0.0
    None => false
  }
}

///|
let answer_periods : Array[Double] = [1000.0 / 7.0, 1000.0 / 24.0, 1000.0 / 60.0, 1000.0 / 120.0]

///|
test "answering: what an answer alone tells comes at once" {
  for period in answer_periods {
    let way = answer_told(period, fn(c) { @view.answering(fn() { c.answer.set(1) }) })
    assert_true(!way, msg="at \{period} ms a frame: the answer's made its way in")
  }
}

///|
test "answering: what an event alone tells makes its way in" {
  for period in answer_periods {
    let way = answer_told(period, fn(c) { c.event.set(1) })
    assert_true(way, msg="at \{period} ms a frame: the event's came at once")
  }
}

///|
test "answering: an answer then an event in one change make their way in" {
  for period in answer_periods {
    let way = answer_told(period, fn(c) {
      @signals.start_batch()
      @view.answering(fn() { c.answer.set(1) })
      c.event.set(1)
      @signals.end_batch()
    })
    assert_true(way, msg="at \{period} ms a frame: answer then event came at once")
  }
}

///|
test "answering: an event then an answer in one change make their way in" {
  for period in answer_periods {
    let way = answer_told(period, fn(c) {
      @signals.start_batch()
      c.event.set(1)
      @view.answering(fn() { c.answer.set(1) })
      @signals.end_batch()
    })
    assert_true(way, msg="at \{period} ms a frame: event then answer came at once")
  }
}

///|
/// A change (a pick told by `trig`) that tells an answer within one part (`b`'s show, in `inner`) and an event outside
/// it (`a`'s show), at `period`: whether each made its way in.
fn answer_within(period : Double) -> (Bool, Bool) raise {
  let clock = Ref(0.0)
  let trig = @signals.signal(0)
  let a = @signals.signal(false)
  let b = @signals.signal(false)
  let made_a : Ref[@view.View?] = Ref(None)
  let made_b : Ref[@view.View?] = Ref(None)
  let inner : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(time=fn() { clock.val }, fn(root) {
    root.box(fn(col) {
      col.show(fn() { a.get() }, fn(s) {
        made_a.val = Some(s)
        s.box(fn(x) { x.height(Is(Some(30.0))) |> ignore }) |> ignore
      })
      col.box(fn(i) {
        inner.val = Some(i)
        i.show(fn() { b.get() }, fn(s) {
          made_b.val = Some(s)
          s.box(fn(x) { x.height(Is(Some(30.0))) |> ignore }) |> ignore
        })
      })
      |> ignore
      col.pick(fn() { trig.get() }, fn(_, t) {
        if t > 0 {
          match inner.val {
            Some(i) => @view.answering(within=i, fn() { b.set(true) })
            None => ()
          }
          a.set(true)
        }
      })
      col.box(fn(line) { line.height(Is(Some(40.0))) |> ignore }) |> ignore
    })
    |> ignore
  })
  // (drawn at rest every `period` till 400 ms)
  while clock.val + period <= 400.0 {
    tree.frame(390.0, 844.0, now=clock.val) |> ignore
    clock.val += period
  }
  clock.val += period / 2.0
  trig.set(1)
  clock.val += period / 2.0
  tree.frame(390.0, 844.0, now=clock.val) |> ignore
  assert_true(!@view.answer_marks_left(), msg="an answer's marks left set")
  let way = fn(m : Ref[@view.View?]) {
    match m.val {
      Some(v) => v.comes_end() >= 0.0
      None => false
    }
  }
  (way(made_a), way(made_b))
}

///|
test "answering: in one change an answer told within a part comes at once there, an event outside it makes its way in" {
  for period in answer_periods {
    let (a, b) = answer_within(period)
    assert_true(a, msg="at \{period} ms a frame: the event's came at once")
    assert_true(!b, msg="at \{period} ms a frame: the answer's made its way in")
  }
}
