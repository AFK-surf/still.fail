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
    #|waiting narrow 28208:9506c151
    #|waiting wide 58561:95cb81f6
    #|waiting-dark narrow 28126:8d2e104d
    #|waiting-dark wide 58388:a2810814
    #|finding narrow 34240:be2ffdf1
    #|finding wide 65295:e7bc693c
    #|finding-dark narrow 34337:52a2c840
    #|finding-dark wide 65301:832f7fed
    #|code narrow 26964:88a7f87b
    #|code wide 57446:5c092151
    #|code-dark narrow 26856:ce8b5d5e
    #|code-dark wide 57247:303946da
    #|wrong narrow 28173:7d27636f
    #|wrong wide 58675:b9440a2a
    #|wrong-dark narrow 28275:4b23cc12
    #|wrong-dark wide 58686:1155f0c7
    #|checking narrow 35247:a55b4d68
    #|checking wide 66422:4a6b188c
    #|checking-dark narrow 35339:cf8b4c9d
    #|checking-dark wide 66423:3eb6872b
    #|none narrow 27676:a0ff063c
    #|none wide 58037:1ff41a7c
    #|none-dark narrow 27598:34020870
    #|none-dark wide 57868:c472bf60
    #|failed narrow 23435:473d3873
    #|failed wide 53789:444ff120
    #|failed-dark narrow 23437:6453ad5f
    #|failed-dark wide 53700:83d0c2ac
    #|nocode narrow 28208:9506c151
    #|nocode wide 58561:95cb81f6
    #|nocode-dark narrow 28126:8d2e104d
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
  inspect(out.to_string(), content=(
    #|settings narrow 77022:ba68b727
    #|station narrow 95281:75936fb1
    #|me-reading narrow 23860:9496c484
    #|settings wide 172993:24ac3018
    #|station wide 240131:fb326c7c
    #|me-reading wide 167639:a390393c
    #|settings-dark narrow 77290:42efbe58
    #|station-dark narrow 95149:7bceef30
    #|me-reading-dark narrow 23998:61f49844
    #|settings-dark wide 172913:55a02a3d
    #|station-dark wide 239797:5a9c18f0
    #|me-reading-dark wide 167635:20849138
    #|






































































  ))
}
