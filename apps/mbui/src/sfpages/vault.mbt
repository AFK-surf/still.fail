// 密钥, one page in every frame and the same on every width (the user, 2026-10-26: 「这个页面需要整体重新设计，现在乱得
// 一批」: its state a card of its own, the longest approval a heading, a paragraph and three cards of their own, each on
// an edge of its own, what it keeps under the fold), and 全部密钥 under it. What has to come first (security mode, this
// device signing, this device set up, the recovery words written down): a card alone on either, with the way on. Set
// up, 密钥 is what waits on the viewer and how the library stands, not what it keeps (「密钥管理不需要入口做这么浅，因为
// 平时不会手动操作，顶多就是类似 1p，进去看一眼复制一下」): the requests waiting on the viewer first (each one's card, as
// in its chat); a vault waiting to be keyed anew, a card under its name (vault_waits); a row to 全部密钥; how its
// secrets are kept, a row each on one list card, each what it is with how it stands under it (encrypted or not, and
// unlocked here a while; those still in plain text from before; the longest an approval lasts, picked through the
// presenters; the devices holding its key); deleting the vault in red at its foot,
// asked first; the stations that refused it. 全部密钥 is what it keeps, a section a kind (the profiles' accounts as the
// profiles list them, then each vault's secrets), each a row to its page, and 添加 at its head. Made of the library's
// page parts (@sf.section, group, link_row, page_card), laid out by the page's width. Adding, a
// secret's editor and the recovery words typed are the presenters' (vault_dialogs.mbt). 全部密钥 is made once as nodes
// of the window's tree (vault_items_node); 密钥 is still its old view: its requests are their chats' card (vault_ask, an
// old view), and hosted in the tree (@ui.old) beside a popover going out, the old frame built keeping that island did
// not build as it did built whole.

///|
/// 密钥 (VaultSettings, VaultScreen): as the core's `vaults` says where the viewer stands.
pub fn vault_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame) -> Unit {
  let look = look_of(c)
  let ws = here.workspace
  let v = (core.topic)("vaults", { "workspace": str(ws) }).get().value
  let body = match vault_first(c, core, ws, fn(core, v) { vault_library(c, core, look, ws, v) }) {
    Some(first) => first
    None => vault_library(c, core, look, ws, v)
  }
  @sf.page(c, on_back=core.pop, frame~, "vault", @sf.t("web-pages.vault.title"), lead=@sf.t("web-pages.vault.lead"), body)
}

///|
/// What 密钥 and 全部密钥 show before the library, as the core's `vaults` says where the viewer stands: the recovery
/// words to write down; waiting for the core; a web page's names; what has to come first. None where the library is
/// there to be used (in plain text on the station, or locked, signed and set up here). While the core is waited for,
/// what the page holds (`shown`: its body for a library's view) of a made-up library, in its bones.
fn vault_first(
  c : @ui.Ctx,
  core : Core,
  ws : String,
  shown : (Core, Json?) -> Array[() -> Unit],
) -> Array[() -> Unit]? {
  let topic = (core.topic)("vaults", { "workspace": str(ws) }).get()
  let v = topic.value
  // (the words as they are now: read, so that this is built again as they come or go)
  recovery_words_turned.get() |> ignore
  match v {
    _ if recovery_words.get(ws) is Some(w) => Some([fn() { vault_words(c, ws, w) }])
    None =>
      Some([
        fn() {
          block_waiting(
            c,
            fn() {
              for b in shown(core.quiet(), Some(vaults_sample())) {
                b()
              }
            },
            error=match topic.error {
              Some(e) => error_text(e)
              None => ""
            },
          )
        },
      ])
    Some(_) if flag(v, "plain") => None
    // (a web page's: what it may say first, then the names it is told)
    Some(_) if !flag(v, "available") => {
      let out : Array[() -> Unit] = [fn() { @sf.page_note(c, @sf.t("android-settings.vault.readOnly")) }]
      for row in items(v, "vaults") {
        out.push(fn() { vault_named(c, core, ws, row) })
      }
      Some(out)
    }
    Some(_) if !flag(v, "locked") =>
      Some([fn() { vault_gate(c, core, @sf.t("web-pages.vault.needsLock"), @sf.t("web-pages.vault.needsLockWhy")) }])
    Some(_) if !flag(v, "canSign") =>
      Some([fn() { vault_gate(c, core, @sf.t("web-pages.vault.notSigner"), @sf.t("web-pages.vault.notSignerWhy")) }])
    Some(_) if !flag(v, "setUp") => Some([fn() { vault_off(c, core, ws) }])
    Some(_) => None
  }
}

///|
/// What the vault waits for before anything else (Gate, ToSecurity): said on a card, with the way there at its foot.
fn vault_gate(c : @ui.Ctx, core : Core, title : String, why : String) -> Unit {
  @sf.page_card(c, footed=true, fn() {
    @sf.card_lines(c, title, note=why)
    @sf.card_foot(c, fn() {
      @sf.button(c, @sf.t("web-pages.vault.toSecurity"), key="vault-to-security", tone=Primary, on_press=fn() {
        (core.push)(Security)
      }) |> ignore
    })
  })
}

