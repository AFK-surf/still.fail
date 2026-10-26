// The players' contract (scripts/host_contract.sh HOST play): on a real host, MBUI_PLAYCHECK=<a video's bytes, base64>
// (test/host/playcheck.mp4: a second of red, 64 × 48 at 10 frames a second, H.264): a player of it (a native view,
// video/mp4) in a box of its own, each read it asks answered from those bytes (the whole file its total), as the app's
// players are; once ready, its length to the tenth of a second and its picture's size said (`PLAYCHECK ready 1000
// 64x48`); where the host draws its picture in the canvas (MBUI_PLAYCHECK_DRAWN=1: Linux's), once its first frame is
// drawn, the middle of its picture as the canvas drew it (`PLAYCHECK drawn red`, else its colour: `PLAYCHECK drawn r g
// b`); where the host reads its frames' times (MBUI_PLAYCHECK_FRAMES=1: Linux's), how many and the first's and last's
// start (`PLAYCHECK frames 10 0 900`); played, said once it has played to its end (`PLAYCHECK ended`); a frame at 500
// ms grabbed, said once it is a PNG (`PLAYCHECK grabbed`); then the app's end. `PLAYCHECK none` where the host has no
// player, `PLAYCHECK failed` where it could not play it. The host asks for a frame as what it does changes: each
// frame's build only asks.

///|
// kept across runs: the check's one run (kitdemo run with MBUI_PLAYCHECK), never reset
let play_check_view : Ref[@ui.NativeView?] = Ref(None)

///|
/// how far it has come: 0 opened, 1 ready said, 2 its drawn picture said (where it is read), 3 its frames' times said
/// (where they are read), 4 played, 5 its end said and a frame asked for
// kept across runs: the check's one run, never reset
let play_check_said : Ref[Int] = Ref(0)

///|
/// the box its picture is drawn in, at its top left (what drawn_pixels reads)
let play_check_key : String = "play-check/picture"

///|
/// its picture's size, in points
let play_check_size : (Double, Double) = (160.0, 120.0)

///|
/// What the check does each frame, once its build is over: each step in turn as far as what they wait on has come, and
/// the app's end.
fn play_check_step(c : @ui.Ctx, v : @ui.NativeView) -> Unit {
  if v.state() < 0 {
    @hostapi.log("PLAYCHECK failed")
    @hostapi.exit(1)
    return
  }
  while play_check_next(c, v) {

  }
}

///|
/// The next step, once what it waits on has come (true: done, the one after looked at too).
fn play_check_next(c : @ui.Ctx, v : @ui.NativeView) -> Bool {
  match play_check_said.val {
    0 if v.state() == 1 => {
      let tenths = (v.duration() / 100.0).round().to_int() * 100
      let (w, h) = v.natural()
      @hostapi.log("PLAYCHECK ready \{tenths} \{w.to_int()}x\{h.to_int()}")
      play_check_said.val = 1
    }
    1 if @ui.env("MBUI_PLAYCHECK_DRAWN") != "1" => play_check_said.val = 2
    // (the picture stretched to its view: the pixel at its middle the video's red, as the canvas drew it)
    1 if v.shown() => {
      match c.drawn_pixels(c.id(play_check_key)) {
        PixelsRead(w, h, px) => {
          let (vw, vh) = play_check_size
          let x = (vw / 2.0 * c.scale).to_int()
          let y = (vh / 2.0 * c.scale).to_int()
          let i = if x < w && y < h { (y * w + x) * 4 } else { 0 }
          let (r, g, b) = (px[i].to_int(), px[i + 1].to_int(), px[i + 2].to_int())
          @hostapi.log(
            if r > 200 && g < 60 && b < 60 {
              "PLAYCHECK drawn red"
            } else {
              "PLAYCHECK drawn \{r} \{g} \{b}"
            },
          )
        }
        _ => @hostapi.log("PLAYCHECK drawn none")
      }
      play_check_said.val = 2
    }
    2 if @ui.env("MBUI_PLAYCHECK_FRAMES") != "1" => play_check_said.val = 3
    // (how many, the first's and the last's start, in ms)
    2 =>
      match v.frames() {
        Some(list) => {
          let ends = if list.length() > 0 {
            " \{list[0].round().to_int()} \{list[list.length() - 1].round().to_int()}"
          } else {
            ""
          }
          @hostapi.log("PLAYCHECK frames \{list.length()}" + ends)
          play_check_said.val = 3
        }
        None => return false
      }
    3 => {
      v.play()
      play_check_said.val = 4
    }
    4 if v.ended() => {
      @hostapi.log("PLAYCHECK ended")
      v.grab_frame(500.0)
      play_check_said.val = 5
    }
    5 =>
      match v.grabbed() {
        Some(png) => {
          let png_head = png.length() > 8 && png[1] == b'P' && png[2] == b'N' && png[3] == b'G'
          @hostapi.log(
            if png.length() == 0 {
              "PLAYCHECK not grabbed"
            } else if png_head {
              "PLAYCHECK grabbed"
            } else {
              "PLAYCHECK grabbed no PNG"
            },
          )
          @hostapi.exit(if png_head { 0 } else { 1 })
          return false
        }
        None => return false
      }
    _ => return false
  }
  true
}

///|
pub fn play_check_run(c : @ui.Ctx, video : String) -> Unit {
  let v = match play_check_view.val {
    Some(v) => v
    None => {
      let data = @codec.from_base64(video)
      let v = @ui.NativeView::video("video/mp4", fn(offset, length, answer) {
        let n = data.length()
        let from = if offset < 0.0 { 0 } else if offset > n.to_double() { n } else { offset.to_int() }
        let to = if from + length > n { n } else { from + length }
        answer(data[from:to].to_owned(), n.to_double(), false)
        fn() {  }
      })
      play_check_view.val = Some(v)
      v
    }
  }
  if !v.here() {
    c.after_build("play-check-none", fn() {
      @hostapi.log("PLAYCHECK none")
      @hostapi.exit(1)
    })
    return
  }
  c.after_build("play-check", fn() { play_check_step(c, v) })
  let (vw, vh) = play_check_size
  c.box(id=c.id(play_check_key), fn() { c.native(v, w=Px(vw), h=Px(vh)) |> ignore }) |> ignore
}
