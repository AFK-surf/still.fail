// A message a chat is to show (ember web/src/jumpTo.ts): a row's state line pressed where the core says what its
// state is about, a notification's, a search's. Asked for here as the chat is opened (by either frame); its page takes
// it once the message is in, goes there and flashes it.

///|
/// The message each chat is to go to once its list is in place (Screen.Chat.at: a notification's), by chat.
pub let go_tos : Map[String, Double] = {}

///|
/// The chat `r`, once open and in place, goes to its message `seq` (the pages before it brought in until it is
/// there), which flashes (ChatHost.kt goTo, jumpTo.ts jumpTo): only the `passage` of it a quote quoted, where its words
/// have it (Chat.tsx Quotes' jump); the whole message else.
pub fn go_to(r : ChatRef, seq : Double, passage? : String = "") -> Unit {
  let k = r.station + "\u{1}" + r.session
  go_tos[k] = seq
  if passage.trim(chars=" \n\t") != "" {
    go_to_passages[k] = passage
  } else {
    go_to_passages.remove(k)
  }
}

///|
/// The passage of the message each chat is to go to that is to flash alone (go_to), by chat.
pub let go_to_passages : Map[String, String] = {}

///|
/// The words a search opened each chat at its message with (Screen.Chat.words, jumpTo.ts `words`), by chat: marked in
/// that message rather than it flashing (Chat.kt host.goToWords).
pub let go_to_words : Map[String, Array[String]] = {}

///|
/// The chat `r` opened from a search at its message `seq`, the search's `words` marked there (Search.kt FoundRow,
/// Switcher.tsx's found message).
pub fn open_chat_found(r : ChatRef, seq : Double, words : Array[String]) -> Unit {
  go_to(r, seq)
  if words.length() > 0 {
    go_to_words[r.station + "\u{1}" + r.session] = words
  }
  open_page(Chat(r))
}
