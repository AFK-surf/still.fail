// 记忆, one page in every frame (web/src/Memory.tsx MemoryView, cloud/settings.tsx MemorySettings; the narrow app's
// mobile/Memory.tsx MemoriesScreen, MemoryScreen), laid out by its width (page_look.mbt): narrow, a row for each
// station opening its memory; wide, every station's memory on the one page, its name over it where there are several.
// A station's memory: the global memory by its parts, the projects', the other skills (the station's own folded in a
// row), each row opening its page; which part a skill is under is the core's (`group`).

///|
/// 记忆 (MemorySettings, MemoriesScreen): each station's memory (wide), or a row to it (narrow); one offline says so.
fn memories_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame) -> Unit {
  let look = look_of(c)
  let topic = @settings.stations_of(core, here)
  let stations = match topic.value {
    Some(Array(a)) => a
    _ => []
  }
  let names = station_names(stations)
  let body : Array[() -> Unit] = []
  match look {
    Narrow =>
      body.push(fn() {
        if topic.value is None {
          @settings.waiting_cards(
            c,
            error=match topic.error {
              Some(e) => error_text(e)
              None => ""
            },
          )
          return
        }
        @sf.group(c, fn() {
          for s in stations {
            let sv = Some(s)
            if flag(sv, "online") {
              if @sf.link_row(c, "memory/" + text(sv, "station"), text(sv, "name"), value=@sf.t("android-misc.memory.row")) {
                (core.push)(Memory(text(sv, "station")))
              }
            } else {
              @sf.said_row(c, text(sv, "name"), @sf.t("web-pages.settings.memory.offline"))
            }
          }
        })
      })
    Wide => {
      for i, s in stations {
        let sv = Some(s)
        body.push(fn() {
          c.box(style=if i == 0 { mem_station_first } else { mem_station }, fn() {
            if stations.length() > 1 {
              c.box(style=mem_station_head, fn() { c.text(text(sv, "name"), style=mem_station_name) |> ignore }) |> ignore
            }
            if flag(sv, "online") {
              memory_view(c, core, look, text(sv, "station"), names)
            } else {
              c.text(@sf.t("web-pages.settings.memory.offline"), style=desk_muted) |> ignore
            }
          })
          |> ignore
        })
      }
      if topic.value is None {
        body.push(fn() { @sf.wait_line(c, @sf.t("common.readingStations")) })
      }
    }
  }
  look_page(c, core, frame, "memories",
    @sf.t("web-pages.settings.memory.title"),
    body,
    about=@sf.t("web-pages.settings.memory.lead"),
    lead=if look == Narrow { @sf.t("android-misc.memory.note") } else { "" },
  )
}

///|
/// One station's memory, on a page of its own (MemoryScreen; wide, a link to it): as 记忆 shows it, under its name.
fn memory_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame, address : String) -> Unit {
  let look = look_of(c)
  let stations = match @settings.stations_of(core, here).value {
    Some(Array(a)) => a
    _ => []
  }
  let mut name = @settings.station_name(address)
  for s in stations {
    if text(Some(s), "station") == address {
      name = text(Some(s), "name")
    }
  }
  look_page(c, core, frame, "memory/" + address, name, about=@sf.t("web-pages.settings.memory.lead"), [
    fn() { memory_view(c, core, look, address, station_names(stations)) },
  ])
}

///|
/// The stations' names by their ids (whose a shared skill is).
fn station_names(stations : Array[Json]) -> Map[String, String] {
  let names : Map[String, String] = {}
  for s in stations {
    names[text(Some(s), "id")] = text(Some(s), "name")
  }
  names
}

