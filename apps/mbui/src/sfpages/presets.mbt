// Presets (docs/presets.md): what a chat starts knowing, chosen on the new chat's page beside where it runs and what it
// runs on (the core's `newChat` view: the station's presets, the one picked and its name; `newChat.pick {preset}`). Its
// control opens a menu of them (不用预设 and each preset, the one picked checked; 编辑 the one picked, 新预设). A preset is
// made or changed in a short dialog, as a key's is: its name, its folders (each a row with its × to let go, 添加目录
// opening a pick of the folders the station found, searched by name, or a path typed), what people want of its chats.

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
    preset_dialog(src, w, address, text(items(v, "presets").get(0), "id"), items(v, "stations"), adding=true)
  }
  if take_asked("preset-new-add") {
    preset_dialog(src, w, address, "", items(v, "stations"), adding=true)
  }
  if (new_capsule(c, "new/preset", label, floating, fn() {
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
    }) &&
    !going) ||
    asked {
    preset_menu(src, w, address, v, picked, @sf.Of(c.id("new/preset")))
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
          preset_dialog(src, w, if at == "" { address } else { at }, picked, items(v, "stations"))
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
  (src.topic)("presets", { "station": Json::string(address) }).value
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
/// A preset being made or changed: its folders (each its path, its repository, the station it is on where that is not
/// the preset's: `station`, `stationName`; what it shows as: `name`, `where`, `icon`), what its name was filled with (the first
/// folder's, until another is typed), whether what it was is in it yet (one changed: once the station's presets are
/// read), being saved, why it was not.
priv struct PresetEditing {
  dirs : Array[Json]
  mut auto : String
  mut filled : Bool
  mut saving : Bool
  mut error : String
  serial : Int
  mut adding : Bool
  /// What the dialog shows, in place of the one before (no sheet over a sheet): its fields (0), the folders to add (1),
  /// a station's folders browsed (2).
  mut step : Int
}

///|
// kept across runs: counted as each opens (its fields' keys); reset puts it back
let preset_serial : Ref[Int] = Ref(0)

///|
/// A preset made (`id` "") or changed (the station's of that id) in a dialog, as short as a key's: its name (the first
/// folder's until one is typed), its folders (a row each: its mark, its name, where it is from, its ×; 添加目录 under
/// them), what people want of its chats; at its foot 删除 for one there, 取消, 创建 or 保存. Made, it is the one picked
/// for the station's new chats.
/// `adding`: 添加目录 asked open as it is first drawn (a fixture's screen of it).
/// `stations`: the workspace's up now (the `newChat` view's), whose folders are offered too.
fn preset_dialog(src : Source, w : Workspace, address : String, id : String, stations : Array[Json], adding? : Bool = false) -> Unit {
  preset_serial.val += 1
  let e : PresetEditing = { dirs: [], auto: "", filled: id == "", saving: false, error: "", serial: preset_serial.val, adding, step: 0 }
  let key = fn(part : String) { "preset-editor/" + e.serial.to_string() + "/" + part }
  let name = field_of(key("name"))
  let instructions = field_of(key("instructions"))
  let was = fn() -> Json? {
    if id == "" {
      return None
    }
    match items(presets_of(src, address), "presets").iter().find_first(fn(p) { text(Some(p), "id") == id }) {
      Some(p) => Some(p)
      None => None
    }
  }
  let title = if id == "" { @sf.t("web-main.preset.new") } else { @sf.t("web-main.preset.edit") }
  open_dialog(
    title,
    live=fn() {
      match e.step {
        1 => (@sf.t("web-main.preset.add"), "", "")
        2 => (@sf.t("web-main.preset.pickFolder"), "", "")
        _ => (title, "", "")
      }
    },
    on_gone=fn() { (@sfbase.folder_browse_close.val)() },
    fn(c, _) {
      let offered = offered_dirs(src, address, stations)
      if e.step == 1 {
        preset_add_step(c, src, address, offered, e, key)
        return
      }
      if e.step == 2 {
        (@sfbase.folder_browse_body.val)(c, src, address)
        return
      }
      // (one changed: what it is, once the station's presets are read)
      if !e.filled {
        match was() {
          Some(p) => {
            e.filled = true
            name.set(text(Some(p), "name"))
            instructions.set(text(Some(p), "instructions"))
            for d in items(Some(p), "dirs") {
              e.dirs.push(d)
            }
          }
          None => ()
        }
      }
      // its name: the first folder's until one is typed
      let auto = match e.dirs.get(0) {
        Some(d) => dir_label(text(Some(d), "path"))
        None => ""
      }
      if id == "" && name.text() == e.auto && auto != e.auto {
        name.set(auto)
        e.auto = auto
      }
      @sf.field(c, @sf.t("web-main.preset.name"), fn() {
        @sf.input(c, key("name"), placeholder=@sf.t("web-main.preset.namePlaceholder"), field=name) |> ignore
      })
      @sf.field(c, @sf.t("web-main.preset.dirs"), hint=if e.dirs.length() == 0 { @sf.t("web-main.preset.dirsHint") } else { "" }, fn() {
        c.box(style=preset_dirs, fn() {
          for d in e.dirs {
            let at = dir_key(Some(d))
            // (what it shows as: as the station offers it, where it does)
            let one = match offered.iter().find_first(fn(o) { dir_key(Some(o)) == at }) {
              Some(x) => Some(x)
              None => Some(d)
            }
            let path = text(one, "path")
            c.box(style=preset_dir_row, fn() {
              repo_mark(c, dir_label(path), text(one, "repo"), text(one, "icon"), preset_dir_mark)
              c.box(style=preset_dir_words, fn() {
                c.text(if text(one, "name") != "" { text(one, "name") } else { dir_label(path) }, style=preset_dir_name) |> ignore
                c.text(dir_note(one, false), style=preset_dir_note) |> ignore
              })
              |> ignore
              if @sf.icon_button(c, "close", key=key("drop/" + at), size=preset_dir_x, label=@sf.t("web-main.preset.remove")) {
                e.dirs.retain(fn(x) { dir_key(Some(x)) != at })
              }
            })
            |> ignore
          }
          if @sf.button(c, @sf.t("web-main.preset.add"), key=key("add"), tone=Ghost, icon="plus") || (e.adding && e.filled) {
            e.adding = false
            field_of(key("q")).set("")
            e.step = 1
          }
        })
        |> ignore
      })
      // (why it was not saved under it: a folder the station has not, say)
      @sf.field(c, @sf.t("web-main.preset.instructions"), hint=@sf.t("web-main.preset.instructionsHint"), error=e.error, fn() {
        @sf.textarea(c, key("instructions"), rows=3, placeholder=@sf.t("web-main.preset.instructionsPlaceholder"), field=instructions)
        |> ignore
      })
    },
    fn(c, shut) {
      // (the folders to add, or a station's browsed: back to what was before, or this folder taken)
      if e.step == 1 {
        c.spacer()
        if @sf.button(c, @sf.t("common.back"), key=key("back"), tone=Ghost) {
          e.step = 0
        }
        return
      }
      if e.step == 2 {
        c.spacer()
        if @sf.button(c, @sf.t("common.back"), key=key("back2"), tone=Ghost) {
          (@sfbase.folder_browse_close.val)()
          e.step = 1
        }
        let here = (@sfbase.folder_browse_here.val)()
        if @sf.button(c, @sf.t("web-main.preset.useFolder"), key=key("use"), tone=Primary, disabled=here == "") {
          let d = Json::object({ "path": Json::string(here) })
          if !e.dirs.iter().any(fn(x) { dir_key(Some(x)) == dir_key(Some(d)) }) {
            e.dirs.push(d)
          }
          (@sfbase.folder_browse_close.val)()
          e.step = 0
        }
        return
      }
      if id != "" {
        if @sf.button(c, @sf.t("common.delete"), key=key("delete"), tone=GhostDanger) {
          confirm(
            @sf.t("web-main.preset.deleteTitle", args=[("name", name.text())]),
            @sf.t("web-main.preset.deleteBody"),
            @sf.t("common.delete"),
            danger=true,
            fn() {
              shut()
              (src.call)("preset.delete", Json::object({ "station": Json::string(address), "id": Json::string(id) }), fn(_) {  })
            },
          )
        }
      }
      c.spacer()
      if @sf.button(c, @sf.t("common.cancel"), key=key("cancel"), tone=Ghost) {
        c.blur()
        shut()
      }
      let ready = e.dirs.length() > 0 && name.text().trim(chars=" \n").to_owned() != ""
      let go = if id == "" { @sf.t("web-main.preset.create") } else { @sf.t("common.save") }
      if @sf.button(c, go, key=key("save"), tone=Primary, busy=e.saving, disabled=!ready) {
        e.saving = true
        e.error = ""
        c.blur()
        let params : Map[String, Json] = {
          "station": Json::string(address),
          "name": Json::string(name.text().trim(chars=" \n").to_owned()),
          // (this station's by their paths; another's as it was read there, with its station)
          "dirs": Json::array(
            e.dirs.map(fn(d) {
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
          "instructions": Json::string(instructions.text()),
        }
        if id != "" {
          params["id"] = Json::string(id)
        }
        (src.call)(if id == "" { "preset.add" } else { "preset.put" }, Json::object(params), fn(r) {
          e.saving = false
          match r {
            Ok(made) => {
              // made: the one the station's new chats are opened with
              if id == "" {
                @sfbase.pick_new(src, w.id, { "preset": Json::string(text(Some(made), "id")) })
              }
              shut()
            }
            Err(err) => e.error = text(Some(err), "message")
          }
        })
      }
    },
  )
}

///|
/// 添加目录, in the dialog in place of its fields: a line to find one by name, then the folders the workspace's stations
/// found and not in the preset yet, as they come (each station's said as it is; those read before shown meanwhile),
/// those their chats worked in first, each where it is, on which station where it is not the preset's, how many chats
/// used it; last 浏览文件夹, the preset's station's folders browsed there too, whatever was found. One picked, the
/// fields again with it among the folders.
fn preset_add_step(c : @ui.Ctx, src : Source, address : String, offered : Array[Json], e : PresetEditing, key : (String) -> String) -> Unit {
  let has = fn(k : String) { e.dirs.iter().any(fn(d) { dir_key(Some(d)) == k }) }
  let q = @sf.input(c, key("q"), placeholder=@sf.t("web-main.preset.search"), field=field_of(key("q"))).text.trim(chars=" ").to_owned().to_lower()
  c.box(style=preset_offered, fn() {
    for o in offered {
      let one = Some(o)
      let k = dir_key(one)
      let (name, repo, icon) = (text(one, "name"), text(one, "repo"), text(one, "icon"))
      if has(k) || (q != "" && !name.to_lower().contains(q) && !repo.to_lower().contains(q) && !text(one, "where").to_lower().contains(q)) {
        continue
      }
      // (as it will stand among the preset's folders once taken: its mark, its name over where it is)
      let id = c.id(key("offer/" + k))
      let b = c.box(style=preset_offer_row, id~, fn() {
        repo_mark(c, name, repo, icon, preset_dir_mark)
        c.box(style=preset_dir_words, fn() {
          c.text(name, style=preset_dir_name) |> ignore
          c.text(dir_note(one, true), style=preset_dir_note) |> ignore
        })
        |> ignore
      })
      c.semantics(b, Button, id~, label=name)
      if c.clicked(id) {
        e.dirs.push(o)
        e.step = 0
      }
    }
    // (last, its folder where the others' marks stand)
    let id = c.id(key("browse"))
    let b = c.box(style=preset_browse_row, id~, fn() {
      // (a tile as the folders' marks are, the folder in it)
      let m = preset_dir_mark
      let tile = preset_browse_mark.then(@ui.style(w=Fixed(m), h=Fixed(m), radius=@sf.agent_mark_corner(m), bg=Data(@sf.theme().p.neutral_bg)))
      c.box(style=tile, fn() { @sf.icon(c, "folder", size=preset_browse_icon, color=@sf.theme().p.muted) |> ignore }) |> ignore
      c.text(@sf.t("web-main.preset.browse"), style=preset_dir_name) |> ignore
    })
    c.semantics(b, Button, id~, label=@sf.t("web-main.preset.browse"))
    if c.clicked(id) {
      (@sfbase.folder_browse_open.val)(address)
      e.step = 2
    }
  })
  |> ignore
}

///|
/// A folder by where it is: its station ("" the preset's own) and its path.
fn dir_key(d : Json?) -> String {
  text(d, "station") + "\n" + text(d, "path")
}

///|
/// The folders the workspace's stations offer (each one's `presets` topic, read as it is shown): the preset's
/// station's first, then the others', each marked with its station; a repository once (where it is on the preset's
/// station, else on the first that has it), as its chats find it by its address on whichever station they run.
fn offered_dirs(src : Source, address : String, stations : Array[Json]) -> Array[Json] {
  let out : Array[Json] = []
  let repos : Map[String, Bool] = {}
  let take = fn(at : String, station_name : String) {
    for o in items(presets_of(src, at), "candidates") {
      let repo = text(Some(o), "repo")
      if repo != "" && repos.contains(repo) {
        continue
      }
      if repo != "" {
        repos[repo] = true
      }
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
/// What a folder says under its name: where it is (and on which station, where it is not the preset's), how many chats
/// worked in it (`chats`: where it is offered).
fn dir_note(o : Json?, chats : Bool) -> String {
  let n = count(o, "chats")
  let at = if text(o, "where") != "" { text(o, "where") } else if text(o, "repo") != "" { text(o, "repo") } else { text(o, "path") }
  let parts = [
    at,
    text(o, "stationName"),
    if chats && n > 0 { @sf.t("web-main.preset.chats", args=[("n", n.to_string())]) } else { "" },
  ]
  join(parts.filter(fn(x) { x != "" }), " · ")
}

///|
/// A folder's mark: its own picture where the station found one, else its first letter on its repository's colour.
fn repo_mark(c : @ui.Ctx, name : String, repo : String, icon : String, size : Double) -> Unit {
  @sf.tile_avatar(c, if repo != "" { repo } else { name }, name, icon, size)
}

///|
/// A folder's mark in the preset's dialog: about as high as its two lines, its corner (a tile's, .3 of it) the
/// ladder's 10, so a ground round it 10 out is the ladder's 18 (preset_offer_row).
let preset_dir_mark : Double = 34.0


///|
/// The picked preset's folders' marks, side by side in its control.
// kept across runs: a value (no field of it changes)
let preset_marks_row : @ui.Style = @ui.css("row gap=S0_5 align=ACenter")

///|
/// The folders offered to add, a row each.
// kept across runs: a value (no field of it changes)
let preset_offered : @ui.Style = @ui.css("w=Full gap=S0_5")

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

///|
/// The preset's folders, then 添加目录, straight under the field's label.
// kept across runs: a value (no field of it changes)
let preset_dirs : @ui.Style = @ui.css("w=Full gap=S1 align=AStart")

///|
/// A folder offered to add, pressed whole: as a folder of the preset stands (preset_dir_row), its ground under the
/// hand rounded about its mark 10 from it each way (its two lines 4 higher than the mark: 8 over and under them),
/// concentric with it (the ladder's 18).
// kept across runs: a value (no field of it changes)
let preset_offer_row : @ui.Style = @ui.css("row w=Full px=S2_5 py=S2 gap=S3 align=ACenter radius=Around hovered{bg=Hover}")

///|
/// 浏览文件夹's row: one line, as high as its mark, so 10 over and under it as at its start.
// kept across runs: a value (no field of it changes)
let preset_browse_row : @ui.Style = @ui.css("row w=Full p=S2_5 gap=S3 align=ACenter radius=Around hovered{bg=Hover}")

///|
/// 浏览文件夹's folder, in a mark's room.
// kept across runs: a value (no field of it changes)
let preset_browse_mark : @ui.Style = @ui.css("align=ACenter justify=JCenter")

///|
let preset_browse_icon : Double = 20.0

///|
/// A folder of the preset: its mark, its name over where it is from, its × at its end.
// kept across runs: a value (no field of it changes)
let preset_dir_row : @ui.Style = @ui.css("row w=Full py=S1 gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let preset_dir_words : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let preset_dir_name : @ui.TextStyle = @ui.text_style(size=Body, leading=L6, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let preset_dir_note : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false, w=Cut)

///|
/// A folder's ×: as high as its name's line and a half.
let preset_dir_x : Double = 28.0
