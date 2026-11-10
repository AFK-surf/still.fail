// Which of the released app's ways a trace's run did not have yet (sfcore's trace_switches): its replay does as its
// run's app did, so a trace without one tests what no device does any more. Counted for every trace a flow reads
// (flows/trace_switches_test.mbt holds each switch to its bar); a trace recorded again has them all.

///|
/// The switches each replay reads (sfcore's trace_switches), as they are said there.
pub fn trace_switches() -> Array[String] {
  @sfcore.trace_switches
}

///|
/// Which of sfcore's trace_switches `trace` (a trace's text) does not say its run's app had on.
pub fn switches_off(trace : String) -> Array[String] {
  let env : Map[String, String] = {}
  for kv in @core.Replay::parse(trace).env() {
    env[kv.0] = kv.1
  }
  @sfcore.trace_switches.filter(fn(name) { env.get(name) != Some("1") })
}
