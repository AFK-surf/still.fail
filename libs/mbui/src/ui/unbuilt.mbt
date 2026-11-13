// What is told when what built it is no longer built (Ctx::on_unbuilt): the end of its owner's life, the framework's
// to say. A package that keeps something outside ui's frame by what built it (the motion package's values by key, a
// node's measure, the kit's tooltip state) lets it go then, not after some time or some frames unused.

///|
/// What asked to be told as it is no longer built, by its id: what tells it, and the build that last built it (built
/// as it asked, or kept as a list's row or a part that asked it: built_used).
// kept across runs: forgotten as another run begins (parts_forget)
let unbuilt_watch : Map[Int, UnbuiltWatch] = Map([])

///|
priv struct UnbuiltWatch {
  mut gone : () -> Unit
  mut build : Int
}

///|
/// `gone` runs once a frame is made whose last build (the one drawn) did not build what asks this now, by `id` (its
/// owner disposed: a page left, a row scrolled away, a part no longer shown); asked again, it is told again then. A
/// list's row or a part kept as its nodes, its build not run, builds it all the same (built_used). Asked outside a
/// build (as a frame is painted, between frames), nothing builds what asks it: nothing is told, and it answers false.
pub fn Ctx::on_unbuilt(self : Ctx, id : Int, gone : () -> Unit) -> Bool {
  if !building.val {
    return false
  }
  match unbuilt_watch.get(id) {
    Some(w) => {
      w.gone = gone
      w.build = self.build_no
    }
    None => unbuilt_watch[id] = { gone, build: self.build_no }
  }
  built_used(fn() {
    match unbuilt_watch.get(id) {
      Some(w) => w.build = g().build_no
      None => ()
    }
  })
  true
}

///|
/// The frame is made (parts_frame_end): what its last build did not build told it is gone.
fn unbuilt_told(c : Ctx) -> Unit {
  if unbuilt_watch.is_empty() {
    return
  }
  let gone : Array[Int] = []
  unbuilt_watch.each(fn(id, w) { if w.build != c.build_no { gone.push(id) } })
  for id in gone {
    match unbuilt_watch.get(id) {
      Some(w) => {
        unbuilt_watch.remove(id)
        (w.gone)()
      }
      None => ()
    }
  }
}
