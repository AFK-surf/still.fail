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
    #|waiting narrow 28522:f5c7e7f2
    #|waiting wide 58930:ec6aaa92
    #|waiting-dark narrow 28298:5a441632
    #|waiting-dark wide 58566:6b50f4b4
    #|finding narrow 30929:1523333
    #|finding wide 61356:d9d61f68
    #|finding-dark narrow 30960:6a3b5d61
    #|finding-dark wide 61247:2e1ec6c
    #|code narrow 25280:a3d0967a
    #|code wide 55728:c311802c
    #|code-dark narrow 25102:4a2ddaea
    #|code-dark wide 55410:ead2b810
    #|wrong narrow 26759:c97d140e
    #|wrong wide 57227:e2e65a77
    #|wrong-dark narrow 26251:f6bf5f4
    #|wrong-dark wide 56579:d82c69c5
    #|checking narrow 33032:2d31772b
    #|checking wide 63520:c4f46beb
    #|checking-dark narrow 33024:a73cb04a
    #|checking-dark wide 63372:1719697e
    #|none narrow 27982:c1d47f7b
    #|none wide 58398:eceef2e8
    #|none-dark narrow 27770:614fca0d
    #|none-dark wide 58046:f2a85d58
    #|failed narrow 23729:ce09a1dd
    #|failed wide 54138:ab5dcd2e
    #|failed-dark narrow 23549:807f6d6b
    #|failed-dark wide 53818:9800378a
    #|refused narrow 26104:192021a5
    #|refused wide 56514:82137d5
    #|refused-dark narrow 25582:a22de27d
    #|refused-dark wide 55852:c2c6c62b
    #|nocode narrow 28522:f5c7e7f2
    #|nocode wide 58930:ec6aaa92
    #|nocode-dark narrow 28298:5a441632
    #|nocode-dark wide 58566:6b50f4b4
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
    #|settings narrow 97207:3ca22d18
    #|station narrow 92824:77551c96
    #|me-reading narrow 15655:26a46c63
    #|settings wide 157263:2a6ee926
    #|station wide 204553:2e09a342
    #|me-reading wide 151895:65e068ec
    #|settings-dark narrow 96796:d46978b5
    #|station-dark narrow 92306:aa067833
    #|me-reading-dark narrow 15489:e11e319e
    #|settings-dark wide 156142:6d2c4a8c
    #|station-dark wide 203185:5a52b49d
    #|me-reading-dark wide 150877:2eda0ac5
    #|






















































  ))
}
