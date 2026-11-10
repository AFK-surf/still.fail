// How many traces a flow reads still replay without each of the released app's ways that a replay takes from its
// trace's head (sfcore's trace_switches, @sfreplay.switches_off): such a replay, and what topic_bytes counts of it,
// is of an app no device runs any more. Counted as the check first ran (2026-11-10): MBUI_PLACES_AHEAD (#5142) off
// in 80 of the 81 (settings-run-settings recorded again in #5186). Each bar only falls: a trace recorded again
// brings it down, and a switch none is without any more goes (from sfcore and from the replay's source: the app's way
// is then every replay's). The user, 2026-11-10: 「加录像开关检查」.

///|
/// Each switch: how many traces may replay without it.
let switches_known : Map[String, Int] = { "MBUI_PLACES_AHEAD": 80 }

///|
test "the released app's ways a replay takes from its trace: how many traces are without each, within its bar" {
  let off : Map[String, Array[String]] = {}
  let names = @sfreplay.tape_barred()
  names.sort()
  for name in names {
    for s in @sfreplay.switches_off(@sfreplay.trace(name)) {
      match off.get(s) {
        Some(a) => a.push(name)
        None => off[s] = [name]
      }
    }
  }
  let wrong : Array[String] = []
  for s in @sfreplay.trace_switches() {
    let without = off.get(s).unwrap_or([])
    match switches_known.get(s) {
      None =>
        wrong.push(
          "\{s}: \{without.length()} traces replay without it, and it has no bar (say it: (\"\{s}\", \{without.length()}))",
        )
      Some(bar) =>
        if without.length() > bar {
          wrong.push(
            "\{s}: \{without.length()} traces replay without it, its bar \{bar} (more: a trace recorded by an app without it? record it again with scripts/rerecord.sh): " +
            without.join(", "),
          )
        } else if without.length() < bar {
          wrong.push(
            "\{s}: \{without.length()} traces replay without it, its bar \{bar} (fewer: its bar comes down to it" +
            (if without.length() == 0 {
              "; none is without it: the switch goes, from sfcore's trace_switches and the replay's source)"
            } else {
              ")"
            }),
          )
        }
    }
  }
  for s, _ in switches_known {
    if !@sfreplay.trace_switches().contains(s) {
      wrong.push("\{s}: no replay reads it any more (not in sfcore's trace_switches): its bar goes")
    }
  }
  if wrong.length() > 0 {
    fail(wrong.join("\n"))
  }
}
