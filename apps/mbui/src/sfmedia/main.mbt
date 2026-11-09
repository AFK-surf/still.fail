// A small catalogue of the media library's device frames, with actual app pictures supplied by the caller.
// scripts/media-sample.sh builds it and renders the sample; the same view can be filmed as any mbui view.

///|
fn main {
  // A caller preparing the app's screen uses the same model's dimensions and system bars as the component.
  let info = @film.arg("MBUI_MEDIA_INFO")
  if info != "" {
    let model = match info {
      "phone" => @media.Device::IPhone11Pro
      "tablet" => @media.Device::IPadPro11
      "laptop" => @media.Device::MacBookPro16
      _ => {
        @film.say("media: unknown screen model \{info}")
        @film.exit(2)
        return
      }
    }
    let s = model.screen()
    // The caller consumes this JSON on stdout; @film.say is for diagnostics on stderr.
    println("{\"width\":\{s.width},\"height\":\{s.height},\"platform\":\{s.platform},\"bars\":{\"top\":\{s.top},\"bottom\":\{s.bottom},\"left\":\{s.left},\"right\":\{s.right}}}")
    @film.exit(0)
    return
  }
  let phone = @film.arg("MBUI_MEDIA_PHONE")
  let tablet = @film.arg("MBUI_MEDIA_TABLET")
  let laptop = @film.arg("MBUI_MEDIA_LAPTOP")
  @film.run(fn(c) {
    @figure.canvas(c, 1920.0, 1080.0, 0xF3F1EDFFL, fn() {
      @figure.words(c, 889.0, 201.0, "屏幕模型", 38.0, 0x272B31FFL, weight=600)
      @figure.panel(c, 215.0, 282.0, 280.0, 560.0, 0L, 0.0, fn() {
        @media.device(c, @media.Device::IPhone11Pro, phone, 280.0) |> ignore
      })
      @figure.panel(c, 550.0, 285.0, 400.0, 555.0, 0L, 0.0, fn() {
        @media.device(c, @media.Device::IPadPro11, tablet, 400.0) |> ignore
      })
      @figure.panel(c, 1006.0, 362.0, 700.0, 401.0, 0L, 0.0, fn() {
        @media.device(c, @media.Device::MacBookPro16, laptop, 700.0) |> ignore
      })
      @figure.words(c, 296.0, 865.0, "iPhone 11 Pro", 20.0, 0x535A62FFL)
      @figure.words(c, 694.0, 865.0, "iPad Pro 11", 20.0, 0x535A62FFL)
      @figure.words(c, 1285.0, 785.0, "MacBook Pro 16", 20.0, 0x535A62FFL)
    })
  })
}
