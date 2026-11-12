// Every screen opened on a workspace of real size (src/sfrealsize: what the core sends each topic on the owner's
// workspace as their phone reported it, 2026-11-10), and the most one frame of its opening did (mbui's journal, a
// frame's FrameDone): nodes of the window's tree made, nodes laid out, words measured. The screens' own fixture is a
// few rows of each thing; a page that makes everything it holds in one frame looks light there and stalls a phone (the
// changelog's 200 changes, a day of them made whole in a frame: the user's 「为啥没检查出来」, 2026-11-11). Each screen's
// counts are held to its bar in real_size_known_wbtest.mbt, which only falls (the user, 2026-11-11: 三条都加): the
// tree's work is counted, never instructions (the user, 2026-11-09).
//
// The workspace is held as a device holds it (@sfrealsize.RealSizeChanging): each topic asked as a device asks the core
// (`compact` on a chat), what the mode puts up over its pages (a sheet, a panel) reading it as the pages do, each
// topic followed as a device's subscription is. So the same opened screen is then given each change of the real
// workspace that reaches a topic it holds (the user, 2026-11-11: 重心转到想办法防止未来劣化). The faults found that day
// were not at opening: a job's sheet let go of and made again its rows for every line its log printed (#5431), a chat
// with a working agent built a frame for every event of its agent's stream that left its line as it was (#5468).
//
// For each way of asking a topic of the real size the screen read and each cause the core's rig has for it
// (src/sfrealsize's c_*.mbt), each of the cause's messages is posted as a device's host posts the core's (taken between
// frames, as what changes only a topic's signal is: @core.receive_said), and the one frame after each is counted: the
// window's tree's nodes made, let go, laid out and words measured, and the old view's (Ctx's) nodes built and laid out
// less those of a frame given nothing on the same screen, taken once just before its first cause: an old view builds
// whole each frame it is built, whatever changed, so what a change costs it is the difference. The cause's count is the
// most of its messages' frames, each of the six. Then the way's value is put back whole and a frame drawn, not
// counted, before the next cause: a screen so given a cause counts as one opened afresh for it (222 rows of chat-job,
// chat-working, home, chat and settings-station measured both ways, 2026-11-11, all the same). A way read more than
// once on a screen (each station's part on a list of stations) is one row, the most of them.
//
// What is the same on every screen is given its changes on one: the shell's lists (`real_size_shell_ways`) on Home, or
// where Home reads none of a way, the first screen that does; the chat page's own topics (`real_size_chat_ways`) on
// the chat's modes about them (`real_size_chat_modes`), not under every sheet and panel over it: given everywhere they
// were 12,398 rows, 10,336 of them zeros, and four times the sweep's time (2026-11-11).
// Each row, "<window> <mode> <way>/<cause>", is held to its bar in real_size_change_known_wbtest.mbt, which only falls:
// more than a tenth over it and by `real_size_change_floor` or more fails, as much under it asks for it to be brought
// down, a row not there fails with the line to write, and one there no longer measured asks for it to be taken out. A
// frame that takes a change and builds nothing is a row of zeros, kept: a change the screen does not show costs
// nothing, and one that comes to cost something fails. Each window is a test of its own, so CI places them apart.

///|
/// The windows: a phone's and a wide desktop's (corner_windows').
let real_size_windows : Array[(String, Double, Double, Int, String)] = [
  ("phone", 360.0, 740.0, 2, ""),
  ("wide", 1280.0, 800.0, 0, ""),
]

///|
/// The ways the shell holds on every screen (the bar's and the rail's lists and a row's own chat, sfpages' chat_row's
/// `chatRow`, the stations, the workspace): the same
/// shell on every screen, so their changes are given on one, Home (or the first screen that reads a way Home does not).
let real_size_shell_ways : Array[String] = [
  "chats", "chatRow", "workspaceMarks", "lock", "stations", "longJobs", "workspace",
]

///|
/// The chat page's own ways: the same chat page under each of its other modes (a sheet, a panel over it), so their
/// changes are given on the chat's modes about them alone (`real_size_chat_modes`).
let real_size_chat_ways : Array[String] = ["chat compact", "live", "chatJobs compact summary", "agentCard", "history", "job"]

///|
/// The chat's modes the chat page's own ways are given their changes on: the chat, an agent at work, a job's sheet, an
/// agent's card, the jobs' sheet.
let real_size_chat_modes : Array[String] = ["chat", "chat-working", "chat-job", "chat-agent", "chat-jobs"]

///|
/// The most one frame of what the journal holds since the Tester began did: made, laid out, measured.
fn real_size_most() -> (Int, Int, Int) {
  let mut most = (0, 0, 0)
  for e in @ui.journal() {
    match e {
      Work({ what: Frame(f), .. }) =>
        most = (
          @cmp.maximum(most.0, f.made),
          @cmp.maximum(most.1, f.laid),
          @cmp.maximum(most.2, f.measured),
        )
      _ => ()
    }
  }
  most
}

