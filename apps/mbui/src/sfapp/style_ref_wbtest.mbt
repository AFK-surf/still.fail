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
    #|waiting wide 59686:8968aa76
    #|waiting-dark narrow 29427:29f8e062
    #|waiting-dark wide 59784:52102140
    #|finding narrow 32265:c4ec98fe
    #|finding wide 62232:60e2dec8
    #|finding-dark narrow 32233:d2af3c90
    #|finding-dark wide 62209:4da91f78
    #|code narrow 26640:49184c39
    #|code wide 56649:21c5af86
    #|code-dark narrow 26488:5afce163
    #|code-dark wide 56485:44994ecc
    #|wrong narrow 28061:25d40192
    #|wrong wide 58089:549b5475
    #|wrong-dark narrow 27957:a5f59222
    #|wrong-dark wide 57919:878a46eb
    #|checking narrow 34482:9eaa7d5a
    #|checking wide 64462:79bc7aa0
    #|checking-dark narrow 34420:aad9bce3
    #|checking-dark wide 64386:11e031cb
    #|none narrow 29081:a68cf483
    #|none wide 58885:5f72f164
    #|none-dark narrow 28917:239c3fa0
    #|none-dark wide 58995:a87e4420
    #|failed narrow 24913:807e0fc7
    #|failed wide 54557:d2efacce
    #|failed-dark narrow 24829:6e3375a2
    #|failed-dark wide 54771:ac3f4cca
    #|refused narrow 27197:6b3f38fe
    #|refused wide 56951:af32e5d7
    #|refused-dark narrow 27149:e668b0dd
    #|refused-dark wide 57147:c2f00ef9
    #|nocode narrow 28285:2bf94585
    #|nocode wide 58091:7a715cfb
    #|nocode-dark narrow 28133:34ef053a
    #|nocode-dark wide 58199:4c55a6a7
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
    #|settings wide 195526:baf602c1
    #|station wide 176632:e8a27fcd
    #|me-reading wide 151000:88f6dd89
    #|settings-dark narrow 81287:2abbe2eb
    #|station-dark narrow 57077:347438b7
    #|me-reading-dark narrow 17107:226b962c
    #|settings-dark wide 195258:ef9c49dc
    #|station-dark wide 176453:2401ac9f
    #|me-reading-dark wide 150896:71d6ef13
    #|

























  ))
}
