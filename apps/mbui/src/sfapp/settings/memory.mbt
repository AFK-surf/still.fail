// The agents' memory on a station (settings/Memory.kt; `memory.get` on the station, read as its page opens): the global
// memory by its parts, each project's memory (a skill whose description says when it applies), the station's other
// skills (the built-in ones folded), each opening a page of its own to read, Markdown; the memory of every station a
// row each from settings (MemoriesScreen). A skill of the station's own is shared with the workspace's other stations,
// or no longer, from its page (ShareRow: `skill.share`).

///|
/// The last memory read of each station (Memory.kt kept), so a page opened from the list has it at once; whether it
/// was asked for since its page came; why it could not be read.
pub(all) struct MemoryRead {
  mut value : Json?
  mut error : String
  mut asked : Bool
}

///|
let memories : Map[String, MemoryRead] = Map::new()

///|
/// A station's memory, asked for once each time one of its pages comes (it changes as agents write it, not while it is
/// looked at).
pub fn memory_of(c : @ui.Ctx, core : Core, address : String) -> MemoryRead {
  let m = match memories.get(address) {
    Some(m) => m
    None => {
      let m = { value: None, error: "", asked: false }
      memories[address] = m
      m
    }
  }
  // (asked once the frame's builds are over, once: each build asks while it is not)
  if !m.asked {
    c.after_build("memory/" + address, fn() {
      if m.asked {
        return
      }
      m.asked = true
      (core.call)("memory.get", obj([("station", str(address))]), fn(r) {
      match r {
        Ok(v) => {
          m.value = Some(v)
          m.error = ""
        }
        Err(e) => m.error = error_text(e)
      }
    })
    })
  }
  m
}

///|
/// The global memory's parts (Memory.kt sectionsOf): by its headings, as the core reads them.
pub fn sections_of(m : Json?) -> Array[(String, String, String)] {
  items(field(m, "global"), "sections").map(fn(x) { (text(Some(x), "title"), text(Some(x), "text"), text(Some(x), "note")) })
}

///|
/// Whose a skill is, after its name (Memory.kt tagOf): another station's, or shared from here.
pub fn skill_tag(k : Json?, names : Map[String, String]) -> String {
  let share = field(k, "share")
  match text(share, "role") {
    "user" => {
      let host = text(share, "host")
      fill("web-main.memory.share.from", [
        (
          "station",
          match names.get(host) {
            Some(n) => n
            None => if host.length() > 8 { host.unsafe_substring(start=0, end=8) } else { host }
          },
        ),
      ])
    }
    "host" => tr("web-main.memory.share.shared")
    _ => ""
  }
}

///|
pub let memory_chevron : Double = 14.0

///|
/// Whether the built-in skills are folded open, by station.
pub let builtin_open : Map[String, Bool] = Map::new()

///|
/// Which page of a memory document is shown, by its station and skill.
let doc_picked : Map[String, Int] = Map::new()

