// 字体, one setting for every frame (web/src/FontSetting.tsx, mobile/Fonts.tsx FontScreen, the Android app's Fonts.kt):
// a face chosen for each of three places (界面, 正文, 代码) and the chat they make seen as it is chosen. What it is for is
// one thing on every screen, so it is one design: the place in view by a choice of three; a chat as the faces set it
// right under that, where the eye is as a face is chosen; the place's faces in a group, each row its name and a line
// of it drawn in itself (how far it has come, what failed, its size where its files are not kept here, at its end;
// the chosen one checked). A row pointed at is tried in the chat first (where there is a pointer: c.lit). This machine's own faces
// (where the host lists them: keyboard and mouse's) are one row more, opening a list of them to find one in. What is chosen
// is the device's (`prefs.set {fonts}`). Its page (fonts_page) and 外观's wide section (appearance.mbt) hold it.

///|
fn font_setting_reset() -> Unit {
  fonts_trying.set("")
  local_try_given.val = ""
  local_open.val = false
  local_filter.set("")
}

///|
/// The face pointed at in the faces' rows, tried in the chat before it is chosen ("" none; "\u{1}" the place's own):
/// said once the faces are built, the chat built again as it changes.
let fonts_trying : @signals.Signal[String] = @signals.signal("", same=fn(a, b) { a == b })

///|
/// The face pointed at as the faces are built, said as fonts_trying once they all are.
// kept across runs: said by the faces' rows as they are built
let fonts_pointed : Ref[String] = Ref("")

///|
/// 字体's setting, a block at a time: the places' choice, the chat as their faces set it, the faces of the place in
/// view.
fn fonts_blocks(c : @ui.Ctx, core : Core) -> Array[() -> Unit] {
  let prefs = (core.topic)("prefs", Map::new()).value
  let chosen_of = fn(place : String) { text(field(prefs, "fonts"), place) }
  let all = items(field(prefs, "faces"), "list")
  let files_state = (core.topic)("fonts", Map::new()).value
  // the faces whose files this device keeps (chosen or not): no size said, choosing one fetches nothing
  let kept = items(files_state, "kept")
  let place = @settings.font_places[@settings.fonts_at.get()]
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
  // the place's own: code's JetBrains Mono, the others' the app's words'
  let own = if place == "code" { (core.own_code_face)() } else { 0 }
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
  // the faces' box, pointed at (one id for the blocks: each is built in a row of its own)
  let faces_id = c.id("fonts/faces")
  [
    fn() {
      let picked = @sf.page_choice(
        c,
        "fonts/place",
        @settings.font_places.map(fn(p) { @sf.t("web-pages.appearance.fonts." + p) }),
        @settings.fonts_at.get(),
      )
      if picked != @settings.fonts_at.get() {
        @settings.fonts_at.set(picked)
      }
    },
    fn() {
      // each place as chosen, the face pointed at (last frame's) tried in its place
      let tried = fonts_trying.get()
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
      // None keeps the chosen face. Some(0) explicitly follows the interface, even if a separate text face is chosen.
      let text_face = match (place, try_face) {
        ("text", Some(f)) => Some(f)
        ("ui", Some(f)) if chosen_of("text") == "" => Some(f)
        _ => {
          let face = if chosen_of("text") == "" { ui_face } else { as_chosen("text") }
          if face == 0 { None } else { Some(face) }
        }
      }
      let code_face = match (place, try_face) {
        ("code", Some(f)) => Some(f)
        _ => {
          let face = as_chosen("code")
          if face == 0 { None } else { Some(face) }
        }
      }
      // held at its tallest while the pointer is over the faces (their box, the gaps between rows too): a face tried
      // sets its words otherwise (taller, wrapped elsewhere), moving the faces under it; let go, the row under the
      // pointer would be another, tried in turn, and the page would shake
      c.box(style=fp_held, id=c.id("fonts/preview"), taps=false, tallest=c.hovered(faces_id), fn() {
        font_preview(c, ui_face, text_face, code_face)
      })
      |> ignore
    },
    fn() {
      fonts_pointed.val = ""
      c.box(style=fp_held, id=faces_id, taps=false, points=true, fn() { @sf.group(c, fn() {
        let none = if place == "text" { "web-pages.appearance.fonts.followUi" } else { "web-pages.appearance.fonts.default" }
        face_row(c, core, place, "none", "", @sf.t(none), own, chosen == "", "", false)
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
            Some(Number(p, ..)) =>
              (@sf.t("android-settings.fonts.downloading", args=[("percent", (p * 100.0).to_int().to_string())]), false)
            _ =>
              if failed != "" {
                (@sf.t("android-settings.fonts.failed", args=[("error", failed)]), true)
              } else if damaged != "" {
                (@sf.t("android-settings.fonts.failed", args=[("error", damaged)]), true)
              } else if (core.face_here)(id) || kept.contains(id.to_json()) {
                ("", false)
              } else {
                (face_size(number(fv, "bytes")), false)
              }
          }
          // not shown in itself (its preview not here): in the place's own
          let face = match shown_in(id) {
            0 => own
            x => x
          }
          face_row(c, core, place, id, id, text(fv, "name"), face, chosen == id, status, bad)
        }
        // a face of this machine's own, where the host lists them (keyboard and mouse's)
        if @ui.local_font_families() != "" {
          local_face_row(c, core, place, chosen)
        }
      }) })
      |> ignore
      fonts_trying.set(fonts_pointed.val)
    },
  ]
}

