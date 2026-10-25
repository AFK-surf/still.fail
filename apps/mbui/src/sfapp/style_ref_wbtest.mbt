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
    #|waiting narrow 28382:62f4aca6
    #|waiting wide 58167:bc405c65
    #|waiting-dark narrow 28228:95c33ba0
    #|waiting-dark wide 58411:cf80c241
    #|finding narrow 30925:503c811d
    #|finding wide 61047:3348b3f0
    #|finding-dark narrow 30913:f031fa9b
    #|finding-dark wide 61092:a66a3be2
    #|code narrow 25188:b8b35c32
    #|code wide 55319:21ae9c89
    #|code-dark narrow 25056:d93a866e
    #|code-dark wide 55255:60a51b73
    #|wrong narrow 26613:92c50060
    #|wrong wide 56800:15d51e02
    #|wrong-dark narrow 26529:5595144c
    #|wrong-dark wide 56730:25c88d54
    #|checking narrow 33010:2b017c49
    #|checking wide 63193:856182f2
    #|checking-dark narrow 32968:d564c480
    #|checking-dark wide 63217:9f609cd7
    #|none narrow 27850:5bc911d7
    #|none wide 57643:79693395
    #|none-dark narrow 27704:6014a47f
    #|none-dark wide 57891:2fc81a89
    #|failed narrow 23657:5f017dbf
    #|failed wide 53451:70b84de5
    #|failed-dark narrow 23591:17b2bc3f
    #|failed-dark wide 53731:73902f45
    #|refused narrow 25978:fd569df3
    #|refused wide 55809:ce456c1e
    #|refused-dark narrow 25948:5d7dd11
    #|refused-dark wide 56071:42f50f56
    #|nocode narrow 28382:62f4aca6
    #|nocode wide 58167:bc405c65
    #|nocode-dark narrow 28228:95c33ba0
    #|nocode-dark wide 58411:cf80c241
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
    #|settings narrow 95989:41935822
    #|station narrow 90796:86bf9c0a
    #|me-reading narrow 13713:cc0d97c9
    #|settings wide 156710:fad04f95
    #|station wide 203101:a073d81b
    #|me-reading wide 149743:59ac81b0
    #|settings-dark narrow 96096:564022fd
    #|station-dark narrow 90532:117795c7
    #|me-reading-dark narrow 13672:c9966393
    #|settings-dark wide 156386:c6e39801
    #|station-dark wide 202688:eaf6ea49
    #|me-reading-dark wide 149486:1d0311d9
    #|




















































  ))
}
