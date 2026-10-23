// The library's writes and an item's own page (Vault.kt): setting the vault up on this device and the recovery words
// shown that once (`vault.setup`, then the first vault made: `vault.create`), 添加 (a profile, or a secret of a kind in
// its editor), a secret's page (its content masked until shown: `vault.open`; each field shown and copied, a secret
// cleared from the clipboard 30 s later; how agents may use it; when they did), its editor (`vault.putItem`,
// `vault.deleteItem`), the key given to devices set up since (`vault.addDevice`) and this device keyed again by the
// recovery words (`vault.recover`). What an item holds is held by its page or sheet only while it is up, never kept,
// never logged (the call log redacts it: stillfail/main.mbt `logged`).

///|
/// The fields each kind of item holds, in the editor's order; those not secret.
fn vault_fields(kind : String) -> Array[String] {
  match kind {
    "token" => ["value"]
    "ssh_key" => ["private_key", "public_key"]
    "login" => ["username", "password", "totp"]
    _ => []
  }
}

///|
// kept across runs: a table of constants, never written
let open_fields : Array[String] = ["public_key", "username"]

///|
/// A field's name (Vault.kt fieldName).
fn field_name(f : String) -> String {
  match f {
    "value" => tr("android-settings.vault.value")
    "private_key" => tr("android-settings.vault.privateKey")
    "public_key" => tr("android-settings.vault.publicKey")
    "username" => tr("android-settings.vault.username")
    "password" => tr("android-settings.vault.password")
    "totp" => tr("android-settings.vault.totp")
    x => x
  }
}

///|
/// What a vault call's failure says (vaultSaid): nothing when the person turned the system's prompt down
/// (`user_cancelled`), that another device wrote first (`vault_conflict`), else why.
fn vault_said(e : Json) -> String? {
  match text(Some(e), "code") {
    "user_cancelled" => None
    "vault_conflict" => Some(tr("android-settings.vault.conflict"))
    _ => Some(error_text(e))
  }
}

///|
/// A vault call (`vault.<name>` on the workspace), as act is for others (vaultAct): `done` said once through, a
/// failure said (a write made elsewhere first said as such; the prompt turned down, nothing).
fn vault_act(
  core : Core,
  ws : String,
  name : String,
  params : Array[(String, Json)],
  what : String,
  done? : String = "",
  then? : (Json) -> Unit = fn(_) {  },
  failed? : (Json) -> Unit = fn(_) {  },
) -> Unit {
  let p = [("workspace", str(ws))]
  for x in params {
    p.push(x)
  }
  (core.call)("vault." + name, obj(p), fn(r) {
    match r {
      Ok(v) => {
        if done != "" {
          (core.say)(done)
        }
        then(v)
      }
      Err(e) => {
        failed(e)
        match vault_said(e) {
          Some(why) =>
            (core.say)(
              if text(Some(e), "code") == "vault_conflict" {
                why
              } else {
                fill(
                  if text(Some(e), "code") == "unconfirmed" {
                    "android-misc.act.unconfirmed"
                  } else {
                    "android-misc.act.failed"
                  },
                  [("what", what), ("error", why)],
                )
              },
            )
          None => ()
        }
      }
    }
  })
}

///|
/// The recovery words `vault.setup` gave, by workspace, until the person says they have written them down: in memory
/// only, never kept (the core gives them only the once).
let recovery_words : Map[String, Array[String]] = Map([])

///|
/// This device set up (`vault.setup`): the first time the recovery words come back, to be written down; then (or at
/// once, when one of the person's devices made them before) their personal vault, when they have none.
fn vault_setup(core : Core, ws : String, v : Json?) -> Unit {
  vault_act(core, ws, "setup", [], tr("android-settings.vault.turnOn"), then=fn(said) {
    match opt_text(Some(said), "words") {
      Some(words) =>
        recovery_words[ws] = words.trim(chars=" \n").to_owned().split(" ").map(fn(w) { w.to_owned() }).filter(fn(w) { w != "" }).collect()
      None => if items(v, "vaults").length() == 0 { vault_create_first(core, ws) }
    }
  })
}

///|
/// The person's first vault made (`vault.create`, their personal one).
fn vault_create_first(core : Core, ws : String) -> Unit {
  vault_act(core, ws, "create", [("name", str(tr("android-settings.vault.personal")))], tr("android-settings.vault.create"))
}

