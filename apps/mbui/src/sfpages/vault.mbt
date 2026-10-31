// 密钥, one page in every frame and the same on every width (the user, 2026-10-26: 「这个页面需要整体重新设计，现在乱得
// 一批」: its state a card of its own, the longest approval a heading, a paragraph and three cards of their own, each on
// an edge of its own, what it keeps under the fold), and 全部密钥 under it. What has to come first (security mode, this
// device signing, this device set up, the recovery words written down): a card alone on either, with the way on. Set
// up, 密钥 is what waits on the viewer and how the library stands, not what it keeps (「密钥管理不需要入口做这么浅，因为
// 平时不会手动操作，顶多就是类似 1p，进去看一眼复制一下」): the requests waiting on the viewer first (each one's card, as
// in its chat); a row to 全部密钥; how its secrets are kept, a row each on one list card, each what it is with how it
// stands under it (encrypted or not, and unlocked here a while; those still in plain text from before; the longest an
// approval lasts, picked through the presenters; the devices holding its key); deleting the vault in red at its foot,
// asked first; the stations that refused it. 全部密钥 is what it keeps, a section a kind (the profiles' accounts as the
// profiles list them, then each vault's secrets), each a row to its page, and 添加 at its head. Made of the library's
// page parts (@sf.section, group, link_row, page_card), laid out by the page's width (page_look.mbt). Adding, a
// secret's editor and the recovery words typed are the presenters' (vault_dialogs.mbt).

///|
/// 密钥 (VaultSettings, VaultScreen): as the core's `vaults` says where the viewer stands.
pub fn vault_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame) -> Unit {
  let look = look_of(c)
  let ws = here.workspace
  let v = (core.topic)("vaults", { "workspace": str(ws) }).value
  let body = match vault_first(c, core, ws, fn(core, v) { vault_library(c, core, look, ws, v) }) {
    Some(first) => first
    None => vault_library(c, core, look, ws, v)
  }
  @sf.page(c, on_back=core.pop, frame~, "vault", @sf.t("web-pages.vault.title"), lead=@sf.t("web-pages.vault.lead"), body)
}

