// A new chat in the wide frame's pane, as the web's (ember web/src/NewChat.tsx NewChatOn, NewChat.css.ts,
// FrequentCombos.tsx): all of it in a column 720 wide at most in the middle of the pane, its middle on the pane's: the
// scene (320 by 160), 新对话, what it does and where; the composer, roomy, its choices in the row under the words (where
// it runs, what it runs on: model_triple.mbt); the frequent combinations under it, what keeps it from starting, and
// the machine's own sessions to go on with.

///|
/// The page on a station, at a desktop's width; `held`, while its stations are read (newchat.mbt new_chat_on): what
/// is said of the station and the choices breathing, the composer taking words but sending nothing.
fn new_chat_page_wide(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  v : Json?,
  station : Json?,
  held? : Bool = false,
  error? : String? = None,
) -> Unit {
  let t = @sf.theme()
  let address = if held { held_address(w, v) } else { text(station, "station") }
  let name = text(station, "name")
  let breathing = error is None
  let here = if name == "" { tr("web-main.newChat.thisMachine") } else { name }
  let col = dmin(new_column_w, c.width - new_column_side)
  // (the composer's own 10 at its sides outside the column: its capsule as wide as the column)
  let room = col + 2.0 * composer_side
  c.box(style=new_wide_page, fn() {
    c.box(style=@ui.style(w=Fixed(room), gap=S2_5, align=ACenter), fn() {
      @sf.drawable(c, if t.dark { "illus_new_chat_dark" } else { "illus_new_chat" }, new_scene_w) |> ignore
      c.box(style=new_wide_title_box, fn() { c.text(tr("web-main.newChat.title"), style=new_wide_title) |> ignore })
      |> ignore
      c.box(style=new_wide_sub_box, fn() {
        // (held: its line breathing, the station's name in it not known yet)
        if held {
          held_line(c, new_held_sub_w, breathing)
        } else {
          c.text(fill("web-main.newChat.sub", [("name", here)]), style=new_wide_sub) |> ignore
        }
      })
      |> ignore
      // its station went as it was written in, or what is sent waits for its quota: said, the page staying
      if flag(v, "down") {
        new_notice(c, fill("web-main.newChat.down", [("name", here)]))
      }
      match opt_text(v, "spent") {
        Some(spent) => new_notice(c, spent)
        None => ()
      }
      let r : ChatRef = { station: address, session: "", title: "", station_name: name }
      // (held with no station to hold it on, its first value not come yet: no draft asked for)
      if !held || address != "" {
        c.box(style=new_wide_composer, fn() {
          c.sized(room, c.height, fn() {
            composer(c, src, r, None, fresh=Some({
              key: "new:" + address,
              placeholder: tr("web-main.newChat.placeholder"),
              send: fn(d) { send_first(c, src, w, v, address, name, d) },
              tools: Some(fn() {
                if held {
                  // where it runs and what it runs on, breathing in their places
                  @sf.bar(c, Px(held_station_w), new_chooser_h, breathing~)
                  @sf.bar(c, Px(held_model_w), new_chooser_h, breathing~)
                } else {
                  new_tools(c, src, w, v, station)
                }
              }),
              held,
            }))
          })
        })
        |> ignore
      }
      let combos = items(v, "frequent")
      if combos.length() > 0 {
        c.box(style=new_wide_frequent, fn() {
          c.text(tr("web-main.combos.short"), style=new_wide_meta) |> ignore
          c.box(style=frequent_flow, flow=true, fn() {
            for combo in combos {
              frequent_chip(c, src, w, Some(combo), false)
            }
          })
          |> ignore
        })
        |> ignore
      }
      // what it waits for, in a line of its own; why its stations could not be read
      match error {
        Some(e) => c.text(e, style=new_wide_error) |> ignore
        None => ()
      }
      if !held && (flag(v, "waiting") || field(v, "model") is None) {
        match opt_text(v, "problem") {
          Some(p) => c.text(p, style=new_wide_meta_wrap) |> ignore
          None => ()
        }
      }
      // the machine's own sessions to go on with, where it kept any
      let blocked = text(v, "blocked")
      if field(station, "overview") is Some(Object(_)) && blocked != "profile" && blocked != "shared" && !src.read_only {
        @settings.machine_sessions_offer(c, settings_core(src, w), address, name)
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// The composer's choices (NewChat.tsx toolbar): where it runs (its stations in a menu), what it runs on (the model
/// control, its panel over the composer); with nothing to run, the way to where models are chosen.
fn new_tools(c : @ui.Ctx, src : Source, w : Workspace, v : Json?, station : Json?) -> Unit {
  let t = @sf.theme()
  let address = text(station, "station")
  let stations = items(v, "stations")
  // where it runs
  let sid = c.id("new/station-menu")
  c.cursor(sid, Hand)
  if c.clicked(sid) {
    wide.station_menu = !wide.station_menu
  }
  let hot = c.hovered(sid) || wide.station_menu
  let b = c.box(style=if hot { new_chooser_on } else { new_chooser }, id=sid, fn() {
    station_or_server(c, text(station, "emoji"), text(station, "icon"), 14.0, if hot { t.p.text } else { t.p.muted })
    c.text(text(station, "name"), style=if hot { triple_words_xs } else { triple_muted_xs }) |> ignore
    @sf.icon(c, "chevron-down", size=12.0, color=t.p.muted) |> ignore
  })
  c.semantics(b, Button, id=sid, label=text(station, "name"))
  let entries = stations.map(fn(s) {
    let s = Some(s)
    @kit.menu_radio(text(s, "id"), text(s, "station") == address, label=text(s, "name"))
  })
  let m = wide_menu(c, "new/stations", wide.station_menu, sid, entries, {}, 220.0)
  if !m.open {
    wide.station_menu = false
  }
  match m.chosen {
    Some(id) => {
      wide.station_menu = false
      pick_new(c, src, w.id, { "station": Json::string(id) })
    }
    None => ()
  }
  // what it runs on: breathing while its profiles are read (the core's `waiting`), not said to be missing
  let p = field(v, "pick")
  if flag(v, "waiting") {
    @sf.bar(c, Px(held_model_w), new_chooser_h, breathing=true)
  } else if p is None || items(p, "options").length() == 0 || text(v, "runtime") == "" || field(v, "model") is None {
    let id = c.id("new/no-models")
    c.cursor(id, Hand)
    if c.clicked(id) {
      app.nav.push(Place("profiles"))
    }
    c.box(style=new_chooser, id~, fn() { c.text(tr("web-main.newChat.noModels"), style=new_link) |> ignore })
    |> ignore
  } else {
    model_triple(c, src, address, "new", up=true, page=p, small=true)
  }
}

///|
/// A line of what is wrong for now (spentNotice): the amber's 12% under it, 8 by 12 in.
fn new_notice(c : @ui.Ctx, words : String) -> Unit {
  c.box(style=new_wide_notice, fn() { c.text(words, style=new_wide_notice_words) |> ignore }) |> ignore
}

///|
/// The column (newChatInner: 720 at most, 32 in from the pane's sides), the scene's width (ILLUS_SIZE: 320).
let new_column_w : Double = 720.0

///|
let new_column_side : Double = 64.0

///|
let new_scene_w : Double = 320.0

///|
/// What the composer stands in from its room at each side (composer.mbt: 10).
let composer_side : Double = 10.0

///|
/// The page (newChat): what it holds in its middle.
// kept across runs: a value (no field of it changes)
let new_wide_page : @ui.Style = @ui.style(w=Full, h=Full, align=ACenter, justify=JCenter)

///|
/// 新对话 (newChatTitle: the heading's 22 on 30, 600), 4 under the scene.
// kept across runs: a value (no field of it changes)
let new_wide_title_box : @ui.Style = @ui.style(pt=S1)

///|
// kept across runs: a value (no field of it changes)
let new_wide_title : @ui.TextStyle = @ui.text_style(size=Xl3, weight=Semibold, color=Fg, wrap=false)

///|
/// What it does (newChatSub: 13 on 20, muted, 8 under it).
// kept across runs: a value (no field of it changes)
let new_wide_sub_box : @ui.Style = @ui.style(w=Full, pb=S2)

///|
// kept across runs: a value (no field of it changes)
let new_wide_sub : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, center=true, w=Full)

///|
// kept across runs: a value (no field of it changes)
let new_wide_composer : @ui.Style = @ui.style(w=Full)

///|
/// The frequent combinations (FrequentCombos.css.ts frequent): their name over them, 8 apart, 12 over and under.
// kept across runs: a value (no field of it changes)
let new_wide_frequent : @ui.Style = @ui.style(w=Full, py=S3, gap=S2, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let new_wide_meta : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let new_wide_error : @ui.TextStyle = @ui.text_style(size=Sm, color=Danger, center=true, w=Full)

///|
/// The line of what it does breathing while its station is not known (its words one line at this width).
let new_held_sub_w : Double = 360.0

///|
/// A chooser's height in the composer's row (new_chooser: S7).
let new_chooser_h : Double = 28.0

///|
// kept across runs: a value (no field of it changes)
let new_wide_meta_wrap : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, center=true, w=Full)

///|
// kept across runs: a value (no field of it changes)
let new_wide_notice : @ui.Style = @ui.style(w=Full, px=S3, py=S2, radius=Xl, bg=A(Warn, O10))

///|
// kept across runs: a value (no field of it changes)
let new_wide_notice_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Fg, w=Full)

///|
/// A chooser in the composer's row (controls.css.ts chooser): 28 high, 8 in, its words 12 and muted; the ink and the
/// ground on hover and while open.
// kept across runs: a value (no field of it changes)
let new_chooser : @ui.Style = @ui.style(row=true, h=S7, px=S2, gap=S1_25, align=ACenter, radius=Lg)

///|
// kept across runs: a value (no field of it changes)
let new_chooser_on : @ui.Style = @ui.style(row=true, h=S7, px=S2, gap=S1_25, align=ACenter, radius=Lg, bg=Hover)

///|
// kept across runs: a value (no field of it changes)
let new_link : @ui.TextStyle = @ui.text_style(size=Xs, color=Link, wrap=false)
