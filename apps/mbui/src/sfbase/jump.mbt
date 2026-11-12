// A message a chat is to show: a row's state line pressed where the core says what its
// state is about, a notification's, a search's. Asked for here as the chat is opened (by either frame); its page takes
// it once the message is in, goes there and flashes it.

///|
/// The message each chat is to go to once its list is in place (Screen.Chat.at: a notification's), by chat.
pub let go_tos : Map[String, Double] = Map([])

///|
/// Told as a chat is given a message to go to (go_to, go_back_to): what goes there as it is told (a chat's page made as
/// nodes, chat_goes_to) looks again.
// kept across runs: a count, only compared
pub let go_tos_said : @signals.Signal[Int] = @signals.signal(0)

///|
/// The chat `r`, once open and in place, goes to its message `seq` (the pages before it brought in until it is
/// there), which flashes: only the `passage` of it a quote quoted, where its words
/// have it (Chat.tsx Quotes' jump); the whole message else.
/// Gone to inside the chat as it shows, placed, more than a list's height from its end (`keep_place`: not where the
/// go-to opens the chat, a notification's, a search's): where the reader was is kept (place_kept), unless a place is
/// kept already, for the way to the newest to go back to first.
pub fn go_to(r : ChatRef, seq : Double, passage? : String = "", keep_place? : Bool = true) -> Unit {
  let k = r.station + "\u{1}" + r.session
  if keep_place {
    keep_place_of(k)
  }
  go_tos[k] = seq
  go_tos_said.set(go_tos_said.untracked() + 1)
  if passage.trim(chars=" \n\t") != "" {
    go_to_passages[k] = passage
  } else {
    go_to_passages.remove(k)
  }
}

///|
/// The passage of the message each chat is to go to that is to flash alone (go_to), by chat.
pub let go_to_passages : Map[String, String] = Map([])

///|
/// The words a search opened each chat at its message with (Screen.Chat.words), by chat: marked in
/// that message rather than it flashing.
pub let go_to_words : Map[String, Array[String]] = Map([])

///|
/// The chat `r` opened from a search at its message `seq`, the search's `words` marked there (Search.kt FoundRow,
/// Switcher.tsx's found message).
pub fn open_chat_found(r : ChatRef, seq : Double, words : Array[String]) -> Unit {
  go_to(r, seq, keep_place=false)
  if words.length() > 0 {
    go_to_words[r.station + "\u{1}" + r.session] = words
  }
  open_page(Chat(r))
}

///|
/// Where the reader was in each chat as a go-to inside it took its list away (go_to): the message at the top of what
/// showed and how far its top was below the list's (as kept_places keeps a place), by chat. The way to the newest goes
/// back there first (go_back_to), then to the end; at the end, sending, `chat.latest` forget it (place_forget).
// kept across runs: put back by the package's reset (pages.mbt)
pub let places_back : Map[String, (Double, Double)] = Map([])

///|
/// Told as a place is kept or forgotten: what says the way to the newest (its tip, its name) built again.
// kept across runs: a count, only compared
pub let places_back_said : @signals.Signal[Int] = @signals.signal(0)

///|
/// The offset each chat's list goes back to its place at (go_back_to): the message gone to then is put there, its top that
/// far under the list's, not flashing (list_after).
// kept across runs: put back by the package's reset (pages.mbt)
pub let go_back_offsets : Map[String, Double] = Map([])

///|
/// Where the reader was is kept for chat `k` (go_to's): its list showing, placed, more than its own height from the
/// chat's end as it was last laid out (Reading's `far`: the window short of the chat's end, or its last row that far
/// under the view), none kept yet. A page made as nodes (chat_page_nodes) says its list is placed only while it shows
/// (sfpages' chat_goes_to), the old page's `shown` none of its.
fn keep_place_of(k : String) -> Unit {
  guard !places_back.contains(k) else { return }
  guard readings.get(k) is Some(rd) &&
    rd.placed &&
    (rd.shown || chat_page_nodes.untracked()) &&
    rd.top_seq >= 0.0 &&
    rd.far else {
    return
  }
  places_back[k] = (rd.top_seq, rd.top_off)
  places_back_said.set(places_back_said.untracked() + 1)
}

///|
/// Whether chat `k` (station and session, \u{1} between) keeps a place to go back to: read, what reads it told as that
/// changes.
pub fn place_kept(k : String) -> Bool {
  places_back_said.get() |> ignore
  places_back.contains(k)
}

///|
/// Chat `k`'s kept place forgotten (its end reached, words sent, `chat.latest`).
pub fn place_forget(k : String) -> Unit {
  if places_back.contains(k) {
    places_back.remove(k) |> ignore
    places_back_said.set(places_back_said.untracked() + 1)
  }
}

///|
/// Chat `r`'s list back to the place kept (none: false), not flashing, and the place forgotten.
pub fn go_back_to(r : ChatRef) -> Bool {
  let k = r.station + "\u{1}" + r.session
  match places_back.get(k) {
    Some((seq, off)) => {
      place_forget(k)
      go_tos[k] = seq
      go_to_passages.remove(k) |> ignore
      go_to_words.remove(k) |> ignore
      go_back_offsets[k] = off
      go_tos_said.set(go_tos_said.untracked() + 1)
      true
    }
    None => false
  }
}
