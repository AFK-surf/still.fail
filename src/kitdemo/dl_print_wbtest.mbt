///|
/// The process's environment (node's), to ask for what a test prints only when asked.
extern "js" fn node_env(name : String) -> String =
  #|(n) => (typeof process !== "undefined" && process.env[n]) || ""

///|
/// A file's words (node's), "" when there is none: a run's tape handed to the test by its path.
extern "js" fn node_read(path : String) -> String =
  #|(p) => { try { return process.getBuiltinModule("fs").readFileSync(p, "utf8"); } catch (e) { return ""; } }

///|
/// The time of a tape's first frame (its first DRAWHASH line), 0 when it has none.
fn first_frame_time(tape : String) -> Double {
  for v in tape.split("\n") {
    let line = v.to_owned()
    match line.find("DRAWHASH ") {
      Some(i) => {
        let parts = line.view(start_offset=i + 9).split(" ").map(fn(p) { p.to_owned() }).to_array()
        if parts.length() >= 2 {
          match (try Some(@json.parse(parts[1])) catch { _ => None }) {
            Some(Number(d, ..)) => return d
            _ => ()
          }
        }
      }
      None => ()
    }
  }
  0.0
}

///|
/// The controls page's draw list printed when asked (MBUI_DL_PRINT=1: scripts/render_offscreen.sh, render_check.sh):
/// of the run kept from mini1, or (MBUI_DL_TAPE, a run's log: its text, its input and its frames) of that run, its
/// frames drawn again here, the last one's; and whether each frame here was the run's (DLFRAMES).
test "the controls page's draw list printed when asked (MBUI_DL_PRINT=1: scripts/render_check.sh)" {
  if node_env("MBUI_DL_PRINT") == "1" {
    let path = node_env("MBUI_DL_TAPE")
    let t = if path == "" {
      controls_kept()
    } else {
      let tape = node_read(path)
      let t = @ui.Tester::new(
        fn(c) { gallery(c, "controls") },
        w=960.0,
        h=720.0,
        text=tape,
        scale=1.0,
        time=first_frame_time(tape) - 16.0,
        stable=true,
      )
      let frames = t.replay_frames(tape)
      let apart = frames.filter(fn(f) { f.1 != f.2 }).length()
      println("DLFRAMES \{frames.length()} apart \{apart}")
      t
    }
    println("DLBEGIN")
    println(t.drawlist())
    println("DLEND")
  }
}
