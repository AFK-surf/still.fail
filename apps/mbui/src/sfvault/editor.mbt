// An item written (Vault.tsx's editor, the app's vault_dialogs.mbt), in the item's pane: its kind (a new one's
// picked), its name, its fields (a file's content and a sign-in's cookies kept as they are: only their name and use
// change here), whether agents may ask for it and how (by the proxy, its domains; its variable), its longest grant.
// Saved through `vault.putItem` with the settings' params (vault_put_params), what is wrong said under it.

///|
/// The fields an item of `kind` is written with here, each its words' key, its label's and whether it is a secret.
fn edited_fields(kind : String) -> Array[(String, String, Bool)] {
  match kind {
    "token" => [("value", "web-pages.vault.editor.value", true)]
    "ssh_key" => [("private_key", "web-pages.vault.editor.privateKey", true), ("public_key", "web-pages.vault.editor.publicKey", false)]
    "login" => [
        ("username", "web-pages.vault.editor.username", false),
        ("password", "web-pages.vault.editor.password", true),
        ("totp", "web-pages.vault.editor.totp", true),
      ]
    _ => []
  }
}

///|
/// The kinds a new item may be.
let new_kinds : Array[String] = ["token", "ssh_key", "login"]

///|
/// The longest grants an item may say (跟随默认 first: its vault's).
let lasts_all : Array[String] = ["default", "once", "hour", "chat"]

