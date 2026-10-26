// The players' contract (scripts/host_contract.sh HOST play): on a real host, MBUI_PLAYCHECK=<a video's bytes, base64>
// (test/host/playcheck.mp4: a second of 64 × 48 at 10 frames a second, H.264): a player opened for it (a view of kind
// 1, video/mp4) and placed, each read it asks answered from those bytes (the whole file its total), as the app's
// players are; once ready, its length to the tenth of a second and its picture's size said (`PLAYCHECK ready 1000
// 64x48`); played, said once it has played to its end (`PLAYCHECK ended`); a frame at 500 ms grabbed, said once it is
// a PNG (`PLAYCHECK grabbed`); then the app's end. `PLAYCHECK none` where the host has no player, `PLAYCHECK failed`
// where it could not play it. The host asks for a frame as what it does changes: each frame's build only asks.

///|
// kept across runs: the check's one run (kitdemo run with MBUI_PLAYCHECK), never reset
let play_check_view : Ref[Int] = Ref(0)

///|
/// its bytes, once read from the environment
// kept across runs: the check's one run, never reset
let play_check_bytes : Ref[Bytes] = Ref(b"")

///|
/// how far it has come: 0 opened, 1 ready said and played, 2 its end said and a frame asked for
// kept across runs: the check's one run, never reset
let play_check_said : Ref[Int] = Ref(0)

///|
/// What the check does each frame, once its builds are over: the player opened (the first time), its reads answered,
/// then each step as it comes, and the app's end.
fn play_check_step(video : String) -> Unit {
  if play_check_view.val == 0 {
    let id = @hostapi.view_open(1, "video/mp4")
    if id == 0 {
      @hostapi.log("PLAYCHECK none")
      @hostapi.exit(1)
      return
    }
    play_check_view.val = id
    play_check_bytes.val = @codec.from_base64(video)
    @hostapi.view_place(id, 0.0, 0.0, 160.0, 120.0, 0.0, 0.0, 160.0, 120.0, 0.0, true)
  }
  let id = play_check_view.val
  let data = play_check_bytes.val
  let ask = FixedArray::make(2, 0.0)
  for req = @hostapi.view_read_next(id, ask); req != 0; req = @hostapi.view_read_next(id, ask) {
    if req < 0 {
      continue
    }
    let n = data.length()
    let from = if ask[0] < 0.0 { 0 } else if ask[0] > n.to_double() { n } else { ask[0].to_int() }
    let to = if from + ask[1].to_int() > n { n } else { from + ask[1].to_int() }
    @hostapi.view_read_answer(id, req, data[from:to].to_bytes(), n.to_double(), false)
  }
  let info = FixedArray::make(10, 0.0)
  let state = @hostapi.view_info(id, info)
  if state < 0 {
    @hostapi.log("PLAYCHECK failed")
    @hostapi.exit(1)
    return
  }
  match play_check_said.val {
    0 if state == 1 => {
      let tenths = (info[0] / 100.0).round().to_int() * 100
      @hostapi.log("PLAYCHECK ready \{tenths} \{info[3].to_int()}x\{info[4].to_int()}")
      @hostapi.view_control(id, 1, 0.0)
      play_check_said.val = 1
    }
    1 if info[9] == 1.0 => {
      @hostapi.log("PLAYCHECK ended")
      @hostapi.view_control(id, 21, 500.0)
      play_check_said.val = 2
    }
    2 =>
      match @hostapi.view_text(id, 2) {
        Some("2") => {
          let png = @hostapi.view_still(id)
          let png_head = png.length() > 8 && png[1] == b'P' && png[2] == b'N' && png[3] == b'G'
          @hostapi.log(if png_head { "PLAYCHECK grabbed" } else { "PLAYCHECK grabbed no PNG" })
          @hostapi.exit(if png_head { 0 } else { 1 })
        }
        Some("-1") => {
          @hostapi.log("PLAYCHECK not grabbed")
          @hostapi.exit(1)
        }
        _ => ()
      }
    _ => ()
  }
}

///|
pub fn play_check_run(c : @ui.Ctx, video : String) -> Unit {
  c.after_build("play-check", fn() { play_check_step(video) })
  c.text("play check") |> ignore
}
