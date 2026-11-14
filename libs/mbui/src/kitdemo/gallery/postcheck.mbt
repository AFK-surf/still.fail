// What a host posts is told between frames (scripts/host_contract.sh linux posted): on a real host, MBUI_POSTCHECK=1:
// once the first frame is built, the host asked to install a package it has none for (@hostapi.install_package), which
// it says on the system channel as a message posted from outside the frames (Linux: mb_post, linux_app.c's
// install_package, say_system's way). What changes only signals is offered as it is told (@ui.on_message_said): asked
// here, it says whether a frame was being made then (`POSTCHECK offered between frames` / `in a frame`) and leaves it
// for the frame, which hands it on (`POSTCHECK handed`), then the app's end: 0 told between frames, 1 in one. A host
// that takes what was posted as a frame begins (what the web's and Linux's did till 2026-11-11) offers it in a frame:
// there the frame has read what it does again before it is taken, a change only the window's tree reads unseen.

///|
// kept across runs: one check a run, set as its first frame is built
let post_check_asked : Ref[Bool] = Ref(false)

///|
/// -1 not offered yet, 1 offered between frames, 0 in a frame
// kept across runs: one check a run, set as the message is offered
let post_check_between : Ref[Int] = Ref(-1)

///|
/// The Ctx of the frames (for whether one is being made as the message is offered: Ctx::in_frame)
// kept across runs: the run's one window, set as it is built
let post_check_ctx : Ref[@ui.Ctx?] = Ref(None)

///|
/// What the system channel says followed, from before the app's first frame.
pub fn post_check_follow() -> Unit {
  @ui.on_message_said(@hostapi.system_channel, fn(json, _) {
    if json.contains("postcheck") && post_check_between.val < 0 {
      let in_one = match post_check_ctx.val {
        Some(c) => c.in_frame()
        None => true
      }
      post_check_between.val = if in_one { 0 } else { 1 }
      @hostapi.log("POSTCHECK offered " + (if in_one { "in a frame" } else { "between frames" }))
    }
    false
  })
  @ui.on_message(@hostapi.system_channel, fn(json, _) {
    if json.contains("postcheck") {
      @hostapi.log("POSTCHECK handed")
      @hostapi.exit(if post_check_between.val == 1 { 0 } else { 1 })
    }
  })
}

///|
pub fn post_check_run(c : @ui.Ctx) -> Unit {
  post_check_ctx.val = Some(c)
  if !post_check_asked.val {
    post_check_asked.val = true
    c.after_build("post-check", fn() {
      @hostapi.install_package("postcheck", b"")
      @hostapi.log("POSTCHECK posted")
    })
  }
  c.text("post check") |> ignore
}