///|
/// The 24 recovery words, numbered, three to a row, for the person to copy out (Words).
fn vault_words(c : @ui.Ctx, words : Array[String]) -> Unit {
  let t = @sf.theme()
  list_card(c, fn() {
    body(c, fn() {
      c.text(tr("android-settings.vault.wordsTitle"), size=15.0, weight=600, color=t.p.text, w=Fill(1.0), line=21.0) |> ignore
      c.text(tr("android-settings.vault.wordsWhy"), size=13.0, color=t.p.muted, w=Fill(1.0), line=19.0) |> ignore
      c.box(w=Fill(1.0), pt=4.0, gap=10.0, fn() {
        let rows = (words.length() + 2) / 3
        for r in 0..<rows {
          c.box(dir=Row, w=Fill(1.0), fn() {
            for i in 0..<3 {
              let k = r * 3 + i
              c.box(dir=Row, w=Fill(1.0), gap=8.0, align=AEnd, fn() {
                if k < words.length() {
                  c.box(w=Px(22.0), align=AEnd, fn() { mono(c, (k + 1).to_string(), size=12.0, color=t.p.subtle) }) |> ignore
                  mono(c, words[k], size=15.0)
                }
              })
              |> ignore
            }
          })
          |> ignore
        }
      })
      |> ignore
    })
  })
}

///|
/// The page's foot (Security.kt Foot): what goes on, over the page's ground, a note under it.
fn vault_foot(c : @ui.Ctx, core : Core, ws : String, v : Json?) -> Unit {
  match recovery_words.get(ws) {
    Some(_) =>
      foot(c, words=tr("android-settings.vault.wordsOnce"), fn() {
        if wide_button(c, "vault-words-done", tr("android-settings.vault.wordsDone"), true) {
          recovery_words.remove(ws)
          if items(v, "vaults").length() == 0 {
            vault_create_first(core, ws)
          }
        }
      })
    None =>
      if v is Some(_) && flag(v, "available") && flag(v, "locked") && flag(v, "canSign") && !flag(v, "setUp") {
        foot(c, fn() {
          if wide_button(c, "vault-turn-on", tr("android-settings.vault.turnOn"), true, busy=is_doing(core, ["vault.setup"], [("workspace", ws)])) {
            vault_setup(core, ws, v)
          }
        })
      }
  }
}

///|
/// (its rows' words: "web-pages.vault.addKind.profile" "web-pages.vault.addKind.profileDetail" "web-pages.vault.addKind.token" "web-pages.vault.addKind.tokenDetail" "web-pages.vault.addKind.ssh_key" "web-pages.vault.addKind.ssh_keyDetail" "web-pages.vault.addKind.login" "web-pages.vault.addKind.loginDetail")
/// 添加 in the library (addSheet): a subscription or a model's key (a profile, added from the Profile list), or a secret
/// of a kind (its editor, the kind fixed); not locked, that such a secret is kept in the clear.
fn open_vault_add(_core : Core, here : Here) -> Unit {
  let ws = here.workspace
  open_sheet(0.55, fn(c, core) {
    let t = @sf.theme()
    let v = (core.topic)("vaults", { "workspace": str(ws) }).value
    let mine = items(v, "vaults").iter().find_first(fn(x) { flag(Some(x), "mine") })
    let plain = flag(v, "plain")
    sheet_head(c, tr("web-pages.vault.addKind.title"))
    let add_row = fn(icon : String, kind : String) {
      list_row(c, key="vault-add/" + kind, fn() {
        c.box(w=Px(18.0), align=ACenter, fn() { @sf.icon(c, icon, size=18.0, color=t.p.subtle) |> ignore }) |> ignore
        row_lines(c, tr("web-pages.vault.addKind." + kind), tr("web-pages.vault.addKind." + kind + "Detail"), wrap_sub=true)
      })
    }
    list_card(c, fn() {
      if add_row("quota", "profile") {
        close_sheet()
        (core.push)(Profiles(""))
      }
      match mine {
        Some(m) =>
          for k in vault_kinds {
            if add_row(kind_icon(k), k) {
              open_vault_editor(core, ws, text(Some(m), "id"), None, kind=k, plain~)
            }
          }
        None => ()
      }
    })
    if plain && mine is Some(_) {
      c.box(w=Fill(1.0), padx=24.0, fn() {
        c.text(tr("web-pages.vault.risk.editor"), size=13.0, color=t.p.warn_ink, w=Fill(1.0), line=19.0) |> ignore
      })
      |> ignore
    }
  })
}

///|
/// The devices that hold each vault's key (Devices); its owner gives it to those set up since (`vault.addDevice`).
fn vault_devices(c : @ui.Ctx, core : Core, ws : String, vaults : Array[Json]) -> Unit {
  list_card(c, fn() {
    for row in vaults {
      let rv = Some(row)
      let id = text(rv, "id")
      let giving = is_doing(core, ["vault.addDevice"], [("workspace", ws), ("vault", id)])
      let give = flag(rv, "mine") && flag(rv, "keyed") && count(rv, "missing") > 0
      let hold = fill("android-settings.vault.devicesHold", [("n", count(rv, "devices").to_string())])
      if list_row(c, key=if give && !giving { "vault-give/" + id } else { "" }, fn() {
          row_lines(
            c,
            if vaults.length() > 1 {
              text(rv, "name") + " · " + hold
            } else {
              hold
            },
            if count(rv, "missing") > 0 {
              fill("android-settings.vault.missing", [("n", count(rv, "missing").to_string())])
            } else {
              ""
            },
            sub_color=warn,
          )
          if giving {
            spinner(c)
          } else if give {
            c.text(tr("android-settings.vault.giveKey"), size=14.0, color=@sf.link_ink(), wrap=false) |> ignore
          }
        }) {
        vault_act(core, ws, "addDevice", [("vault", str(id))], tr("android-settings.vault.giveKey"), done=tr("android-settings.vault.gaveKey"))
      }
    }
  })
}

