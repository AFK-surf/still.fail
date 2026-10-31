// The spacing rules (mbui's Tester::gap_faults, gaps.mbt: 1 what lights up apart, 2 neighbours of a kind equally
// apart, 3 blocks never at 0 or over each other, 4 what a box with a ground holds in from its edges and as far from
// both sides, 5 a column's blocks on one edge, 6 neighbours a step of the spacing scale apart, 7 a row that lights up
// across what holds it the theme's lit_reach in from its edges) on the same screens and windows
// the corner rule is held on (corners_wbtest.mbt, each screen opened once for both). Each rule's faults, all screens
// in all windows in a language, keep to the bar here: one more fails, and one less until the bar comes down to it.
// Every fault is printed (`at: rule n: …`) when a count is off its bar.

///|
/// The faults each rule still has, in each language: they only fall (rule 4's two more with files-add-folder swept, its
/// files' bar a phone's and a tablet's as the drive's other screens have it; seven fewer with a chat shared as a
/// picture under the bar a file opened has, no more a pill of its own holding a button; eight fewer with a settings
/// page opened on the tape the one in use, whole in the window; one with a memory page's bar the frame's; rule 5's last with an agent's
/// picture in its line on the messages' pictures' edge; rule 4's four more with 共享调试's lent states swept, the
/// settings' bar they share with settings-adb; eight fewer with every row one least height, 36 with keyboard and mouse,
/// a sidebar's rows no more 32 high, and words at a capsule's end held by their box, not as a mark by their middle; one
/// more with newchat-lend swept, a phone's new chat's bar newchat has too; one more with settings-profiles-monthly swept,
/// a phone's profiles' bar settings-profiles has too; one more with player-failed swept, the player's bar its
/// other screens have).
let gaps_known : Map[String, Int] = {
  "zh rule 1": 0,
  "zh rule 2": 0,
  "zh rule 3": 0,
  "zh rule 4": 76,
  "en rule 1": 0,
  "en rule 2": 0,
  "en rule 3": 0,
  "en rule 4": 76,
  "zh rule 5": 0,
  "en rule 5": 0,
  "zh rule 6": 0,
  "en rule 6": 0,
  "zh rule 7": 0,
  "en rule 7": 0,
}

///|
/// What is off its bar in `lang`'s faults `gaps` (each `at: rule n: …`), None where each rule keeps to it.
fn gaps_wrong(lang : String, gaps : Array[String]) -> String? {
  let counts : Map[String, Int] = {}
  for f in gaps {
    for rule in ["rule 1", "rule 2", "rule 3", "rule 4", "rule 5", "rule 6", "rule 7"] {
      if f.contains(": \{rule}: ") {
        counts["\{lang} \{rule}"] = counts.get("\{lang} \{rule}").unwrap_or(0) + 1
      }
    }
  }
  let off : Array[String] = []
  for rule in ["rule 1", "rule 2", "rule 3", "rule 4", "rule 5", "rule 6", "rule 7"] {
    let key = "\{lang} \{rule}"
    let have = counts.get(key).unwrap_or(0)
    let known = gaps_known.get(key).unwrap_or(0)
    if have != known {
      off.push(
        "\{key}: \{have} faults, \{known} known (" +
        (if have < known {
          "fewer: its bar comes down in gaps_known_wbtest.mbt"
        } else {
          "more than its bar: stand them apart (mbui's gaps.mbt says how)"
        }) +
        ")",
      )
    }
  }
  if off.is_empty() {
    return None
  }
  println(gaps.join("\n"))
  Some("the spacing rules off their bars:\n  " + off.join("\n  "))
}
