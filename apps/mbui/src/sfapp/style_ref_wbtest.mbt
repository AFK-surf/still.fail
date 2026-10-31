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
    #|waiting wide 58360:8f05e01f
    #|waiting-dark narrow 28178:febce866
    #|waiting-dark wide 58183:667c3003
    #|finding narrow 33121:74cd6aa0
    #|finding wide 63889:2bd7d04b
    #|finding-dark narrow 33234:345996f3
    #|finding-dark wide 63909:79ec08e2
    #|code narrow 26965:511d23be
    #|code wide 57192:d434631f
    #|code-dark narrow 26857:88527073
    #|code-dark wide 56991:7648cd46
    #|wrong narrow 28174:8ca892aa
    #|wrong wide 58421:cbd92bc4
    #|wrong-dark narrow 28276:add99b1d
    #|wrong-dark wide 58430:3c09d0cf
    #|checking narrow 35248:cde21a98
    #|checking wide 66136:f8e036a3
    #|checking-dark narrow 35340:bebe791b
    #|checking-dark wide 66135:ac1f5a1c
    #|none narrow 27730:fa6a92a9
    #|none wide 57836:79ec75fd
    #|none-dark narrow 27650:9881fb7
    #|none-dark wide 57663:2aa91f87
    #|failed narrow 23489:21c40c89
    #|failed wide 53588:85d260a9
    #|failed-dark narrow 23489:5c5d6373
    #|failed-dark wide 53495:fcb986ef
    #|refused narrow 25594:d1d4411f
    #|refused wide 55694:102e0fb6
    #|refused-dark narrow 25792:e91492cd
    #|refused-dark wide 55799:4c46444c
    #|nocode narrow 28262:c3271574
    #|nocode wide 58360:8f05e01f
    #|nocode-dark narrow 28178:febce866
    #|nocode-dark wide 58183:667c3003
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
    #|settings wide 154683:a5450693
    #|station wide 201523:b2fbd0d3
    #|me-reading wide 149329:7b300df
    #|settings-dark narrow 85171:a814463c
    #|station-dark narrow 91128:5f04e45e
    #|me-reading-dark narrow 15808:e5c51641
    #|settings-dark wide 154619:bb8b135d
    #|station-dark wide 201213:b63f56dc
    #|me-reading-dark wide 149341:2ad040dc
    #|






























































  ))
}
