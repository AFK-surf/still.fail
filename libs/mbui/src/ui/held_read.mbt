// What holds something read with nothing following it: a fault of the reader. A computed whose reads reach a resource
// (a core's subscription, told as its last reader leaves: signals' ReactiveNode `holds`) read with nothing reading it
// and nothing following it (a reaction's `then`, a handler, an `untracked`) keeps what it read linked for good, the
// resource with it, past whatever read it (#6239: a chat's subscription held past its page by its list's at-foot read
// so). The reader is to follow what it reads (a reaction's own tracked read, a binding). Said only under a Tester (the
// hook is a Tester's: signals' held_read_said), once for each place read from and computed read, counted against the
// bar of the file the Tester was made in (`held_read_known`, given by a test package as it starts; only falling):
// `HELD-READ <file> <n>/<bar>: <read from> reads <made at>`, said as each is first found where the counted checks say
// theirs (motion_runs) and kept past a run's tail
// (scripts/test.sh, mbui's and the app's). Counted, nothing stopped: the rule that such a read lets go of what it read
// is not in (signals' Computed::get says why).

///|
/// Each file's bar: how many places reading so a Tester made there finds, as last counted.
// kept across runs: said once as a test program starts (its packages' `init`)
let held_read_bars : Map[String, Int] = Map([])

///|
/// The places reading so that the Tester made last found (read from, the computed read), and its file.
priv struct HeldReads {
  mut file : String
  found : Set[String]
}

///|
// kept across runs: begun anew by each Tester (held_read_begin)
let held_reads : HeldReads = { file: "", found: Set([]) }

///|
/// How many places reading so a Tester made in each file of `bars` finds, as counted (gaps_steady_known's way). Said by
/// a test package as it starts (`fn init`); only falls.
pub fn held_read_known(bars : Array[(String, Int)]) -> Unit {
  for b in bars {
    held_read_bars.set(b.0, b.1)
  }
}

///|
/// A Tester made at `loc` begun: what is read so found from here, told as it is read (signals' held_read_said), where
/// a Tester's run checks it (held_read_checked: not a Wasm program a shell runs, a bench, whose numbers are a device's).
fn held_read_begin(loc : String) -> Unit {
  held_reads.found.clear()
  held_reads.file = match loc.find(":") {
    Some(i) => loc.unsafe_substring(start=0, end=i)
    None => loc
  }
  if !held_read_checked() {
    @signals.held_read_said.val = None
    return
  }
  @signals.held_read_said.val = Some(fn(made, from) {
    held_read_told(made.to_string(), from.map(fn(f) { f.to_string() }))
  })
}

///|
/// A read so told: each place (read from, computed read) once, said with how many its Tester's file has found and its
/// bar.
fn held_read_told(made : String, from : String?) -> Unit {
  let who = from.unwrap_or("?") + " reads " + made
  if held_reads.found.contains(who) {
    return
  }
  held_reads.found.add(who)
  // (said where the other counted checks say theirs, motion_runs: MBUI_TEST_BARS at the default rate, the motion runs;
  // silent otherwise)
  guard motion_runs() else { return }
  let bar = held_read_bars.get(held_reads.file).unwrap_or(0)
  println("HELD-READ \{held_reads.file} \{held_reads.found.length()}/\{bar}: \{who}")
}
