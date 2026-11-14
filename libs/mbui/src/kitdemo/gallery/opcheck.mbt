// How a run of the password manager's `op` ended is told between frames (scripts/host_contract.sh mac op): on a real
// host, MBUI_OPCHECK=ran with a stand-in `op` first on PATH (it prints `[{"opcheck":true}]` and ends 0), or
// MBUI_OPCHECK=missing with none anywhere: once the first frame is built, a run asked (@hostapi.op_run), and a watch of
// how it ended (OpRun::done, a signal the host's word sets: hostcall.mbt's outside_op) says whether a frame was being
// made as it was told, and what it read (`OPCHECK told between frames: code 0 out [{"opcheck":true}]` / `… code -1 err op
// not found`); the app ends 0 where it was told between frames and read what that case gives, else 1.

///|
// kept across runs: one check a run, set as its first frame is built
let op_check_asked : Ref[Bool] = Ref(false)

///|
/// The Ctx of the frames (for whether one is being made as how it ended is told: Ctx::in_frame)
// kept across runs: the run's one window, set as it is built
let op_check_ctx : Ref[@ui.Ctx?] = Ref(None)

///|
pub fn op_check_run(c : @ui.Ctx, case_ : String) -> Unit {
  op_check_ctx.val = Some(c)
  if !op_check_asked.val {
    op_check_asked.val = true
    c.after_build("op-check", fn() {
      match @hostapi.op_run(["item", "list", "--format", "json"]) {
        Some(r) => {
          @hostapi.log("OPCHECK asked")
          // (owned by nothing: the watch is the run's, not the frame's. Made outside the frame's reading too: an
          // after_build runs as the frame's watch reads (frame_watch.mbt), and an effect made there is that watch's,
          // whatever owner is set, let go as it reads the next frame, before the host's word came: the run never ended,
          // CI's job stopped at its five minutes, 2026-11-12)
          let owner = @signals.set_owner(None)
          @signals.untracked(fn() {
            @signals.effect(fn() {
              match r.done() {
                Some(d) => {
                  let in_one = match op_check_ctx.val {
                    Some(c) => c.in_frame()
                    None => true
                  }
                  let out = d.out.trim(chars=" \n").to_owned()
                  let err = d.err.trim(chars=" \n").to_owned()
                  @hostapi.log(
                    "OPCHECK told " +
                    (if in_one { "in a frame" } else { "between frames" }) +
                    ": code \{d.code} out \{out} err \{err}",
                  )
                  let read = if case_ == "missing" {
                    d.code == -1 && err.contains("not found")
                  } else {
                    d.code == 0 && out.contains("opcheck")
                  }
                  @hostapi.exit(if !in_one && read { 0 } else { 1 })
                }
                None => ()
              }
            })
            |> ignore
          })
          @signals.set_owner(owner) |> ignore
        }
        None => {
          @hostapi.log("OPCHECK no password manager here")
          @hostapi.exit(1)
        }
      }
    })
  }
  c.text("op check") |> ignore
}
