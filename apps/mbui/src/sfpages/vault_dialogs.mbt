// The desktop's 密钥's dialogs (web/src/VaultAdd.tsx AddKinds, cloud/Vault.tsx Editor and Recover), the library's
// (open_dialog; 添加's a pick): what 添加 offers, an item written (a new one, or one opened, changed or deleted), the recovery words
// typed in.

///|
/// 添加 (AddKinds): which kind is added, picked beside what opened it (`from`: the page's 添加; a sheet on Small): a
/// subscription or a model's key (a profile: the Profile list), or a secret of a kind (its editor, the kind fixed, which
/// says it is kept in the clear where the library is not locked); each its mark, its name and what it is.
pub fn vault_add(core : Core, here : Here, from~ : @sf.Beside) -> Unit {
  let ws = here.workspace
  let v = (core.topic)("vaults", { "workspace": str(ws) }).value
  let mine = items(v, "vaults").iter().find_first(fn(x) { flag(Some(x), "mine") })
  let plain = flag(v, "plain")
  let kinds = ["profile"]
  if mine is Some(_) {
    kinds.append(vault_kinds)
  }
  let choices = kinds.map(fn(k) {
    @sf.choice(
      k,
      @sf.t("web-pages.vault.addKind." + k),
      note=@sf.t("web-pages.vault.addKind." + k + "Detail"),
      icon=if k == "profile" { "quota" } else { @settings.kind_icon(k) },
    )
  })
  @sf.pick("", choices, "", fn(k) {
    if k == "profile" {
      (core.push)(Profiles(""))
    } else {
      match mine {
        Some(m) => vault_editor_dialog(core, ws, text(Some(m), "id"), None, kind=k, plain~, kinds=false)
        None => ()
      }
    }
  }, from~, along=End)
}

///|
/// A fixture's mode's 添加 put up from the page's own (MBUI_FIXTURE=settings-vault-add), as it is drawn.
pub let fx_vault_add_up : Ref[Bool] = Ref(false)

