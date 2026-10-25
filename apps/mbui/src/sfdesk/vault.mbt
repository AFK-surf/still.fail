// 密钥, one page in every frame (web/src/cloud/Vault.tsx VaultSettings, Library; the narrow app's mobile/Vault.tsx), laid
// out by its width (page_look.mbt): under its title what it keeps and 添加; what has to come first (security mode, this
// device signing, this device set up, the recovery words written down), then the requests waiting on the viewer (each
// one's card, as in its chat), whether it is encrypted (and locking it again), the longest a grant lasts, the profiles'
// accounts, each vault's secrets a section a kind (or, with no key here, its items' names), the devices that hold its
// keys, the stations that refused it. Adding, a secret's editor and the recovery words typed are the presenters'
// (vault_dialogs.mbt).

///|
/// 密钥 (VaultSettings, VaultScreen): as the core's `vaults` says where the viewer stands.
fn vault_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame) -> Unit {
  let look = look_of(c)
  let ws = here.workspace
  let topic = (core.topic)("vaults", { "workspace": str(ws) })
  let v = topic.value
  let words = recovery_words.get(ws)
  let usable = v is Some(_) &&
    words is None &&
    (flag(v, "plain") || (flag(v, "available") && flag(v, "locked") && flag(v, "canSign") && flag(v, "setUp")))
  let body : Array[() -> Unit] = match v {
    _ if words is Some(w) => [fn() { vault_words(c, look, ws, w) }]
    None =>
      [
        fn() {
          waiting_cards(
            c,
            error=match topic.error {
              Some(e) => error_text(e)
              None => ""
            },
          )
        },
      ]
    Some(_) if flag(v, "plain") => vault_library(c, core, look, ws, v)
    Some(_) if !flag(v, "available") => {
      let out : Array[() -> Unit] = []
      for row in items(v, "vaults") {
        out.append(vault_named(c, core, look, ws, row))
      }
      out.push(fn() { @sf.page_note(c, @sf.t("android-settings.vault.readOnly")) })
      out
    }
    Some(_) if !flag(v, "locked") =>
      [fn() { vault_gate(c, core, look, @sf.t("web-pages.vault.needsLock"), @sf.t("web-pages.vault.needsLockWhy")) }]
    Some(_) if !flag(v, "canSign") =>
      [fn() { vault_gate(c, core, look, @sf.t("web-pages.vault.notSigner"), @sf.t("web-pages.vault.notSignerWhy")) }]
    Some(_) if !flag(v, "setUp") => [fn() { vault_off(c, core, look, ws) }]
    Some(_) => vault_library(c, core, look, ws, v)
  }
  let add = fn() {
    match look {
      Wide =>
        if @sf.button(c, @sf.t("web-pages.vault.add"), key="vault-add", tone=Ghost, icon="plus") {
          vault_add_dialog(core, here)
        }
      Narrow =>
        if @sf.icon_button(c, "plus", key="vault-add", round=true, label=@sf.t("web-pages.vault.add")) {
          vault_add_dialog(core, here)
        }
    }
  }
  look_page(c, core, frame, "vault",
    @sf.t("web-pages.vault.title"),
    lead=@sf.t("web-pages.vault.lead"),
    actions?=if usable { Some(add) } else { None },
    body,
  )
}

///|
/// A card of the page's own: its state first (its mark before it where `icon`; amber where `risk`), what it means
/// under it, `then` after (its buttons).
fn vt_card(
  c : @ui.Ctx,
  look : Look,
  title : String,
  why : String,
  icon? : String = "",
  risk? : Bool = false,
  then? : () -> Unit,
) -> Unit {
  let t = @sf.theme()
  let draw = fn() {
    c.box(style=vt_state_line, fn() {
      if icon != "" {
        @sf.icon(c, icon, size=vt_glyph, color=if risk { t.p.warn_ink } else { t.p.text }) |> ignore
      }
      c.text(title, style=if risk { vt_state_risk } else { vt_state }) |> ignore
    })
    |> ignore
    if why != "" {
      c.text(why, style=desk_muted) |> ignore
    }
    match then {
      Some(f) => f()
      None => ()
    }
  }
  match look {
    Narrow => @sf.page_card(c, draw)
    Wide => c.box(style=desk_card.then(vt_lead), draw) |> ignore
  }
}

