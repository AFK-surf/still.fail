// 记忆, one page in every frame (web/src/Memory.tsx MemoryView, cloud/settings.tsx MemorySettings; the narrow app's
// mobile/Memory.tsx MemoriesScreen, MemoryScreen), the same on every width (the user, 2026-10-26: 「设置感觉很乱」; wide
// had every station's memory on the one page, a third level of headings): a row for each station opening its memory,
// one offline saying so. A station's memory: the global memory by its parts, the projects', the other skills (the
// station's own folded in a row), each row opening its page; which part a skill is under is the core's (`group`).

///|
/// 记忆 (MemorySettings, MemoriesScreen): a row to each station's memory; one offline says so.
pub fn memories_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame) -> Unit {
  let topic = @settings.stations_of(core, here)
  let stations = match topic.value {
    Some(Array(a)) => a
    _ => []
  }
  let body : Array[() -> Unit] = [
    fn() {
      if topic.value is None {
        block_waiting(
          c,
          fn() { memories_list(c, core.quiet(), sample_stations()) },
          error=match topic.error {
            Some(e) => error_text(e)
            None => ""
          },
        )
        return
      }
      memories_list(c, core, stations)
    },
  ]
  @sf.page(c, on_back=core.pop, frame~, "memories", @sf.t("web-pages.settings.memory.title"), body, lead=@sf.t("android-misc.memory.note"))
}

///|
/// One station's memory, on a page of its own (MemoryScreen; wide, a link to it): as 记忆 shows it, under its name.
pub fn memory_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame, address : String) -> Unit {
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
  @sf.page(c, on_back=core.pop, frame~, "memory/" + address, name, about=@sf.t("web-pages.settings.memory.lead"), [
    fn() { memory_view(c, core, look, address, station_names(stations)) },
  ])
}

///|
/// A row to each station's memory; one offline says so.
fn memories_list(c : @ui.Ctx, core : Core, stations : Array[Json]) -> Unit {
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
  let read = memory_of(core, address)
  // (read the first time: what it will show in its bones, made up)
  guard read.value is Some(_) else {
    block_waiting(c, fn() { memory_body(c, core.quiet(), look, "sample", names, Some(memory_sample())) }, error=if read.error == "" {
      ""
    } else {
      @sf.t("web-main.memory.failed", args=[("error", read.error)])
    })
  }
  memory_body(c, core, look, address, names, read.value)
}

///|
/// A station's memory (`m`, as the core reads it) as a list: its sections, each a row that opens its page.
fn memory_body(c : @ui.Ctx, core : Core, look : Look, address : String, names : Map[String, String], m : Json?) -> Unit {
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
      c.text(value, style=if narrow { @sf.pg_value } else { mem_tag_muted }) |> ignore
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
/// What a narrow page's section says where it has nothing (mMemoryNote: 24 from the page's sides, 12 in its room; 8
/// under).
// kept across runs: a value (no field of it changes)
let mem_narrow_none : @ui.Style = @ui.css("w=Full px=S3 pb=S2")

///|
// kept across runs: a value (no field of it changes)
let mem_narrow_none_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
pub let mem_narrow_title : @ui.TextStyle = @sf.body.then(@sf.one_line)

///|
// kept across runs: a value (no field of it changes)
let mem_narrow_sub : @ui.TextStyle = @sf.secondary.then(@sf.one_line).then(@sf.full_words)

///|
/// (memoryRowTitle: its name and its tags in a line, 8 apart)
// kept across runs: a value (no field of it changes)
let mem_title_line : @ui.Style = @ui.css("row gap=S2 align=AEnd")

///|
/// (memoryTag: the meta's size, subtle)
// kept across runs: a value (no field of it changes)
let mem_tag : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Subtle, wrap=false)

///|
/// (memoryRowValue: the meta's size, muted)
// kept across runs: a value (no field of it changes)
let mem_tag_muted : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
/// (memoryRowSub: the meta's size, muted, on one line cut short)
// kept across runs: a value (no field of it changes)
let mem_sub : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false, w=Full)

///|
/// A station's memory made up, for what is shown while it is read (memory_body in its bones): a few parts of the
/// global memory, a project's skill and two others.
fn memory_sample() -> Json {
  let row = fn(name : Int, line : Int, group : String) -> Json {
    {
      "name": Json::string(@sf.sample_words(name)),
      "line": Json::string(@sf.sample_words(line)),
      "size": Json::string(@sf.sample_words(3)),
      "group": Json::string(group),
    }
  }
  {
    "global": {
      "size": Json::string(@sf.sample_words(3)),
      "sections": Json::array(
        [4, 6, 5].map(fn(n) { Json::object({ "title": Json::string(@sf.sample_words(n)), "note": Json::string(@sf.sample_words(3)) }) }),
      ),
    },
    "skills": [row(6, 18, "project"), row(5, 14, "skill"), row(8, 20, "skill")],
  }
}
