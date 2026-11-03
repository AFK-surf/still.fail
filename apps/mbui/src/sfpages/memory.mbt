// 记忆, one page in every frame (web/src/Memory.tsx MemoryView, cloud/settings.tsx MemorySettings; the narrow app's
// mobile/Memory.tsx MemoriesScreen, MemoryScreen), the same on every width (the user, 2026-10-26: 「设置感觉很乱」; wide
// had every station's memory on the one page, a third level of headings): a row for each station opening its memory,
// one offline saying so. A station's memory: the global memory by its parts, the projects', the other skills (the
// station's own folded in a row), each row opening its page; which part a skill is under is the core's (`group`).

///|
/// 记忆 (MemorySettings, MemoriesScreen) made once as nodes (page_node, laid out by the `width` its frame gives it,
/// narrow where none is given) in node `v`: what it is for over its list, a row to each
/// station's memory (its name, opening it), one offline saying so, followed as the core says them; while the stations
/// are read the first time, the list in its bones (waiting_node: three made up, the core asked nothing for them), what
/// could not be read said over them. `here`: who and where, as that changes.
pub fn memories_node(
  v : @view.View,
  core : Core,
  here : () -> @settings.Here,
  on_back~ : () -> Unit,
  frame~ : () -> PageFrame,
  said? : (@sf.PageSaid) -> Unit,
  width? : () -> Double,
) -> Unit {
  let topic = fn() { @settings.stations_of(core, here()) }
  @sf.page_node(
    v,
    fn() { @sf.t("web-pages.settings.memory.title") },
    on_back~,
    frame~,
    said?,
    width?,
    lead=fn() { @sf.t("android-misc.memory.note") },
    fn() { ["list"] },
    fn(b, _) {
      b.pick(fn() { topic().value is None }, fn(p, reading) {
        if reading {
          @sf.waiting_node(
            p,
            fn(s) { memories_list_node(s, core.quiet(), fn() { sample_stations() }) },
            error=fn() {
              match topic().error {
                Some(e) => error_text(e)
                None => ""
              }
            },
          )
        } else {
          memories_list_node(p, core, fn() {
            match topic().value {
              Some(Array(a)) => a
              _ => []
            }
          })
        }
      })
    },
  )
}

