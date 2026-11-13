// Presets: what a chat starts knowing, chosen on the new chat's page beside where it runs and what it
// runs on (the core's `newChat` view: the station's presets, the one picked and its name; `newChat.pick {preset}`). Its
// control opens a menu of them (不用预设 and each preset, the one picked checked; 编辑 the one picked, 新预设), or, while
// the workspace has none, the new one's dialog at once. A preset is made or changed in a dialog of nodes: its folders
// first (each a row with its ×; 添加目录 a step further in: the folders the stations found, searched by name, 浏览文件夹…
// the folder picker a step further still, 从 Git 克隆… a repository cloned onto a station, its row 正在克隆… till it is
// there), its name (the first folder's till one is typed), what people want of its chats.

///|
/// What a new chat is opened with (the presets' Chooser, beside the station's): its mark, the preset's name (预设 while
/// none is picked), a chevron; pressed, the menu of the station's presets.
fn new_preset_control(c : @ui.Ctx, src : Source, w : Workspace, v : Json?, station : Json?, floating : Bool, going : Bool) -> Unit {
  let address = text(station, "station")
  if address == "" || c.in_bones() {
    return
  }
  let t = @sf.theme()
  let picked = text(v, "preset")
  // (its name as the core says it with the page)
  let name = if picked == "" { "" } else { text(v, "presetName") }
  let label = if name == "" { @sf.t("web-main.preset.label") } else { name }
  let asked = take_asked("preset")
  if take_asked("preset-new") {
    preset_dialog(src, w, address, "", items(v, "stations"))
  }
  if take_asked("preset-edit") {
    preset_dialog(src, w, address, text(items(v, "presets").get(0), "id"), items(v, "stations"))
  }
  if take_asked("preset-add") {
    preset_dialog(src, w, address, text(items(v, "presets").get(0), "id"), items(v, "stations"), then="add")
  }
  if take_asked("preset-new-add") {
    preset_dialog(src, w, address, "", items(v, "stations"), then="add")
  }
  if take_asked("preset-new-browse") {
    preset_dialog(src, w, address, "", items(v, "stations"), then="browse")
  }
  if take_asked("preset-new-clone") {
    preset_dialog(src, w, address, "", items(v, "stations"), then="clone")
  }
  // (its folder picker in a folder of repositories)
  if take_asked("preset-new-browse-repos") {
    preset_dialog(src, w, address, "", items(v, "stations"), then="browse:/Users/lin/项目")
  }
  // (a new one's dialog with a clone under way and one failed, as the made-up station tells them: fix_clones)
  if take_asked("preset-new-clones") {
    preset_dialog(src, w, address, "", items(v, "stations"), clones=[
      { station: address, id: "c-web", repo: "github.com/acme/shop", name: "shop" },
      { station: address, id: "c-bad", repo: "github.com/acme/private", name: "private" },
    ])
  }
  let from = c.id("new/preset")
  // (none at all yet: the new one's dialog, not a menu whose one choice is 不用预设)
  let open = fn() {
    if items(v, "presets").length() == 0 {
      preset_dialog(src, w, address, "", items(v, "stations"))
    } else {
      preset_menu(src, w, address, v, picked, @sf.Of(from))
    }
  }
  new_capsule(c, "new/preset", label, floating, fn() {
    // (picked: its folders' marks, as they are shown where they are picked; none: a quiet mark of what it adds)
    let marks = items(v, "presetMarks")
    if name != "" && marks.length() > 0 {
      c.box(style=preset_marks_row, fn() {
        for m in marks {
          repo_mark(c, text(Some(m), "name"), text(Some(m), "repo"), text(Some(m), "icon"), new_mark)
        }
      })
      |> ignore
    } else {
      @sf.icon(c, "folder-plus", size=new_mark, color=t.p.muted) |> ignore
    }
    // (its words left out first, short of room: its mark says what it is, the station's name and the model's matter more)
    c.box(style=new_station_name, drop=preset_drop_words, fn() {
      c.text(label, style=if name == "" { preset_capsule_quiet } else { new_capsule_words }) |> ignore
    })
    |> ignore
    // (its chevron last, after the station's name: its mark alone, a round, on the narrowest)
    c.box(drop=preset_drop_chevron, fn() { @sf.icon(c, "chevron-down", size=new_chevron, color=t.p.muted) |> ignore }) |> ignore
  }, on_press=fn() {
    if !going {
      open()
    }
  })
  // (asked from elsewhere: opened as it is seen)
  if asked {
    open()
  }
}

///|
/// The station's presets as a menu (the model's and the station's picks' look): 不用预设 and each preset, the one
/// picked checked; under a line, 编辑 the one picked and 新预设.
fn preset_menu(src : Source, w : Workspace, address : String, v : Json?, picked : String, from : @sf.Beside) -> Unit {
  let pick = fn(id : String, at : String) { fn() { @sfbase.pick_new(src, w.id, { "preset": Json::string(id), "presetStation": Json::string(at) }) } }
  let all = items(v, "presets")
  // (which station each is of, said only where they are of more than one)
  let several = all.iter().any(fn(p) { text(Some(p), "station") != text(all.get(0), "station") })
  let menu : Array[@sf.MenuItem?] = [Some(@sf.menu_item_of(@sf.t("web-main.preset.none"), pick("", ""), chosen=picked == ""))]
  for p in all {
    let one = Some(p)
    let id = text(one, "id")
    let at = text(one, "station")
    let label = if several { text(one, "name") + " · " + text(one, "stationName") } else { text(one, "name") }
    menu.push(Some(@sf.menu_item_of(label, pick(id, at), chosen=id == picked && at == text(v, "presetStation"))))
  }
  menu.push(None)
  if picked != "" {
    let at = text(v, "presetStation")
    menu.push(
      Some(
        @sf.menu_item_of(@sf.t("web-main.preset.editNamed", args=[("name", text(v, "presetName"))]), fn() {
          preset_dialog(src, w, if at == "" { address } else { at }, picked, items(v, "stations"), browse_station=address)
        }, icon="edit"),
      ),
    )
  }
  menu.push(Some(@sf.menu_item_of(@sf.t("web-main.preset.newRow"), fn() { preset_dialog(src, w, address, "", items(v, "stations")) }, icon="plus")))
  @sf.menu(menu, from~, title=@sf.t("web-main.preset.label"))
}