///|
/// A face of the place (FaceRow, the web's tile): its name and a line of it, each drawn in itself (`face`, a host face:
/// 0 the app's words'); at its end how it stands (`bad` in red), the check where it is the one chosen (`on`); pointed
/// at, tried in the chat; pressed, chosen (`id` "": the place's own).
fn face_row(
  c : @ui.Ctx,
  core : Core,
  place : String,
  key : String,
  id : String,
  name : String,
  face : Int,
  on : Bool,
  status : String,
  bad : Bool,
) -> Unit {
  let rkey = "fonts/face/" + place + "/" + key
  if c.lit(c.id(rkey)) {
    fonts_pointed.val = if id == "" { "\u{1}" } else { id }
  }
  if @sf.choice_row(c, rkey, on, name, body=fn() { face_words(c, rkey, name, face, status, bad) }) {
    @settings.set_font(core, place, if id == "" { None } else { Some(id) })
  }
}

///|
/// A face's name over a line of it, each drawn in `face`; how it stands at their end.
fn face_words(c : @ui.Ctx, key : String, name : String, face : Int, status : String, bad : Bool) -> Unit {
  c.box(style=face_lines, fn() {
    c.rich([@ui.span(name)], key=key + "/name", style=face_name_words, face~) |> ignore
    c.rich([@ui.span(@sf.t("web-pages.appearance.fonts.sampleRow"))], key=key + "/sample", style=face_sample_words, face~)
    |> ignore
  })
  |> ignore
  if status != "" {
    c.box(style=face_status_room, fn() {
      c.text(status, style=if bad { face_status_words.then(@sf.bad) } else { face_status_words }) |> ignore
    })
    |> ignore
  }
}

///|
/// 本机字体 (FontSetting.tsx LocalTile): a row, the family chosen's name in itself where one is (else 本机字体);
/// pressed, a list of the families installed here under it, a field to find one, each pointed at tried in the chat,
/// one chosen as the place's face (`local:<family>`).
fn local_face_row(c : @ui.Ctx, core : Core, place : String, chosen : String) -> Unit {
  let t = @sf.theme()
  let picked = if chosen.has_prefix(local_prefix) {
    chosen.unsafe_substring(start=local_prefix.length(), end=chosen.length())
  } else {
    ""
  }
  // the place's own host face holds it once chosen (faces.mbt): its words drawn in it
  let face = if picked != "" { @settings.font_places.search(place).unwrap_or(0) + 1 } else { 0 }
  let rkey = "fonts/face/" + place + "/local"
  let tid = c.id(rkey)
  let name = if picked != "" { picked } else { @sf.t("web-pages.appearance.fonts.local") }
  @sf.choice_row(c, rkey, picked != "", @sf.t("web-pages.appearance.fonts.local"), body=fn() {
    face_words(c, rkey, name, face, "", false)
  })
  |> ignore
  // (pressed: opened or closed as it is let go, as it is then)
  c.on_press(tid, fn() {
    local_open.val = !local_open.val
    local_filter.set("")
  })
  // (dismissed by the hand, Escape or a press outside it and its row: closed at that moment; closed as one is picked)
  c.with_dismissed(fn(_) { local_open.val = false }, fn() { local_faces(c, core, place, tid, picked) })
}

