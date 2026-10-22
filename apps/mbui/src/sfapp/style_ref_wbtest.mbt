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
    #|waiting narrow 19974:876845e4
    #|waiting wide 59559:f5cdef4
    #|waiting-dark narrow 20082:d27c562b
    #|waiting-dark wide 59689:53f8b489
    #|finding narrow 22731:2340bcae
    #|finding wide 62185:e0e267eb
    #|finding-dark narrow 22808:1f2c04b9
    #|finding-dark wide 62194:6d244462
    #|code narrow 17063:259de09e
    #|code wide 56570:515b9500
    #|code-dark narrow 17095:66f6066c
    #|code-dark wide 56438:d61dd89f
    #|wrong narrow 18484:74636e17
    #|wrong wide 57986:fbd9a0bd
    #|wrong-dark narrow 18564:a2a23247
    #|wrong-dark wide 57848:cf5769d8
    #|checking narrow 24909:cae25dff
    #|checking wide 64383:284f6fee
    #|checking-dark narrow 25027:fac88ce0
    #|checking-dark wide 64339:96da8e00
    #|none narrow 19464:64b42cf4
    #|none wide 58766:2f04416a
    #|none-dark narrow 19564:2c7ba7dd
    #|none-dark wide 58908:4b82c899
    #|failed narrow 15368:1bb26c78
    #|failed wide 54502:1f46b674
    #|failed-dark narrow 15404:2aa2f7eb
    #|failed-dark wide 54748:2dee21f3
    #|refused narrow 17652:ec94491d
    #|refused wide 56860:4169e777
    #|refused-dark narrow 17724:f8676c46
    #|refused-dark wide 57088:733ed4b2
    #|nocode narrow 18650:8d7471c2
    #|nocode wide 57964:a4ca13e5
    #|nocode-dark narrow 18788:a317ec17
    #|nocode-dark wide 58104:d56a7740
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
    #|settings narrow 28119:6a5fb38f
    #|station narrow 51160:e1cba146
    #|me-reading narrow 16937:f31ac204
    #|settings wide 125372:ece7a06d
    #|station wide 136957:47fbb340
    #|me-reading wide 113182:f037c2b5
    #|settings-dark narrow 28142:588f58e7
    #|station-dark narrow 50800:5d5c02b4
    #|me-reading-dark narrow 17081:8bfe4403
    #|settings-dark wide 125329:ccd78796
    #|station-dark wide 136793:fd8c77dc
    #|me-reading-dark wide 113188:2bd5b0f2
    #|














  ))
}
