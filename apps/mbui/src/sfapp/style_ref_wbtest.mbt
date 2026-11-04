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
    #|waiting wide 58401:95c1ebd
    #|waiting-dark narrow 28177:273f1828
    #|waiting-dark wide 58224:d4684317
    #|finding narrow 33120:e0cb13d0
    #|finding wide 63930:9f4f7c0a
    #|finding-dark narrow 33233:7bd3d895
    #|finding-dark wide 63950:d3000bbf
    #|code narrow 26964:88a7f87b
    #|code wide 57233:951cbac9
    #|code-dark narrow 26856:ce8b5d5e
    #|code-dark wide 57032:726c81e
    #|wrong narrow 28173:7d27636f
    #|wrong wide 58462:4eabfb38
    #|wrong-dark narrow 28275:4b23cc12
    #|wrong-dark wide 58471:fe8bb2bd
    #|checking narrow 35247:a55b4d68
    #|checking wide 66177:4541c7d2
    #|checking-dark narrow 35339:cf8b4c9d
    #|checking-dark wide 66176:8bf911b9
    #|none narrow 27729:50cff18b
    #|none wide 57877:338f011b
    #|none-dark narrow 27649:92e439f
    #|none-dark wide 57704:8b9e4363
    #|failed narrow 23488:6a0bface
    #|failed wide 53629:e800ce1f
    #|failed-dark narrow 23488:d6aa537e
    #|failed-dark wide 53536:3d95475b
    #|nocode narrow 28261:276919d4
    #|nocode wide 58401:95c1ebd
    #|nocode-dark narrow 28177:273f1828
    #|nocode-dark wide 58224:d4684317
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
    #|settings wide 157089:e6c308e9
    #|station wide 223364:8ecc0775
    #|me-reading wide 151802:d4231918
    #|settings-dark narrow 76685:a9841340
    #|station-dark narrow 85292:f6d55113
    #|me-reading-dark narrow 15109:3c245f0d
    #|settings-dark wide 156969:48b783a1
    #|station-dark wide 223013:5a4a984d
    #|me-reading-dark wide 151758:469f55b
    #|


































































  ))
}