///|
/// A card's buttons at its foot, its words before them (the row goes on under where it has not the room): in the card's
/// foot corners, concentric with them (@sf.foot_reach; `words_first`: words lead the row, only its end reaching).
fn vt_buttons(c : @ui.Ctx, words_first? : Bool = false, f : () -> Unit) -> Unit {
  c.box(style=vt_actions.then(@sf.foot_reach(@sf.button_height(), words_first~)), flow=true, f) |> ignore
}

///|
/// What the vault waits for before anything else (Gate, ToSecurity): said, with the way there.
fn vault_gate(c : @ui.Ctx, core : Core, look : Look, title : String, why : String) -> Unit {
  vt_card(c, look, title, why, then=fn() {
    vt_buttons(c, fn() {
      if @sf.button(c, @sf.t("web-pages.vault.toSecurity"), key="vault-to-security", tone=Primary) {
        (core.push)(Security)
      }
    })
  })
}

///|
/// Not set up on this device yet (Off): what it is and what agents do with it; 开启 (`vault.setup`).
fn vault_off(c : @ui.Ctx, core : Core, look : Look, ws : String) -> Unit {
  vt_card(c, look, @sf.t("android-settings.vault.offTitle"), @sf.t("android-settings.vault.offWhat"), then=fn() {
    c.text(@sf.t("android-settings.vault.offAgents") + " " + @sf.t("android-settings.vault.offUnlock"), style=desk_muted)
    |> ignore
    vt_buttons(c, fn() {
      if @sf.button(
          c,
          @sf.t("android-settings.vault.turnOn"),
          key="vault-turn-on",
          tone=Primary,
          busy=is_doing(core, ["vault.setup"], [("workspace", ws)]),
        ) {
        vault_setup(core, ws)
      }
    })
  })
}

///|
/// This device set up (`vault.setup`, which makes the person's own vault when they have none): the first time the
/// recovery words come back, to be written down.
fn vault_setup(core : Core, ws : String) -> Unit {
  vault_act(core, ws, "setup", [], @sf.t("android-settings.vault.turnOn"), then=fn(said) {
    if opt_text(Some(said), "words") is Some(words) {
      recovery_words[ws] = words.trim(chars=" \n").to_owned().split(" ").map(fn(w) { w.to_owned() }).filter(fn(w) { w != "" }).collect()
    }
  })
}

///|
/// The 24 recovery words, numbered, three to a row, for the person to copy out (Words); written down, the person says so
/// (only once shown: the core gives them the once).
fn vault_words(c : @ui.Ctx, look : Look, ws : String, words : Array[String]) -> Unit {
  vt_card(c, look, @sf.t("android-settings.vault.wordsTitle"), @sf.t("android-settings.vault.wordsWhy"), then=fn() {
    c.box(style=vt_words, fn() {
      let rows = (words.length() + 2) / 3
      for r in 0..<rows {
        c.box(style=vt_words_row, fn() {
          for i in 0..<3 {
            let k = r * 3 + i
            c.box(style=vt_word, fn() {
              if k < words.length() {
                c.box(style=vt_word_number, fn() { mono(c, (k + 1).to_string(), style=vt_word_number_words) }) |> ignore
                mono(c, words[k], style=vt_word_words)
              }
            })
            |> ignore
          }
        })
        |> ignore
      }
    })
    |> ignore
    vt_buttons(c, words_first=true, fn() {
      c.text(@sf.t("android-settings.vault.wordsOnce"), style=desk_note) |> ignore
      if @sf.button(c, @sf.t("android-settings.vault.wordsDone"), key="vault-words-done", tone=Primary) {
        recovery_words.remove(ws)
      }
    })
  })
}

