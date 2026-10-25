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
    #|waiting wide 58195:8cb6c60a
    #|waiting-dark narrow 28173:ef227a1e
    #|waiting-dark wide 58439:dd37617c
    #|finding narrow 30827:ede8d6da
    #|finding wide 61061:b80f0b46
    #|finding-dark narrow 30815:b27bd604
    #|finding-dark wide 61106:aa80beae
    #|code narrow 25135:a0ddba66
    #|code wide 55339:ffe439fa
    #|code-dark narrow 25003:845ca720
    #|code-dark wide 55275:1487af1c
    #|wrong narrow 26580:b2c7ae56
    #|wrong wide 56844:10f54cfb
    #|wrong-dark narrow 26496:d4ba3524
    #|wrong-dark wide 56774:a9bf40bf
    #|checking narrow 33055:750bbf11
    #|checking wide 63221:8ef4a281
    #|checking-dark narrow 33013:ad5d8ec8
    #|checking-dark wide 63245:2412e678
    #|none narrow 27805:c53b9e
    #|none wide 57659:8175cbed
    #|none-dark narrow 27659:7c5eb898
    #|none-dark wide 57907:e3f691d7
    #|failed narrow 23669:39ac6a87
    #|failed wide 53455:aae02244
    #|failed-dark narrow 23603:b6ad240b
    #|failed-dark wide 53735:1584c3f8
    #|refused narrow 25953:cba9ce20
    #|refused wide 55813:af4c2f25
    #|refused-dark narrow 25923:e63dde
    #|refused-dark wide 56075:3eb696df
    #|nocode narrow 28327:4fcde68e
    #|nocode wide 58195:8cb6c60a
    #|nocode-dark narrow 28173:ef227a1e
    #|nocode-dark wide 58439:dd37617c
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
    #|settings narrow 95512:951d1d07
    #|station narrow 92169:86bd5ad7
    #|me-reading narrow 9899:3a2845c4
    #|settings wide 181946:d8f6d9eb
    #|station wide 229099:ada214d8
    #|me-reading wide 171617:cefc5b20
    #|settings-dark narrow 95616:82183247
    #|station-dark narrow 91903:cc39f57b
    #|me-reading-dark narrow 9940:ffbeae23
    #|settings-dark wide 181513:40c8c4ad
    #|station-dark wide 228661:4defe2cd
    #|me-reading-dark wide 171262:31b160e8
    #|














































  ))
}