///|
/// The station's presets and the folders it offers for one (the `presets` topic), read as they are shown.
fn presets_of(src : Source, address : String) -> Json? {
  src.topic("presets", { "station": Json::string(address) }).get().value
}

///|
/// A folder as a row says it: its own name.
fn dir_label(path : String) -> String {
  match path.rev_find("/") {
    Some(i) if i + 1 < path.length() => path.unsafe_substring(start=i + 1, end=path.length())
    _ => path
  }
}

///|
/// A repository being cloned for a preset (`preset.clone`'s answer, kept by the dialog that asked): the station it is
/// cloned onto, its id there, its repository and its name.
priv struct PresetClone {
  station : String
  id : String
  repo : String
  name : String
}

///|
/// A preset being made or changed: its folders (each its path, its repository, the station it is on where that is not
/// the preset's: `station`, `stationName`; what it shows as: `name`, `where`, `icon`), the repositories cloned for it
/// still to come, its name and what people want of its chats, what its name was filled with (the first folder's, until
/// another is typed), whether what it was is in it yet (one changed: once the station's presets are read), being saved,
/// why it was not; the station browsed and cloned onto (the composer's at first), 添加目录's search, the clone's address,
/// why it was not cloned, its call on its way; which step to go on to as it opens (a fixture's: `add`, `browse`,
/// `browse:<folder>`, `clone`: a step further in from the dialog, the others' from 添加目录 in their place). One object, held by the closures of its dialog and its steps.
priv struct PresetEditing {
  dirs : @signals.Signal[Array[Json]]
  clones : @signals.Signal[Array[PresetClone]]
  name : @ui.Field
  instructions : @ui.Field
  mut auto : String
  filled : @signals.Signal[Bool]
  saving : @signals.Signal[Bool]
  error : @signals.Signal[String]
  browse_station : @signals.Signal[String]
  q : @ui.Field
  url : @ui.Field
  clone_station : @signals.Signal[String]
  clone_error : @signals.Signal[String]
  clone_busy : @signals.Signal[Bool]
  then : @signals.Signal[String]
}

///|
/// A preset made (`id` "") or changed (the station's of that id) in a dialog: its folders (a row each: its mark, its
/// name over where it is, its ×; a clone under way as one, 正在克隆…; 添加目录 under them), its name (the first
/// folder's until one is typed), what people want of its chats; at its foot 删除 for one there, 取消, 创建 or 保存
/// (not while a clone of it is under way: its folder is not there yet). Made, it is the one picked for the station's
/// new chats. `stations`: the workspace's up now (the `newChat` view's), whose folders are offered too;
/// `browse_station`: the one its folders are browsed and cloned on at first (the composer's). `then`: the step gone on
/// to as it opens (a fixture's screen of each); `clones`: those under way as it opens (one).
fn preset_dialog(
  src : Source,
  w : Workspace,
  address : String,
  id : String,
  stations : Array[Json],
  then? : String = "",
  browse_station? : String = "",
  clones? : Array[PresetClone] = [],
) -> Unit {
  let e : PresetEditing = {
    dirs: @signals.signal([]),
    clones: @signals.signal(clones),
    name: @ui.Field::new(),
    instructions: @ui.Field::new(),
    auto: "",
    filled: @signals.signal(id == "", same=fn(a, b) { a == b }),
    saving: @signals.signal(false, same=fn(a, b) { a == b }),
    error: @signals.signal("", same=fn(a, b) { a == b }),
    browse_station: @signals.signal(if browse_station == "" { address } else { browse_station }, same=fn(a, b) { a == b }),
    q: @ui.Field::new(),
    url: @ui.Field::new(),
    clone_station: @signals.signal("", same=fn(a, b) { a == b }),
    clone_error: @signals.signal("", same=fn(a, b) { a == b }),
    clone_busy: @signals.signal(false, same=fn(a, b) { a == b }),
    then: @signals.signal(then, same=fn(a, b) { a == b }),
  }
  let title = if id == "" { @sf.t("web-main.preset.new") } else { @sf.t("web-main.preset.edit") }
  @sf.panel_nodes(
    title,
    fn(v, close) { preset_fields(v, src, address, id, stations, e, close) },
    from=Unanchored,
    foot=fn(v, close) { preset_foot(v, src, w, address, id, e, close) },
  )
}

///|
/// The preset `id` of `address` as the station's presets say it (None while they are read, or for a new one).
fn preset_was(src : Source, address : String, id : String) -> Json? {
  if id == "" {
    return None
  }
  items(presets_of(src, address), "presets").iter().find_first(fn(p) { text(Some(p), "id") == id })
}

///|
/// The step asked as the dialog opened (a fixture's screen: `then`), gone on to from it: it closes, the step a step
/// further in from it.
fn preset_then(src : Source, address : String, stations : Array[Json], e : PresetEditing, close : () -> Unit) -> Unit {
  let then = e.then.untracked()
  guard then != "" else { return }
  e.then.set("")
  close()
  if then == "browse" {
    preset_browse(src, address, stations, e, None)
  } else if then.has_prefix("browse:") {
    preset_browse(src, address, stations, e, Some(then.exact_view(start=7).to_owned()))
  } else if then == "clone" {
    preset_clone_open(src, address, stations, e)
  } else {
    preset_add_open(src, address, stations, e)
  }
}

