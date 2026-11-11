// Every screen opened on a workspace of real size (src/sfrealsize: what the core sends each topic on the owner's
// workspace as their phone reported it, 2026-11-10), and the most one frame of its opening did (mbui's journal, a
// frame's FrameDone): nodes of the window's tree made, nodes laid out, words measured. The screens' own fixture is a
// few rows of each thing; a page that makes everything it holds in one frame looks light there and stalls a phone (the
// changelog's 200 changes, a day of them made whole in a frame: the user's 「为啥没检查出来」, 2026-11-11). Each screen's
// counts are held to its bar in real_size_known_wbtest.mbt, which only falls (the user, 2026-11-11: 三条都加): the
// tree's work is counted, never instructions (the user, 2026-11-09).

///|
/// The windows: a phone's and a wide desktop's (corner_windows').
let real_size_windows : Array[(String, Double, Double, Int, String)] = [
  ("phone", 360.0, 740.0, 2, ""),
  ("wide", 1280.0, 800.0, 0, ""),
]

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
test "every screen opened on a workspace of real size: the most one frame makes, lays out and measures, held to its bar" {
  let faults : Array[String] = []
  let lines : Array[String] = []
  for win in real_size_windows {
    for mode in corner_modes {
      let _ = screen_in(mode, win, "zh", real=true)
      let (made, laid, measured) = real_size_most()
      let name = "\{win.0} \{mode}"
      let line = "  \"\{name}\": (\{made}, \{laid}, \{measured}),"
      match real_size_known.get(name) {
        None => {
          faults.push("\{name}: not in real_size_known_wbtest.mbt")
          lines.push(line)
        }
        Some((m, l, w)) =>
          if real_size_over(made, m) || real_size_over(laid, l) || real_size_over(measured, w) {
            faults.push(
              "\{name}: made \{made} laid \{laid} measured \{measured}, its bar (\{m}, \{l}, \{w}): one frame does more than a tenth over it",
            )
          } else if real_size_over(m, made) || real_size_over(l, laid) || real_size_over(w, measured) {
            faults.push(
              "\{name}: made \{made} laid \{laid} measured \{measured}, a tenth under its bar (\{m}, \{l}, \{w}): bring it down",
            )
            lines.push(line)
          }
      }
    }
  }
  if lines.length() > 0 {
    println("real_size_known_wbtest.mbt, written so:\n" + lines.join("\n"))
  }
  assert_eq(faults, [])
}
