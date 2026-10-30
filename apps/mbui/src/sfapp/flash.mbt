// A message gone to flashing (ember apps/android chat/screens/ChatMotion.kt flash, flashed): which, how lit, and the
// accent's ground it is drawn in (by its message: messages.mbt).

///|
/// The message flashing in the chat drawn now (its ts, "" none) and how lit it is.
let flashing : @signals.Signal[(String, Double)] = @signals.signal(("", 0.0), same=fn(a, b) { a == b })

///|
/// The accent's ground in a chat (ChatMotion.kt accentBg: web --accent-bg).
fn flash_ground() -> Int64 {
  if @sf.theme().dark {
    0x43251AFFL
  } else {
    0xFFEFE6FFL
  }
}
