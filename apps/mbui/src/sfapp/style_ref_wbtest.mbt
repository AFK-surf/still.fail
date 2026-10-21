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
    #|waiting narrow 14226:92684e1f
    #|waiting wide 14459:96eb6d3d
    #|waiting-dark narrow 14416:497cfce6
    #|waiting-dark wide 14592:44f0c809
    #|finding narrow 16983:827cbfc9
    #|finding wide 17359:8f74485b
    #|finding-dark narrow 17142:451c09c0
    #|finding-dark wide 17371:2432f037
    #|code narrow 11315:e853ce72
    #|code wide 11744:5c15de72
    #|code-dark narrow 11429:321f7f3e
    #|code-dark wide 11615:85a91664
    #|wrong narrow 12736:993ce597
    #|wrong wide 13108:6c63721d
    #|wrong-dark narrow 12898:8aa92193
    #|wrong-dark wide 12973:869866e5
    #|checking narrow 19161:cf796b1d
    #|checking wide 19505:9a9d6460
    #|checking-dark narrow 19361:b53072de
    #|checking-dark wide 19464:e59003b3
    #|none narrow 13716:3ac4a9d7
    #|none wide 13940:e8660877
    #|none-dark narrow 13898:edf41050
    #|none-dark wide 14085:264d58f3
    #|failed narrow 9620:6caf20ba
    #|failed wide 9676:497f5a39
    #|failed-dark narrow 9738:83c6b857
    #|failed-dark wide 9925:9f5245f1
    #|refused narrow 11904:fb795c7d
    #|refused wide 12034:7fb5c594
    #|refused-dark narrow 12058:f7379a40
    #|refused-dark wide 12265:119b583e
    #|nocode narrow 12902:a3468695
    #|nocode wide 13138:1daffea2
    #|nocode-dark narrow 13122:93a5f5c6
    #|nocode-dark wide 13281:8767585c
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
    #|settings narrow 20077:2b014859
    #|station narrow 39854:80d58861
    #|me-reading narrow 20007:8f4931c7
    #|settings wide 38460:c06e8d92
    #|station wide 44178:2eae8666
    #|me-reading wide 29858:9d6a8024
    #|settings-dark narrow 20044:154fc2c7
    #|station-dark narrow 39482:11e17e30
    #|me-reading-dark narrow 20157:50cc2aab
    #|settings-dark wide 38433:590d59c2
    #|station-dark wide 44061:bc269b3e
    #|me-reading-dark wide 29831:8c8c904e
    #|











  ))
}