///|
/// One of a station's memory pages (MemoryDocScreen): a skill with when it is read, whether it is shared, its other
/// files (`skill`), or the global memory a part at a time (from `at`); the parts as pills across the top.
fn memory_doc_page(c : @ui.Ctx, core : Core, address : String, skill : String, at : Int) -> Unit {
  let t = @sf.theme()
  let read = memory_of(c, core, address)
  let m = read.value
  let k = if skill == "" {
    None
  } else {
    items(m, "skills").iter().find_first(fn(x) { text(Some(x), "name") == skill })
  }
  let kv = match k {
    Some(x) => Some(x)
    None => None
  }
  let sub = if skill == "" {
    tr("web-main.memory.global.when")
  } else {
    // (the core's: 项目记忆, station 内置, Skill)
    text(kv, "kindText")
  }
  let key = address + "\u{1}" + skill
  let picked = doc_picked.get(key).unwrap_or(at)
  c.box(w=Fill(1.0), h=Fill(1.0), fn() {
    let title = if skill == "" { tr("android-misc.memory.global") } else { skill }
    if sub != "" {
      nav_bar(c, core, tr("android-misc.memory.title"), title, sub=fn() {
        c.text(sub, size=11.0, color=t.p.muted, wrap=false, line=16.0) |> ignore
      })
    } else {
      nav_bar(c, core, tr("android-misc.memory.title"), title)
    }
    if m is None {
      waiting_cards(
        c,
        error=if read.error == "" { "" } else { fill("android-misc.memory.loadFailed", [("error", read.error)]) },
      )
      return
    }
    if skill != "" && kv is None {
      c.box(w=Fill(1.0), pad=24.0, fn() {
        c.text(tr("web-main.memory.gone"), size=14.0, color=t.p.muted, w=Fill(1.0), line=20.0) |> ignore
      })
      |> ignore
      return
    }
    let pages : Array[(String, String, String)] = if kv is None {
      sections_of(m).map(fn(p) { (p.0, p.2, p.1) })
    } else {
      // its SKILL.md (总览), then each other file (the core's)
      items(kv, "pages").map(fn(p) { (text(Some(p), "label"), text(Some(p), "size"), text(Some(p), "text")) })
    }
    let i = if pages.length() == 0 { 0 } else if picked >= pages.length() { pages.length() - 1 } else if picked < 0 { 0 } else { picked }
    let blocks : Array[() -> Unit] = [fn() { gap(c, 4.0) }]
    if kv is Some(_) {
      blocks.push(fn() {
        // its rows in its corners: 8 in, their words 12 more (the card's 20)
        c.box(style=card_room, fn() {
          c.box(style=skill_card, fn() {
            c.box(style=skill_card_words, fn() {
              c.text(tr("web-main.memory.when"), size=12.0, weight=500, color=t.p.subtle, wrap=false, line=17.0) |> ignore
              c.box(w=Fill(1.0), pt=2.0, fn() {
                c.text(
                  text(kv, "whenText"),
                  size=13.0,
                  color=t.p.muted,
                  w=Fill(1.0),
                  line=18.0,
                )
                |> ignore
              })
              |> ignore
            })
            |> ignore
            if !flag(kv, "builtin") && text(field(kv, "share"), "role") != "user" {
              skill_share_row(c, core, address, kv, read)
            }
          })
          |> ignore
        })
        |> ignore
      })
    }
    if pages.length() > 1 {
      blocks.push(fn() {
        let got = doc_chips(c, key, pages, i)
        if got != i {
          doc_picked[key] = got
        }
      })
    }
    blocks.push(fn() {
      card(c, fn() {
        let words = if pages.length() == 0 { "" } else { pages[i].2 }
        @sf.markdown(c, if words == "" { tr("android-misc.memory.empty") } else { words }, size=14.0) |> ignore
      })
      |> ignore
    })
    blocks.push(fn() { gap(c, 30.0) })
    scroll_page(c, "memory-doc/" + key, blocks)
  })
  |> ignore
}

