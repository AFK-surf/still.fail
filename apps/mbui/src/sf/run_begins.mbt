// A run's beginning, the library's one moment of it (run_begin): what a run before left (a menu a test opened and did
// not close) is no run's after it. Where nothing runs the app before its Tester (a Tester of sfpages' or of this
// library's), it is the moment that Tester is made (mbui's on_reset). Where what runs the app begins the run itself
// before its Tester (sfapp's new_run, its reset said by hand: the made-up core given what it opens first, what the test
// opens over it), it is that moment, and the Tester made after it begins none again: what was opened in between is
// that run's (#5559 put the presenters back as every Tester was made, and closed what sfapp's tests had opened before
// theirs: a chat's context, the card to share). On a device neither is ever said: a run is the app's.
// Why run_begun_by_app is here: mbui's own moment a run begins (@ui.on_reset) is the moment a Tester is made, so where
// the app begins its run earlier each layer that keeps something across runs has to be told not to begin it again
// (the app's own reset_by_hand, this). Once mbui owns the one moment a run begins (an app's run begun before its Tester
// included), the hooks hang there and this goes.

///|
/// Whether what runs the app has begun the run its next Tester is made in (sfapp's: its reset said by hand since a
/// Tester last began), so that Tester begins none. Said once as the app starts; none where nothing runs the app.
// kept across runs: a wire the app says once as it starts, the same for every run of it
pub let run_begun_by_app : Ref[() -> Bool] = Ref(fn() { false })

///|
/// A run begins as a Tester is made, unless what runs the app began it already (run_begun_by_app).
fn init {
  @ui.on_reset(fn() { if !(run_begun_by_app.val)() { run_begin() } })
}

///|
/// The library as a run begins: nothing presented, no menu open, no mark tapped open (parts_reset); no group's or
/// page's rows as drawn (group_rows_reset, page_rows_reset); no text read, no film played, the reader's layout as at
/// first (viewer_reset); none of the system's bars said (native_bars_reset). Said as a Tester begins a run (init
/// above) and by what runs the app as it begins one itself (its reset). Each was put back by the app's reset alone: a
/// run without the app (a Tester of sfpages' or of this library's) was given what the run before it left.
pub fn run_begin() -> Unit {
  parts_reset()
  group_rows_reset()
  page_rows_reset()
  viewer_reset()
  native_bars_reset()
}
