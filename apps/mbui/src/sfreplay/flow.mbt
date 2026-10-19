// A flow of e2e/flows seen again over the app (source.mbt) with a run's core: the flow's own script as the run had it
// (trace_*.mbt's drive_*), run by the Tester (Tester::drive), the run's conversation with its core given as each frame
// begins, where src/stillfail's frame takes what the core said (@core.pump).
//
// One flow a test process (a package of its own, as src/sfreplay/send_text): the app's pages keep what they were told
// for as long as the process lives (that the core knows the app is in front, a chat's draft read), as the run's app,
// a process of its own, did; a second flow in the same process would start where the first left them, and ask less.

///|
/// `script` run over the app with `trace` as its core: `at_most` of what came given as each frame begins (-1: all
/// that may), the run's calls named in `skip` not waited for (Replay::skip). The replay, the tester, the drive's log.
pub fn run_flow(
  trace : String,
  script : String,
  skip? : Array[String] = [],
  at_most? : Int = -1,
) -> (@core.Replay, @ui.Tester, Array[String]) {
  let r = @core.Replay::parse(trace)
  for call in skip {
    r.skip(call)
  }
  r.attach()
  let t = @ui.Tester::new(fn(c) {
    r.deliver(at_most~) |> ignore
    app(c)
  })
  let log = t.drive(without_shots(script))
  (r, t, log)
}

///|
/// A flow's script without its shots: a Tester has no screen to take, and waits 1.5 s at a shot instead (drive.mbt),
/// where the run went straight on; in such a pause the composer keeps its draft (`draft.put`), as the run never did.
pub fn without_shots(script : String) -> String {
  script.split("\n").filter(fn(l) { !l.has_prefix("shot ") }).map(fn(l) { l.to_string() }).join("\n")
}

///|
/// How long a step of the drive waited before it passed (its `DRIVE ok STEP (N ms)`), -1 if it did not.
pub fn waited(log : Array[String], step : String) -> Int {
  let head = "DRIVE ok " + step + " ("
  for l in log {
    if l.has_prefix(head) {
      let mut n = 0
      for ch in l.view(start_offset=head.length()) {
        if ch >= '0' && ch <= '9' {
          n = n * 10 + (ch.to_int() - '0'.to_int())
        } else {
          return n
        }
      }
    }
  }
  -1
}

///|
/// The screen as laid out (Tester::dump: every node, where it is, its words) in a number (FNV-1a over its UTF-16
/// units): two runs that end the same have the same.
pub fn screen_sum(t : @ui.Tester) -> String {
  let mut h = 0x811c9dc5U
  for ch in t.dump() {
    h = (h ^ ch.to_int().reinterpret_as_uint()) * 0x01000193U
  }
  h.to_string()
}
