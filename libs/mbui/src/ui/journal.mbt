// What the window's thread did, piece by piece, and the hangs found in it after (GPUI's foreground journal and hang
// detection: zed's crates/gpui/src/profiler/journal.rs, hang.rs). Each event from outside (view_event_said), each
// frame's work, its presenting and what follows it (on_frame) is put into a ring of the last `journal_cap` as it ends;
// pieces shorter than `journal_floor_ms` folded into one, their count and work kept. What is between two boundaries is
// an interval, and the boundaries are what happened, never how long it was: a frame presented, the thread idle with
// no frame asked for, the app hidden. As an interval is closed it is looked over: one piece of work at least
// `hang_stall_ms` long, the work a presented frame waited on at least the frame's budget (`probe_slow_ms`), or, closed
// with no frame, one piece at least the budget long, is a hang (Hang), said on the log, into the device's performance
// record, and to whoever the app has listen (hangs_told).
//
// Recorded, never judged: nothing here is read by what the app does, asks for a frame or reads a signal. It is timed
// by the work's clock (work_now): a Tester's is its own and still within a frame, so what it runs takes no time and
// finds no hang unless a test gives it a clock (set_work_clock). What it keeps of a piece is its kind, never what it
// carried (no key, no words, no message of the core's), and of a frame's why the code it names alone (journal_places).
// What the app shows it is told as that changes (journal_shows), a name it does not read: a hang says the one shown as
// its interval was sealed, the summary its counts by the name shown as each was counted.

///|
/// One piece of the window's thread's work.
#derive(Eq, Debug)
pub(all) enum Done {
  /// an event from outside handled (view_event_said's `what`): its kind alone
  Event(String)
  /// a frame's work up to presenting it (on_frame)
  Frame(FrameDone)
  /// the frame handed to the host to show (h_present, the shots read back, images let go)
  Present
  /// what the frame did after it was presented (the probe, a scripted run's step, what ends with the frame)
  FrameEnd
  /// pieces each shorter than `journal_floor_ms`, folded: how many, their work summed (ms)
  Small(Int, Double)
}

///|
/// A frame's work up to presenting it, by part (ms on the work clock): the window's tree brought, the messages from
/// outside handed on, its builds, its layout, its paint; the nodes built and instances drawn; what it was drawn for
/// (built, painted or looks, and the code that asked: journal_places), said only of a frame at least the budget long.
#derive(Eq, Debug)
pub(all) struct FrameDone {
  tree : Double
  messages : Double
  build : Double
  layout : Double
  paint : Double
  nodes : Int
  insts : Int
  /// what the window's tree did since the frame before (its Work's counts, an input's handler's between them too):
  /// nodes made and let go, nodes laid out, words measured
  made : Int
  let_go : Int
  laid : Int
  measured : Int
  why : String
}

///|
/// A piece of work and when it began and ended (ms on the work clock); of folded pieces, the first one's beginning and
/// the last one's end.
#derive(Eq, Debug)
pub(all) struct Worked {
  what : Done
  start : Double
  end : Double
  /// what it went on, by part (@hostapi.work_part: where it was made, ms summed), the longest first, each 1 ms in all at
  /// least, at most `journal_notes_kept`
  notes : Array[(String, Double)]
}

///|
pub fn Worked::ms(self : Worked) -> Double {
  match self.what {
    Small(_, ms) => ms
    _ => self.end - self.start
  }
}

///|
/// What closed an interval.
#derive(Eq, Debug)
pub(all) enum Seal {
  /// a frame presented
  Presented
  /// the thread done with nothing asked of the display: no frame asked for, none moving
  Idle
  /// the app no longer shown (on_app_state): no frame comes until it is again
  Hidden
}

///|
/// What the journal keeps, oldest first (journal).
#derive(Eq, Debug)
pub(all) enum Entry {
  Work(Worked)
  Boundary(Seal, Double)
}

///|
/// Which rule found a hang.
#derive(Eq, Debug)
pub(all) enum HangTrigger {
  /// one piece of work at least `hang_stall_ms` long
  Stall
  /// a presented frame whose work, with what came before it since it was asked for, took longer than its budget
  LateFrame
  /// an interval closed with no frame, one piece of it at least the budget long
  Blocking
}

