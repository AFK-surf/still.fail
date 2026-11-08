// One of a station's memory pages (设置 › 记忆 › it; web/src/Memory.tsx MemoryDoc, Memory.css.ts; the narrow app's
// mobile/Memory.tsx MemoryDocScreen), one page in every frame: the global memory a part at a time, or a skill (what
// kind it is and when it is read, sharing it with the workspace's other stations, its pages to pick between), its
// text as people read it, on a card where the page is narrow (the narrow app's), on the page where it is wide (the
// web's). Its pages' pills go on in lines where the room ends: every one there to pick, none behind a ⋯ nor scrolled
// out (the phone's copy, gone, left the last out). What it says is the core's (looks.ts).

///|
/// The page in view of each memory page, by its station and skill ("" the global memory): picked by its chips.
// kept across runs: said by its chips; memory_doc_reset (sfpages' reset) empties it
let doc_at : @sf.LiveMap[String, Int] = @sf.LiveMap::new()

///|
fn memory_doc_reset() -> Unit {
  doc_at.clear()
}

///|
/// The page (MemoryDoc) made once as nodes in node `v`, laid out by the `width` its frame gives it: `skill` "" the
/// global memory, `at` the part first shown; while the memory is read the first time, the page of a made-up one in its
/// bones; all of it as the core says it now.
pub fn memory_doc_node(
  v : @view.View,
  core : Core,
  here : () -> Here,
  address : String,
  skill : String,
  at : Int,
  on_back~ : () -> Unit,
  frame~ : () -> PageFrame,
  said? : (@sf.PageSaid) -> Unit,
  width? : () -> Double,
) -> Unit {
  let read = fn() { memory_of(core, address) }
  let names = fn() {
    station_names(
      match @settings.stations_of(core, here()).value {
        Some(Array(a)) => a
        _ => []
      },
    )
  }
  let title = if skill == "" { @sf.t("web-main.memory.global") } else { skill }
  @sf.page_node(v, fn() { title }, on_back~, frame~, said?, width?, fn() { ["doc"] }, fn(b, _) {
    b.pick(fn() { read().value is None }, fn(p, reading) {
      if reading {
        @sf.waiting_node(
          p,
          fn(s) { doc_body_node(s, core.quiet(), "sample", skill, at, fn() { Some(doc_sample(skill)) }, names) },
          error=fn() {
            let e = read().error
            if e == "" {
              ""
            } else {
              @sf.t("web-main.memory.failed", args=[("error", e)])
            }
          },
        )
      } else {
        doc_body_node(p, core, address, skill, at, fn() { read().value }, names)
      }
    })
  })
}