///|
/// Not set up on this device yet (Off): what it is, what agents do with it and how it is opened, a line each; 开启
/// (`vault.setup`) at its foot.
fn vault_off(c : @ui.Ctx, core : Core, ws : String) -> Unit {
  @sf.page_card(c, footed=true, fn() {
    @sf.card_lines(
      c,
      @sf.t("android-settings.vault.offTitle"),
      words=@sf.t("android-settings.vault.offWhat"),
      note=@sf.t("android-settings.vault.offAgents") + "\n" + @sf.t("android-settings.vault.offUnlock"),
    )
    @sf.card_foot(c, fn() {
      @sf.button(
        c,
        @sf.t("android-settings.vault.turnOn"),
        key="vault-turn-on",
        tone=Primary,
        busy=is_doing(core, ["vault.setup"], [("workspace", ws)]),
        on_press=fn() {
          vault_setup(core, ws)
        },
      ) |> ignore
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
      recovery_words_changed()
    }
  })
}

///|
/// The 24 recovery words, numbered, three to a row, for the person to copy out (Words): why, and that they are shown
/// this once (the core gives them the once); written down, the person says so at its foot.
fn vault_words(c : @ui.Ctx, ws : String, words : Array[String]) -> Unit {
  @sf.page_card(c, footed=true, fn() {
    @sf.card_lines(
      c,
      @sf.t("android-settings.vault.wordsTitle"),
      words=@sf.t("android-settings.vault.wordsWhy"),
      note=@sf.t("android-settings.vault.wordsOnce"),
    )
    c.box(style=vt_words, fn() {
      let rows = (words.length() + 2) / 3
      for r in 0..<rows {
        c.box(style=vt_words_row, fn() {
          for i in 0..<3 {
            let k = r * 3 + i
            c.box(style=vt_word, fn() {
              if k < words.length() {
                c.box(style=vt_word_number, fn() { @settings.mono(c, (k + 1).to_string(), style=vt_word_number_words) }) |> ignore
                @settings.mono(c, words[k], style=vt_word_words)
              }
            })
            |> ignore
          }
        })
        |> ignore
      }
    })
    |> ignore
    @sf.card_foot(c, fn() {
      @sf.button(c, @sf.t("android-settings.vault.wordsDone"), key="vault-words-done", tone=Primary, on_press=fn() {
        recovery_words.remove(ws)
        recovery_words_changed()
      }) |> ignore
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
  if !plain && vaults.length() == 0 {
    out.push(fn() {
      @sf.page_card(c, footed=true, fn() {
        @sf.card_lines(c, @sf.t("web-pages.vault.none"))
        @sf.card_foot(c, fn() {
          @sf.button(c, @sf.t("web-pages.vault.setUp"), key="vault-create", tone=Primary, busy=is_doing(core, ["vault.create"], [("workspace", ws)]), on_press=fn() {
            @settings.act(core, @sf.t("web-pages.vault.createWhat"), "vault.create", obj([("workspace", str(ws)), ("name", str(@sf.t("web-pages.vault.personal")))]))
          }) |> ignore
        })
      })
    })
  }
  // this device holding no key to one of them: how to get one
  for row in vaults {
    if !plain && !flag(Some(row), "keyed") {
      out.push(fn() { vault_no_key(c, core, ws, Some(row)) })
    }
  }
  // one waiting to be keyed anew: on which station, and that it is read meanwhile, not changed
  for row in vaults {
    if text(Some(row), "waits") != "" {
      out.push(fn() { vault_waits(c, Some(row)) })
    }
  }
  // what it keeps (the profiles' accounts, the vaults' secrets), a page of its own
  out.push(fn() {
    @sf.group(c, fn() {
      @sf.link_row(c, "vault-all", @sf.t("web-pages.vault.all"), on_press=fn() {
        (core.push)(VaultItems)
      }) |> ignore
    })
  })
  out.push(fn() { vault_kept(c, core, ws, v) })
  // deleting a vault of the viewer's own, in red at the page's foot, asked first (what goes with it said)
  let mine = vaults.filter(fn(x) { flag(Some(x), "mine") })
  if !plain && mine.length() > 0 {
    out.push(fn() {
      @sf.group(c, fn() {
        for row in mine {
          vault_delete_row(c, core, ws, Some(row), vaults.length() > 1)
        }
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
/// A request waiting on the viewer: its card, as in its chat (vault_ask), and a way to that chat.
fn vault_request(c : @ui.Ctx, core : Core, ws : String, r : Json) -> Unit {
  let rv = Some(r)
  let id = text(rv, "id")
  let save = field(rv, "save")
  let asked : Asked = {
    name: match opt_text(rv, "itemName") {
      Some(n) => n
      None => text(rv, "item")
    },
    reason: text(rv, "reason"),
    timeout_kind: text(rv, "timeoutKind"),
    timeout_seconds: count(rv, "timeoutSeconds"),
    approved_timeout_kind: "",
    approved_timeout_seconds: 0,
    mode: text(rv, "mode"),
    command: text(rv, "command"),
    how_text: text(rv, "howText"),
    save_kind: text(save, "kind"),
    username: text(save, "username"),
    filename: text(save, "filename"),
    typed: flag(save, "typed"),
    oauth: text(save, "oauth"),
    station: "",
    describe: field(rv, "describe") is Some(_),
    new_name: text(field(rv, "describe"), "name"),
    new_about: text(field(rv, "describe"), "about"),
    was_about: text(field(rv, "describe"), "wasAbout"),
    remove: flag(rv, "remove"),
  }
  let station = text(rv, "station")
  let extra = if station == "" {
    None
  } else {
    Some(fn() {
      @sf.button(c, @sf.t("web-pages.vault.openChat"), key="vault-chat/" + id, tone=Ghost, on_press=fn() {
        (core.open_chat)(ws + "/" + station, text(rv, "session"), "")
      }) |> ignore
    })
  }
  c.box(style=vt_request, fn() { vault_ask(c, core, ws, id, asked, true, extra~) }) |> ignore
}

///|
/// How the library keeps its secrets, a row each on one list card (as a page's own settings stand first: a workspace's
/// name and mark): encrypted, or in plain text on the station (the way to security mode at its end), unlocked here a
/// while (locked again at once from its end); those still in plain text from before (encrypted from its end); the
/// longest an approval of the viewer's secrets lasts where a secret says none (its choices, each with what it means,
/// through the presenters); the devices holding each vault's key (given to new ones from its end). A row that does
/// something does it pressed, saying what at its end (vault_do_row); what is not as it should be said in amber.
fn vault_kept(c : @ui.Ctx, core : Core, ws : String, v : Json?) -> Unit {
  let plain = flag(v, "plain")
  let vaults = items(v, "vaults")
  let left = number(v, "plainLeft").to_int()
  @sf.group(c, fn() {
    if plain {
      vault_do_row(c, "vault-turn-on", @sf.t("web-pages.vault.lib.plain"), @sf.t("web-pages.vault.lib.plainWhy"), @sf.t("web-pages.vault.lib.turnOn"), lacks=true, on_press=fn() {
        (core.push)(Security)
      })
    } else {
      let open = vaults.iter().any(fn(x) { flag(Some(x), "open") })
      let sealed_words = @sf.t("web-pages.vault.lib.sealed")
      if open {
        let locking = is_doing(core, ["vault.lock"], [("workspace", ws)])
        vault_do_row(c, "vault-lock", sealed_words, @sf.t("web-pages.vault.opened"), @sf.t("web-pages.vault.lockNow"), busy=locking, on_press=fn() {
          vault_act(core, ws, "lock", [], @sf.t("web-pages.vault.lockNow"))
        })
      } else {
        @sf.link_row(c, "", sealed_words, note=@sf.t("web-pages.vault.lib.sealedWhy"), goes=false) |> ignore
      }
      if left > 0 {
        let moving = is_doing(core, ["vault.migrate"], [("workspace", ws)])
        vault_do_row(
          c,
          "vault-migrate",
          @sf.t("web-pages.vault.migrate.title", args=[("n", left.to_string())]),
          @sf.t("android-settings.vault.migrate.body"),
          @sf.t("web-pages.vault.migrate.go"),
          lacks=true,
          busy=moving,
          on_press=fn() {
            @settings.act(core, @sf.t("web-pages.vault.migrate.what"), "vault.migrate", obj([("workspace", str(ws))]), done=@sf.t("android-settings.vault.migrate.done"))
          },
        )
      }
    }
    match vaults.iter().find_first(fn(r) { flag(Some(r), "mine") }) {
      Some(mine) => vault_lasts_row(c, core, ws, mine)
      None => ()
    }
    if !plain {
      for row in vaults {
        vault_devices_row(c, core, ws, Some(row), vaults.length() > 1)
      }
    }
  })
}

///|
/// A row that does one thing (as 解锁's: vault_all): pressed anywhere, it does it; what it does in the link's ink
/// where a row says how it stands (under its title where the line has not the room), turning while it is done (not
/// done again then): `on_press` as it is pressed.
fn vault_do_row(
  c : @ui.Ctx,
  key : String,
  title : String,
  note : String,
  action : String,
  lacks? : Bool = false,
  busy? : Bool = false,
  on_press~ : () -> Unit,
) -> Unit {
  @sf.link_row(c, key, title, note~, lacks~, value=action, value_lit=true, chevron=false, tail=fn() { doing_mark(c, busy, None) }, on_press=fn() {
    if !busy {
      on_press()
    }
  })
  |> ignore
}

///|
/// The longest a grant of the viewer's secrets lasts where a secret says none (Lasts, DefaultLasts): the one now under
/// it; pressed, the library's choices, each with what it means (a sheet with a finger, a panel by it with a pointer).
fn vault_lasts_row(c : @ui.Ctx, core : Core, ws : String, mine : Json) -> Unit {
  let id = text(Some(mine), "id")
  let now = match vault_scopes.search(text(Some(mine), "lasts")) {
    Some(_) => text(Some(mine), "lasts")
    None => "chat"
  }
  let key = "vault-lasts"
  let from = c.id(key)
  let on = [("workspace", ws), ("vault", id)]
  @sf.link_row(c, key, @sf.t("web-pages.vault.lasts.title"), note=@sf.t("web-pages.vault.lasts." + now), tail=fn() {
    doing_mark(c, is_doing(core, ["vault.setLasts"], on), failed_of(core, ["vault.setLasts"], on))
  }, on_press=fn() {
    @sf.pick(
      @sf.t("web-pages.vault.lasts.title"),
      vault_scopes.map(fn(s) {
        @sf.choice(s, @sf.t("web-pages.vault.lasts." + s), note=@sf.t("web-pages.vault.lasts." + s + "Detail"))
      }),
      now,
      fn(picked) {
        if picked != now {
          vault_act(core, ws, "setLasts", [("vault", str(id)), ("lasts", str(picked))], @sf.t("web-pages.vault.lasts.what"))
        }
      },
      from=Of(from),
    )
  }) |> ignore
}

///|
/// The devices holding a vault's key (its name where there are more than one): how many, under it; where some new
/// ones have none yet, how many, in amber, given it from its end by its owner's device holding it.
fn vault_devices_row(c : @ui.Ctx, core : Core, ws : String, rv : Json?, many : Bool) -> Unit {
  let id = text(rv, "id")
  let title = if many { text(rv, "name") } else { @sf.t("android-settings.vault.devices") }
  let missing = count(rv, "missing")
  if missing == 0 {
    @sf.link_row(c, "", title, note=@sf.t("web-pages.vault.devicesHold", args=[("n", count(rv, "devices").to_string())]), goes=false)
    |> ignore
    return
  }
  let note = @sf.t("web-pages.vault.missing", args=[("n", missing.to_string())])
  // (given it from its owner's device holding it)
  if !(flag(rv, "mine") && flag(rv, "keyed")) {
    @sf.link_row(c, "", title, note~, lacks=true, goes=false) |> ignore
    return
  }
  let giving = is_doing(core, ["vault.addDevice"], [("workspace", ws), ("vault", id)])
  vault_do_row(c, "vault-give/" + id, title, note, @sf.t("web-pages.vault.addDevice"), lacks=true, busy=giving, on_press=fn() {
    vault_act(core, ws, "addDevice", [("vault", str(id))], @sf.t("web-pages.vault.addDeviceWhat"), done=@sf.t("web-pages.vault.addedDevice"))
  })
}

///|
/// Deleting a vault of the viewer's own (its name after where there are more than one), in red: asked first, saying
/// what goes with it.
fn vault_delete_row(c : @ui.Ctx, core : Core, ws : String, rv : Json?, many : Bool) -> Unit {
  let id = text(rv, "id")
  let on = [("workspace", ws), ("vault", id)]
  let label = @sf.t("web-pages.vault.deleteVault") + (if many { " · " + text(rv, "name") } else { "" })
  @sf.link_row(c, "vault-delete/" + id, label, danger=true, chevron=false, tail=fn() {
    doing_mark(c, is_doing(core, ["vault.delete"], on), failed_of(core, ["vault.delete"], on))
  }, on_press=fn() { if !is_doing(core, ["vault.delete"], on) { vault_delete_ask(core, ws, rv) } })
  |> ignore
}

///|
/// Asked before a vault of the viewer's own goes, saying what goes with it.
fn vault_delete_ask(core : Core, ws : String, rv : Json?) -> Unit {
  let id = text(rv, "id")
  let n = count(rv, "items")
  confirm(
    @sf.t("web-pages.vault.deleteTitle", args=[("name", text(rv, "name"))]),
    if n > 0 {
      @sf.t("web-pages.vault.deleteVaultBody", args=[("n", n.to_string())])
    } else {
      @sf.t("web-pages.vault.deleteVaultEmpty")
    },
    @sf.t("common.delete"),
    danger=true,
    fn() { vault_act(core, ws, "delete", [("vault", str(id))], @sf.t("web-pages.vault.deleteWhat"), done=@sf.t("web-pages.vault.deleted")) },
  )
}

///|
/// A vault this device has no key to (VaultSection's), under its name: that it has none, how to get one; 申请授权
/// (`vault.ask`: this device's certificate published anew, so the owner's devices are prompted for the key, or give it
/// at once where one holds it unsealed) and the recovery words typed where they can give it one.
fn vault_no_key(c : @ui.Ctx, core : Core, ws : String, rv : Json?) -> Unit {
  let recoverable = flag(rv, "recoverable")
  let id = text(rv, "id")
  @sf.section(c, text(rv, "name"), fn() {
    @sf.page_card(c, footed=true, fn() {
      @sf.card_lines(c, @sf.t("android-settings.vault.noKey"), note=@sf.t("android-settings.vault.noKeyHow"))
      @sf.card_foot(c, fn() {
        @sf.button(c, @sf.t("web-pages.vault.ask"), key="vault-ask/" + id, tone=Primary, busy=is_doing(core, ["vault.ask"], [("workspace", ws)]), on_press=fn() {
          @settings.act(core, @sf.t("web-pages.vault.askWhat"), "vault.ask", obj([("workspace", str(ws))]), done=@sf.t("web-pages.vault.asked"))
        }) |> ignore
        if recoverable {
          @sf.button(c, @sf.t("android-settings.vault.recover"), key="vault-recover/" + id, tone=Ghost, on_press=fn() {
            vault_recover_dialog(core, ws)
          }) |> ignore
        }
      })
    })
  })
}

///|
/// A vault waiting to be keyed anew (its row's `waits`: a device or member holding its key taken out of the lock),
/// under its name: on which station its owner's device gives it new keys, and that until then it is read and used, not
/// changed. Nothing to press: the owner's device does it by itself, and a change meanwhile says why it is refused.
fn vault_waits(c : @ui.Ctx, rv : Json?) -> Unit {
  let station = text(rv, "waits")
  let note = if flag(rv, "mine") {
    @sf.t("web-pages.vault.waits.mine", args=[("station", station)])
  } else {
    @sf.t("web-pages.vault.waits.theirs", args=[("owner", text(rv, "ownerName")), ("station", station)])
  }
  @sf.section(c, text(rv, "name"), fn() {
    @sf.page_card(c, fn() { @sf.card_lines(c, @sf.t("web-pages.vault.waits.title"), note~) })
  })
}

///|
/// A vault known by its items' names only (VaultSection), a section under its name: a web page's, or one this device
/// has no key to (how to get one is 密钥's: vault_no_key); each item's name (locked, that it is), how agents may ask
/// for it under it, a green dot at its end where agents are told of it.
fn vault_named(c : @ui.Ctx, core : Core, ws : String, row : Json) -> Unit {
  let rv = Some(row)
  let topic = (core.topic)("vaultItems", { "workspace": str(ws), "vault": str(text(rv, "id")) }).get()
  let list = items(topic.value, "items")
  @sf.section(c, text(rv, "name"), fn() {
    if list.length() == 0 {
      match topic.value {
        None =>
          match topic.error {
            Some(e) => @sf.page_note(c, error_text(e), bad=true)
            // (read the first time: rows' shapes where its card's rows will be, 4)
            None =>
              @sf.group_waiting(c, fn() { named_rows(c, vault_sample_items().map(Json::object)) }, text=@sf.t("common.reading"))
          }
        Some(_) => @sf.page_note(c, @sf.t("android-settings.vault.empty"))
      }
    } else {
      @sf.group(c, fn() { named_rows(c, list) })
    }
  })
}

///|
/// A vault's items known by their names only: each item's name (locked, that it is), how agents may ask for it under
/// it, a green dot at its end where agents are told of it.
fn named_rows(c : @ui.Ctx, list : Array[Json]) -> Unit {
  for it in list {
    let iv = Some(it)
    @sf.link_row(
      c,
      "",
      opt_text(iv, "name").unwrap_or(@sf.t("android-settings.vault.lockedItem")),
      note=text(iv, "agentText"),
      goes=false,
      tail?=if flag(iv, "listed") { Some(fn() { c.box(style=vt_listed, fn() {  }) |> ignore }) } else { None },
    )
    |> ignore
  }
}

///|
/// A library made up (the core's `vaults`), for what its pages show while it is read: one vault, its items to read.
fn vaults_sample() -> Json {
  { "plain": true, "available": true, "vaults": [{ "id": "sample", "name": Json::string(@sf.sample_words(4)), "keyed": true }] }
}

///|
/// A vault's items made up, for what is shown while they are read: their names, kinds and lines as long as theirs.
fn vault_sample_items() -> Array[Map[String, Json]] {
  [(6, 14), (9, 11), (5, 16)].mapi(fn(i, n) {
    {
      "id": Json::string("sample" + i.to_string()),
      "name": Json::string(@sf.sample_words(n.0)),
      "kindText": Json::string(@sf.sample_words(2)),
      "lineText": Json::string(@sf.sample_words(n.1)),
      "agentText": Json::string(@sf.sample_words(n.1)),
    }
  })
}

///|
let vt_glyph : Double = 16.0

///|
/// (actions: a card's buttons at its foot, 8 apart, its words before them)
// kept across runs: a value (no field of it changes)
pub let vt_actions : @ui.Style = @ui.css("row w=Full gap=S2 pt=S1 align=ACenter")

///|
/// 全部密钥's field: over its list, as wide as its card, 10 above it.
// kept across runs: a value (no field of it changes)
let vt_find : @ui.Style = @ui.css("w=Full pb=S2_5")

///|
/// (requests: each one's card, 10 apart as the page's cards: pagesCss.card)
// kept across runs: a value (no field of it changes)
let vt_requests : @ui.Style = @ui.css("w=Full gap=S2_5")

///|
/// (a request's card, as wide as the page: AskCard fill)
// kept across runs: a value (no field of it changes)
let vt_request : @ui.Style = @ui.css("w=Full")

///|
/// Narrow: the requests' cards in the page's room, 10 apart.
// kept across runs: a value (no field of it changes)
let vt_requests_narrow : @ui.Style = @ui.css("w=Full pb=S2_5 gap=S2_5")

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
/// 全部密钥 (VaultItems) made once as nodes in node `v` (page_node, as vault_node is): what the library keeps
/// (vault_all_node), 添加 at its head while it is there to be used; what has to come first, as on 密钥.
pub fn vault_items_node(
  v : @view.View,
  core : Core,
  here : () -> Here,
  on_back~ : () -> Unit,
  frame~ : () -> PageFrame,
  said? : (@sf.PageSaid) -> Unit,
  width? : () -> Double,
  tips? : @sf.TipLayer,
) -> Unit {
  let ws = fn() { here().workspace }
  let view = fn() { (core.topic)("vaults", { "workspace": str(ws()) }).get() }
  let usable = fn() { vault_first_keys(ws(), view().value) is None }
  @sf.page_node(
    v,
    fn() { @sf.t("web-pages.vault.all") },
    on_back~,
    frame~,
    said?,
    width?,
    tips?,
    actions=fn(a) {
      a.show(usable, fn(s) {
        s.box(fn(k) {
          let add = fn() {
            let (x, y, w, h) = k.placed_window_now()
            vault_add(core, @signals.untracked(here), from=At(x, y, w, h))
          }
          k.pick(fn() { @sf.look_node(k) }, fn(p, look) {
            match look {
              Wide => @sf.button_node(p, fn() { @sf.t("web-pages.vault.add") }, add, tone=Ghost, icon="plus") |> ignore
              Narrow => @sf.icon_button_node(p, "plus", fn() { @sf.t("web-pages.vault.add") }, add) |> ignore
            }
          })
          // (a fixture's mode's 添加, from this one, at the moment the page is made: laid out by then, so it stands beside
          // it as when it is pressed)
          if fx_vault_add_up.val {
            fx_vault_add_up.val = false
            k.laid_before_causes()
            k.at_moment(k.logic_at(), add) |> ignore
          }
        })
        |> ignore
      })
    },
    fn() {
      match vault_first_keys(ws(), view().value) {
        Some(keys) => keys
        None => ["all"]
      }
    },
    fn(b, key) {
      if vault_first_node(b, core, here, view, key, fn(s, quiet, sample) {
          vault_all_node(s, quiet, ws, fn() { sample }, tips)
        }) {
        return
      }
      vault_all_node(b, core, ws, fn() { view().value }, tips)
    },
  )
}

///|
/// What 密钥 and 全部密钥 show before the library, by their keys, as the core's `vaults` (`v`) says where the viewer
/// stands: the recovery words to write down ("words"); waiting for the core ("waiting"); a web page's names
/// ("read-only", then "named/<vault>" each); what has to come first ("needs-lock", "not-signer", "off"). None where
/// the library is there to be used (in plain text on the station, or locked, signed and set up here).
fn vault_first_keys(ws : String, v : Json?) -> Array[String]? {
  // (the words as they are now: read, so that what reads this follows them as they come or go)
  recovery_words_turned.get() |> ignore
  match v {
    _ if recovery_words.get(ws) is Some(_) => Some(["words"])
    None => Some(["waiting"])
    Some(_) if flag(v, "plain") => None
    Some(_) if !flag(v, "available") => Some(["read-only"] + items(v, "vaults").map(fn(r) { "named/" + text(Some(r), "id") }))
    Some(_) if !flag(v, "locked") => Some(["needs-lock"])
    Some(_) if !flag(v, "canSign") => Some(["not-signer"])
    Some(_) if !flag(v, "setUp") => Some(["off"])
    Some(_) => None
  }
}

///|
/// The block `key` of what comes before the library (vault_first_keys) in node `b`, as `view` (the core's `vaults`)
/// says it now; while it is waited for, what the page holds (`shown`: its blocks for a library's view, by a core that
/// answers nothing) of a made-up library, in its bones. False where `key` is none of those.
fn vault_first_node(
  b : @view.View,
  core : Core,
  here : () -> Here,
  view : () -> @settings.Read,
  key : String,
  shown : (@view.View, Core, Json?) -> Unit,
) -> Bool {
  let ws = fn() { here().workspace }
  match key {
    "words" => vault_words_node(b, ws)
    "waiting" =>
      @sf.waiting_node(b, fn(s) { shown(s, core.quiet(), Some(vaults_sample())) }, error=fn() {
        match view().error {
          Some(e) => error_text(e)
          None => ""
        }
      })
    "read-only" => @sf.page_note_node(b, fn() { @sf.t("android-settings.vault.readOnly") })
    "needs-lock" => vault_gate_node(b, core, "web-pages.vault.needsLock", "web-pages.vault.needsLockWhy")
    "not-signer" => vault_gate_node(b, core, "web-pages.vault.notSigner", "web-pages.vault.notSignerWhy")
    "off" => vault_off_node(b, core, ws)
    k if k.has_prefix("named/") => {
      let id = k.exact_view(start=6).to_owned()
      vault_named_node(b, core, ws, fn() { items(view().value, "vaults").iter().find_first(fn(r) { text(Some(r), "id") == id }) })
    }
    _ => return false
  }
  true
}

///|
/// What the vault waits for before anything else (Gate, ToSecurity): said on a card (`title`, `why`: their words'
/// keys), with the way there at its foot.
fn vault_gate_node(b : @view.View, core : Core, title : String, why : String) -> Unit {
  @sf.page_card_node(b, footed=true, fn(k) {
    @sf.card_lines_node(k, fn() { @sf.t(title) }, note=fn() { @sf.t(why) })
    @sf.card_foot_node(k, fn(f) {
      @sf.button_node(f, fn() { @sf.t("web-pages.vault.toSecurity") }, fn() { (core.push)(Security) }, tone=Primary, card_words=true)
      |> ignore
    })
  })
}

///|
/// Not set up on this device yet (Off): what it is, what agents do with it and how it is opened, a line each; 开启
/// (`vault.setup`) at its foot.
fn vault_off_node(b : @view.View, core : Core, ws : () -> String) -> Unit {
  @sf.page_card_node(b, footed=true, fn(k) {
    @sf.card_lines_node(
      k,
      fn() { @sf.t("android-settings.vault.offTitle") },
      words=fn() { @sf.t("android-settings.vault.offWhat") },
      note=fn() { @sf.t("android-settings.vault.offAgents") + "\n" + @sf.t("android-settings.vault.offUnlock") },
    )
    @sf.card_foot_node(k, fn(f) {
      @sf.button_node(
        f,
        fn() { @sf.t("android-settings.vault.turnOn") },
        fn() { vault_setup(core, @signals.untracked(ws)) },
        tone=Primary,
        busy=fn() { is_doing(core, ["vault.setup"], [("workspace", ws())]) },
        card_words=true,
      )
      |> ignore
    })
  })
}

///|
/// The 24 recovery words, numbered, three to a row, for the person to copy out (Words): why, and that they are shown
/// this once (the core gives them the once); written down, the person says so at its foot.
fn vault_words_node(b : @view.View, ws : () -> String) -> Unit {
  let words = fn() {
    recovery_words_turned.get() |> ignore
    recovery_words.get(ws()).unwrap_or([])
  }
  @sf.page_card_node(b, footed=true, fn(k) {
    @sf.card_lines_node(
      k,
      fn() { @sf.t("android-settings.vault.wordsTitle") },
      words=fn() { @sf.t("android-settings.vault.wordsWhy") },
      note=fn() { @sf.t("android-settings.vault.wordsOnce") },
    )
    k.box(fn(all) {
      @sf.style_node(all, fn() { vt_words })
      all.each(fn() { Array::makei((words().length() + 2) / 3, fn(r) { r }) }, fn(r) { r }, fn(line, r) {
        line.box(fn(l) {
          @sf.style_node(l, fn() { vt_words_row })
          for i in 0..<3 {
            let at = fn() { r.get() * 3 + i }
            l.box(fn(w) {
              @sf.style_node(w, fn() { vt_word }, in_row=true)
              w.show(fn() { at() < words().length() }, fn(s) {
                s.row(Is(true)).gap(Is(vt_word_gap)).lines_up(Is(Some(End))) |> ignore
                s.box(fn(n) {
                  @sf.style_node(n, fn() { vt_word_number })
                  vt_mono_node(n, fn() { (at() + 1).to_string() }, Meta, fn() { @sf.theme().p.subtle })
                })
                |> ignore
                vt_mono_node(s, fn() { words().get(at()).unwrap_or("") }, Body, fn() { @sf.theme().p.text })
              })
            })
            |> ignore
          }
        })
        |> ignore
      })
    })
    |> ignore
    @sf.card_foot_node(k, fn(f) {
      @sf.button_node(
        f,
        fn() { @sf.t("android-settings.vault.wordsDone") },
        fn() {
          recovery_words.remove(@signals.untracked(ws))
          recovery_words_changed()
        },
        tone=Primary,
        card_words=true,
      )
      |> ignore
    })
  })
}

///|
/// Words in the code face on one line (mono's, as a node) in `parent`, `words` as they are now, `size` (the theme's as
/// the node is made), in `ink`.
fn vt_mono_node(parent : @view.View, words : () -> String, size : @ui.TextSize, ink : () -> Int64) -> Unit {
  parent.box(fn(w) {
    // (its size as the theme's is now: followed, the system's size of words changed)
    let look = fn() -> @view.WordsLook {
      let (px, line) = @ui.tree_theme().text_size(size)
      { size: px, weight: 400, line, wrap: false, tracking: @view.letters_own, balance: false, max_lines: 0 }
    }
    w
    .words_runs(By(fn() { [@ui.span(words(), mono=true)] }), look=@signals.untracked(look))
    .words_look(By(look))
    .ink(By(ink))
    |> ignore
  })
  |> ignore
}

///|
/// What 全部密钥's field looks for: words of a secret's row (its name, its kind, how it is given: its host, its
/// variable; where it was last used).
// kept across runs: what the page's field holds, the person's; vault_reset empties it
let vault_find : @ui.Field = @ui.Field::new()

///|
/// Whether 全部密钥's profiles' accounts are shown (folded at its foot till then).
// kept across runs: the person's; vault_reset folds them
let vault_accounts_open : @signals.Signal[Bool] = @signals.signal(false)

///|
fn vault_reset() -> Unit {
  vault_find.set("")
  vault_accounts_open.set(false)
}

///|
/// A row of 全部密钥: a vault's secret ("it/<vault>/<item>"), or those of a vault it does not name ("hidden/<vault>").
#derive(Eq)
priv enum VaultRow {
  Secret(Json, Json, Bool, Bool)
  Hidden(Json, String, String, Bool)
}

///|
/// 全部密钥 (LibraryItems), as a password manager's list (the user, 2026-10-26: a section a kind of one row each was
/// 「信息密度极低，找也找不到有意义的东西」), in node `b`, as the library's view (`view`) and each vault's items say them
/// now: a field to find one by any of its words; then every one on one list card, a row each: its mark (a secret's
/// kind), its name, and under it its kind and what is worth knowing of it (a secret's way to an agent and its last use,
/// the core's lineText), each leading to its page: each vault's secrets (a vault this device has no key to, the names
/// it is told, going nowhere), locked, a row of those it does not name; then the profiles' accounts on a card of their
/// own, folded under a row naming them (they are the profiles' pages' first: the user, 2026-10-26, 「订阅一般在
/// profiles 看过了」), open where what is looked for is among them.
fn vault_all_node(b : @view.View, core : Core, ws : () -> String, view : () -> Json?, tips : @sf.TipLayer?) -> Unit {
  ignore(tips)
  let find = fn() { vault_find.text().trim(chars=" ").to_lower() }
  let shows = fn(words : Array[String]) {
    let f = find()
    f == "" || words.iter().any(fn(w) { w.to_lower().contains(f) })
  }
  // (a row's line: what is said of it, those words that are not empty, a dot between)
  let said = fn(words : Array[String]) { words.filter(fn(w) { w != "" }).join(" · ") }
  let vaults = fn() { items(view(), "vaults") }
  let topic_of = fn(rv : Json?) { (core.topic)("vaultItems", { "workspace": str(ws()), "vault": str(text(rv, "id")) }).get() }
  let reading = fn() { vaults().iter().any(fn(r) { topic_of(Some(r)).value is None }) }
  // each vault's secrets, by name (the core's order); those it does not name, a row
  let rows = fn() {
    let plain = flag(view(), "plain")
    let many = vaults().length() > 1
    let out : Array[(String, VaultRow)] = []
    let unnamed : Array[(String, VaultRow)] = []
    for row in vaults() {
      let rv = Some(row)
      let listed = topic_of(rv).value
      if listed is None {
        continue
      }
      let list = items(listed, "items")
      let keyed = plain || flag(rv, "keyed")
      for it in list {
        let iv = Some(it)
        if has(iv, "name") && shows([text(iv, "name"), text(iv, "kindText"), text(iv, "lineText"), text(iv, "howText")]) {
          out.push(("it/" + text(rv, "id") + "/" + text(iv, "id"), Secret(row, it, many, keyed)))
        }
      }
      let hidden = list.filter(fn(x) { !has(Some(x), "name") })
      if hidden.length() > 0 {
        unnamed.push(
          (
            "hidden/" + text(rv, "id"),
            Hidden(row, text(Some(hidden[0]), "id"), @sf.t("web-pages.vault.hidden", args=[("n", hidden.length().to_string())]), keyed),
          ),
        )
      }
    }
    out + unnamed
  }
  // (the secrets found by their names: not found, whatever a vault does not name)
  let named = fn() { rows().iter().filter(fn(r) { r.1 is Secret(_, _, _, _) }).count() }
  // the profiles' accounts, as the profiles list them: each its key, its title, what is said under it, its trouble, its
  // group, where it goes
  let accounts = fn() {
    let out : Array[(String, String, String, String, String, @settings.Route)] = []
    for g in profile_groups(items((core.topic)("profiles", { "scope": str(ws()) }).get().value, "items")) {
      for e in g.1 {
        let ev = Some(e)
        let p = field(ev, "profile")
        // (a subscription by its account, a key by its name: the core's)
        let title = if text(ev, "title") == "" { text(p, "name") } else { text(ev, "title") }
        if shows([title, g.0, text(ev, "where")]) {
          out.push(
            (
              text(ev, "key"),
              title,
              said([g.0, text(ev, "where")]),
              if text(p, "checkTone") == "red" { text(p, "checkText") } else { "" },
              text(ev, "group"),
              Profile(text(ev, "station"), text(p, "id")),
            ),
          )
        }
      }
    }
    out
  }
  let kept_accounts = fn() {
    let mut n = 0
    for g in profile_groups(items((core.topic)("profiles", { "scope": str(ws()) }).get().value, "items")) {
      n += g.1.length()
    }
    n
  }
  b.box(fn(col) {
    col.box(fn(f) {
      @sf.style_node(f, fn() { vt_find })
      @sf.input_node(f, vault_find, placeholder=@sf.t("web-pages.vault.find")) |> ignore
    })
    |> ignore
    // (each secret by its vault and id: one added or taken out comes and goes where it is)
    col.show(fn() { rows().length() > 0 }, fn(s) {
      @sf.group_node(s, fn(g) { g.each(rows, fn(r) { r.0 }, fn(row, r) { vault_row_node(row, core, ws, fn() { r.get().1 }) }) })
    })
    // the accounts, folded under a row naming them (open where what is looked for is among them)
    col.show(fn() { accounts().length() > 0 }, fn(s) {
      let open = fn() { vault_accounts_open.get() || find() != "" }
      @sf.group_node(s, fn(g) {
        // (its words where the names are, as those of the secrets' row of those it does not name)
        @sf.link_row_node(
          g,
          fn() { @sf.t("web-pages.vault.accounts") },
          fn() {
            if @signals.untracked(find) == "" {
              vault_accounts_open.set(!@signals.untracked(open))
            }
          },
          note=fn() { if open() { "" } else { accounts().map(fn(a) { a.1 }).join("、") } },
          folds=open,
          lead=LeadMade(fn(l) { l.width(Is(Some(vt_no_mark_w))) |> ignore }),
        )
        g.show(open, fn(o) {
          o.each(accounts, fn(a) { a.0 }, fn(row, a) {
            let av = fn() { a.get() }
            @sf.link_row_node(
              row,
              fn() { av().1 },
              fn() { (core.push)(@signals.untracked(av).5) },
              note=fn() { av().2 },
              trouble=fn() { av().3 },
              lead=LeadMade(fn(l) { l.pick(fn() { av().4 }, fn(m, group) { vt_group_mark_node(m, group) }) }),
            )
          })
        })
      })
    })
    col.pick(
      fn() {
        if reading() {
          1
        } else if named() + accounts().length() == 0 && find() != "" {
          2
        } else if rows().length() + kept_accounts() == 0 {
          3
        } else {
          0
        }
      },
      fn(p, what) {
        match what {
          // (a vault's secrets still read: rows' shapes under what is shown)
          1 =>
            @sf.waiting_node(p, fn(w) {
              @sf.group_node(w, fn(g) {
                for x in vault_sample_items() {
                  vault_row_node(g, core.quiet(), ws, fn() { Secret(Json::null(), Json::object(x), false, true) })
                }
              })
            }, note=fn() { { reading: true, text: @sf.t("common.reading"), failing: [] } })
          2 =>
            @sf.page_note_node(p, fn() { @sf.t("web-pages.vault.noMatch", args=[("q", vault_find.text().trim(chars=" ").to_owned())]) })
          3 => @sf.page_note_node(p, fn() { @sf.t("web-pages.vault.empty") })
          _ => ()
        }
      },
    )
  })
  |> ignore
}

///|
/// A row of 全部密钥 (`r`, as it is now) on its card: a secret (its kind's mark, its name, its kind, its vault where
/// there are more than one, how an agent gets it, when and where it was last used: the core's; pressed, its page where
/// it can be opened here), or those of a vault it does not name (its words where the names are; unlocked by opening one
/// of them, the vault's key kept a while, every name shown; one this device has no key to, said alone).
fn vault_row_node(row : @view.View, core : Core, ws : () -> String, r : () -> VaultRow) -> Unit {
  let how_now = fn() {
    match r() {
      Secret(_, _, _, keyed) => if keyed { 0 } else { 1 }
      Hidden(_, _, _, keyed) => if keyed { 2 } else { 3 }
    }
  }
  row.pick(how_now, fn(p, how) {
    match how {
      0 | 1 => {
        let parts = fn() {
          match r() {
            Secret(v, i, many, _) => (Some(v), Some(i), many)
            _ => (None, None, false)
          }
        }
        let keyed = how == 0
        @sf.link_row_node(
          p,
          fn() { text(parts().1, "name") },
          fn() {
            let (rv, iv, _) = @signals.untracked(parts)
            (core.push)(VaultItem(text(rv, "id"), text(iv, "id")))
          },
          note=fn() {
            let (rv, iv, many) = parts()
            [text(iv, "kindText"), if many { text(rv, "name") } else { "" }, if keyed { text(iv, "lineText") } else { text(iv, "agentText") }]
            .filter(fn(w) { w != "" })
            .join(" · ")
          },
          lead=LeadMade(fn(l) {
            l.pick(fn() { @settings.kind_icon(text(parts().1, "kind")) }, fn(m, icon) {
              @sf.icon_node(m, icon, vt_glyph, By(fn() { @sf.theme().p.text })) |> ignore
            })
          }),
          goes=keyed,
        )
      }
      _ => {
        let words = fn() {
          match r() {
            Hidden(_, _, w, _) => w
            _ => ""
          }
        }
        let lead : @sf.RowLead = LeadMade(fn(l : @view.View) { l.width(Is(Some(vt_no_mark_w))) |> ignore })
        if how == 3 {
          @sf.link_row_node(p, words, fn() {  }, lead~, goes=false)
        } else {
          @sf.link_row_node(
            p,
            words,
            fn() {
              match @signals.untracked(r) {
                Hidden(_, first, _, _) =>
                  @settings.act(core, @sf.t("web-pages.vault.unlockWhat"), "vault.open", obj([("workspace", str(@signals.untracked(ws))), ("item", str(first))]))
                _ => ()
              }
            },
            value=fn() { @sf.t("web-pages.vault.unlock") },
            value_lit=true,
            chevron=false,
            lead~,
          )
        }
      }
    }
  })
}

///|
/// Where a row's mark would be, kept for one with none (w=S4): its words where the others' names are.
let vt_no_mark_w : Double = 16.0

///|
/// vt_word's room between a word's number and it (gap=S2).
let vt_word_gap : Double = 8.0

///|
/// A vault known by its items' names only (`rv`; VaultSection), a section under its name: a web page's, or one this
/// device has no key to (how to get one is 密钥's: vault_no_key_node); each item's name (locked, that it is), how agents
/// may ask for it under it, a green dot at its end where agents are told of it; while they are read the first time,
/// rows of made-up ones in their bones.
fn vault_named_node(b : @view.View, core : Core, ws : () -> String, rv : () -> Json?) -> Unit {
  let topic = fn() { (core.topic)("vaultItems", { "workspace": str(ws()), "vault": str(text(rv(), "id")) }).get() }
  let list = fn() { items(topic().value, "items") }
  @sf.section_node(b, fn() { text(rv(), "name") }, fn(s) {
    s.pick(
      fn() {
        if list().length() > 0 {
          0
        } else {
          match topic().value {
            Some(_) => 1
            None => if topic().error is Some(_) { 2 } else { 3 }
          }
        }
      },
      fn(p, what) {
        match what {
          0 => @sf.group_node(p, fn(g) { named_rows_node(g, list) })
          1 => @sf.page_note_node(p, fn() { @sf.t("android-settings.vault.empty") })
          2 => @sf.page_note_node(p, fn() { topic().error.map(error_text).unwrap_or("") }, bad=fn() { true })
          // (read the first time: rows' shapes where its card's rows will be)
          _ =>
            @sf.waiting_node(p, fn(w) {
              @sf.group_node(w, fn(g) { named_rows_node(g, fn() { vault_sample_items().map(Json::object) }) })
            })
        }
      },
    )
  })
}

///|
/// A vault's items known by their names only (`list`, as it is now), on a group's card `g`: each item's name (locked,
/// that it is), how agents may ask for it under it, a green dot at its end where agents are told of it.
fn named_rows_node(g : @view.View, list : () -> Array[Json]) -> Unit {
  g.each(fn() { list().mapi(fn(i, x) { (i, x) }) }, fn(x) { x.0 }, fn(row, x) {
    let iv = fn() { Some(x.get().1) }
    @sf.link_row_node(
      row,
      fn() { opt_text(iv(), "name").unwrap_or(@sf.t("android-settings.vault.lockedItem")) },
      fn() {  },
      note=fn() { text(iv(), "agentText") },
      goes=false,
      tail=fn(e) { e.box(fn(d) { @sf.style_node(d, fn() { vt_listed }) }) |> ignore },
      tail_shown=fn() { flag(iv(), "listed") },
    )
  })
}

///|
/// What a profile's group is by (@settings.group_mark's) as a node: a key's, else its provider's, 16 across.
fn vt_group_mark_node(parent : @view.View, group : String) -> Unit {
  match group {
    "key" => @sf.icon_node(parent, "key", vt_glyph, By(fn() { @sf.theme().p.text })) |> ignore
    // signed in to an account: its provider's
    "kimi" => @sf.provider_logo_node(parent, "claude", "api-provider", vt_glyph, "kimi") |> ignore
    "opencode" => @sf.provider_logo_node(parent, "claude", "opencode-go", vt_glyph, "") |> ignore
    // a subscription: its vendor's, by the runtime it is (ChatGPT's Codex; SuperGrok's xAI, Cursor's, Devin's)
    "chatgpt" => @sf.provider_logo_node(parent, "codex", "subscription", vt_glyph, "") |> ignore
    "" => @sf.provider_logo_node(parent, "claude", "subscription", vt_glyph, "") |> ignore
    g => @sf.provider_logo_node(parent, g, "subscription", vt_glyph, "") |> ignore
  }
}
