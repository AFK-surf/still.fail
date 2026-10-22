// The workspace's library of secrets (settings/Vault.kt VaultScreen, docs/vault.md; the core's `vaults`, `vaultItems`
// and `profiles` topics): what has to come first (security mode on, this device confirmed and set up), then the
// requests waiting on the viewer (an agent asking to use an item: 允许一次, 一小时内, 拒绝), whether it is locked, the
// profiles' accounts, each vault's secrets a section a kind (by name and what agents may do with them), the devices that
// hold the keys. As the app shows it read only: an item's own page, its editor and the recovery sheets are a later
// slice's.

///|
/// The kinds of item, in the editor's order (Vault.kt KINDS).
// kept across runs: a table, never written
let vault_kinds : Array[String] = ["token", "ssh_key", "login"]

///|
fn kind_icon(kind : String) -> String {
  match kind {
    "ssh_key" => "server"
    "login" => "user"
    _ => "key"
  }
}

///|
fn mode_name(mode : String) -> String {
  match mode {
    "proxy" | "env" | "ssh" => tr("android-settings.vault.mode." + mode)
    m => m
  }
}

///|
/// What agents may do with an item, in a line (Vault.kt agentLine).
fn agent_line(listed : Bool, modes : Array[String], hosts : Array[String]) -> String {
  if !listed {
    return tr("android-settings.vault.selfOnly")
  }
  let parts = [tr("android-settings.vault.agentCan")]
  parts.append(modes.map(mode_name))
  parts.push(join(hosts, ", "))
  join(parts, " · ")
}

///|
/// How a request would be given (Vault.kt howLine).
fn how_line(mode : String, hosts : Array[String]) -> String {
  let only = if mode == "proxy" && hosts.length() > 0 {
    fill("web-pages.vault.onlyTo", [("hosts", join(hosts, ", "))])
  } else {
    ""
  }
  join([mode_name(mode), only], " · ")
}

///|
fn vault_page(c : @ui.Ctx, core : Core, here : Here) -> Unit {
  let ws = here.workspace
  let topic = (core.topic)("vaults", { "workspace": str(ws) })
  let v = topic.value
  let words = recovery_words.get(ws)
  // not locked (no security mode): the library kept in the clear on its station, usable at once
  let usable = v is Some(_) &&
    words is None &&
    (flag(v, "plain") || (flag(v, "available") && flag(v, "locked") && flag(v, "canSign") && flag(v, "setUp")))
  let blocks : Array[() -> Unit] = [
    fn() {
      if usable {
        top_back(c, core, tr("android-settings.title"), trailing=fn() {
          if round_icon(c, "vault-add", "plus", @sf.theme().p.text) {
            open_vault_add(core, here)
          }
        })
      } else {
        top_back(c, core, tr("android-settings.title"))
      }
    },
    fn() { large_title(c, tr("android-settings.vault.title")) },
  ]
  match v {
    _ if words is Some(_) => blocks.push(fn() { vault_words(c, words.unwrap()) })
    None =>
      blocks.push(fn() {
        waiting_cards(
          c,
          error=match topic.error {
            Some(e) => error_text(e)
            None => ""
          },
        )
      })
    Some(_) if flag(v, "plain") => blocks.append(library(c, core, ws, v))
    Some(_) if !flag(v, "available") => {
      for row in items(v, "vaults") {
        blocks.append(vault_section(c, core, ws, row))
      }
      blocks.push(fn() { page_note(c, tr("android-settings.vault.readOnly")) })
    }
    Some(_) if !flag(v, "locked") =>
      blocks.push(fn() {
        to_security(c, core, tr("android-settings.vault.needsLock"), tr("android-settings.vault.needsLockWhy"))
      })
    Some(_) if !flag(v, "canSign") =>
      blocks.push(fn() {
        to_security(c, core, tr("android-settings.vault.notSigner"), tr("android-settings.vault.notSignerWhy"))
      })
    Some(_) if !flag(v, "setUp") => blocks.push(fn() { vault_off(c) })
    Some(_) => blocks.append(library(c, core, ws, v))
  }
  blocks.push(fn() { gap(c, 30.0) })
  c.box(w=Fill(1.0), h=Fill(1.0), fn() {
    c.box(w=Fill(1.0), h=Fill(1.0), fn() { scroll_page(c, "vault", blocks) }) |> ignore
    vault_foot(c, core, ws, v)
  })
  |> ignore
}