///|
/// 本机字体's popover under its row `tid`: the families installed here, found by its field (`picked` checked), one
/// picked the place's face.
fn local_faces(c : @ui.Ctx, core : Core, place : String, tid : Int, picked : String) -> Unit {
  let t = @sf.theme()
  @kit.popover(
    c,
    "fonts/local",
    local_open.val,
    tid,
    side=Bottom,
    along=Start,
    label=@sf.t("web-pages.appearance.fonts.local"),
    look=@sf.beside_look(Px(local_panel_w)),
    fn() {
      // its field to find one (localSearch): a small panel's search, as a pick's, its ground setting it apart from
      // the list (no line under it: only a menu's parts are set apart by one)
      c.box(style=local_search, fn() {
        @sf.input(c, "fonts/local/find", placeholder=@sf.t("web-pages.appearance.fonts.searchLocal"), small=true, field=local_filter)
        |> ignore
      })
      |> ignore
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
            if c.lit(rid) {
              fonts_pointed.val = local_prefix + f
            }
            if c.clicked(rid) {
              @settings.set_font(core, place, Some(local_prefix + f))
              local_open.val = false
            }
            c.box(style=(if f == picked || c.lit(rid) { local_row_hot } else { local_row }).then(@sf.pick_high()), id=rid, fn() {
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
  |> ignore
}

///|
/// A chat as the faces set it (FontSetting.tsx Preview, Fonts.kt FontPreview): their message in its bubble, an agent's
/// under its name and when, its words as a chat's are (body_size), on a card of the page; their bubble in its
/// top right corner the ladder's inset in (a block of the ladder's, tall enough not to be a capsule), the agent's words
/// 20 in. `ui_face` is the interface's host face (0: as chosen); `text_face` and `code_face` are tried in their
/// words (None: as chosen, Some(0): the app's face for that kind).
fn font_preview(c : @ui.Ctx, ui_face : Int, text_face : Int?, code_face : Int?) -> Unit {
  @sf.page_card(c, fn() {
    c.box(style=fp_column, fn() {
      c.box(style=fp_mine_room, fn() {
        c.box(style=fp_mine_clear, fn() {  }) |> ignore
        c.box(style=fp_bubble, fn() {
          c.rich([@ui.span(@sf.t("web-pages.appearance.fonts.sampleMine"))], key="fonts/sample-mine", style=@sf.body, words=text_face is None, face=text_face.unwrap_or(0))
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
          size=body_size,
          text_face~,
          code_face~,
        )
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
}

///|
// kept across runs: a value (no field of it changes)
let fp_sample_code : String = "```ts\nform.onsubmit = (e) => {\n  e.preventDefault(); // 0O 1lI\n};\n```"

///|
/// The preview's two messages 12 apart: theirs at the end in a bubble (18 round on the page's ground, 14 by 10 in), out
/// of the card's other top corner; the agent's name (14 semibold in the accent's ink) and when (12 subtle) over its
/// words, 4 apart.
// kept across runs: a value (no field of it changes)
let fp_column : @ui.Style = @ui.css("w=Full gap=S3")

///|
/// The box the chat is held in, and the faces' (Ctx::hovered's): as wide as the page's block.
// kept across runs: a value (no field of it changes)
let fp_held : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let fp_mine_room : @ui.Style = @ui.css("row w=Full justify=JEnd")

///|
/// What their bubble leaves at the row's start: as wide as the chat's at most (MineBubble: 78% of the column), its words
/// wrapping in what is left.
// kept across runs: a value (no field of it changes)
let fp_mine_clear : @ui.Style = @ui.style(w=Pct(fp_mine_clear_share))

///|
let fp_mine_clear_share : Double = 22.0

///|
/// The bubble out of its row, the ladder's inset in from the card's top right, not its words' 20: concentric with its
/// corner there, a block's 18 of the ladder's, all four alike (its row on the column's edges, as the agent's words).
// kept across runs: a value (no field of it changes)
let fp_bubble : @ui.Style = @ui.css("radius=Xl2 bg=Bg px=S3_5 py=S2_5").then(
  @ui.style(mt=@sf.room_of(@sf.corner_inset - @sf.card_pad), mr=@sf.room_of(@sf.corner_inset - @sf.card_pad)),
)

///|
// kept across runs: a value (no field of it changes)
let fp_agent : @ui.Style = @ui.css("w=Full gap=S1")

///|
// kept across runs: a value (no field of it changes)
let fp_who_line : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let fp_who_words : @ui.TextStyle = @ui.text_style(size=Body, weight=Semibold, color=AccentText)

///|
// kept across runs: a value (no field of it changes)
let fp_time_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Subtle)

///|
/// A face's name over a line of it, 2 apart, each on one line: the body's in the ink, the small's in the muted.
// kept across runs: a value (no field of it changes)
let face_lines : @ui.Style = @ui.style(w=@sf.grow, gap=S0_5)

///|
// kept across runs: a value (no field of it changes)
let face_name_words : @ui.TextStyle = @ui.text_style(size=Title, color=Fg, w=Full, max_lines=1)

///|
// kept across runs: a value (no field of it changes)
let face_sample_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, w=Full, max_lines=1)

///|
/// How a face stands, at its row's end: 140 wide at most, the small's subtle on one line.
// kept across runs: a value (no field of it changes)
let face_status_room : @ui.Style = @ui.style(max_w=@sf.face_status_most)

///|
// kept across runs: a value (no field of it changes)
let face_status_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Subtle, wrap=false)

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
pub let local_open : Ref[Bool] = Ref(false)

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
/// The marks in the list of this machine's faces (its field's, the chosen one's check): 14.
let font_check : Double = 14.0

///|
/// The list (localPanel: 300 wide; localList: 320 high at most; the first 400 found).
let local_panel_w : Double = 300.0

///|
let local_list_most : Double = 320.0

///|
let local_most : Int = 400

///|
/// (localSearch: the field at the panel's padding, its rows 6 under it)
// kept across runs: a value (no field of it changes)
let local_search : @ui.Style = @ui.css("w=Full pb=S1_5")

///|
/// (localRow: a menu's item, as high as the screen's (@sf.pick_high), the chosen on the hover ground, its check at its
/// end)
// kept across runs: a value (no field of it changes)
let local_row : @ui.Style = @ui.css("row w=Full px=S2_5 gap=S2 radius=Inner align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let local_row_hot : @ui.Style = local_row.then(@ui.css("bg=Hover"))

///|
/// (localName: the body's size, cut short)
// kept across runs: a value (no field of it changes)
let local_name : @ui.TextStyle = @ui.text_style(size=Body, leading=L7, color=Fg, wrap=false, w=Full, max_lines=1)

///|
// kept across runs: a value (no field of it changes)
let local_note_box : @ui.Style = @ui.css("w=Full px=S2_5 py=S2")

///|
// kept across runs: a value (no field of it changes)
let local_note : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, w=Full)

///|
/// A face's size to fetch, in thousands as the fonts' own pages say it (kB, MB, GB: Android's
/// Formatter.formatShortFileSize), no decimals from 10 up, one below.
fn face_size(bytes : Double) -> String {
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
