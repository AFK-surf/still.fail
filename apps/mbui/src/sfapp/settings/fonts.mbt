// 外观 › 字体 (the Android app's screens/Fonts.kt, the web phone's mobile/Fonts.tsx): the three places one at a time, a
// chat as their faces set it, and the faces of the place in view, each drawn in itself (its preview: Core's
// face_preview) with a line of it under its name. One picked is kept as the device's (`prefs.set {fonts}`) and fetched
// whole by the app (src/sfapp/faces.mbt): how far it got (the core's `fonts` topic), its size before.

///|
// kept across runs: a table, never written
let font_places : Array[String] = ["ui", "text", "code"]

///|
/// The place in view on the fonts page (its switch).
let fonts_at : Ref[Int] = Ref(0)

///|
/// 外观's row: the faces chosen at a glance (their names, "·" between), opening the page.
fn font_row(c : @ui.Ctx, core : Core) -> Unit {
  let prefs = (core.topic)("prefs", Map::new()).value
  let faces = field(prefs, "faces")
  let names = []
  for place in font_places {
    if text(field(prefs, "fonts"), place) != "" {
      names.push(text(field(faces, place), "name"))
    }
  }
  let value = if names.is_empty() { tr("web-pages.appearance.fonts.default") } else { names.join(" · ") }
  // (the wide frame's under its section's head 字体: its row names what it chooses for)
  let title = if wide.val {
    [
      tr("web-pages.appearance.fonts.ui"),
      tr("web-pages.appearance.fonts.text"),
      tr("web-pages.appearance.fonts.code"),
    ].join(" · ")
  } else {
    tr("web-pages.appearance.fonts.title")
  }
  if go_row(c, "appearance/fonts", title, value~) {
    (core.push)(Fonts)
  }
}

///|
fn fonts_page(c : @ui.Ctx, core : Core) -> Unit {
  let prefs = (core.topic)("prefs", Map::new()).value
  let chosen_of = fn(place : String) { text(field(prefs, "fonts"), place) }
  let faces = field(prefs, "faces")
  let all = items(faces, "list")
  let files_state = (core.topic)("fonts", Map::new()).value
  let place = font_places[fonts_at.val]
  let chosen = chosen_of(place)
  // each face shown in itself: its host face (its preview's), by its place in the list
  let shown_in = fn(id : String) {
    let mut face = 0
    for i, f in all {
      if text(Some(f), "id") == id {
        face = (core.face_preview)(id, i, items(Some(f), "files").iter().any(fn(x) { number(Some(x), "weight") == 0.0 }))
      }
    }
    face
  }
  // as chosen, each place in its face as far as it is here: one whole is the app's already (0: as the app's words
  // are), one coming in its preview
  let as_chosen = fn(p : String) {
    let id = chosen_of(p)
    if id == "" || (core.face_here)(id) {
      0
    } else {
      shown_in(id)
    }
  }
  let ui_face = as_chosen("ui")
  let text_face = if chosen_of("text") == "" { ui_face } else { as_chosen("text") }
  scroll_page(c, "fonts", [
    fn() { top_back(c, core, tr("android-settings.appearance.title")) },
    fn() { large_title(c, tr("web-pages.appearance.fonts.title")) },
    fn() {
      c.box(style=fonts_seg_room, fn() {
        let picked = seg(c, "fonts/place", font_places.map(fn(p) { tr("web-pages.appearance.fonts." + p) }), fonts_at.val, fill=true, height=34.0)
        if picked != fonts_at.val {
          fonts_at.val = picked
        }
      })
      |> ignore
      gap(c, 12.0)
    },
    fn() { font_preview(c, ui_face, text_face) },
    fn() {
      list_card(c, fn() {
        let none = if place == "text" { "web-pages.appearance.fonts.followUi" } else { "web-pages.appearance.fonts.default" }
        // none: the app's own for the place (code's JetBrains Mono; text's as the interface is now)
        let own = if place == "code" { (core.own_code_face)() } else { 0 }
        if face_row(c, "fonts/none/" + place, tr(none), own, chosen == "", "", false) {
          set_font(core, place, None)
        }
        for f in all {
          let fv = Some(f)
          if flag(fv, "mono") != (place == "code") {
            continue
          }
          let id = text(fv, "id")
          let fetching = field(field(files_state, "fetching"), id)
          let failed = text(field(files_state, "failed"), id)
          let damaged = (core.face_failed)(id)
          let (status, bad) = match fetching {
            Some(Number(p, ..)) => (fill("android-settings.fonts.downloading", [("percent", (p * 100.0).to_int().to_string())]), false)
            _ =>
              if failed != "" {
                (fill("android-settings.fonts.failed", [("error", failed)]), true)
              } else if damaged != "" {
                (fill("android-settings.fonts.failed", [("error", damaged)]), true)
              } else if (core.face_here)(id) {
                ("", false)
              } else {
                (short_size(number(fv, "bytes")), false)
              }
          }
          // not shown in itself (its preview not here): code's in the app's own code face
          let face = match shown_in(id) {
            0 => own
            f => f
          }
          if face_row(c, "fonts/face/" + place + "/" + id, text(fv, "name"), face, chosen == id, status, bad) {
            set_font(core, place, Some(id))
          }
        }
      })
    },
    fn() { seg_note(c, tr("web-pages.appearance.fonts.description")) },
    fn() { gap(c, 30.0) },
  ])
}