///|
/// Pages to pick between as a row of pills (Memory.kt DocChips): each with how much is in it; the one shown in ink.
/// Answers the one picked.
fn doc_chips(c : @ui.Ctx, key : String, pages : Array[(String, String, String)], picked : Int) -> Int {
  let t = @sf.theme()
  let mut got = picked
  // scrolled across when they do not fit (Memory.kt DocChips: horizontalScroll)
  c.box(style=doc_chips_room, fn() {
    c.sideways(key + "/chips", padx=12.0, fn() {
      c.box(dir=Row, gap=6.0, fn() {
        for i, p in pages {
          let on = i == picked
          let id = c.id(key + "/chip/" + i.to_string())
          if hit(c, id) {
            got = i
          }
          c.box(dir=Row, padx=14.0, pady=7.0, radius=16.0, bg=if on { t.p.text } else { t.p.chip }, id~, fn() {
            c.text(p.0, size=13.0, weight=if on { 600 } else { 400 }, color=if on { t.p.bg } else { t.p.text }, wrap=false)
            |> ignore
            if p.1 != "" {
              c.text("  " + p.1, size=13.0, color=@sf.alpha(if on { t.p.bg } else { t.p.text }, 0.6), wrap=false) |> ignore
            }
          })
          |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
  got
}

///|
/// The pills' room: 10 over what is under them; 12 in from the page's sides as they scroll (Memory.kt:243).
// kept across runs: a value (no field of it changes)
let doc_chips_room : @ui.Style = @ui.css("w=Full pb=S2_5")

///|
/// The card a skill's when and sharing are on: a card (20 down, 22 round) whose rows reach 8 from its sides, as
/// MemoryDocScreen's ShareRow bleeds out of it (CARD_PAD less LIST_PAD).
// kept across runs: a value (no field of it changes)
let skill_card : @ui.Style = card_ground.then(@ui.css("px=S2"))

///|
/// Its words 12 further in: 20 from its sides, as a card's.
// kept across runs: a value (no field of it changes)
let skill_card_words : @ui.Style = @ui.css("w=Full px=S3")

///|
/// The sharing row, 12 under the words: its ground under the finger rounded as the card's less its room
/// (LIST_ROW_CORNER), its words 12 in, 6 over and under.
// kept across runs: a value (no field of it changes)
let skill_share_room : @ui.Style = @ui.css("w=Full pt=S3")

///|
// kept across runs: a value (no field of it changes)
let skill_share_line : @ui.Style = @ui.css("row w=Full pl=S3 py=S1_5 gap=S2_5 radius=Inner align=ACenter").then(
  @ui.style(pr=@sf.capsule_end_room(share_line_h, share_switch_h)),
)

///|
/// The line's height (the switch's 26 and 6 over and under: a capsule, as round as its ends), its switch at its end as
/// far in as makes it concentric with that end.
let share_line_h : Double = 38.0

///|
let share_switch_h : Double = 26.0

///|
/// Its words (14, the ink, as wide as the row lets them).
// kept across runs: a value (no field of it changes)
let skill_share_words : @ui.TextStyle = @ui.text_style(size=Base, color=Fg, w=Full)

///|
/// The edits two stations made at once (12, the warning's ink), 6 under it, 12 in.
// kept across runs: a value (no field of it changes)
let skill_conflicts_room : @ui.Style = @ui.css("w=Full px=S3 pt=S1_5")

///|
// kept across runs: a value (no field of it changes)
let skill_conflicts_words : @ui.TextStyle = @ui.text_style(size=Xs, w=Full)

///|
/// Whether a skill of this station's is shared with the workspace's other stations (MemoryDocScreen's ShareRow): a tap
/// switches it (`skill.share`), its memory read again once it has; and the edits two made at once.
fn skill_share_row(c : @ui.Ctx, core : Core, address : String, kv : Json?, read : MemoryRead) -> Unit {
  let t = @sf.theme()
  let name = text(kv, "name")
  let on_what = [("station", address), ("name", name)]
  let busy = is_doing(core, ["skill.share"], on_what)
  let on = text(field(kv, "share"), "role") == "host"
  c.box(style=skill_share_room, fn() {
    // (no tap while it is being switched)
    let id = if busy { 0 } else { c.id("skill-share/" + name) }
    c.box(style=skill_share_line, id~, fn() {
      c.text(tr("web-main.memory.share.switch"), style=skill_share_words) |> ignore
      doing_mark(c, busy, failed_of(core, ["skill.share"], on_what))
      switch(c, "skill-share/" + name, on)
      // Memory.kt: clip(Smooth(LIST_ROW_CORNER)).clickable (not while busy)
      if id != 0 {
        @motion.ripple(c, id, @sf.row_corner)
      }
    })
    |> ignore
    if id != 0 && hit(c, id) {
      act(
        core,
        tr("web-main.memory.share.switch"),
        "skill.share",
        obj([("station", str(address)), ("name", str(name)), ("on", Json::boolean(!on))]),
        then=fn(_) { read.asked = false },
      )
    }
  })
  |> ignore
  let conflicts = items(field(kv, "share"), "conflicts").map(fn(x) {
    match x {
      String(n) => n
      _ => ""
    }
  })
  if conflicts.length() > 0 {
    c.box(style=skill_conflicts_room, fn() {
      c.text(
        fill("web-main.memory.share.conflicts", [("names", join(conflicts, tr("web-main.list.separator")))]),
        style=skill_conflicts_words,
        color=t.p.warn_ink,
      )
      |> ignore
    })
    |> ignore
  }
}
