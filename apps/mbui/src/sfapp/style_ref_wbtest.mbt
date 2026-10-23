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
    #|waiting narrow 20119:c41bb593
    #|waiting wide 59559:f5cdef4
    #|waiting-dark narrow 19962:4df63003
    #|waiting-dark wide 59707:533c044
    #|finding narrow 22785:5e829afe
    #|finding wide 62185:e0e267eb
    #|finding-dark narrow 22768:8ac78329
    #|finding-dark wide 62212:4573f729
    #|code narrow 17160:f24112c1
    #|code wide 56570:515b9500
    #|code-dark narrow 17023:77540a2c
    #|code-dark wide 56456:443fff44
    #|wrong narrow 18581:c75e7342
    #|wrong wide 57986:fbd9a0bd
    #|wrong-dark narrow 18492:405cccc3
    #|wrong-dark wide 57866:f8513163
    #|checking narrow 25002:3f7c2da
    #|checking wide 64383:284f6fee
    #|checking-dark narrow 24955:e1ef40ac
    #|checking-dark wide 64357:5b29eda9
    #|none narrow 19601:2c08218f
    #|none wide 58766:2f04416a
    #|none-dark narrow 19452:b23e8e79
    #|none-dark wide 58926:8328172a
    #|failed narrow 15433:6f0bbf53
    #|failed wide 54502:1f46b674
    #|failed-dark narrow 15364:491adb43
    #|failed-dark wide 54766:3ad292d4
    #|refused narrow 17717:9b213afe
    #|refused wide 56860:4169e777
    #|refused-dark narrow 17684:b6815b3e
    #|refused-dark wide 57106:4cfff131
    #|nocode narrow 18805:6df58d8d
    #|nocode wide 57964:a4ca13e5
    #|nocode-dark narrow 18668:23fac7bb
    #|nocode-dark wide 58122:e3acc8ef
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
    #|settings wide 125372:ece7a06d
    #|station wide 139669:2f66c462
    #|me-reading wide 113198:96e01a9e
    #|settings-dark narrow 81287:2abbe2eb
    #|station-dark narrow 57077:347438b7
    #|me-reading-dark narrow 17107:226b962c
    #|settings-dark wide 125347:fa996cb7
    #|station-dark wide 139596:68517e62
    #|me-reading-dark wide 113214:54b5a144
    #|




















  ))
}
