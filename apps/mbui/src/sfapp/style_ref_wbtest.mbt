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
    #|waiting narrow 14175:88121d18
    #|waiting wide 14454:f6896dad
    #|waiting-dark narrow 14365:185f14c9
    #|waiting-dark wide 14587:8c6106d5
    #|finding narrow 9773:15e9d71d
    #|finding wide 10163:4434e03a
    #|finding-dark narrow 9834:230c5cfc
    #|finding-dark wide 10083:2110f22d
    #|code narrow 11269:28bcd053
    #|code wide 11744:5c15de72
    #|code-dark narrow 11383:fc541e89
    #|code-dark wide 11615:85a91664
    #|wrong narrow 12690:1fec415c
    #|wrong wide 13108:6c63721d
    #|wrong-dark narrow 12852:6e04a47e
    #|wrong-dark wide 12973:869866e5
    #|checking narrow 11962:90a9833c
    #|checking wide 12314:ff761566
    #|checking-dark narrow 12064:668c116f
    #|checking-dark wide 12181:4649d5e2
    #|none narrow 13665:6efef70
    #|none wide 13935:f05a901f
    #|none-dark narrow 13847:c047be4b
    #|none-dark wide 14080:9cf1dfa3
    #|failed narrow 9569:3aacaa4f
    #|failed wide 9671:e640b995
    #|failed-dark narrow 9687:abe39e02
    #|failed-dark wide 9920:18617e3d
    #|refused narrow 11853:5c5ca9a6
    #|refused wide 12029:9c5599a6
    #|refused-dark narrow 12007:e4a61453
    #|refused-dark wide 12260:97fb905c
    #|nocode narrow 12851:f5d3a1e
    #|nocode wide 13133:6ddf0a2e
    #|nocode-dark narrow 13071:622b42b9
    #|nocode-dark wide 13276:92713bb0
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
    #|settings narrow 18396:baa45b04
    #|station narrow 33460:6daf665a
    #|me-reading narrow 10505:10cb81f5
    #|settings wide 37578:ec083139
    #|station wide 40836:928ecd8b
    #|me-reading wide 21665:4f15bd5c
    #|settings-dark narrow 18382:e3e145f6
    #|station-dark narrow 33146:3588e6e5
    #|me-reading-dark narrow 10497:8c3dba09
    #|settings-dark wide 37556:28c3ffe9
    #|station-dark wide 40757:b8f57e71
    #|me-reading-dark wide 21549:687d0e66
    #|


  ))
}