///|
/// What has to come first, and the way to it (Vault.kt ToSecurity).
fn to_security(c : @ui.Ctx, core : Core, title : String, why : String) -> Unit {
  list_card(c, fn() {
    body(c, fn() { para(c, title, sub=why) })
    if go_row(c, "to-security", tr("web-pages.security.title")) {
      (core.push)(Security)
    }
  })
}

///|
/// Not set up on this device yet (Vault.kt Off): what it is and what agents do with it.
fn vault_off(c : @ui.Ctx) -> Unit {
  let t = @sf.theme()
  list_card(c, fn() {
    body(c, fn() {
      c.box(dir=Row, gap=8.0, align=ACenter, fn() {
        dot(c, false)
        c.text(tr("android-settings.vault.offTitle"), size=15.0, weight=600, color=t.p.text, wrap=false, line=21.0)
        |> ignore
      })
      |> ignore
      para(c, tr("android-settings.vault.offWhat"))
      para(c, tr("android-settings.vault.offAgents"), sub=tr("android-settings.vault.offUnlock"))
    })
  })
}

///|
/// The library (Vault.kt Library): the requests waiting on the viewer, whether it is locked, the profiles' accounts,
/// each vault's secrets, the devices that hold the keys.
fn library(c : @ui.Ctx, core : Core, ws : String, v : Json?) -> Array[() -> Unit] {
  let t = @sf.theme()
  let plain = flag(v, "plain")
  let requests = items(v, "requests")
  let vaults = items(v, "vaults")
  let blocks : Array[() -> Unit] = []
  if requests.length() > 0 {
    blocks.push(fn() {
      section_header(c, tr("android-settings.vault.waitingTitle") + " · " + requests.length().to_string(), start=S6)
    })
    for r in requests {
      blocks.push(fn() { request_card(c, core, ws, v, r) })
    }
  }
  blocks.push(fn() {
    // first, whether it is locked (security mode on), and the way to lock it when not
    list_card(c, fn() {
      if list_row(c, key="vault-state", fn() {
          c.box(w=Px(18.0), align=ACenter, fn() {
            @sf.icon(c, "shield-check", size=18.0, color=if plain { warn } else { t.p.subtle }) |> ignore
          })
          |> ignore
          row_lines(
            c,
            tr(if plain { "web-pages.vault.lib.plain" } else { "web-pages.vault.lib.sealed" }),
            tr(if plain { "web-pages.vault.lib.plainWhy" } else { "web-pages.vault.lib.sealedWhy" }),
            title_color=if plain { warn } else { t.p.text },
            wrap_title=false,
          )
          if plain {
            c.text(tr("web-pages.vault.lib.turnOn"), size=15.0, color=@sf.link_ink(), wrap=false) |> ignore
          } else {
            chevron(c)
          }
        }) {
        (core.push)(Security)
      }
    })
  })
  // locked, the viewer's secrets saved before it still in plain text: encrypted into their vault
  let left = number(v, "plainLeft").to_int()
  if !plain && left > 0 {
    blocks.push(fn() { plain_left(c, core, ws, left) })
  }
  // the profiles' accounts it keeps, a section a kind as the Profile list groups them
  let profiles = (core.topic)("profiles", { "scope": str(ws) }).value
  for g in profile_groups(items(profiles, "items")) {
    blocks.append([
      fn() { section_header(c, g.0, start=S6) },
      fn() {
        list_card(c, fn() {
          for e in g.1 {
            let ev = Some(e)
            let p = field(ev, "profile")
            if list_row(c, key="vault-profile/" + text(ev, "key"), fn() {
                c.box(w=Px(18.0), align=ACenter, fn() {
                  provider_mark(c, text(p, "runtime"), text(field(p, "access"), "kind"), 18.0, text(p, "providerMark"))
                })
                |> ignore
                row_lines(c, text(p, "name"), join(["Profile", text(ev, "where")], " · "), wrap_title=false)
                chevron(c)
              }) {
              (core.push)(Profile(text(ev, "station"), text(p, "id")))
            }
          }
        })
      },
    ])
  }
  if !plain && vaults.length() == 0 {
    blocks.push(fn() {
      list_card(c, fn() {
        body(c, fn() {
          para(c, tr("android-settings.vault.none"))
          if wide_button(
              c,
              "vault-create",
              tr("android-settings.vault.create"),
              true,
              busy=is_doing(core, ["vault.create"], [("workspace", ws)]),
            ) {
            act(
              core,
              tr("android-settings.vault.create"),
              "vault.create",
              obj([("workspace", str(ws)), ("name", str(tr("android-settings.vault.personal")))]),
            )
          }
        })
      })
    })
  }
  for row in vaults {
    if plain || flag(Some(row), "keyed") {
      blocks.append(library_vault(c, core, ws, row, plain))
    } else {
      blocks.append(vault_section(c, core, ws, row))
    }
  }
  if !plain && vaults.length() > 0 {
    blocks.append([
      fn() { section_header(c, tr("android-settings.vault.devices"), start=S6) },
      fn() { vault_devices(c, core, ws, vaults) },
    ])
  }
  for r in items(v, "refused") {
    let rv = Some(r)
    let name = match text(rv, "name") {
      "" => text(rv, "station")
      n => n
    }
    blocks.push(fn() {
      page_note(
        c,
        fill(
          if text(rv, "code") == "vault_needs_lock" {
            "android-settings.vault.refusedLock"
          } else {
            "android-settings.vault.refusedOld"
          },
          [("name", name)],
        ),
      )
    })
  }
  blocks
}

