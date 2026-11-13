///|
/// Permits: at most so many holders at once.
pub struct Semaphore {
  priv mut permits : Int
  priv waiters : Waiters
}

///|
pub fn Semaphore::new(permits : Int) -> Semaphore {
  { permits, waiters: Waiters::new() }
}

///|
pub fn Semaphore::available(self : Semaphore) -> Int {
  self.permits
}

///|
pub fn Semaphore::try_acquire(self : Semaphore) -> Bool {
  if self.permits > 0 {
    self.permits -= 1
    true
  } else {
    false
  }
}

///|
pub async fn Semaphore::acquire(self : Semaphore) -> Unit noraise {
  while self.permits == 0 {
    self.waiters.wait()
  }
  self.permits -= 1
}

///|
pub fn Semaphore::release(self : Semaphore) -> Unit {
  self.permits += 1
  self.waiters.wake_all()
}

///|
/// `f` holding a permit, given back however it ends (withPermits(1)).
pub async fn[X] Semaphore::with_permit(self : Semaphore, f : async () -> X) -> X {
  self.acquire()
  defer self.release()
  f()
}
