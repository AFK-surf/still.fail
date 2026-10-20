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
    #|waiting narrow 13303:cd3af78d
    #|waiting wide 13570:ff17694c
    #|waiting-dark narrow 13493:daa5b238
    #|waiting-dark wide 13703:9507ad4a
    #|finding narrow 9181:f6695278
    #|finding wide 9559:b93a9091
    #|finding-dark narrow 9242:79990343
    #|finding-dark wide 9479:72550c72
    #|code narrow 10589:20b966d6
    #|code wide 11052:c1a375bb
    #|code-dark narrow 10703:94687670
    #|code-dark wide 10923:3d23f923
    #|wrong narrow 11914:e592ac13
    #|wrong wide 12320:4562b8fc
    #|wrong-dark narrow 12076:b2cb4509
    #|wrong-dark wide 12185:b18e6d9a
    #|checking narrow 11242:58eabbf
    #|checking wide 11582:2aa46407
    #|checking-dark narrow 11344:73ce27f4
    #|checking-dark wide 11449:44843109
    #|none narrow 12825:339cd555
    #|none wide 13083:624a7054
    #|none-dark narrow 13007:7a6b9f36
    #|none-dark wide 13228:66411f42
    #|failed narrow 8985:f2550dfa
    #|failed wide 9075:ed814e5e
    #|failed-dark narrow 9103:34343d4f
    #|failed-dark wide 9324:74b2dd20
    #|refused narrow 11125:da8df9bf
    #|refused wide 11289:1d82ebd5
    #|refused-dark narrow 11279:39f3d4a2
    #|refused-dark wide 11520:4d83fe75
    #|nocode narrow 12059:82a19513
    #|nocode wide 12329:185d3c95
    #|nocode-dark narrow 12279:9d0b0124
    #|nocode-dark wide 12472:9c75e855
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
    #|station narrow 31504:219d717f
    #|me-reading narrow 9873:82e96fc0
    #|settings wide 35318:a381ea59
    #|station wide 38432:1371a32a
    #|me-reading wide 20365:7930275e
    #|settings-dark narrow 17246:9104c939
    #|station-dark narrow 31190:f7bceccc
    #|me-reading-dark narrow 9865:e7138d48
    #|settings-dark wide 35296:ce5431c1
    #|station-dark wide 38353:a123ae9a
    #|me-reading-dark wide 20249:7f6d45c8
    #|


  ))
}