///|
/// An interval with a hang in it: the rule, what closed it, whether no frame had been presented before it (the app
/// starting); from what it waited on to its end (ms on the work clock: from the frame's asking, or the first piece that
/// made it one); its longest piece, its work in all, its pieces (folded ones apart), the journal's lost under it (its
/// beginning overwritten before it closed: no budget is judged then), what made it a hang, the longest first, at most
/// `hang_contributors_kept`, and how many more there were; what the app said it showed as the interval was sealed
/// (journal_shows: "" none said yet).
#derive(Eq, Debug)
pub(all) struct Hang {
  trigger : HangTrigger
  page : String
  /// how the app laid out what it showed then and the window's size in points (journal_arranged: "" and 0 none said)
  arranged : String
  window_w : Double
  window_h : Double
  sealed_by : Seal
  startup : Bool
  start : Double
  end : Double
  stall_ms : Double
  work_ms : Double
  pieces : Int
  small : Int
  small_ms : Double
  lost : Int
  contributors : Array[Worked]
  elided : Int
}

///|
/// What the app did while it was shown, said as it is hidden (hang_summary_told): from its first work after it was
/// last hidden to now (ms on the work clock), its work in all, its frames presented, its hangs by rule; its frames
/// counted by how long each waited (journal_seal's `waited`, a hang's measure, so those under the budget too): in
/// the bands `frame_band_ms` bounds (below 4 ms, 4 to 8, ... , 24 and over: one more than the bounds), four times
/// over, by whether a finger's move was handled since the frame before and whether the window's tree laid anything
/// out for it (`still`, `still_laid`, `moved`, `moved_laid`, each frame in one). Frames whose interval the journal
/// lost the beginning of are in none. `by_page`: of the frames presented, stalls, late frames and blocking, those
/// counted while each name the app said it showed was (journal_shows; "" before it said one), in the order the names
/// were said: they add up to the four counts above.
#derive(Eq, Debug)
pub(all) struct HangSummary {
  shown_ms : Double
  work_ms : Double
  frames : Int
  stalls : Int
  late : Int
  blocking : Int
  still : Array[Int]
  still_laid : Array[Int]
  moved : Array[Int]
  moved_laid : Array[Int]
  by_page : Array[(String, Int, Int, Int, Int)]
}

///|
/// The bounds (ms) of the bands a presented frame is counted in by what it waited on (HangSummary): 120, 90 and 60
/// frames a second's budgets fall in the second, third and fifth.
let frame_band_ms : FixedArray[Double] = [4.0, 8.0, 12.0, 16.0, 24.0]

///|
/// Which of frame_band_ms's bands a wait of `w` ms is in, its bounds written out: every frame is counted, and reads
/// no array for it (journal_wbtest holds the two to each other).
fn frame_band(w : Double) -> Int {
  if w < 4.0 {
    0
  } else if w < 8.0 {
    1
  } else if w < 12.0 {
    2
  } else if w < 16.0 {
    3
  } else if w < 24.0 {
    4
  } else {
    5
  }
}

///|
let journal_cap : Int = 1024

///|
/// Work shorter than this is folded (Done::Small).
let journal_floor_ms : Double = 1.0

///|
/// One piece of work this long is a hang whatever it was.
let hang_stall_ms : Double = 50.0

///|
let hang_contributors_kept : Int = 8

///|
let hangs_kept_most : Int = 16

///|
/// How many of what a piece went on are kept with it (Worked's `notes`).
let journal_notes_kept : Int = 4

///|
/// What the piece being done went on so far (@hostapi.work_part), by where it was made: its ms summed.
// kept across runs: emptied as each piece is kept (journal_work) and as a run begins (journal_reset)
let journal_notes : Map[String, Double] = Map([])

///|
// kept across runs: put back as a run begins (journal_reset)
let journal_ring : FixedArray[Entry] = FixedArray::make(journal_cap, Boundary(Idle, 0.0))

///|
/// How many entries were ever put into the ring, and the first of the interval still open.
// kept across runs: put back as a run begins (journal_reset)
let journal_at : FixedArray[Int] = FixedArray::make(2, 0)

///|
/// The pieces folded since the last kept: how many, their work, the first's beginning, the last's end.
// kept across runs: put back as a run begins (journal_reset)
let journal_small : FixedArray[Double] = FixedArray::make(4, 0.0)

///|
/// When the frame the open interval waits on was first asked for (-1: none asked).
// kept across runs: put back as a run begins (journal_reset)
let journal_dirty_at : Ref[Double] = Ref(-1.0)

///|
/// A frame asked for as the frame now running was drawn: the next one is waited on from its presenting.
// kept across runs: put back as a run begins (journal_reset)
let journal_asked : Ref[Bool] = Ref(false)

