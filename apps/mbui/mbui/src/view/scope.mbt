// A part of the window drawn otherwise than the rest (an app's sidebar in a theme of its own): a number a node is
// given (View::scope) and what it holds as they are made take from it, and what is read for them (their bindings,
// their making, what is built in them later) reads as `scope_now`. What it means is the app's: mbui draws nothing
// otherwise for it.

///|
/// The scope what is read now is read in (0: none said).
// kept across runs: always put back as what set it returns (in_scope)
let scope_at : Ref[Int] = Ref(0)

///|
/// The scope what is read now is read in (View::scope; 0: none said).
pub fn scope_now() -> Int {
  scope_at.val
}

///|
/// `f` read in scope `k`, the one before put back after.
pub fn[T] in_scope(k : Int, f : () -> T) -> T {
  if scope_at.val == k {
    return f()
  }
  let was = scope_at.val
  scope_at.val = k
  let v = f()
  scope_at.val = was
  v
}

///|
/// `read` and `then` each done in the scope they are bound in now.
fn[T] scoped(read : () -> T, then : (T) -> Unit) -> (() -> T, (T) -> Unit) {
  let k = scope_at.val
  (fn() { in_scope(k, read) }, fn(v) { in_scope(k, fn() { then(v) }) })
}

///|
/// The scope a node made in `parent` is in: its holder's (none: 0).
fn Tree::scope_of(self : Tree, parent : Int) -> Int {
  if parent >= 0 && parent < self.nodes.length() {
    self.nodes[parent].scope
  } else {
    0
  }
}

///|
/// It and what is made in it from now on in scope `k` (what holds it, what was made in it before as it was): its
/// bindings bound from now on, its making and what they read, read in it.
pub fn View::scope(self : View, k : Int) -> View {
  guard self.live() is Some(n) else { return self }
  n.scope = k
  self
}
