///|
/// A queue that was shut down: no more offers, and takes once it is empty.
pub suberror QueueShutdown derive(Show)

///|
/// A queue between fibers: `take` waits for an item; on a bounded one,
/// `offer` waits for room.
pub struct Queue[X] {
  priv items : @deque.Deque[X]
  priv cap : Int
  priv takers : Waiters
  priv putters : Waiters
  priv mut shut : Bool
}

///|
pub fn[X] Queue::unbounded() -> Queue[X] {
  { items: @deque.Deque([]), cap: -1, takers: Waiters::new(), putters: Waiters::new(), shut: false }
}

///|
pub fn[X] Queue::bounded(capacity : Int) -> Queue[X] {
  { items: @deque.Deque([]), cap: capacity, takers: Waiters::new(), putters: Waiters::new(), shut: false }
}

///|
pub fn[X] Queue::size(self : Queue[X]) -> Int {
  self.items.length()
}

///|
fn[X] Queue::has_room(self : Queue[X]) -> Bool {
  self.cap < 0 || self.items.length() < self.cap
}

///|
/// Adds `x` if there is room (offerUnsafe); false when full or shut down.
pub fn[X] Queue::try_offer(self : Queue[X], x : X) -> Bool {
  if self.shut || !self.has_room() {
    return false
  }
  self.items.push_back(x)
  self.takers.wake_all()
  true
}

///|
/// Adds `x`, waiting for room on a bounded queue.
pub async fn[X] Queue::offer(self : Queue[X], x : X) -> Unit {
  while !self.shut && !self.has_room() {
    self.putters.wait()
  }
  if self.shut {
    raise QueueShutdown
  }
  self.items.push_back(x)
  self.takers.wake_all()
}

///|
/// The first item, waiting for one.
pub async fn[X] Queue::take(self : Queue[X]) -> X {
  while self.items.is_empty() {
    if self.shut {
      raise QueueShutdown
    }
    self.takers.wait()
  }
  let x = self.items.pop_front().unwrap()
  self.putters.wake_all()
  x
}

///|
pub fn[X] Queue::try_take(self : Queue[X]) -> X? {
  let x = self.items.pop_front()
  if x is Some(_) {
    self.putters.wake_all()
  }
  x
}

///|
/// No more offers; takes end once what is in it is taken.
pub fn[X] Queue::shutdown(self : Queue[X]) -> Unit {
  self.shut = true
  self.takers.wake_all()
  self.putters.wake_all()
}