///|
/// The profiles' accounts by the kind they are listed under, in the core's order: (its title, its accounts).
fn profile_groups(list : Array[Json]) -> Array[(String, Array[Json])] {
  let out : Array[(String, String, Array[Json])] = []
  for e in list {
    let g = text(Some(e), "group")
    match index_of(out, g) {
      Some(i) => out[i].2.push(e)
      None => out.push((g, text(Some(e), "groupTitle"), [e]))
    }
  }
  out.map(fn(x) { (x.1, x.2) })
}

///|
/// A request waiting on the viewer (Vault.kt RequestCard): what it is for, its command, how it is given, its chat; the
/// three answers under it (VaultOptions).
fn request_card(c : @ui.Ctx, core : Core, ws : String, v : Json?, r : Json) -> Unit {
  let t = @sf.theme()
  let rv = Some(r)
  let id = text(rv, "id")
  let mut station = ""
  for x in items(v, "vaults") {
    if text(Some(x), "id") == text(rv, "vault") {
      station = text(Some(x), "station")
    }
  }
  list_card(c, fn() {
    body(c, fn() {
      c.text(
        fill("android-settings.vault.request.title", [
          (
            "name",
            match opt_text(rv, "itemName") {
              Some(n) => n
              None => tr("android-settings.vault.request.someItem")
            },
          ),
        ]),
        size=15.0,
        weight=600,
        color=t.p.text,
        w=Fill(1.0),
        line=21.0,
      )
      |> ignore
      c.text(text(rv, "reason"), size=14.0, color=t.p.text, w=Fill(1.0), line=20.0) |> ignore
      match opt_text(rv, "command") {
        Some(cmd) => mono(c, cmd, size=13.0, line=19.0, wrap=true)
        None => ()
      }
      c.text(how_line(text(rv, "mode"), strings(rv, "hosts")), size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0)
      |> ignore
      if station != "" &&
        tap_text(c, "vault-chat/" + id, tr("android-settings.vault.request.openChat"), size=14.0) {
        (core.open_chat)(ws + "/" + station, text(rv, "session"), "")
      }
    })
  })
  c.box(w=Fill(1.0), padx=12.0, pb=10.0, fn() {
    let on = [("workspace", ws), ("request", id)]
    let options = [
      (tr("android-settings.vault.approve.once"), tr("android-settings.vault.approve.onceDetail"), true),
      (tr("android-settings.vault.approve.hour"), tr("android-settings.vault.approve.hourDetail"), false),
      (tr("android-settings.vault.approve.deny"), tr("android-settings.vault.approve.denyDetail"), false),
    ]
    let busy = if is_doing(core, ["vault.approve"], [("workspace", ws), ("request", id), ("scope", "once")]) {
      0
    } else if is_doing(core, ["vault.approve"], [("workspace", ws), ("request", id), ("scope", "hour")]) {
      1
    } else if is_doing(core, ["vault.deny"], on) {
      2
    } else {
      -1
    }
    match decision_options(c, "vault-options/" + id, options, busy) {
      Some(2) =>
        act(core, tr("android-settings.vault.approve.denyWhat"), "vault.deny", obj([("workspace", str(ws)), ("request", str(id))]))
      Some(k) =>
        act(
          core,
          tr("android-settings.vault.approve.what"),
          "vault.approve",
          obj([("workspace", str(ws)), ("request", str(id)), ("scope", str(if k == 0 { "once" } else { "hour" }))]),
        )
      None => ()
    }
  })
  |> ignore
}

