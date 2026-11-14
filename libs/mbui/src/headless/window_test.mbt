// What every test of this package makes its window by (`window`), and what that holds of each: a component draws
// nothing and lays nothing out (headless.mbt). Held by what the tree keeps of each node, where each property of it was
// said (view's source.mbt): of every node the window has once it is made, a property said from one of this package's
// own files (a test's file, where the tests' looks are, is none) is one that is neither drawn nor laid out by. A
// component added here is held as its tests make their windows: nothing is listed.

///|
/// Where this package's own files are, as a place says them (view's source_place).
let own_files : String = "mbui/src/headless/"

///|
/// The properties of a node that draw nothing and lay nothing out: what it is read out as and whether it is, whether
/// it takes a press and the focus. A component says of its nodes, in its own files, only these.
let own_words : Array[String] = ["Says", "Hides", "Presses", "Focusable", "TabStop"]

///|
/// Whether `place` is in one of this package's own files, no test's.
fn own_place(place : String) -> Bool {
  place.has_prefix(own_files) && !place.contains("_test.mbt:")
}

///|
/// What node `v` of `tree` was said to be from this package's own files: each property, by name.
fn said_here(tree : @view.Tree, v : @view.View) -> Array[String] {
  match tree.sources_of(v.id()) {
    [step, ..] if step.id == v.id() => step.said.filter_map(fn(s) { if own_place(s.1) { Some(s.0) } else { None } })
    _ => []
  }
}

///|
/// Each property of a node in `v` or held by it that was said from this package's own files and is drawn or laid out
/// by: its name and where it was said.
fn drawn_here(tree : @view.Tree, v : @view.View, out : Array[String]) -> Unit {
  match tree.sources_of(v.id()) {
    [step, ..] if step.id == v.id() =>
      for s in step.said {
        if own_place(s.1) && !own_words.contains(s.0) {
          out.push("\{s.0} said at \{s.1}")
        }
      }
    _ => ()
  }
  for k in v.kids() {
    drawn_here(tree, k, out)
  }
}

///|
/// A window 400 by 300 whose tree `make` makes, pointed at with `pointing`, drawn once; held: nothing in it is drawn
/// or laid out by what a component's own file says.
fn window(make : (@view.View) -> Unit, pointing? : @ui.Pointing = Mouse) -> @ui.Tester raise {
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=300.0, pointing~)
  @ui.set_view_app(make)
  t.draw()
  let tree = @ui.view_tree().unwrap()
  let drawn = []
  drawn_here(tree, tree.root(), drawn)
  assert_eq(drawn, [])
  t
}
