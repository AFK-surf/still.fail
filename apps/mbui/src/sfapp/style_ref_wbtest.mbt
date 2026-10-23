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
    #|waiting wide 59494:4701a5e
    #|waiting-dark narrow 29427:29f8e062
    #|waiting-dark wide 59644:a095e242
    #|finding narrow 32265:c4ec98fe
    #|finding wide 62040:4c1b4b74
    #|finding-dark narrow 32233:d2af3c90
    #|finding-dark wide 62069:255dd96a
    #|code narrow 26640:49184c39
    #|code wide 56457:df89a798
    #|code-dark narrow 26488:5afce163
    #|code-dark wide 56345:82f7186c
    #|wrong narrow 28061:25d40192
    #|wrong wide 57897:f2a3e1cf
    #|wrong-dark narrow 27957:a5f59222
    #|wrong-dark wide 57779:a73bfcd
    #|checking narrow 34482:9eaa7d5a
    #|checking wide 64270:ce7a6cf0
    #|checking-dark narrow 34420:aad9bce3
    #|checking-dark wide 64246:4bfae65d
    #|none narrow 29081:a68cf483
    #|none wide 58693:a64c6ea
    #|none-dark narrow 28917:239c3fa0
    #|none-dark wide 58855:982b5a4
    #|failed narrow 24913:807e0fc7
    #|failed wide 54365:35b94d04
    #|failed-dark narrow 24829:6e3375a2
    #|failed-dark wide 54631:7c01148e
    #|refused narrow 27197:6b3f38fe
    #|refused wide 56759:94f402b7
    #|refused-dark narrow 27149:e668b0dd
    #|refused-dark wide 57007:b088a1ed
    #|nocode narrow 28285:2bf94585
    #|nocode wide 57899:fd45fa1
    #|nocode-dark narrow 28133:34ef053a
    #|nocode-dark wide 58059:742e1195
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
    #|me-reading narrow 16968:8259928c
    #|settings wide 195329:d1a62e27
    #|station wide 176462:84f706bd
    #|me-reading wide 150806:91bddd4a
    #|settings-dark narrow 81287:2abbe2eb
    #|station-dark narrow 57077:347438b7
    #|me-reading-dark narrow 17107:226b962c
    #|settings-dark wide 195113:2062d4a4
    #|station-dark wide 176335:48c45529
    #|me-reading-dark wide 150754:e1b7c16
    #|
























  ))
}