///|
/// The app hidden by the event being handled: the interval closed as it ends.
// kept across runs: put back as a run begins (journal_reset)
let journal_hidden : Ref[Bool] = Ref(false)

///|
/// Whether a frame has been presented (a hang before it is the app starting).
// kept across runs: put back as a run begins (journal_reset)
let journal_presented : Ref[Bool] = Ref(false)

///|
/// The last hangs found, oldest first.
// kept across runs: put back as a run begins (journal_reset)
let hangs_found : Array[Hang] = []

///|
/// The summary's counts since the app was last hidden: frames, stalls, late frames, blocking; its work; its first
/// work's beginning (-1: none yet).
// kept across runs: put back as a run begins (journal_reset)
// (its first work none yet as the program starts too: a device's first summary counted from 0 on its clock before)
let journal_counts : FixedArray[Double] = [0.0, 0.0, 0.0, 0.0, 0.0, -1.0]

///|
/// The frames presented since the app was last hidden, by band (frame_band_ms's, and one over), four times over:
/// still, still and laid out, moved, moved and laid out (HangSummary).
// kept across runs: put back as a run begins (journal_reset), emptied as the app is hidden (journal_said_shown)
let journal_bands : FixedArray[Int] = FixedArray::make(4 * (frame_band_ms.length() + 1), 0)

///|
/// A finger's move was handled in the interval still open.
// kept across runs: put back as a run begins (journal_reset) and as each interval closes (journal_seal)
let journal_moved : Ref[Bool] = Ref(false)

///|
/// The window's tree laid something out for the frame of the interval still open.
// kept across runs: put back as a run begins (journal_reset) and as each interval closes (journal_seal)
let journal_laid : Ref[Bool] = Ref(false)

///|
/// How many names of what the app shows the journal tells apart (journal_shows): one past them is `other`.
let shown_names_most : Int = 32

///|
/// The names the app said it showed since the summary was last said (the one shown now kept), in the order said: a
/// name's slot is its place here and one (0: none said yet; shown_names_most + 1: `other`).
// kept across runs: put back as a run begins (journal_reset), begun again as the summary is said (journal_said_shown)
let shown_names : Array[String] = []

///|
/// The slot of the name shown now (shown_names'), and the name as the app said it.
// kept across runs: put back as a run begins (journal_reset)
let shown_slot : Ref[Int] = Ref(0)

///|
// kept across runs: put back as a run begins (journal_reset)
let shown_said : Ref[String] = Ref("")

///|
/// How the app lays out what it shows and the window's size in points, as it last said (journal_arranged).
// kept across runs: put back as a run begins (journal_reset)
let arranged_said : Ref[(String, Double, Double)] = Ref(("", 0.0, 0.0))

///|
/// The summary's counts by the name shown as each was counted, four a slot (shown_slot's): frames, stalls, late
/// frames, blocking. A frame presented costs one rise of one of them.
// kept across runs: put back as a run begins (journal_reset), emptied as the app is hidden (journal_said_shown)
let shown_counts : FixedArray[Int] = FixedArray::make(4 * (shown_names_most + 2), 0)

///|
/// What the app shows now told, by `name` (a kind, never which: still.fail's sfbase shown_kind), as it changes, never
/// asked each frame: a hang says the one shown as its interval is sealed, the summary counts by it. Past
/// `shown_names_most` names since the summary was last said, `other`.
pub fn journal_shows(name : String) -> Unit {
  shown_said.val = name
  shown_slot.val = shown_slot_of(name)
}

///|
/// How the app lays out what it shows (`name`, of a few the app has: still.fail's 小屏, 中屏, 大屏) and the window's
/// size in points (`w`, `h`), told as either changes, never asked each frame: a hang says them as its interval is
/// sealed, so one can be made again in a Tester's window of that size (the hang reports' `why` alone did not say
/// which, 2026-11-14).
pub fn journal_arranged(name : String, w : Double, h : Double) -> Unit {
  arranged_said.val = (name, w, h)
}

///|
fn shown_slot_of(name : String) -> Int {
  if name == "" {
    return 0
  }
  for i, n in shown_names {
    if n == name {
      return i + 1
    }
  }
  if shown_names.length() >= shown_names_most {
    return shown_names_most + 1
  }
  shown_names.push(name)
  shown_names.length()
}

///|
/// The name of what the app shows now as the journal keeps it (journal_shows; `other` past its most; "" none said):
/// what its hangs and summary say, the device's performance record too.
pub fn journal_shown() -> String {
  shown_name(shown_slot.val)
}

