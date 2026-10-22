// still.fail's Android app recorded frame by frame by its own motion tests (apps/android/.../motion, Harness.kt's
// tape.json, kept as e2e/tapes/NAME.trace) and this app replayed over the same (@sfapp.tape_differences): where each
// frame's words are drawn here against where Android drew them.

///|
/// The tapes kept: each of Android's recordings by its name.
let tapes : Array[String] = [
  "answered-by-picking", "chat-open", "activity-pushed", "caught-up", "emit-one", "emit-stream", "emit-two", "emit-two-agents",
  "follow-glide", "one-stops-first",
  // the chats list (HomeMotionTest)
  "home-news-up", "home-row-gone", "home-row-new", "home-made-chat", "home-mark", "home-days", "home-day-gone", "home-filter",
  "home-swipe", "home-search", "home-back-changed",
]

///|
test "Android's recordings replayed: where their words are drawn here, frame by frame" {
  for name in tapes {
    match read_trace("../tapes/" + name) {
      Some(json) => {
        let diffs = @sfapp.tape_differences(json)
        println("TAPE \{name}: \{diffs.length()} words differ")
        for d in diffs {
          println("TAPE   " + d)
        }
      }
      None => println("TAPE \{name}: not found")
    }
  }
}
