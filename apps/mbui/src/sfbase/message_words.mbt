// What a person wrote, as a chat draws it on the phone and the desktop (src/sfapp/messages.mbt, src/sfdesk/message.mbt):
// references to chats and web addresses written bare as links; and how every time in the app is said.

///|
/// Whether times say when (pressed, every one in the app says the other: the web's ui.tsx useAbsoluteTime), not how
/// long ago.
pub let absolute_times : Ref[Bool] = { val: false }

///|
/// Plain words as a message draws them (Markdown.kt withRefs, the web's ChatRef.tsx WithRefs): `[title](its link)` a
/// reference to that chat (`@` a little lighter, its title, in `accent`), a web address written bare a link, one to a
/// chat a reference too, reading as its title where `chat_title` says it (the message's chats, as the core says them).
/// What was sent from here and is not the core's yet has its references as the composer's marks, `@[title]` (`marks`:
/// where each starts and ends): drawn as the reference the core's row will have there.
pub fn message_runs(
  s : String,
  accent : Int64,
  chat_title? : (String) -> String? = fn(_) { None },
  marks? : Array[(Int, Int)] = [],
) -> Array[@ui.Run] {
  let out : Array[@ui.Run] = []
  let mut next = 0
  let words = StringBuilder()
  let flush = fn() {
    let w = words.to_string()
    if w != "" {
      bare_links(w, out, accent, chat_title)
    }
    words.reset()
  }
  let n = s.length()
  let mut i = 0
  while i < n {
    while next < marks.length() && marks[next].0 < i {
      next += 1
    }
    if next < marks.length() && marks[next].0 == i && marks[next].1 <= n && marks[next].1 - i >= 4 {
      let b = marks[next].1
      flush()
      out.push(@ui.span("@", color=@sf.alpha(accent, 0.7)))
      out.push(@ui.span(s.view(start_offset=i + 2, end_offset=b - 1).to_string(), color=accent))
      i = b
      continue
    }
    let ch = s.at(i).to_int()
    if ch == 91 {
      // [title](href) with /chats/ in it
      match s.view(start_offset=i + 1).find("](") {
        Some(close) if close >= 1 && close <= 120 => {
          let title = s.view(start_offset=i + 1, end_offset=i + 1 + close).to_string()
          let rest = s.view(start_offset=i + 1 + close + 2).to_string()
          match rest.find(")") {
            Some(end) if !title.contains("\n") => {
              let href = rest.view(end_offset=end).to_string()
              if @sf.is_chat_link(href) && !href.contains(" ") {
                flush()
                out.push(@ui.span("@", link=href, color=@sf.alpha(accent, 0.7)))
                out.push(@ui.span(title, link=href, color=accent))
                i = i + 1 + close + 2 + end + 1
                continue
              }
            }
            _ => ()
          }
        }
        _ => ()
      }
    }
    words.write_char(s.at(i).unsafe_to_char())
    i = i + 1
  }
  flush()
  out
}

///|
/// Words with the web addresses in them as links (bareLinks.ts: one ends at a space or at Chinese); one to a chat a
/// reference to it (message_runs).
fn bare_links(s : String, out : Array[@ui.Run], accent : Int64, chat_title : (String) -> String?) -> Unit {
  let mut from = 0
  let mut i = 0
  let n = s.length()
  while i < n {
    let at_link = s.view(start_offset=i).has_prefix("https://") ||
      s.view(start_offset=i).has_prefix("http://")
    if at_link {
      let mut j = i
      while j < n {
        let k = s.at(j).to_int()
        if k <= 32 || k >= 0x2E80 || k == 0xFF0C || k == 0x3002 {
          break
        }
        j = j + 1
      }
      // what ends a sentence is not the address's
      while j > i && ".,;:!?)'\"".contains(s.at(j - 1).unsafe_to_char().to_string()) {
        j = j - 1
      }
      if j - i > 8 {
        if i > from {
          out.push(@ui.plain(s.view(start_offset=from, end_offset=i).to_string()))
        }
        let href = s.view(start_offset=i, end_offset=j).to_string()
        if @sf.is_chat_link(href) {
          out.push(@ui.span("@", link=href, color=@sf.alpha(accent, 0.7)))
          out.push(@ui.span(chat_title(href).unwrap_or(href), link=href, color=accent))
        } else {
          out.push(@ui.link(href, href))
        }
        from = j
        i = j
        continue
      }
    }
    i = i + 1
  }
  if from < n {
    out.push(@ui.plain(s.view(start_offset=from).to_string()))
  }
}