///|
/// A place's face chosen (None: back to the app's own), kept as the device's.
fn set_font(core : Core, place : String, id : String?) -> Unit {
  let v = match id {
    Some(s) => s.to_json()
    None => Json::null()
  }
  let fonts : Map[String, Json] = {}
  fonts[place] = v
  (core.call)("prefs.set", Json::object({ "fonts": Json::object(fonts) }), fn(_) {  })
}

///|
/// A face (Fonts.kt FaceRow): its name and a line of it, each in itself (`face`, a host face: 0 the app's words'); at
/// its end how it stands (`bad` in red) and a check where it is the one chosen. True on the frame after a tap.
fn face_row(c : @ui.Ctx, key : String, name : String, face : Int, checked : Bool, status : String, bad : Bool) -> Bool {
  let t = @sf.theme()
  list_row(c, key~, fn() {
    c.box(style=face_lines, fn() {
      c.rich([@ui.span(name)], key=key + "/name", style=face_name_words, face~) |> ignore
      c.rich([@ui.span(tr("web-pages.appearance.fonts.sampleRow"))], key=key + "/sample", style=face_sample_words, face~)
      |> ignore
    })
    |> ignore
    if status != "" {
      c.box(style=face_status_room, fn() {
        c.text(status, style=if bad { face_status_words.then(@sf.bad) } else { face_status_words }) |> ignore
      })
      |> ignore
    }
    if checked {
      @sf.icon(c, "check", size=14.0, color=t.p.accent) |> ignore
    }
  })
}

///|
// kept across runs: a value (no field of it changes)
let font_sample_code : String = "```ts\nform.onsubmit = (e) => {\n  e.preventDefault(); // 0O 1lI\n};\n```"

