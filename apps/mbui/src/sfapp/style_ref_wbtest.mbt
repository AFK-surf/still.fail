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
    #|waiting wide 58225:bdb2c071
    #|waiting-dark narrow 28126:8d2e104d
    #|waiting-dark wide 58052:5c571917
    #|finding narrow 34240:be2ffdf1
    #|finding wide 64919:7d9721af
    #|finding-dark narrow 34337:52a2c840
    #|finding-dark wide 64925:ed3a50ea
    #|code narrow 26964:88a7f87b
    #|code wide 57110:56244bda
    #|code-dark narrow 26856:ce8b5d5e
    #|code-dark wide 56911:acb54c8d
    #|wrong narrow 28173:7d27636f
    #|wrong wide 58339:676fb52d
    #|wrong-dark narrow 28275:4b23cc12
    #|wrong-dark wide 58350:da1a726c
    #|checking narrow 35247:a55b4d68
    #|checking wide 66046:1e4ab9ff
    #|checking-dark narrow 35339:cf8b4c9d
    #|checking-dark wide 66047:288125e8
    #|none narrow 27676:a0ff063c
    #|none wide 57701:a6d3fcf
    #|none-dark narrow 27598:34020870
    #|none-dark wide 57532:b06e1bb
    #|failed narrow 23435:473d3873
    #|failed wide 53453:1b4b7d7b
    #|failed-dark narrow 23437:6453ad5f
    #|failed-dark wide 53364:94e5c7af
    #|nocode narrow 28208:9506c151
    #|nocode wide 58225:bdb2c071
    #|nocode-dark narrow 28126:8d2e104d
    #|nocode-dark wide 58052:5c571917
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
    #|settings narrow 76418:6d7b9b7
    #|station narrow 94878:7660be12
    #|me-reading narrow 23860:9496c484
    #|settings wide 172657:8e369faa
    #|station wide 239385:51ace4f8
    #|me-reading wide 167370:6aef6d66
    #|settings-dark narrow 76686:fbcc498
    #|station-dark narrow 94746:f9d68295
    #|me-reading-dark narrow 23998:61f49844
    #|settings-dark wide 172577:20f7e7bf
    #|station-dark wide 239051:2a9ce064
    #|me-reading-dark wide 167366:8048abfc
    #|





































































  ))
}
