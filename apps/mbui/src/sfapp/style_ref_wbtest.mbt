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
    #|waiting narrow 13416:6939e2e7
    #|waiting wide 13696:827d4fc6
    #|waiting-dark narrow 13606:55e1046e
    #|waiting-dark wide 13829:d97ef636
    #|finding narrow 9180:8ea4c76d
    #|finding wide 9558:47465ca2
    #|finding-dark narrow 9241:9676d6d6
    #|finding-dark wide 9478:89ed600b
    #|code narrow 10523:d7420693
    #|code wide 10985:70696b66
    #|code-dark narrow 10637:4b4e60d7
    #|code-dark wide 10856:326e1098
    #|wrong narrow 11872:2898b235
    #|wrong wide 12394:77569902
    #|wrong-dark narrow 12034:59b5d685
    #|wrong-dark wide 12259:42319a40
    #|checking narrow 11154:21e710a7
    #|checking wide 11622:87dbbcce
    #|checking-dark narrow 11256:1d87454a
    #|checking-dark wide 11489:b8089c2a
    #|none narrow 12930:fc40a51f
    #|none wide 13188:a776a1cb
    #|none-dark narrow 13112:47f45520
    #|none-dark wide 13333:26bb1f45
    #|failed narrow 9026:8375a88b
    #|failed wide 9116:586c3a8d
    #|failed-dark narrow 9144:2342a766
    #|failed-dark wide 9365:eec0e297
    #|refused narrow 11202:f265669c
    #|refused wide 11366:60b04fe2
    #|refused-dark narrow 11356:78e7709d
    #|refused-dark wide 11597:b58355a4
    #|nocode narrow 12192:355aaeb0
    #|nocode wide 12462:f265d4a
    #|nocode-dark narrow 12412:869e1b27
    #|nocode-dark wide 12605:8a5641d4
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
    #|settings narrow 17260:4646cb7b
    #|station narrow 31484:b094a1e1
    #|me-reading narrow 9873:82e96fc0
    #|settings wide 35318:a381ea59
    #|station wide 38432:1371a32a
    #|me-reading wide 20365:7930275e
    #|settings-dark narrow 17246:9104c939
    #|station-dark narrow 31170:c5363af2
    #|me-reading-dark narrow 9865:e7138d48
    #|settings-dark wide 35296:ce5431c1
    #|station-dark wide 38353:a123ae9a
    #|me-reading-dark wide 20249:7f6d45c8
    #|

  ))
}
