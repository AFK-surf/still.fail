// Presets: what a chat starts knowing, chosen on the new chat's page beside where it runs and what it
// runs on (the core's `newChat` view: the person's own presets, the one picked and its name; `newChat.pick {preset}`).
// A person sees their own; the other members' are one press further in (the user, 2026-11-14: 「用户默认只能看到自己的
// 预设，想要查看别人的预设需要额外操作」): looked at, opened a chat with and copied into one's own, never edited or
// deleted here (the lead, 2026-11-14). Its control opens a menu of them (不用预设 and each of one's own, the one picked
// checked, someone else's picked among them with whose it is; 编辑 the one picked or, someone else's, 复制为我的预设;
// 新预设; 其他成员的预设, a level further in, asked of the core at that press). A preset is made or changed in a dialog
// of nodes (what it is read of the core's `preset`): its folders
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
  // (none of one's own yet: still a menu, its 新预设 and 其他成员的预设, never one whose one choice is 不用预设)
  let open = fn() { preset_menu_open(src, w, address, v, @sf.Of(from)) }
  // (the other members' presets, a fixture's screen: their menu, as a press on 其他成员的预设 opens it; and the menu
  // with someone else's picked, opened once whose it is is answered: neither opened as a view builds, press_wait)
  // (said again by each build of the frame, taken by the last: what an earlier build said is let go, Ctx::after_build)
  if new_chat_state.asked == "preset-others" {
    c.after_build("preset-others", fn() { if take_asked("preset-others") { preset_others_open(src, w, v, @sf.Of(from)) } })
  }
  // (picked: its folders' marks, as they are shown where they are picked; none: a quiet mark of what it adds)
  let marks = items(v, "presetMarks")
  new_capsule(c, "new/preset", label, floating, marked=name != "" && marks.length() > 0, fn() {
    if name != "" && marks.length() > 0 {
      c.box(style=preset_marks_row, fn() {
        for m in marks {
          repo_mark(c, text(Some(m), "name"), text(Some(m), "repo"), text(Some(m), "icon"), new_mark)
        }
      })
      |> ignore
    } else if name != "" {
      @sf.icon(c, "sparks", size=new_mark, color=t.p.accent_text) |> ignore
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
  // (asked from elsewhere: opened as it is seen, once the frame is built)
  if new_chat_state.asked == "preset" {
    c.after_build("preset-open", fn() { if take_asked("preset") { open() } })
  }
}

///|
/// Whether the preset picked (`v`'s `preset`) is the person's own: none picked, or among their own (`presets`). One
/// that is not is someone else's, picked from 其他成员的预设.
fn preset_picked_own(v : Json?) -> Bool {
  let picked = text(v, "preset")
  picked == "" || items(v, "presets").iter().any(fn(p) { text(Some(p), "id") == picked })
}

///|
/// What the preset `id` of workspace `scope` is asked by, whole (the core's `preset`: whose it is, its folders).
fn preset_asked(scope : String, id : String) -> Map[String, Json] {
  { "scope": Json::string(scope), "id": Json::string(id) }
}

///|
/// The presets' menu opened by a press on the control: at once where the one picked is the person's own or none is;
/// someone else's, once whose it is is answered (its `preset`, asked at the press and let go of as the menu opens:
/// the page holds no topic for it), the screen as it was meanwhile (press_wait). Answered with an error (nothing on
/// the device has it any more), the menu by its name alone.
fn preset_menu_open(src : Source, w : Workspace, address : String, v : Json?, from : @sf.Beside) -> Unit {
  if preset_picked_own(v) {
    preset_menu(src, w, address, v, "", from)
    return
  }
  let (answered, leases) = @sfbase.asked_now(src, [("preset", preset_asked(w.id, text(v, "preset")))])
  let let_go = fn() { leases.each(fn(l) { l.cancel() }) }
  @sfbase.press_wait(answered, fn() {
    let one = match @signals.untracked(fn() { leases[0].follow() }) {
      Some(t) => t.value
      None => None
    }
    let_go()
    preset_menu(src, w, address, v, text(one, "whose"), from)
  }, let_go~)
  |> ignore
}

///|
/// The person's presets as a menu (the model's and the station's picks' look): 不用预设 and each of their own, the one
/// picked checked, and someone else's where that is the one picked, checked, whose it is after its name (`whose`: ""
/// where that was not said), so what is picked is always in sight; under a line, for the one picked 编辑「X」 (one's
/// own) or 复制为我的预设 (someone else's), 新预设, and 其他成员的预设, a level further in. With none of their own and
/// none picked, no 不用预设 (its one choice would be the one there) and no line.
fn preset_menu(src : Source, w : Workspace, address : String, v : Json?, whose : String, from : @sf.Beside) -> Unit {
  let picked = text(v, "preset")
  let all = items(v, "presets")
  let own = preset_picked_own(v)
  let menu : Array[@sf.MenuItem?] = []
  if picked != "" || all.length() > 0 {
    menu.push(Some(@sf.menu_item_of(@sf.t("web-main.preset.none"), preset_pick(src, w, "", ""), chosen=picked == "")))
  }
  for p in all {
    let one = Some(p)
    let id = text(one, "id")
    let at = text(one, "station")
    menu.push(Some(@sf.menu_item_of(preset_menu_label(all, p), preset_pick(src, w, id, at), chosen=id == picked && at == text(v, "presetStation"))))
  }
  if !own {
    menu.push(
      Some(
        @sf.menu_item_of(
          preset_whose_label(text(v, "presetName"), whose),
          preset_pick(src, w, picked, text(v, "presetStation")),
          chosen=true,
        ),
      ),
    )
  }
  if menu.length() > 0 {
    menu.push(None)
  }
  if picked != "" {
    menu.push(Some(if own { preset_edit_item(src, w, address, v, picked) } else { preset_copy_item(src, w, address, v) }))
  }
  menu.push(Some(@sf.menu_item_of(@sf.t("web-main.preset.newRow"), fn() { preset_dialog(src, w, address, "", items(v, "stations")) }, icon="plus")))
  menu.push(Some(@sf.menu_item_of(@sf.t("web-main.preset.others"), fn() { preset_others_open(src, w, v, from) }, icon="users")))
  @sf.menu(menu, from~, title=@sf.t("web-main.preset.label"))
}

///|
/// Preset `id` of station `at` picked for the workspace's new chats ("" none).
fn preset_pick(src : Source, w : Workspace, id : String, at : String) -> () -> Unit {
  fn() { @sfbase.pick_new(src, w.id, { "preset": Json::string(id), "presetStation": Json::string(at) }) }
}

///|
/// Someone else's preset as a menu names it: its name, whose it is after it (the member's name; its name alone where
/// that was not said).
fn preset_whose_label(name : String, whose : String) -> String {
  if whose == "" {
    name
  } else {
    name + " · " + whose
  }
}

///|
/// 其他成员的预设, a level further in from the presets' menu (the presenters' own: a menu a menu's item opens), or a
/// menu of its own where nothing was chosen in one (a fixture's screen): the other members' presets, asked of the core
/// at the press (`otherPresets`, read of the stations reached then) and opened once all of them have answered
/// (`reading` over), whole, the screen as it was meanwhile (press_wait); each by its name, whose it is after it, as the
/// core orders them, the one picked checked; none, one line saying so. Picked, it is the new chat's and the menu
/// closes. What was asked is held while it shows, let go of as it goes or something is picked in it.
fn preset_others_open(src : Source, w : Workspace, v : Json?, from : @sf.Beside) -> Unit {
  let lease = src.lease_topic("otherPresets", { "scope": Json::string(w.id) })
  let let_go = fn() { lease.cancel() }
  let ready = fn() {
    match lease.follow() {
      Some(t) => t.error is Some(_) || (t.value is Some(_) && !flag(t.value, "reading"))
      // (let go of: nothing to wait for)
      None => true
    }
  }
  @sfbase.press_wait(ready, fn() {
    let said = @signals.untracked(fn() { lease.follow() })
    let menu : Array[@sf.MenuItem?] = []
    match said {
      Some({ error: Some(e), .. }) =>
        menu.push(Some(@sf.menu_item_of(error_words(e), fn() {  }, disabled=true)))
      Some({ value, .. }) => {
        let picked = text(v, "preset")
        for p in items(value, "presets") {
          let one = Some(p)
          let id = text(one, "id")
          let at = text(one, "station")
          let pick = preset_pick(src, w, id, at)
          menu.push(
            Some(
              @sf.menu_item_of(
                preset_whose_label(text(one, "name"), text(one, "whose")),
                fn() {
                  let_go()
                  pick()
                },
                chosen=id == picked,
              ),
            ),
          )
        }
        if menu.length() == 0 {
          menu.push(Some(@sf.menu_item_of(@sf.t("web-main.preset.othersNone"), fn() {  }, disabled=true)))
        }
      }
      None => ()
    }
    @sf.menu(menu, from~, title=@sf.t("web-main.preset.others"), gone=let_go)
  }, let_go~)
  |> ignore
}

///|
/// 复制为我的预设, in place of 编辑 for someone else's preset picked: copied into the person's own (`preset.copy`, made on
/// the page's station `address`), the copy picked, and its dialog opened so it can be changed. Not copied, said why
/// and that it can be pressed again.
fn preset_copy_item(src : Source, w : Workspace, address : String, v : Json?) -> @sf.MenuItem {
  let picked = text(v, "preset")
  let stations = items(v, "stations")
  @sf.menu_item_of(@sf.t("web-main.preset.copyMine"), fn() {
    (src.call)("preset.copy", Json::object({ "station": Json::string(address), "id": Json::string(picked) }), fn(r) {
      match r {
        Ok(made) => {
          let id = text(Some(made), "id")
          @sfbase.pick_new(src, w.id, { "preset": Json::string(id), "presetStation": Json::string(address) })
          preset_dialog(src, w, address, id, stations)
        }
        Err(e) => toast_later(@sf.t("web-main.preset.copyFailed", args=[("error", error_words(e))]))
      }
    })
  }, icon="copy")
}

///|
/// Preset `p` as the menu of `all` (the page's `presets`) names it: by its name alone, where it is kept no concern of
/// who picks it (the user, 2026-11-14: 「用户大部分时候不需要知道这个」); its station's name after it only to tell it
/// from another of the same name on another station.
fn preset_menu_label(all : Array[Json], p : Json) -> String {
  let name = text(Some(p), "name")
  let at = text(Some(p), "station")
  let twin = all.iter().any(fn(o) { text(Some(o), "name") == name && text(Some(o), "station") != at })
  if twin {
    name + " · " + text(Some(p), "stationName")
  } else {
    name
  }
}

///|
/// 编辑「X」 of the preset picked (`picked`, of the station the page says, `presetStation`): its dialog, browsing on
/// the composer's station.
fn preset_edit_item(src : Source, w : Workspace, address : String, v : Json?, picked : String) -> @sf.MenuItem {
  let at = text(v, "presetStation")
  @sf.menu_item_of(@sf.t("web-main.preset.editNamed", args=[("name", text(v, "presetName"))]), fn() {
    preset_dialog(src, w, if at == "" { address } else { at }, picked, items(v, "stations"), browse_station=address)
  }, icon="edit")
}

///|
/// What a control the picked preset holds fixed (its model, its station) opens as it is pressed: a menu saying so in
/// its title (`title`), and the two ways to change it, 编辑 the preset (复制为我的预设 for someone else's, never edited
/// here) and 不用预设 (the user, 2026-11-14: a press that did nothing looked broken).
fn preset_fixed_menu(src : Source, w : Workspace, address : String, v : Json?, title : String, from : @sf.Beside) -> Unit {
  let picked = text(v, "preset")
  @sf.menu(
    [
      Some(if preset_picked_own(v) { preset_edit_item(src, w, address, v, picked) } else { preset_copy_item(src, w, address, v) }),
      Some(@sf.menu_item_of(@sf.t("web-main.preset.none"), fn() {
        @sfbase.pick_new(src, w.id, { "preset": Json::string(""), "presetStation": Json::string("") })
      }, icon="close")),
    ],
    from~,
    title~,
  )
}

///|
/// The folders a station offers for a preset and the clones under way there (the `presets` topic's `candidates` and
/// `clones`), read as they are shown. Not the presets: a person's own are the core's `newChat.presets` and `preset`.
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
  auto_station : @signals.Signal[Bool]
  station : @signals.Signal[String]
  stations : @signals.Signal[Array[String]]
  initial_model : @signals.Signal[Json?]
  model_state : @signals.Signal[Int]
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
    auto_station: @signals.signal(false, same=fn(a, b) { a == b }),
    station: @signals.signal("", same=fn(a, b) { a == b }),
    stations: @signals.signal([]),
    initial_model: @signals.signal(None),
    model_state: @signals.signal(0, same=fn(a, b) { a == b }),
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
    fn(v, close) { preset_fields(v, src, w.id, address, id, stations, e, close) },
    from=Unanchored,
    foot=fn(v, close) { preset_foot(v, src, w, address, id, e, close) },
  )
}