///|
/// What `vault.open` gave of the item on its page (by item), while the page is up; whether it is being opened.
priv struct Opened {
  plain : Map[String, Json]
  opening : Map[String, Bool]
  /// the fields shown (by item and field)
  shown : Map[String, Bool]
}

///|
let opened : Opened = { plain: {}, opening: {}, shown: {} }

///|
/// The item opened (`vault.open`: the system's prompt first where its vault is locked here), then `then` with what it
/// holds.
fn open_item(core : Core, ws : String, item : String, then : (Json) -> Unit) -> Unit {
  if opened.opening.contains(item) {
    return
  }
  opened.opening[item] = true
  (core.call)("vault.open", obj([("workspace", str(ws)), ("item", str(item))]), fn(r) {
    opened.opening.remove(item)
    match r {
      Ok(v) =>
        match field(Some(v), "plain") {
          Some(Object(_) as p) => {
            opened.plain[item] = p
            then(p)
          }
          _ => ()
        }
      Err(e) =>
        match vault_said(e) {
          Some(why) =>
            (core.say)(fill("android-misc.act.failed", [("what", tr("android-settings.vault.openWhat")), ("error", why)]))
          None => ()
        }
    }
  })
}

///|
/// An item's page left: what it held goes.
fn vault_item_left(item : String) -> Unit {
  opened.plain.remove(item)
  opened.opening.remove(item)
  let gone = opened.shown.keys().filter(fn(k) { k.has_prefix(item + "/") }).collect()
  for k in gone {
    opened.shown.remove(k)
  }
}

