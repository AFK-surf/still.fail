// What a person wrote, as a chat draws it on the phone and the desktop (src/sfapp/messages.mbt, src/sfdesk/message.mbt):
// references to chats and web addresses written bare as links; and how every time in the app is said.

///|
/// Whether times say when (pressed, every one in the app says the other: the web's ui.tsx useAbsoluteTime), not how
/// long ago. A signal: what a node shows of a time follows it.
// kept across runs: false as a run begins (pages.mbt)
pub let absolute_times : @signals.Signal[Bool] = @signals.signal(false, same=fn(a, b) { a == b })

///|
/// How much of `accent` a reference's `@` has.
let ref_at_alpha : Double = 0.7

///|
/// A person's words in the runs the core read them in (a message's `words`: refLinks.ts personWords; what was sent from
/// here, its outbox row's, or before the core has it its `ref.words`: draftWords): a reference to a chat `@` a little
/// lighter and its title in `accent` (one written bare reading as `chat_title` says; a composer's mark its title), a web
/// address a link.
pub fn words_runs(parts : Array[Json], accent : Int64, chat_title? : (String) -> String? = fn(_) { None }) -> Array[@ui.Run] {
  let out : Array[@ui.Run] = []
  for p in parts {
    let words = text(Some(p), "text")
    let link = text(Some(p), "link")
    match field(Some(p), "ref") {
      Some(True) => {
        let title = if words == link { chat_title(link).unwrap_or(link) } else { words }
        out.push(@ui.span("@", link~, color=@sf.alpha(accent, ref_at_alpha)))
        out.push(@ui.span(title, link~, color=accent))
      }
      _ => out.push(if link != "" { @ui.link(words, link) } else { @ui.plain(words) })
    }
  }
  out
}

///|
/// What a person wrote as every place draws it, in a message, on its way there: the core's runs of it (`runs`, words_runs),
/// else the words as they are. Nothing makes up runs the core did not give: a row without them draws its words as
/// written in a test as on a device (a fixture's rows carry them as the core's do).
pub fn person_runs(words : String, runs : Json?, accent : Int64, chat_title? : (String) -> String? = fn(_) { None }) -> Array[@ui.Run] {
  match runs {
    Some(Array(parts)) => words_runs(parts, accent, chat_title~)
    _ => [@ui.plain(words)]
  }
}