///|
/// What the dialog holds, in node `v` (its body's): 目录, 名字, 指令.
fn preset_fields(
  v : @view.View,
  src : Source,
  address : String,
  id : String,
  stations : Array[Json],
  e : PresetEditing,
  close : () -> Unit,
) -> Unit {
  // (one changed: what it is, once the station's presets are read)
  v.reacts(fn() { !e.filled.get() && preset_was(src, address, id) is Some(_) }, fn(ready) {
    guard ready else { return }
    guard @signals.untracked(fn() { preset_was(src, address, id) }) is Some(p) else { return }
    e.filled.set(true)
    e.name.set(text(Some(p), "name"))
    e.instructions.set(text(Some(p), "instructions"))
    e.dirs.set(items(Some(p), "dirs"))
  })
  // its name: the first folder's until one is typed
  v.reacts(
    fn() {
      match e.dirs.get().get(0) {
        Some(d) => dir_label(text(Some(d), "path"))
        None => ""
      }
    },
    fn(auto) {
      if id == "" && @signals.untracked(fn() { e.name.text() }) == e.auto && auto != e.auto {
        e.name.set(auto)
        e.auto = auto
      }
    },
  )
  // a clone done: its folder among the preset's, as the station offers it, once it has left the clones it tells and
  // is among its folders by its repository
  v.reacts(fn() { e.clones.get().filter(fn(k) { clone_done(src, address, stations, k) is Some(_) }).map(fn(k) { k.id }) }, fn(
    done,
  ) {
    guard done.length() > 0 else { return }
    let all = @signals.untracked(fn() { e.clones.get() })
    let dirs = @signals.untracked(fn() { e.dirs.get() }).copy()
    for k in all {
      if done.contains(k.id) {
        match @signals.untracked(fn() { clone_done(src, address, stations, k) }) {
          Some(d) => if !dirs.iter().any(fn(x) { dir_key(Some(x)) == dir_key(Some(d)) }) { dirs.push(d) }
          None => ()
        }
      }
    }
    @signals.start_batch()
    e.dirs.set(dirs)
    e.clones.set(all.filter(fn(k) { !done.contains(k.id) }))
    @signals.end_batch()
  })
  // (a step asked as it opens, a fixture's: gone on to once what it is is in it)
  // (once it has come in, as a person goes on from it: at rest first, its step after, the presenters' own way in from
  // there)
  v.reacts(fn() { e.then.get() != "" && e.filled.get() }, fn(go) {
    guard go else { return }
    v.at_moment(v.cause_at() + @ui.move_most_ms, fn() { preset_then(src, address, stations, e, close) }) |> ignore
  })
  v.box(fn(col) {
    @sf.style_node(col, fn() { preset_form })
    @sf.field_node(col, fn() { @sf.t("web-main.preset.dirs") }, hint=fn() {
      if e.dirs.get().length() == 0 && e.clones.get().length() == 0 {
        @sf.t("web-main.preset.dirsHint")
      } else {
        ""
      }
    }, fn(b) { preset_dirs_node(b, src, address, stations, e, close) })
    @sf.field_node(col, fn() { @sf.t("web-main.preset.name") }, fn(b) {
      @sf.input_node(b, e.name, placeholder=@sf.t("web-main.preset.namePlaceholder")) |> ignore
    })
    // (why it was not saved under it: a folder the station has not, say)
    @sf.field_node(col, fn() { @sf.t("web-main.preset.instructions") }, hint=fn() { @sf.t("web-main.preset.instructionsHint") }, error=fn() {
      e.error.get()
    }, fn(b) {
      @sf.textarea_node(b, e.instructions, rows=3, placeholder=@sf.t("web-main.preset.instructionsPlaceholder")) |> ignore
    })
  })
  |> ignore
}

