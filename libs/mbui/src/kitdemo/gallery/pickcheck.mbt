// What the system's picker gave is told between frames (scripts/host_contract.sh linux picked): on a real host,
// MBUI_PICKCHECK=1 with MBUI_PICK_FILES=<a file>: once the first frame is built, a pick asked (@ui.pick), which the host
// answers with that file at once, no dialog. What reads what was picked (Pick::files, a signal) is told as the host's
// word is taken: here, a watch of it says whether a frame was being made then (`PICKCHECK taken between frames` /
// `in a frame`), and the app ends, 0 told between frames, 1 in one. A host that told it as a frame begins (Linux's and
// Windows' till 2026-11-11) tells it in a frame: there the frame has read what it does again before it is taken.

///|
// kept across runs: one check a run, set as its first frame is built
let pick_check_asked : Ref[Bool] = Ref(false)

///|
/// The Ctx of the frames (for whether one is being made as what was picked is told: Ctx::in_frame)
// kept across runs: the run's one window, set as it is built
let pick_check_ctx : Ref[@ui.Ctx?] = Ref(None)

///|
pub fn pick_check_run(c : @ui.Ctx) -> Unit {
  pick_check_ctx.val = Some(c)
  if !pick_check_asked.val {
    pick_check_asked.val = true
    c.after_build("pick-check", fn() {
      match @ui.pick(Files) {
        Some(p) => {
          @hostapi.log("PICKCHECK asked")
          // (owned by nothing: the watch is the run's, not the frame's. Made outside the frame's reading too: an
          // after_build runs as the frame's watch reads (frame_watch.mbt), and an effect made there is that watch's,
          // whatever owner is set, let go as it reads the next frame, before the host's word came)
          let owner = @signals.set_owner(None)
          @signals.untracked(fn() {
            @signals.effect(fn() {
              match p.files() {
                Some(files) => {
                  let in_one = match pick_check_ctx.val {
                    Some(c) => c.in_frame()
                    None => true
                  }
                  @hostapi.log(
                    "PICKCHECK taken " + (if in_one { "in a frame" } else { "between frames" }) + ": \{files.length()} files",
                  )
                  @hostapi.exit(if in_one || files.length() == 0 { 1 } else { 0 })
                }
                None => ()
              }
            })
            |> ignore
          })
          @signals.set_owner(owner) |> ignore
        }
        None => {
          @hostapi.log("PICKCHECK no picker here")
          @hostapi.exit(1)
        }
      }
    })
  }
  c.text("pick check") |> ignore
}
