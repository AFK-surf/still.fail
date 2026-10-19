///|
/// Tasks parked on something (a Deferred, a Queue, a Semaphore). A task that
/// is interrupted while parked takes itself off (`defer`); a woken one checks
/// again what it waited for, so nothing handed to a task that was cut is lost.
struct Waiters {
  tasks : Map[Int, Task]
  mut next : Int
}

///|
fn Waiters::new() -> Waiters {
  { tasks: {}, next: 0 }
}

///|
fn Waiters::is_empty(self : Waiters) -> Bool {
  self.tasks.is_empty()
}

///|
fn Waiters::wake_all(self : Waiters) -> Unit {
  let ts = self.tasks.values().to_array()
  self.tasks.clear()
  for t in ts {
    t.wake()
  }
}

///|
async fn Waiters::wait(self : Waiters) -> Unit noraise {
  let t = current_task()
  self.next += 1
  let id = self.next
  self.tasks.set(id, t)
  defer self.tasks.remove(id)
  park()
}