///|
/// The preset's folders in node `v`, by station (its name over them only where they are of more than one, or of
/// another than the preset's), the clones under way among them, then 添加目录 (a step further in).
fn preset_dirs_node(
  v : @view.View,
  src : Source,
  address : String,
  stations : Array[Json],
  e : PresetEditing,
  close : () -> Unit,
) -> Unit {
  let keys = fn() {
    let dirs = e.dirs.get()
    let clones = e.clones.get()
    let order : Array[String] = []
    for d in dirs {
      let s = dir_station(Some(d), address)
      if !order.contains(s) {
        order.push(s)
      }
    }
    for k in clones {
      if !order.contains(k.station) {
        order.push(k.station)
      }
    }
    let headed = order.length() > 1 || order.iter().any(fn(s) { s != address })
    let out : Array[String] = []
    for s in order {
      if headed {
        out.push("h\n" + s)
      }
      for d in dirs {
        if dir_station(Some(d), address) == s {
          out.push("d\n" + dir_key(Some(d)))
        }
      }
      for k in clones {
        if k.station == s {
          out.push("c\n" + k.id)
        }
      }
    }
    out.push("a")
    out
  }
  v.box(fn(list) {
    list.each(keys, fn(k) { k }, fn(row, item) {
      let k = item.untracked()
      if k == "a" {
        // (what the dialog opens on in the window's middle: its folders are what a preset is made of first, its name
        // the first folder's until typed; Enter there adds one, and no input method is raised over the form by touch)
        preset_action_row(
          row,
          "plus",
          fn() { @sf.t("web-main.preset.add") },
          fn() {
            close()
            preset_add_open(src, address, stations, e)
          },
          opens=true,
        )
      } else if k.has_prefix("h\n") {
        let s = k.exact_view(start=2).to_owned()
        let saved = @signals.untracked(fn() {
          match e.dirs.get().iter().find_first(fn(d) { dir_station(Some(d), address) == s }) {
            Some(d) => text(Some(d), "stationName")
            None => ""
          }
        })
        @sf.panel_heading_node(row, fn() { preset_station_name(s, saved, stations) })
      } else if k.has_prefix("d\n") {
        let at = k.exact_view(start=2).to_owned()
        guard @signals.untracked(fn() { e.dirs.get().iter().find_first(fn(d) { dir_key(Some(d)) == at }) }) is Some(was) else {
          return
        }
        // (what it shows as: as its station offers it, where it does)
        let one = fn() {
          let offered = offered_dirs(src, address, stations)
          match offered.iter().find_first(fn(o) { dir_key(Some(o)) == at }) {
            Some(x) => Some(x)
            None => Some(was)
          }
        }
        let path = text(Some(was), "path")
        preset_dir_row(
          row,
          fn() { if text(one(), "name") != "" { text(one(), "name") } else { dir_label(path) } },
          fn() { text(one(), "repo") },
          fn() { text(one(), "icon") },
          fn() { dir_note(one(), false) },
          end=fn(x) {
            preset_drop_node(x, fn() {
              e.dirs.set(e.dirs.untracked().filter(fn(d) { dir_key(Some(d)) != at }))
            })
          },
        )
      } else {
        let cid = k.exact_view(start=2).to_owned()
        guard @signals.untracked(fn() { e.clones.get().iter().find_first(fn(x) { x.id == cid }) }) is Some(c) else {
          return
        }
        preset_clone_row(row, src, c, e)
      }
    })
  })
  |> ignore
}

///|
/// How a clone stands as its station tells it (the `presets` topic's `clones`): failed (and why), or under way (also
/// while it is no more told and not among its folders yet).
fn clone_failed(src : Source, k : PresetClone) -> String? {
  match items(presets_of(src, k.station), "clones").iter().find_first(fn(x) { text(Some(x), "id") == k.id }) {
    Some(x) if text(Some(x), "state") == "failed" => Some(clone_why(text(Some(x), "error")))
    _ => None
  }
}

///|
/// Why a clone failed, for a row's one line: the last line of git's words the station kept, its conclusion (`fatal: …`;
/// the lines before it lead up to it and would be all the row shows, cut short).
fn clone_why(error : String) -> String {
  let mut last = ""
  for line in error.split("\n") {
    let l = line.trim(chars=" \t\r").to_owned()
    if l != "" {
      last = l
    }
  }
  last
}

///|
/// A clone done: no more among the clones its station tells, and among its folders by its repository; that folder as
/// a preset's folder takes it (another station's marked with it).
fn clone_done(src : Source, address : String, stations : Array[Json], k : PresetClone) -> Json? {
  let v = presets_of(src, k.station)
  guard v is Some(_) else { return None }
  if items(v, "clones").iter().any(fn(x) { text(Some(x), "id") == k.id }) {
    return None
  }
  match items(v, "candidates").iter().find_first(fn(o) { text(Some(o), "repo") == k.repo }) {
    Some(o) => Some(dir_of_station(o, k.station, address, stations))
    None => None
  }
}

///|
/// A folder `o` a station `at` offers, as a preset of `address` takes it: as it is there, marked with its station where
/// that is another.
fn dir_of_station(o : Json, at : String, address : String, stations : Array[Json]) -> Json {
  match o {
    Object(m) if at != address => {
      let marked = m.copy()
      marked["station"] = Json::string(at)
      marked["stationName"] = Json::string(preset_station_name(at, "", stations))
      Json::object(marked)
    }
    _ => o
  }
}

///|
/// A clone of the preset's in node `v` as a folder's row: its tile, its name, under it 正在克隆… (the library's small
/// spinner at its end) or why it failed in red; its × lets go of it there (`preset.cloneDrop`) and here.
fn preset_clone_row(v : @view.View, src : Source, k : PresetClone, e : PresetEditing) -> Unit {
  let failed = fn() { clone_failed(src, k) }
  preset_row(
    v,
    fn(l) { @sf.tile_avatar_node(l, fn() { k.repo }, fn() { k.name }, fn() { "" }, preset_dir_mark, corner=@sf.small_corner) },
    fn() { k.name },
    fn() {
      match failed() {
        Some(why) => @sf.t("web-main.preset.cloneFailed", args=[("why", why)])
        None => @sf.t("web-main.preset.cloning")
      }
    },
    bad=fn() { failed() is Some(_) },
    tail=fn(t) {
      t.show(fn() { failed() is None }, at_once=true, fn(w) { @sf.spinner_node(w) |> ignore })
      preset_drop_node(t, fn() {
        (src.call)("preset.cloneDrop", { "station": Json::string(k.station), "id": Json::string(k.id) }, @sfbase.answer_unread)
        e.clones.set(e.clones.untracked().filter(fn(c) { c.id != k.id }))
      })
    },
  )
}

///|
/// A folder's row in node `v`: its tile (its picture, else its letter on its repository's colour), its name over where
/// it is (`note`), `end` at its end where given (its ×); pressed, `press` where given.
fn preset_dir_row(
  v : @view.View,
  name : () -> String,
  repo : () -> String,
  icon : () -> String,
  note : () -> String,
  press? : () -> Unit,
  end? : (@view.View) -> Unit,
) -> Unit {
  preset_row(
    v,
    fn(l) { @sf.tile_avatar_node(l, fn() { if repo() != "" { repo() } else { name() } }, name, icon, preset_dir_mark, corner=@sf.small_corner) },
    name,
    note,
    press?,
    tail?=end,
  )
}