///|
/// A chat as the faces set it (Fonts.kt FontPreview, the web's): their message in its bubble, an agent's under its
/// name. `ui_face`, `text_face`: host faces the faces coming are shown in meanwhile (0: as the app is set now).
fn font_preview(c : @ui.Ctx, ui_face : Int, text_face : Int, wide? : Bool = false) -> Unit {
  // (the wide frame's in 外观 itself: a card of its own as wide as the setting, 20 in; its words the web's 14)
  let card = fn(c : @ui.Ctx, body : () -> Unit) {
    if wide {
      c.box(style=font_preview_card, fn() { body() }) |> ignore
      true
    } else {
      card(c, body)
    }
  }
  card(c, fn() {
    c.box(style=preview_column, fn() {
      c.box(style=preview_mine_room, fn() {
        c.box(style=preview_bubble, fn() {
          c.rich([@ui.span(tr("web-pages.appearance.fonts.sampleMine"))], key="fonts/sample-mine", style=@sf.body, words=true, face=text_face)
          |> ignore
        })
        |> ignore
      })
      |> ignore
      c.box(style=preview_agent, fn() {
        c.box(style=near_beside, fn() {
          c.rich([@ui.span("Claude")], key="fonts/sample-who", style=preview_who_words, face=ui_face) |> ignore
          c.rich([@ui.span(tr("web-pages.appearance.fonts.sampleTime"))], key="fonts/sample-time", style=preview_time_words, face=ui_face)
          |> ignore
        })
        |> ignore
        @sf.markdown(
          c,
          tr("web-pages.appearance.fonts.sampleText") + "\n\n" + font_sample_code + "\n\n" + tr("web-pages.appearance.fonts.sampleAfter"),
          key="fonts/sample",
          size=if wide { @sf.text_scale.base.0 } else { @sf.text_scale.lg.0 },
        )
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// The places' switch's room: 12 in from the page's sides (Fonts.kt:93).
// kept across runs: a value (no field of it changes)
let fonts_seg_room : @ui.Style = @ui.style(w=Full, px=S3)

///|
/// A face's name over a line of it, 2 apart (Fonts.kt:138), each on one line: 16 in the ink, 13 in the muted.
// kept across runs: a value (no field of it changes)
let face_lines : @ui.Style = @ui.style(w=Full, gap=S0_5)

///|
// kept across runs: a value (no field of it changes)
let face_name_words : @ui.TextStyle = @ui.text_style(size=Xl, color=Fg, w=Full, max_lines=1)

///|
// kept across runs: a value (no field of it changes)
let face_sample_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, w=Full, max_lines=1)

///|
/// How a face stands, at its row's end: at most 140 wide (Fonts.kt:142), 12 in the subtle on one line.
// kept across runs: a value (no field of it changes)
let face_status_room : @ui.Style = @ui.style(max_w=@sf.face_status_most)

///|
// kept across runs: a value (no field of it changes)
let face_status_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Subtle, wrap=false)

///|
/// The preview's two messages 12 apart (Fonts.kt:152): theirs at the end in a bubble (18 round on the page's ground,
/// 14 by 8 in), the agent's name (14 semibold in the accent's ink) and when (12 subtle) over its words, 4 apart.
// kept across runs: a value (no field of it changes)
let preview_column : @ui.Style = @ui.style(w=Full, gap=S3)

///|
// kept across runs: a value (no field of it changes)
let preview_mine_room : @ui.Style = @ui.style(w=Full, align=AEnd)

///|
// kept across runs: a value (no field of it changes)
let preview_bubble : @ui.Style = @ui.style(radius=Xl2, bg=Bg, px=S3_5, py=S2)

///|
// kept across runs: a value (no field of it changes)
let preview_agent : @ui.Style = @ui.style(w=Full, gap=S1)

///|
// kept across runs: a value (no field of it changes)
let preview_who_words : @ui.TextStyle = @ui.text_style(size=Base, weight=Semibold, color=AccentText)

///|
// kept across runs: a value (no field of it changes)
let preview_time_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Subtle)

///|
/// A file's size as Android's Formatter.formatShortFileSize says it: in thousands (kB, MB, GB), no decimals from 10
/// up, one below.
fn short_size(bytes : Double) -> String {
  let mut v = bytes
  let mut unit = "B"
  for u in ["kB", "MB", "GB"] {
    if v <= 900.0 {
      break
    }
    v = v / 1000.0
    unit = u
  }
  let n = if unit == "B" || v >= 10.0 {
    v.round().to_int().to_string()
  } else {
    let tenths = (v * 10.0).round().to_int()
    "\{tenths / 10}.\{tenths % 10}"
  }
  n + " " + unit
}

// ---------------------------------------------------------------------------
// The wide frame's: in 外观 itself (FontSetting.tsx)

///|
/// The face pointed at in the wide frame's tiles, tried in the preview before it is chosen ("" none; "\u{1}" the place's
/// own).
let fonts_trying : Ref[String] = Ref("")

///|
/// 外观's 字体 in the wide frame (FontSetting.tsx FontSetting): the places' switch (界面 / 正文 / 代码), the faces of the
/// place in view as tiles (默认 or 跟随界面 first), each `Aa 字` and its name drawn in itself, the chosen one ringed and
/// checked; under them a chat as the faces set it, a tile pointed at tried in it first.
fn font_setting_wide(c : @ui.Ctx, core : Core) -> Unit {
  let t = @sf.theme()
  let prefs = (core.topic)("prefs", Map::new()).value
  let chosen_of = fn(place : String) { text(field(prefs, "fonts"), place) }
  let all = items(field(prefs, "faces"), "list")
  let files_state = (core.topic)("fonts", Map::new()).value
  let place = font_places[fonts_at.val]
  let chosen = chosen_of(place)
  let shown_in = fn(id : String) {
    let mut face = 0
    for i, f in all {
      if text(Some(f), "id") == id {
        face = (core.face_preview)(id, i, items(Some(f), "files").iter().any(fn(x) { number(Some(x), "weight") == 0.0 }))
      }
    }
    face
  }
  let own = if place == "code" { (core.own_code_face)() } else { 0 }
  let as_chosen = fn(p : String) {
    let id = chosen_of(p)
    if id == "" || (core.face_here)(id) {
      0
    } else {
      shown_in(id)
    }
  }
  // what the preview shows: each place as chosen, the one pointed at tried in its place
  let tried = fonts_trying.val
  let try_face = if tried == "\u{1}" {
    Some(own)
  } else if tried.has_prefix(local_prefix) {
    Some(local_tried(tried.unsafe_substring(start=local_prefix.length(), end=tried.length())))
  } else if tried != "" {
    Some(match shown_in(tried) {
      0 => own
      f => f
    })
  } else {
    None
  }
  let ui_face = match (place, try_face) {
    ("ui", Some(f)) => f
    _ => as_chosen("ui")
  }
  let text_face = match (place, try_face) {
    ("text", Some(f)) => f
    ("ui", Some(f)) if chosen_of("text") == "" => f
    _ => if chosen_of("text") == "" { ui_face } else { as_chosen("text") }
  }
  fonts_trying.val = ""
  c.box(style=fonts_wide_setting, fn() {
    let picked = seg(c, "fonts/place", font_places.map(fn(p) { tr("web-pages.appearance.fonts." + p) }), fonts_at.val, compact=true)
    if picked != fonts_at.val {
      fonts_at.val = picked
    }
    c.box(style=font_tiles, fn() {
      let tile = fn(key : String, id : String, name : String, face : Int, status : String) {
        let tid = c.id("fonts/tile/" + place + "/" + key)
        c.cursor(tid, Hand)
        if c.hovered(tid) {
          fonts_trying.val = if id == "" { "\u{1}" } else { id }
        }
        if hit(c, tid) {
          set_font(core, place, if id == "" { None } else { Some(id) })
        }
        let on = chosen == id
        let b = c.box(style=if on { font_tile_on } else { font_tile }, id=tid, fn() {
          c.rich([@ui.span(tr("web-pages.appearance.fonts.glyph"))], key="fonts/tile-glyph/" + key, style=font_tile_glyph, face~)
          |> ignore
          c.rich([@ui.span(if status != "" { status } else { name })], key="fonts/tile-name/" + key, style=if on {
            font_tile_name_on
          } else {
            font_tile_name
          }, face~)
          |> ignore
          if on {
            c.layer(fn() {
              c.box(style=font_tile_check_place, fn() { @sf.icon(c, "check", size=font_check, color=t.p.accent) |> ignore })
              |> ignore
            })
            |> ignore
          }
        })
        c.semantics(b, Button, id=tid, label=name)
      }
      let none = if place == "text" { "web-pages.appearance.fonts.followUi" } else { "web-pages.appearance.fonts.default" }
      tile("none", "", tr(none), own, "")
      for f in all {
        let fv = Some(f)
        if flag(fv, "mono") != (place == "code") {
          continue
        }
        let id = text(fv, "id")
        let status = match field(field(files_state, "fetching"), id) {
          Some(Number(p, ..)) => fill("android-settings.fonts.downloading", [("percent", (p * 100.0).to_int().to_string())])
          _ =>
            match text(field(files_state, "failed"), id) {
              "" => ""
              why => fill("android-settings.fonts.failed", [("error", why)])
            }
        }
        let face = match shown_in(id) {
          0 => own
          x => x
        }
        tile(id, id, text(fv, "name"), face, status)
      }
      // a face of this machine's own, where the host lists them (the desktop's)
      if @ui.local_font_families() != "" {
        local_tile(c, core, place, chosen)
      }
    })
    |> ignore
    font_preview(c, ui_face, text_face, wide=true)
  })
  |> ignore
}

///|
/// A tile's check (14), in its corner.
let font_check : Double = 14.0

///|
/// The setting (setting: 14 apart, 640 wide at most): the switch as wide as its words, the tiles across, the preview.
// kept across runs: a value (no field of it changes)
let fonts_wide_setting : @ui.Style = @ui.style(w=Full, max_w=Fixed(font_setting_most), gap=S3_5, align=AStart)

///|
let font_setting_most : Double = 640.0

///|
/// The tiles (tiles: 96 wide at least, 10 apart; tile: 96 high, 12 by 10 in, the card's corner and ground, ringed 1.5 in
/// the accent when chosen).
// kept across runs: a value (no field of it changes)
let font_tiles : @ui.Style = @ui.style(row=true, w=Full, gap=S2_5)

///|
// kept across runs: a value (no field of it changes)
let font_tile : @ui.Style = @ui.style(
  w=Fixed(font_tile_w),
  h=S24,
  px=S2_5,
  py=S3,
  gap=S1_5,
  align=ACenter,
  justify=JCenter,
  radius=Xl3,
  bg=Card,
  hovered=@ui.patch(bg=Tint),
)

///|
// kept across runs: a value (no field of it changes)
let font_tile_on : @ui.Style = font_tile.then(@ui.style(border=B1, border_color=Accent))

///|
// kept across runs: a value (no field of it changes)
let font_tile_glyph : @ui.TextStyle = @ui.text_style(size=Xl4, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let font_tile_name : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false, max_lines=1)

///|
// kept across runs: a value (no field of it changes)
let font_tile_name_on : @ui.TextStyle = @ui.text_style(size=Xs, color=Fg, wrap=false, max_lines=1)

///|
// kept across runs: a value (no field of it changes)
let font_tile_check_place : @ui.Style = @ui.style(w=Full, h=Full, p=S2_5, align=AEnd)

///|
/// A tile as wide as six to the setting's width are, 10 apart (tiles: auto-fill, 96 at least).
let font_tile_w : Double = (font_setting_most - 50.0) / 6.0

///|
/// The wide frame's preview (preview: a settings card, 20 in, as wide as the setting).
// kept across runs: a value (no field of it changes)
let font_preview_card : @ui.Style = @ui.style(w=Full, p=S5, radius=Xl3, bg=Card)

///|
/// What a face of this machine's own is said as in the prefs' `fonts` (client/core-ts/src/fonts.ts LOCAL).
let local_prefix : String = "local:"

///|
/// The host face a family of this machine's is tried in (the preview, as a row of the list is pointed at), and the
/// family it holds now ("" none).
let local_try_face : Int = 14

///|
// kept across runs: said by local_tried; core.mbt's reset empties it
let local_try_given : Ref[String] = Ref("")

///|
/// Whether 本机字体's list is open, and what is typed to find one in it.
// kept across runs: said by the tile and the list; core.mbt's reset puts them back
let local_open : Ref[Bool] = Ref(false)

///|
// kept across runs: said by the list's field; core.mbt's reset empties it
let local_filter : @ui.Field = @ui.Field::new()

///|
/// The host face family `family` of this machine's is tried in (given to it once); 0 where the host has none of it.
fn local_tried(family : String) -> Int {
  if local_try_given.val != family {
    @ui.face_clear(local_try_face)
    local_try_given.val = if @ui.face_add_family(local_try_face, family) { family } else { "" }
  }
  if local_try_given.val == family {
    local_try_face
  } else {
    0
  }
}

///|
/// The families installed here (the host's: @ui.local_font_families), in its order.
fn local_families() -> Array[String] {
  let parsed = @json.parse(@ui.local_font_families()) catch { _ => Json::null() }
  // in the host's order: its person's language's (local_font_families)
  match parsed {
    Array(a) => a.filter_map(fn(x) { if x is String(s) { Some(s) } else { None } })
    _ => []
  }
}

///|
/// 本机字体 (FontSetting.tsx LocalTile): a tile, the family chosen's name in itself where one is (else 本机字体 under
/// "…"); pressed, a list of the families installed here under it, a field to find one, each pointed at tried in the
/// preview, one chosen as the place's face (`local:<family>`).
fn local_tile(c : @ui.Ctx, core : Core, place : String, chosen : String) -> Unit {
  let t = @sf.theme()
  let picked = if chosen.has_prefix(local_prefix) {
    chosen.unsafe_substring(start=local_prefix.length(), end=chosen.length())
  } else {
    ""
  }
  // the place's own host face holds it once chosen (faces.mbt): its words drawn in it
  let face = if picked != "" { font_places.search(place).unwrap_or(0) + 1 } else { 0 }
  let tid = c.id("fonts/tile/" + place + "/local")
  c.cursor(tid, Hand)
  if c.clicked(tid) {
    local_open.val = !local_open.val
    local_filter.set("")
  }
  let on = picked != ""
  let b = c.box(style=if on { font_tile_on } else { font_tile }, id=tid, fn() {
    c.rich([@ui.span(if on { tr("web-pages.appearance.fonts.glyph") } else { "…" })], key="fonts/tile-glyph/local", style=font_tile_glyph, face~)
    |> ignore
    c.rich([@ui.span(if on { picked } else { tr("web-pages.appearance.fonts.local") })], key="fonts/tile-name/local", style=if on {
      font_tile_name_on
    } else {
      font_tile_name
    }, face~)
    |> ignore
    if on {
      c.layer(fn() {
        c.box(style=font_tile_check_place, fn() { @sf.icon(c, "check", size=font_check, color=t.p.accent) |> ignore }) |> ignore
      })
      |> ignore
    }
  })
  c.semantics(b, Button, id=tid, label=tr("web-pages.appearance.fonts.local"), expanded=local_open.val)
  let p = @kit.popover(
    c,
    "fonts/local",
    local_open.val,
    tid,
    side=Bottom,
    along=Start,
    label=tr("web-pages.appearance.fonts.local"),
    look=fn(c, _, body) { @sf.panel(c, w=Px(local_panel_w), body) |> ignore },
    fn() {
      // its field to find one (localSearch)
      c.box(style=local_search, fn() {
        @sf.icon(c, "search", size=font_check, color=t.p.subtle) |> ignore
        c.box(style=local_search_field, fn() {
          ignore(
            c.editor(
              "fonts/local/find",
              field=local_filter,
              placeholder=tr("web-pages.appearance.fonts.searchLocal"),
              font_size=13.0,
              max_lines=1,
              plain=true,
              color=t.p.text,
              placeholder_color=t.p.subtle,
              caret_color=t.p.accent,
            ),
          )
        })
        |> ignore
      })
      |> ignore
      c.box(style=local_rule, fn() {  }) |> ignore
      let find = local_filter.text().trim(chars=" ").to_lower()
      let shown = local_families().filter(fn(f) { find == "" || f.to_lower().contains(find) })
      let list = if shown.length() > local_most { shown[:local_most].to_array() } else { shown }
      if list.length() == 0 {
        c.box(style=local_note_box, fn() { c.text(tr("web-pages.appearance.fonts.noMatch"), style=local_note) |> ignore })
        |> ignore
      } else {
        c.capped("fonts/local/list", local_list_most, fn() {
          for f in list {
            let rid = c.id("fonts/local/" + f)
            c.cursor(rid, Hand)
            if c.hovered(rid) {
              fonts_trying.val = local_prefix + f
            }
            if c.clicked(rid) {
              set_font(core, place, Some(local_prefix + f))
              local_open.val = false
            }
            c.box(style=if f == picked || c.hovered(rid) { local_row_hot } else { local_row }, id=rid, fn() {
              c.text(f, style=local_name) |> ignore
              if f == picked {
                @sf.icon(c, "check", size=font_check, color=t.p.text) |> ignore
              }
            })
            |> ignore
          }
        })
        |> ignore
      }
    },
  )
  local_open.val = p.value
}

///|
/// The list (localPanel: 300 wide; localList: 320 high at most; the first 400 found).
let local_panel_w : Double = 300.0

///|
let local_list_most : Double = 320.0

///|
let local_most : Int = 400

///|
/// (localSearch: its icon and field 8 apart, a line under it, 4 over and 8 under)
// kept across runs: a value (no field of it changes)
let local_search : @ui.Style = @ui.style(row=true, w=Full, gap=S2, px=S2_5, pt=S1, pb=S2, align=ACenter)

///|
/// (its line: the words' colour faintly, 6 over the list)
// kept across runs: a value (no field of it changes)
let local_rule : @ui.Style = @ui.style(w=Full, h=Fixed(local_rule_h), mb=S1_5, bg=Line)

///|
let local_rule_h : Double = 1.0

///|
// kept across runs: a value (no field of it changes)
let local_search_field : @ui.Style = @ui.style(w=@sf.grow)

///|
/// (localRow: a menu's item, the chosen on the hover ground, its check at its end)
// kept across runs: a value (no field of it changes)
let local_row : @ui.Style = @ui.style(row=true, w=Full, min_h=S8, px=S2_5, gap=S2, radius=Xl, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let local_row_hot : @ui.Style = local_row.then(@ui.style(bg=Hover))

///|
/// (localName: the body's size, cut short)
// kept across runs: a value (no field of it changes)
let local_name : @ui.TextStyle = @ui.text_style(size=Base, leading=L7, color=Fg, wrap=false, w=Full, max_lines=1)

///|
// kept across runs: a value (no field of it changes)
let local_note_box : @ui.Style = @ui.style(w=Full, px=S2_5, py=S2)

///|
// kept across runs: a value (no field of it changes)
let local_note : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Muted, w=Full)
