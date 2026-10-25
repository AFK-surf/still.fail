// What the styles' migration (mbui's docs/style.md) must leave as it was, byte for byte: the draw lists of the lock's
// waiting page in each of its states, and of screens with kit's components, narrow and wide, light and dark. Each is
// kept as its length and its FNV-1a hash; one that changes is a change to what is drawn.

///|
fn fnv(s : String) -> String {
  let mut h = 0x811c9dc5U
  for ch in s {
    h = (h ^ ch.to_int().reinterpret_as_uint()) * 0x01000193U
  }
  s.length().to_string() + ":" + h.to_string(radix=16)
}

///|
/// The system a screen this wide is drawn on: a phone's width a phone's (Android: the phone the screens are of), a
/// desktop's the Mac's.
fn platform_of(w : Double) -> Int {
  if w < @sf.medium_from {
    2
  } else {
    0
  }
}

///|
/// The app over fixture `mode`, `w` × `h`, its first frame (and, with `page`, a settings page pushed): the draw list.
fn screen_drawlist(mode : String, w : Double, h : Double, page? : String = "") -> String {
  reset()
  @settings.reset()
  let src = fixture(mode)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w~, h~, platform=platform_of(w))
  if page != "" {
    open_setting(page)
  }
  t.draw()
  t.run_for(@ui.nav_push_ms)
  t.drawlist()
}

///|
let style_ref_sizes : Array[(String, Double, Double)] = [("narrow", 390.0, 844.0), ("wide", 1280.0, 800.0)]

///|
test "styles: the lock's waiting page, every state, drawn as before" {
  let out = StringBuilder()
  for state in ["waiting", "finding", "code", "wrong", "checking", "none", "failed", "refused", "nocode"] {
    for dark in ["", "-dark"] {
      for size in style_ref_sizes {
        let (name, w, h) = size
        let d = screen_drawlist("lock-" + state + dark, w, h)
        out.write_string(state + dark + " " + name + " " + fnv(d) + "\n")
      }
    }
  }
  inspect(out.to_string(), content=(
    #|waiting narrow 28327:4fcde68e
    #|waiting wide 57504:6bd00d55
    #|waiting-dark narrow 28173:ef227a1e
    #|waiting-dark wide 57750:3155287
    #|finding narrow 30827:ede8d6da
    #|finding wide 60370:955375b1
    #|finding-dark narrow 30815:b27bd604
    #|finding-dark wide 60417:2c64412d
    #|code narrow 25135:a0ddba66
    #|code wide 54648:59fb9605
    #|code-dark narrow 25003:845ca720
    #|code-dark wide 54586:d12d327
    #|wrong narrow 26580:b2c7ae56
    #|wrong wide 56153:329e8a6
    #|wrong-dark narrow 26496:d4ba3524
    #|wrong-dark wide 56085:f237a1b6
    #|checking narrow 33055:750bbf11
    #|checking wide 62530:44566708
    #|checking-dark narrow 33013:ad5d8ec8
    #|checking-dark wide 62556:4c6fc953
    #|none narrow 27805:c53b9e
    #|none wide 56968:53bb3ac4
    #|none-dark narrow 27659:7c5eb898
    #|none-dark wide 57218:d479fbce
    #|failed narrow 23669:39ac6a87
    #|failed wide 52764:7c17502b
    #|failed-dark narrow 23603:b6ad240b
    #|failed-dark wide 53046:1e0185d3
    #|refused narrow 25953:cba9ce20
    #|refused wide 55122:dd5f8fc
    #|refused-dark narrow 25923:e63dde
    #|refused-dark wide 55386:dcfb1a56
    #|nocode narrow 28327:4fcde68e
    #|nocode wide 57504:6bd00d55
    #|nocode-dark narrow 28173:ef227a1e
    #|nocode-dark wide 57750:3155287
    #|

























  ))
}

///|
test "styles: screens with kit's components (switches, a sheet), drawn as before" {
  let out = StringBuilder()
  for dark in ["", "-dark"] {
    for size in style_ref_sizes {
      let (name, w, h) = size
      let home = screen_drawlist("settings" + dark, w, h, page="home")
      out.write_string("settings" + dark + " " + name + " " + fnv(home) + "\n")
      let station = screen_drawlist("settings" + dark, w, h, page="station:ws1/st1")
      out.write_string("station" + dark + " " + name + " " + fnv(station) + "\n")
      // a settings page's wait line, in its list's rows (built as the list is laid out: still.fail#791)
      let reading = screen_drawlist("settings-me-reading" + dark, w, h, page="me")
      out.write_string("me-reading" + dark + " " + name + " " + fnv(reading) + "\n")
    }
  }
  inspect(out.to_string(), content=(
    #|settings narrow 88657:14e0e2b5
    #|station narrow 55450:8c1dfc69
    #|me-reading narrow 9899:3a2845c4
    #|settings wide 196485:e70fc1a8
    #|station wide 225785:314a59a
    #|me-reading wide 171057:c672e593
    #|settings-dark narrow 88761:9b249b91
    #|station-dark narrow 55062:4ce9e088
    #|me-reading-dark narrow 9940:ffbeae23
    #|settings-dark wide 196111:fe606ef0
    #|station-dark wide 225351:a3047a2f
    #|me-reading-dark wide 170702:618b7c51
    #|








































  ))
}
