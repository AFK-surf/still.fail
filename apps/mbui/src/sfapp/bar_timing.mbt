// How long a switch between places on the bottom bar takes (still.fail's Android app's BarTiming.kt
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
/// Told each time a place is put on the stack to be told built (bar_placed): what a page made once reacts to
/// (bar_built_node), back to the chats too, where no switch of the bar's is said.
// kept across runs: only counted on, what reads it reacting to its change, never to its value
let bar_timed_said : @signals.Signal[Int] = @signals.signal(0)

///|
/// A place's page put on the stack in place of `from`'s ("" none), from the bar or back to the chats (AppState.place).
fn bar_placed(from : String, place : String) -> Unit {
  match bar_timing.val {
    Some(t) => {
      (t.placed)(from, place)
      bar_timed.val = Some(place)
      bar_timed_said.set(bar_timed_said.untracked() + 1)
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

///|
/// A page made once at the stack's root (narrow_made_as's place), its page `page`: told built as bar_built tells one,
/// as it is made and as the place is switched to it again (place_switch said), at that change's moment.
fn bar_built_node(v : @view.View, page : () -> Page) -> Unit {
  v.reacts(fn() {
    place_switch.said()
    (place_switch.starts_at(), bar_timed_said.get())
  }, fn(_) {
    match (bar_timing.val, bar_timed.val, place_of(@signals.untracked(page))) {
      (Some(t), Some(p), Some(q)) if p == q =>
        v.at_moment(v.cause_at(), fn() {
          if bar_timed.val == Some(p) {
            bar_timed.val = None
            (t.built)(p)
          }
        })
        |> ignore
      _ => ()
    }
  })
}
