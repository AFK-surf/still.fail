// The native views' contract (docs/determinism.md, "What is compared, and where"; scripts/host_contract.sh HOST views):
// on a real host, MBUI_VIEWCHECK=1: a video's view and a page's placed between pixels (a 16:9 picture fitted in 366
// across, its top 147.3625 down; a page under it at 410.4375, 120.25 tall), each kind the host has (Windows has no
// video player yet: its page alone), what the app told the host on the log (VIEWTOLD, in device pixels: ui's native.mbt) beside where the
// host put it (VIEWAT, each host's own), then `VIEWCHECK done` and the app's end. The two the same, on whole device
// pixels, or the contract fails: else the row its edge half covers shows what is under the canvas.

///|
let view_check_view : Ref[@ui.NativeView?] = Ref(None)

///|
let view_check_page : Ref[@ui.NativeView?] = Ref(None)

///|
/// How long the views are left placed once each the host has is open (ready, or failed: a video with no bytes), before
/// the run ends: the host's placing done by then (Android's, on its main thread, after the frame that told it; a
/// page's on Windows, once its WebView2 is made).
let view_check_ms : Double = 500.0

///|
fn view_check_run(c : @ui.Ctx) -> Unit {
  let v = match view_check_view.val {
    Some(v) => v
    None => {
      let v = @ui.NativeView::video("video/mp4", fn(_offset, _length, answer) { answer(b"", -1.0) })
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
  // (a picture fitted between pixels: 147.3625 down, 205.875 tall; a page under it, its top 410.4375 down)
  c.column(fn() {
    c.native(v, h=Px(400.0), content=Some((12.0, 147.3625, 366.0, 205.875))) |> ignore
    c.native(p, h=Px(200.0), content=Some((12.0, 10.4375, 366.0, 120.25))) |> ignore
  })
  |> ignore
  // (each the host has, open: a view it has not is not here)
  let open = [v, p].iter().all(fn(x) { !x.here() || x.state() != 0 })
  if @kit.after(c, "viewcheck", open, view_check_ms) {
    @host.log("VIEWCHECK done")
    @host.exit(0)
  }
}
