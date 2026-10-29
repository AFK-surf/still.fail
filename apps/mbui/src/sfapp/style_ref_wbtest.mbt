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
  reset()
  @settings.reset()
  let src = fixture(mode)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w~, h~, platform=platform_of(w))
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
    #|waiting narrow 28262:a45192a9
    #|waiting wide 58539:45f3317f
    #|waiting-dark narrow 28178:b2c72701
    #|waiting-dark wide 58365:4a3ea5a7
    #|finding narrow 33121:74cd6aa0
    #|finding wide 64076:a0d6f2e4
    #|finding-dark narrow 33234:345996f3
    #|finding-dark wide 64099:ac2ecca1
    #|code narrow 26965:709b30ab
    #|code wide 57371:ec4a55bb
    #|code-dark narrow 26857:8db1e4
    #|code-dark wide 57173:40d280ba
    #|wrong narrow 28174:f1b75cb6
    #|wrong wide 58600:f4ee2c72
    #|wrong-dark narrow 28276:b197332d
    #|wrong-dark wide 58612:5f618385
    #|checking narrow 35248:cde21a98
    #|checking wide 66323:524a97c4
    #|checking-dark narrow 35340:bebe791b
    #|checking-dark wide 66325:e773d25b
    #|none narrow 27730:74bfcc56
    #|none wide 58015:a239d1ed
    #|none-dark narrow 27650:2336e7e0
    #|none-dark wide 57845:33ec120b
    #|failed narrow 23489:e02b43ce
    #|failed wide 53767:ad864551
    #|failed-dark narrow 23489:bdccacda
    #|failed-dark wide 53677:95afa353
    #|refused narrow 25594:de9ddfb6
    #|refused wide 55873:3cf32488
    #|refused-dark narrow 25792:11a40c52
    #|refused-dark wide 55981:f3ac347a
    #|nocode narrow 28262:a45192a9
    #|nocode wide 58539:45f3317f
    #|nocode-dark narrow 28178:b2c72701
    #|nocode-dark wide 58365:4a3ea5a7
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
    #|settings wide 154862:eabf7c9e
    #|station wide 201702:7050e6b6
    #|me-reading wide 149508:71bb77c8
    #|settings-dark narrow 85171:a814463c
    #|station-dark narrow 91128:5f04e45e
    #|me-reading-dark narrow 15808:e5c51641
    #|settings-dark wide 154801:d0ea16e8
    #|station-dark wide 201395:4322dd9f
    #|me-reading-dark wide 149523:3ce67349
    #|






























































  ))
}
