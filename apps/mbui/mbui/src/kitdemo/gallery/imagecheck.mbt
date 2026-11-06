// The pictures' contract over a new context (scripts/host_contract.sh linux images): on a real host,
// MBUI_IMAGECHECK=<a PNG's path>: a red picture shown, and once it is told ready and drawn, the host's GL context made
// anew (@hostapi.drive 10), as one lost. Once the host has every picture it had decoded anew in it (none of them
// decoding: a frame's build reads what the host has uploaded and told before it), the one shown is told ready again
// (`IMAGECHECK told 2`; else `IMAGECHECK not told again`, the app's end with 1), what draws it drawn again; the next
// frame pictured at the path (`IMAGECHECK drawn PATH 120 SCALE`: the picture's side in points, the window's scale, for
// scripts/chk images to find it red in), then the app's end. `IMAGECHECK none` where the host makes no context anew.

///|
/// 32 × 32 pixels of red
let image_check_png = "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAAJ0lEQVR42u3NsQkAAAjAsP7/tF7hIASyp6lTCQQCgUAgEAgEgi/BAjLD/C5w/SM9AAAAAElFTkSuQmCC"

///|
let image_check_key = "mem:imagecheck"

///|
/// how often the picture has been told decoded (the host's word of it, followed), -1 before it is followed
let image_check_told : Ref[Int] = Ref(-1)

///|
/// 0 shown, 1 its context asked anew, 2 made anew, 3 told again
let image_check_at : Ref[Int] = Ref(0)

///|
/// the host's id of a picture asked for after the shown one: every picture of the run's is at most it
let image_check_last : Ref[Int] = Ref(0)

///|
fn image_check_step(path : String, scale : Double) -> Unit {
  match image_check_at.val {
    0 =>
      if image_check_told.val >= 1 && @ui.image_state(image_check_key) == 1 {
        image_check_last.val = @hostapi.image_load_bytes(@codec.from_base64(image_check_png), 32)
        if !@hostapi.drive(10, "") {
          @hostapi.log("IMAGECHECK none")
          @hostapi.exit(1)
          return
        }
        @hostapi.log("IMAGECHECK told \{image_check_told.val}, its context made anew")
        image_check_at.val = 1
      }
    1 =>
      if @hostapi.drive(11, "") {
        image_check_at.val = 2
      }
    2 => {
      let out = FixedArray::make(4, 0.0)
      for id in 1..=image_check_last.val {
        if @hostapi.image_info(id, out) == 0 {
          @hostapi.request_frame()
          return
        }
      }
      if image_check_told.val < 2 {
        @hostapi.log("IMAGECHECK not told again (told \{image_check_told.val})")
        @hostapi.exit(1)
        return
      }
      @hostapi.log("IMAGECHECK told \{image_check_told.val}")
      image_check_at.val = 3
    }
    _ => {
      @hostapi.drive(4, path) |> ignore
      @hostapi.log("IMAGECHECK drawn \{path} 120 \{scale}")
      @hostapi.exit(0)
      return
    }
  }
  @hostapi.request_frame()
}

///|
pub fn image_check_run(c : @ui.Ctx, path : String) -> Unit {
  if image_check_told.val < 0 {
    c.image_bytes(image_check_key, @codec.from_base64(image_check_png))
    @signals.effect(fn() {
      @ui.image_state(image_check_key) |> ignore
      image_check_told.val += 1
    })
    |> ignore
  }
  c.image(image_check_key, w=Px(120.0), h=Px(120.0), fade=false) |> ignore
  let scale = c.scale
  c.after_build("image-check", fn() { image_check_step(path, scale) })
}
