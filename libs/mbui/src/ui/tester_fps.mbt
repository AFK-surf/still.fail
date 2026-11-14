///|
/// How far apart the frames run_for draws on its way are (ms), or 0, none (run_for goes straight to its end, the
/// default): MBUI_TEST_FPS (frames a second) that rate's, a run of the tests at a frame rate, which must come out the
/// same (scripts/fps_check.sh). The test program's own environment, not the app's (the fake host's, a Tester's `env`):
/// asked of the fake, it was never set, and every run at a frame rate went straight to its ends as the default's did.
fn test_frames_between() -> Double {
  let fps = @env.get_env_var("MBUI_TEST_FPS").unwrap_or("")
  match (try Some(@json.parse(fps)) catch { _ => None }) {
    Some(Number(n, ..)) if n > 0.0 => 1000.0 / n
    _ => 0.0
  }
}

///|
/// Whether a run at a frame rate judges how what moves goes frame to frame on its frames on run_for's way too
/// (Tester::judges_motion), not only the results: MBUI_TEST_MOTION `judge` (a fault fails its test, as on the default
/// run's frames) or `count` (each said, `MOTION …`, none failing: what the tests show listed, mended down to none). At
/// 60 and 120 a second, a display's own rates: the default run draws few frames in the middle of a motion, so a
/// step half way through one went unseen (the user, 2026-11-09: 「动画执行到一半突变也算突变」). `count` counts only the
/// Testers made in the files still counted (motion_counted) and judges the rest, so a file mended to none stays so.
fn test_motion_judged(loc : String) -> MotionJudged {
  match @env.get_env_var("MBUI_TEST_MOTION").unwrap_or("") {
    "judge" => Judge
    "count" => {
      let file = match loc.find(":") {
        Some(i) => loc.unsafe_substring(start=0, end=i)
        None => loc
      }
      if motion_counted_files.contains(file) {
        Count
      } else {
        Judge
      }
    }
    _ => Results
  }
}

///|
/// Whether this run says each file's bars and what was found under them: one that counts or judges how what moves goes
/// (MBUI_TEST_MOTION said, a run at 60 or 120 a second), or one at the default rate told to (MBUI_TEST_BARS `1`, CI's:
/// a bar holds what the default run's frames find as well). If so it says what each file's bars are, which files its
/// Testers were made in, which of them are not judged on how what moves goes (Tester::motion_unjudged), and each fault
/// a Tester found with how many it has come to, within its file's bar or counted (`MOTION bar`, `MOTION made`, `MOTION
/// unjudged`, `MOTION known`, `MOTION counted`, `MOTION held`), so that each bar can be set beside the most one Tester
/// of its file found (scripts/motion_bars.sh): a bar more than that falls, or what it was for is filed under another
/// file (a Tester made in a helper of another file's: the helper's file).
fn motion_runs() -> Bool {
  if motion_run_said.val < 0 {
    motion_run_said.val = if @env.get_env_var("MBUI_TEST_MOTION").unwrap_or("") != "" ||
      @env.get_env_var("MBUI_TEST_BARS").unwrap_or("") == "1" {
      1
    } else {
      0
    }
  }
  motion_run_said.val == 1
}

///|
// kept across runs: the test program's own environment, asked once (-1 not yet)
let motion_run_said : Ref[Int] = Ref(-1)

///|
/// A per-file bar said (motion_runs): `MOTION bar <check> <file> <n>`.
fn motion_bars_said(check : String, bars : Array[(String, Int)]) -> Unit {
  if motion_runs() {
    for b in bars {
      println("MOTION bar \{check} \{b.0} \{b.1}")
    }
  }
}

///|
/// A fault a Tester found, judged against its file's bar or counted (motion_runs): `MOTION known <check> <file>
/// <n>/<bar>: <what>`, `n` how many that Tester has found so far, the most of them what the bar holds.
fn motion_known_said(check : String, file : String, n : Int, bar : Int, what : String) -> Unit {
  if motion_runs() {
    println("MOTION known \{check} \{file} \{n}/\{bar}: \{what}")
  }
}

///|
/// Whether a Tester looks at each frame's corners worked out with what is kept (tester_corners.mbt): MBUI_CORNERS_LOOK
/// `0` not, for a run to set beside one that does (the same to the bit); else, the default, it does.
fn test_corners_looked() -> Bool {
  @env.get_env_var("MBUI_CORNERS_LOOK").unwrap_or("") != "0"
}
