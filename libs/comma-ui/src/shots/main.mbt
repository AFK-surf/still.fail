// The gallery's pictures, drawn offscreen by mbui's renderer at 3 pixels a point (@film.picture: a Tester with the
// host's own text and pictures), no window: each page light and dark, and the second page with each floating part open.
//
//   MBUI_CM_SHOTS=<dir> MBUI_CM_FONT=<Inter's variable .ttf> shots.exe    <dir>/<page>-<open>-<light|dark>.png

///|
fn main {
  let dir = @ui.env("MBUI_CM_SHOTS")
  if dir == "" {
    println("shots: MBUI_CM_SHOTS=<dir> says where the pictures go")
    return
  }
  let font = @ui.env("MBUI_CM_FONT")
  if font != "" {
    ignore(@hostapi.face_add(@hostapi.face_ui, font, 0))
  }
  let shots : Array[(String, Bool, String, Bool)] = [
    ("base", false, "", false),
    ("base", false, "", true),
    ("more", true, "", false),
    ("more", true, "", true),
  ]
  for o in ["menu", "dropdown", "popup", "dialog", "toast", "tooltip"] {
    shots.push(("more", true, o, false))
    shots.push(("more", true, o, true))
  }
  let mut failed = 0
  for s in shots {
    let (name, more, open, dark) = s
    @cm.set_dark(Some(dark))
    let path = "\{dir}/\{name}-\{if open == "" { "closed" } else { open }}-\{if dark { "dark" } else { "light" }}.png"
    let ok = @film.picture(
      fn(_c) {  },
      tree=fn(root) { @pages.page(root, more~, open~) },
      path~,
      w=1280.0,
      h=1000.0,
      scale=3.0,
      dark~,
      at=1000.0,
    )
    println("shots: \{path} \{if ok { "ok" } else { "failed" }}")
    if !ok {
      failed += 1
    }
  }
  if failed > 0 {
    println("shots: \{failed} failed")
  }
}