///|
/// A secret's page (VaultItemScreen): its kind and where it is kept; in a library not locked, that it is not
/// encrypted; its content masked until shown, each field shown and copied; how agents may use it; when they did, each
/// use opening its chat. 编辑 opens it first, then its editor.
fn vault_item_page(c : @ui.Ctx, core : Core, here : Here, vault : String, item : String) -> Unit {
  let t = @sf.theme()
  let ws = here.workspace
  let vaults = (core.topic)("vaults", { "workspace": str(ws) })
  let list = (core.topic)("vaultItems", { "workspace": str(ws), "vault": str(vault) })
  let uses = (core.topic)("vaultUses", { "workspace": str(ws), "vault": str(vault), "item": str(item) })
  let v = items(vaults.value, "vaults").iter().find_first(fn(x) { text(Some(x), "id") == vault })
  let row = items(list.value, "items").iter().find_first(fn(x) { text(Some(x), "id") == item })
  let plain = flag(vaults.value, "plain")
  let back = tr("android-settings.vault.title")
  c.box(w=Fill(1.0), h=Fill(1.0), fn() {
    guard v is Some(vj) && row is Some(rj) else {
      nav_bar(c, core, back, back)
      waiting_cards(
        c,
        count=2,
        error=match (vaults.error, list.error) {
          (Some(e), _) | (_, Some(e)) => error_text(e)
          _ => ""
        },
      )
      return
    }
    let vv = Some(vj)
    let rv = Some(rj)
    let edit = fn(p : Json) { open_vault_editor(core, ws, vault, Some((rj, p)), plain~) }
    nav_bar(
      c,
      core,
      back,
      text(rv, "name"),
      sub=fn() {
        c.text(
          join([tr("android-settings.vault.kind." + text(rv, "kind")), fill("web-pages.vault.storedOn", [("station", text(vv, "stationName"))])], " · "),
          size=11.0,
          color=t.p.muted,
          wrap=false,
          line=16.0,
        )
        |> ignore
      },
      trailing=fn() {
        if nav_button(c, "vault-edit", "edit") {
          match opened.plain.get(item) {
            Some(p) => edit(p)
            None => open_item(core, ws, item, edit)
          }
        }
      },
    )
    let blocks : Array[() -> Unit] = [fn() { gap(c, 12.0) }]
    if plain {
      blocks.push(fn() {
        list_card(c, fn() {
          body(c, fn() {
            c.box(dir=Row, gap=8.0, align=ACenter, fn() {
              dot(c, false, warned=true)
              c.text(tr("web-pages.vault.risk.title"), size=15.0, weight=600, color=t.p.text, wrap=false, line=21.0) |> ignore
            })
            |> ignore
            c.text(fill("web-pages.vault.risk.body", [("station", text(vv, "stationName"))]), size=14.0, color=t.p.subtle, w=Fill(1.0), line=21.0)
            |> ignore
            if tap_text(c, "vault-item-lock", tr("web-pages.vault.lib.turnOn")) {
              (core.push)(Security)
            }
          })
        })
      })
    }
    blocks.push(fn() { section_header(c, tr("web-pages.vault.content"), start=S6) })
    blocks.push(fn() {
      list_card(c, fn() {
        match opened.plain.get(item) {
          None =>
            list_row(c, fn() {
              // masked, as long whatever its length (which would say something of it)
              c.box(w=Fill(1.0), fn() { mono(c, "••••••••••••••••••••", size=14.0) }) |> ignore
              if opened.opening.contains(item) {
                spinner(c, inline=true)
              } else if tap_text(c, "vault-show", tr("web-pages.vault.show")) {
                open_item(core, ws, item, fn(_) {  })
              }
            })
            |> ignore
          Some(p) => {
            let kind = text(Some(p), "kind")
            let fs = match vault_fields(kind) {
              [] =>
                match field(Some(p), "fields") {
                  Some(Object(m)) => m.keys().collect()
                  _ => []
                }
              x => x
            }
            for f in fs {
              let value = text(field(Some(p), "fields"), f)
              if value != "" {
                field_row(c, core, item, f, value, !open_fields.contains(f))
              }
            }
          }
        }
      })
    })
    blocks.push(fn() { section_header(c, tr("web-pages.vault.forAgents"), start=S6) })
    blocks.push(fn() {
      list_card(c, fn() {
        body(c, fn() {
          if !flag(rv, "listed") {
            c.text(tr("web-pages.vault.notForAgents"), size=15.0, color=t.p.muted, w=Fill(1.0), line=21.0) |> ignore
          } else {
            let hosts = strings(rv, "hosts")
            fact(c, tr("web-pages.vault.how"), join(strings(rv, "modes").map(fn(m) { how_line(m, hosts) }), "、"))
            match opt_text(rv, "env") {
              Some(env) if env != "" => fact(c, tr("android-settings.vault.env"), env, code=true)
              _ => ()
            }
            // its own longest grant, else its vault's (跟随默认 · …)
            fact(c, tr("android-settings.vault.lasts"), match opt_text(rv, "lasts") {
              Some(l) if l != "" => lasts_name(l)
              _ => fill("android-settings.vault.lasts.following", [("lasts", lasts_name(text(vv, "lasts")))])
            })
          }
        })
      })
    })
    blocks.push(fn() { section_header(c, tr("web-pages.vault.uses.title"), start=S6) })
    blocks.push(fn() {
      list_card(c, fn() {
        match uses.value {
          None =>
            list_row(c, fn() {
              row_title(
                c,
                match uses.error {
                  Some(e) => error_text(e)
                  None => tr("web-pages.settings.reading")
                },
                color=t.p.muted,
              )
            })
            |> ignore
          Some(_) => {
            let list = items(uses.value, "uses")
            if list.length() == 0 {
              list_row(c, fn() { row_title(c, tr("web-pages.vault.uses.none"), color=t.p.muted) }) |> ignore
            }
            for i, u in list {
              let uv = Some(u)
              let station = opt_text(uv, "station")
              if list_row(c, key=if station is Some(_) { "vault-use/" + i.to_string() } else { "" }, fn() {
                  c.box(w=Fill(1.0), fn() {
                    c.box(dir=Row, w=Fill(1.0), fn() {
                      c.text(
                        match opt_text(uv, "chatTitle") {
                          Some(x) => x
                          None => text(uv, "session")
                        },
                        size=15.0,
                        color=t.p.text,
                        wrap=false,
                        line=21.0,
                      )
                      |> ignore
                      if flag(uv, "denied") {
                        c.text(" · " + tr("web-pages.vault.uses.denied"), size=15.0, color=warn, wrap=false, line=21.0) |> ignore
                      }
                    })
                    |> ignore
                    mono(
                      c,
                      match opt_text(uv, "command") {
                        Some(x) => x
                        None => how_line(text(uv, "mode"), strings(uv, "hosts"))
                      },
                      size=13.0,
                      color=t.p.muted,
                    )
                  })
                  |> ignore
                  c.text(text(field(uv, "at"), "ago"), size=13.0, color=t.p.muted, wrap=false) |> ignore
                }) {
                match station {
                  Some(s) => (core.open_chat)(ws + "/" + s, text(uv, "session"), text(uv, "chatTitle"))
                  None => ()
                }
              }
            }
          }
        }
      })
    })
    blocks.push(fn() { gap(c, 30.0) })
    scroll_page(c, "vault-item/" + item, blocks)
  })
  |> ignore
}

