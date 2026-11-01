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
    preset_dialog(src, w, address, "")
  }
  if take_asked("preset-edit") {
    preset_dialog(src, w, address, text(items(v, "presets").get(0), "id"))
  }
  if take_asked("preset-add") {
    preset_dialog(src, w, address, text(items(v, "presets").get(0), "id"), adding=true)
  }
  if (new_capsule(c, "new/preset", label, floating, fn() {
      @sf.icon(c, "boxes", size=new_mark, color=if name == "" { t.p.muted } else { t.p.text }) |> ignore
      // (its words left out first, short of room: its mark says what it is, the station's name and the model's matter more)
      c.box(style=new_station_name, drop=preset_drop_words, fn() {
        c.text(label, style=if name == "" { preset_capsule_quiet } else { new_capsule_words }) |> ignore
      })
      |> ignore
      @sf.icon(c, "chevron-down", size=new_chevron, color=t.p.muted) |> ignore
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
  let pick = fn(id : String) { fn() { @sfbase.pick_new(src, w.id, { "preset": Json::string(id) }) } }
  let menu : Array[@sf.MenuItem?] = [Some(@sf.menu_item_of(@sf.t("web-main.preset.none"), pick(""), chosen=picked == ""))]
  for p in items(v, "presets") {
    let id = text(Some(p), "id")
    menu.push(Some(@sf.menu_item_of(text(Some(p), "name"), pick(id), chosen=id == picked)))
  }
  menu.push(None)
  if picked != "" {
    menu.push(
      Some(
        @sf.menu_item_of(@sf.t("web-main.preset.editNamed", args=[("name", text(v, "presetName"))]), fn() { preset_dialog(src, w, address, picked) }, icon="edit"),
      ),
    )
  }
  menu.push(Some(@sf.menu_item_of(@sf.t("web-main.preset.newRow"), fn() { preset_dialog(src, w, address, "") }, icon="plus")))
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
/// A preset being made or changed: its folders (their paths, as picked), what its name was filled with (the first
/// folder's, until another is typed), whether what it was is in it yet (one changed: once the station's presets are
/// read), being saved, why it was not.
priv struct PresetEditing {
  dirs : Array[String]
  mut auto : String
  mut filled : Bool
  mut saving : Bool
  mut error : String
  serial : Int
  mut adding : Bool
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
fn preset_dialog(src : Source, w : Workspace, address : String, id : String, adding? : Bool = false) -> Unit {
  preset_serial.val += 1
  let e : PresetEditing = { dirs: [], auto: "", filled: id == "", saving: false, error: "", serial: preset_serial.val, adding }
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
  open_dialog(
    if id == "" {
      @sf.t("web-main.preset.new")
    } else {
      @sf.t("web-main.preset.edit")
    },
    fn(c, _) {
      let offered = items(presets_of(src, address), "candidates")
      // (one changed: what it is, once the station's presets are read)
      if !e.filled {
        match was() {
          Some(p) => {
            e.filled = true
            name.set(text(Some(p), "name"))
            instructions.set(text(Some(p), "instructions"))
            for d in items(Some(p), "dirs") {
              e.dirs.push(text(Some(d), "path"))
            }
          }
          None => ()
        }
      }
      // its name: the first folder's until one is typed
      let auto = match e.dirs.get(0) {
        Some(d) => dir_label(d)
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
          for path in e.dirs {
            let at = path
            let one = match offered.iter().find_first(fn(o) { text(Some(o), "path") == at }) {
              Some(x) => Some(x)
              None => None
            }
            c.box(style=preset_dir_row, fn() {
              @sf.icon(c, if text(one, "repo") != "" { "file-code" } else { "folder" }, size=16.0, color=@sf.theme().p.muted) |> ignore
              c.box(style=preset_dir_words, fn() {
                c.text(dir_label(at), style=preset_dir_name) |> ignore
                c.text(if text(one, "repo") != "" { text(one, "repo") } else { at }, style=preset_dir_note) |> ignore
              })
              |> ignore
              if @sf.icon_button(c, "close", key=key("drop/" + at), size=preset_dir_x, label=@sf.t("web-main.preset.remove")) {
                e.dirs.retain(fn(x) { x != at })
              }
            })
            |> ignore
          }
          if @sf.button(c, @sf.t("web-main.preset.add"), key=key("add"), tone=Ghost, icon="plus") || (e.adding && e.filled) {
            e.adding = false
            preset_add_pick(offered, e, @sf.Of(c.id(key("add"))))
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
          "dirs": Json::array(e.dirs.map(Json::string)),
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
/// 添加目录: the folders the station found and not in the preset yet, a pick searched by name (those its chats worked in
/// first, each where it is from and how many chats used it), and 输入路径 for one it did not find.
fn preset_add_pick(offered : Array[Json], e : PresetEditing, from : @sf.Beside) -> Unit {
  let choices = offered
    .filter(fn(o) { !e.dirs.contains(text(Some(o), "path")) })
    .map(fn(o) {
      let one = Some(o)
      @sf.choice(text(one, "path"), text(one, "name"), note=offer_note(one), icon=if text(one, "repo") != "" { "file-code" } else { "folder" })
    })
  choices.push(@sf.choice("+path", @sf.t("web-main.preset.typePath"), icon="edit"))
  @sf.pick(@sf.t("web-main.preset.add"), choices, "", fn(path) {
    if path == "+path" {
      @sf.ask(@sf.t("web-main.preset.typePath"), @sf.t("web-main.preset.addShort"), fn(typed) {
        if typed != "" && !e.dirs.contains(typed) {
          e.dirs.push(typed)
        }
      }, placeholder="~/code/app")
    } else if !e.dirs.contains(path) {
      e.dirs.push(path)
    }
  }, from~)
}

///|
/// What an offered folder says under its name: the repository it is a clone of, how many chats worked in it.
fn offer_note(o : Json?) -> String {
  let chats = count(o, "chats")
  let parts = [text(o, "repo"), if chats > 0 { @sf.t("web-main.preset.chats", args=[("n", chats.to_string())]) } else { "" }]
  join(parts.filter(fn(x) { x != "" }), " · ")
}

///|
/// Short of room, the preset's words go with the first of the model's parts (model_triple.mbt triple_drop_name: who
/// runs it by name, later in the row, goes before them), before the station's name.
let preset_drop_words : Int = 1

///|
/// The control's words while no preset is picked: as quiet as what says what is not chosen.
// kept across runs: a value (no field of it changes)
let preset_capsule_quiet : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false, w=Cut)

///|
/// The preset's folders, then 添加目录, straight under the field's label.
// kept across runs: a value (no field of it changes)
let preset_dirs : @ui.Style = @ui.css("w=Full gap=S1 align=AStart")

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