///|
/// Whether `n` is over `bar` by more than a tenth of it.
fn real_size_over(n : Int, bar : Int) -> Bool {
  n * 10 > bar * 11
}

///|
/// A difference from its bar under this is no fault, over or under: small counts move by a node or two for causes
/// of no weight (a row's words one longer).
let real_size_change_floor : Int = 8

///|
/// Whether `n` is over `bar` by more than a tenth of it and by the floor.
fn real_size_change_over(n : Int, bar : Int) -> Bool {
  n * 10 > bar * 11 && n - bar >= real_size_change_floor
}

///|
/// What is to be taken as the next frame begins, in order (real_size_change_frame): each the message of a way put.
// kept across runs: emptied by the frame that takes it, each test's posts taken before it ends
let real_size_change_due : Array[() -> Unit] = []

///|
/// The channel the sweep's messages are posted on, taken as they come as the core's are where they change only a
/// topic's signal (src/core/core.mbt `receive_said`, @ui.on_message_said).
let real_size_change_channel : String = "real-size"

///|
fn real_size_change_said() -> Unit {
  @ui.on_message_said(real_size_change_channel, fn(_, _) {
    if real_size_change_due.length() > 0 {
      (real_size_change_due.remove(0))()
    }
    true
  })
}

///|
/// What the frame that takes `put` does: posted as the core's message is, taken as the frame begins, one frame drawn:
/// the window's tree's nodes made, let go, laid out, words measured; the old view's nodes built and laid out.
fn real_size_change_frame(t : @ui.Tester, put : () -> Unit) -> (Int, Int, Int, Int, Int, Int) {
  real_size_change_due.push(put)
  t.tree_frames_from_now()
  t.post(real_size_change_channel, "{}")
  t.frame()
  let old = t.frame_perf()
  let f = t.tree_frames().fold(init=(0, 0, 0, 0), fn(a, x) {
    (a.0 + x.made, a.1 + x.let_go, a.2 + x.laid, a.3 + x.measured)
  })
  (f.0, f.1, f.2, f.3, old.nodes, old.laid)
}

///|
/// Each of the six the most of `a`'s and `b`'s.
fn real_size_frame_most(a : (Int, Int, Int, Int, Int, Int), b : (Int, Int, Int, Int, Int, Int)) -> (Int, Int, Int, Int, Int, Int) {
  (
    @cmp.maximum(a.0, b.0),
    @cmp.maximum(a.1, b.1),
    @cmp.maximum(a.2, b.2),
    @cmp.maximum(a.3, b.3),
    @cmp.maximum(a.4, b.4),
    @cmp.maximum(a.5, b.5),
  )
}

///|
/// Whether way `way` of a screen `mode` is given its changes there (the head says which are given on one screen):
/// `measured`, the shell's ways given already in this window; `home`, those Home reads.
fn real_size_given_here(mode : String, way : String, measured : Map[String, Bool], home : Map[String, Bool]) -> Bool {
  if real_size_shell_ways.contains(way) {
    mode == "home" || (!home.contains(way) && !measured.contains(way))
  } else if real_size_chat_ways.contains(way) {
    real_size_chat_modes.contains(mode)
  } else {
    true
  }
}

///|
/// The screen opened as `mode` in `win` on the workspace of real size held as a device holds it, and given each change
/// of a way it reads that is given there (`given`): the most one frame of its opening did (made, laid, measured), and
/// for each "<way>/<cause>" what the frame that takes it does, in the order measured.
fn real_size_screen(
  mode : String,
  win : (String, Double, Double, Int, String),
  given : (String) -> Bool,
) -> ((Int, Int, Int), Array[(String, (Int, Int, Int, Int, Int, Int))]) {
  let c = @sfrealsize.RealSizeChanging::new()
  // (what moves not judged frame to frame: putting a way's value back whole before the next cause is the sweep's own,
  // nothing a device does, and a list's rows go back in one frame then: a chat's row 300 went 67 px as its message 301
  // went, 2026-11-11)
  let t = screen_in(mode, win, "zh", changing=Some(c), moves_held=false)
  let opening = real_size_most()
  real_size_change_said()
  let rows : Array[(String, (Int, Int, Int, Int, Int, Int))] = []
  let todo : Array[(Int, String, Array[Json])] = []
  for i, way in c.ways() {
    let name = @sfrealsize.real_size_way(way.0, way.1)
    if !given(name) {
      continue
    }
    for change in c.changed(i) {
      todo.push((i, "\{name}/\{change.0}", change.1))
    }
  }
  if todo.is_empty() {
    return (opening, rows)
  }
  // (what the old view builds in a frame given nothing: built whole each frame it is built)
  let nothing = real_size_change_frame(t, fn() {  })
  for job in todo {
    let (i, row, messages) = job
    let mut most = (0, 0, 0, 0, 0, 0)
    for m in messages {
      let f = real_size_change_frame(t, fn() { c.put(i, m) })
      let f = (f.0, f.1, f.2, f.3, @cmp.maximum(0, f.4 - nothing.4), @cmp.maximum(0, f.5 - nothing.5))
      most = real_size_frame_most(most, f)
    }
    c.put_back(i)
    real_size_change_frame(t, fn() {  }) |> ignore
    match rows.search_by(fn(r) { r.0 == row }) {
      Some(k) => rows[k] = (row, real_size_frame_most(rows[k].1, most))
      None => rows.push((row, most))
    }
  }
  (opening, rows)
}

