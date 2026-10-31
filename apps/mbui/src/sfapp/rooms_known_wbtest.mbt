// The room a press has (mbui's Tester::room_faults and hover_only_faults, rooms.mbt; still.fail's rules 1 and 2,
// docs/architecture.md: room, what takes presses 44×44 at least; apart, no two such rooms overlapping; hover, what only
// a resting pointer shows reached by a hold too) on the same screens and windows the corner rule is held on
// (corners_wbtest.mbt, each screen opened once for all), in Chinese. Each rule's faults, all screens in all windows,
// keep to the bar here: one more fails, and one less until the bar comes down to it. Every fault is printed
// (`at: rule: …`) when a count is off its bar.

///|
/// The faults each rule still has (2026-10-26, as the rules came): they only fall. (2026-10-27: settings-notify-denied
/// showed the chats' list, its fixture naming no page, and shows the notifications page now: the chats' list's 10 room
/// and 7 apart gone from it, the settings' list's 21 apart beside it in the wide windows come, the ones every settings
/// screen there has: its rows 32 high, 34 apart. The same day the pages' rows the library's: 2 apart fewer. And a
/// capsule in a smooth corner standing as a circle reads it (smooth.mbt round_like): a tablet's composer on the tape
/// 6 lower, the chat's list showing more of the message at its top, its time under its words as every message's: 1
/// apart more. (2026-10-27: a chat row's state line and the marks in it parts of the row, only pointed at,
/// not targets of their own: 2090 room fewer. The same day one room for the hit test, a finger's and a pointer's,
/// and the rules (Ctx's press_reach, press_room): moved in from the window's edge, cut to what holds it, where two
/// meet each the part nearer it. A room overlapping another's is no fault of its own any more, only what is left
/// of each once they are parted: the 7248 apart, two targets each, counted as room where what is left is under
/// 44 (rows 32 high one after another, 32 keys 4 apart, a message's name, time and words), 9098 room; apart now
/// what is drawn over each other, none. Then a press's room and every row's least height by the native input, 36 with
/// keyboard and mouse and 44 with touch (the user, 2026-10-27: 大屏按最小 36 来设计，不用 44), a sidebar's rows no more
/// 32 high one after another: 4617 room fewer. A ground no control (Ctx::cursor's Arrow: a message's words a hold
/// picks in, a stage, the room round a list's rows): a message's name and time no more parted with its words, 1957
/// room fewer. The same day a profile's models side by side by series, each a row's least height: 45 room fewer.
/// Keys in a row as far apart as makes each a press's room across (@sf.keys_gap: a bar's, the viewer's, the
/// player's, beside 新建对话): 1432 room fewer. A web service's page beside its chat a screen of its own
/// (chat-service-side), what it has as chat-jobs-side has: its tab's close key, the chat's agent's two halves: 5 more.
/// A chat's bar's agent and its station two keys of their own with touch (@sf.tile_split): 132 room fewer. A column's
/// edge pressed only where it is drawn, its line in the middle, as the web's (the user, 2026-10-28: 左右各 6px, 同
/// web; @ui's as_drawn): 41 room fewer. A shared picture's attachments taken out by the composer's ✕ on their corner, not
/// a box to tick on them: 6 room fewer. What was said in a chat besides words beside it a screen of its own
/// (chat-things-side), what chat-letters-side has: its tab's close key, 3 more. A new chat whose station lends its files
/// (newchat-lend), what newchat has: its station and model chips and its frequent ones, 7 more. The card to share swept
/// (share-card and its looks), over a new chat's composer laid out Medium on a tablet: its chips, 10 more. Medium's
/// tape a tree's nodes, its panels whole where they stand (2026-10-31): what they hold measured there as Large's sidebar
/// is; two rooms meeting, a hair over each other by the layout's rounding, each its own side (thirds of a segmented
/// choice, a policy's options none before); a station's processes' table and a history's lines a row's least high:
/// 256. A narrow page's own head under back: what it does at back's line's end, its name's line its mark and name
/// alone (a profile's, a station's, a connect's ⋯ in the page's corner): 28 room fewer, 228.)
let rooms_known : Map[String, Int] = { "room": 228, "apart": 0, "hover": 0 }

///|
/// What is off its bar in the faults `rooms` (each `at: rule: …`), None where each rule keeps to it.
fn rooms_wrong(rooms : Array[String]) -> String? {
  let counts : Map[String, Int] = {}
  for f in rooms {
    for rule in ["room", "apart", "hover"] {
      if f.contains(": \{rule}: ") {
        counts[rule] = counts.get(rule).unwrap_or(0) + 1
      }
    }
  }
  let off : Array[String] = []
  for rule in ["room", "apart", "hover"] {
    let have = counts.get(rule).unwrap_or(0)
    let known = rooms_known.get(rule).unwrap_or(0)
    if have != known {
      off.push(
        "\{rule}: \{have} faults, \{known} known (" +
        (if have < known {
          "fewer: its bar comes down in rooms_known_wbtest.mbt"
        } else {
          "more than its bar: give it its room (mbui's rooms.mbt says how)"
        }) +
        ")",
      )
    }
  }
  if off.is_empty() {
    return None
  }
  println(rooms.join("\n"))
  Some("the rules of a press's room off their bars:\n  " + off.join("\n  "))
}