///|
/// A row of the preset's, in node `v`: what `lead` makes (a tile) where a folder's mark stands, its `title` over its
/// `note` (red where `bad`; none where ""), each one line cut short, what `tail` makes at its end; as high as a press
/// at least, its words on the panel's words' line (panel_row_in_node), its ground out to the panel's sides as the
/// panel's rows' are. Pressed whole where `press` is given (a button named by its title, its ground under the hand);
/// `opens`: what a dialog in the window's middle opens on (@sf.panel_opens_on_node).
fn preset_row(
  v : @view.View,
  lead : (@view.View) -> Unit,
  title : () -> String,
  note : () -> String,
  bad? : () -> Bool = fn() { false },
  press? : () -> Unit,
  tail? : (@view.View) -> Unit,
  opens? : Bool = false,
) -> Unit {
  v.box(fn(r) {
    @sf.style_node(r, fn() { preset_row_at.then(@sf.panel_row_in_node(r)) })
    match press {
      Some(p) => {
        r
        .ground(By(fn() { if @sf.lit_node(r) { @sf.theme().p.hover } else { 0L } }))
        |> ignore
        @sf.rippled_node(r, p, @sf.panel_row_corner_node(r), title)
        if opens {
          @sf.panel_opens_on_node(r)
        }
      }
      None => ()
    }
    r.box(fn(l) {
      l.shrink(Is(0.0)) |> ignore
      lead(l)
    })
    |> ignore
    r.box(fn(w) {
      w.grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
      @sf.words_node(w, title, fn() { preset_dir_name }) |> ignore
      w.show(fn() { note() != "" }, fn(n) {
        @sf.words_node(n, note, fn() { if bad() { preset_dir_bad } else { preset_dir_note } }) |> ignore
      })
    })
    |> ignore
    match tail {
      Some(t) =>
        r.box(fn(e) {
          e.shrink(Is(0.0)).row(Is(true)).gap(Is(preset_tail_gap)).lines_up(Is(Some(Middle))) |> ignore
          t(e)
        })
        |> ignore
      None => ()
    }
  })
  |> ignore
}

///|
/// A row that does something in node `v`, as a folder's row stands: a neutral tile with `icon` in it where a folder's
/// mark stands, its `words` on one line; pressed whole, `press`.
fn preset_action_row(v : @view.View, icon : String, words : () -> String, press : () -> Unit, opens? : Bool = false) -> Unit {
  preset_row(v, fn(l) { preset_action_tile(l, icon) }, words, fn() { "" }, press~, opens~)
}

///|
/// A neutral tile as large as a folder's mark, `icon` in its middle, in node `v`.
fn preset_action_tile(v : @view.View, icon : String) -> Unit {
  v.box(fn(t) {
    t
    .width(Is(Some(preset_dir_mark)))
    .height(Is(Some(preset_dir_mark)))
    .radius(Is(@sf.small_corner))
    .row(Is(true))
    .lines_up(Is(Some(Middle)))
    .lies_along(Is(Middle))
    .ground(By(fn() { @sf.theme().p.neutral_bg }))
    |> ignore
    @sf.icon_node(t, icon, preset_action_icon, By(fn() { @sf.theme().p.muted })) |> ignore
  })
  |> ignore
}

///|
/// A row's ×, in node `v`: named 移除.
fn preset_drop_node(v : @view.View, press : () -> Unit) -> Unit {
  @sf.icon_button_node(v, "close", fn() { @sf.t("web-main.preset.remove") }, press, size=preset_dir_x) |> ignore
}

///|
/// The dialog's foot in node `v`: 删除 for one there (asked first), 取消, 创建 or 保存 (busy as it is saved; not while it
/// has no folder or no name, or a clone of it is under way).
fn preset_foot(
  v : @view.View,
  src : Source,
  w : Workspace,
  address : String,
  id : String,
  e : PresetEditing,
  close : () -> Unit,
) -> Unit {
  if id != "" {
    @sf.button_node(v, fn() { @sf.t("common.delete") }, fn() {
      @sf.confirm(
        @sf.t("web-main.preset.deleteTitle", args=[("name", e.name.text())]),
        @sf.t("web-main.preset.deleteBody"),
        @sf.t("common.delete"),
        danger=true,
        fn() {
          close()
          (src.call)("preset.delete", Json::object({ "station": Json::string(address), "id": Json::string(id) }), @sfbase.answer_unread)
        },
      )
    }, tone=GhostDanger)
    |> ignore
  }
  @sf.foot_spacer_node(v)
  @sf.button_node(v, fn() { @sf.t("common.cancel") }, close, tone=Ghost) |> ignore
  let named = fn() { e.name.text().trim(chars=" \n").to_owned() }
  let ready = fn() { e.dirs.get().length() > 0 && named() != "" && !e.clones.get().iter().any(fn(k) { clone_failed(src, k) is None }) }
  @sf.button_node(
    v,
    fn() { if id == "" { @sf.t("web-main.preset.create") } else { @sf.t("common.save") } },
    fn() {
      e.saving.set(true)
      e.error.set("")
      let params : Map[String, Json] = {
        "station": Json::string(address),
        "name": Json::string(@signals.untracked(named)),
        // (this station's by their paths; another's as it was read there, with its station)
        "dirs": Json::array(
          e.dirs.untracked().map(fn(d) {
            let one = Some(d)
            if text(one, "station") == "" {
              Json::string(text(one, "path"))
            } else {
              Json::object({
                "path": Json::string(text(one, "path")),
                "repo": if text(one, "repo") == "" { Json::null() } else { Json::string(text(one, "repo")) },
                "station": Json::string(text(one, "station")),
                "stationName": Json::string(text(one, "stationName")),
              })
            }
          }),
        ),
        "instructions": Json::string(@signals.untracked(fn() { e.instructions.text() })),
      }
      if id != "" {
        params["id"] = Json::string(id)
      }
      (src.call)(if id == "" { "preset.add" } else { "preset.put" }, Json::object(params), fn(r) {
        e.saving.set(false)
        match r {
          Ok(made) => {
            // made: the one the station's new chats are opened with
            if id == "" {
              @sfbase.pick_new(src, w.id, { "preset": Json::string(text(Some(made), "id")), "presetStation": Json::string(address) })
            }
            close()
          }
          Err(err) => e.error.set(text(Some(err), "message"))
        }
      })
    },
    tone=Primary,
    busy=fn() { e.saving.get() },
    disabled=fn() { !ready() },
  )
  |> ignore
}