///|
fn shown_name(slot : Int) -> String {
  if slot == 0 {
    ""
  } else if slot > shown_names_most {
    "other"
  } else {
    shown_names[slot - 1]
  }
}

///|
/// The summary's counts by name (HangSummary's `by_page`): each slot counted, in their order ("" first, `other` last).
fn shown_by_page() -> Array[(String, Int, Int, Int, Int)] {
  let out = []
  for slot in 0..<(shown_names_most + 2) {
    let at = slot * 4
    let (f, s, l, b) = (shown_counts[at], shown_counts[at + 1], shown_counts[at + 2], shown_counts[at + 3])
    if f + s + l + b > 0 {
      out.push((shown_name(slot), f, s, l, b))
    }
  }
  out
}

///|
// kept across runs: an app's main sets it once; put back as a run begins (journal_reset)
let hang_tell : Ref[((Hang) -> Unit)?] = Ref(None)

///|
// kept across runs: an app's main sets it once; put back as a run begins (journal_reset)
let hang_summary_tell : Ref[((HangSummary) -> Unit)?] = Ref(None)

///|
/// `f` told each hang as it is found (None: no one), after the work it was found in, outside any build: what an app
/// sends where it sends its reports (still.fail's src/stillfail/reports.mbt).
pub fn hangs_told(f : ((Hang) -> Unit)?) -> Unit {
  hang_tell.val = f
  journal_listens()
}

///|
/// `f` told what the app did while it was shown as it is hidden (HangSummary): hangs per hour shown.
pub fn hang_summary_told(f : ((HangSummary) -> Unit)?) -> Unit {
  hang_summary_tell.val = f
}

///|
fn journal_reset() -> Unit {
  journal_ring.fill(Boundary(Idle, 0.0))
  journal_at.fill(0)
  journal_small.fill(0.0)
  journal_dirty_at.val = -1.0
  journal_asked.val = false
  journal_hidden.val = false
  journal_presented.val = false
  hangs_found.clear()
  journal_counts.fill(0.0)
  journal_counts[5] = -1.0
  journal_bands.fill(0)
  journal_moved.val = false
  journal_laid.val = false
  hang_tell.val = None
  hang_summary_tell.val = None
  journal_notes.clear()
  journal_tree_work.val = (0, 0, 0, 0)
  shown_names.clear()
  shown_slot.val = 0
  shown_said.val = ""
  arranged_said.val = ("", 0.0, 0.0)
  shown_counts.fill(0)
  journal_listens()
}

///|
/// What a piece goes on told the journal by what runs it (@hostapi.work_part), on its clock: as a run begins and as an
/// app listens for its hangs.
fn journal_listens() -> Unit {
  @hostapi.work_noted_by(
    Some((work_now, fn(what, ms) { journal_notes[what] = journal_notes.get(what).unwrap_or(0.0) + ms })),
  )
}

///|
/// What the journal holds, oldest first: the last `journal_cap` entries.
pub fn journal() -> Array[Entry] {
  let n = journal_at[0]
  let from = if n > journal_cap { n - journal_cap } else { 0 }
  Array::makei(n - from, fn(i) { journal_ring[(from + i) % journal_cap] })
}

///|
/// The last hangs found, oldest first (at most `hangs_kept_most`).
pub fn hangs() -> Array[Hang] {
  hangs_found.copy()
}

///|
fn journal_put(e : Entry) -> Unit {
  journal_ring[journal_at[0] % journal_cap] = e
  journal_at[0] += 1
}

///|
fn journal_flush_small() -> Unit {
  if journal_small[0] > 0.0 {
    journal_put(
      Work({
        what: Small(journal_small[0].to_int(), journal_small[1]),
        start: journal_small[2],
        end: journal_small[3],
        notes: [],
      }),
    )
    journal_small.fill(0.0)
  }
}