///|
/// 全部密钥 (VaultItems): what the library keeps, 添加 at its head; what has to come first, as on 密钥.
pub fn vault_items_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame) -> Unit {
  let look = look_of(c)
  let ws = here.workspace
  let v = (core.topic)("vaults", { "workspace": str(ws) }).value
  let (body, usable) = match vault_first(c, core, ws, fn(core, v) { vault_all(c, core, ws, v) }) {
    Some(first) => (first, false)
    None => (vault_all(c, core, ws, v), true)
  }
  let add = fn() {
    let pressed = match look {
      Wide => @sf.button(c, @sf.t("web-pages.vault.add"), key="vault-add", tone=Ghost, icon="plus")
      Narrow => @sf.icon_button(c, "plus", key="vault-add", round=true, label=@sf.t("web-pages.vault.add"))
    }
    // (or a fixture's mode's, from it all the same)
    if pressed || fx_vault_add_up.val {
      fx_vault_add_up.val = false
      vault_add(core, here, from=Of(c.id("vault-add")))
    }
  }
  @sf.page(c, on_back=core.pop, frame~, "vault-items", @sf.t("web-pages.vault.all"), actions?=if usable { Some(add) } else { None }, body)
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
  let topic = (core.topic)("vaults", { "workspace": str(ws) })
  let v = topic.value
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
      if @sf.button(c, @sf.t("web-pages.vault.toSecurity"), key="vault-to-security", tone=Primary) {
        (core.push)(Security)
      }
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
  if !plain && vaults.length() == 0 {
    out.push(fn() {
      @sf.page_card(c, footed=true, fn() {
        @sf.card_lines(c, @sf.t("web-pages.vault.none"))
        @sf.card_foot(c, fn() {
          if @sf.button(c, @sf.t("web-pages.vault.setUp"), key="vault-create", tone=Primary, busy=is_doing(core, ["vault.create"], [("workspace", ws)])) {
            @settings.act(core, @sf.t("web-pages.vault.createWhat"), "vault.create", obj([("workspace", str(ws)), ("name", str(@sf.t("web-pages.vault.personal")))]))
          }
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
  // what it keeps (the profiles' accounts, the vaults' secrets), a page of its own
  out.push(fn() {
    @sf.group(c, fn() {
      if @sf.link_row(c, "vault-all", @sf.t("web-pages.vault.all")) {
        (core.push)(VaultItems)
      }
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
/// What 全部密钥's field looks for: words of a secret's row (its name, its kind, how it is given: its host, its
/// variable; where it was last used).
// kept across runs: what the page's field holds, the person's; vault_reset empties it
let vault_find : @ui.Field = @ui.Field::new()

///|
/// Whether 全部密钥's profiles' accounts are shown (folded at its foot till then).
// kept across runs: the person's; vault_reset folds them
let vault_accounts_open : Ref[Bool] = Ref(false)

///|
fn vault_reset() -> Unit {
  vault_find.set("")
  vault_accounts_open.val = false
}

///|
/// 全部密钥 (LibraryItems), as a password manager's list (the user, 2026-10-26: a section a kind of one row each was
/// 「信息密度极低，找也找不到有意义的东西」): a field to find one by any of its words; then every one on one list card, a
/// row each: its mark (the profile's service; a secret's kind), its name, and under it its kind and what is worth
/// knowing of it (an account's station, and what is wrong with it; a secret's way to an agent and its last use, the
/// core's lineText), each leading to its page: each vault's secrets (a vault this device has no key to, the names it is
/// told, going nowhere), locked, a row of those it does not name; then the profiles' accounts on a card of their own,
/// folded under a row naming them (they are the profiles' pages' first: the user, 2026-10-26, 「订阅一般在 profiles
/// 看过了」), open where what is looked for is among them.
fn vault_all(c : @ui.Ctx, core : Core, ws : String, v : Json?) -> Array[() -> Unit] {
  let th = @sf.theme()
  let plain = flag(v, "plain")
  let vaults = items(v, "vaults")
  let many = vaults.length() > 1
  let find = vault_find.text().trim(chars=" ").to_lower()
  let shows = fn(words : Array[String]) { find == "" || words.iter().any(fn(w) { w.to_lower().contains(find) }) }
  // (a row's line: what is said of it, those words that are not empty, a dot between)
  let said = fn(words : Array[String]) { words.filter(fn(w) { w != "" }).join(" · ") }
  let rows : Array[(String, () -> Unit)] = []
  let mut reading = false
  // the profiles' accounts, as the profiles list them (folded at the foot: seen on the profiles' pages)
  let accounts : Array[() -> Unit] = []
  let account_names : Array[String] = []
  let mut kept_accounts = 0
  for g in profile_groups(items((core.topic)("profiles", { "scope": str(ws) }).value, "items")) {
    for e in g.1 {
      let ev = Some(e)
      let p = field(ev, "profile")
      // (a subscription by its account, a key by its name: the core's)
      let title = if text(ev, "title") == "" { text(p, "name") } else { text(ev, "title") }
      kept_accounts += 1
      if !shows([title, g.0, text(ev, "where")]) {
        continue
      }
      account_names.push(title)
      accounts.push(fn() {
        if @sf.link_row(
            c,
            "vault-profile/" + text(ev, "key"),
            title,
            note=said([g.0, text(ev, "where")]),
            trouble=if text(p, "checkTone") == "red" { text(p, "checkText") } else { "" },
            lead=fn() { @settings.group_mark(c, text(p, "group")) },
          ) {
          (core.push)(Profile(text(ev, "station"), text(p, "id")))
        }
      })
    }
  }
  // each vault's secrets, by name (the core's order); those it does not name, a row
  let unnamed : Array[(String, () -> Unit)] = []
  for row in vaults {
    let rv = Some(row)
    let topic = (core.topic)("vaultItems", { "workspace": str(ws), "vault": str(text(rv, "id")) })
    if topic.value is None {
      reading = true
      continue
    }
    let list = items(topic.value, "items")
    let keyed = plain || flag(rv, "keyed")
    for it in list {
      let iv = Some(it)
      if !has(iv, "name") || !shows([text(iv, "name"), text(iv, "kindText"), text(iv, "lineText"), text(iv, "howText")]) {
        continue
      }
      rows.push(("it/" + text(rv, "id") + "/" + text(iv, "id"), fn() { vault_item_row(c, core, rv, iv, many, keyed) }))
    }
    let hidden = list.filter(fn(x) { !has(Some(x), "name") })
    if hidden.length() > 0 {
      let words = @sf.t("web-pages.vault.hidden", args=[("n", hidden.length().to_string())])
      unnamed.push(("hidden/" + text(rv, "id"), fn() {
        // (its words where the names are; unlocked by opening one of them: the vault's key kept a while, every name
        // shown; one this device has no key to, said alone)
        let lead = fn() { c.box(style=vt_no_mark, fn() {  }) |> ignore }
        if !keyed {
          @sf.link_row(c, "", words, lead~, goes=false) |> ignore
        } else if @sf.link_row(c, "vault-unlock/" + text(rv, "id"), words, value=@sf.t("web-pages.vault.unlock"), value_lit=true, chevron=false, lead~) {
          @settings.act(core, @sf.t("web-pages.vault.unlockWhat"), "vault.open", obj([("workspace", str(ws)), ("item", str(text(Some(hidden[0]), "id")))]))
        }
      }))
    }
  }
  let out : Array[() -> Unit] = [
    fn() {
      c.box(style=vt_find, fn() {
        @sf.input(c, "vault-find", placeholder=@sf.t("web-pages.vault.find"), field=vault_find) |> ignore
      })
      |> ignore
    },
  ]
  if rows.length() + unnamed.length() > 0 {
    out.push(fn() {
      // (each secret by its vault and id: one added or taken out comes and goes where it is, @sf.group_rows)
      @sf.group(c, fn() { @sf.group_rows(c, "vault-items/" + ws, rows + unnamed) })
    })
  }
  // the accounts, folded under a row naming them (open where what is looked for is among them)
  if accounts.length() > 0 {
    let open = vault_accounts_open.val || find != ""
    out.push(fn() {
      @sf.group(c, fn() {
        // (its words where the names are, as those of the secrets' row of those it does not name)
        if @sf.link_row(
            c,
            "vault-accounts",
            @sf.t("web-pages.vault.accounts"),
            note=if open { "" } else { account_names.join("、") },
            folds=open,
            lead=fn() { c.box(style=vt_no_mark, fn() {  }) |> ignore },
          ) &&
          find == "" {
          vault_accounts_open.val = !open
        }
        if open {
          for r in accounts {
            r()
          }
        }
      })
    })
  }
  if reading {
    // (a vault's secrets still read: rows' shapes under what is shown, Vault.tsx's Waiting, 3 dense)
    out.push(fn() { @sf.group_waiting(c, fn() { vault_items_sample(c, core) }, text=@sf.t("common.reading")) })
  } else if rows.length() + accounts.length() == 0 && find != "" {
    out.push(fn() { @sf.page_note(c, @sf.t("web-pages.vault.noMatch", args=[("q", vault_find.text().trim(chars=" ").to_owned())])) })
  } else if rows.length() + unnamed.length() + kept_accounts == 0 {
    out.push(fn() { @sf.page_note(c, @sf.t("web-pages.vault.empty")) })
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
    filename: text(save, "filename"),
    typed: flag(save, "typed"),
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
      if vault_do_row(c, "vault-turn-on", @sf.t("web-pages.vault.lib.plain"), @sf.t("web-pages.vault.lib.plainWhy"), @sf.t("web-pages.vault.lib.turnOn"), lacks=true) {
        (core.push)(Security)
      }
    } else {
      let open = vaults.iter().any(fn(x) { flag(Some(x), "open") })
      let sealed = @sf.t("web-pages.vault.lib.sealed")
      if open {
        let locking = is_doing(core, ["vault.lock"], [("workspace", ws)])
        if vault_do_row(c, "vault-lock", sealed, @sf.t("web-pages.vault.opened"), @sf.t("web-pages.vault.lockNow"), busy=locking) {
          vault_act(core, ws, "lock", [], @sf.t("web-pages.vault.lockNow"))
        }
      } else {
        @sf.link_row(c, "", sealed, note=@sf.t("web-pages.vault.lib.sealedWhy"), goes=false) |> ignore
      }
      if left > 0 {
        let moving = is_doing(core, ["vault.migrate"], [("workspace", ws)])
        if vault_do_row(
            c,
            "vault-migrate",
            @sf.t("web-pages.vault.migrate.title", args=[("n", left.to_string())]),
            @sf.t("android-settings.vault.migrate.body"),
            @sf.t("web-pages.vault.migrate.go"),
            lacks=true,
            busy=moving,
          ) {
          @settings.act(core, @sf.t("web-pages.vault.migrate.what"), "vault.migrate", obj([("workspace", str(ws))]), done=@sf.t("android-settings.vault.migrate.done"))
        }
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
/// done again then). True on the frame it is pressed.
fn vault_do_row(c : @ui.Ctx, key : String, title : String, note : String, action : String, lacks? : Bool = false, busy? : Bool = false) -> Bool {
  @sf.link_row(c, key, title, note~, lacks~, value=action, value_lit=true, chevron=false, tail=fn() { doing_mark(c, busy, None) }) &&
  !busy
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
  let on = [("workspace", ws), ("vault", id)]
  if @sf.link_row(c, key, @sf.t("web-pages.vault.lasts.title"), note=@sf.t("web-pages.vault.lasts." + now), tail=fn() {
      doing_mark(c, is_doing(core, ["vault.setLasts"], on), failed_of(core, ["vault.setLasts"], on))
    }) {
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
      from=Of(c.id(key)),
    )
  }
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
  if vault_do_row(c, "vault-give/" + id, title, note, @sf.t("web-pages.vault.addDevice"), lacks=true, busy=giving) {
    vault_act(core, ws, "addDevice", [("vault", str(id))], @sf.t("web-pages.vault.addDeviceWhat"), done=@sf.t("web-pages.vault.addedDevice"))
  }
}

///|
/// Deleting a vault of the viewer's own (its name after where there are more than one), in red: asked first, saying
/// what goes with it.
fn vault_delete_row(c : @ui.Ctx, core : Core, ws : String, rv : Json?, many : Bool) -> Unit {
  let id = text(rv, "id")
  let on = [("workspace", ws), ("vault", id)]
  let label = @sf.t("web-pages.vault.deleteVault") + (if many { " · " + text(rv, "name") } else { "" })
  if !@sf.link_row(c, "vault-delete/" + id, label, danger=true, chevron=false, tail=fn() {
      doing_mark(c, is_doing(core, ["vault.delete"], on), failed_of(core, ["vault.delete"], on))
    }) ||
    is_doing(core, ["vault.delete"], on) {
    return
  }
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
/// A vault this device has no key to (VaultSection's), under its name: that it has none, how to get one, and the
/// recovery words typed where they can give it one.
fn vault_no_key(c : @ui.Ctx, core : Core, ws : String, rv : Json?) -> Unit {
  let recoverable = flag(rv, "recoverable")
  @sf.section(c, text(rv, "name"), fn() {
    @sf.page_card(c, footed=recoverable, fn() {
      @sf.card_lines(c, @sf.t("android-settings.vault.noKey"), note=@sf.t("android-settings.vault.noKeyHow"))
      if recoverable {
        @sf.card_foot(c, fn() {
          if @sf.button(c, @sf.t("android-settings.vault.recover"), key="vault-recover/" + text(rv, "id"), tone=Primary) {
            vault_recover_dialog(core, ws)
          }
        })
      }
    })
  })
}

///|
/// A vault known by its items' names only (VaultSection), a section under its name: a web page's, or one this device
/// has no key to (how to get one is 密钥's: vault_no_key); each item's name (locked, that it is), how agents may ask
/// for it under it, a green dot at its end where agents are told of it.
fn vault_named(c : @ui.Ctx, core : Core, ws : String, row : Json) -> Unit {
  let rv = Some(row)
  let topic = (core.topic)("vaultItems", { "workspace": str(ws), "vault": str(text(rv, "id")) })
  let list = items(topic.value, "items")
  @sf.section(c, text(rv, "name"), fn() {
    if list.length() == 0 {
      match topic.value {
        None =>
          match topic.error {
            Some(e) => @sf.page_note(c, error_text(e), bad=true)
            // (read the first time: rows' shapes where its card's rows will be, Vault.tsx's Waiting, 4)
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
/// A vault's item (`iv`, of vault `rv`): its kind's mark, its name, its kind, its vault where there are more than one
/// (`many`), how an agent gets it, when and where it was last used (the core's); pressed, its page (`keyed`: where it
/// can be opened here).
fn vault_item_row(c : @ui.Ctx, core : Core, rv : Json?, iv : Json?, many : Bool, keyed : Bool) -> Unit {
  let th = @sf.theme()
  let mark = fn() { @sf.icon(c, @settings.kind_icon(text(iv, "kind")), size=vt_glyph, color=th.p.text) |> ignore }
  let line = [text(iv, "kindText"), if many { text(rv, "name") } else { "" }, if keyed { text(iv, "lineText") } else { text(iv, "agentText") }]
    .filter(fn(w) { w != "" })
    .join(" · ")
  if @sf.link_row(c, "vault-item/" + text(iv, "id"), text(iv, "name"), note=line, lead=mark, goes=keyed) {
    (core.push)(VaultItem(text(rv, "id"), text(iv, "id")))
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
/// The items to come while they are read (the library's Waiting, in its bones): vault_item_row's of made-up ones.
fn vault_items_sample(c : @ui.Ctx, core : Core) -> Unit {
  for x in vault_sample_items() {
    vault_item_row(c, core.quiet(), None, Some(Json::object(x)), false, true)
  }
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
/// Where a row's mark would be, kept for one with none: its words where the others' names are.
// kept across runs: a value (no field of it changes)
let vt_no_mark : @ui.Style = @ui.css("w=S4")

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
/// (rowIcon: 16 wide, the muted, at the name's line)
// kept across runs: a value (no field of it changes)
let vt_row_icon : @ui.Style = @ui.css("w=S4 pt=S0_5 align=ACenter")

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