///|
/// The library (Library): see vault_page.
fn vault_library(c : @ui.Ctx, core : Core, look : Look, ws : String, v : Json?) -> Array[() -> Unit] {
  let plain = flag(v, "plain")
  let requests = items(v, "requests")
  let vaults = items(v, "vaults")
  let out : Array[() -> Unit] = []
  if requests.length() > 0 {
    out.push(fn() {
      sec_section(c, look, @sf.t("web-pages.vault.requests"), count=requests.length(), fn() {
        c.box(style=if look == Wide { vt_requests } else { vt_requests_narrow }, fn() {
          for r in requests {
            vault_request(c, core, ws, r)
          }
        })
        |> ignore
      })
    })
  }
  // whether it is encrypted, and locking it again once unlocked here a while
  out.push(fn() {
    vt_card(
      c,
      look,
      @sf.t(if plain { "web-pages.vault.lib.plain" } else { "web-pages.vault.lib.sealed" }),
      @sf.t(if plain { "web-pages.vault.lib.plainLong" } else { "web-pages.vault.lib.sealedWhy" }),
      icon="shield-check",
      risk=plain,
      then=fn() {
        if plain {
          vt_buttons(c, fn() {
            if @sf.button(c, @sf.t("web-pages.vault.lib.turnOn"), key="vault-turn-on", tone=Primary) {
              (core.push)(Security)
            }
          })
        } else if vaults.iter().any(fn(x) { flag(Some(x), "open") }) {
          vt_buttons(c, words_first=true, fn() {
            c.text(@sf.t("web-pages.vault.opened"), style=desk_note) |> ignore
            let locking = is_doing(core, ["vault.lock"], [("workspace", ws)])
            if @sf.button(c, @sf.t("web-pages.vault.lockNow"), key="vault-lock", tone=Ghost, busy=locking) {
              vault_act(core, ws, "lock", [], @sf.t("web-pages.vault.lockNow"))
            }
          })
        }
      },
    )
  })
  // the longest a grant of the viewer's secrets lasts where a secret says none
  match vaults.iter().find_first(fn(r) { flag(Some(r), "mine") }) {
    Some(mine) => out.push(fn() { vault_lasts_row(c, core, look, ws, mine) })
    None => ()
  }
  let left = number(v, "plainLeft").to_int()
  if !plain && left > 0 {
    out.push(fn() {
      vt_card(c, look, @sf.t("web-pages.vault.migrate.title", args=[("n", left.to_string())]), @sf.t("web-pages.vault.migrate.body"), risk=true, then=fn() {
        vt_buttons(c, fn() {
          if @sf.button(c, @sf.t("web-pages.vault.migrate.go"), key="vault-migrate", tone=Primary, busy=is_doing(core, ["vault.migrate"], [("workspace", ws)])) {
            @settings.act(core, @sf.t("web-pages.vault.migrate.what"), "vault.migrate", obj([("workspace", str(ws))]), done=@sf.t("android-settings.vault.migrate.done"))
          }
        })
      })
    })
  }
  // the profiles' accounts it keeps, a section a kind as the profiles list them, each to its profile
  let profiles = (core.topic)("profiles", { "scope": str(ws) }).value
  for g in profile_groups(items(profiles, "items")) {
    out.push(fn() {
      @sf.section(c, g.0, heads=true, fn() {
        vt_list(c, look, fn() {
          for e in g.1 {
            let ev = Some(e)
            let p = field(ev, "profile")
            if vt_row(c, look, "vault-profile/" + text(ev, "key"), text(p, "name"), join(["Profile", text(ev, "where")], " · "), fn() {
                @sf.provider_logo(c, text(p, "runtime"), text(field(p, "access"), "kind"), vt_glyph, text(p, "providerMark"))
              }) {
              (core.push)(Profile(text(ev, "station"), text(p, "id")))
            }
          }
        })
      })
    })
  }
  if !plain && vaults.length() == 0 {
    out.push(fn() {
      vt_card(c, look, @sf.t("web-pages.vault.none"), "", then=fn() {
        vt_buttons(c, fn() {
          if @sf.button(c, @sf.t("web-pages.vault.setUp"), key="vault-create", tone=Primary, busy=is_doing(core, ["vault.create"], [("workspace", ws)])) {
            @settings.act(core, @sf.t("web-pages.vault.createWhat"), "vault.create", obj([("workspace", str(ws)), ("name", str(@sf.t("web-pages.vault.personal")))]))
          }
        })
      })
    })
  }
  for row in vaults {
    if plain || flag(Some(row), "keyed") {
      out.append(vault_secrets(c, core, look, ws, row, plain, vaults.length() > 1))
    } else {
      out.append(vault_named(c, core, look, ws, row))
    }
  }
  if !plain && vaults.length() > 0 {
    out.push(fn() {
      @sf.section(c, @sf.t("web-pages.vault.devices"), heads=true, fn() {
        sec_group(c, look, fn() {
          // each vault a row: its name, and how many devices hold its key or, where some have none yet, how many
          for row in vaults {
            let rv = Some(row)
            let id = text(rv, "id")
            let missing = count(rv, "missing")
            sec_line(
              c,
              look,
              text(rv, "name"),
              note=if missing > 0 {
                @sf.t("web-pages.vault.missing", args=[("n", missing.to_string())])
              } else {
                @sf.t("web-pages.vault.devicesHold", args=[("n", count(rv, "devices").to_string())])
              },
              warn=missing > 0,
              strong=false,
              end=fn() {
                if missing > 0 && flag(rv, "mine") && flag(rv, "keyed") {
                  let giving = is_doing(core, ["vault.addDevice"], [("workspace", ws), ("vault", id)])
                  if sec_do(c, look, "vault-give/" + id, @sf.t("web-pages.vault.addDevice"), busy=giving) {
                    vault_act(core, ws, "addDevice", [("vault", str(id))], @sf.t("web-pages.vault.addDeviceWhat"), done=@sf.t("web-pages.vault.addedDevice"))
                  }
                }
              },
            )
          }
        })
      })
    })
  }
  // the stations that refused the library: not in security mode, or too old for it
  for r in items(v, "refused") {
    let rv = Some(r)
    let name = match text(rv, "name") {
      "" => text(rv, "station")
      n => n
    }
    out.push(fn() {
      @sf.page_note(c, @sf.t(if text(rv, "code") == "vault_needs_lock" { "android-settings.vault.refusedLock" } else { "android-settings.vault.refusedOld" }, args=[
          ("name", name),
        ]),
      )
    })
  }
  out
}