///|
/// 添加目录, a step further in from the dialog: a line to find one by name, then 浏览文件夹… and 从 Git 克隆… first
/// whatever is typed, then the folders the workspace's stations found and not in the preset yet, as they come (each
/// station's said as it is; those read before shown meanwhile), by station, those their chats worked in first, each
/// where it is and how many chats used it. One picked, back to the dialog with it among the folders.
fn preset_add_open(src : Source, address : String, stations : Array[Json], e : PresetEditing) -> Unit {
  e.q.set("")
  @sf.panel_nodes(
    @sf.t("web-main.preset.add"),
    fn(v, close) { preset_add_node(v, src, address, stations, e, close) },
    from=Unanchored,
    // (as tall as the folder picker a step further on, its share of the window whatever it lists: as tall as the
    // dialog it comes from or taller, which stays as it was laid out as it slides off, its foot where it stood)
    tall=preset_steps_tall,
  )
}

///|
/// 添加目录's rows' keys: its two ways first, then each station's name over the folders it offers that are not the
/// preset's yet and have what is typed in their name, repository, place or station.
fn preset_add_keys(src : Source, address : String, stations : Array[Json], e : PresetEditing) -> Array[String] {
  let q = e.q.text().trim(chars=" ").to_owned().to_lower()
  let dirs = e.dirs.get()
  let out = ["a\nbrowse", "a\nclone"]
  let mut shown = ""
  for o in offered_dirs(src, address, stations) {
    let one = Some(o)
    let k = dir_key(one)
    let station = dir_station(one, address)
    let station_name = preset_station_name(station, text(one, "stationName"), stations)
    let (name, repo) = (text(one, "name"), text(one, "repo"))
    if dirs.iter().any(fn(d) { dir_key(Some(d)) == k }) ||
      (q != "" && !name.to_lower().contains(q) && !repo.to_lower().contains(q) && !text(one, "where").to_lower().contains(q) && !station_name.to_lower().contains(q)) {
      continue
    }
    if shown != station {
      out.push("h\n" + station)
      shown = station
    }
    out.push("o\n" + k)
  }
  // (room after the last, clear of a dialog's foot corners)
  out.push("z")
  out
}

///|
/// What 添加目录 holds in node `v`: the line to find by, standing still, and its rows scrolling under it.
fn preset_add_node(
  v : @view.View,
  src : Source,
  address : String,
  stations : Array[Json],
  e : PresetEditing,
  close : () -> Unit,
) -> Unit {
  let browse = fn(at : String?) {
    close()
    preset_browse(src, address, stations, e, at)
  }
  let clone = fn() {
    close()
    preset_clone_open(src, address, stations, e)
  }
  v.box(fn(fb) {
    @sf.style_node(fb, fn() { preset_search_at.then(@sf.panel_field_in_node(fb)) })
    @sf.input_node(
      fb,
      e.q,
      placeholder=@sf.t("web-main.preset.search"),
      small=true,
      lead=fn(l) { @sf.icon_node(l, "search", preset_search_icon, By(fn() { @sf.theme().p.muted })) |> ignore },
    )
    // (a search over what the panel lists: the keys as it opens with keys and a mouse, never an input method raised
    // over the folders)
    |> @sf.panel_search_at_hand_node
  })
  |> ignore
  @sf.panel_list_node(
    v,
    fn() { preset_add_keys(src, address, stations, e) },
    fills=true,
    fn(r, k) {
      if k == "z" {
        r.box(fn(z) { @sf.style_node(z, fn() { preset_list_end }) }) |> ignore
      } else if k == "a\nbrowse" {
        preset_action_row(r, "folder", fn() { @sf.t("web-main.preset.browse") }, fn() { browse(None) })
      } else if k == "a\nclone" {
        preset_action_row(r, "download", fn() { @sf.t("web-main.preset.clone") }, clone)
      } else if k.has_prefix("h\n") {
        let s = k.exact_view(start=2).to_owned()
        let saved = @signals.untracked(fn() {
          match offered_dirs(src, address, stations).iter().find_first(fn(o) { dir_station(Some(o), address) == s }) {
            Some(o) => text(Some(o), "stationName")
            None => ""
          }
        })
        @sf.panel_heading_node(r, fn() { preset_station_name(s, saved, stations) })
      } else {
        let at = k.exact_view(start=2).to_owned()
        let find = fn() { offered_dirs(src, address, stations).iter().find_first(fn(o) { dir_key(Some(o)) == at }) }
        guard @signals.untracked(find) is Some(was) else { return }
        let one = fn() { Some(find().unwrap_or(was)) }
        preset_dir_row(
          r,
          fn() { text(one(), "name") },
          fn() { text(one(), "repo") },
          fn() { text(one(), "icon") },
          fn() { dir_note(one(), true) },
          press=fn() {
            e.dirs.set([..e.dirs.untracked(), was])
            @sf.panel_back() |> ignore
          },
        )
      }
    },
    est=preset_row_est,
  )
  |> ignore
}

