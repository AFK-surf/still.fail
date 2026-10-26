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
    #|waiting wide 58173:32b7b1fe
    #|waiting-dark narrow 28298:c308358c
    #|waiting-dark wide 58409:47135016
    #|finding narrow 30929:1523333
    #|finding wide 61047:4adb4e4
    #|finding-dark narrow 30960:195d319d
    #|finding-dark wide 61090:f555402c
    #|code narrow 25280:a3d0967a
    #|code wide 55325:177ad1ae
    #|code-dark narrow 25102:4a2ddaea
    #|code-dark wide 55253:2122bb60
    #|wrong narrow 26759:9bb92216
    #|wrong wide 56806:6886b03f
    #|wrong-dark narrow 26251:f6bf5f4
    #|wrong-dark wide 56710:ac56e8f9
    #|checking narrow 33032:2d31772b
    #|checking wide 63193:34195bdb
    #|checking-dark narrow 33024:c8028436
    #|checking-dark wide 63215:773e39f8
    #|none narrow 27982:c1d47f7b
    #|none wide 57649:cf72fc2
    #|none-dark narrow 27770:2dcd3197
    #|none-dark wide 57889:25aa07f6
    #|failed narrow 23729:a8abfcf5
    #|failed wide 53457:73b50da2
    #|failed-dark narrow 23549:fcf1f965
    #|failed-dark wide 53725:63a09934
    #|refused narrow 26104:8edc317d
    #|refused wide 55815:cf508861
    #|refused-dark narrow 25582:caf962f7
    #|refused-dark wide 56047:c759b6d5
    #|nocode narrow 28522:f5c7e7f2
    #|nocode wide 58173:32b7b1fe
    #|nocode-dark narrow 28298:c308358c
    #|nocode-dark wide 58409:47135016
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
    #|me-reading narrow 15280:b04a4c41
    #|settings wide 156722:ef96649a
    #|station wide 204051:f06f5e38
    #|me-reading wide 151133:99d4dacb
    #|settings-dark narrow 96796:d46978b5
    #|station-dark narrow 92306:aa067833
    #|me-reading-dark narrow 15064:2d641ee4
    #|settings-dark wide 156366:4304351e
    #|station-dark wide 203563:d3685bed
    #|me-reading-dark wide 150826:618989fe
    #|





















































  ))
}
