// The desktop's 密钥 (web/src/cloud/Vault.tsx VaultSettings, Library) on the library's parts: under its title what it
// keeps and 添加; what has to come first (security mode, this device signing), then the requests waiting on the viewer
// (each one's facts over its answers), whether it is encrypted (and locking it again), the longest a grant lasts, the
// profiles' accounts, each vault's secrets a section a kind, the devices that hold its keys.

///|
/// 密钥 (VaultSettings): as the core's `vaults` says where the viewer stands.
fn vault_page_wide(c : @ui.Ctx, core : Core, here : Here) -> Unit {
  let ws = here.workspace
  let topic = (core.topic)("vaults", { "workspace": str(ws) })
  let v = topic.value
  let words = recovery_words.get(ws)
  let usable = v is Some(_) &&
    words is None &&
    (flag(v, "plain") || (flag(v, "available") && flag(v, "locked") && flag(v, "canSign") && flag(v, "setUp")))
  let body : Array[() -> Unit] = match v {
    _ if words is Some(w) => [fn() { vault_words(c, w) }]
    None =>
      [
        fn() {
          match topic.error {
            Some(e) => c.text(error_text(e), style=desk_note_bad) |> ignore
            None => @sf.wait_line(c, tr("common.reading"))
          }
        },
      ]
    Some(_) if flag(v, "plain") => vault_library_wide(c, core, ws, v)
    Some(_) if !flag(v, "available") => {
      let out : Array[() -> Unit] = []
      for row in items(v, "vaults") {
        out.append(vault_section(c, core, ws, row))
      }
      out.push(fn() { c.text(tr("android-settings.vault.readOnly"), style=desk_note) |> ignore })
      out
    }
    Some(_) if !flag(v, "locked") =>
      [fn() { vault_gate(c, core, tr("web-pages.vault.needsLock"), tr("web-pages.vault.needsLockWhy")) }]
    Some(_) if !flag(v, "canSign") =>
      [fn() { vault_gate(c, core, tr("web-pages.vault.notSigner"), tr("web-pages.vault.notSignerWhy")) }]
    Some(_) if !flag(v, "setUp") => [fn() { vault_off(c) }]
    Some(_) => vault_library_wide(c, core, ws, v)
  }
  c.box(style=vt_fill, fn() {
    c.box(style=vt_fill, fn() {
      desk_page(c, core, "vault", tr("web-pages.vault.title"), lead=tr("web-pages.vault.lead"), actions?=if usable {
        Some(fn() {
          if @sf.button(c, tr("web-pages.vault.add"), key="vault-add", tone=Ghost, icon="plus") {
            open_vault_add(core, here)
          }
        })
      } else {
        None
      }, body)
    })
    |> ignore
    vault_foot(c, core, ws, v)
  })
  |> ignore
}