///|
/// A decision's options (SettingParts.kt DecisionOptions): one card, a row each, its number in a circle (the
/// recommended one's in the accent), its label and its detail; `busy` the one being sent. Answers the one tapped.
fn decision_options(c : @ui.Ctx, key : String, options : Array[(String, String, Bool)], busy : Int) -> Int? {
  let t = @sf.theme()
  let mut picked : Int? = None
  // (the number's disc in the card's corner, a whole circle: the card's corner drawn round it, docs/ui-panels.md)
  let card_pad = 8.0
  let row_pad = 7.0
  let disc = 22.0
  let card_radius = @sf.around(card_pad + row_pad, disc / 2.0)
  c.box(w=Fill(1.0), pad=card_pad, radius=card_radius, bg=t.p.chip, fn() {
    // (nothing drawn between two: SettingParts.kt DecisionOptions)
    for i, o in options {
      let id = c.id(key + "/" + i.to_string())
      if hit(c, id) && busy < 0 {
        picked = Some(i)
      }
      c.box(
        dir=Row,
        w=Fill(1.0),
        pl=row_pad,
        pr=12.0,
        pt=row_pad,
        pb=row_pad,
        gap=12.0,
        radius=18.0,
        bg=if c.pressed(id) { @sf.alpha(t.p.text, 0.08) } else { 0L },
        id~,
        fn() {
          c.box(
            w=Px(disc),
            h=Px(disc),
            radius=disc / 2.0,
            bg=if o.2 { t.p.accent } else { @sf.alpha(t.p.text, 0.09) },
            align=ACenter,
            justify=JCenter,
            fn() {
              let ink = if o.2 { 0xFFFFFFFFL } else { t.p.muted }
              let digit = "option-" + (i + 1).to_string()
              if i < 6 && @sf.has_icon(digit) {
                @sf.icon(c, digit, size=22.0, color=ink) |> ignore
              } else {
                c.text((i + 1).to_string(), size=12.0, weight=600, color=ink, wrap=false) |> ignore
              }
            },
          )
          |> ignore
          c.box(w=Fill(1.0), fn() {
            c.text(o.0, size=15.0, weight=500, color=t.p.text, w=Fill(1.0), line=21.0) |> ignore
            if o.1 != "" {
              c.text(o.1, size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
            }
          })
          |> ignore
          if busy == i {
            spinner(c, inline=true)
          }
        },
      )
      |> ignore
    }
  })
  |> ignore
  picked
}

///|
/// A vault known by its items' names only (Vault.kt VaultSection): a web page's, or one this device has no key to.
fn vault_section(c : @ui.Ctx, core : Core, ws : String, row : Json) -> Array[() -> Unit] {
  let t = @sf.theme()
  let rv = Some(row)
  let topic = (core.topic)("vaultItems", { "workspace": str(ws), "vault": str(text(rv, "id")) })
  let list = items(topic.value, "items")
  let blocks : Array[() -> Unit] = [fn() { section_header(c, text(rv, "name"), start=S6) }]
  if flag((core.topic)("vaults", { "workspace": str(ws) }).value, "available") && !flag(rv, "keyed") {
    blocks.push(fn() {
      list_card(c, fn() {
        body(c, fn() { para(c, tr("android-settings.vault.noKey"), sub=tr("android-settings.vault.noKeyHow")) })
        if flag(rv, "recoverable") && go_row(c, "vault-recover/" + text(rv, "id"), tr("android-settings.vault.recover")) {
          open_vault_recover(core, ws)
        }
      })
    })
  }
  blocks.push(fn() {
    list_card(c, fn() {
      if list.length() == 0 {
        body(c, fn() {
          match topic.value {
            None =>
              match topic.error {
                Some(e) => wait_line(c, error_text(e), error=true)
                None => wait_line(c, tr("web-pages.settings.reading"))
              }
            Some(_) =>
              c.text(tr("android-settings.vault.empty"), size=14.0, color=t.p.muted, w=Fill(1.0), line=20.0) |> ignore
          }
        })
      }
      for it in list {
        let iv = Some(it)
        list_row(c, fn() {
          c.box(w=Px(32.0), h=Px(32.0), radius=10.0, bg=t.p.bg, align=ACenter, justify=JCenter, fn() {
            @sf.icon(c, kind_icon(text(iv, "kind")), size=16.0, color=if has(iv, "kind") { t.p.text } else { t.p.subtle })
            |> ignore
          })
          |> ignore
          c.box(w=Fill(1.0), fn() {
            let named = opt_text(iv, "name")
            c.text(
              named.unwrap_or(tr("android-settings.vault.lockedItem")),
              size=15.0,
              color=if named is None { t.p.muted } else { t.p.text },
              wrap=false,
              w=Fill(1.0),
              line=21.0,
            )
            |> ignore
            c.box(dir=Row, w=Fill(1.0), gap=6.0, align=ACenter, fn() {
              if flag(iv, "listed") {
                c.box(w=Px(6.0), h=Px(6.0), radius=3.0, bg=t.p.green, fn() {  }) |> ignore
              }
              c.text(
                agent_line(flag(iv, "listed"), strings(iv, "modes"), strings(iv, "hosts")),
                size=13.0,
                color=t.p.muted,
                wrap=false,
                w=Fill(1.0),
                line=18.0,
              )
              |> ignore
            })
            |> ignore
          })
          |> ignore
        })
        |> ignore
      }
    })
  })
  blocks
}

///|
/// A vault's secrets, a section each kind (Vault.kt LibraryVault): each one's name, and when an agent last used it (else
/// what agents may do with it); in a library not locked, that it is not encrypted, first.
fn library_vault(c : @ui.Ctx, core : Core, ws : String, row : Json, plain : Bool) -> Array[() -> Unit] {
  let t = @sf.theme()
  let rv = Some(row)
  let topic = (core.topic)("vaultItems", { "workspace": str(ws), "vault": str(text(rv, "id")) })
  let list = match topic.value {
    Some(_) => items(topic.value, "items")
    None => return []
  }
  let blocks : Array[() -> Unit] = []
  for kind in vault_kinds {
    let rows = list.filter(fn(x) { has(Some(x), "name") && text(Some(x), "kind") == kind })
    if rows.length() == 0 {
      continue
    }
    blocks.append([
      fn() { section_header(c, tr("android-settings.vault.kind." + kind), start=S6) },
      fn() {
        list_card(c, fn() {
          for it in rows {
            let iv = Some(it)
            if list_row(c, key="vault-item/" + text(iv, "id"), fn() {
              c.box(w=Px(18.0), align=ACenter, fn() {
                @sf.icon(c, kind_icon(kind), size=18.0, color=t.p.subtle) |> ignore
              })
              |> ignore
              let used = field(field(iv, "lastUse"), "at")
              let line = match used {
                Some(Object(_)) => fill("web-pages.vault.uses.last", [("when", text(used, "ago"))])
                _ => agent_line(flag(iv, "listed"), strings(iv, "modes"), strings(iv, "hosts"))
              }
              c.box(w=Fill(1.0), fn() {
                c.text(text(iv, "name"), size=15.0, color=t.p.text, wrap=false, w=Fill(1.0), line=21.0) |> ignore
                c.box(dir=Row, w=Fill(1.0), fn() {
                  if plain {
                    c.text(tr("web-pages.vault.risk.row") + " · ", size=13.0, color=warn, wrap=false, line=18.0)
                    |> ignore
                  }
                  c.text(line, size=13.0, color=t.p.muted, wrap=false, w=Fill(1.0), line=18.0) |> ignore
                })
                |> ignore
              })
              |> ignore
              chevron(c)
            }) {
              (core.push)(VaultItem(text(rv, "id"), text(iv, "id")))
            }
          }
        })
      },
    ])
  }
  let hidden = list.filter(fn(x) { !has(Some(x), "name") })
  if !plain && (hidden.length() > 0 || flag(rv, "open")) {
    blocks.push(fn() {
      list_card(c, fn() {
        if hidden.length() > 0 &&
          list_row(c, key="vault-unlock/" + text(rv, "id"), fn() {
            c.box(w=Px(18.0), align=ACenter, fn() { @sf.icon(c, "key", size=18.0, color=t.p.subtle) |> ignore })
            |> ignore
            row_title(c, tr("android-settings.vault.lockedNote"), color=t.p.muted)
          }) {
          act(
            core,
            tr("android-settings.vault.lockedNote"),
            "vault.open",
            obj([("workspace", str(ws)), ("item", str(text(Some(hidden[0]), "id")))]),
          )
        }
        if flag(rv, "open") &&
          list_row(c, key="vault-lock/" + text(rv, "id"), fn() {
            c.box(w=Px(18.0), fn() {  }) |> ignore
            row_title(c, tr("android-settings.vault.lock"), color=@sf.link_ink())
          }) {
          (core.call)("vault.lock", obj([("workspace", str(ws))]), fn(_) {  })
        }
      })
    })
  }
  blocks
}

///|
/// Whose service a profile runs on (Parts.kt ProviderMark): OpenCode's square, a listed provider's maker (the plug where
/// there is none), Anthropic or OpenAI.
fn provider_mark(c : @ui.Ctx, runtime : String, kind : String, size : Double, mark : String) -> Unit {
  let t = @sf.theme()
  if kind == "opencode-go" || mark == "opencode" {
    c.box(w=Px(size), h=Px(size), align=ACenter, justify=JCenter, fn() {
      c.box(w=Px(size / 2.0), h=Px(size * 2.0 / 3.0), border=size / 10.0, border_color=t.p.text, fn() {  }) |> ignore
    })
    |> ignore
    return
  }
  let maker = if kind == "api-provider" {
    mark
  } else if runtime == "claude" || kind == "anthropic-api" {
    "anthropic"
  } else {
    "openai"
  }
  if maker == "" || !@sf.has_drawable("maker_" + maker.replace_all(old="-", new="_")) {
    @sf.icon(c, "plug", size~, color=t.p.text) |> ignore
  } else {
    @sf.maker_mark(c, maker, runtime, size) |> ignore
  }
}

///|
/// Where the group `g` is among `out`, if it is.
fn index_of(out : Array[(String, String, Array[Json])], g : String) -> Int? {
  for i, x in out {
    if x.0 == g {
      return Some(i)
    }
  }
  None
}

///|
/// Security mode on, the viewer's secrets saved before it still in plain text (Vault.kt PlainLeft): how many, and 加密
/// under the words in the card's corner (`vault.migrate`).
fn plain_left(c : @ui.Ctx, core : Core, ws : String, n : Int) -> Unit {
  card(c, foot=true, fn() {
    c.box(style=plain_left_column, fn() {
      c.box(style=@sf.full_width, fn() {
        c.text(fill("android-settings.vault.migrate.title", [("n", n.to_string())]), style=@sf.body.then(@sf.full_words))
        |> ignore
        c.text(tr("android-settings.vault.migrate.body"), style=plain_left_body) |> ignore
      })
      |> ignore
      if button(
          c,
          "vault-migrate",
          tr("android-settings.vault.migrate.action"),
          true,
          busy=is_doing(core, ["vault.migrate"], [("workspace", ws)]),
        ) {
        act(
          core,
          tr("android-settings.vault.migrate.what"),
          "vault.migrate",
          obj([("workspace", str(ws))]),
          done=tr("android-settings.vault.migrate.done"),
        )
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// Its words, then its button, 12 apart (Vault.kt:493); the line under its title 13 on 19 in the muted.
// kept across runs: a value (no field of it changes)
let plain_left_column : @ui.Style = @ui.style(w=Full, gap=S3)

///|
// kept across runs: a value (no field of it changes)
let plain_left_body : @ui.TextStyle = @ui.text_style(size=Sm, leading=L4_75, color=Muted, w=Full)
