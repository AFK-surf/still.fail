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
/// The app over fixture `mode`, `w` × `h`, its first frame (and, with `page`, a settings page pushed): the draw list.
fn screen_drawlist(mode : String, w : Double, h : Double, page? : String = "") -> String {
  reset()
  @settings.reset()
  let src = fixture(mode)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w~, h~)
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
    #|waiting narrow 29599:bfe98887
    #|waiting wide 59836:759b70af
    #|waiting-dark narrow 29427:29f8e062
    #|waiting-dark wide 59936:bc4c46bc
    #|finding narrow 23487:6f4a19bf
    #|finding wide 53548:46979f06
    #|finding-dark narrow 23379:6bb9808b
    #|finding-dark wide 53446:f2f32f5b
    #|code narrow 26640:49184c39
    #|code wide 56799:2be775ab
    #|code-dark narrow 26488:5afce163
    #|code-dark wide 56637:657011e0
    #|wrong narrow 28061:25d40192
    #|wrong wide 58239:12a17be8
    #|wrong-dark narrow 27957:a5f59222
    #|wrong-dark wide 58071:42c8445b
    #|checking narrow 26657:72a8a4b0
    #|checking wide 56751:956b7a20
    #|checking-dark narrow 26505:d4765730
    #|checking-dark wide 56589:d3c8c157
    #|none narrow 29081:a68cf483
    #|none wide 59035:7da6d155
    #|none-dark narrow 28917:239c3fa0
    #|none-dark wide 59147:16b73efc
    #|failed narrow 24913:807e0fc7
    #|failed wide 54707:779b8183
    #|failed-dark narrow 24829:6e3375a2
    #|failed-dark wide 54923:b5d0574e
    #|refused narrow 27197:6b3f38fe
    #|refused wide 57101:9984ce52
    #|refused-dark narrow 27149:e668b0dd
    #|refused-dark wide 57299:581f6e61
    #|nocode narrow 28285:2bf94585
    #|nocode wide 58241:5ce8e3a6
    #|nocode-dark narrow 28133:34ef053a
    #|nocode-dark wide 58351:b00d9b57
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
    #|settings narrow 81183:b241c4bb
    #|station narrow 57285:ffeeaf6
    #|me-reading narrow 8018:e855e289
    #|settings wide 196154:58a21f75
    #|station wide 220105:2307d4c3
    #|me-reading wide 169026:cd5bf0eb
    #|settings-dark narrow 81287:2abbe2eb
    #|station-dark narrow 57077:347438b7
    #|me-reading-dark narrow 8081:87b8dafd
    #|settings-dark wide 195778:551ad4d4
    #|station-dark wide 219737:1a65fd2f
    #|me-reading-dark wide 168701:8649ea97
    #|































  ))
}