///|
/// The editor of item `id` ("" a new one) of `kind` in node `v`.
fn editor(v : @view.View, s : State, id : String, kind : String, back : Bool) -> Unit {
  let row = @signals.untracked(fn() { s.chosen_row() })
  let was = match @signals.untracked(fn() { s.plain.get() }) {
    Some((at, o)) if at == id => @sfbase.field(Some(o), "plain")
    _ => None
  }
  let fields = @sfbase.field(was, "fields")
  let kind_now = @signals.signal(kind)
  // (its words as they were, each in a field of its own)
  let typed : Map[String, @ui.Field] = {}
  let field_of = fn(key : String, initial : String) {
    match typed.get(key) {
      Some(f) => f
      None => {
        let f = @ui.Field::new(text=initial)
        typed[key] = f
        f
      }
    }
  }
  let name = field_of("name", @sfbase.text(was, "name"))
  for k in ["value", "private_key", "public_key", "username", "password", "totp"] {
    field_of(k, @sfbase.text(fields, k)) |> ignore
  }
  let listed = row.map(fn(r) { @sfbase.flag(Some(r), "listed") }).unwrap_or(id == "")
  let agent = @signals.signal(listed)
  let modes = @settings.strings(row, "modes")
  let mode = @signals.signal(if modes.contains("env") { "env" } else { "proxy" })
  let hosts = field_of("hosts", @settings.strings(row, "hosts").join(", "))
  let env = field_of("env", @sfbase.text(row, "env"))
  let lasts = @signals.signal(match @sfbase.text(row, "lasts") {
    "" => "default"
    l => l
  })
  let problem = @signals.signal("")
  let vault = match @signals.untracked(fn() { s.chosen.get() }) {
    (vt, _) if vt != "" => vt
    _ => @sfbase.text(@signals.untracked(fn() { s.vault_rows() }).get(0), "id")
  }
  let save = fn() {
    let k = @signals.untracked(fn() { kind_now.get() })
    let words : Map[String, String] = {}
    for key, f in typed {
      words[key] = f.text()
    }
    // (a file's content and a sign-in's cookies as they were)
    for key in ["content", "filename", "cookies"] {
      if @sfbase.text(fields, key) != "" {
        words[key] = @sfbase.text(fields, key)
      }
    }
    let on = @signals.untracked(fn() { agent.get() })
    let m = @signals.untracked(fn() { mode.get() })
    let why = @settings.vault_problem(k, words, on, m)
    problem.set(why)
    if why != "" {
      return
    }
    let params = @settings.vault_put_params(vault, row, was, k, words, on, m, @signals.untracked(fn() { lasts.get() }))
    @sfbase.act(
      s.src,
      @sf.t("web-pages.vaultApp.saveWhat"),
      "vault/put",
      "vault.putItem",
      @settings.obj([("workspace", @settings.str(s.ws())), ..params]),
      done=@sf.t("web-pages.vaultApp.saved"),
      ok=fn(answer) {
        s.editing.set(None)
        let new_id = @sfbase.text(Some(answer), "id")
        s.show(vault, if new_id == "" { id } else { new_id })
      },
    )
  }
  pane_bar(v, s, back, fn(bar) {
    @sf.button_node(bar, fn() { @sf.t("common.cancel") }, fn() { s.editing.set(None) }, tone=Ghost) |> ignore
    @sf.button_node(bar, fn() { @sf.t("common.save") }, save, tone=Primary, busy=fn() { doing("vault/put") }) |> ignore
  })
  column(v, fn(c) {
    text(c, fn() {
      if id == "" {
        @sf.t("web-pages.vault.editor.new")
      } else {
        @sfbase.text(was, "name")
      }
    }, 22.0, fn() { p().text }, weight=600, line=28.0)
    |> ignore
    // a new one's kind
    if id == "" {
      @sf.seg_node(c, fn() { new_kinds.map(fn(k) { @sf.t("web-pages.vault.kind." + k) }) }, fn() {
        new_kinds.search(kind_now.get()).unwrap_or(0)
      }, fn(i) { kind_now.set(new_kinds[i]) })
      |> ignore
    }
    card(c, fn(k) {
      k.padding(Is((16.0, 14.0, 16.0, 16.0))).gap(Is(12.0)) |> ignore
      labelled(k, "web-pages.vault.editor.name", fn(b) {
        @sf.input_node(b, name, placeholder=@sf.t("web-pages.vault.editor.namePlaceholder")) |> ignore
      })
      k.pick(fn() { kind_now.get() }, fn(fs, kd) {
        fs.gap(Is(12.0)) |> ignore
        for x in edited_fields(kd) {
          let (key, label, secret) = x
          labelled(fs, label, fn(b) {
            if key == "private_key" {
              @sf.textarea_node(b, typed[key], rows=4) |> ignore
            } else {
              @sf.input_node(b, typed[key], secret~) |> ignore
            }
          })
        }
        if kd == "file" || kd == "browser" {
          text(fs, fn() { @sf.t(if kd == "file" { "web-pages.vaultApp.fileKept" } else { "web-pages.vaultApp.browserKept" }) }, 12.0, fn() {
            p().muted
          }, wrap=true)
          |> ignore
        }
      })
    })
    // how agents may ask for it
    card(c, fn(k) {
      k.padding(Is((16.0, 14.0, 16.0, 16.0))).gap(Is(12.0)) |> ignore
      @sf.switch_row_node(k, fn() { @sf.t("web-pages.vault.editor.agent") }, fn() { agent.get() }, fn(on) { agent.set(on) }, note=fn() {
        @sf.t("web-pages.vault.editor.agentNote")
      })
      |> ignore
      k.show(fn() { agent.get() }, fn(a) {
        a.gap(Is(12.0)) |> ignore
        a.pick(fn() { kind_now.get() }, fn(m, kd) {
          m.gap(Is(12.0)) |> ignore
          if kd == "token" || kd == "login" {
            labelled(m, "web-pages.vault.editor.how", fn(b) {
              @sf.seg_node(b, fn() { [@sf.t("web-pages.vault.mode.proxy"), @sf.t("web-pages.vault.mode.env")] }, fn() {
                if mode.get() == "env" { 1 } else { 0 }
              }, fn(i) { mode.set(if i == 1 { "env" } else { "proxy" }) })
              |> ignore
            })
            text(m, fn() {
              @sf.t(if mode.get() == "env" { "web-pages.vault.editor.envNote" } else { "web-pages.vault.editor.proxyNote" })
            }, 12.0, fn() { p().muted }, wrap=true)
            |> ignore
          } else {
            text(m, fn() { @sf.t("web-pages.vault.editor." + (if kd == "ssh_key" { "ssh" } else { kd }) + "Note") }, 12.0, fn() {
              p().muted
            }, wrap=true)
            |> ignore
          }
        })
        a.show(fn() { (mode.get() == "proxy" && kind_now.get() != "ssh_key" && kind_now.get() != "file") || kind_now.get() == "browser" }, fn(h) {
          labelled(h, "web-pages.vault.editor.hosts", fn(b) {
            @sf.input_node(b, hosts, placeholder=@sf.t("web-pages.vault.editor.hostsPlaceholder")) |> ignore
          })
        })
        a.show(fn() { kind_now.get() != "ssh_key" && kind_now.get() != "browser" }, fn(e) {
          labelled(e, "web-pages.vault.editor.env", fn(b) {
            @sf.input_node(b, env, placeholder=@sf.t("web-pages.vault.editor.envPlaceholder")) |> ignore
          })
        })
        labelled(a, "web-pages.vault.editor.lasts", fn(b) {
          @sf.seg_node(b, fn() {
            lasts_all.map(fn(l) { @sf.t(if l == "default" { "web-pages.vault.lasts.default" } else { "web-pages.vault.lasts." + l }) })
          }, fn() { lasts_all.search(lasts.get()).unwrap_or(0) }, fn(i) { lasts.set(lasts_all[i]) })
          |> ignore
        })
      })
    })
    c.show(fn() { problem.get() != "" }, fn(w) {
      text(w, fn() {
        match problem.get() {
          "hosts" => @sf.t("web-pages.vault.editor.hostsNeeded")
          "name" => @sf.t("web-pages.vault.editor.name")
          _ => @sf.t("web-pages.vault.editor.value")
        }
      }, 13.0, fn() { p().red })
      |> ignore
    })
  })
}

///|
/// A field's label over what `body` makes.
fn labelled(parent : @view.View, label : String, body : (@view.View) -> Unit) -> Unit {
  parent.box(fn(b) {
    b.gap(Is(6.0)) |> ignore
    text(b, fn() { @sf.t(label) }, 12.0, fn() { p().muted }, weight=500) |> ignore
    body(b)
  })
  |> ignore
}
