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
    #|waiting wide 58232:33e3c0cd
    #|waiting-dark narrow 28298:c308358c
    #|waiting-dark wide 58468:1a32ca65
    #|finding narrow 30929:1523333
    #|finding wide 61106:9cbbf8e3
    #|finding-dark narrow 30960:195d319d
    #|finding-dark wide 61149:c5b62533
    #|code narrow 25280:a3d0967a
    #|code wide 55384:6b1297bd
    #|code-dark narrow 25102:4a2ddaea
    #|code-dark wide 55312:3544687
    #|wrong narrow 26759:9bb92216
    #|wrong wide 56865:13e55616
    #|wrong-dark narrow 26251:f6bf5f4
    #|wrong-dark wide 56769:8dceac34
    #|checking narrow 33032:2d31772b
    #|checking wide 63252:421b7672
    #|checking-dark narrow 33024:c8028436
    #|checking-dark wide 63274:a8a15daf
    #|none narrow 27982:c1d47f7b
    #|none wide 57708:631e9a71
    #|none-dark narrow 27770:2dcd3197
    #|none-dark wide 57948:59637045
    #|failed narrow 23729:a8abfcf5
    #|failed wide 53516:5b76c751
    #|failed-dark narrow 23549:fcf1f965
    #|failed-dark wide 53784:27efb4ab
    #|refused narrow 26104:8edc317d
    #|refused wide 55874:72568460
    #|refused-dark narrow 25582:caf962f7
    #|refused-dark wide 56106:3ae953b0
    #|nocode narrow 28522:f5c7e7f2
    #|nocode wide 58232:33e3c0cd
    #|nocode-dark narrow 28298:c308358c
    #|nocode-dark wide 58468:1a32ca65
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
    #|settings narrow 97207:afd0a6a4
    #|station narrow 92824:77551c96
    #|me-reading narrow 15655:d2e95c14
    #|settings wide 156781:b96c0543
    #|station wide 204110:a368e137
    #|me-reading wide 151467:57f14cbc
    #|settings-dark narrow 96796:d46978b5
    #|station-dark narrow 92306:aa067833
    #|me-reading-dark narrow 15489:b86dcdb
    #|settings-dark wide 156425:2ae6158b
    #|station-dark wide 203622:d37455d8
    #|me-reading-dark wide 151159:9a22e1c8
    #|





















































  ))
}
