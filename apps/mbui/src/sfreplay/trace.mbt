///|
/// A run's trace: e2e/traces/NAME.trace (a line each),
/// read as the test runs. Read, not compiled in: as constants they were every flow test's program's data (17 MB of a
/// test's 25 MB data.c, all 78 traces in each), compiled again for each test and on any change.
pub fn trace(name : String) -> String {
  pass_trace.val = name
  // (a trace a flow plays has its bar of what the core sent for its subscriptions, where the bars are said:
  // topic_bytes.mbt)
  if !tape_bars.is_empty() && !tape_bars.contains(name) {
    @halt.saying(
      "e2e/traces/\{name}.trace has no bar in src/sfreplay/flows/topic_bytes_known_test.mbt: say what its run was sent (the flows' test \"what the core sends…\" prints it)",
    )
  }
  match read_trace(name) {
    Some(t) => {
      // (one recorded without its display's frames is one of those known so, and one with them none of them)
      match (t.contains("{\"frame\":"), frames_unrecorded_known.contains(name)) {
        (false, false) =>
          @halt.saying(
            "e2e/traces/\{name}.trace keeps no {\"frame\":…} lines (its display's frames): record it again (scripts/rerecord.sh)",
          )
        (true, true) =>
          @halt.saying(
            "e2e/traces/\{name}.trace keeps its display's frames now: take it out of frames_unrecorded_known (pace_known.mbt)",
          )
        _ => ()
      }
      t
    }
    None =>
      @halt.saying(
        "no e2e/traces/\{name}.trace (looked under $MBUI_APP_MOD, the module this was built in, and up from here)",
      )
  }
}