///|
/// The stations a folder is browsed or cloned on (the workspace's up now), as the library's station control has them.
fn preset_station_choices(stations : Array[Json]) -> Array[@sf.StationChoice] {
  stations.map(fn(s) {
    let one = Some(s)
    { station: text(one, "station"), name: preset_station_name(text(one, "station"), "", stations), emoji: text(one, "emoji"), icon: text(one, "icon") }
  })
}

///|
/// 浏览文件夹, a step further in from 添加目录: the folder picker on the station browsed (the composer's at first), at
/// `at` (its home where None), its stations the workspace's up now; switching starts at that station's home. The folder
/// chosen goes among the preset's (on another station than the preset's, with it: its repository where that station
/// offers it so), back in the dialog.
fn preset_browse(src : Source, address : String, stations : Array[Json], e : PresetEditing, at : String?) -> Unit {
  (@sfbase.folder_pick_asked.val)(src, {
    title: @sf.t("web-main.preset.pickFolder"),
    note: "",
    stations: preset_station_choices(stations),
    station: e.browse_station.untracked(),
    at: at.unwrap_or(""),
    action: fn(name) { @sf.t("web-main.preset.choose", args=[("name", name)]) },
    taken: fn(_, _) { false },
    taken_words: "",
    pick: fn(station, here, _, _) {
      e.browse_station.set(station)
      let d = if station == address {
        Json::object({ "path": Json::string(here) })
      } else {
        // (the station offering this folder as a repository: that kept too)
        let repo = match items(presets_of(src, station), "candidates").iter().find_first(fn(o) { text(Some(o), "path") == here }) {
          Some(o) => field(Some(o), "repo").unwrap_or(Json::null())
          None => Json::null()
        }
        Json::object({
          "path": Json::string(here),
          "repo": repo,
          "station": Json::string(station),
          "stationName": Json::string(preset_station_name(station, "", stations)),
        })
      }
      if !e.dirs.untracked().iter().any(fn(x) { dir_key(Some(x)) == dir_key(Some(d)) }) {
        e.dirs.set([..e.dirs.untracked(), d])
      }
      @sf.panel_back(to=1) |> ignore
    },
  })
}

///|
/// 从 Git 克隆, a step further in from 添加目录: under its title where it goes, then the repository's address (its field
/// the keys' as it opens); at its foot the station it is cloned onto (the one browsed; another where there are others)
/// and 克隆, which asks it of that station (`preset.clone`): one it has already among the preset's folders, one under way
/// remembered by the dialog, back in the dialog either way; why not under the field.
fn preset_clone_open(src : Source, address : String, stations : Array[Json], e : PresetEditing) -> Unit {
  e.url.set("")
  e.clone_error.set("")
  e.clone_busy.set(false)
  e.clone_station.set(e.browse_station.untracked())
  let go = fn() {
    let url = @signals.untracked(fn() { e.url.text() }).trim(chars=" \t\n").to_owned()
    guard url != "" && !e.clone_busy.untracked() else { return }
    let station = e.clone_station.untracked()
    e.clone_busy.set(true)
    e.clone_error.set("")
    (src.call)("preset.clone", { "station": Json::string(station), "url": Json::string(url) }, fn(r) {
      e.clone_busy.set(false)
      match r {
        Ok(a) => {
          let one = Some(a)
          if text(one, "state") == "there" {
            let d = dir_of_station(
              Json::object({ "path": Json::string(text(one, "path")), "repo": Json::string(text(one, "repo")), "name": Json::string(text(one, "name")) }),
              station,
              address,
              stations,
            )
            if !e.dirs.untracked().iter().any(fn(x) { dir_key(Some(x)) == dir_key(Some(d)) }) {
              e.dirs.set([..e.dirs.untracked(), d])
            }
          } else {
            e.clones.set([..e.clones.untracked(), { station, id: text(one, "id"), repo: text(one, "repo"), name: text(one, "name") }])
          }
          e.browse_station.set(station)
          @sf.panel_back(to=1) |> ignore
        }
        Err(err) => e.clone_error.set(text(Some(err), "message"))
      }
    })
  }
  @sf.panel_nodes(
    @sf.t("web-main.preset.cloneTitle"),
    fn(v, _) {
      v.box(fn(col) {
        @sf.style_node(col, fn() { preset_form })
        @sf.field_node(
          col,
          fn() { @sf.t("web-main.preset.cloneUrl") },
          error=fn() { e.clone_error.get() },
          fn(b) {
            let f = @sf.input_node(b, e.url, placeholder=@sf.t("web-main.preset.clonePlaceholder"), submitted=fn(_) { go() })
            @sf.panel_opens_in_node(f)
          },
        )
      })
      |> ignore
    },
    from=Unanchored,
    // (where it goes said under its title, as the station it goes onto is now)
    live=fn() {
      (
        @sf.t("web-main.preset.cloneTitle"),
        "",
        @sf.t("web-main.preset.cloneWhere", args=[("station", preset_station_name(e.clone_station.get(), "", stations))]),
      )
    },
    foot=fn(v, _) {
      // (the station it is cloned onto at its start: another where there are others; round as the buttons beside it)
      @sf.station_choice_node(
        v,
        fn() { preset_station_choices(stations) },
        fn() { e.clone_station.get() },
        fn(at) { e.clone_station.set(at) },
        title=@sf.t("android-misc.files.lendOn"),
        label=fn(name) { @sf.t("android-misc.files.lendOn") + ": " + name },
        round=true,
      )
      |> ignore
      @sf.foot_spacer_node(v)
      @sf.button_node(v, fn() { @sf.t("web-main.preset.cloneGo") }, go, tone=Primary, busy=fn() { e.clone_busy.get() }, disabled=fn() {
        e.url.text().trim(chars=" \t\n").to_owned() == ""
      })
      |> ignore
    },
  )
}

