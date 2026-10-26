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
    #|waiting narrow 28262:a45192a9
    #|waiting wide 58592:8ab61c3
    #|waiting-dark narrow 28178:b2c72701
    #|waiting-dark wide 58416:3e4d1d2d
    #|finding narrow 33121:8a02ba54
    #|finding wide 64129:4e32db46
    #|finding-dark narrow 33234:ec97182f
    #|finding-dark wide 64150:c7626d97
    #|code narrow 25068:61af9ae1
    #|code wide 55438:27a1a511
    #|code-dark narrow 24982:c8ccca51
    #|code-dark wide 55260:91203a55
    #|wrong narrow 26277:91929809
    #|wrong wide 56667:b46d736e
    #|wrong-dark narrow 26401:2f3e5965
    #|wrong-dark wide 56699:ea85fe78
    #|checking narrow 35333:22401792
    #|checking wide 66376:c4313625
    #|checking-dark narrow 35425:b14aad
    #|checking-dark wide 66376:b2c732c4
    #|none narrow 27730:74bfcc56
    #|none wide 58068:8a2dc0d9
    #|none-dark narrow 27650:2336e7e0
    #|none-dark wide 57896:83adb031
    #|failed narrow 23489:e02b43ce
    #|failed wide 53820:b59da755
    #|failed-dark narrow 23489:bdccacda
    #|failed-dark wide 53728:35fe6dc9
    #|refused narrow 25594:de9ddfb6
    #|refused wide 55926:7a47782e
    #|refused-dark narrow 25792:11a40c52
    #|refused-dark wide 56032:a98aa9ee
    #|nocode narrow 28262:a45192a9
    #|nocode wide 58592:8ab61c3
    #|nocode-dark narrow 28178:b2c72701
    #|nocode-dark wide 58416:3e4d1d2d
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
    #|settings narrow 100925:fe568792
    #|station narrow 91340:3e6ef941
    #|me-reading narrow 15728:84abb5eb
    #|settings wide 154784:246980db
    #|station wide 201624:a28f695d
    #|me-reading wide 149440:3e818d00
    #|settings-dark narrow 101286:3bb8335a
    #|station-dark narrow 91128:5f04e45e
    #|me-reading-dark narrow 15808:23578321
    #|settings-dark wide 154722:3168fbcf
    #|station-dark wide 201316:65e42596
    #|me-reading-dark wide 149444:eb0208a8
    #|


























































  ))
}
