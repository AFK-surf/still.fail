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
    #|waiting narrow 28262:c3271574
    #|waiting wide 58474:e3f9ed0b
    #|waiting-dark narrow 28178:febce866
    #|waiting-dark wide 58300:71e4b5bb
    #|finding narrow 33121:74cd6aa0
    #|finding wide 64011:dfd20d93
    #|finding-dark narrow 33234:345996f3
    #|finding-dark wide 64034:327e1b08
    #|code narrow 26965:511d23be
    #|code wide 57306:d41949bb
    #|code-dark narrow 26857:88527073
    #|code-dark wide 57108:ade4996e
    #|wrong narrow 28174:8ca892aa
    #|wrong wide 58535:d5c509e0
    #|wrong-dark narrow 28276:add99b1d
    #|wrong-dark wide 58547:f53abff7
    #|checking narrow 35248:cde21a98
    #|checking wide 66258:d0778c9b
    #|checking-dark narrow 35340:bebe791b
    #|checking-dark wide 66260:cbd349fa
    #|none narrow 27730:fa6a92a9
    #|none wide 57950:68688a79
    #|none-dark narrow 27650:9881fb7
    #|none-dark wide 57780:7fd4f9cf
    #|failed narrow 23489:21c40c89
    #|failed wide 53702:9f8ca935
    #|failed-dark narrow 23489:5c5d6373
    #|failed-dark wide 53612:48977267
    #|refused narrow 25594:d1d4411f
    #|refused wide 55808:ed06d1a2
    #|refused-dark narrow 25792:e91492cd
    #|refused-dark wide 55916:26b1ee24
    #|nocode narrow 28262:c3271574
    #|nocode wide 58474:e3f9ed0b
    #|nocode-dark narrow 28178:febce866
    #|nocode-dark wide 58300:71e4b5bb
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
    #|settings narrow 84810:b665b714
    #|station narrow 91340:3e6ef941
    #|me-reading narrow 15718:bc76477a
    #|settings wide 154797:9419a95f
    #|station wide 201637:730d066f
    #|me-reading wide 149443:5f66413b
    #|settings-dark narrow 85171:a814463c
    #|station-dark narrow 91128:5f04e45e
    #|me-reading-dark narrow 15808:e5c51641
    #|settings-dark wide 154736:8bb51625
    #|station-dark wide 201330:f8b75c74
    #|me-reading-dark wide 149458:a6348664
    #|






























































  ))
}