///|
/// A request waiting on the viewer (Vault.tsx Request): its card, as in its chat (vault_ask), and a way to that chat.
fn vault_request(c : @ui.Ctx, core : Core, ws : String, r : Json) -> Unit {
  let rv = Some(r)
  let id = text(rv, "id")
  let save = field(rv, "save")
  let asked : Asked = {
    name: match opt_text(rv, "itemName") {
      Some(n) => n
      None => text(rv, "item")
    },
    mode: text(rv, "mode"),
    command: text(rv, "command"),
    save_kind: text(save, "kind"),
    username: text(save, "username"),
    station: "",
  }
  let station = text(rv, "station")
  let extra = if station == "" {
    None
  } else {
    Some(fn() {
      if @sf.button(c, @sf.t("web-pages.vault.openChat"), key="vault-chat/" + id, tone=Ghost) {
        (core.open_chat)(ws + "/" + station, text(rv, "session"), "")
      }
    })
  }
  // (here, away from its chat: why the agent asks, and how it would be given)
  c.box(style=vt_request, fn() { vault_ask(c, core, ws, id, asked, true, extra~, said=[text(rv, "reason"), text(rv, "howText")]) }) |> ignore
}

///|
/// The longest a grant of the viewer's secrets lasts where a secret says none (Lasts, DefaultLasts): the library's
/// choices, each with what it means.
fn vault_lasts_row(c : @ui.Ctx, core : Core, look : Look, ws : String, mine : Json) -> Unit {
  let id = text(Some(mine), "id")
  let now = match vault_scopes.search(text(Some(mine), "lasts")) {
    Some(_) => text(Some(mine), "lasts")
    None => "chat"
  }
  let choose = fn() {
    let picked = @sf.choices(
      c,
      "vault-lasts",
      now,
      vault_scopes.map(fn(s) { (s, @sf.t("web-pages.vault.lasts." + s), @sf.t("web-pages.vault.lasts." + s + "Detail")) }),
      label=@sf.t("web-pages.vault.lasts.title"),
    )
    if picked != now {
      c.after_build("vault-lasts", fn() {
        vault_act(core, ws, "setLasts", [("vault", str(id)), ("lasts", str(picked))], @sf.t("web-pages.vault.lasts.what"))
      })
    }
  }
  match look {
    Wide => vt_card(c, look, @sf.t("web-pages.vault.lasts.title"), @sf.t("web-pages.vault.lasts.note"), then=choose)
    // (narrow: its title over it, the note, the choices on the page's ground, each its own card)
    Narrow => {
      @sf.heading(c, @sf.t("web-pages.vault.lasts.title"))
      @sf.page_note(c, @sf.t("web-pages.vault.lasts.note"))
      c.box(style=vt_choices_narrow, choose) |> ignore
    }
  }
}

