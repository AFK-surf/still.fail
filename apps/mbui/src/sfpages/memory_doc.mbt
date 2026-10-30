// One of a station's memory pages (设置 › 记忆 › it; web/src/Memory.tsx MemoryDoc, Memory.css.ts; the narrow app's
// mobile/Memory.tsx MemoryDocScreen), one page in every frame: the global memory a part at a time, or a skill (what
// kind it is and when it is read, sharing it with the workspace's other stations, its pages to pick between), its
// text as people read it, on a card where the page is narrow (the narrow app's), on the page where it is wide (the
// web's). Its pages' pills go on in lines where the room ends: every one there to pick, none behind a ⋯ nor scrolled
// out (the phone's copy, gone, left the last out). What it says is the core's (looks.ts).

///|
/// The page in view of each memory page, by its station and skill ("" the global memory): picked by its chips.
// kept across runs: said by its chips; memory_doc_reset (sfpages' reset) empties it
let doc_at : Map[String, Int] = {}

///|
fn memory_doc_reset() -> Unit {
  doc_at.clear()
}

///|
/// The page (MemoryDoc): `skill` "" the global memory, `at` the part first shown.
pub fn memory_doc_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame, address : String, skill : String, at : Int) -> Unit {
  let read = memory_of(core, address)
  let names = station_names(
    match @settings.stations_of(core, here).value {
      Some(Array(a)) => a
      _ => []
    },
  )
  let title = if skill == "" { @sf.t("web-main.memory.global") } else { skill }
  let m = read.value
  guard m is Some(_) else {
    // (read the first time: the page of a made-up memory, in its bones)
    let error = if read.error == "" { "" } else { @sf.t("web-main.memory.failed", args=[("error", read.error)]) }
    @sf.page_waiting(c, title, error~, fn() { doc_page(c, core.quiet(), frame, "sample", skill, at, Some(doc_sample(skill)), names) })
  }
  doc_page(c, core, frame, address, skill, at, m, names)
}

///|
/// A memory's page (`m`, as the core reads it): `skill` "" the global memory, `at` the part first shown; `names` the
/// stations' by their ids (who has a shared skill).
fn doc_page(
  c : @ui.Ctx,
  core : Core,
  frame : PageFrame,
  address : String,
  skill : String,
  at : Int,
  m : Json?,
  names : Map[String, String],
) -> Unit {
  let key = "memory-doc/" + address + "/" + skill
  let title = if skill == "" { @sf.t("web-main.memory.global") } else { skill }
  let kv = if skill == "" {
    None
  } else {
    match items(m, "skills").search_by(fn(x) { text(Some(x), "name") == skill }) {
      Some(i) => Some(items(m, "skills")[i])
      None => None
    }
  }
  if skill != "" && kv is None {
    @sf.page(c, on_back=core.pop, frame~, key, title, [fn() { c.text(@sf.t("web-main.memory.gone"), style=desk_muted) |> ignore }])
    return
  }
  // its pages: the global memory's parts, or the skill's (its SKILL.md, then each other file)
  let pages = if skill == "" {
    items(field(m, "global"), "sections").map(fn(p) { (text(Some(p), "title"), text(Some(p), "note"), text(Some(p), "text")) })
  } else {
    items(kv, "pages").map(fn(p) { (text(Some(p), "label"), text(Some(p), "size"), text(Some(p), "text")) })
  }
  let picked = doc_at.get(key).unwrap_or(at)
  let i = if pages.length() == 0 { 0 } else if picked >= pages.length() { pages.length() - 1 } else if picked < 0 { 0 } else { picked }
  // (its head, its pills and its text: the layers of one document, one block of the page, 16 under its head and 20
  // under its pills, the web's memoryHead's and memoryChips')
  let layers : Array[() -> Unit] = []
  if skill == "" {
    layers.push(fn() {
      c.box(style=md_under_head, fn() {
        c.text(join([@sf.t("web-main.memory.global.when"), text(field(m, "global"), "size")], " · "), style=md_when) |> ignore
      })
      |> ignore
    })
  } else {
    // what kind it is and when it is read; sharing it (not a station's own, nor another station's copy)
    layers.push(fn() {
      c.box(style=md_under_head, fn() {
        @sf.page_card(c, fn() {
          c.box(style=md_when_box, fn() {
            c.text(text(kv, "kindText") + " · " + @sf.t("web-main.memory.when"), style=md_when_head) |> ignore
            c.text(text(kv, "whenText"), style=md_when) |> ignore
          })
          |> ignore
          let share = field(kv, "share")
          if !flag(kv, "builtin") && text(share, "role") != "user" {
            let on_what = [("station", address), ("name", skill)]
            let busy = is_doing(core, ["skill.share"], on_what)
            let on = text(share, "role") == "host"
            let now = @sf.switch_row(c, key + "/share", @sf.t("web-main.memory.share.switch"), on, busy~, disabled=busy)
            if now != on {
              @settings.act(
                core,
                @sf.t("web-main.memory.share.switch"),
                "skill.share",
                obj([("station", str(address)), ("name", str(skill)), ("on", Json::boolean(now))]),
              )
            }
            // who has it, who may and does not and why, why it is not being shared now (the core's words)
            let name_of = fn(id : String) {
              match names.get(id) {
                Some(n) => n
                None => if id.length() > 8 { id.unsafe_substring(start=0, end=8) } else { id }
              }
            }
            let users = strings(share, "users").map(name_of)
            if on && users.length() > 0 {
              c.text(@sf.t("web-main.memory.share.users", args=[("stations", users.join(@sf.t("web-main.list.separator")))]), style=md_when)
              |> ignore
            }
            if on {
              for x in items(share, "missing") {
                c.text(
                  @sf.t("web-main.memory.share.missing", args=[("station", name_of(text(Some(x), "station"))), ("why", text(Some(x), "whyText"))]),
                  style=md_conflict,
                )
                |> ignore
              }
              let unread = text(share, "unreadText")
              if unread != "" {
                c.text(unread, style=md_conflict) |> ignore
              }
            }
            let conflicts = strings(share, "conflicts")
            if conflicts.length() > 0 {
              c.text(
                @sf.t("web-main.memory.share.conflicts", args=[("names", conflicts.join(@sf.t("web-main.list.separator")))]),
                style=md_conflict,
              )
              |> ignore
            }
          }
        })
        |> ignore
      })
      |> ignore
    })
  }
  // the pages to pick between: pills as wide as their words, the one in view in the ink; with the text under them,
  // one layer (its pills its tabs, 20 over it)
  let doc : Array[() -> Unit] = []
  if pages.length() > 1 {
    doc.push(fn() {
      c.box(style=md_chips, flow=true, fn() {
        for n, p in pages {
          let id = c.id(key + "/chip/" + n.to_string())
          if c.clicked(id) {
            doc_at[key] = n
          }
          let on = n == i
          let b = c.box(style=if on { md_chip_on } else if c.hovered(id) { md_chip_lit } else { md_chip }, id~, fn() {
            c.text(p.0, style=if on { md_chip_words_on } else { md_chip_words }) |> ignore
            if p.1 != "" {
              c.text(p.1, style=if on { md_chip_note_on } else { md_chip_note }) |> ignore
            }
          })
          c.semantics(b, Tab, id~, label=p.0, selected=on)
        }
      })
      |> ignore
    })
  }
  // its text: on a card on a narrow page (the narrow app's), on the page itself on a wide one (the web's)
  let look = look_of(c)
  doc.push(fn() {
    let words = if pages.length() == 0 { "" } else { pages[i].2 }
    let text = fn() {
      @sf.markdown(c, if words == "" { @sf.t("web-main.memory.empty") } else { words }, key=key + "/" + i.to_string(), size=@sf.text_scale.base.0)
      |> ignore
    }
    if look == Narrow {
      @sf.page_card(c, text)
    } else {
      text()
    }
  })
  layers.push(fn() {
    c.box(style=md_doc, fn() {
      for d in doc {
        d()
      }
    })
    |> ignore
  })
  @sf.page(c, on_back=core.pop, frame~, key, title, [
    fn() {
      @sf.layers(c, fn() {
        for l in layers {
          l()
        }
      })
    },
  ])
}

