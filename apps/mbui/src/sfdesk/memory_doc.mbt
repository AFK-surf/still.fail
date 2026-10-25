// One of a station's memory pages on the desktop (设置 › 记忆 › it; ember web/src/Memory.tsx MemoryDoc, Memory.css.ts):
// the global memory a part at a time, or a skill (what kind it is and when it is read, sharing it with the workspace's
// other stations, its pages to pick between), its text as people read it. What it says is the core's (looks.ts).

///|
/// The page in view of each memory page, by its station and skill ("" the global memory): picked by its chips.
// kept across runs: said by its chips; memory_doc_reset empties it
let doc_at : Map[String, Int] = {}

///|
fn memory_doc_reset() -> Unit {
  doc_at.clear()
}

///|
/// The page (MemoryDoc): `skill` "" the global memory, `at` the part first shown.
fn memory_doc_page(c : @ui.Ctx, core : Core, address : String, skill : String, at : Int) -> Unit {
  let read = memory_of(core, address)
  let key = "memory-doc/" + address + "/" + skill
  let title = if skill == "" { @sf.t("web-main.memory.global") } else { skill }
  let back = @sf.t("web-pages.settings.nav.memory")
  let m = read.value
  guard m is Some(_) else {
    desk_page(c, core, key, title, back~, [
      fn() {
        @sf.waiting(c, count=4, error=if read.error == "" { "" } else { @sf.t("web-main.memory.failed", args=[("error", read.error)]) })
      },
    ])
  }
  let kv = if skill == "" {
    None
  } else {
    match items(m, "skills").search_by(fn(x) { text(Some(x), "name") == skill }) {
      Some(i) => Some(items(m, "skills")[i])
      None => None
    }
  }
  if skill != "" && kv is None {
    desk_page(c, core, key, title, back~, [fn() { c.text(@sf.t("web-main.memory.gone"), style=desk_muted) |> ignore }])
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
  let blocks : Array[() -> Unit] = []
  if skill == "" {
    blocks.push(fn() {
      c.text(join([@sf.t("web-main.memory.global.when"), text(field(m, "global"), "size")], " · "), style=md_when) |> ignore
    })
  } else {
    // what kind it is and when it is read; sharing it (not a station's own, nor another station's copy)
    blocks.push(fn() {
      c.box(style=md_head, fn() {
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
  }
  // the pages to pick between: pills as wide as their words, the one in view in the ink
  if pages.length() > 1 {
    blocks.push(fn() {
      c.box(style=md_chips, flow=true, fn() {
        for n, p in pages {
          let id = c.id(key + "/chip/" + n.to_string())
          c.cursor(id, Hand)
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
  blocks.push(fn() {
    let words = if pages.length() == 0 { "" } else { pages[i].2 }
    @sf.markdown(c, if words == "" { @sf.t("web-main.memory.empty") } else { words }, key=key + "/" + i.to_string(), size=@sf.text_scale.base.0)
    |> ignore
  })
  desk_page(c, core, key, title, back~, blocks)
}

// ── styles (Memory.css.ts) ──────────────────────────────────────────────

///|
/// A skill's card (memoryHead: a card, 16 over what follows).
// kept across runs: a value (no field of it changes)
let md_head : @ui.Style = desk_card.then(@ui.css("mb=S4"))

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
