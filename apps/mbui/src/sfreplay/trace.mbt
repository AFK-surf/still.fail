///|
/// A run's trace: e2e/traces/NAME.trace (scripts/trace.py: what the app and its core said in the run, a line each),
/// read as the test runs. Read, not compiled in: as constants they were every flow test's program's data (17 MB of a
/// test's 25 MB data.c, all 78 traces in each), compiled again for each test and on any change.
pub fn trace(name : String) -> String {
  match read_trace(name) {
    Some(t) => t
    None =>
      abort(
        "no e2e/traces/\{name}.trace (looked under $MBUI_APP_MOD, the module this was built in, and up from here)",
      )
  }
}
