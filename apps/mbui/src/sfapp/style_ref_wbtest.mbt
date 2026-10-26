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
    #|waiting narrow 28382:67250274
    #|waiting wide 58232:33e3c0cd
    #|waiting-dark narrow 28298:c308358c
    #|waiting-dark wide 58468:1a32ca65
    #|finding narrow 30847:3124716c
    #|finding wide 61106:9cbbf8e3
    #|finding-dark narrow 30960:195d319d
    #|finding-dark wide 61149:c5b62533
    #|code narrow 25188:d4fc9b60
    #|code wide 55384:6b1297bd
    #|code-dark narrow 25102:4a2ddaea
    #|code-dark wide 55312:3544687
    #|wrong narrow 26397:34c2cc30
    #|wrong wide 56865:f556bf08
    #|wrong-dark narrow 26521:4c4caece
    #|wrong-dark wide 56463:54206d34
    #|checking narrow 32932:680b5e21
    #|checking wide 63252:421b7672
    #|checking-dark narrow 33024:c8028436
    #|checking-dark wide 63274:a8a15daf
    #|none narrow 27850:219b35b1
    #|none wide 57708:631e9a71
    #|none-dark narrow 27770:2dcd3197
    #|none-dark wide 57948:59637045
    #|failed narrow 23609:d6fa21a3
    #|failed wide 53516:90129f99
    #|failed-dark narrow 23609:ceb6b263
    #|failed-dark wide 53716:36d5a5f9
    #|refused narrow 25714:e8ab502d
    #|refused wide 55874:49dec6e
    #|refused-dark narrow 25912:5107a839
    #|refused-dark wide 55732:ac231a5c
    #|nocode narrow 28382:67250274
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
    #|settings narrow 96725:df0939e3
    #|station narrow 92741:b71e3b05
    #|me-reading narrow 15469:3966b92c
    #|settings wide 156809:4773be53
    #|station wide 204110:940aef61
    #|me-reading wide 151467:980658c5
    #|settings-dark narrow 97096:43dc30d9
    #|station-dark narrow 92514:85d6b18f
    #|me-reading-dark narrow 15549:c1528520
    #|settings-dark wide 155983:73c06186
    #|station-dark wide 203282:5beb78a
    #|me-reading-dark wide 150751:89c25d9
    #|























































  ))
}
