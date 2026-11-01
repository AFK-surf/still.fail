// Presets (docs/presets.md): what a chat starts knowing, chosen on the new chat's page beside where it runs and what it
// runs on (the core's `presets` topic of the station, the one picked in its `newChat` view's `preset`; `newChat.pick
// {preset}`). Its control opens the station's presets to pick from (none, each with its directories), 新预设 at their
// foot; a preset made or changed in a dialog whose most of it is its directories: those the station's chats worked in
// offered first, a tap each, a path typed or pasted for the rest, its name from the first of them until one is typed.

///|
/// What a new chat is opened with (the presets' Chooser, beside the station's): its mark, the preset's name (预设 while
/// none is picked), a chevron; pressed, the station's presets through the presenters.
fn new_preset_control(c : @ui.Ctx, src : Source, w : Workspace, v : Json?, station : Json?, floating : Bool, going : Bool) -> Unit {
  let address = text(station, "station")
  if address == "" || c.in_bones() {
    return
  }
  let t = @sf.theme()
  let picked = text(v, "preset")
  // (its name as the core says it with the page: the station's presets read only as they are opened)
  let name = if picked == "" { "" } else { text(v, "presetName") }
  let label = if name == "" { @sf.t("web-main.preset.label") } else { name }
  let asked = take_asked("preset")
  if take_asked("preset-new") {
    preset_dialog(src, w, address, None)
  }
  if take_asked("preset-edit") {
    preset_dialog(src, w, address, items(presets_of(src, address), "presets").get(0))
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
    @sf.panel(
      @sf.t("web-main.preset.pick"),
      fn(c, close) { preset_rows(c, src, w, address, presets_of(src, address), picked, close) },
      from=Of(c.id("new/preset")),
      foot=fn(c, close) { preset_rows_foot(c, src, w, address, close) },
    )
  }
}

///|
/// The station's presets and the folders offered for a new one (the `presets` topic), read as they are shown.
fn presets_of(src : Source, address : String) -> Json? {
  (src.topic)("presets", { "station": Json::string(address) }).value
}

///|
/// The station's presets to pick from, as a pick's choices are (@sf.choice_row): 不用预设 first, each preset its name
/// over its folders, the one picked checked, its 编辑 at its end; 新预设 at the panel's foot.
fn preset_rows(c : @ui.Ctx, src : Source, w : Workspace, address : String, listed : Json?, picked : String, close : () -> Unit) -> Unit {
  if @sf.choice_row(c, "pick-preset/", picked == "", @sf.t("web-main.preset.none"), note=@sf.t("web-main.preset.noneNote")) {
    @sfbase.pick_new(src, w.id, { "preset": Json::string("") })
    close()
  }
  for x in items(listed, "presets") {
    let one = Some(x)
    let id = text(one, "id")
    let dirs = items(one, "dirs").map(fn(d) { dir_label(Some(d)) })
    let chosen = @sf.choice_row(c, "pick-preset/" + id, id == picked, text(one, "name"), note=join(dirs, " · "), trail=fn() {
      // (as high as its name's line, so its note stands under its name as the others' do: its press reaches round it,
      // in the row's room)
      if @sf.icon_button(c, "edit", key="pick-preset-edit/" + id, size=preset_edit_side, label=@sf.t("web-main.preset.edit")) {
        close()
        preset_dialog(src, w, address, one)
      }
    })
    if chosen {
      @sfbase.pick_new(src, w.id, { "preset": Json::string(id) })
      close()
    }
  }
}

///|
/// The picker's foot: 新预设, the dialog that makes one.
fn preset_rows_foot(c : @ui.Ctx, src : Source, w : Workspace, address : String, close : () -> Unit) -> Unit {
  c.spacer()
  if @sf.button(c, @sf.t("web-main.preset.new"), key="pick-preset-new", icon="plus") {
    close()
    preset_dialog(src, w, address, None)
  }
}

///|
/// A directory as a preset's line says it: its folder's name.
fn dir_label(d : Json?) -> String {
  let path = text(d, "path")
  match path.rev_find("/") {
    Some(i) if i + 1 < path.length() => path.unsafe_substring(start=i + 1, end=path.length())
    _ => path
  }
}

///|
/// A preset being made or changed: the directories in it (their paths, as picked), whether its name was typed (else it
/// is the first directory's), being saved, why it was not.
priv struct PresetEditing {
  dirs : Array[String]
  mut auto : String
  mut saving : Bool
  mut error : String
  serial : Int
}

///|
// kept across runs: counted as each opens (its fields' keys); reset puts it back
let preset_serial : Ref[Int] = Ref(0)