///|
/// A vault's secrets, a section a kind (LibraryVault): each one's name and when an agent last used it, else how it
/// may be asked for (not encrypted first, in a library not locked); locked, those it does not name and unlocking.
fn vault_secrets(c : @ui.Ctx, core : Core, look : Look, ws : String, row : Json, plain : Bool, many : Bool) -> Array[() -> Unit] {
  let t = @sf.theme()
  let rv = Some(row)
  let topic = (core.topic)("vaultItems", { "workspace": str(ws), "vault": str(text(rv, "id")) })
  let list = match topic.value {
    Some(_) => items(topic.value, "items")
    None => return [fn() { @sf.wait_line(c, @sf.t("common.reading")) }]
  }
  let out : Array[() -> Unit] = []
  for kind in vault_kinds {
    let rows = list.filter(fn(x) { has(Some(x), "name") && text(Some(x), "kind") == kind })
    if rows.length() == 0 {
      continue
    }
    let title = @sf.t("web-pages.vault.kind." + kind)
    out.push(fn() {
      @sf.section(c, title + (if many { " · " + text(rv, "name") } else { "" }), heads=true, fn() {
        vt_list(c, look, fn() {
          for it in rows {
            let iv = Some(it)
            // (the core's: when an agent last used it, else how agents may ask for it)
            if vt_row(c, look, "vault-item/" + text(iv, "id"), text(iv, "name"), text(iv, "lineText"), risk=plain, fn() {
                @sf.icon(c, @settings.kind_icon(kind), size=vt_glyph, color=t.p.muted) |> ignore
              }) {
              (core.push)(VaultItem(text(rv, "id"), text(iv, "id")))
            }
          }
        })
      })
    })
  }
  // locked, those it does not name: a row of the list to unlock it
  let hidden = list.filter(fn(x) { !has(Some(x), "name") })
  if hidden.length() > 0 {
    out.push(fn() {
      vt_list(c, look, fn() {
        if vt_row(
            c,
            look,
            "vault-unlock/" + text(rv, "id"),
            @sf.t("web-pages.vault.hidden", args=[("n", hidden.length().to_string())]),
            "",
            value=@sf.t("web-pages.vault.unlock"),
            fn() { @sf.icon(c, "key", size=vt_glyph, color=t.p.muted) |> ignore },
          ) {
          @settings.act(core, @sf.t("web-pages.vault.unlockWhat"), "vault.open", obj([("workspace", str(ws)), ("item", str(text(Some(hidden[0]), "id")))]))
        }
      })
    })
  }
  if list.length() == 0 {
    out.push(fn() { @sf.page_note(c, @sf.t("web-pages.vault.empty")) })
  }
  out
}

