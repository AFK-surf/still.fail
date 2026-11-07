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
    #|waiting narrow 28261:276919d4
    #|waiting wide 58348:6d17d918
    #|waiting-dark narrow 28177:273f1828
    #|waiting-dark wide 58173:f6c85a4e
    #|finding narrow 34240:be2ffdf1
    #|finding wide 64997:dd17f0e5
    #|finding-dark narrow 34337:52a2c840
    #|finding-dark wide 65003:8cb003d6
    #|code narrow 26964:88a7f87b
    #|code wide 57180:53acc254
    #|code-dark narrow 26856:ce8b5d5e
    #|code-dark wide 56981:8e036739
    #|wrong narrow 28173:7d27636f
    #|wrong wide 58409:d2d3041b
    #|wrong-dark narrow 28275:4b23cc12
    #|wrong-dark wide 58420:45446d48
    #|checking narrow 35247:a55b4d68
    #|checking wide 66124:9566bdf5
    #|checking-dark narrow 35339:cf8b4c9d
    #|checking-dark wide 66125:3e1bfc6c
    #|none narrow 27729:50cff18b
    #|none wide 57824:81cbd3e
    #|none-dark narrow 27649:92e439f
    #|none-dark wide 57653:179012c2
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
    #|station narrow 86425:11f0a459
    #|me-reading narrow 23860:9496c484
    #|settings wide 166001:39a69019
    #|station wide 224252:b004f0b5
    #|me-reading wide 160647:be970bd2
    #|settings-dark narrow 76685:a9841340
    #|station-dark narrow 86258:47aff2b5
    #|me-reading-dark narrow 23998:61f49844
    #|settings-dark wide 165931:848c3c0a
    #|station-dark wide 223893:f769f92c
    #|me-reading-dark wide 160653:cb14a5e
    #|




































































  ))
}