///|
/// A row to each of `stations`' memory as they are now, by its address: online, its name
/// and 查看 opening it; offline, its name and that it is.
fn memories_list_node(v : @view.View, core : Core, stations : () -> Array[Json]) -> Unit {
  @sf.group_node(v, fn(g) {
    g.each(stations, fn(s) { text(Some(s), "station") }, fn(row, s) {
      let sv = fn() { Some(s.get()) }
      row.pick(fn() { flag(sv(), "online") }, fn(r, online) {
        if online {
          @sf.link_row_node(r, fn() { text(sv(), "name") }, fn() { (core.push)(Memory(text(sv(), "station"))) }, value=fn() {
            @sf.t("android-misc.memory.row")
          })
        } else {
          @sf.link_row_node(r, fn() { text(sv(), "name") }, fn() {  }, goes=false, note=fn() {
            @sf.t("web-pages.settings.memory.offline")
          })
        }
      })
    })
  })
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
  let open = @settings.builtin_open_of(address)
  let skill_row = fn(k : Json) {
    let kv = Some(k)
    // (the core's: when it is read, in a line)
    if memory_row(c, "memory/" + address + "/skill/" + text(kv, "name"), text(kv, "name"), text(kv, "line"), text(kv, "size"), tag=skill_tag(kv, names)) {
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
          if memory_row(c, "memory/" + address + "/part/" + i.to_string(), p.0, "", p.2) {
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
            @settings.builtin_turn(address)
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
/// A row that opens a page, or folds a group open (MemoryRow): a library row, its name and whose after it, a line
/// under it (cut short), how much is in it at its end. True on the frame it is pressed.
fn memory_row(
  c : @ui.Ctx,
  key : String,
  title : String,
  sub : String,
  value : String,
  tag? : String = "",
  open? : Bool = false,
) -> Bool {
  @sf.link_row(
    c,
    key,
    title,
    note=sub,
    note_cut=true,
    value~,
    title_after?=if tag != "" { Some(fn() { c.text(tag, style=mem_tag) |> ignore }) } else { None },
    folds?=if key.has_suffix("/builtin") { Some(open) } else { None },
  )
}

///|
/// One station's memory made once as nodes (memory_page's: page_node, laid out by the `width` its frame gives it,
/// narrow where none is given) in node `v`, titled by the station's name as `here`'s stations say it: its global
/// memory by its parts, its projects', the other skills (its built-in ones folded in a row, open as it was left), each
/// row opening its page, followed as the core says them; while it is read the first time, all of it in its bones
/// (waiting_node: made up, the core asked nothing for it), what could not be read said over it.
pub fn memory_node(
  v : @view.View,
  core : Core,
  here : () -> @settings.Here,
  address : String,
  on_back~ : () -> Unit,
  frame~ : () -> PageFrame,
  said? : (@sf.PageSaid) -> Unit,
  width? : () -> Double,
) -> Unit {
  let stations = fn() {
    match @settings.stations_of(core, here()).value {
      Some(Array(a)) => a
      _ => []
    }
  }
  let title = fn() {
    let mut name = @settings.station_name(address)
    for s in stations() {
      if text(Some(s), "station") == address {
        name = text(Some(s), "name")
      }
    }
    name
  }
  let names = fn() { station_names(stations()) }
  let read = fn() { memory_of(core, address) }
  @sf.page_node(
    v,
    title,
    on_back~,
    frame~,
    said?,
    width?,
    about=fn() { @sf.t("web-pages.settings.memory.lead") },
    fn() { ["memory"] },
    fn(b, _) {
      b.pick(fn() { read().value is None }, fn(p, reading) {
        if reading {
          @sf.waiting_node(
            p,
            fn(s) { memory_body_node(s, core.quiet(), "sample", names, fn() { Some(memory_sample()) }) },
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
          memory_body_node(p, core, address, names, fn() { read().value })
        }
      })
    },
  )
}

///|
/// A station's memory (`m`, as the core reads it, as it changes) as nodes (memory_body's): its global memory by its
/// parts, its projects', the other skills with its built-in ones folded in a row, each row opening its page.
fn memory_body_node(
  v : @view.View,
  core : Core,
  address : String,
  names : () -> Map[String, String],
  m : () -> Json?,
) -> Unit {
  let skills = fn(group : String) { items(m(), "skills").filter(fn(k) { text(Some(k), "group") == group }) }
  let skill_rows = fn(g : @view.View, group : () -> Array[Json]) {
    g.each(group, fn(k) { text(Some(k), "name") }, fn(row, k) {
      let kv = fn() { Some(k.get()) }
      memory_row_node(
        row,
        fn() { text(kv(), "name") },
        fn() { text(kv(), "line") },
        fn() { text(kv(), "size") },
        tag=fn() { skill_tag(kv(), names()) },
        fn() { (core.push)(MemoryDoc(address, text(kv(), "name"), 0)) },
      )
    })
  }
  // (what a section says where it has nothing)
  let none = fn(p : @view.View, words : () -> String) {
    p.box(fn(n) {
      match @sf.look_node(n) {
        Narrow => {
          n.padding(Is((12.0, 0.0, 12.0, 8.0))) |> ignore
          @sf.words_node(n, words, fn() { mem_narrow_none_words }) |> ignore
        }
        Wide => @sf.words_node(n, words, fn() { desk_muted }) |> ignore
      }
    })
    |> ignore
  }
  @sf.section_node(
    v,
    fn() { @sf.t("web-main.memory.global") },
    note=fn() { join([@sf.t("web-main.memory.global.when"), text(field(m(), "global"), "size")], " · ") },
    fn(s) {
      s.pick(fn() { sections_of(m()).length() == 0 }, fn(p, empty) {
        if empty {
          none(p, fn() { @sf.t("web-main.memory.empty") })
        } else {
          @sf.group_node(p, fn(g) {
            g.each(fn() { sections_of(m()).mapi(fn(i, x) { (i, x) }) }, fn(x) { x.0.to_string() }, fn(row, x) {
              let i = @signals.untracked(fn() { x.get().0 })
              memory_row_node(row, fn() { x.get().1.0 }, fn() { "" }, fn() { x.get().1.2 }, fn() {
                (core.push)(MemoryDoc(address, "", i))
              })
            })
          })
        }
      })
    },
  )
  @sf.section_node(v, fn() { @sf.t("web-main.memory.projects") }, note=fn() { @sf.t("web-main.memory.projects.when") }, fn(
    s,
  ) {
    s.pick(fn() { skills("project").length() == 0 }, fn(p, empty) {
      if empty {
        none(p, fn() { @sf.t("web-main.memory.projects.none") })
      } else {
        @sf.group_node(p, fn(g) { skill_rows(g, fn() { skills("project") }) })
      }
    })
  })
  v.show(fn() { skills("skill").length() + skills("builtin").length() > 0 }, fn(o) {
    @sf.section_node(o, fn() { @sf.t("web-main.memory.others") }, fn(s) {
      @sf.group_node(s, fn(g) {
        skill_rows(g, fn() { skills("skill") })
        // (the station's own, folded in a row: open as it was left, @settings.builtin_open_of)
        g.show(fn() { skills("builtin").length() > 0 }, fn(f) {
          let open = fn() { @settings.builtin_open_of(address) }
          memory_row_node(
            f,
            fn() { @sf.t("web-main.memory.builtin") },
            fn() {
              if open() {
                ""
              } else {
                join(skills("builtin").map(fn(k) { text(Some(k), "name") }), @sf.t("web-main.list.separator"))
              }
            },
            fn() { @sf.t("web-main.memory.count", args=[("n", skills("builtin").length().to_string())]) },
            folds=open,
            fn() { @settings.builtin_turn(address) },
          )
        })
        g.show(fn() { skills("builtin").length() > 0 && @settings.builtin_open_of(address) }, fn(f) {
          skill_rows(f, fn() { skills("builtin") })
        })
      })
    })
  })
}

///|
/// A row of a station's memory made once (memory_row's): its name and whose (`tag`, as it changes) after it on
/// its line, a line under it cut short, how much is in it at its end; `folds` what follows it where it says so.
fn memory_row_node(
  parent : @view.View,
  title : () -> String,
  sub : () -> String,
  value : () -> String,
  tag? : () -> String = fn() { "" },
  folds? : () -> Bool,
  press : () -> Unit,
) -> Unit {
  @sf.link_row_node(
    parent,
    title,
    press,
    value~,
    note=sub,
    note_cut=true,
    title_after=fn(a) { @sf.words_node(a, tag, fn() { mem_tag }) |> ignore },
    title_after_shown=fn() { tag() != "" },
    folds?,
  )
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