///|
/// A piece of work done from `start` to `end`: kept, or folded where it is short and of a kind that comes often (an
/// event, what follows a frame).
fn journal_work(what : Done, start : Double, end : Double) -> Unit {
  if journal_counts[5] < 0.0 {
    journal_counts[5] = start
  }
  journal_counts[4] += end - start
  // (what it went on, the longest first)
  // (a part 1 ms in all at least: its pieces summed by where it was made, each as short as work_part tells)
  let notes = if journal_notes.is_empty() {
    []
  } else {
    let all = journal_notes.to_array().filter(fn(n) { n.1 >= journal_floor_ms })
    journal_notes.clear()
    all.sort_by(fn(a, b) { b.1.compare(a.1) })
    if all.length() > journal_notes_kept {
      all[:journal_notes_kept].to_owned()
    } else {
      all
    }
  }
  let foldable = match what {
    Event(_) | FrameEnd => true
    _ => false
  }
  if foldable && end < start + journal_floor_ms {
    if journal_small[0] == 0.0 {
      journal_small[2] = start
    }
    journal_small[0] += 1.0
    journal_small[1] += end - start
    journal_small[3] = end
    return
  }
  journal_flush_small()
  journal_put(Work({ what, start, end, notes }))
}

///|
/// A frame asked of the host (h_request_frame, h_frame_owed, h_request_frame_on): the open interval waits on it.
fn journal_wants() -> Unit {
  if frame_running.val {
    journal_asked.val = true
  } else if journal_dirty_at.val < 0.0 {
    journal_dirty_at.val = work_now()
  }
}

///|
/// An event from outside, the outermost, handled from `start` to now: kept, and where it left no frame asked for, the
/// interval closed (idle; hidden where it hid the app).
fn journal_event(what : String, start : Double) -> Unit {
  let end = work_now()
  if what == "touch-move" {
    journal_moved.val = true
  }
  journal_work(Event(what), start, end)
  if journal_hidden.val {
    journal_hidden.val = false
    journal_dirty_at.val = -1.0
    journal_seal(Hidden, end)
    journal_said_shown(end)
  } else if journal_dirty_at.val < 0.0 {
    journal_seal(Idle, end)
  }
}

///|
/// A frame's work from `tw` (its tree brought) and its own from `t0`, presented from `t3` to `t4`: kept, and the
/// interval closed by it.
fn journal_frame(c : Ctx, tw : Double, t0 : Double, t3 : Double, t4 : Double) -> Unit {
  let why = if t3 - tw < probe_slow_ms {
    ""
  } else if built_why.val != "" {
    "built" + journal_places(built_why.val)
  } else if painted_why.val != "" {
    "painted" + journal_places(painted_why.val)
  } else {
    "looks" + journal_places(looks_why())
  }
  let msgs = probe_msgs_ms.val
  // (what the window's tree did since the frame before: its counts now less those kept then)
  let now = match view_app.val {
    Some(tree) => {
      let w = tree.work()
      (w.made, w.let_go, w.laid, w.measured)
    }
    None => (0, 0, 0, 0)
  }
  let was = journal_tree_work.val
  journal_tree_work.val = now
  journal_laid.val = journal_since(now.2, was.2) > 0
  journal_work(
    Frame({
      tree: t0 - tw,
      messages: msgs,
      build: c.t_build - msgs,
      layout: c.t_layout,
      paint: c.t_paint,
      nodes: c.count,
      insts: c.ninst,
      made: journal_since(now.0, was.0),
      let_go: journal_since(now.1, was.1),
      laid: journal_since(now.2, was.2),
      measured: journal_since(now.3, was.3),
      why,
    }),
    tw,
    t3,
  )
  journal_work(Present, t3, t4)
  journal_counts[0] += 1.0
  shown_counts[shown_slot.val * 4] += 1
  journal_seal(Presented, t4)
  journal_presented.val = true
  journal_dirty_at.val = -1.0
}

///|
/// The window's tree's counts as the last frame was kept (journal_frame): nodes made, let go, laid out, words measured.
// kept across runs: put back as a run begins (journal_reset), written as each frame is kept
let journal_tree_work : Ref[(Int, Int, Int, Int)] = Ref((0, 0, 0, 0))

///|
/// A count's rise since it was `was`: all of it where it is below (another tree in the first's place counts from 0).
fn journal_since(now : Int, was : Int) -> Int {
  if now >= was { now - was } else { now }
}

///|
/// The frame presented at `t4` ended now: what it did after kept; a frame asked for as it ran waited on from its
/// presenting, else the thread idle.
fn journal_frame_ended(t4 : Double) -> Unit {
  let end = work_now()
  journal_work(FrameEnd, t4, end)
  if journal_asked.val {
    journal_asked.val = false
    if journal_dirty_at.val < 0.0 {
      journal_dirty_at.val = t4
    }
  } else if journal_dirty_at.val < 0.0 {
    journal_seal(Idle, end)
  }
}

