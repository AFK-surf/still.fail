///|
/// Both sides of a `race` failed.
pub suberror BothFailed {
  BothFailed(Error, Error)
} derive(Show)

///|
/// Which of `tasks` ended first (its index), waiting for one to.
async fn first_end(tasks : Array[Task]) -> Int noraise {
  let me = current_task()
  let winner = Ref(-1)
  let ids : Array[(Task, Int)] = []
  for i, t in tasks {
    if !(t.end is NotYet) {
      if winner.val < 0 {
        winner.val = i
      }
    } else {
      let id = t.watch(() => {
        if winner.val < 0 {
          winner.val = i
        }
        me.wake()
      })
      ids.push((t, id))
    }
  }
  defer {
    for p in ids {
      p.0.watchers.remove(p.1)
    }
  }
  while winner.val < 0 {
    park()
  }
  winner.val
}

///|
/// The first of `a` and `b` to end, success or failure, is the answer; the
/// other is interrupted and waited for, its finalizers run (raceFirst).
pub async fn[X] race_first(a : async () -> X, b : async () -> X) -> X {
  scoped(s => {
    let fa = s.fork(a, name="race a")
    let fb = s.fork(b, name="race b")
    let (w, l) = if first_end([fa.task, fb.task]) == 0 {
      (fa, fb)
    } else {
      (fb, fa)
    }
    ignore(l.interrupt_and_wait())
    w.join()
  })
}

///|
/// The first of `a` and `b` to succeed; the other is interrupted and waited
/// for. Both failing: `BothFailed`, first failure first (Effect.race).
pub async fn[X] race(a : async () -> X, b : async () -> X) -> X {
  scoped(s => {
    let fa = s.fork(a, name="race a")
    let fb = s.fork(b, name="race b")
    let (w, l) = if first_end([fa.task, fb.task]) == 0 {
      (fa, fb)
    } else {
      (fb, fa)
    }
    match w.poll() {
      Some(Succeeded(x)) => {
        ignore(l.interrupt_and_wait())
        x
      }
      Some(Failed(e1)) =>
        match l.wait() {
          Succeeded(x) => x
          Failed(e2) => raise BothFailed(e1, e2)
          Interrupted => raise e1
        }
      _ => l.join()
    }
  })
}

///|
/// All of `fs` at once; their values in order. The first to fail fails it,
/// the others interrupted (Effect.all with unbounded concurrency); others
/// that had failed as well are told to `on_defect`.
pub async fn[X] all(fs : Array[async () -> X]) -> Array[X] {
  scoped(s => {
    let fibers = fs.map(f => s.fork(f, name="all"))
    while true {
      let open = fibers.filter(f => !(f.is_done())).map(f => f.task)
      for i, f in fibers {
        match f.poll() {
          Some(Failed(e)) => {
            // others that failed too are not lost (Effect's Cause would hold
            // them): told to on_defect
            for j in (i + 1)..<fibers.length() {
              if fibers[j].poll() is Some(Failed(e2)) {
                fibers[j].task.rt.report(e2)
              }
            }
            raise e
          }
          Some(Interrupted) => raise Interrupt
          _ => ()
        }
      }
      if open.is_empty() {
        break
      }
      ignore(first_end(open))
    }
    fibers.map(f => f.cell.val.unwrap())
  })
}

///|
/// `f`'s value, or None when it took longer than `ms` (it is interrupted).
pub async fn[X] timeout(ms : Int, f : async () -> X) -> X? {
  race_first(() => Some(f()), () => {
    sleep(ms)
    None
  })
}
