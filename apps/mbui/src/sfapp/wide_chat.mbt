// A chat in the wide frame's pane (ember web/src/pages/ChatPage.tsx, styles/sidebar.css.ts pageBar, session.css.ts,
// dock.css.ts): its bar (45 high, the title 14 in 600, who is in it, its agents; at its end 归档 while nothing is left
// in it, its services and jobs, its info), the messages in a column 760 wide at most in the middle of the pane (the
// phone's rows: chat.mbt), the composer at its foot, 804 at most. What the phone's chat page does (reading, following
// its end, the way to the newest, telling the core what shows) is the same page's.

///|
/// What the composer's column holds, in the pane's middle (the column and the capsule's curve each side, 804 wide at
/// most, 12 from the pane's sides: dock.css.ts), in the wide frame; as it is elsewhere.
fn wide_center(c : @ui.Ctx, body : () -> Unit) -> Unit {
  ignore(c)
  body()
}

///|
/// The message the chat's window was last moved about for what ⌘F found (`chat.around`, once each).
let find_around : @signals.Signal[Double] = @signals.signal(-1.0, same=fn(a, b) { a == b })