///|
/// The open interval closed by `seal` at `at`, looked over for a hang.
fn journal_seal(seal : Seal, at : Double) -> Unit {
  journal_flush_small()
  let from = journal_at[1]
  let to = journal_at[0]
  // (the ring keeps the last journal_cap: what of the interval is older is lost)
  let first = if to - from > journal_cap { to - journal_cap } else { from }
  let lost = first - from
  let dirty = journal_dirty_at.val
  let startup = !journal_presented.val
  let moved = journal_moved.val
  let laid = journal_laid.val
  journal_moved.val = false
  journal_laid.val = false
  journal_put(Boundary(seal, at))
  journal_at[1] = journal_at[0]
  if to == from {
    return
  }
  // (summed first with nothing made, as every frame closes one: what is kept of it only where it is a hang)
  let mut pieces = 0
  let mut small = 0
  let mut small_ms = 0.0
  let mut work = 0.0
  let mut longest = 0.0
  // (what the frame waited on: all since it was asked for, what asked for it too; a frame the host drew of its own,
  // all of the interval)
  let mut waited = 0.0
  let waits = fn(w : Worked) { dirty < 0.0 || w.end >= dirty }
  for i in first..<to {
    match journal_ring[i % journal_cap] {
      Work({ what: Small(k, ms), .. }) => {
        small += k
        small_ms += ms
        work += ms
      }
      Work(w) => {
        pieces += 1
        work += w.ms()
        longest = dmax(longest, w.ms())
        if waits(w) {
          waited += w.ms()
        }
      }
      Boundary(_, _) => ()
    }
  }
  // (a frame presented, counted by what it waited on: every one, a hang or not)
  if seal == Presented && lost == 0 {
    let kind = (if moved { 2 } else { 0 }) + (if laid { 1 } else { 0 })
    journal_bands[kind * 6 + frame_band(waited + small_ms)] += 1
  }
  let trigger = if longest >= hang_stall_ms {
    Stall
  } else if seal == Presented {
    if lost > 0 || waited + small_ms < probe_slow_ms {
      return
    }
    LateFrame
  } else if longest >= probe_slow_ms {
    Blocking
  } else {
    return
  }
  let mut contributors : Array[Worked] = []
  for i in first..<to {
    if journal_ring[i % journal_cap] is Work(w) && !(w.what is Small(_, _)) {
      let made = match trigger {
        Stall => w.ms() >= hang_stall_ms
        LateFrame => waits(w)
        Blocking => w.ms() >= probe_slow_ms
      }
      if made {
        contributors.push(w)
      }
    }
  }
  let mut start = at
  for w in contributors {
    start = dmin(start, w.start)
  }
  if seal == Presented && dirty >= 0.0 {
    start = dmin(start, dirty)
  }
  contributors.sort_by(fn(a, b) { b.ms().compare(a.ms()) })
  let elided = if contributors.length() > hang_contributors_kept {
    contributors.length() - hang_contributors_kept
  } else {
    0
  }
  if elided > 0 {
    contributors = contributors[:hang_contributors_kept].to_owned()
  }
  let hang = {
    trigger,
    page: journal_shown(),
    arranged: arranged_said.val.0,
    window_w: arranged_said.val.1,
    window_h: arranged_said.val.2,
    sealed_by: seal,
    startup,
    start,
    end: at,
    stall_ms: longest,
    work_ms: work,
    pieces,
    small,
    small_ms,
    lost,
    contributors,
    elided,
  }
  let count = match trigger {
    Stall => 1
    LateFrame => 2
    Blocking => 3
  }
  journal_counts[count] += 1.0
  shown_counts[shown_slot.val * 4 + count] += 1
  if hangs_found.length() >= hangs_kept_most {
    hangs_found.remove(0) |> ignore
  }
  hangs_found.push(hang)
  let line = hang.said()
  h_log("HANG " + line)
  @hostapi.perf_line("hang: " + line)
  if hang_tell.val is Some(f) {
    @signals.untracked(fn() { f(hang) })
  }
}

