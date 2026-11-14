// What the styles' migration (mbui's ui/style.mbt) must leave as it was, byte for byte: the draw lists of the lock's
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
/// The system a screen this wide is drawn on: a phone's width a phone's (Android: the phone the screens are of), a
/// desktop's the Mac's.
fn platform_of(w : Double) -> Int {
  if w < @sf.medium_from {
    2
  } else {
    0
  }
}

///|
/// The app over fixture `mode`, `w` × `h`, its first frame (and, with `page`, a settings page pushed): the draw list.
fn screen_drawlist(mode : String, w : Double, h : Double, page? : String = "") -> String {
  new_run()
  @settings.reset()
  let src = fixture(mode)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform=platform_of(w))
  if page != "" {
    open_setting(page)
  }
  t.draw()
  t.run_for(@ui.move_most_ms)
  t.drawlist()
}

///|
let style_ref_sizes : Array[(String, Double, Double)] = [("narrow", 390.0, 844.0), ("wide", 1280.0, 800.0)]

///|
test "styles: the lock's waiting page, every state, drawn as before" {
  let out = StringBuilder()
  for state in ["waiting", "finding", "code", "wrong", "checking", "none", "failed", "nocode"] {
    for dark in ["", "-dark"] {
      for size in style_ref_sizes {
        let (name, w, h) = size
        let d = screen_drawlist("lock-" + state + dark, w, h)
        out.write_string(state + dark + " " + name + " " + fnv(d) + "\n")
      }
    }
  }
  inspect(out.to_string(), content=(
    #|waiting narrow 28275:39622baf
    #|waiting wide 58561:95cb81f6
    #|waiting-dark narrow 28193:277c0cc7
    #|waiting-dark wide 58388:a2810814
    #|finding narrow 44483:19a881e2
    #|finding wide 75292:ef31b5ff
    #|finding-dark narrow 44536:d1f32a7a
    #|finding-dark wide 75254:5f39daef
    #|code narrow 31619:9deffdf
    #|code wide 61977:d3d20b74
    #|code-dark narrow 31494:1c8c4705
    #|code-dark wide 61761:b97b01c
    #|wrong narrow 28240:97d2f231
    #|wrong wide 58675:b9440a2a
    #|wrong-dark narrow 28342:6b141516
    #|wrong-dark wide 58686:1155f0c7
    #|checking narrow 35321:285a7a7f
    #|checking wide 66422:9d8764b2
    #|checking-dark narrow 35413:543f0fd4
    #|checking-dark wide 66423:5c9c74d5
    #|none narrow 37542:1dbb1867
    #|none wide 67714:168f01d1
    #|none-dark narrow 37420:fd5a9a96
    #|none-dark wide 67501:fd9fa742
    #|failed narrow 23502:ede593dd
    #|failed wide 53789:444ff120
    #|failed-dark narrow 23504:9d059bad
    #|failed-dark wide 53700:83d0c2ac
    #|nocode narrow 28275:39622baf
    #|nocode wide 58561:95cb81f6
    #|nocode-dark narrow 28193:277c0cc7
    #|nocode-dark wide 58388:a2810814
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
      // (a station's page made once: what lies in the window drawn as the old list drew it, each of the four drawn to a
      // picture the same to the byte as main's at 16203ebae7, every glyph shown in the same box and every word seen at
      // the same place; the tree also hands the draw list the rows wholly under the window's foot, cut out by the page's
      // clip, and the shapes they draw, which the old list never drew)
      let station = screen_drawlist("settings" + dark, w, h, page="station:ws1/st1")
      out.write_string("station" + dark + " " + name + " " + fnv(station) + "\n")
      // a settings page's wait line, in its list's rows (built as the list is laid out: still.fail#791)
      let reading = screen_drawlist("settings-me-reading" + dark, w, h, page="me")
      out.write_string("me-reading" + dark + " " + name + " " + fnv(reading) + "\n")
    }
  }
  // (the wide ones, 2026-11-10: 共享调试 a row of the settings' sidebar on a computer too, 关于 under the window's
  // foot for it; the narrow ones, a phone's, had the row)
  // (the wide ones again, 2026-11-10: a sidebar's marks, words and headings 2 in, where its rows' foot capsules start)
  inspect(out.to_string(), content=(
    #|settings narrow 77022:ba68b727
    #|station narrow 68962:b084a34
    #|me-reading narrow 23870:8074bf2b
    #|settings wide 169493:802f151e
    #|station wide 214277:232d9bcb
    #|me-reading wide 164149:d62b64d1
    #|settings-dark narrow 77290:42efbe58
    #|station-dark narrow 68824:85eb5585
    #|me-reading-dark narrow 23998:5789351d
    #|settings-dark wide 169413:9d946751
    #|station-dark wide 213932:42413ff7
    #|me-reading-dark wide 164135:8c5f9435
    #|






































































  ))
}
