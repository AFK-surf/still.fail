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
    #|waiting narrow 29727:8588bcda
    #|waiting wide 59559:f5cdef4
    #|waiting-dark narrow 29558:ecbc39eb
    #|waiting-dark wide 59707:533c044
    #|finding narrow 32393:ac0eb48b
    #|finding wide 62185:e0e267eb
    #|finding-dark narrow 32364:a43859c1
    #|finding-dark wide 62212:4573f729
    #|code narrow 26768:2d514798
    #|code wide 56570:515b9500
    #|code-dark narrow 26619:1b228668
    #|code-dark wide 56456:443fff44
    #|wrong narrow 28189:c2ad8e47
    #|wrong wide 57986:fbd9a0bd
    #|wrong-dark narrow 28088:45d4a6ab
    #|wrong-dark wide 57866:f8513163
    #|checking narrow 34610:736d8faf
    #|checking wide 64383:284f6fee
    #|checking-dark narrow 34551:6b3654e8
    #|checking-dark wide 64357:5b29eda9
    #|none narrow 29209:8ea1cd9e
    #|none wide 58766:2f04416a
    #|none-dark narrow 29048:d25f5671
    #|none-dark wide 58926:8328172a
    #|failed narrow 25041:1e3a069a
    #|failed wide 54502:1f46b674
    #|failed-dark narrow 24960:5d1dcd2b
    #|failed-dark wide 54766:3ad292d4
    #|refused narrow 27325:b9a1548b
    #|refused wide 56860:4169e777
    #|refused-dark narrow 27280:82c4e2f2
    #|refused-dark wide 57106:4cfff131
    #|nocode narrow 28413:e75160cc
    #|nocode wide 57964:a4ca13e5
    #|nocode-dark narrow 28264:7ce22b03
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
    #|settings wide 163541:24da1dc1
    #|station wide 176751:1c322319
    #|me-reading wide 151047:627f7281
    #|settings-dark narrow 81287:2abbe2eb
    #|station-dark narrow 57077:347438b7
    #|me-reading-dark narrow 17107:226b962c
    #|settings-dark wide 163393:43238df4
    #|station-dark wide 176622:48948719
    #|me-reading-dark wide 150993:1d23dbb5
    #|




















  ))
}
