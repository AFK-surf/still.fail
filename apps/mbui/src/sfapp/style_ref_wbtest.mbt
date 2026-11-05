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
    #|waiting narrow 28261:276919d4
    #|waiting wide 58348:6d17d918
    #|waiting-dark narrow 28177:273f1828
    #|waiting-dark wide 58173:f6c85a4e
    #|finding narrow 44148:5a9337a
    #|finding wide 74997:94066c9a
    #|finding-dark narrow 44181:e39eb8b7
    #|finding-dark wide 74939:388b52cf
    #|code narrow 30853:b41da5a4
    #|code wide 61110:2f17e991
    #|code-dark narrow 30715:190e79df
    #|code-dark wide 60881:4f372b64
    #|wrong narrow 28173:7d27636f
    #|wrong wide 58409:d2d3041b
    #|wrong-dark narrow 28275:4b23cc12
    #|wrong-dark wide 58420:45446d48
    #|checking narrow 35247:a55b4d68
    #|checking wide 66124:9566bdf5
    #|checking-dark narrow 35339:cf8b4c9d
    #|checking-dark wide 66125:3e1bfc6c
    #|none narrow 38117:bad80af4
    #|none wide 68304:e957d73f
    #|none-dark narrow 37957:2029186c
    #|none-dark wide 68053:190cb789
    #|failed narrow 23488:6a0bface
    #|failed wide 53576:b25856d2
    #|failed-dark narrow 23488:d6aa537e
    #|failed-dark wide 53485:14a8739a
    #|nocode narrow 28261:276919d4
    #|nocode wide 58348:6d17d918
    #|nocode-dark narrow 28177:273f1828
    #|nocode-dark wide 58173:f6c85a4e
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
    #|settings narrow 76417:a41cf0b3
    #|station narrow 85449:40712050
    #|me-reading narrow 15019:a90f4e9c
    #|settings wide 157036:f63a4178
    #|station wide 223311:75eef3fe
    #|me-reading wide 151749:d1072b03
    #|settings-dark narrow 76685:a9841340
    #|station-dark narrow 85292:f6d55113
    #|me-reading-dark narrow 15109:3c245f0d
    #|settings-dark wide 156918:7d056968
    #|station-dark wide 222962:53a99d6e
    #|me-reading-dark wide 151707:310cb5c6
    #|



































































  ))
}
