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
/// screen there has: its rows 32 high, 34 apart. The same day the pages' rows the library's: 2 apart fewer.)
let rooms_known : Map[String, Int] = { "room": 2548, "apart": 7247, "hover": 28 }

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
