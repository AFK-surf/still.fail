// A flow's steps as a scripted run's (src/ui/drive.mbt's), written for scripts/rerecord.sh: the test run once with
// FLOW_EMIT=<file>, its first order's steps go there as a .drive the app runs against a live backend, and that run's
// conversation becomes the test's trace again (trace.py). Each step says its line (Flow::*); what only a live run
// needs (alice's other device, a page before the first frame) is a step of its own that the Tester skips (Flow::peer,
// Flow::before, Flow::open_page). Time is the host's there: a step waits as drive's do, so run_for and run_to say
// nothing, but where a step must land inside a motion (a tap on what a sheet going down only draws), run_for says
// `wait` and the next step is `now`.

///|
/// The flow being written (None: none is).
// kept across runs: Flow::start sets it for each flow, as FLOW_EMIT says
let script : Ref[Array[String]?] = Ref::new(None)

///|
/// Whether the step after is to be taken at once (after a run_for into a motion).
// kept across runs: Flow::start sets it for each flow
let now_next : Ref[Bool] = Ref::new(false)

///|
/// Starts writing the flow, when FLOW_EMIT asks and this is its first order (seed 0).
fn emit_start(seed : UInt, w : Double, h : Double, env : Array[(String, String)]) -> Unit {
  now_next.val = false
  if seed != 0 || emit_path() == "" {
    script.val = None
    return
  }
  let s = ["# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand", "timeout 90000"]
  if w != 390.0 || h != 844.0 {
    s.push("#env MBUI_WIN=\{w.to_int()}x\{h.to_int()}")
  }
  for kv in env {
    s.push("#env \{kv.0}=\{kv.1}")
  }
  script.val = Some(s)
  write_file(emit_path(), s.join("\n") + "\n")
}

///|
/// A line of the script (a header, `#…`, as it is; a step after a run_for, `now` first).
fn emit(line : String) -> Unit {
  match script.val {
    Some(s) => {
      if line.has_prefix("#") || line.has_prefix("wait ") || line.has_prefix("log ") {
        s.push(line)
      } else if now_next.val {
        now_next.val = false
        s.push("now " + line)
      } else {
        s.push(line)
      }
      // (written as it goes: a test that stops halfway, the app now asking otherwise, leaves the script to there)
      write_file(emit_path(), s.join("\n") + "\n")
    }
    None => ()
  }
}

///|
/// The flow over: nothing more is written.
fn emit_end() -> Unit {
  match script.val {
    Some(_) => script.val = None
    None => ()
  }
}

///|
/// What only a live run does beside the app, as scripts/e2e-local.sh `WORDS` (alice's other device: `peer send …`,
/// the station frozen…): said on the script's log there (`log do: WORDS`), nothing here, where the trace has what came
/// of it.
pub fn Flow::peer(self : Flow, words : String) -> Unit {
  ignore(self)
  emit("log do: " + words)
}

///|
/// What a live run does before the app starts (`#before WORDS`: scripts/e2e-local.sh WORDS, a chat made elsewhere):
/// nothing here.
pub fn Flow::before(self : Flow, words : String) -> Unit {
  ignore(self)
  emit("#before " + words)
}

///|
/// Time a step waited into a motion: `wait` there, and the step after taken at once (`now`), where a scripted step
/// would wait for the motion to end.
fn emit_wait(ms : Double) -> Unit {
  match script.val {
    Some(_) => {
      emit("wait \{ms.to_int()}")
      now_next.val = true
    }
    None => ()
  }
}

///|
/// A page as MBUI_OPEN_PAGE names it (src/stillfail/main.mbt).
fn page_name(page : @sfapp.Page) -> String {
  match page {
    Files => "files"
    Decisions => "decisions"
    _ => abort("flow: no MBUI_OPEN_PAGE for this page")
  }
}

///|
/// The calls the step just taken made of the core (that the run answered), a scripted run's `answered NAME` each
/// (drive.mbt: what has ended since the last step that acted, and the frame drawn after it), once each in order.
fn emit_answered(names : Array[String]) -> Unit {
  match script.val {
    Some(_) => {
      let seen : Array[String] = []
      for n in names {
        if !seen.contains(n) {
          seen.push(n)
          emit("answered " + n)
        }
      }
    }
    None => ()
  }
}
