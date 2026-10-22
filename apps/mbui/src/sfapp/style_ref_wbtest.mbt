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
    #|waiting narrow 19991:fc5132d5
    #|waiting wide 59559:f5cdef4
    #|waiting-dark narrow 20100:f7734d09
    #|waiting-dark wide 59707:533c044
    #|finding narrow 22748:cc7716ad
    #|finding wide 62185:e0e267eb
    #|finding-dark narrow 22826:96c40e2f
    #|finding-dark wide 62212:4573f729
    #|code narrow 17080:dd3f6469
    #|code wide 56570:515b9500
    #|code-dark narrow 17113:a9231966
    #|code-dark wide 56456:443fff44
    #|wrong narrow 18501:be685046
    #|wrong wide 57986:fbd9a0bd
    #|wrong-dark narrow 18582:2fad7829
    #|wrong-dark wide 57866:f8513163
    #|checking narrow 24926:725743bc
    #|checking wide 64383:284f6fee
    #|checking-dark narrow 25045:9d6976fe
    #|checking-dark wide 64357:5b29eda9
    #|none narrow 19481:e5cde6c5
    #|none wide 58766:2f04416a
    #|none-dark narrow 19582:d4830d6b
    #|none-dark wide 58926:8328172a
    #|failed narrow 15385:591cebc5
    #|failed wide 54502:1f46b674
    #|failed-dark narrow 15422:e053c7cd
    #|failed-dark wide 54766:3ad292d4
    #|refused narrow 17669:4a7193c
    #|refused wide 56860:4169e777
    #|refused-dark narrow 17742:cec4f31c
    #|refused-dark wide 57106:4cfff131
    #|nocode narrow 18667:8ab92173
    #|nocode wide 57964:a4ca13e5
    #|nocode-dark narrow 18806:6214666d
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
    #|settings narrow 28173:bc00eb6f
    #|station narrow 51082:32ac51a3
    #|me-reading narrow 16964:bd7fdb81
    #|settings wide 125372:ece7a06d
    #|station wide 136957:303015ea
    #|me-reading wide 113190:3e431981
    #|settings-dark narrow 28108:4adfaee9
    #|station-dark narrow 50774:95590feb
    #|me-reading-dark narrow 17099:6a983f09
    #|settings-dark wide 125347:fa996cb7
    #|station-dark wide 136811:f8a85317
    #|me-reading-dark wide 113206:9fcb1559
    #|
















  ))
}