///|
/// A folder by where it is: its station ("" the preset's own) and its path.
fn dir_key(d : Json?) -> String {
  text(d, "station") + "\n" + text(d, "path")
}

///|
/// The station a folder is on (an absent station means the preset's own).
fn dir_station(d : Json?, address : String) -> String {
  let at = text(d, "station")
  if at == "" { address } else { at }
}

///|
/// The workspace's current name for a station, or its saved name when it is offline.
fn preset_station_name(address : String, saved : String, stations : Array[Json]) -> String {
  match stations.iter().find_first(fn(s) { text(Some(s), "station") == address }) {
    Some(s) if text(Some(s), "name") != "" => text(Some(s), "name")
    _ => if saved != "" { saved } else { address }
  }
}

///|
/// The folders the workspace's stations offer (each one's `presets` topic, read as it is shown): the preset's
/// station's first, then the others', each marked with its station. The same repository on two stations is offered
/// on both: their paths and the instructions in them can differ.
fn offered_dirs(src : Source, address : String, stations : Array[Json]) -> Array[Json] {
  let out : Array[Json] = []
  let take = fn(at : String, station_name : String) {
    for o in items(presets_of(src, at), "candidates") {
      match o {
        Object(m) if at != address => {
          let marked = m.copy()
          marked["station"] = Json::string(at)
          marked["stationName"] = Json::string(station_name)
          out.push(Json::object(marked))
        }
        _ => out.push(o)
      }
    }
  }
  take(address, "")
  for s in stations {
    let at = text(Some(s), "station")
    if at != "" && at != address {
      take(at, text(Some(s), "name"))
    }
  }
  out
}

///|
/// What a folder says under its name: where it is, and how many chats worked in it (`chats`: where it is offered).
fn dir_note(o : Json?, chats : Bool) -> String {
  let n = count(o, "chats")
  let at = if text(o, "where") != "" { text(o, "where") } else if text(o, "repo") != "" { text(o, "repo") } else { text(o, "path") }
  let parts = [
    at,
    if chats && n > 0 { @sf.t("web-main.preset.chats", args=[("n", n.to_string())]) } else { "" },
  ]
  join(parts.filter(fn(x) { x != "" }), " · ")
}

///|
/// A folder's mark: its own picture where the station found one, else its first letter on its repository's colour.
fn repo_mark(c : @ui.Ctx, name : String, repo : String, icon : String, size : Double) -> Unit {
  @sf.tile_avatar(c, if repo != "" { repo } else { name }, name, icon, size, corner=@sf.small_corner)
}

///|
/// A folder's mark in the preset's dialog: as high as its two lines (`L6 + L5`), its corner the small block's (the
/// ladder's 10).
let preset_dir_mark : Double = 38.0

///|
/// The icon in a neutral tile of a row that does something (浏览文件夹…, 从 Git 克隆…, 添加目录).
let preset_action_icon : Double = 20.0

///|
/// A folder's ×: as high as its name's line and a half.
let preset_dir_x : Double = 28.0

///|
/// The search's mark before what is typed.
let preset_search_icon : Double = 16.0

///|
/// A row's height before it is laid out (a name, a note under it, its tile's room).
let preset_row_est : Double = 56.0

///|
/// 添加目录's share of the window, the folder picker's (sfdesk station_pick_tall's).
let preset_steps_tall : Double = 0.86

///|
/// 添加目录's room after its last row: what is there clear of a dialog's foot corners (no foot of its own).
// kept across runs: a value (no field of it changes)
let preset_list_end : @ui.Style = @ui.css("w=Full h=S4")

///|
/// Between what stands at a row's end (a spinner, its ×).
let preset_tail_gap : Double = 8.0

///|
/// A row of the preset's (preset_row): 44 high at least, 8 over and under, 12 between its tile, its words, its end.
// kept across runs: a value (no field of it changes)
let preset_row_at : @ui.Style = @ui.css("row w=Full min_h=S11 py=S2 gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let preset_dir_name : @ui.TextStyle = @ui.text_style(size=Body, leading=L6, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let preset_dir_note : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false, w=Cut)

///|
/// Why a clone failed, in red.
// kept across runs: a value (no field of it changes)
let preset_dir_bad : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Danger, wrap=false, w=Cut)

///|
/// The dialog's fields, and the clone step's: one under another, 20 apart.
// kept across runs: a value (no field of it changes)
let preset_form : @ui.Style = @ui.css("w=Full gap=S5")

///|
/// 添加目录's search over its rows: across the panel (where panel_field_in_node stands it), a row's room under it.
// kept across runs: a value (no field of it changes)
let preset_search_at : @ui.Style = @ui.css("w=Full pb=S1_5")

///|
/// The picked preset's folders' marks, side by side in its control.
// kept across runs: a value (no field of it changes)
let preset_marks_row : @ui.Style = @ui.css("row gap=S0_5 align=ACenter")

///|
/// Short of room, the preset's words go with the first of the model's parts (model_triple.mbt triple_drop_name: who
/// runs it by name, later in the row, goes before them), before the station's name.
let preset_drop_words : Int = 1

///|
/// The last it gives up, after the station's name: its chevron.
let preset_drop_chevron : Int = new_drop_station_name + 1

///|
/// The control's words while no preset is picked: as quiet as what says what is not chosen.
// kept across runs: a value (no field of it changes)
let preset_capsule_quiet : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false, w=Cut)
