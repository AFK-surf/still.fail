// The pictures' contract over a new context (scripts/host_contract.sh linux images): on a real host,
// MBUI_IMAGECHECK=<a PNG's path>: a red picture shown, and once it is told ready, the host's GL context made anew
// (@hostapi.drive 10), as one lost. The host decodes it anew there and tells it ready again: the frame built for that
// word says `IMAGECHECK told 2` (`IMAGECHECK told before its context` where the context is not yet made anew, the
// app's end with 1) and draws it; the frame after pictures what it drew at the path (`IMAGECHECK drawn PATH 120
// SCALE`: the picture's side in points, the window's scale, for scripts/chk images to find it red in), then the app's
// end. A host that never tells it again gives no frame for it, and the run says no more (no `told 2`). `IMAGECHECK
// none` where the host makes no context anew.

///|
/// 32 × 32 pixels of red
let image_check_png = "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAAJ0lEQVR42u3NsQkAAAjAsP7/tF7hIASyp6lTCQQCgUAgEAgEgi/BAjLD/C5w/SM9AAAAAElFTkSuQmCC"

///|
let image_check_key = "mem:imagecheck"

///|
/// how often the picture has been told decoded (the host's word of it, followed), -1 before it is followed
let image_check_told : Ref[Int] = Ref(-1)

///|
let image_check_given : Ref[Bool] = Ref(false)

///|
/// 0 shown, 1 its context asked anew, 2 told again and drawn: read by the build, so that each step is a frame's
let image_check_at : @signals.Signal[Int] = @signals.signal(0)

///|
fn image_check_step(path : String, scale : Double) -> Unit {
  match image_check_at.untracked() {
    0 =>
      if image_check_told.val >= 1 && @ui.image_state(image_check_key) == 1 {
        if !@hostapi.drive(10, "") {
          @hostapi.log("IMAGECHECK none")
          @hostapi.exit(1)
          return
        }
        @hostapi.log("IMAGECHECK told \{image_check_told.val}, its context made anew")
        image_check_at.set(1)
      }
    1 =>
      if image_check_told.val >= 2 {
        if !@hostapi.drive(11, "") {
          @hostapi.log("IMAGECHECK told before its context (told \{image_check_told.val})")
          @hostapi.exit(1)
          return
        }
        @hostapi.log("IMAGECHECK told \{image_check_told.val}")
        image_check_at.set(2)
      }
    _ => {
      @hostapi.drive(4, path) |> ignore
      @hostapi.log("IMAGECHECK drawn \{path} 120 \{scale}")
      @hostapi.exit(0)
    }
  }
}

///|
/// What the host says of the picture followed, from before the app's first frame: owned by no build (one a build
/// made would go with the next build of it, and what the host says after with it).
pub fn image_check_follow() -> Unit {
  @signals.effect(fn() {
    @ui.image_state(image_check_key) |> ignore
    image_check_told.val += 1
  })
  |> ignore
}

///|
pub fn image_check_run(c : @ui.Ctx, path : String) -> Unit {
  if !image_check_given.val {
    image_check_given.val = true
    c.image_bytes(image_check_key, @codec.from_base64(image_check_png))
  }
  c.image(image_check_key, w=Px(120.0), h=Px(120.0), fade=false) |> ignore
  image_check_at.get() |> ignore
  let scale = c.scale
  c.after_build("image-check", fn() { image_check_step(path, scale) })
}
