// How many traces a flow reads still replay without each of the released app's ways that a replay takes from its
// trace's head (sfcore's trace_switches, @sfreplay.switches_off): such a replay, and what topic_bytes counts of it,
// is of an app no device runs any more. Counted as the check first ran (2026-11-10): MBUI_PLACES_AHEAD (#5142) off
// in 80 of the 81 (settings-run-settings recorded again in #5186). Each bar only falls: a trace recorded again
// brings it down, and a switch none is without any more goes (from sfcore and from the replay's source: the app's way
// is then every replay's). The user, 2026-11-10: 「加录像开关检查」.
//
// Where a way a switch keeps for old traces is itself taken out of the app as wrong (not only followed by a newer
// one), there is no old way left to replay those that had it on: a new switch takes the old one's place, the traces
// that had the old one on are recorded again with the new, and the old switch goes with its bar. So MBUI_PLACES_BAR
// (#5227) in the place of MBUI_PLACES_AHEAD, whose read-ahead worked out frame by frame was taken out: its one trace
// on (settings-run-settings) recorded again, the other 80 never had either.
//
// MBUI_STATION_ROWS (the stations a row each, `station`, `stationPart`), in all 81 as it came: unlike MBUI_PLACES_BAR
// the app does not branch on it, its old way of asking the stations (whole, `brief`, `drive`) gone from it. Only the
// replay reads it: a trace without it has its run's `stations` kept by the replay (@core.Replay::keep_stations) and the
// app's new asks read out of them (sfreplay's source.mbt), so its replay is of today's app, its asks of the stations
// aside; its bytes (topic_bytes) are still the old app's.
//
// MBUI_CONNECT_ROWS (the connects a row each, `connect`, `connectCandidates`), in all 81 as it came, as
// MBUI_STATION_ROWS: only the replay reads it, which reads the app's `connect` and `connectCandidates` out of the run's
// `connects {scope, mine:false}` (sfreplay's source.mbt).

///|
/// Each switch: how many traces may replay without it.
/// MBUI_DEVICES (#5232, 2026-11-10: the stations' places and pages ask for the workspace's devices) off in all 81 as
/// it came.
/// MBUI_HAVE_SAME (2026-11-11: what the places open on kept as it is let go of, asked again with its version) off in
/// all 81 as it came, to be recorded again.
/// MBUI_OUTLINE (对话目录, 2026-11-10: an open chat's page wide enough for its rail of ticks, and its outline's panel,
/// ask for its outline) off in all 81 as it came.
/// MBUI_KEEP_CHAT (2026-11-11: a chat kept as it is let go of, the last few, asked again with its version) off in all
/// 81 as it came: none had been recorded with MBUI_HAVE_SAME on either.
/// MBUI_CHAT_ROW (2026-11-11: a row of the chats' lists what it draws, what a press, a hold, a swipe or a pointer reads
/// of it its chat's whole row, `chatRow`) off in all 81 as it came: as MBUI_CONNECT_ROWS, only the replay reads it,
/// which reads the app's `chatRow` out of the run's chats' list, whose rows were whole.
/// MBUI_CHATS_WINDOW (2026-11-11: a chats' list asked without a `limit`, how many of its rows go out its window, told
/// the core before it is asked and raised as it is scrolled) off in all 81 as it came: only the replay reads it, which
/// answers the app's list by the run's asked with its first limit and tells the run no window.
/// MBUI_MARKS_ONE (2026-11-12: the workspaces' marks one topic whichever workspace is shown) off in all 81 as it came:
/// only the replay reads it, which answers the app's marks by the run's, asked of the workspace then shown.
/// MBUI_PROFILE_ROWS (2026-11-12: an account a row each in the accounts' list, one account whole its pages' own
/// `profile`) off in all 81 as it came: as MBUI_CONNECT_ROWS, only the replay reads it, which reads the app's rows and
/// `profile` out of the run's `profiles {scope}`, whose items were whole.
/// MBUI_HOME_SAME (2026-11-12: Home's own lists kept as they are let go of, as the places' are) off in all 81 as it
/// came.
/// MBUI_SWITCH_AHEAD (2026-11-14: a choice that switches what its page reads asks ahead of the switch, sfbase's
/// switch_answered: 用量's days and split, a station's page's parts) off in all 81 as it came.
let switches_known : Map[String, Int] = {
  "MBUI_PLACES_BAR": 72,
  "MBUI_DEVICES": 73,
  "MBUI_STATION_ROWS": 73,
  "MBUI_HAVE_SAME": 73,
  "MBUI_OUTLINE": 73,
  "MBUI_CONNECT_ROWS": 73,
  "MBUI_KEEP_CHAT": 73,
  "MBUI_CHAT_ROW": 74,
  "MBUI_CHATS_WINDOW": 74,
  "MBUI_MARKS_ONE": 74,
  "MBUI_PROFILE_ROWS": 81,
  "MBUI_HOME_SAME": 81,
  "MBUI_SWITCH_AHEAD": 81,
}

///|
test "the released app's ways a replay takes from its trace: how many traces are without each, within its bar" {
  let off : Map[String, Array[String]] = Map([])
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
