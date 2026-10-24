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
/// The hand a screen this wide is drawn for: a phone's width a finger's (the phone the screens are of), a desktop's
/// a mouse's.
fn hand_of(w : Double) -> @ui.Pointing {
  if w < @sf.medium_from {
    Finger
  } else {
    Mouse
  }
}

///|
/// The app over fixture `mode`, `w` × `h`, its first frame (and, with `page`, a settings page pushed): the draw list.
fn screen_drawlist(mode : String, w : Double, h : Double, page? : String = "") -> String {
  reset()
  @settings.reset()
  let src = fixture(mode)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w~, h~, pointing=hand_of(w))
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
    #|waiting narrow 29605:e17bf923
    #|waiting wide 57504:6bd00d55
    #|waiting-dark narrow 29433:42533946
    #|waiting-dark wide 57750:3155287
    #|finding narrow 23493:903a5afb
    #|finding wide 60370:955375b1
    #|finding-dark narrow 23385:9802e5df
    #|finding-dark wide 60417:2c64412d
    #|code narrow 26646:665b6f49
    #|code wide 54648:59fb9605
    #|code-dark narrow 26494:2465df7
    #|code-dark wide 54586:d12d327
    #|wrong narrow 28067:fdbb9ee6
    #|wrong wide 56153:329e8a6
    #|wrong-dark narrow 27963:44e53e06
    #|wrong-dark wide 56085:f237a1b6
    #|checking narrow 26663:2136f700
    #|checking wide 62530:44566708
    #|checking-dark narrow 26511:6b1d8240
    #|checking-dark wide 62556:4c6fc953
    #|none narrow 29087:1becf067
    #|none wide 56968:53bb3ac4
    #|none-dark narrow 28923:36bd82b0
    #|none-dark wide 57218:d479fbce
    #|failed narrow 24919:35145563
    #|failed wide 52764:7c17502b
    #|failed-dark narrow 24835:49180586
    #|failed-dark wide 53046:1e0185d3
    #|refused narrow 27203:2923ffca
    #|refused wide 55122:dd5f8fc
    #|refused-dark narrow 27155:491dad75
    #|refused-dark wide 55386:dcfb1a56
    #|nocode narrow 28291:d4c2328d
    #|nocode wide 57504:6bd00d55
    #|nocode-dark narrow 28139:df21ec9e
    #|nocode-dark wide 57750:3155287
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
    #|settings narrow 80353:6470ec6b
    #|station narrow 56546:3fcd0f74
    #|me-reading narrow 9899:3a2845c4
    #|settings wide 196485:460b4102
    #|station wide 219991:9d6bd263
    #|me-reading wide 171057:45b05bc1
    #|settings-dark narrow 80457:79e32647
    #|station-dark narrow 56338:1e0d90f9
    #|me-reading-dark narrow 9940:ffbeae23
    #|settings-dark wide 196111:4cf1d1a
    #|station-dark wide 219626:8efe0687
    #|me-reading-dark wide 170702:f7462037
    #|


































  ))
}