///|
/// The app hidden at `at`: what it did while shown said (hang_summary_told), its counts begun again.
fn journal_said_shown(at : Double) -> Unit {
  let since = journal_counts[5]
  let n = frame_band_ms.length() + 1
  let bands = fn(kind : Int) { Array::makei(n, fn(i) { journal_bands[kind * n + i] }) }
  let summary = {
    shown_ms: if since < 0.0 { 0.0 } else { at - since },
    work_ms: journal_counts[4],
    frames: journal_counts[0].to_int(),
    stalls: journal_counts[1].to_int(),
    late: journal_counts[2].to_int(),
    blocking: journal_counts[3].to_int(),
    still: bands(0),
    still_laid: bands(1),
    moved: bands(2),
    moved_laid: bands(3),
    by_page: shown_by_page(),
  }
  journal_counts.fill(0.0)
  journal_counts[5] = -1.0
  journal_bands.fill(0)
  shown_counts.fill(0)
  // (the names begun again, the one shown now first: a long run's names past the most are told apart again)
  shown_names.clear()
  shown_slot.val = shown_slot_of(shown_said.val)
  if hang_summary_tell.val is Some(f) {
    @signals.untracked(fn() { f(summary) })
  }
}

///|
/// Of what a frame's why says (frame_watch.mbt's built_why, painted_why, looks_why), the code it names alone
/// (`….mbt:line…`, at most 4, each once), each after a space: no key of a motion, a row or a page, which may carry an
/// id of what is shown.
fn journal_places(why : String) -> String {
  let out : Array[String] = []
  let word = StringBuilder()
  let take = fn(w : String) {
    if w.contains(".mbt:") && !out.contains(w) && out.length() < 4 {
      out.push(w)
    }
  }
  for ch in why {
    if ch.is_ascii_alphabetic() || ch.is_ascii_digit() || ch == '_' || ch == '.' || ch == '/' || ch == ':' || ch == '-' || ch == '@' {
      word.write_char(ch)
    } else {
      take(word.to_string())
      word.reset()
    }
  }
  take(word.to_string())
  out.map(fn(w) { " " + w }).join("")
}

///|
fn journal_ms(x : Double) -> Double {
  (x * 10.0).round() / 10.0
}

///|
fn Seal::name(self : Seal) -> String {
  match self {
    Presented => "presented"
    Idle => "idle"
    Hidden => "hidden"
  }
}

///|
fn HangTrigger::name(self : HangTrigger) -> String {
  match self {
    Stall => "stall"
    LateFrame => "late_frame"
    Blocking => "blocking"
  }
}

///|
fn Done::name(self : Done) -> String {
  match self {
    Event(what) => what
    Frame(_) => "frame"
    Present => "present"
    FrameEnd => "frame-end"
    Small(_, _) => "small"
  }
}

///|
/// A piece of work in a few words: its kind and ms, a frame's parts and why.
fn Worked::said(self : Worked) -> String {
  let head = "\{self.what.name()} \{journal_ms(self.ms())}ms"
  match self.what {
    Frame(f) =>
      head +
      " (tree=\{journal_ms(f.tree)} msgs=\{journal_ms(f.messages)} build=\{journal_ms(f.build)} layout=\{journal_ms(f.layout)} paint=\{journal_ms(f.paint)} nodes=\{f.nodes} insts=\{f.insts}" +
      (if f.why != "" { " " + f.why } else { "" }) +
      ")" +
      self.notes_said()
    _ => head + self.notes_said()
  }
}

///|
/// What it went on, in a few words (" on part 12ms, …"); "" none.
fn Worked::notes_said(self : Worked) -> String {
  if self.notes.is_empty() {
    ""
  } else {
    " on " + self.notes.map(fn(n) { "\{n.0} \{journal_ms(n.1)}ms" }).join(", ")
  }
}

///|
/// The hang in a line (the log's `HANG`, the performance record's `hang:`): its rule, what closed it, what the app
/// showed (none said: not said), its times, what made it one, the longest first.
pub fn Hang::said(self : Hang) -> String {
  let active = self.end - self.start
  let busy = if active > 0.0 { (dmin(self.work_ms / active, 1.0) * 100.0).round() } else { 100.0 }
  "trigger=\{self.trigger.name()} sealed=\{self.sealed_by.name()} phase=\{if self.startup { "startup" } else { "steady" }} " +
  (if self.page != "" { "page=\{self.page} " } else { "" }) +
  (if self.arranged != "" { "arranged=\{self.arranged} " } else { "" }) +
  (if self.window_w > 0.0 { "window=\{self.window_w.round()}x\{self.window_h.round()} " } else { "" }) +
  "active=\{journal_ms(active)}ms stall=\{journal_ms(self.stall_ms)}ms work=\{journal_ms(self.work_ms)}ms busy=\{busy}% " +
  "pieces=\{self.pieces} small=\{self.small}/\{journal_ms(self.small_ms)}ms lost=\{self.lost} by: " +
  self.contributors.map(fn(w) { w.said() }).join(" | ") +
  (if self.elided > 0 { " | +\{self.elided}" } else { "" })
}

