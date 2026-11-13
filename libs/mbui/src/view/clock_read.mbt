// What reads the time as a node's property is worked out by its binding: a fault, failing the test that draws it
// (mbui's AGENTS.md, Two views: time is read where it is drawn, never as a frame is built). Such a property is worked
// out only when something tells the tree, so a frame painted alone draws it as it stood: what it worked out of the time
// stands still, or follows the clock while nothing on it moves.
//
// How a binding reads the time instead: where it is drawn (View::moved_by, a look's closure), or a way through its
// entry (Way::shown_on, View::drawn_while: the clock followed while it goes, its end read once it is there;
// View::goes_now: whether it goes, told at both its ends, the clock not followed). The tree's own work reads the
// logic's moment uncounted (Tree::logic_said: a layout, a scroll, what a pointer is over), and its own ways that follow
// the clock only while they go the clock uncounted (Tree::drawn_said: a scroll on by itself, its bar coming and going):
// a read there is said of the node it draws, made wherever the app made it, so no file's bar could hold it.
//
// Said only under a Tester (where the tree keeps where its nodes were made), once for each place: `CLOCKREAD` and how,
// where the node was made, for what part.
//
// - `logic_at` (Tree::logic_at, View::logic_at) fails, wherever it is read, past the bars below.
// - `drawn_at` (Tree::drawn_at) read in a binding of a source file fails past the bars below: it follows the clock, so
//   what it draws is never wrong, only worked out again on every frame, still or not (the coordinator of the migration,
//   2026-11-10: counted, not failing outright). A test's own (a `_test.mbt` or `_wbtest.mbt` file) is not counted: a
//   test may read the time as it likes.
// - `cycle` (View::cycle) is not counted: a spinner or a band of progress not known turns as long as it shows, which is
//   no motion with an end (Tree::cycle_read), so it follows the clock all the while by what it is.
//
// The bars are per file, places in it (lines nodes are made at that read so), and only fall: a file that reads fewer
// has its bar brought down in the same change, one with none leaves the list.

///|
/// How many places in each file may read the time so (`how` and the file): those left, each going. mbui's own here; an
/// app's said by the package each file is in, as it is loaded (clock_read_known, from its `fn init`).
// kept across tests: what the packages loaded said, once
let clock_read_bars : Map[String, Int] = {
  // the check's own case (clock_in_binding_wbtest), what it holds it says
  "logic_at mbui/src/ui/clock_in_binding_wbtest.mbt": 1,
  "drawn_at mbui/src/ui/nav_view.mbt": 1,
  "drawn_at mbui/src/ui/nav_flat_view.mbt": 1,
}

///|
/// An app's bars (`how`, its file as a place names it: `module/path`, and how many places), said by the package the
/// files are in from its `fn init`: they only fall, as mbui's.
pub fn clock_read_known(bars : Array[(String, String, Int)]) -> Unit {
  for bar in bars {
    clock_read_bars[bar.0 + " " + bar.1] = bar.2
  }
}

///|
// kept across tests: each place said once (Tree::clock_read_in_binding), and the places of each bar's file found so far
let clock_reads_said : Map[String, Bool] = Map([])

///|
let clock_read_places : Map[String, Array[String]] = Map([])

///|
/// The file of a place (`module/path:line`).
fn place_file(place : String) -> String {
  match place.rev_find(":") {
    Some(k) => place[:k].to_owned()
    None => place
  }
}

///|
/// Whether a file is a test's.
fn test_file(file : String) -> Bool {
  file.has_suffix("_test.mbt") || file.has_suffix("_wbtest.mbt")
}

///|
/// What is wrong with the time read so (`how`) in a binding of a node made at `place`, its file's places read so found
/// before it `found` (its bar's: what this one adds to it): None where nothing is.
pub fn clock_read_fault(how : String, place : String, found : Array[String]) -> String? {
  let file = place_file(place)
  if how == "cycle" || (how == "drawn_at" && test_file(file)) {
    return None
  }
  let bar = clock_read_bars.get(how + " " + file).unwrap_or(0)
  let places = if found.contains(place) { found.length() } else { found.length() + 1 }
  guard places > bar else { return None }
  Some(
    "the time read as a node's property is worked out by its binding (mbui's src/view/clock_read.mbt): " + how + " in a node made at " +
    place + ", " + places.to_string() + " places of " + file + " reading it so, its bar " + bar.to_string() +
    ". Read it where it is drawn (View::moved_by, a look's closure) or a way through its entry (Way::shown_on, View::drawn_while, View::goes_now)",
  )
}

///|
/// The time read (`how`: Tree::logic_at, Tree::drawn_at, View::cycle) as a node's property is worked out by its binding:
/// said once for each place, where the tree keeps where its nodes were made (a Tester's); past its file's bar, the test
/// fails (clock_read_fault).
fn Tree::clock_read_in_binding(self : Tree, how : String) -> Unit {
  if self.binding_reading < 0 || self.binding_reading >= self.nodes.length() {
    return
  }
  let n = self.nodes[self.binding_reading]
  guard n.source is Some(_) else { return }
  let steps = self.sources_of({ at: self.binding_reading, gen: n.gen })
  guard steps.get(0) is Some(first) else { return }
  let key = how + " " + first.made + " for " + first.made_for
  if clock_reads_said.contains(key) {
    return
  }
  clock_reads_said[key] = true
  println("CLOCKREAD " + key)
  let bar_key = how + " " + place_file(first.made)
  let found = clock_read_places.get(bar_key).unwrap_or([])
  if clock_read_fault(how, first.made, found) is Some(said) {
    @halt.saying(said)
  }
  if !found.contains(first.made) {
    found.push(first.made)
    clock_read_places[bar_key] = found
  }
}

///|
/// What has read the time as a node's property was worked out by its binding, said once each (Tree::clock_read_in_binding):
/// how, where the node was made, for what part.
pub fn clock_reads_in_bindings() -> Array[String] {
  let out = clock_reads_said.keys().collect()
  out.sort()
  out
}
