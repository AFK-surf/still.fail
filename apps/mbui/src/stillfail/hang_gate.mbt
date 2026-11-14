// Which of the window thread's hangs are sent (reports.mbt's): in each ten minutes the first `hangs_most` at once, and
// of the rest the heaviest `hangs_most` (a stall before a late frame, the longer first) held and sent as the ten minutes
// end or the app is hidden; how many were sent of none, said with the summary. A phone slow throughout used to send its
// ten minutes' first twenty and nothing after, its stalls among them (2026-11-10: five stalls told by the summary,
// none sent).

///|
/// The ten minutes from `since` (the work clock's ms; below 0 none yet): how many were sent at once, the heaviest of
/// the rest held, and how many were let go since the last summary.
struct HangGate {
  mut since : Double
  mut sent : Int
  held : Array[@ui.Hang]
  mut unsent : Int
}

///|
let hangs_most : Int = 20

///|
let hangs_span_ms : Double = 600000.0

///|
fn HangGate::new() -> HangGate {
  { since: -1.0, sent: 0, held: [], unsent: 0 }
}

///|
/// Whether `a` is heavier than `b`: a stall first, then the longer stall.
fn hang_heavier(a : @ui.Hang, b : @ui.Hang) -> Bool {
  let sa = a.trigger is Stall
  let sb = b.trigger is Stall
  if sa != sb {
    sa
  } else {
    a.stall_ms > b.stall_ms
  }
}

///|
/// Hang `h` found: what is sent now (the held ones first where its ten minutes are new, then it, while fewer than
/// `hangs_most` went at once).
fn HangGate::offer(self : HangGate, h : @ui.Hang) -> Array[@ui.Hang] {
  let out = []
  if self.since < 0.0 || h.end >= self.since + hangs_span_ms {
    out.append(self.held)
    self.held.clear()
    self.since = h.end
    self.sent = 0
  }
  if self.sent < hangs_most {
    self.sent += 1
    out.push(h)
  } else if self.held.length() < hangs_most {
    self.held.push(h)
  } else {
    // (the lightest held let go where `h` is heavier, else `h`)
    let mut light = 0
    for i in 1..<self.held.length() {
      if hang_heavier(self.held[light], self.held[i]) {
        light = i
      }
    }
    if hang_heavier(h, self.held[light]) {
      self.held[light] = h
    }
    self.unsent += 1
  }
  out
}

///|
/// The app hidden (its summary told): the held ones, sent now, and how many were let go since the last summary.
fn HangGate::flush(self : HangGate) -> (Array[@ui.Hang], Int) {
  let out = self.held.copy()
  self.held.clear()
  let unsent = self.unsent
  self.unsent = 0
  (out, unsent)
}