///|
/// The hang as JSON (what an app sends of it: still.fail's reports.mbt): its times from its start (ms), each
/// contributor its kind, start, ms, and a frame's parts; what the app showed as `page`, how it laid it out as
/// `arranged` and the window's size as `window_w`, `window_h` (none said: no field).
pub fn Hang::json(self : Hang) -> Json {
  let active = self.end - self.start
  let contributors = self.contributors.map(fn(w) {
    let o : Map[String, Json] = {
      "kind": Json::string(w.what.name()),
      "start_ms": Json::number(journal_ms(w.start - self.start)),
      "ms": Json::number(journal_ms(w.ms())),
    }
    if w.notes.length() > 0 {
      o["parts"] = Json::array(
        w.notes.map(fn(n) { Json::object({ "part": Json::string(n.0), "ms": Json::number(journal_ms(n.1)) }) }),
      )
    }
    if w.what is Frame(f) {
      o["tree_ms"] = Json::number(journal_ms(f.tree))
      o["messages_ms"] = Json::number(journal_ms(f.messages))
      o["build_ms"] = Json::number(journal_ms(f.build))
      o["layout_ms"] = Json::number(journal_ms(f.layout))
      o["paint_ms"] = Json::number(journal_ms(f.paint))
      o["nodes"] = Json::number(f.nodes.to_double())
      o["insts"] = Json::number(f.insts.to_double())
      o["made"] = Json::number(f.made.to_double())
      o["let_go"] = Json::number(f.let_go.to_double())
      o["laid"] = Json::number(f.laid.to_double())
      o["measured"] = Json::number(f.measured.to_double())
      o["why"] = Json::string(f.why)
    }
    Json::object(o)
  })
  let o : Map[String, Json] = {
    "trigger": Json::string(self.trigger.name()),
    "sealed_by": Json::string(self.sealed_by.name()),
    "phase": Json::string(if self.startup { "startup" } else { "steady" }),
    "active_ms": Json::number(journal_ms(active)),
    "stall_ms": Json::number(journal_ms(self.stall_ms)),
    "work_ms": Json::number(journal_ms(self.work_ms)),
    "busy_fraction": Json::number(
      if active > 0.0 { (dmin(self.work_ms / active, 1.0) * 100.0).round() / 100.0 } else { 1.0 },
    ),
    "pieces": Json::number(self.pieces.to_double()),
    "small_count": Json::number(self.small.to_double()),
    "small_ms": Json::number(journal_ms(self.small_ms)),
    "lost": Json::number(self.lost.to_double()),
    "contributors": Json::array(contributors),
    "contributors_elided": Json::number(self.elided.to_double()),
  }
  if self.page != "" {
    o["page"] = Json::string(self.page)
  }
  if self.arranged != "" {
    o["arranged"] = Json::string(self.arranged)
  }
  if self.window_w > 0.0 {
    o["window_w"] = Json::number(self.window_w.round())
    o["window_h"] = Json::number(self.window_h.round())
  }
  Json::object(o)
}

///|
/// The summary as JSON (reports.mbt's): its counts by what was shown as `by_page`, each name's [frames, stalls, late
/// frames, blocking] (none said yet: under "").
pub fn HangSummary::json(self : HangSummary) -> Json {
  let by_page : Map[String, Json] = Map([])
  for p in self.by_page {
    by_page[p.0] = journal_counts_json([p.1, p.2, p.3, p.4])
  }
  {
    "shown_ms": Json::number(journal_ms(self.shown_ms)),
    "work_ms": Json::number(journal_ms(self.work_ms)),
    "frames": Json::number(self.frames.to_double()),
    "stalls": Json::number(self.stalls.to_double()),
    "late_frames": Json::number(self.late.to_double()),
    "blocking": Json::number(self.blocking.to_double()),
    "frames_by_ms": {
      "bounds": Json::array(Array::makei(frame_band_ms.length(), fn(i) { Json::number(frame_band_ms[i]) })),
      "still": journal_counts_json(self.still),
      "still_laid": journal_counts_json(self.still_laid),
      "moved": journal_counts_json(self.moved),
      "moved_laid": journal_counts_json(self.moved_laid),
    },
    "by_page": Json::object(by_page),
  }
}

///|
fn journal_counts_json(counts : Array[Int]) -> Json {
  Json::array(counts.map(fn(k) { Json::number(k.to_double()) }))
}