///|
/// A fact of an item: its name in a narrow column, then what it is (Fact).
fn fact(c : @ui.Ctx, label : String, value : String, code? : Bool = false) -> Unit {
  let t = @sf.theme()
  c.box(dir=Row, w=Fill(1.0), gap=16.0, fn() {
    c.box(min_w=52.0, fn() { c.text(label, size=14.0, color=t.p.muted, wrap=false, line=21.0) |> ignore }) |> ignore
    c.box(w=Fill(1.0), fn() {
      if code {
        mono(c, value, size=14.0, line=21.0, wrap=true)
      } else {
        c.text(value, size=15.0, color=t.p.text, w=Fill(1.0), line=21.0) |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// A round icon button (RoundIcon). True on the frame after a tap.
fn round_icon(c : @ui.Ctx, key : String, icon : String, tint : Int64, said~ : String) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  let b = c.box(
    w=Px(34.0),
    h=Px(34.0),
    radius=17.0,
    align=ACenter,
    justify=JCenter,
    id~,
    fn() {
      @sf.icon(c, icon, size=18.0, color=tint) |> ignore
      // RoundIcon: clip(CircleShape).clickable
      @motion.ripple(c, id, 17.0)
    },
  )
  // `said`: what it is to a screen reader (RoundIcon's contentDescription)
  c.semantics(b, Button, id~, label=said)
  hit(c, id)
}

///|
/// What the eye beside a secret says (Vault.kt): 隐藏 while it shows, else 显示.
fn eye_said(shown : Bool) -> String {
  tr(if shown { "android-settings.vault.hide" } else { "android-settings.vault.reveal" })
}

///|
/// A field of an opened item (FieldRow): its name over its value (dots until shown, when secret), shown and copied from
/// beside it.
fn field_row(c : @ui.Ctx, core : Core, item : String, f : String, value : String, secret : Bool) -> Unit {
  let t = @sf.theme()
  let k = item + "/" + f
  let shown = !secret || opened.shown.contains(k)
  c.box(dir=Row, w=Fill(1.0), pl=16.0, pr=8.0, pt=10.0, pb=10.0, gap=2.0, align=ACenter, fn() {
    c.box(w=Fill(1.0), gap=2.0, fn() {
      c.text(field_name(f), size=12.0, color=t.p.muted, wrap=false, line=17.0) |> ignore
      // masked, as long whatever its length
      mono(c, if shown { value } else { "••••••••••••" }, size=14.0, line=20.0, wrap=shown)
    })
    |> ignore
    if secret && round_icon(c, "field-eye/" + k, "eye", if shown { t.p.accent } else { t.p.muted }, said=eye_said(shown)) {
      if shown {
        opened.shown.remove(k)
      } else {
        opened.shown[k] = true
      }
    }
    if round_icon(c, "field-copy/" + k, "copy", t.p.muted, said=tr("common.copy")) {
      copy_secret(c, core, value, secret)
    }
  })
  |> ignore
}

///|
/// What a secret copied was, and when (it is taken off the clipboard 30 s later, unless the app copied something else
/// meanwhile).
priv struct Copied {
  mut words : String
  /// a count of secrets copied: each its own 30 s
  mut serial : Int
}

///|
let copied : Copied = { words: "", serial: 0 }

///|
/// How long a secret copied stays on the clipboard (Vault.kt: 30 s).
let copied_life : Double = 30000.0

///|
/// Copied to the clipboard (copy): a secret said so and cleared copied_life later. (The Android app also marks it
/// sensitive for the system's preview of it, which this app's hosts do not do yet.)
fn copy_secret(c : @ui.Ctx, core : Core, words : String, secret : Bool) -> Unit {
  c.copy_text(words)
  (core.say)(tr(if secret { "android-settings.vault.copied" } else { "common.copied" }))
  if secret {
    copied.words = words
    copied.serial += 1
  } else {
    copied.words = ""
  }
}

///|
/// The secret copied taken off the clipboard once its time is up (@kit.after on the Ctx's clock; what is shown does
/// not wait for it).
fn clear_copied(c : @ui.Ctx) -> Unit {
  if copied.words == "" {
    return
  }
  if @kit.after(c, "vault-copied/" + copied.serial.to_string(), true, copied_life, later=true) {
    c.copy_text("")
    copied.words = ""
  }
}

///|
/// An item being written (Editor's state): its kind, whether agents may ask for it, how, the error said under it.
priv struct VaultEditing {
  mut kind : Int
  mut agent : Bool
  mut mode : String
  /// its longest grant (vault_lasts: 跟随默认 first)
  mut lasts : Int
  mut error : String
  mut saving : Bool
  /// the fields shown in the clear (by field)
  reveal : Map[String, Bool]
  serial : Int
}

///|
let vault_serial : Ref[Int] = Ref(0)

///|
/// An item's editor (editorSheet, Editor): its kind (new, and not fixed: picked), name and fields, whether agents may
/// ask for it (then how it is given, where to, under which variable); `vault.putItem`. The sheet stays while it is
/// saved (the system's prompt may come up): turned down, nothing lost; refused, why under it. 删除这一条 for one there.
/// `editing`: the item's row and what it holds as opened.
fn open_vault_editor(_core : Core, ws : String, vault : String, editing : (Json, Json)?, kind? : String = "", plain? : Bool = false) -> Unit {
  vault_serial.val += 1
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
  let e : VaultEditing = {
    kind: vault_kinds.search(start_kind).unwrap_or(0),
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
  }
  let key = fn(part : String) { "vault-editor/" + e.serial.to_string() + "/" + part }
  let filled : Map[String, Bool] = Map([])
  let fill_once = fn(c : @ui.Ctx, part : String, value : String) {
    if !filled.contains(part) {
      filled[part] = true
      if value != "" {
        field_of(key(part)).set(value)
      }
    }
  }
  // the fields' words as last drawn: 保存 at the top is drawn before them, from the frame before
  let words : Map[String, String] = Map([])
  open_sheet(0.92, fn(c, core) {
    let t = @sf.theme()
    let k = vault_kinds[e.kind]
    let blocks : Array[() -> Unit] = []
    let labeled = fn(label : String, f : () -> Unit) {
      c.box(w=Fill(1.0), gap=6.0, fn() {
        c.text(label, size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
        f()
      })
      |> ignore
    }
    let vault_field = fn(part : String, placeholder : String, secret : Bool, lines : Int) {
      fill_once(c, part, text(field(was, "fields"), part))
      let shown = e.reveal.contains(part)
      c.box(dir=Row, w=Fill(1.0), pl=12.0, pr=if secret { 8.0 } else { 12.0 }, pt=10.0, pb=10.0, gap=8.0, radius=12.0, bg=t.p.card, border=1.0, border_color=t.p.line, align=ACenter, fn() {
        let r = c.editor(
          key(part),
          field=field_of(key(part)),
          placeholder~,
          font_size=15.0,
          max_lines=if lines == 1 { 1 } else { 10 },
          plain=true,
          line=20.0,
          color=t.p.text,
          placeholder_color=t.p.subtle,
          caret_color=t.p.accent,
          enter_sends=lines == 1,
          secret=secret && !shown,
        )
        words[part] = r.text
        if secret && round_icon(c, key(part) + "/eye", "eye", if shown { t.p.accent } else { t.p.subtle }, said=eye_said(shown)) {
          if shown {
            e.reveal.remove(part)
          } else {
            e.reveal[part] = true
          }
        }
      })
      |> ignore
    }
    if plain {
      blocks.push(fn() {
        c.text(tr("web-pages.vault.risk.editor"), size=13.0, color=t.p.warn_ink, w=Fill(1.0), line=19.0) |> ignore
      })
    }
    if was is None && kind == "" {
      blocks.push(fn() {
        e.kind = seg(c, key("kind"), vault_kinds.map(fn(x) { tr("android-settings.vault.kind." + x) }), e.kind, fill=true, height=34.0)
      })
    }
    blocks.push(fn() {
      labeled(tr("android-settings.vault.name"), fn() {
        fill_once(c, "name", text(was, "name"))
        words["name"] = field_box(c, key("name"), tr("android-settings.vault.namePlaceholder"))
      })
    })
    let optional = fn(f : String) { fill("android-settings.vault.optional", [("name", field_name(f))]) }
    match k {
      "token" => blocks.push(fn() { labeled(field_name("value"), fn() { vault_field("value", "ghp_…", true, 1) }) })
      "ssh_key" => {
        blocks.push(fn() {
          labeled(field_name("private_key"), fn() { vault_field("private_key", "-----BEGIN OPENSSH PRIVATE KEY-----", true, 4) })
        })
        blocks.push(fn() { labeled(optional("public_key"), fn() { vault_field("public_key", "ssh-ed25519 AAAA…", false, 2) }) })
      }
      _ => {
        blocks.push(fn() { labeled(field_name("username"), fn() { vault_field("username", "name@example.com", false, 1) }) })
        blocks.push(fn() { labeled(field_name("password"), fn() { vault_field("password", "", true, 1) }) })
        blocks.push(fn() { labeled(optional("totp"), fn() { vault_field("totp", "JBSWY3DPEHPK3PXP", true, 1) }) })
      }
    }
    blocks.push(fn() {
      c.box(w=Fill(1.0), padx=16.0, pady=14.0, radius=16.0, bg=t.p.card, gap=12.0, fn() {
        let aid = c.id(key("agent"))
        if hit(c, aid) {
          e.agent = !e.agent
        }
        c.box(dir=Row, w=Fill(1.0), gap=12.0, align=ACenter, id=aid, fn() {
          row_lines(c, tr("android-settings.vault.agent"), tr("android-settings.vault.agentNote"), wrap_sub=true)
          switch(c, key("agent"), e.agent)
        })
        |> ignore
        if e.agent {
          if k == "ssh_key" {
            labeled(tr("android-settings.vault.how"), fn() {
              c.text(mode_name("ssh"), size=15.0, color=t.p.text, w=Fill(1.0), line=21.0) |> ignore
              c.text(tr("android-settings.vault.sshNote"), size=12.0, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
            })
          } else {
            labeled(tr("android-settings.vault.how"), fn() {
              let i = seg(c, key("mode"), [mode_name("proxy"), mode_name("env")], if e.mode == "env" { 1 } else { 0 }, fill=true, height=34.0)
              e.mode = if i == 1 { "env" } else { "proxy" }
              c.box(w=Fill(1.0), pt=4.0, fn() {
                c.text(tr("android-settings.vault.howNote"), size=12.0, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
              })
              |> ignore
            })
            if e.mode == "proxy" {
              labeled(tr("android-settings.vault.hosts"), fn() {
                fill_once(c, "hosts", join(strings(row, "hosts"), ", "))
                words["hosts"] = field_box(c, key("hosts"), "api.github.com, uploads.github.com")
                // words typed that name no host (only commas and spaces): said, in red (Vault.kt hostsNeeded)
                let typed = words.get("hosts").unwrap_or("")
                let named = typed.replace_all(old=",", new=" ").replace_all(old="\n", new=" ").split(" ").any(fn(h) { h != "" })
                if typed != "" && !named {
                  c.text(tr("android-settings.vault.hostsNeeded"), style=hosts_needed_words) |> ignore
                }
              })
            }
            labeled(tr("android-settings.vault.env"), fn() {
              fill_once(c, "env", text(row, "env"))
              words["env"] = field_box(c, key("env"), tr("android-settings.vault.envPlaceholder"))
            })
          }
          // how long a grant of it lasts at most: its vault's, or its own
          labeled(tr("android-settings.vault.lasts"), fn() {
            e.lasts = seg(c, key("lasts"), vault_lasts.map(lasts_choice), e.lasts, fill=true, height=34.0)
            c.box(style=vault_note_room, fn() { c.text(tr("android-settings.vault.lastsNote"), style=vault_note_words) |> ignore }) |> ignore
          })
        }
      })
      |> ignore
    })
    blocks.push(fn() {
      if e.error != "" {
        c.text(e.error, size=13.0, color=t.p.red, w=Fill(1.0), line=18.0) |> ignore
      }
      match row {
        Some(r) =>
          if tap_text(c, key("delete"), tr("android-settings.vault.delete"), color=t.p.red, size=14.0) {
            confirm(
              fill("android-settings.vault.deleteTitle", [("name", text(was, "name"))]),
              tr("android-settings.vault.deleteText"),
              tr("common.delete"),
              danger=true,
              fn() {
                vault_act(core, ws, "deleteItem", [("vault", str(vault)), ("item", str(text(Some(r), "id")))], tr("android-settings.vault.deleteWhat"), then=fn(_) {
                  (core.pop)()
                })
              },
            )
          }
        None => ()
      }
      gap(c, 24.0)
    })
    // what it would be saved as, from this frame's words
    let name = words.get("name").unwrap_or("").trim(chars=" ").to_owned()
    let got = fn(f : String) { words.get(f).unwrap_or("").trim(chars=" \n").to_owned() }
    let filled_in = match k {
      "token" => got("value") != ""
      "ssh_key" => got("private_key") != ""
      _ => got("username") != "" || got("password") != ""
    }
    let host_list : Array[String] = []
    for h in words.get("hosts").unwrap_or("").replace_all(old=",", new=" ").replace_all(old="\n", new=" ").split(" ") {
      if h != "" {
        host_list.push(h.to_owned())
      }
    }
    let no_hosts = e.agent && e.mode == "proxy" && k != "ssh_key" && host_list.length() == 0
    let ready = name != "" && filled_in && !no_hosts
    // its title, 保存 at its end
    c.box(dir=Row, w=Fill(1.0), pl=18.0, pr=18.0, pt=4.0, pb=10.0, gap=8.0, align=ACenter, fn() {
      c.text(
        match was {
          None => tr("android-settings.vault.newTitle")
          Some(p) => fill("android-settings.vault.editTitle", [("name", text(Some(p), "name"))])
        },
        size=17.0,
        weight=700,
        color=t.p.text,
        wrap=false,
        w=Fill(1.0),
        line=24.0,
      )
      |> ignore
      if button(c, key("save"), tr("common.save"), true, busy=e.saving, enabled=ready) {
        e.saving = true
        e.error = ""
        let fields : Array[(String, Json)] = []
        for f in vault_fields(k) {
          // a private key as pasted (its last line break is part of it); the rest without the spaces around them
          let v = if f == "private_key" { words.get(f).unwrap_or("") } else { got(f) }
          if v.trim(chars=" \n") != "" {
            fields.push((f, str(v)))
          }
        }
        let plain_item = obj([
          ("kind", str(k)),
          ("name", str(name)),
          ("fields", obj(fields)),
          ("domains", Json::array(strings(was, "domains").map(str))),
          ("notes", str(text(was, "notes"))),
        ])
        let params = [("vault", str(vault)), ("plain", plain_item)]
        match row {
          Some(r) => params.push(("id", str(text(Some(r), "id"))))
          None => ()
        }
        if e.agent {
          let modes = if k == "ssh_key" { ["ssh"] } else { [e.mode] }
          let listing = [
            ("name", str(name)),
            ("kind", str(k)),
            ("modes", Json::array(modes.map(str))),
            ("hosts", Json::array((if modes == ["proxy"] { host_list } else { [] }).map(str))),
          ]
          let env = got("env")
          if env != "" && k != "ssh_key" {
            listing.push(("env", str(env)))
          }
          // its own longest grant (none: its vault's)
          if vault_lasts[e.lasts] != "default" {
            listing.push(("lasts", str(vault_lasts[e.lasts])))
          }
          params.push(("listing", obj(listing)))
        }
        c.blur()
        vault_act(
          core,
          ws,
          "putItem",
          params,
          tr("common.save"),
          then=fn(_) {
            e.saving = false
            close_sheet()
          },
          failed=fn(err) {
            e.saving = false
            // written elsewhere first: the vault was read again; what is here was written over that, so it goes
            if text(Some(err), "code") == "vault_conflict" {
              close_sheet()
            } else {
              e.error = vault_said(err).unwrap_or("")
            }
          },
        )
      }
    })
    |> ignore
    c.box(w=Fill(1.0), h=Fill(1.0), fn() {
      scroll_page(c, "vault-editor/" + e.serial.to_string() + "/" + k, blocks.map(fn(b) {
        fn() { c.box(w=Fill(1.0), padx=20.0, pb=12.0, fn() { b() }) |> ignore }
      }))
    })
    |> ignore
  })
}

///|
/// This device keyed into the person's vaults again by their 24 recovery words (recoverSheet: `vault.recover`); the
/// words typed are this sheet's only while it is up.
fn open_vault_recover(_core : Core, ws : String) -> Unit {
  vault_serial.val += 1
  let key = "vault-recover/" + vault_serial.val.to_string()
  let state : Ref[(Bool, String)] = Ref((false, ""))
  open_sheet(0.62, fn(c, core) {
    let t = @sf.theme()
    sheet_head(c, tr("android-settings.vault.recover"))
    c.box(w=Fill(1.0), padx=20.0, gap=10.0, fn() {
      c.text(tr("android-settings.vault.recoverLead"), size=14.0, color=t.p.muted, w=Fill(1.0), line=20.0) |> ignore
      let mut words = ""
      c.box(w=Fill(1.0), padx=12.0, pady=10.0, radius=12.0, bg=t.p.card, border=1.0, border_color=t.p.line, fn() {
        words = c.editor(
          key,
          field=field_of(key),
          placeholder="orbit canvas lemon …",
          font_size=14.0,
          max_lines=5,
          plain=true,
          line=20.0,
          color=t.p.text,
          placeholder_color=t.p.subtle,
          caret_color=t.p.accent,
          enter_sends=false,
          secret=true,
        ).text
      })
      |> ignore
      let n = words.replace_all(old="\n", new=" ").split(" ").filter(fn(w) { w != "" }).count()
      c.text(fill("android-settings.vault.recoverCount", [("n", n.to_string())]), size=12.0, color=if n == 24 { t.p.green_ink } else { t.p.subtle }, w=Fill(1.0), line=17.0)
      |> ignore
      let (busy, error) = state.val
      if error != "" {
        c.text(error, size=13.0, color=t.p.red, w=Fill(1.0), line=18.0) |> ignore
      }
      c.box(dir=Row, w=Fill(1.0), pt=6.0, pb=24.0, gap=8.0, justify=JEnd, fn() {
        if button(c, "recover-cancel", tr("common.cancel"), false) {
          c.blur()
          close_sheet()
        }
        if button(c, "recover-go", tr("android-settings.vault.recoverAction"), true, busy~, enabled=n == 24) {
          state.val = (true, "")
          (core.call)("vault.recover", obj([("workspace", str(ws)), ("words", str(words.trim(chars=" \n").to_owned()))]), fn(r) {
            match r {
              Ok(v) => {
                state.val = (false, "")
                close_sheet()
                let got = count(Some(v), "recovered")
                (core.say)(
                  if got > 0 {
                    fill("android-settings.vault.recovered", [("n", got.to_string())])
                  } else {
                    tr("android-settings.vault.recoveredNone")
                  },
                )
              }
              Err(e) => state.val = (false, vault_said(e).unwrap_or(""))
            }
          })
        }
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// Hosts that name none (Vault.kt hostsNeeded: 12sp, red).
// kept across runs: a value (no field of it changes)
let hosts_needed_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Danger, w=Full)

///|
/// A field's note under it, 4 below (Vault.kt Labeled's: 12/18, muted).
// kept across runs: a value (no field of it changes)
let vault_note_room : @ui.Style = @ui.style(w=Full, pt=S1)

///|
// kept across runs: a value (no field of it changes)
let vault_note_words : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Muted, w=Full)
