// The native views' contract (docs/determinism.md, "What is compared, and where"; scripts/host_contract.sh HOST views):
// on a real host, MBUI_VIEWCHECK=1: a video's view and a page's placed between pixels (a 16:9 picture fitted in 366
// across, its top 147.3625 down; a page under it at 410.4375, 120.25 tall), each kind the host has (Windows has no
// video player yet: its page alone), what the app told the host on the log (VIEWTOLD, in device pixels: ui's native.mbt) beside where the
// host put it (VIEWAT, each host's own), then `VIEWCHECK done` and the app's end. The two the same, on whole device
// pixels, or the contract fails: else the row its edge half covers shows what is under the canvas. The page's corners
// round (view_check_round: told the host, its hole as round); MBUI_VIEWCHECK=hold leaves both on the screen once placed
// (`VIEWCHECK placed`) for the contract's picture of those corners (Android: scripts/host_contract.sh android views),
// with a page far taller than a picture of it can be under them (view_check_tall), seen in its middle.

///|
let view_check_view : Ref[@ui.NativeView?] = Ref(None)

///|
let view_check_page : Ref[@ui.NativeView?] = Ref(None)

///|
let view_check_tall : Ref[@ui.NativeView?] = Ref(None)

///|
/// A page 40,000 tall (its CSS pixels the points it is placed in; Android: past the largest texture a GPU takes, many
/// times over), placed so that only the middle of its band of green on red is seen: there, its picture shows the part
/// of it that is there (NativeViews.Page), or the contract fails.
let view_check_tall_html : String = "<html><body style=\"margin:0;background:#c00\"><div style=\"height:29000px\"></div><div style=\"height:2000px;background:#0a0\"></div><div style=\"height:9000px\"></div></body></html>"

///|
/// The page's corners' radius (points): a phone's screen's, as a page laid out as one shows (still.fail's preview).
let view_check_round : Double = 24.0

///|
let view_check_placed : Ref[Bool] = Ref(false)

///|
pub fn view_check_run(c : @ui.Ctx) -> Unit {
  let v = match view_check_view.val {
    Some(v) => v
    None => {
      let v = @ui.NativeView::video("video/mp4", fn(_offset, _length, answer) {
          answer(b"", -1.0, false)
          fn() {  }
        })
      view_check_view.val = Some(v)
      v
    }
  }
  let p = match view_check_page.val {
    Some(p) => p
    None => {
      let p = @ui.NativeView::page("<html><body style=\"margin:0;background:#888\"></body></html>")
      view_check_page.val = Some(p)
      p
    }
  }
  // (held for the picture: the tall page under them too)
  let hold = @ui.env("MBUI_VIEWCHECK") == "hold"
  let tall = if hold {
    match view_check_tall.val {
      Some(t) => Some(t)
      None => {
        let t = @ui.NativeView::page(view_check_tall_html)
        view_check_tall.val = Some(t)
        Some(t)
      }
    }
  } else {
    None
  }
  // (a picture fitted between pixels: 147.3625 down, 205.875 tall; a page under it, its top 410.4375 down; the tall
  // page's 150 seen from 29,900 down it, in its band of green from 29,000 to 31,000)
  c.column(fn() {
    c.native(v, h=Px(400.0), content=Some((12.0, 147.3625, 366.0, 205.875))) |> ignore
    c.native(p, h=Px(200.0), content=Some((12.0, 10.4375, 366.0, 120.25)), radius=view_check_round) |> ignore
    match tall {
      Some(t) => c.native(t, h=Px(150.0), content=Some((12.0, -29900.0, 366.0, 40000.0))) |> ignore
      None => ()
    }
  })
  |> ignore
  // (each the host has, open as its host says: a page's content ready to be drawn, not loaded only (Android's
  // WebView: a picture taken once it had loaded showed its ground, white); a view it has not is not here)
  let views = match tall {
    Some(t) => [v, p, t]
    None => [v, p]
  }
  let open = views.iter().all(fn(x) { !x.here() || (x.state() != 0 && x.host_done()) })
  // (a host places a view as the frame that told it is painted: Android on its main thread, where the app's exit
  // comes after it; its picture waits for its own word that the view, placed and done, is on the display: VIEWDRAWN)
  if open {
    if hold {
      // (left as it is, for its picture: the contract ends the app)
      if !view_check_placed.val {
        view_check_placed.val = true
        @hostapi.log("VIEWCHECK placed")
      }
      return
    }
    @hostapi.log("VIEWCHECK done")
    @hostapi.exit(0)
  }
}