///|
/// A vault known by its items' names only (VaultSection): a web page's, or one this device has no key to (then how to
/// get one, the recovery words where they can).
fn vault_named(c : @ui.Ctx, core : Core, look : Look, ws : String, row : Json) -> Array[() -> Unit] {
  let t = @sf.theme()
  let rv = Some(row)
  let topic = (core.topic)("vaultItems", { "workspace": str(ws), "vault": str(text(rv, "id")) })
  let list = items(topic.value, "items")
  let out : Array[() -> Unit] = []
  out.push(fn() {
    @sf.section(c, text(rv, "name"), heads=true, fn() {
      if flag((core.topic)("vaults", { "workspace": str(ws) }).value, "available") && !flag(rv, "keyed") {
        vt_card(c, look, @sf.t("android-settings.vault.noKey"), @sf.t("android-settings.vault.noKeyHow"), then=fn() {
          if flag(rv, "recoverable") {
            vt_buttons(c, fn() {
              if @sf.button(c, @sf.t("android-settings.vault.recover"), key="vault-recover/" + text(rv, "id"), tone=Ghost) {
                vault_recover_dialog(core, ws)
              }
            })
          }
        })
      }
      if list.length() == 0 {
        match topic.value {
          None =>
            match topic.error {
              Some(e) => @sf.page_note(c, error_text(e), bad=true)
              None => @sf.wait_line(c, @sf.t("common.reading"))
            }
          Some(_) => @sf.page_note(c, @sf.t("android-settings.vault.empty"))
        }
      } else {
        sec_group(c, look, fn() {
          for it in list {
            let iv = Some(it)
            let named = opt_text(iv, "name")
            sec_line(
              c,
              look,
              named.unwrap_or(@sf.t("android-settings.vault.lockedItem")),
              note=text(iv, "agentText"),
              strong=false,
              mark=fn() {
                @sf.icon(c, @settings.kind_icon(text(iv, "kind")), size=vt_glyph, color=if has(iv, "kind") { t.p.text } else { t.p.subtle })
                |> ignore
              },
              end=fn() {
                if flag(iv, "listed") {
                  c.box(style=vt_listed, fn() {  }) |> ignore
                }
              },
            )
          }
        })
      }
    })
  })
  out
}

///|
/// Rows that open something together (narrow: ListCard; wide: the web's list).
fn vt_list(c : @ui.Ctx, look : Look, body : () -> Unit) -> Unit {
  match look {
    Narrow => @sf.group(c, body)
    Wide => c.box(style=desk_list, body) |> ignore
  }
}

///|
/// A row of a list that opens something (rowButton, ListRow): its mark 16 in a column of its own (the muted, at the
/// name's line), its name, its line under it (`risk`: 未加密 first in the amber), `value` at its end in the link's ink.
/// Whether it was pressed.
fn vt_row(
  c : @ui.Ctx,
  look : Look,
  key : String,
  name : String,
  line : String,
  risk? : Bool = false,
  value? : String = "",
  mark : () -> Unit,
) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  c.cursor(id, Hand)
  let words = fn(title : @ui.TextStyle, note : @ui.TextStyle, warn : @ui.TextStyle) {
    c.box(style=if look == Wide { desk_list_text } else { narrow_row_words }, fn() {
      c.text(name, style=title) |> ignore
      if line != "" || risk {
        c.box(style=desk_said_line, fn() {
          if risk {
            c.text(@sf.t("web-pages.vault.risk.row") + " · ", style=warn) |> ignore
          }
          c.text(line, style=note) |> ignore
        })
        |> ignore
      }
    })
    |> ignore
  }
  let b = match look {
    Wide =>
      c.box(style=desk_list_link, id~, fn() {
        c.box(style=vt_row_icon, mark) |> ignore
        words(desk_list_title, desk_note, vt_warn)
        if value != "" {
          c.text(value, style=vt_link_words) |> ignore
        }
      })
    Narrow =>
      c.box(style=narrow_row, id~, fn() {
        c.box(style=vt_row_icon, mark) |> ignore
        words(narrow_row_title, vt_narrow_note, vt_narrow_warn)
        if value != "" {
          c.text(value, style=vt_narrow_link) |> ignore
        } else {
          @sf.icon(c, "chevron-right", size=narrow_chevron, color=t.p.subtle) |> ignore
        }
        finger_ripple(c, id)
      })
  }
  c.semantics(b, Link, id~, label=name)
  hit(c, id)
}

///|
/// (the page, its foot over it)
// kept across runs: a value (no field of it changes)
let vt_fill : @ui.Style = @ui.css("w=Full h=Full")

///|
let vt_glyph : Double = 16.0

///|
/// (state: first in its card, the body's size, 500, its icon 8 before it)
// kept across runs: a value (no field of it changes)
let vt_state : @ui.TextStyle = @ui.text_style(size=Body, leading=L7, weight=Medium, color=Fg, w=Full)

///|
// kept across runs: a value (no field of it changes)
let vt_state_risk : @ui.TextStyle = vt_state.then(@ui.text_style(color=Warn))

///|
// kept across runs: a value (no field of it changes)
let vt_state_line : @ui.Style = @ui.css("row gap=S2 align=ACenter")