///|
/// What the vault waits for before anything else (Gate): said, with the way there.
fn vault_gate(c : @ui.Ctx, core : Core, title : String, why : String) -> Unit {
  c.box(style=desk_card, fn() {
    c.text(title, style=vt_state) |> ignore
    c.text(why, style=desk_muted) |> ignore
    c.box(style=vt_actions, fn() {
      if @sf.button(c, tr("web-pages.vault.toSecurity"), key="vault-to-security", tone=Primary) {
        (core.push)(Security)
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// The library (Library): see vault_page_wide.
fn vault_library_wide(c : @ui.Ctx, core : Core, ws : String, v : Json?) -> Array[() -> Unit] {
  let t = @sf.theme()
  let plain = flag(v, "plain")
  let requests = items(v, "requests")
  let vaults = items(v, "vaults")
  let out : Array[() -> Unit] = []
  if requests.length() > 0 {
    out.push(fn() {
      @sf.section(
        c,
        tr("web-pages.vault.requests"),
        title_after=fn() {
          c.box(style=vt_count, fn() { c.text(requests.length().to_string(), style=vt_count_words) |> ignore }) |> ignore
        },
        fn() {
          c.box(style=vt_requests, fn() {
            for r in requests {
              vault_request_wide(c, core, ws, r)
            }
          })
          |> ignore
        },
      )
    })
  }
  // whether it is encrypted, and locking it again once unlocked here a while
  out.push(fn() {
    c.box(style=desk_card.then(vt_lead), fn() {
      c.box(style=vt_state_line, fn() {
        @sf.icon(c, "shield-check", size=vt_glyph, color=t.p.text) |> ignore
        c.text(tr(if plain { "web-pages.vault.lib.plain" } else { "web-pages.vault.lib.sealed" }), style=if plain {
          vt_state_risk
        } else {
          vt_state
        })
        |> ignore
      })
      |> ignore
      c.text(tr(if plain { "web-pages.vault.lib.plainLong" } else { "web-pages.vault.lib.sealedWhy" }), style=desk_muted) |> ignore
      if plain {
        c.box(style=vt_actions, fn() {
          if @sf.button(c, tr("web-pages.vault.lib.turnOn"), key="vault-turn-on", tone=Primary) {
            (core.push)(Security)
          }
        })
        |> ignore
      } else if vaults.iter().any(fn(x) { flag(Some(x), "open") }) {
        c.box(style=vt_actions, fn() {
          c.text(tr("web-pages.vault.opened"), style=desk_note) |> ignore
          let locking = is_doing(core, ["vault.lock"], [("workspace", ws)])
          if @sf.button(c, tr("web-pages.vault.lockNow"), key="vault-lock", tone=Ghost, busy=locking) {
            vault_act(core, ws, "lock", [], tr("web-pages.vault.lockNow"))
          }
        })
        |> ignore
      }
    })
    |> ignore
  })
  // the longest a grant of the viewer's secrets lasts where a secret says none
  match vaults.iter().find_first(fn(r) { flag(Some(r), "mine") }) {
    Some(mine) => out.push(fn() { vault_lasts_wide(c, core, ws, mine) })
    None => ()
  }
  let left = number(v, "plainLeft").to_int()
  if !plain && left > 0 {
    out.push(fn() {
      c.box(style=desk_card.then(vt_lead), fn() {
        c.text(fill("web-pages.vault.migrate.title", [("n", left.to_string())]), style=vt_state_risk) |> ignore
        c.text(tr("web-pages.vault.migrate.body"), style=desk_muted) |> ignore
        c.box(style=vt_actions, fn() {
          if @sf.button(c, tr("web-pages.vault.migrate.go"), key="vault-migrate", tone=Primary, busy=is_doing(core, ["vault.migrate"], [("workspace", ws)])) {
            act(core, tr("web-pages.vault.migrate.what"), "vault.migrate", obj([("workspace", str(ws))]), done=tr("android-settings.vault.migrate.done"))
          }
        })
        |> ignore
      })
      |> ignore
    })
  }
  // the profiles' accounts it keeps, a section a kind as the profiles list them, each to its profile
  let profiles = (core.topic)("profiles", { "scope": str(ws) }).value
  for g in profile_groups(items(profiles, "items")) {
    out.push(fn() {
      @sf.section(c, g.0, fn() {
        c.box(style=desk_list, fn() {
          for e in g.1 {
            let ev = Some(e)
            let p = field(ev, "profile")
            if vt_row(c, "vault-profile/" + text(ev, "key"), text(p, "name"), join(["Profile", text(ev, "where")], " · "), fn() {
                provider_mark(c, text(p, "runtime"), text(field(p, "access"), "kind"), vt_glyph, text(p, "providerMark"))
              }) {
              (core.push)(Profile(text(ev, "station"), text(p, "id")))
            }
          }
        })
        |> ignore
      })
    })
  }
  if !plain && vaults.length() == 0 {
    out.push(fn() {
      c.box(style=desk_card, fn() {
        c.text(tr("web-pages.vault.none"), style=desk_muted) |> ignore
        c.box(style=vt_actions, fn() {
          if @sf.button(c, tr("web-pages.vault.setUp"), key="vault-create", tone=Primary, busy=is_doing(core, ["vault.create"], [("workspace", ws)])) {
            act(core, tr("web-pages.vault.createWhat"), "vault.create", obj([("workspace", str(ws)), ("name", str(tr("web-pages.vault.personal")))]))
          }
        })
        |> ignore
      })
      |> ignore
    })
  }
  for row in vaults {
    if plain || flag(Some(row), "keyed") {
      out.append(vault_secrets_wide(c, core, ws, row, plain, vaults.length() > 1))
    } else {
      out.append(vault_section(c, core, ws, row))
    }
  }
  if !plain && vaults.length() > 0 {
    out.push(fn() {
      @sf.section(c, tr("web-pages.vault.devices"), fn() {
        c.box(style=desk_card, fn() {
          for row in vaults {
            let rv = Some(row)
            let id = text(rv, "id")
            let hold = fill("web-pages.vault.devicesHold", [("n", count(rv, "devices").to_string())])
            c.box(style=vt_device_row, fn() {
              c.box(style=vt_device_text, fn() {
                c.text((if vaults.length() > 1 { text(rv, "name") + " · " } else { "" }) + hold, style=desk_words) |> ignore
                if count(rv, "missing") > 0 {
                  c.text(fill("web-pages.vault.missing", [("n", count(rv, "missing").to_string())]), style=vt_warn) |> ignore
                }
              })
              |> ignore
              if count(rv, "missing") > 0 && flag(rv, "mine") && flag(rv, "keyed") {
                let giving = is_doing(core, ["vault.addDevice"], [("workspace", ws), ("vault", id)])
                if @sf.button(c, tr("web-pages.vault.addDevice"), key="vault-give/" + id, tone=Ghost, busy=giving) {
                  vault_act(core, ws, "addDevice", [("vault", str(id))], tr("web-pages.vault.addDeviceWhat"), done=tr("web-pages.vault.addedDevice"))
                }
              }
            })
            |> ignore
          }
        })
        |> ignore
      })
    })
  }
  out
}

///|
/// A request waiting on the viewer (Vault.tsx Request): its card, as in its chat (vault_ask), and a way to that chat.
fn vault_request_wide(c : @ui.Ctx, core : Core, ws : String, r : Json) -> Unit {
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
      if @sf.button(c, tr("web-pages.vault.openChat"), key="vault-chat/" + id, tone=Ghost) {
        (core.open_chat)(ws + "/" + station, text(rv, "session"), "")
      }
    })
  }
  c.box(style=vt_request, fn() { vault_ask(c, core, ws, id, asked, true, extra~) }) |> ignore
}

///|
/// The longest a grant of the viewer's secrets lasts where a secret says none (Lasts): the library's choices.
fn vault_lasts_wide(c : @ui.Ctx, core : Core, ws : String, mine : Json) -> Unit {
  let id = text(Some(mine), "id")
  let now = match vault_scopes.search(text(Some(mine), "lasts")) {
    Some(_) => text(Some(mine), "lasts")
    None => "chat"
  }
  c.box(style=desk_card.then(vt_lead), fn() {
    c.text(tr("web-pages.vault.lasts.title"), style=vt_state) |> ignore
    c.text(tr("web-pages.vault.lasts.note"), style=desk_muted) |> ignore
    let picked = @sf.choices(
      c,
      "vault-lasts",
      now,
      vault_scopes.map(fn(s) { (s, tr("web-pages.vault.lasts." + s), tr("web-pages.vault.lasts." + s + "Detail")) }),
      label=tr("web-pages.vault.lasts.title"),
    )
    if picked != now {
      c.after_build("vault-lasts", fn() {
        vault_act(core, ws, "setLasts", [("vault", str(id)), ("lasts", str(picked))], tr("web-pages.vault.lasts.what"))
      })
    }
  })
  |> ignore
}

///|
/// A vault's secrets, a section a kind (LibraryVault): each one's name and when an agent last used it, else how it
/// may be asked for (not encrypted first, in a library not locked); locked, those it does not name and unlocking.
fn vault_secrets_wide(c : @ui.Ctx, core : Core, ws : String, row : Json, plain : Bool, many : Bool) -> Array[() -> Unit] {
  let t = @sf.theme()
  let rv = Some(row)
  let topic = (core.topic)("vaultItems", { "workspace": str(ws), "vault": str(text(rv, "id")) })
  let list = match topic.value {
    Some(_) => items(topic.value, "items")
    None => return [fn() { @sf.wait_line(c, tr("common.reading")) }]
  }
  let out : Array[() -> Unit] = []
  for kind in vault_kinds {
    let rows = list.filter(fn(x) { has(Some(x), "name") && text(Some(x), "kind") == kind })
    if rows.length() == 0 {
      continue
    }
    let title = tr("web-pages.vault.kind." + kind)
    out.push(fn() {
      @sf.section(c, title + (if many { " · " + text(rv, "name") } else { "" }), fn() {
        c.box(style=desk_list, fn() {
          for it in rows {
            let iv = Some(it)
            let used = field(field(iv, "lastUse"), "at")
            let line = match used {
              Some(Object(_)) => fill("web-pages.vault.uses.last", [("when", text(used, "ago"))])
              _ => vt_item_line(iv)
            }
            if vt_row(c, "vault-item/" + text(iv, "id"), text(iv, "name"), line, risk=plain, fn() {
                @sf.icon(c, kind_icon(kind), size=vt_glyph, color=t.p.muted) |> ignore
              }) {
              (core.push)(VaultItem(text(rv, "id"), text(iv, "id")))
            }
          }
        })
        |> ignore
      })
    })
  }
  // locked, those it does not name: a row of the list to unlock it
  let hidden = list.filter(fn(x) { !has(Some(x), "name") })
  if hidden.length() > 0 {
    out.push(fn() {
      c.box(style=desk_list, fn() {
        let id = c.id("vault-unlock/" + text(rv, "id"))
        c.cursor(id, Hand)
        if hit(c, id) {
          act(core, tr("web-pages.vault.unlockWhat"), "vault.open", obj([("workspace", str(ws)), ("item", str(text(Some(hidden[0]), "id")))]))
        }
        c.box(style=desk_list_link, id~, fn() {
          c.box(style=desk_list_text, fn() {
            c.text(fill("web-pages.vault.hidden", [("n", hidden.length().to_string())]), style=desk_note) |> ignore
          })
          |> ignore
          c.text(tr("web-pages.vault.unlock"), style=vt_link_words) |> ignore
        })
        |> ignore
      })
      |> ignore
    })
  }
  if list.length() == 0 {
    out.push(fn() { c.text(tr("web-pages.vault.empty"), style=desk_note) |> ignore })
  }
  out
}

///|
/// An item's second line (itemLine): whether agents may ask for it and how, or that it is the viewer's alone.
fn vt_item_line(iv : Json?) -> String {
  if !flag(iv, "listed") {
    return tr("web-pages.vault.private")
  }
  let modes = strings(iv, "modes")
  let parts = [tr("web-pages.vault.agentMay")]
  parts.append(modes.map(mode_name))
  if modes.contains("proxy") {
    parts.append(strings(iv, "hosts"))
  }
  join(parts, " · ")
}

///|
/// A row of a list that opens something (rowButton): its mark 16 in a column of its own (the muted, at the name's
/// line), its name, its line under it (`risk`: 未加密 first in the amber). Whether it was pressed.
fn vt_row(c : @ui.Ctx, key : String, name : String, line : String, risk? : Bool = false, mark : () -> Unit) -> Bool {
  let id = c.id(key)
  c.cursor(id, Hand)
  c.box(style=desk_list_link, id~, fn() {
    c.box(style=vt_row_icon, mark) |> ignore
    c.box(style=desk_list_text, fn() {
      c.text(name, style=desk_list_title) |> ignore
      c.box(style=desk_said_line, fn() {
        if risk {
          c.text(tr("web-pages.vault.risk.row") + " · ", style=vt_warn) |> ignore
        }
        c.text(line, style=desk_note) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
  hit(c, id)
}

///|
/// (the page, its foot over it)
// kept across runs: a value (no field of it changes)
let vt_fill : @ui.Style = @ui.style(w=Full, h=Full)

///|
let vt_glyph : Double = 16.0

///|
/// (state: first in its card, the body's size, 500, its icon 8 before it)
// kept across runs: a value (no field of it changes)
let vt_state : @ui.TextStyle = @ui.text_style(size=Base, leading=L7, weight=Medium, color=Fg, w=Full)

///|
// kept across runs: a value (no field of it changes)
let vt_state_risk : @ui.TextStyle = vt_state.then(@ui.text_style(color=Warn))

///|
// kept across runs: a value (no field of it changes)
let vt_state_line : @ui.Style = @ui.style(row=true, gap=S2, align=ACenter)

///|
/// (lead: the first card as far from what follows as a section is)
// kept across runs: a value (no field of it changes)
let vt_lead : @ui.Style = @ui.style(mb=S7)

///|
/// (actions: a card's buttons at its foot, 8 apart, its words before them)
// kept across runs: a value (no field of it changes)
let vt_actions : @ui.Style = @ui.style(row=true, w=Full, gap=S2, pt=S1, align=ACenter)

///|
/// (count: the red's ground, the meta's size, 7 in)
// kept across runs: a value (no field of it changes)
let vt_count : @ui.Style = @ui.style(px=S1_5, radius=Full, bg=DangerBg)

///|
// kept across runs: a value (no field of it changes)
let vt_count_words : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, weight=Medium, color=Danger, wrap=false)

///|
/// (requests: each one's card, 10 apart as the page's cards: pagesCss.card)
// kept across runs: a value (no field of it changes)
let vt_requests : @ui.Style = @ui.style(w=Full, gap=S2_5)

///|
/// (a request's card, as wide as the page: AskCard fill)
// kept across runs: a value (no field of it changes)
let vt_request : @ui.Style = @ui.style(w=Full)

///|
/// (link: the accent's ink, the list's size)
// kept across runs: a value (no field of it changes)
let vt_link_words : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=AccentText, wrap=false)

///|
/// (warn: the amber, the meta's size)
// kept across runs: a value (no field of it changes)
let vt_warn : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Warn, wrap=false)

///|
/// (rowIcon: 16 wide, the muted, at the name's line)
// kept across runs: a value (no field of it changes)
let vt_row_icon : @ui.Style = @ui.style(w=S4, pt=S0_5, align=ACenter)

///|
/// (row: the devices' line, 30 high at least, its button at its end)
// kept across runs: a value (no field of it changes)
let vt_device_row : @ui.Style = @ui.style(row=true, w=Full, min_h=Fixed(vt_row_least), gap=S3, align=ACenter)

///|
let vt_row_least : Double = 30.0

///|
// kept across runs: a value (no field of it changes)
let vt_device_text : @ui.Style = @ui.style(row=true, w=@sf.grow, gap=S2_5, align=AEnd)