///|
/// An item written (Editor): a new one (`editing` None; its kind picked unless `kinds` is false and `kind` says it), or
/// one opened changed (its row and what it holds); its name and fields, whether agents may ask for it (then how it is
/// given, where to, under which variable, its longest grant); `vault.putItem`, the dialog staying while it is saved
/// (refused, why under it); 删除 for one there, asked first. `plain`: the library is not locked, said first.
pub fn vault_editor_dialog(
  core : Core,
  ws : String,
  vault : String,
  editing : (Json, Json)?,
  kind? : String = "",
  plain? : Bool = false,
  kinds? : Bool = true,
) -> Unit {
  let was = match editing {
    Some((_, p)) => Some(p)
    None => None
  }
  let row = match editing {
    Some((r, _)) => Some(r)
    None => None
  }
  let start_kind = match was {
    Some(p) => text(Some(p), "kind")
    None => kind
  }
  vault_serial.val += 1
  let e : VaultEditing = {
    kind: vault_item_kinds.search(start_kind).unwrap_or(0),
    agent: flag(row, "listed"),
    mode: match strings(row, "modes").iter().find_first(fn(m) { m == "proxy" || m == "env" }) {
      Some(m) => m
      None => "proxy"
    },
    lasts: vault_lasts.search(text(row, "lasts")).unwrap_or(0),
    error: "",
    saving: false,
    reveal: {},
    serial: vault_serial.val,
    file_content: text(field(was, "fields"), "content"),
    file_name: text(field(was, "fields"), "filename"),
    file_pick: None,
  }
  let key = fn(part : String) { "vault-editor/" + e.serial.to_string() + "/" + part }
  let filled : Map[String, Bool] = {}
  // a field's words put in once, as it opens
  let field_for = fn(part : String, value : String) -> @ui.Field {
    let f = field_of(key(part))
    if !filled.contains(part) {
      filled[part] = true
      if value != "" {
        f.set(value)
      }
    }
    f
  }
  // the fields' words as last typed: the foot's 保存 reads them
  let words : Map[String, String] = {}
  // a field of its: its label, its line (or lines: `area`), a secret's dotted, what is wrong under it
  let input = fn(c : @ui.Ctx, part : String, label : String, placeholder : String, secret : Bool, area : Bool, error : String) {
    let value = if part == "name" || part == "hosts" || part == "env" {
      match part {
        "name" => text(was, "name")
        "hosts" => join(strings(row, "hosts"), ", ")
        _ => text(row, "env")
      }
    } else {
      text(field(was, "fields"), part)
    }
    @sf.field(c, label, error~, fn() {
      words[part] = if area {
        @sf.textarea(c, key(part), rows=5, placeholder~, field=field_for(part, value))
      } else {
        @sf.input(c, key(part), placeholder~, secret~, field=field_for(part, value)).text
      }
    })
  }
  let title = match was {
    None => @sf.t("web-pages.vault.editor.new")
    Some(p) => text(Some(p), "name")
  }
  open_dialog(
    title,
    fn(c, _) {
      let k = vault_item_kinds[e.kind]
      if plain {
        c.text(@sf.t("web-pages.vault.risk.editor"), style=vt_warn_lines) |> ignore
      }
      if was is None && kinds {
        c.box(fn() {
          e.kind = @sf.segmented(c, key("kind"), vault_kinds.map(fn(x) { @sf.t("web-pages.vault.kind." + x) }), e.kind)
        })
        |> ignore
      }
      input(c, "name", @sf.t("web-pages.vault.editor.name"), @sf.t(if k == "file" { "web-pages.vault.editor.fileNamePlaceholder" } else { "web-pages.vault.editor.namePlaceholder" }), false, false, "")
      match k {
        "token" => input(c, "value", @sf.t("web-pages.vault.editor.value"), "ghp_…", true, false, "")
        "ssh_key" => {
          input(c, "private_key", @sf.t("web-pages.vault.editor.privateKey"), "-----BEGIN OPENSSH PRIVATE KEY-----", false, true, "")
          input(c, "public_key", @sf.t("web-pages.vault.editor.publicKey"), "ssh-ed25519 AAAA…", false, false, "")
        }
        // a sign-in: its cookies as they were kept, never typed or shown here
        "browser" => words["cookies"] = text(field(was, "fields"), "cookies")
        "file" => {
          // the system's picker answered: the file it gave (one too big said so, and none kept)
          match e.file_pick {
            Some(p) =>
              if take_picked_file(core, p, fn(content, name) {
                  e.file_content = content
                  e.file_name = name
                }) {
                e.file_pick = None
              }
            None => ()
          }
          @sf.field(c, @sf.t("web-pages.vault.editor.file"), fn() {
            // (the button the same before and after: what was picked fades in beside it, the row no higher)
            c.box(style=vd_file, fn() {
              if @sf.button(c, @sf.t("web-pages.vault.editor.pickFile"), key=key("file"), tone=Plain) {
                e.file_pick = @ui.pick(Files)
              }
              if e.file_content != "" {
                let name = if e.file_name != "" { e.file_name } else { @sf.t("web-pages.vault.kind.file") }
                let shown = @kit.presence(c, key("file/" + name), true).t
                c.rich([@ui.span(name + " · " + file_size(e.file_content), color=@sf.alpha(@sf.theme().p.text, shown))], style=vd_file_name)
                |> ignore
              }
            })
            |> ignore
          })
          words["content"] = e.file_content
          words["filename"] = e.file_name
        }
        _ => {
          input(c, "username", @sf.t("web-pages.vault.editor.username"), "name@example.com", false, false, "")
          input(c, "password", @sf.t("web-pages.vault.editor.password"), "", true, false, "")
          input(c, "totp", @sf.t("web-pages.vault.editor.totp"), "", true, false, "")
        }
      }
      // how agents may ask for it (agentBox)
      c.box(style=vd_agent, fn() {
        e.agent = @sf.switch_row(c, key("agent"), @sf.t("web-pages.vault.editor.agent"), e.agent, note=@sf.t("web-pages.vault.editor.agentNote"))
        if e.agent {
          @sf.field(c, @sf.t("web-pages.vault.editor.how"), fn() {
            if k == "ssh_key" || k == "file" || k == "browser" {
              c.text(mode_name(if k == "file" { "file" } else if k == "browser" { "browser" } else { "ssh" }), style=desk_words) |> ignore
            } else {
              let i = @sf.segmented(c, key("mode"), [mode_name("proxy"), mode_name("env")], if e.mode == "env" { 1 } else { 0 })
              e.mode = if i == 1 { "env" } else { "proxy" }
            }
          })
          c.text(
            @sf.t(
              if k == "ssh_key" {
                "web-pages.vault.editor.sshNote"
              } else if k == "file" {
                "web-pages.vault.editor.fileNote"
              } else if k == "browser" {
                "web-pages.vault.editor.browserNote"
              } else if e.mode == "proxy" {
                "web-pages.vault.editor.proxyNote"
              } else {
                "web-pages.vault.editor.envNote"
              },
            ),
            style=desk_note,
          )
          |> ignore
          if (k != "ssh_key" && k != "file" && e.mode == "proxy") || k == "browser" {
            let typed = words.get("hosts").unwrap_or("")
            input(c, "hosts", @sf.t("web-pages.vault.editor.hosts"), @sf.t("web-pages.vault.editor.hostsPlaceholder"), false, false, if typed != "" && vault_hosts(words).length() == 0 { @sf.t("web-pages.vault.editor.hostsNeeded") } else { "" })
          }
          if k != "ssh_key" && k != "browser" {
            input(c, "env", @sf.t("web-pages.vault.editor.env"), @sf.t(if k == "file" { "web-pages.vault.editor.fileEnvPlaceholder" } else { "web-pages.vault.editor.envPlaceholder" }), false, false, "")
          }
          @sf.field(c, @sf.t("web-pages.vault.editor.lasts"), fn() {
            e.lasts = @sf.segmented(c, key("lasts"), vault_lasts.map(lasts_choice), e.lasts)
          })
          c.text(@sf.t("web-pages.vault.editor.lastsNote"), style=desk_note) |> ignore
        }
      })
      |> ignore
      if e.error != "" {
        c.text(e.error, style=desk_note_bad) |> ignore
      }
    },
    fn(c, shut) {
      let k = vault_item_kinds[e.kind]
      match row {
        Some(r) => {
          let removing = is_doing(core, ["vault.deleteItem"], [("workspace", ws), ("vault", vault)])
          if @sf.button(c, @sf.t("common.delete"), key=key("delete"), tone=GhostDanger, busy=removing) {
            confirm(
              @sf.t("web-pages.vault.deleteTitle", args=[("name", text(was, "name"))]),
              @sf.t("web-pages.vault.deleteBody"),
              @sf.t("common.delete"),
              danger=true,
              fn() {
                shut()
                vault_act(core, ws, "deleteItem", [("vault", str(vault)), ("item", str(text(Some(r), "id")))], @sf.t("web-pages.vault.deleteWhat"), done=@sf.t("web-pages.vault.deleted"), then=fn(
                  _,
                ) {
                  (core.pop)()
                })
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
      let ready = vault_problem(k, words, e.agent, e.mode) == ""
      if @sf.button(c, @sf.t("common.save"), key=key("save"), tone=Primary, busy=e.saving, disabled=!ready) {
        e.saving = true
        e.error = ""
        c.blur()
        vault_act(
          core,
          ws,
          "putItem",
          vault_put_params(vault, row, was, k, words, e.agent, e.mode, vault_lasts[e.lasts]),
          @sf.t("web-pages.vault.saveWhat"),
          done=@sf.t("web-pages.vault.saved"),
          then=fn(_) {
            e.saving = false
            shut()
          },
          failed=fn(err) {
            e.saving = false
            // written elsewhere first: the vault was read again; what is here was written over that, so it goes
            if text(Some(err), "code") == "vault_conflict" {
              shut()
            } else {
              e.error = vault_said(err).unwrap_or("")
            }
          },
        )
      }
    },
  )
}

///|
/// The recovery words typed in (Recover): this device keyed into the person's vaults again (`vault.recover`); how many
/// typed of 24 at the foot.
pub fn vault_recover_dialog(core : Core, ws : String) -> Unit {
  vault_serial.val += 1
  let key = "vault-recover/" + vault_serial.val.to_string()
  let state : @signals.Signal[(Bool, String)] = @signals.signal((false, ""))
  let words = Ref("")
  let count_of = fn() { words.val.replace_all(old="\n", new=" ").split(" ").filter(fn(w) { w != "" }).count() }
  open_dialog(
    @sf.t("web-pages.vault.recover"),
    description=@sf.t("web-pages.vault.recoverLead"),
    fn(c, _) {
      words.val = @sf.textarea(c, key, rows=4, field=field_of(key))
      let (_, error) = state.get()
      if error != "" {
        c.text(error, style=desk_note_bad) |> ignore
      }
    },
    fn(c, shut) {
      let n = count_of()
      c.text("\{n} / 24", style=desk_note) |> ignore
      c.spacer()
      if @sf.button(c, @sf.t("common.cancel"), key=key + "/cancel", tone=Ghost) {
        c.blur()
        shut()
      }
      let (busy, _) = state.get()
      // (its button's words short beside the count and 取消 on a phone: the dialog's title says what it is)
      if @sf.button(c, @sf.t("web-pages.vault.recoverGo"), key=key + "/go", tone=Primary, busy~, disabled=n != 24) {
        state.set((true, ""))
        (core.call)("vault.recover", obj([("workspace", str(ws)), ("words", str(words.val.trim(chars=" \n").to_lower().to_owned()))]), fn(
          r,
        ) {
          match r {
            Ok(v) => {
              state.set((false, ""))
              let got = count(Some(v), "recovered")
              (core.say)(
                if got > 0 {
                  @sf.t("web-pages.vault.recovered", args=[("n", got.to_string())])
                } else {
                  @sf.t("web-pages.vault.recoveredNone")
                },
              )
              if got > 0 {
                shut()
              }
            }
            Err(e) => state.set((false, vault_said(e).unwrap_or("")))
          }
        })
      }
    },
  )
}


///|
/// (a file: its name and size, then the button that picks another, 12 apart)
// kept across runs: a value (no field of it changes)
let vd_file : @ui.Style = @ui.css("row w=Full gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let vd_file_name : @ui.TextStyle = @ui.text_style(size=Ui, leading=L5, color=Fg, wrap=false, w=Cut)

///|
/// (agentBox: the switch and what it opens, 10 apart, 4 over them)
// kept across runs: a value (no field of it changes)
let vd_agent : @ui.Style = @ui.css("w=Full gap=S2_5 pt=S1")

///|
/// (warn: the amber, the meta's size, in lines)
// kept across runs: a value (no field of it changes)
let vt_warn_lines : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=WarnInk, w=Full)
