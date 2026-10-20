// How long a switch between places on the bottom bar takes (still.fail's Android app's BarTiming.kt, docs/telemetry.md
// → 安卓 `bar_switch`): the host is told as a place's page is put on the stack in place of another's (go_place), and as
// the frame that first built it is over. The times are the host's (src/stillfail: Android's BarTiming.java, logcat
// StillfailTiming and PostHog), from the finger lifted; nothing here reads a clock, and under a Tester nothing is told.

///|
/// What the host is told of a switch: a place's page put on the stack (the place left, "" from none; the place), and
/// built (the place).
pub(all) struct BarTiming {
  placed : (String, String) -> Unit
  built : (String) -> Unit
}

///|
/// The host's, set once as the app starts (src/stillfail main); None under a Tester (reset), unless its test sets one.
pub let bar_timing : Ref[BarTiming?] = Ref(None)

///|
/// The place switched to whose page is to be told built, until the frame that built it is over.
let bar_timed : Ref[String?] = Ref(None)

///|
/// A place's page put on the stack in place of `from`'s ("" none), from the bar or back to the chats (AppState.place).
fn bar_placed(from : String, place : String) -> Unit {
  match bar_timing.val {
    Some(t) => {
      (t.placed)(from, place)
      bar_timed.val = Some(place)
    }
    None => ()
  }
}

///|
/// The page at the stack's root built (page_view): the place switched to, told once the frame's builds are over.
fn bar_built(c : @ui.Ctx, page : Page) -> Unit {
  match (bar_timing.val, bar_timed.val, place_of(page)) {
    (Some(t), Some(p), Some(q)) if p == q =>
      c.after_build("bar-timing", fn() {
        if bar_timed.val == Some(p) {
          bar_timed.val = None
          (t.built)(p)
        }
      })
    _ => ()
  }
}