///|
/// A memory's page's body (`m`, as the core reads it, as it changes) in node `v`: `skill` "" the global memory, `at` the
/// part first shown; `names` the stations' by their ids (who has a shared skill). Its head, its pills and its text: the
/// layers of one document, one block of the page, 16 under its head and 20 under its pills (the web's memoryHead's and
/// memoryChips'); a skill no longer there, said so.
fn doc_body_node(
  v : @view.View,
  core : Core,
  address : String,
  skill : String,
  at : Int,
  m : () -> Json?,
  names : () -> Map[String, String],
) -> Unit {
  let key = "memory-doc/" + address + "/" + skill
  let kv = fn() -> Json? {
    if skill == "" {
      None
    } else {
      let all = items(m(), "skills")
      match all.search_by(fn(x) { text(Some(x), "name") == skill }) {
        Some(i) => Some(all[i])
        None => None
      }
    }
  }
  v.pick(fn() { skill != "" && kv() is None }, fn(p, gone) {
    if gone {
      @sf.words_node(p, fn() { @sf.t("web-main.memory.gone") }, fn() { desk_muted }) |> ignore
      return
    }
    // its pages: the global memory's parts, or the skill's (its SKILL.md, then each other file)
    let pages = fn() {
      if skill == "" {
        items(field(m(), "global"), "sections").map(fn(x) { (text(Some(x), "title"), text(Some(x), "note"), text(Some(x), "text")) })
      } else {
        items(kv(), "pages").map(fn(x) { (text(Some(x), "label"), text(Some(x), "size"), text(Some(x), "text")) })
      }
    }
    let shown_at = fn() {
      let n = pages().length()
      let picked = doc_at.get(key).unwrap_or(at)
      if n == 0 { 0 } else if picked >= n { n - 1 } else if picked < 0 { 0 } else { picked }
    }
    // (its text on a card on a narrow page (the narrow app's), on the page itself on a wide one (the web's))
    let narrow = @sf.look_node(p) is Narrow
    p.box(fn(l) {
      @sf.style_node(l, fn() { md_doc })
      l.box(fn(h) {
        @sf.style_node(h, fn() { md_under_head })
        if skill == "" {
          @sf.words_node(h, fn() { join([@sf.t("web-main.memory.global.when"), text(field(m(), "global"), "size")], " · ") }, fn() {
            md_when
          })
          |> ignore
        } else {
          // what kind it is and when it is read; sharing it (not a station's own, nor another station's copy): a card,
          // alone where it is one of the layers (narrow), as the page's cards are where it is wide
          @sf.page_card_node(h, layered=narrow, fn(k) { doc_skill_card_node(k, core, address, skill, kv, names) })
        }
      })
      |> ignore
      l.box(fn(d) {
        @sf.style_node(d, fn() { md_doc })
        // the pages to pick between: pills as wide as their words, going on in lines, the one in view in the ink
        d.show(fn() { pages().length() > 1 }, fn(chips) {
          @sf.style_node(chips, fn() { md_chips })
          chips.wraps(Is(Some(md_chips_gap))) |> ignore
          chips.each(fn() { pages().mapi(fn(n, x) { (n, x.0, x.1) }) }, fn(x) { x.0 }, fn(chip, x) {
            let n = @signals.untracked(fn() { x.get().0 })
            let on = fn() { shown_at() == n }
            @sf.style_node(chip, fn() {
              if on() {
                md_chip_on
              } else if @sf.lit_node(chip) {
                md_chip_lit
              } else {
                md_chip
              }
            }, in_row=true)
            @sf.presses_node(chip, fn() { doc_at[key] = n })
            chip.says(By(fn() { Some(@view.said(Tab, label=x.get().1, selected=on())) })) |> ignore
            @sf.words_node(chip, fn() { x.get().1 }, fn() { if on() { md_chip_words_on } else { md_chip_words } }) |> ignore
            chip.show(fn() { x.get().2 != "" }, fn(o) {
              @sf.words_node(o, fn() { x.get().2 }, fn() { if on() { md_chip_note_on } else { md_chip_note } }) |> ignore
            })
          })
        })
        // its text: on a card on a narrow page (the narrow app's), on the page itself on a wide one (the web's)
        let words = fn() {
          let all = pages()
          let w = if all.length() == 0 { "" } else { all[shown_at()].2 }
          if w == "" {
            @sf.t("web-main.memory.empty")
          } else {
            w
          }
        }
        let text_in = fn(t : @view.View) {
          @sf.markdown_node(t, words, size=fn() { @sf.text_scale.base.0 }) |> ignore
        }
        if narrow {
          @sf.page_card_node(d, layered=true, text_in)
        } else {
          text_in(d)
        }
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// A skill's card (memory_doc's head): what kind it is and when it is read; sharing it where it can be (not a
/// station's own, nor another station's copy), who has it, who may and does not and why, why it is not being shared now
/// (the core's words); each as `kv` says it now.
fn doc_skill_card_node(
  k : @view.View,
  core : Core,
  address : String,
  skill : String,
  kv : () -> Json?,
  names : () -> Map[String, String],
) -> Unit {
  k.box(fn(w) {
    @sf.style_node(w, fn() { md_when_box })
    @sf.words_node(w, fn() { text(kv(), "kindText") + " · " + @sf.t("web-main.memory.when") }, fn() { md_when_head }) |> ignore
    @sf.words_node(w, fn() { text(kv(), "whenText") }, fn() { md_when }) |> ignore
  })
  |> ignore
  let share = fn() { field(kv(), "share") }
  let on = fn() { text(share(), "role") == "host" }
  let name_of = fn(id : String) {
    match names().get(id) {
      Some(n) => n
      None => if id.length() > 8 { id.unsafe_substring(start=0, end=8) } else { id }
    }
  }
  k.show(fn() { !flag(kv(), "builtin") && text(share(), "role") != "user" }, fn(s) {
    // (its lines as far apart as the card's: they were the card's own)
    s.gap(Is(md_card_gap)) |> ignore
    let on_what = [("station", address), ("name", skill)]
    let busy = fn() { is_doing(core, ["skill.share"], on_what) }
    @sf.switch_row_node(
      s,
      fn() { @sf.t("web-main.memory.share.switch") },
      on,
      fn(now) {
        if now != @signals.untracked(on) {
          @settings.act(
            core,
            @sf.t("web-main.memory.share.switch"),
            "skill.share",
            obj([("station", str(address)), ("name", str(skill)), ("on", Json::boolean(now))]),
          )
        }
      },
      disabled=busy,
      in_words=true,
    )
    let users = fn() { strings(share(), "users").map(name_of) }
    s.show(fn() { on() && users().length() > 0 }, fn(u) {
      @sf.words_node(u, fn() { @sf.t("web-main.memory.share.users", args=[("stations", users().join(@sf.t("web-main.list.separator")))]) }, fn() {
        md_when
      })
      |> ignore
    })
    s.show(fn() { on() }, fn(o) {
      o.gap(Is(md_card_gap)) |> ignore
      o.each(fn() { items(share(), "missing") }, fn(x) { text(Some(x), "station") }, fn(r, x) {
        @sf.words_node(r, fn() {
          @sf.t("web-main.memory.share.missing", args=[("station", name_of(text(Some(x.get()), "station"))), ("why", text(Some(x.get()), "whyText"))])
        }, fn() { md_conflict })
        |> ignore
      })
      o.show(fn() { text(share(), "unreadText") != "" }, fn(n) {
        @sf.words_node(n, fn() { text(share(), "unreadText") }, fn() { md_conflict }) |> ignore
      })
    })
    s.show(fn() { strings(share(), "conflicts").length() > 0 }, fn(c) {
      @sf.words_node(c, fn() {
        @sf.t("web-main.memory.share.conflicts", args=[("names", strings(share(), "conflicts").join(@sf.t("web-main.list.separator")))])
      }, fn() { md_conflict })
      |> ignore
    })
  })
}

// ── styles ──────────────────────────────────────────────

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
/// The room between what a skill's card says (a page's card's, page_card_node's).
let md_card_gap : Double = 14.0

///|
/// The room between the pills' lines where they go on in another (md_chips' gap, as an old view's flow keeps it).
let md_chips_gap : Double = 6.0

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
