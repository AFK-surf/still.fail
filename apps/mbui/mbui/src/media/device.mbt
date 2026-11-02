// Front-on device frames and their screen apertures. The art is PommePlate's CC0 SVG, with its screen made transparent;
// the screen picture is composed beneath the hardware and is never stretched.

///|
pub(all) enum Device {
  IPhone11Pro
  IPadPro11
  MacBookPro16
} derive(Eq, Debug)

///|
/// A device's artwork size and the screen rectangle within it, in the artwork's original units.
pub(all) struct DeviceGeometry {
  width : Double
  height : Double
  screen_x : Double
  screen_y : Double
  screen_width : Double
  screen_height : Double
}

///|
/// A portrait screen's logical points and example edge-to-edge bars, for drawing an app behind this device's frame.
/// `scale` is the artwork's pixels per point, not the scale an export must use. `platform` is @hostapi.platform's
/// value (0 macOS, 1 iOS). Actual safe areas can change with system UI and orientation; use the host's values when
/// they are available. The bars reserve room; their actual system UI comes from a system capture.
pub(all) struct DeviceScreen {
  width : Double
  height : Double
  scale : Double
  top : Double
  bottom : Double
  left : Double
  right : Double
  platform : Int
}

///|
pub fn Device::screen(self : Device) -> DeviceScreen {
  match self {
    IPhone11Pro => { width: 375.0, height: 812.0, scale: 3.0, top: 44.0, bottom: 34.0, left: 0.0, right: 0.0, platform: 1 }
    IPadPro11 => { width: 834.0, height: 1194.0, scale: 2.0, top: 24.0, bottom: 20.0, left: 0.0, right: 0.0, platform: 1 }
    MacBookPro16 => { width: 1536.0, height: 960.0, scale: 2.0, top: 0.0, bottom: 0.0, left: 0.0, right: 0.0, platform: 0 }
  }
}

///|
pub fn Device::geometry(self : Device) -> DeviceGeometry {
  match self {
    IPhone11Pro => {
      width: 1296.0, height: 2592.0, screen_x: 86.0, screen_y: 78.035606,
      screen_width: 1125.0, screen_height: 2436.0,
    }
    IPadPro11 => {
      width: 1861.0, height: 2581.0, screen_x: 93.0, screen_y: 100.0,
      screen_width: 1668.0, screen_height: 2388.0,
    }
    MacBookPro16 => {
      width: 3910.0, height: 2236.0, screen_x: 419.0, screen_y: 95.0,
      screen_width: 3072.0, screen_height: 1920.0,
    }
  }
}

///|
fn Device::art(self : Device) -> (String, String) {
  match self {
    IPhone11Pro => ("mem:mbui-media/iphone-11-pro", iphone_11_pro_svg)
    IPadPro11 => ("mem:mbui-media/ipad-pro-11", ipad_pro_11_svg)
    MacBookPro16 => ("mem:mbui-media/macbook-pro-16", macbook_pro_16_svg)
  }
}

///|
/// The device drawn `width` points wide with a real screen picture beneath its hardware. A picture of another aspect
/// is contained with black around it, never stretched or cropped. System bars and window controls, when wanted, belong
/// in the picture itself. Produce the picture at the device's logical screen size separately from its pixel scale.
pub fn device(c : @ui.Ctx, model : Device, screen : String, width : Double) -> Int {
  let g = model.geometry()
  let scale = width / g.width
  let (art, svg) = model.art()
  if !@ui.has_image(art) {
    @ui.add_vector_image(art, @utf8.encode(svg), fn(data, px) { @svg.rasterize(data, px) })
  }
  c.box(w=Px(width), h=Px(g.height * scale), name="media-device", fn() {
    c.box(
      left=g.screen_x * scale,
      top=g.screen_y * scale,
      w=Px(g.screen_width * scale),
      h=Px(g.screen_height * scale),
      bg=0x000000FFL,
      clip=true,
      name="media-screen",
      fn() {
        c.image(screen, w=Fill(1.0), h=Fill(1.0), fit=FitContain, bg=0x000000FFL, fade=false) |> ignore
      },
    )
    |> ignore
    c.layer(fn() {
      c.image(art, w=Fill(1.0), h=Fill(1.0), fit=FitFill, bg=0L, fade=false) |> ignore
    })
    |> ignore
  })
}
