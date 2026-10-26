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
    #|waiting narrow 28262:a45192a9
    #|waiting wide 58082:efa2a45e
    #|waiting-dark narrow 28178:2c85dc0b
    #|waiting-dark wide 58318:63ad4ea
    #|finding narrow 30727:725a4361
    #|finding wide 60956:1073bf7c
    #|finding-dark narrow 30840:59ce360a
    #|finding-dark wide 60999:ca5618b0
    #|code narrow 25068:61af9ae1
    #|code wide 55234:cae717ee
    #|code-dark narrow 24982:c8ccca51
    #|code-dark wide 55162:bb1c8ddc
    #|wrong narrow 26277:91929809
    #|wrong wide 56715:211f0821
    #|wrong-dark narrow 26401:2f3e5965
    #|wrong-dark wide 56313:b4c3c5c5
    #|checking narrow 32812:580b5d16
    #|checking wide 63102:aaf08b1b
    #|checking-dark narrow 32904:f9373a35
    #|checking-dark wide 63124:a355c164
    #|none narrow 27730:74bfcc56
    #|none wide 57558:a651f222
    #|none-dark narrow 27650:8e635352
    #|none-dark wide 57798:27a6f44a
    #|failed narrow 23489:e02b43ce
    #|failed wide 53366:a4516b2a
    #|failed-dark narrow 23489:4ac103b4
    #|failed-dark wide 53566:b319ecde
    #|refused narrow 25594:de9ddfb6
    #|refused wide 55724:e4220577
    #|refused-dark narrow 25792:1083c56c
    #|refused-dark wide 55582:653e1c3d
    #|nocode narrow 28262:a45192a9
    #|nocode wide 58082:efa2a45e
    #|nocode-dark narrow 28178:2c85dc0b
    #|nocode-dark wide 58318:63ad4ea
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
    #|settings narrow 95709:135fd501
    #|station narrow 91340:3e6ef941
    #|me-reading narrow 15456:c5569fdf
    #|settings wide 155013:75c19fcc
    #|station wide 201719:bae5028f
    #|me-reading wide 149675:b9eb5ad4
    #|settings-dark narrow 96080:94228223
    #|station-dark narrow 91113:db027c43
    #|me-reading-dark narrow 15536:ac41601
    #|settings-dark wide 154187:aa890779
    #|station-dark wide 200891:77403242
    #|me-reading-dark wide 148959:15cc2f7c
    #|
























































  ))
}