///|
/// A preset made (`was` None) or changed in a dialog: its directories first (those picked, each its × to let go; a line
/// to find one among those offered or to type or paste a path; what is offered, a tap each: the station's repositories
/// its chats worked in most first), its name (the first directory's until one is typed), what people want of its chats;
/// at its foot 删除 for one there, 取消, 创建 or 保存. Made, it is the one picked for the station's new chats.
fn preset_dialog(src : Source, w : Workspace, address : String, was : Json?) -> Unit {
  preset_serial.val += 1
  let e : PresetEditing = { dirs: items(was, "dirs").map(fn(d) { text(Some(d), "path") }), auto: "", saving: false, error: "", serial: preset_serial.val }
  let key = fn(part : String) { "preset-editor/" + e.serial.to_string() + "/" + part }
  let name = field_of(key("name"))
  let instructions = field_of(key("instructions"))
  match was {
    Some(_) => {
      name.set(text(was, "name"))
      instructions.set(text(was, "instructions"))
    }
    None => ()
  }
  let title = match was {
    None => @sf.t("web-main.preset.new")
    Some(_) => @sf.t("web-main.preset.edit")
  }
  open_dialog(
    title,
    fn(c, _) {
      // (what the station offers, as it is read now)
      let offered = items(presets_of(src, address), "candidates")
      // its folders: a line to find one or to paste a path, then those picked (ticked) and the rest offered, a tick each
      @sf.field(c, @sf.t("web-main.preset.dirs"), fn() {
        let q = @sf.input(c, key("q"), placeholder=@sf.t("web-main.preset.search"), field=field_of(key("q"))).text.trim(chars=" \n").to_owned()
        let typed = q.has_prefix("/") || q.has_prefix("~")
        let found = fn(o : Json) {
          let one = Some(o)
          q == "" || typed || text(one, "name").to_lower().contains(q.to_lower()) || text(one, "repo").to_lower().contains(q.to_lower())
        }
        let rest = offered.filter(fn(o) { !e.dirs.contains(text(Some(o), "path")) && found(o) })
        // (with nothing typed, the first of the rest: the others found by their name)
        let shown = if q == "" && rest.length() > preset_offered_most { rest[:preset_offered_most].to_owned() } else { rest }
        let tick = fn(path : String, label : String, note : String) {
          let on = e.dirs.contains(path)
          if @sf.check_row(c, key("dir/" + path), label, on, note~) != on {
            if on {
              e.dirs.retain(fn(x) { x != path })
            } else {
              e.dirs.push(path)
            }
          }
        }
        c.box(style=preset_offered, fn() {
          if typed && !e.dirs.contains(q) {
            tick(q, @sf.t("web-main.preset.addPath", args=[("path", q)]), "")
          }
          for path in e.dirs {
            match offered.iter().find_first(fn(o) { text(Some(o), "path") == path }) {
              Some(o) => tick(path, text(Some(o), "name"), offer_note(Some(o)))
              None => tick(path, dir_label(Some(Json::object({ "path": Json::string(path) }))), path)
            }
          }
          for o in shown {
            tick(text(Some(o), "path"), text(Some(o), "name"), offer_note(Some(o)))
          }
          if shown.length() < rest.length() {
            c.text(@sf.t("web-main.preset.more", args=[("n", (rest.length() - shown.length()).to_string())]), style=preset_row_sub) |> ignore
          }
          if offered.length() == 0 && e.dirs.length() == 0 && !typed {
            c.text(@sf.t("web-main.preset.empty"), style=preset_row_sub) |> ignore
          }
        })
        |> ignore
      })
      // its name: the first directory's until one is typed
      let auto = match e.dirs.get(0) {
        Some(d) => dir_label(Some(Json::object({ "path": Json::string(d) })))
        None => ""
      }
      if was is None && name.text() == e.auto && auto != e.auto {
        name.set(auto)
        e.auto = auto
      }
      @sf.field(c, @sf.t("web-main.preset.name"), fn() {
        @sf.input(c, key("name"), field=name) |> ignore
      })
      // (why it was not saved under it: a directory the station has not, say)
      @sf.field(c, @sf.t("web-main.preset.instructions"), hint=@sf.t("web-main.preset.instructionsHint"), error=e.error, fn() {
        @sf.textarea(c, key("instructions"), rows=3, field=instructions) |> ignore
      })
    },
    fn(c, shut) {
      match was {
        Some(x) => {
          let id = text(Some(x), "id")
          if @sf.button(c, @sf.t("common.delete"), key=key("delete"), tone=GhostDanger) {
            confirm(
              @sf.t("web-main.preset.deleteTitle", args=[("name", text(Some(x), "name"))]),
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
        None => ()
      }
      c.spacer()
      if @sf.button(c, @sf.t("common.cancel"), key=key("cancel"), tone=Ghost) {
        c.blur()
        shut()
      }
      let ready = e.dirs.length() > 0 && name.text().trim(chars=" \n").to_owned() != ""
      let go = match was {
        None => @sf.t("web-main.preset.create")
        Some(_) => @sf.t("common.save")
      }
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
        let op = match was {
          None => "preset.add"
          Some(x) => {
            params["id"] = Json::string(text(Some(x), "id"))
            "preset.put"
          }
        }
        (src.call)(op, Json::object(params), fn(r) {
          e.saving = false
          match r {
            Ok(made) => {
              // made: the one the station's new chats are opened with
              if was is None {
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
/// What an offered folder's row says under its name: the repository it is a clone of, how many chats worked in it.
fn offer_note(o : Json?) -> String {
  let chats = count(o, "chats")
  let parts = [text(o, "repo"), if chats > 0 { @sf.t("web-main.preset.chats", args=[("n", chats.to_string())]) } else { "" }]
  join(parts.filter(fn(x) { x != "" }), " · ")
}

///|
/// What is under a row's name: its directories, where a repository is from and how many chats worked in it.
// kept across runs: a value (no field of it changes)
let preset_row_sub : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false, w=Cut)

///|
/// How many folders are offered with nothing typed.
let preset_offered_most : Int = 8

///|
/// Short of room, the preset's words go with the first of the model's parts (model_triple.mbt triple_drop_name: who
/// runs it by name, later in the row, goes before them), before the station's name.
let preset_drop_words : Int = 1

///|
/// The control's words while no preset is picked: as quiet as what says what is not chosen.
// kept across runs: a value (no field of it changes)
let preset_capsule_quiet : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false, w=Cut)

///|
/// The folders' tick rows, straight on the dialog, out past its words by a row's own room (as accounts.mbt
/// pf_spread_rows: each box under the field's label, not indented past it).
// kept across runs: a value (no field of it changes)
let preset_offered : @ui.Style = @sf.outset_start(@sf.row_corner)

///|
/// A preset's 编辑 in its row: as high as the row's name's line.
let preset_edit_side : Double = 24.0
