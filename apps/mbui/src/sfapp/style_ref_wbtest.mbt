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
    #|waiting wide 59824:c8d76a3f
    #|waiting-dark narrow 29427:29f8e062
    #|waiting-dark wide 59924:bf26dae
    #|finding narrow 23487:6f4a19bf
    #|finding wide 53536:2b05c616
    #|finding-dark narrow 23379:6bb9808b
    #|finding-dark wide 53434:69e3e951
    #|code narrow 26640:49184c39
    #|code wide 56787:e92c3967
    #|code-dark narrow 26488:5afce163
    #|code-dark wide 56625:27ef4be6
    #|wrong narrow 28061:25d40192
    #|wrong wide 58227:e163cbf4
    #|wrong-dark narrow 27957:a5f59222
    #|wrong-dark wide 58059:66cb2999
    #|checking narrow 26657:72a8a4b0
    #|checking wide 56739:901281ac
    #|checking-dark narrow 26505:d4765730
    #|checking-dark wide 56577:2113e3d
    #|none narrow 29081:a68cf483
    #|none wide 59023:c342598d
    #|none-dark narrow 28917:239c3fa0
    #|none-dark wide 59135:b2c0d55a
    #|failed narrow 24913:807e0fc7
    #|failed wide 54695:b7e23a5f
    #|failed-dark narrow 24829:6e3375a2
    #|failed-dark wide 54911:931735c8
    #|refused narrow 27197:6b3f38fe
    #|refused wide 57089:f94d07aa
    #|refused-dark narrow 27149:e668b0dd
    #|refused-dark wide 57287:64e40f4b
    #|nocode narrow 28285:2bf94585
    #|nocode wide 58229:6cab16b6
    #|nocode-dark narrow 28133:34ef053a
    #|nocode-dark wide 58339:c5bbd965
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
    #|settings wide 196132:218932fe
    #|station wide 176761:7d513d44
    #|me-reading wide 169014:6b4aea11
    #|settings-dark narrow 81287:2abbe2eb
    #|station-dark narrow 57077:347438b7
    #|me-reading-dark narrow 8081:87b8dafd
    #|settings-dark wide 195920:12be85f7
    #|station-dark wide 176584:afef90d9
    #|me-reading-dark wide 168689:c3de9b2b
    #|






























  ))
}
