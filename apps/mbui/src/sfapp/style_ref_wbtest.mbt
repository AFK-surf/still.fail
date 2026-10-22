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
/// The app over fixture `mode`, `w` × `h`, its first frame (and, with `page`, a settings page pushed): the draw list.
fn screen_drawlist(mode : String, w : Double, h : Double, page? : String = "") -> String {
  reset()
  @settings.reset()
  let src = fixture(mode)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w~, h~)
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
    #|waiting narrow 12494:b75e0f8
    #|waiting wide 14447:3c460bee
    #|waiting-dark narrow 12613:d70b90fd
    #|waiting-dark wide 14616:87efb07e
    #|finding narrow 15251:c95cea3c
    #|finding wide 17347:9e9f10a4
    #|finding-dark narrow 15339:ec51b23f
    #|finding-dark wide 17395:6dbd1e9e
    #|code narrow 9583:2d854e87
    #|code wide 11732:abaf7c67
    #|code-dark narrow 9626:7aa50d75
    #|code-dark wide 11639:a8fff689
    #|wrong narrow 11004:131bf554
    #|wrong wide 13096:1a6a32a0
    #|wrong-dark narrow 11095:91c54118
    #|wrong-dark wide 12997:e85fc8c
    #|checking narrow 17429:d589dd20
    #|checking wide 19493:363811b3
    #|checking-dark narrow 17558:368c6215
    #|checking-dark wide 19488:9e8d7234
    #|none narrow 11984:7cb291f8
    #|none wide 13928:326fb73a
    #|none-dark narrow 12095:9db1860f
    #|none-dark wide 14109:ad493066
    #|failed narrow 7888:f270fbe9
    #|failed wide 9664:6fb6c9b0
    #|failed-dark narrow 7935:2c60b55c
    #|failed-dark wide 9949:3692c124
    #|refused narrow 10172:4dfaa026
    #|refused wide 12022:30cb967d
    #|refused-dark narrow 10255:261129ff
    #|refused-dark wide 12289:be72fe1b
    #|nocode narrow 11170:dc248f86
    #|nocode wide 13126:920b2cd7
    #|nocode-dark narrow 11319:cb030fdd
    #|nocode-dark wide 13305:4d911a55
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
    #|settings narrow 20099:f2f21007
    #|station narrow 39876:49925ffb
    #|me-reading narrow 16312:6402ba53
    #|settings wide 38448:1f26bb7
    #|station wide 44166:2535d1e7
    #|me-reading wide 26752:8ef58acb
    #|settings-dark narrow 20068:c3aae350
    #|station-dark narrow 39506:432a2367
    #|me-reading-dark narrow 16454:c7712a8a
    #|settings-dark wide 38457:c74a4c93
    #|station-dark wide 44085:1d0ad9c7
    #|me-reading-dark wide 26804:7b20aace
    #|













  ))
}