///|
/// Every screen in window `win` opened on the workspace of real size and given its changes, each held to its bar.
fn real_size_sweep(win : (String, Double, Double, Int, String)) -> Unit raise {
  let faults : Array[String] = []
  let lines : Array[String] = []
  let change_lines : Array[String] = []
  let seen : Map[String, Bool] = Map([])
  let measured : Map[String, Bool] = Map([])
  let home : Map[String, Bool] = Map([])
  // (Home first: the shell's ways are given there, those it does not read on the first screen that does)
  let modes = corner_modes.filter(fn(m) { m == "home" }) + corner_modes.filter(fn(m) { m != "home" })
  for mode in modes {
    let (opening, rows) = real_size_screen(mode, win, fn(way) {
      real_size_given_here(mode, way, measured, home)
    })
    let (made, laid, words) = opening
    let name = "\{win.0} \{mode}"
    // (what the screen says it shows, which the hang reports send: a kind's name someone has read, shown_wbtest.mbt)
    match shown_fault(name, @ui.journal_shown()) {
      Some(f) => faults.push(f)
      None => ()
    }
    let line = "  \"\{name}\": (\{made}, \{laid}, \{words}),"
    match real_size_known.get(name) {
      None => {
        faults.push("\{name}: not in real_size_known_wbtest.mbt")
        lines.push(line)
      }
      Some((m, l, w)) =>
        if real_size_over(made, m) || real_size_over(laid, l) || real_size_over(words, w) {
          faults.push(
            "\{name}: made \{made} laid \{laid} measured \{words}, its bar (\{m}, \{l}, \{w}): one frame does more than a tenth over it",
          )
        } else if real_size_over(m, made) || real_size_over(l, laid) || real_size_over(w, words) {
          faults.push(
            "\{name}: made \{made} laid \{laid} measured \{words}, a tenth under its bar (\{m}, \{l}, \{w}): bring it down",
          )
          lines.push(line)
        }
    }
    for r in rows {
      let (row, f) = r
      let way = match row.rev_find("/") {
        Some(i) => row.exact_view(end=i).to_owned()
        None => row
      }
      if mode == "home" {
        home[way] = true
      }
      if real_size_shell_ways.contains(way) {
        measured[way] = true
      }
      let name = "\{win.0} \{mode} \{row}"
      seen[name] = true
      let line = "  \"\{name}\": (\{f.0}, \{f.1}, \{f.2}, \{f.3}, \{f.4}, \{f.5}),"
      match real_size_change_known.get(name) {
        None => {
          faults.push("\{name}: not in real_size_change_known_wbtest.mbt")
          change_lines.push(line)
        }
        Some(bar) => {
          let said = "made \{f.0} let go \{f.1} laid \{f.2} measured \{f.3} old built \{f.4} old laid \{f.5}, its bar \{Repr(bar)}"
          let pairs = [(f.0, bar.0), (f.1, bar.1), (f.2, bar.2), (f.3, bar.3), (f.4, bar.4), (f.5, bar.5)]
          if pairs.iter().any(fn(p) { real_size_change_over(p.0, p.1) }) {
            faults.push("\{name}: \{said}: the frame that takes it does more than a tenth over it")
          } else if pairs.iter().any(fn(p) { real_size_change_over(p.1, p.0) }) {
            faults.push("\{name}: \{said}: a tenth under its bar, bring it down")
            change_lines.push(line)
          }
        }
      }
    }
  }
  for name, _ in real_size_change_known {
    if name.has_prefix(win.0 + " ") && !seen.contains(name) {
      faults.push("\{name}: measured no longer (the screen holds that way no more, or the cause is gone): take it out")
    }
  }
  if lines.length() > 0 {
    println("real_size_known_wbtest.mbt, written so:\n" + lines.join("\n"))
  }
  if change_lines.length() > 0 {
    println("real_size_change_known_wbtest.mbt, written so:\n" + change_lines.join("\n"))
  }
  assert_eq(faults, [])
}

///|
test "every screen on a workspace of real size in a phone's window: its opening's most frame and each change's frame, held to their bars" {
  real_size_sweep(real_size_windows[0])
}

///|
test "every screen on a workspace of real size in a wide window: its opening's most frame and each change's frame, held to their bars" {
  real_size_sweep(real_size_windows[1])
}
