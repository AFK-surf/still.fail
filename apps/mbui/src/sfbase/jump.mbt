// A message a chat is to show (ember web/src/jumpTo.ts): a row's state line pressed where the core says what its
// state is about, a notification's, a search's. Asked for here as the chat is opened (by either frame); its page takes
// it once the message is in, goes there and flashes it.

///|
/// The message each chat is to go to once its list is in place (Screen.Chat.at: a notification's), by chat.
pub let go_tos : Map[String, Double] = {}

///|
/// The chat `r`, once open and in place, goes to its message `seq` (the pages before it brought in until it is
/// there), which flashes (ChatHost.kt goTo, jumpTo.ts jumpTo).
pub fn go_to(r : ChatRef, seq : Double) -> Unit {
  go_tos[r.station + "\u{1}" + r.session] = seq
}
