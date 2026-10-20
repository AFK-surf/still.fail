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
    #|waiting narrow 14180:fea611d8
    #|waiting wide 14459:96eb6d3d
    #|waiting-dark narrow 14370:8ac0f737
    #|waiting-dark wide 14592:44f0c809
    #|finding narrow 9773:880f5d03
    #|finding wide 10163:f521ae64
    #|finding-dark narrow 9834:49fa6102
    #|finding-dark wide 10083:a1c186df
    #|code narrow 11269:28bcd053
    #|code wide 11744:5c15de72
    #|code-dark narrow 11383:fc541e89
    #|code-dark wide 11615:85a91664
    #|wrong narrow 12690:1fec415c
    #|wrong wide 13108:6c63721d
    #|wrong-dark narrow 12852:6e04a47e
    #|wrong-dark wide 12973:869866e5
    #|checking narrow 11962:beb4c072
    #|checking wide 12314:6b5deba8
    #|checking-dark narrow 12064:1aab7c99
    #|checking-dark wide 12181:2dd001c8
    #|none narrow 13670:c4c30f20
    #|none wide 13940:e8660877
    #|none-dark narrow 13852:fbdb33cd
    #|none-dark wide 14085:264d58f3
    #|failed narrow 9574:20fd6f39
    #|failed wide 9676:497f5a39
    #|failed-dark narrow 9692:fd1177d2
    #|failed-dark wide 9925:9f5245f1
    #|refused narrow 11858:9960ae02
    #|refused wide 12034:7fb5c594
    #|refused-dark narrow 12012:3ed7e779
    #|refused-dark wide 12265:119b583e
    #|nocode narrow 12856:fb97678e
    #|nocode wide 13138:1daffea2
    #|nocode-dark narrow 13076:307a475f
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
    #|settings narrow 18875:865720ab
    #|station narrow 33480:d25e6434
    #|me-reading narrow 11129:3266fe5e
    #|settings wide 37578:ec083139
    #|station wide 40836:928ecd8b
    #|me-reading wide 21670:ea03ed36
    #|settings-dark narrow 18861:8651d843
    #|station-dark narrow 33166:911c4bf7
    #|me-reading-dark narrow 11121:9e0dad8c
    #|settings-dark wide 37556:28c3ffe9
    #|station-dark wide 40757:b8f57e71
    #|me-reading-dark wide 21554:41ad0dce
    #|





  ))
}