///|
/// (lead: the first card as far from what follows as a section is)
// kept across runs: a value (no field of it changes)
let vt_lead : @ui.Style = @ui.css("mb=S7")

///|
/// (actions: a card's buttons at its foot, 8 apart, its words before them)
// kept across runs: a value (no field of it changes)
let vt_actions : @ui.Style = @ui.css("row w=Full gap=S2 pt=S1 align=ACenter")

///|
/// (count: the red's ground, the meta's size, 7 in)
// kept across runs: a value (no field of it changes)
let vt_count : @ui.Style = @ui.css("px=S1_5 radius=Full bg=DangerBg")

///|
// kept across runs: a value (no field of it changes)
let vt_count_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Medium, color=Danger, wrap=false)

///|
/// (requests: each one's card, 10 apart as the page's cards: pagesCss.card)
// kept across runs: a value (no field of it changes)
let vt_requests : @ui.Style = @ui.css("w=Full gap=S2_5")

///|
/// (a request's card, as wide as the page: AskCard fill)
// kept across runs: a value (no field of it changes)
let vt_request : @ui.Style = @ui.css("w=Full")

///|
/// (link: the accent's ink, the list's size)
// kept across runs: a value (no field of it changes)
let vt_link_words : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=AccentText, wrap=false)

///|
/// (warn: the amber, the meta's size)
// kept across runs: a value (no field of it changes)
let vt_warn : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Warn, wrap=false)

///|
/// (rowIcon: 16 wide, the muted, at the name's line)
// kept across runs: a value (no field of it changes)
let vt_row_icon : @ui.Style = @ui.css("w=S4 pt=S0_5 align=ACenter")

///|
/// (row: the devices' line, 30 high at least, its button at its end)
// kept across runs: a value (no field of it changes)
let vt_device_row : @ui.Style = @ui.style(row=true, w=Full, min_h=Fixed(vt_row_least), gap=S3, align=ACenter)

///|
let vt_row_least : Double = 30.0

///|
// kept across runs: a value (no field of it changes)
let vt_device_text : @ui.Style = @ui.style(row=true, w=@sf.grow, gap=S2_5, align=AEnd)

///|
/// Narrow: the requests' cards in the page's room, 10 apart; a row's line under its name (the secondary's, on
/// one line), amber where it is not encrypted.
// kept across runs: a value (no field of it changes)
let vt_requests_narrow : @ui.Style = @ui.css("w=Full pb=S2_5 gap=S2_5")

///|
// kept across runs: a value (no field of it changes)
let vt_narrow_note : @ui.TextStyle = @sf.secondary.then(@sf.one_line)

///|
// kept across runs: a value (no field of it changes)
let vt_narrow_warn : @ui.TextStyle = vt_narrow_note.then(@ui.text_style(color=Warn))

///|
/// An item agents are told of (listed): a green dot 6 round at its row's end.
// kept across runs: a value (no field of it changes)
let vt_listed : @ui.Style = @ui.css("w=S1_5 h=S1_5 radius=Full bg=Positive")

///|
/// The recovery words (Words): three to a row, 10 apart; each its number (the code face 12, subtle, 24 wide at its
/// end) 8 before it (the code face 15).
// kept across runs: a value (no field of it changes)
let vt_words : @ui.Style = @ui.css("w=Full pt=S1 gap=S2_5")

///|
// kept across runs: a value (no field of it changes)
let vt_words_row : @ui.Style = @ui.css("row w=Full")

///|
// kept across runs: a value (no field of it changes)
let vt_word : @ui.Style = @ui.style(row=true, w=@sf.grow, gap=S2, align=AEnd)

///|
// kept across runs: a value (no field of it changes)
let vt_word_number : @ui.Style = @ui.css("w=S6 align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let vt_word_number_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Subtle, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let vt_word_words : @ui.TextStyle = @ui.text_style(size=Body, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let vt_narrow_link : @ui.TextStyle = @sf.link.then(@sf.one_line)

///|
/// Narrow: the longest grant's choices in the page's room, 8 under its note, 10 over what follows.
// kept across runs: a value (no field of it changes)
let vt_choices_narrow : @ui.Style = @ui.css("w=Full pt=S2 pb=S2_5")
