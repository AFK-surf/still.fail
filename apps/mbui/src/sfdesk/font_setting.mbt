// 外观's 字体 on the desktop (ember web/src/FontSetting.tsx, FontSetting.css.ts): the places' switch (界面 / 正文 /
// 代码), the faces of the place in view as tiles, this machine's own faces in a list, and a chat as they set it. What is
// chosen is the device's (`prefs.set {fonts}`), fetched by the app as the phone's fonts page's are.

///|
fn font_setting_reset() -> Unit {
  fonts_trying.val = ""
  local_try_given.val = ""
  local_open.val = false
  local_filter.set("")
}

///|
/// A chat as the faces set it (FontSetting.tsx Preview: a settings card, 20 in, as wide as the setting): their message
/// in its bubble, an agent's under its name and when, its words the body's 14. `ui_face`, `text_face`: the host faces
/// tried in it (0: as the app is set now).
fn font_setting_preview(c : @ui.Ctx, ui_face : Int, text_face : Int) -> Unit {
  c.box(style=font_preview_card, fn() {
    c.box(style=fp_column, fn() {
      c.box(style=fp_mine_room, fn() {
        c.box(style=fp_bubble, fn() {
          c.rich([@ui.span(@sf.t("web-pages.appearance.fonts.sampleMine"))], key="fonts/sample-mine", style=@sf.body, words=true, face=text_face)
          |> ignore
        })
        |> ignore
      })
      |> ignore
      c.box(style=fp_agent, fn() {
        c.box(style=fp_who_line, fn() {
          c.rich([@ui.span("Claude")], key="fonts/sample-who", style=fp_who_words, face=ui_face) |> ignore
          c.rich([@ui.span(@sf.t("web-pages.appearance.fonts.sampleTime"))], key="fonts/sample-time", style=fp_time_words, face=ui_face)
          |> ignore
        })
        |> ignore
        @sf.markdown(
          c,
          @sf.t("web-pages.appearance.fonts.sampleText") + "\n\n" + fp_sample_code + "\n\n" + @sf.t("web-pages.appearance.fonts.sampleAfter"),
          key="fonts/sample",
          size=@sf.text_scale.base.0,
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
// kept across runs: a value (no field of it changes)
let fp_sample_code : String = "```ts\nform.onsubmit = (e) => {\n  e.preventDefault(); // 0O 1lI\n};\n```"

///|
/// The preview's two messages 12 apart: theirs at the end in a bubble (18 round on the page's ground, 14 by 8 in), the
/// agent's name (14 semibold in the accent's ink) and when (12 subtle) over its words, 4 apart.
// kept across runs: a value (no field of it changes)
let fp_column : @ui.Style = @ui.css("w=Full gap=S3")

///|
// kept across runs: a value (no field of it changes)
let fp_mine_room : @ui.Style = @ui.css("w=Full align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let fp_bubble : @ui.Style = @ui.css("radius=Xl2 bg=Bg px=S3_5 py=S2")

///|
// kept across runs: a value (no field of it changes)
let fp_agent : @ui.Style = @ui.css("w=Full gap=S1")

///|
// kept across runs: a value (no field of it changes)
let fp_who_line : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let fp_who_words : @ui.TextStyle = @ui.text_style(size=Base, weight=Semibold, color=AccentText)

///|
// kept across runs: a value (no field of it changes)
let fp_time_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Subtle)


///|
/// The face pointed at in the wide frame's tiles, tried in the preview before it is chosen ("" none; "\u{1}" the place's
/// own).
let fonts_trying : Ref[String] = Ref("")

///|
/// 外观's 字体 in the wide frame (FontSetting.tsx FontSetting): the places' switch (界面 / 正文 / 代码), the faces of the
/// place in view as tiles (默认 or 跟随界面 first), each `Aa 字` and its name drawn in itself, the chosen one ringed and
/// checked; under them a chat as the faces set it, a tile pointed at tried in it first.
fn font_setting(c : @ui.Ctx, core : Core) -> Unit {
  let t = @sf.theme()
  let prefs = (core.topic)("prefs", Map::new()).value
  let chosen_of = fn(place : String) { text(field(prefs, "fonts"), place) }
  let all = items(field(prefs, "faces"), "list")
  let files_state = (core.topic)("fonts", Map::new()).value
  let place = @settings.font_places[@settings.fonts_at.val]
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
    let picked = @sf.segmented(c, "fonts/place", @settings.font_places.map(fn(p) { @sf.t("web-pages.appearance.fonts." + p) }), @settings.fonts_at.val)
    if picked != @settings.fonts_at.val {
      @settings.fonts_at.val = picked
    }
    // (on as many lines as they take: FontSetting.css.ts tiles' auto-fill)
    c.box(style=font_tiles, flow=true, fn() {
      let tile = fn(key : String, id : String, name : String, face : Int, status : String) {
        let tid = c.id("fonts/tile/" + place + "/" + key)
        c.cursor(tid, Hand)
        if c.lit(tid) {
          fonts_trying.val = if id == "" { "\u{1}" } else { id }
        }
        if c.clicked(tid) {
          @settings.set_font(core, place, if id == "" { None } else { Some(id) })
        }
        let on = chosen == id
        let b = c.box(style=if on { font_tile_on } else { font_tile }, id=tid, fn() {
          c.rich([@ui.span(@sf.t("web-pages.appearance.fonts.glyph"))], key="fonts/tile-glyph/" + key, style=font_tile_glyph, face~)
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
      tile("none", "", @sf.t(none), own, "")
      for f in all {
        let fv = Some(f)
        if flag(fv, "mono") != (place == "code") {
          continue
        }
        let id = text(fv, "id")
        let status = match field(field(files_state, "fetching"), id) {
          Some(Number(p, ..)) => @sf.t("android-settings.fonts.downloading", args=[("percent", (p * 100.0).to_int().to_string())])
          _ =>
            match text(field(files_state, "failed"), id) {
              "" => ""
              why => @sf.t("android-settings.fonts.failed", args=[("error", why)])
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
    font_setting_preview(c, ui_face, text_face)
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
let font_tiles : @ui.Style = @ui.css("row w=Full gap=S2_5")

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
let font_tile_on : @ui.Style = font_tile.then(@ui.css("border=B1 border_color=Accent"))

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
let font_tile_check_place : @ui.Style = @ui.css("w=Full h=Full p=S2_5 align=AEnd")

///|
/// A tile as wide as six to the setting's width are, 10 apart (tiles: auto-fill, 96 at least).
let font_tile_w : Double = (font_setting_most - 50.0) / 6.0

///|
/// The wide frame's preview (preview: a settings card, 20 in, as wide as the setting).
// kept across runs: a value (no field of it changes)
let font_preview_card : @ui.Style = @ui.css("w=Full p=S5 radius=Xl3 bg=Card")

///|
/// What a face of this machine's own is said as in the prefs' `fonts` (client/core-ts/src/fonts.ts LOCAL).
let local_prefix : String = "local:"

///|
/// The host face a family of this machine's is tried in (the preview, as a row of the list is pointed at), and the
/// family it holds now ("" none).
let local_try_face : Int = 14

///|
// kept across runs: said by local_tried; font_setting_reset empties it
let local_try_given : Ref[String] = Ref("")

///|
/// Whether 本机字体's list is open, and what is typed to find one in it.
// kept across runs: said by the tile and the list; font_setting_reset puts them back
let local_open : Ref[Bool] = Ref(false)

///|
// kept across runs: said by the list's field; font_setting_reset empties it
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
  let face = if picked != "" { @settings.font_places.search(place).unwrap_or(0) + 1 } else { 0 }
  let tid = c.id("fonts/tile/" + place + "/local")
  c.cursor(tid, Hand)
  if c.clicked(tid) {
    local_open.val = !local_open.val
    local_filter.set("")
  }
  let on = picked != ""
  let b = c.box(style=if on { font_tile_on } else { font_tile }, id=tid, fn() {
    c.rich([@ui.span(if on { @sf.t("web-pages.appearance.fonts.glyph") } else { "…" })], key="fonts/tile-glyph/local", style=font_tile_glyph, face~)
    |> ignore
    c.rich([@ui.span(if on { picked } else { @sf.t("web-pages.appearance.fonts.local") })], key="fonts/tile-name/local", style=if on {
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
  c.semantics(b, Button, id=tid, label=@sf.t("web-pages.appearance.fonts.local"), expanded=local_open.val)
  let p = @kit.popover(
    c,
    "fonts/local",
    local_open.val,
    tid,
    side=Bottom,
    along=Start,
    label=@sf.t("web-pages.appearance.fonts.local"),
    look=fn(c, _, body) { @sf.small_panel(c, w=Px(local_panel_w), body) |> ignore },
    fn() {
      // its field to find one (localSearch)
      c.box(style=local_search, fn() {
        @sf.icon(c, "search", size=font_check, color=t.p.subtle) |> ignore
        c.box(style=local_search_field, fn() {
          ignore(
            c.editor(
              "fonts/local/find",
              field=local_filter,
              placeholder=@sf.t("web-pages.appearance.fonts.searchLocal"),
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
        c.box(style=local_note_box, fn() { c.text(@sf.t("web-pages.appearance.fonts.noMatch"), style=local_note) |> ignore })
        |> ignore
      } else {
        c.capped("fonts/local/list", local_list_most, fn() {
          for f in list {
            let rid = c.id("fonts/local/" + f)
            c.cursor(rid, Hand)
            if c.lit(rid) {
              fonts_trying.val = local_prefix + f
            }
            if c.clicked(rid) {
              @settings.set_font(core, place, Some(local_prefix + f))
              local_open.val = false
            }
            c.box(style=if f == picked || c.lit(rid) { local_row_hot } else { local_row }, id=rid, fn() {
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
let local_search : @ui.Style = @ui.css("row w=Full gap=S2 px=S2_5 pt=S1 pb=S2 align=ACenter")

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
let local_row : @ui.Style = @ui.css("row w=Full min_h=S8 px=S2_5 gap=S2 radius=Xl align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let local_row_hot : @ui.Style = local_row.then(@ui.css("bg=Hover"))

///|
/// (localName: the body's size, cut short)
// kept across runs: a value (no field of it changes)
let local_name : @ui.TextStyle = @ui.text_style(size=Base, leading=L7, color=Fg, wrap=false, w=Full, max_lines=1)

///|
// kept across runs: a value (no field of it changes)
let local_note_box : @ui.Style = @ui.css("w=Full px=S2_5 py=S2")

///|
// kept across runs: a value (no field of it changes)
let local_note : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Muted, w=Full)
