// Exercise the real film host with a missing picture or a native view, neither of which can be rendered offscreen.

///|
fn main {
  let mode = @film.arg("MBUI_FILM_CHECK_MODE")
  let path = @film.arg("MBUI_FILM_CHECK_OUT")
  let native : Ref[@ui.NativeView?] = Ref(None)
  let reveal = Ref(false)
  let scene = fn(c : @ui.Ctx) {
    if mode == "late-missing" || mode == "unused-missing" {
      let button = c.id("reveal")
      c.box(id=button, w=Px(64.0), h=Px(32.0), fn() { c.text(if mode == "late-missing" { "Reveal" } else { "Hide" }) |> ignore }) |> ignore
      if c.clicked(button) { reveal.val = true }
    }
    if mode == "missing" || mode == "late-missing" && reveal.val || mode == "unused-missing" && !reveal.val {
      c.image_bytes("mem:broken", b"not an image")
      c.image("mem:broken", w=Px(64.0), h=Px(64.0), fade=false) |> ignore
    } else if mode == "native" {
      let view = match native.val {
        Some(v) => v
        None => {
          let v = @ui.NativeView::page("<p>content</p>")
          native.val = Some(v)
          v
        }
      }
      c.native(view, w=Px(64.0), h=Px(64.0)) |> ignore
    } else {
      c.box(w=Px(64.0), h=Px(64.0), bg=0xFF0000FFL, fn() {  }) |> ignore
    }
  }
  if @film.arg("MBUI_FILM_CHECK_RUN") == "1" {
    @film.run(scene)
    return
  }
  let ok = @film.film(
    scene,
    script=if mode == "late-missing" { "tap Reveal\nexit" } else { "exit" },
    out=path,
    w=128.0,
    h=128.0,
    scale=1.0,
    allow_incomplete=@film.arg("MBUI_FILM_CHECK_ALLOW") == "1",
  )
  @film.exit(if ok { 0 } else { 1 })
}
