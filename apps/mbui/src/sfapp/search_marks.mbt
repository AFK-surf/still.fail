// A search's words marked in the message it opened a chat at (still.fail apps/android chat/screens/ChatMotion.kt markWords,
// drawFound; Chat.kt rememberJump's FOUND; shared/ui/TextMark.kt passageMark with words): the chat opens with the
// message's top under the bar, its first word put in the list's middle when it lies low (past 80% of the page); each
// of the words in it is bold with a hand-drawn stroke under it, drawn in one after another, kept for as long as the
// chat shows. Nothing flashes.

///|
/// In the chat drawn now: the message the search opened it at (its ts, "" none), the words, how far their strokes are
/// drawn in (ms).
let found_marking : Ref[(String, Array[String], Double)] = Ref(("", [], 0.0))

///|
/// How long the strokes are drawn in for (ChatMotion.kt drawFound: STROKE_MS + STROKE_GAP_MS × 12).
let found_draw_ms : Double = @sf.strokes_ms(12)

///|
/// In the chat drawn now, while ⌘F's bar is open in it (wide_find.mbt): what it found, marked in every message drawn.
let find_marking : Ref[Array[String]] = Ref([])
