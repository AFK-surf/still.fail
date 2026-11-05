// Compatibility boundary for existing row renderers. The list obtains intrinsic
// answers for its owned rows before the tree is placed. Discovering another row
// can therefore extend the list's measurement without another whole-tree layout.
// This does not make arbitrary row-construction callbacks pure: migrating their
// model ownership remains separate from this render-resource adapter.

///|
fn Tree::layout_inputs(self : Tree) -> Unit {
  while true {
    let mut i = 0
    while i < self.bindings_due.length() {
      let binding = self.bindings_due[i]
      if binding.queued { (binding.run)() }
      i += 1
    }
    self.bindings_due.clear()
    self.heights_resolved()
    if self.list_measures.is_empty() { break }
    guard !self.measuring_lists else {
      abort("a list's intrinsic measurement cannot enter layout again")
    }
    self.measuring_lists = true
    let changed = @signals.untracked(fn() {
      @flex.measure_pass(fn() {
        let mut changed = false
        // Resolving a row may create or release a nested list. New owners join
        // the next iteration; a disposed owner answers without doing work.
        let readers = self.list_measures.values().collect()
        for read in readers {
          if read() { changed = true }
        }
        changed
      })
    })
    self.measuring_lists = false
    if !changed && self.bindings_due.is_empty() && self.heights_due.is_empty() { break }
  }
}
