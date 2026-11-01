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
    )
  }
}

///|
/// The station's presets and the folders offered for a new one (the `presets` topic), read as they are shown.
fn presets_of(src : Source, address : String) -> Json? {
  (src.topic)("presets", { "station": Json::string(address) }).value
}

///|
/// The station's presets to pick from (as station_rows): 不用预设 first, each preset its name over its directories and
/// a check on the one picked, its edit at its end; 新预设 at their foot.
fn preset_rows(c : @ui.Ctx, src : Source, w : Workspace, address : String, listed : Json?, picked : String, close : () -> Unit) -> Unit {
  let p = @sf.theme().p
  let row = fn(key : String, icon : String, name : String, sub : String, on : Bool, chosen : () -> Unit, edit : (() -> Unit)?) {
    let id = c.id("pick-preset/" + key)
    if c.clicked(id) {
      chosen()
    }
    let b = c.box(style=station_row.then(@sf.panel_row_in()), id~, fn() {
      c.box(style=station_row_mark_box, fn() { @sf.icon(c, icon, size=new_mark, color=p.text) |> ignore }) |> ignore
      c.box(style=station_row_words, fn() {
        c.box(style=station_row_head, fn() {
          c.text(name, style=station_row_name) |> ignore
          if on {
            @sf.icon(c, "check", size=new_mark, color=p.accent) |> ignore
          }
        })
        |> ignore
        if sub != "" {
          c.text(sub, style=preset_row_sub) |> ignore
        }
      })
      |> ignore
      match edit {
        Some(f) =>
          if @sf.icon_button(c, "edit", key="pick-preset-edit/" + key, size=28.0, label=@sf.t("web-main.preset.edit")) {
            f()
          }
        None => ()
      }
      @sf.press_ripple(c, id, @sf.row_corner)
    })
    c.semantics(b, Button, id~, label=name, check=if on { On } else { Off })
  }
  row("", "minus", @sf.t("web-main.preset.none"), @sf.t("web-main.preset.noneNote"), picked == "", fn() {
    @sfbase.pick_new(src, w.id, { "preset": Json::string("") })
    close()
  }, None)
  for x in items(listed, "presets") {
    let one = Some(x)
    let id = text(one, "id")
    let dirs = items(one, "dirs").map(fn(d) { dir_label(Some(d)) })
    row(id, "boxes", text(one, "name"), join(dirs, " · "), id == picked, fn() {
      @sfbase.pick_new(src, w.id, { "preset": Json::string(id) })
      close()
    }, Some(fn() {
      close()
      preset_dialog(src, w, address, one)
    }))
  }
  row("+new", "plus", @sf.t("web-main.preset.newRow"), "", false, fn() {
    close()
    preset_dialog(src, w, address, None)
  }, None)
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
      let p = @sf.theme().p
      // (what the station offers, as it is read now)
      let offered = items(presets_of(src, address), "candidates")
      // its directories, then what can be added
      @sf.field(c, @sf.t("web-main.preset.dirs"), fn() {
        if e.dirs.length() > 0 {
          c.box(style=preset_chips, flow=true, line_gap=6.0, fn() {
            for path in e.dirs {
              let at = path
              if @sf.chip(c, dir_label(Some(Json::object({ "path": Json::string(at) }))), key=key("dir/" + at), icon="close", inner=true) {
                e.dirs.retain(fn(x) { x != at })
              }
            }
          })
          |> ignore
        }
        let q = @sf.input(c, key("q"), placeholder=@sf.t("web-main.preset.search"), field=field_of(key("q"))).text.trim(chars=" \n").to_owned()
        let typed = q.has_prefix("/") || q.has_prefix("~")
        let matching = offered.filter(fn(o) {
          let one = Some(o)
          q == "" ||
          typed ||
          text(one, "name").to_lower().contains(q.to_lower()) ||
          text(one, "repo").to_lower().contains(q.to_lower())
        })
        // (with nothing typed, the first of them: the rest found by their name)
        let shown = if q == "" && matching.length() > preset_offered_most { matching[:preset_offered_most].to_owned() } else { matching }
        c.box(style=preset_offered, fn() {
          if typed && !e.dirs.contains(q) {
            let id = c.id(key("typed"))
            if c.clicked(id) {
              e.dirs.push(q)
              field_of(key("q")).set("")
            }
            let b = c.box(style=station_row.then(@sf.panel_row_in()), id~, fn() {
              c.box(style=station_row_mark_box, fn() { @sf.icon(c, "folder-plus", size=new_mark, color=p.text) |> ignore }) |> ignore
              c.text(@sf.t("web-main.preset.addPath", args=[("path", q)]), style=station_row_name) |> ignore
              @sf.press_ripple(c, id, @sf.row_corner)
            })
            c.semantics(b, Button, id~, label=q)
          }
          for o in shown {
            let one = Some(o)
            let path = text(one, "path")
            let on = e.dirs.contains(path)
            let id = c.id(key("offer/" + path))
            if c.clicked(id) {
              if on {
                e.dirs.retain(fn(x) { x != path })
              } else {
                e.dirs.push(path)
              }
            }
            let chats = count(one, "chats")
            let sub = [text(one, "repo"), if chats > 0 { @sf.t("web-main.preset.chats", args=[("n", chats.to_string())]) } else { "" }].filter(fn(s) { s != "" })
            let b = c.box(style=station_row.then(@sf.panel_row_in()), id~, fn() {
              c.box(style=station_row_mark_box, fn() { @sf.icon(c, if text(one, "repo") != "" { "file-code" } else { "folder" }, size=new_mark, color=p.text) |> ignore }) |> ignore
              c.box(style=station_row_words, fn() {
                c.box(style=station_row_head, fn() {
                  c.text(text(one, "name"), style=station_row_name) |> ignore
                  @sf.icon(c, if on { "check" } else { "plus" }, size=new_mark, color=if on { p.accent } else { p.muted }) |> ignore
                })
                |> ignore
                c.text(join(sub, " · "), style=preset_row_sub) |> ignore
              })
              |> ignore
              @sf.press_ripple(c, id, @sf.row_corner)
            })
            c.semantics(b, Button, id~, label=text(one, "name"), check=if on { On } else { Off })
          }
          if shown.length() < matching.length() {
            c.text(@sf.t("web-main.preset.more", args=[("n", (matching.length() - shown.length()).to_string())]), style=preset_row_sub) |> ignore
          }
          if offered.length() == 0 && !typed {
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
/// The directories picked, a chip each, wrapping.
// kept across runs: a value (no field of it changes)
let preset_chips : @ui.Style = @ui.css("row w=Full gap=S1_5")

///|
/// What is offered to add, under the line to find it: as tall as some rows, scrolled past that.
// kept across runs: a value (no field of it changes)
let preset_offered : @ui.Style = @ui.css("w=Full gap=S0_5")