///|
/// A station's memory as a list (MemoryView): its sections, each a row that opens its page; a wait while it is read.
fn memory_view(c : @ui.Ctx, core : Core, look : Look, address : String, names : Map[String, String]) -> Unit {
  let read = memory_of(c, core, address)
  guard read.value is Some(_) else {
    match look {
      Narrow => @settings.waiting_cards(c, error=if read.error == "" { "" } else { @sf.t("web-main.memory.failed", args=[("error", read.error)]) })
      Wide =>
        if read.error == "" {
          @sf.wait_line(c, @sf.t("common.reading"))
        } else {
          c.text(@sf.t("web-main.memory.failed", args=[("error", read.error)]), style=desk_note_bad) |> ignore
        }
    }
  }
  let m = read.value
  let sections = sections_of(m)
  let skills = items(m, "skills")
  let part = fn(group : String) { skills.filter(fn(k) { text(Some(k), "group") == group }) }
  let projects = part("project")
  let others = part("skill")
  let builtin = part("builtin")
  let open = builtin_open.get(address).unwrap_or(false)
  let skill_row = fn(k : Json) {
    let kv = Some(k)
    // (the core's: when it is read, in a line)
    if memory_row(c, look, "memory/" + address + "/skill/" + text(kv, "name"), text(kv, "name"), text(kv, "line"), text(kv, "size"), tag=skill_tag(kv, names)) {
      (core.push)(MemoryDoc(address, text(kv, "name"), 0))
    }
  }
  let none = fn(words : String) {
    match look {
      Narrow => c.box(style=mem_narrow_none, fn() { c.text(words, style=mem_narrow_none_words) |> ignore }) |> ignore
      Wide => c.text(words, style=desk_muted) |> ignore
    }
  }
  let global_said = join([@sf.t("web-main.memory.global.when"), text(field(m, "global"), "size")], " · ")
  @sf.section(c, @sf.t("web-main.memory.global"), heads=true, note=global_said, fn() {
    if sections.length() == 0 {
      none(@sf.t("web-main.memory.empty"))
    } else {
      @sf.group(c, fn() {
        for i, p in sections {
          if memory_row(c, look, "memory/" + address + "/part/" + i.to_string(), p.0, "", p.2) {
            (core.push)(MemoryDoc(address, "", i))
          }
        }
      })
    }
  })
  @sf.section(c, @sf.t("web-main.memory.projects"), heads=true, note=@sf.t("web-main.memory.projects.when"), fn() {
    if projects.length() == 0 {
      none(@sf.t("web-main.memory.projects.none"))
    } else {
      @sf.group(c, fn() {
        for k in projects {
          skill_row(k)
        }
      })
    }
  })
  if others.length() + builtin.length() > 0 {
    @sf.section(c, @sf.t("web-main.memory.others"), heads=true, fn() {
      @sf.group(c, fn() {
        for k in others {
          skill_row(k)
        }
        if builtin.length() > 0 {
          if memory_row(
              c,
              look,
              "memory/" + address + "/builtin",
              @sf.t("web-main.memory.builtin"),
              if open {
                ""
              } else {
                join(builtin.map(fn(k) { text(Some(k), "name") }), @sf.t("web-main.list.separator"))
              },
              @sf.t("web-main.memory.count", args=[("n", builtin.length().to_string())]),
              open~,
            ) {
            builtin_open[address] = !open
          }
          if open {
            for k in builtin {
              skill_row(k)
            }
          }
        }
      })
    })
  }
}

///|
/// A row that opens a page, or folds a group open (MemoryRow): its name and whose, a line under it (cut short), how
/// much is in it, a chevron 14 in the subtle grey. True on the frame it is pressed.
fn memory_row(
  c : @ui.Ctx,
  look : Look,
  key : String,
  title : String,
  sub : String,
  value : String,
  tag? : String = "",
  open? : Bool = false,
) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  c.cursor(id, Hand)
  let narrow = look == Narrow
  let b = c.box(style=if narrow { narrow_row } else { desk_list_link }, id~, fn() {
    c.box(style=desk_list_text, fn() {
      c.box(style=mem_title_line, fn() {
        c.text(title, style=if narrow { mem_narrow_title } else { desk_list_title }) |> ignore
        if tag != "" {
          c.text(tag, style=mem_tag) |> ignore
        }
      })
      |> ignore
      if sub != "" {
        c.text(sub, style=if narrow { mem_narrow_sub } else { mem_sub }) |> ignore
      }
    })
    |> ignore
    if value != "" {
      c.text(value, style=if narrow { narrow_value } else { mem_tag_muted }) |> ignore
    }
    @sf.icon(c, if open { "chevron-down" } else { "chevron-right" }, size=memory_chevron, color=t.p.subtle) |> ignore
    if narrow {
      finger_ripple(c, id)
    }
  })
  c.semantics(b, Link, id~, label=title, expanded?=if key.has_suffix("/builtin") { Some(open) } else { None })
  c.clicked(id)
}

///|
/// What a narrow page's section says where it has nothing (mMemoryNote: 24 in, 8 under).
// kept across runs: a value (no field of it changes)
let mem_narrow_none : @ui.Style = @ui.css("w=Full px=S6 pb=S2")

///|
// kept across runs: a value (no field of it changes)
let mem_narrow_none_words : @ui.TextStyle = @ui.text_style(size=Sm, leading=L5, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let mem_narrow_title : @ui.TextStyle = @sf.body.then(@sf.one_line)

///|
// kept across runs: a value (no field of it changes)
let mem_narrow_sub : @ui.TextStyle = @sf.secondary.then(@sf.one_line).then(@sf.full_words)

///|
/// (memoryStation + memoryStation: 36 between two stations)
// kept across runs: a value (no field of it changes)
let mem_station_first : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let mem_station : @ui.Style = @ui.css("w=Full pt=S9")

///|
/// (memoryStationName: the title's size, 600, 8 over what follows)
// kept across runs: a value (no field of it changes)
let mem_station_head : @ui.Style = @ui.css("w=Full pb=S2")

///|
// kept across runs: a value (no field of it changes)
let mem_station_name : @ui.TextStyle = @ui.text_style(size=Xl, leading=L7, weight=Semibold, color=Fg, wrap=false)

///|
/// (memoryRowTitle: its name and its tags in a line, 8 apart)
// kept across runs: a value (no field of it changes)
let mem_title_line : @ui.Style = @ui.css("row gap=S2 align=AEnd")

///|
/// (memoryTag: the meta's size, subtle)
// kept across runs: a value (no field of it changes)
let mem_tag : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Subtle, wrap=false)

///|
/// (memoryRowValue: the meta's size, muted)
// kept across runs: a value (no field of it changes)
let mem_tag_muted : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Muted, wrap=false)

///|
/// (memoryRowSub: the meta's size, muted, on one line cut short)
// kept across runs: a value (no field of it changes)
let mem_sub : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Muted, wrap=false, w=Full)