// ── styles (Memory.css.ts) ──────────────────────────────────────────────

///|
/// When it is read (memoryWhen: the muted; its head over it, the subtle, 2 apart).
// kept across runs: a value (no field of it changes)
let md_when_box : @ui.Style = @ui.css("w=Full gap=S0_5")

///|
// kept across runs: a value (no field of it changes)
let md_when_head : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Medium, color=Subtle, w=Full)

///|
// kept across runs: a value (no field of it changes)
let md_when : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let md_conflict : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=WarnInk, w=Full)

///|
/// The pages to pick between (memoryChips: 6 apart, wrapping; memoryChip: 30 high, 12 in, round, the card's ground, the
/// hover's under the pointer; the one in view the ink's, its words the page's ground).
// kept across runs: a value (no field of it changes)
let md_chips : @ui.Style = @ui.css("row w=Full pb=S5 gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let md_chip : @ui.Style = @ui.style(h=Fixed(md_chip_h)).then(@ui.css("row px=S3 gap=S1_5 align=ACenter radius=Full bg=Card"))

///|
let md_chip_h : Double = 30.0

///|
// kept across runs: a value (no field of it changes)
let md_chip_lit : @ui.Style = md_chip.then(@ui.css("bg=Hover"))

///|
// kept across runs: a value (no field of it changes)
let md_chip_on : @ui.Style = md_chip.then(@ui.css("bg=Fg"))

///|
// kept across runs: a value (no field of it changes)
let md_chip_words : @ui.TextStyle = @ui.text_style(size=Ui, leading=L5, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let md_chip_words_on : @ui.TextStyle = @ui.text_style(size=Ui, leading=L5, color=Bg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let md_chip_note : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let md_chip_note_on : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Subtle, wrap=false)

///|
/// What is under a document's head (its card, the global memory's when): 16 (memoryHead's, memoryWhen's).
// kept across runs: a value (no field of it changes)
let md_under_head : @ui.Style = @ui.css("w=Full mb=S4")

///|
/// Its text with its pills over it: one layer.
// kept across runs: a value (no field of it changes)
let md_doc : @ui.Style = @ui.css("w=Full")

///|
/// A memory made up, for what its page shows while it is read (doc_page in its bones): the global memory's parts, or
/// skill `skill`'s pages, each of a few paragraphs.
fn doc_sample(skill : String) -> Json {
  let words = [24, 40, 16, 32].map(@sf.sample_words).join("\n\n")
  let parts = Json::array(
    [4, 6, 5].map(fn(n) {
      Json::object({
        "title": Json::string(@sf.sample_words(n)),
        "label": Json::string(@sf.sample_words(n)),
        "note": Json::string(@sf.sample_words(3)),
        "size": Json::string(@sf.sample_words(3)),
        "text": Json::string(words),
      })
    }),
  )
  {
    "global": { "size": Json::string(@sf.sample_words(3)), "sections": parts },
    "skills": [{ "name": Json::string(skill), "kindText": Json::string(@sf.sample_words(4)), "whenText": Json::string(@sf.sample_words(16)), "pages": parts }],
  }
}