///|
/// The preset `id` of workspace `scope` whole, as the core has it (`preset`: the person's own as the device holds it,
/// wherever it was made; None while it is read, where nothing has it, or for a new one).
fn preset_was(src : Source, scope : String, id : String) -> Json? {
  if id == "" {
    return None
  }
  src.topic("preset", preset_asked(scope, id)).get().value
}

///|
/// A folder of a preset as the core says it (`preset`'s `dirs`: each with its station) as the dialog holds it (dir_key):
/// one of `address`'s by its path and repository alone, another station's with its station and that station's name.
fn preset_dir_held(d : Json, address : String) -> Json {
  let one = Some(d)
  let repo = if text(one, "repo") == "" { Json::null() } else { Json::string(text(one, "repo")) }
  if text(one, "station") == "" || text(one, "station") == address {
    Json::object({ "path": Json::string(text(one, "path")), "repo": repo })
  } else {
    Json::object({
      "path": Json::string(text(one, "path")),
      "repo": repo,
      "station": Json::string(text(one, "station")),
      "stationName": Json::string(text(one, "stationName")),
    })
  }
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
  scope : String,
  address : String,
  id : String,
  stations : Array[Json],
  e : PresetEditing,
  close : () -> Unit,
) -> Unit {
  // (one changed: what it is, once the core has said it)
  v.reacts(fn() { !e.filled.get() && preset_was(src, scope, id) is Some(_) }, fn(ready) {
    guard ready else { return }
    guard @signals.untracked(fn() { preset_was(src, scope, id) }) is Some(p) else { return }
    e.filled.set(true)
    e.name.set(text(Some(p), "name"))
    e.instructions.set(text(Some(p), "instructions"))
    e.dirs.set(items(Some(p), "dirs").map(fn(d) { preset_dir_held(d, address) }))
    e.auto_station.set(flag(Some(p), "autoStation"))
    e.station.set(text(Some(p), "station"))
    e.stations.set(items(Some(p), "stations").filter_map(fn(s) { if s is String(str) && str != "" { Some(str) } else { None } }))
    e.initial_model.set(field(Some(p), "model"))
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
    preset_capsules_node(col, src, address, stations, e)
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
        .says(By(fn() { Some(@view.said(Button, label=title())) }))
        |> ignore
        @sf.presses_node(r, p)
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
  let ready = fn() { named() != "" && !e.clones.get().iter().any(fn(k) { clone_failed(src, k) is None }) }
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
      if e.auto_station.untracked() {
        params["autoStation"] = Json::boolean(true)
      } else if e.station.untracked() != "" {
        params["stations"] = Json::array([Json::string(e.station.untracked())])
      } else if e.stations.untracked().length() > 0 {
        params["stations"] = Json::array(e.stations.untracked().map(fn(s) { Json::string(s) }))
      }
      let pick_val = match e.model_state.untracked() {
        2 => {
          let pick_v = @signals.untracked(fn() {
            src.topic("pick", { "station": Json::string(address), "of": Json::string("connect-new:preset") }).get().value
          })
          field(pick_v, "value")
        }
        0 => e.initial_model.untracked()
        _ => None
      }
      if text(pick_val, "model") != "" {
        let pm : Map[String, Json] = { "model": Json::string(text(pick_val, "model")) }
        if text(pick_val, "runtime") != "" {
          pm["runtime"] = Json::string(text(pick_val, "runtime"))
        }
        if text(pick_val, "effort") != "" {
          pm["effort"] = Json::string(text(pick_val, "effort"))
        }
        if text(pick_val, "profile") != "" {
          pm["profile"] = Json::string(text(pick_val, "profile"))
        }
        let p_list = items(pick_val, "profiles")
        if p_list.length() > 0 {
          pm["profiles"] = Json::array(p_list)
        }
        params["model"] = Json::object(pm)
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
/// A folder's mark in the preset's dialog: as high as its two lines, its corner the small block's (the ladder's 10), so
/// with a row's 8 over and under it stands a corner's inset (8) in from the row's round ground on every side, concentric
/// with its 18 (@sf.panel_row_in_node) whether the row has one line or two.
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
/// Station 与模型（可选）：一行双胶囊，支持不限（不选）或指定 Station（单选/多选自动分配）与模型。
fn preset_capsules_node(
  col : @view.View,
  src : Source,
  address : String,
  stations : Array[Json],
  e : PresetEditing,
) -> Unit {
  let has_station = fn() {
    e.auto_station.get() || e.station.get() != "" || e.stations.get().length() > 0
  }
  let station_words = fn() {
    let first_name = match stations.get(0) {
      Some(s) if text(Some(s), "name") != "" => text(Some(s), "name")
      _ => preset_station_name(address, "", stations)
    }
    if e.auto_station.get() {
      if first_name != "" { "自动 · " + first_name } else { "自动分配" }
    } else if e.station.get() != "" {
      let sid = e.station.get()
      match stations.iter().find_first(fn(s) { text(Some(s), "id") == sid || text(Some(s), "station") == sid }) {
        Some(s) if text(Some(s), "name") != "" => text(Some(s), "name")
        _ => sid
      }
    } else if e.stations.get().length() > 0 {
      "\{e.stations.get().length()} 台 station"
    } else {
      "不限 Station"
    }
  }
  let pick_v = fn() {
    src.topic("pick", { "station": Json::string(address), "of": Json::string("connect-new:preset") }).get().value
  }
  let pick_val = fn() {
    match e.model_state.get() {
      2 => field(pick_v(), "value")
      0 => e.initial_model.get()
      _ => None
    }
  }
  let pick_vo = fn() {
    match e.model_state.get() {
      2 => field(pick_v(), "valueOption")
      0 => {
        let mid = text(e.initial_model.get(), "model")
        if mid == "" {
          None
        } else {
          items(pick_v(), "options").iter().find_first(fn(o) { text(Some(o), "model") == mid })
        }
      }
      _ => None
    }
  }
  let has_model = fn() { text(pick_val(), "model") != "" }
  let model_words = fn() {
    if !has_model() {
      "不限模型"
    } else {
      let mname = if text(pick_vo(), "name") != "" { text(pick_vo(), "name") } else { text(pick_val(), "model") }
      let parts = [mname]
      let rt = text(pick_val(), "runtime")
      if !flag(pick_v(), "runtimeFixed") && (flag(pick_v(), "showRuntime") || items(pick_vo(), "runtimes").length() > 1) && rt != "" {
        parts.push(@settings.runtime_short(rt))
      }
      let eff = effort_text(text(pick_val(), "effort"))
      if eff != "" {
        parts.push(eff)
      }
      if e.model_state.get() == 2 {
        let fast = text(pick_v(), "fastText")
        if fast != "" {
          parts.push(fast)
        }
        let acc = text(field(pick_v(), "account"), "text")
        if acc != "" {
          parts.push(acc)
        }
      }
      join(parts, " · ")
    }
  }
  @sf.field_node(col, fn() { "Station 与模型（可选）" }, fn(b) {
    b.box(fn(bar) {
      @sf.style_node(bar, fn() { preset_simple_capsules })
      bar.wraps(Is(Some(8.0))) |> ignore
      preset_capsule_pill(
        bar,
        fn(l) {
          @sf.icon_node(
            l,
            "sliders",
            15.0,
            By(fn() { if has_station() { @sf.theme().p.text } else { @sf.theme().p.muted } }),
          )
          |> ignore
        },
        station_words,
        has_station,
        fn(btn) { preset_station_open(src, address, stations, e, Node(btn)) },
        "清除 Station",
        fn() {
          e.auto_station.set(false)
          e.station.set("")
          e.stations.set([])
        },
      )
      preset_capsule_pill(
        bar,
        fn(l) {
          l.pick(
            fn() {
              if has_model() {
                Some((text(field(pick_vo(), "maker"), "id"), text(pick_val(), "runtime")))
              } else {
                None
              }
            },
            fn(m, picked_maker) {
              match picked_maker {
                Some((maker_id, rt)) => @sf.maker_mark_node(m, maker_id, rt, 14.0) |> ignore
                None => @sf.icon_node(m, "sparks", 15.0, By(fn() { @sf.theme().p.muted })) |> ignore
              }
            },
          )
        },
        model_words,
        has_model,
        fn(btn) {
          let state_was = e.model_state.untracked()
          if state_was != 2 {
            match (state_was, e.initial_model.untracked()) {
              (0, Some(Object(m))) if text(Some(Json::object(m)), "model") != "" => {
                let save_p : Map[String, Json] = {
                  "station": Json::string(address),
                  "of": Json::string("connect-new:preset"),
                  "model": Json::string(text(Some(Json::object(m)), "model")),
                }
                for k in ["runtime", "effort", "profile", "profiles"] {
                  match m.get(k) {
                    Some(v) => save_p[k] = v
                    None => ()
                  }
                }
                (src.call)("pick.save", Json::object(save_p), @sfbase.answer_unread)
              }
              _ =>
                (src.call)(
                  "pick.set",
                  { "station": Json::string(address), "of": Json::string("connect-new:preset"), "clear": Json::boolean(true) },
                  @sfbase.answer_unread,
                )
            }
            e.model_state.set(2)
          }
          let (x, y, w, h) = btn.placed_window_now()
          open_triple_panel(
            src,
            address,
            "connect-new:preset",
            At(x, y, w, h),
            asks=fn(borrow) { borrow_ask(src, address, "connect-new:preset", borrow) },
          )
        },
        "清除模型",
        fn() {
          e.model_state.set(1)
          (src.call)(
            "pick.set",
            { "station": Json::string(address), "of": Json::string("connect-new:preset"), "clear": Json::boolean(true) },
            @sfbase.answer_unread,
          )
        },
      )
    })
    |> ignore
  })
}

///|
fn preset_capsule_pill(
  parent : @view.View,
  lead : (@view.View) -> Unit,
  words : () -> String,
  has_value : () -> Bool,
  on_open : (@view.View) -> Unit,
  clear_label : String,
  on_clear : () -> Unit,
) -> Unit {
  parent.box(fn(pill) {
    @sf.style_node(pill, fn() { preset_capsule_outer })
    pill
    .shrink(Is(1.0))
    .min_width(Is(Some(0.0)))
    .radius(Is(999.0))
    .ground(By(fn() { if has_value() { @sf.theme().p.neutral_bg } else { 0L } }))
    .edge(By(fn() { (1.0, @sf.theme().p.line) }))
    |> ignore
    pill.box(fn(btn) {
      @sf.style_node(btn, fn() { if has_value() { preset_capsule_btn_active } else { preset_capsule_btn } })
      btn
      .shrink(Is(1.0))
      .min_width(Is(Some(0.0)))
      .radius(Is(999.0))
      .ground(By(fn() { if @sf.lit_node(btn) { @sf.theme().p.hover } else { 0L } }))
      .says(By(fn() { Some(@view.said(Button, label=words())) }))
      |> ignore
      @sf.presses_node(btn, fn() { on_open(btn) })
      lead(btn)
      @sf.words_node(btn, words, fn() { if has_value() { new_capsule_words } else { preset_capsule_quiet } })
      .shrink(Is(1.0))
      .min_width(Is(Some(0.0)))
      .cuts(Is(true))
      .allow_ellipsis(Is(true))
      |> ignore
      @sf.icon_node(btn, "chevron-down", new_chevron, By(fn() { @sf.theme().p.muted })) |> ignore
    })
    |> ignore
    pill.show(has_value, fn(c) {
      c.box(fn(x) {
        @sf.style_node(x, fn() { preset_capsule_clear_btn })
        x
        .shrink(Is(0.0))
        .radius(Is(999.0))
        .ground(By(fn() { if @sf.lit_node(x) { @sf.theme().p.hover } else { 0L } }))
        .says(Is(Some(@view.said(Button, label=clear_label))))
        |> ignore
        @sf.presses_node(x, on_clear)
        @sf.icon_node(x, "close", 13.0, By(fn() { @sf.theme().p.muted })) |> ignore
      })
      |> ignore
    })
  })
  |> ignore
}

///|
fn preset_station_id(s : Json) -> String {
  let id = text(Some(s), "id")
  if id != "" { id } else { text(Some(s), "station") }
}

///|
fn preset_station_open(
  _src : Source,
  _address : String,
  stations : Array[Json],
  e : PresetEditing,
  from : @sf.Anchor,
) -> Unit {
  let all_ids = stations.map(preset_station_id).filter(fn(id) { id != "" })
  let current_selected = fn() -> Array[String] {
    if e.auto_station.get() {
      all_ids
    } else if e.station.get() != "" {
      [e.station.get()]
    } else {
      e.stations.get()
    }
  }
  let apply_selected = fn(next : Array[String]) {
    if next.length() == 0 {
      e.auto_station.set(false)
      e.station.set("")
      e.stations.set([])
    } else if next.length() == 1 {
      e.auto_station.set(false)
      e.station.set(next[0])
      e.stations.set([])
    } else if all_ids.length() > 1 && next.length() >= all_ids.length() {
      e.auto_station.set(true)
      e.station.set("")
      e.stations.set([])
    } else {
      e.auto_station.set(false)
      e.station.set("")
      e.stations.set(next)
    }
  }
  let unrestricted = fn() {
    !e.auto_station.get() && e.station.get() == "" && e.stations.get().length() == 0
  }
  let all_checked = fn() {
    e.auto_station.get() || (all_ids.length() > 1 && e.stations.get().length() >= all_ids.length())
  }
  let some_checked = fn() {
    !unrestricted() && !all_checked()
  }
  @sf.panel_nodes(
    @sf.t("android-chat.new.station.pick"),
    fn(n, close) {
      @sf.choice_row_node(
        n,
        fn() { "不限 Station" },
        unrestricted,
        compact=true,
        note=fn() { "保持新对话当前选中的 station" },
        press=fn() {
          apply_selected([])
          close()
        },
      )
      @sf.choice_row_node(
        n,
        fn() { @sf.t("web-main.model.selectAll") },
        fn() { false },
        compact=true,
        lead=fn(l) { @sf.check_mark_node(l, all_checked, mixed=some_checked) },
        note=fn() { "在所有可用 station 间按负载自动分配" },
        press=fn() {
          if all_checked() {
            apply_selected([])
          } else {
            e.auto_station.set(true)
            e.station.set("")
            e.stations.set([])
          }
        },
      )
      for s in stations {
        let sid = preset_station_id(s)
        let sname = preset_station_name(text(Some(s), "station"), text(Some(s), "name"), stations)
        let checked = fn() {
          e.auto_station.get() || e.station.get() == sid || e.stations.get().contains(sid)
        }
        @sf.choice_row_node(
          n,
          fn() { sname },
          fn() { false },
          compact=true,
          lead=fn(l) { @sf.check_mark_node(l, checked) },
          note=fn() { text(Some(s), "summary") },
          press=fn() {
            let cur = @signals.untracked(current_selected)
            if cur.contains(sid) {
              apply_selected(cur.filter(fn(x) { x != sid }))
            } else {
              apply_selected([..cur, sid])
            }
          },
        )
      }
    },
    from~,
  )
}

///|
// kept across runs: a value (no field of it changes)
let preset_simple_capsules : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let preset_capsule_outer : @ui.Style = @ui.css("row align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let preset_capsule_btn : @ui.Style = @ui.css("row min_h=S11 px=S3 gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let preset_capsule_btn_active : @ui.Style = @ui.css("row min_h=S11 pl=S3 pr=S1_5 gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let preset_capsule_clear_btn : @ui.Style = @ui.css("row w=S11 h=S11 align=ACenter justify=JCenter")

///|
/// The control's words while no preset is picked: as quiet as what says what is not chosen.
// kept across runs: a value (no field of it changes)
let preset_capsule_quiet : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false, w=Cut)
