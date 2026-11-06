// An agent's asks in place of its post's words (decision.mbt's vault_ask_card, phone_ask_card) as nodes of the window's
// tree, made once: its card while it waits (settings' vault_card_node, phone_card_node), then a line saying how it
// went, a press away from the card as it was. In a chat's list each comes and goes in a room of its own (under_node's).

///|
/// What vault request `ask` asks (settings' Asked), as its card says it.
fn asked_of(ask : VaultAsk) -> @settings.Asked {
  {
    name: ask.name,
    reason: ask.reason,
    timeout_kind: ask.timeout_kind,
    timeout_seconds: ask.timeout_seconds,
    approved_timeout_kind: ask.approved_timeout_kind,
    approved_timeout_seconds: ask.approved_timeout_seconds,
    mode: ask.mode,
    command: ask.command,
    how_text: ask.how_text,
    save_kind: ask.save_kind,
    username: ask.username,
    filename: ask.filename,
    typed: ask.typed,
    station: ask.station,
  }
}

///|
/// The card's history (card_history's): its card as it was, in a panel opened from `at`.
fn card_history_open(at : @sf.Anchor, body : (@ui.Ctx) -> Unit) -> Unit {
  @sf.panel(
    @sf.t("web-main.history.details"),
    fn(p, _) { p.box(style=@sf.panel_words_in(), fn() { body(p) }) |> ignore },
    from=at,
  )
}

///|
/// An agent's request about a vault item in place of post `m`'s words (vault_ask_card's) in `v`: its card as wide as
/// what it says (320 at least, 560 at most; one whose file the person picks as wide as it may be), its answer at its
/// foot; once decided, a line saying how it ended, its card as it was a press away.
fn vault_ask_card_node(v : @view.View, here : () -> MessageHere, m : () -> Message) -> Unit {
  let card = fn() { m().card }
  let ask = fn() {
    match card() {
      Some({ ask: Some(a), .. }) => Some(a)
      _ => None
    }
  }
  let decided = fn() { ask().map(fn(a) { a.status != "" }).unwrap_or(false) }
  let asked = fn() { asked_of(ask().unwrap()) }
  let asking = fn(u : @view.View) {
    let first = @signals.untracked(ask).unwrap()
    let least = if first.typed && first.save_kind == "file" { 560.0 } else { 320.0 }
    u.padding(Is((0.0, 8.0, 0.0, 0.0))) |> ignore
    @sf.ask_card_room_node(u, least~, fn(room) {
      match @signals.untracked(here).core {
        Some(core) => {
          let c = @signals.untracked(card).unwrap()
          @settings.vault_card_node(room, core, workspace_of(@signals.untracked(here).station), c.vault, asked, fn() {
            let a = ask().unwrap()
            let k = card().unwrap()
            @settings.card_answer(a.answer, a.lasts, mine_to(here(), k.assignee), who=k.assignee_text)
          }, fn() {
            match ask() {
              Some(a) if a.status != "" => Some((a.status, a.scope))
              _ => None
            }
          })
        }
        None => @sf.card_node(room, fn(k) { @settings.vault_asked_node(k, asked) }) |> ignore
      }
    })
    |> ignore
  }
  let ended = fn(u : @view.View) {
    @settings.ask_outcome_node(u, fn() { ask().map(fn(a) { a.status == "granted" }).unwrap_or(false) }, fn() {
      match ask() {
        Some(a) => @settings.vault_outcome_words(asked(), a.status, a.scope)
        None => []
      }
    }, fn() { here().inline }, history=Some(fn(at) {
      let a = @signals.untracked(asked)
      card_history_open(at, fn(p) { @settings.vault_ask_details(p, a) })
    }))
  }
  asked_or_ended_node(v, here, decided, asking, ended)
}

///|
/// An agent's request for its person's phone in place of post `m`'s words (phone_ask_card's) in `v`: its card while it
/// waits (answered with `adb.decide`), then a line saying how it went (how its station holds the phone).
fn phone_ask_card_node(v : @view.View, here : () -> MessageHere, m : () -> Message) -> Unit {
  let card = fn() { m().card }
  let ask = fn() {
    match card() {
      Some({ phone: Some(a), .. }) => Some(a)
      _ => None
    }
  }
  let decided = fn() { ask().map(fn(a) { a.status != "" }).unwrap_or(false) }
  let asking = fn(u : @view.View) {
    u.padding(Is((0.0, 8.0, 0.0, 0.0))) |> ignore
    @sf.ask_card_room_node(u, fn(room) {
      let h = @signals.untracked(here)
      let first = @signals.untracked(ask).unwrap()
      let k = @signals.untracked(card).unwrap()
      @settings.phone_card_node(
        room,
        h.core,
        h.station,
        first.request,
        fn() { ask().map(fn(a) { a.reason }).unwrap_or("") },
        mine_to(h, k.assignee),
        fn() { ask().map(fn(a) { a.lasts }).unwrap_or("chat") },
        k.assignee_text,
        fn() {
          match ask() {
            Some(a) if a.status != "" => Some((a.status, a.scope, a.why))
            _ => None
          }
        },
        fn() { open_page(Setting(@settings.phone_steps(here().core, here().station, request=first.request))) },
        chat=h.view.chat_address,
      )
    })
    |> ignore
  }
  let ended = fn(u : @view.View) {
    let link = fn() {
      let h = here()
      @settings.phone_link(h.core, h.station, ask().map(fn(a) { a.link }).unwrap_or(""))
    }
    @settings.ask_outcome_node(u, fn() {
      ask().map(fn(a) { a.status == "granted" }).unwrap_or(false) && (link() == "" || link() == "connected")
    }, fn() {
      match ask() {
        Some(a) => {
          let words = @settings.phone_outcome_words(a.status, a.scope, a.why)
          let l = link()
          [@ui.span(if a.status == "granted" && l != "" { words + " · " + @settings.phone_link_words(l) } else { words })]
        }
        None => []
      }
    }, fn() { here().inline }, history=Some(fn(at) {
      let reason = @signals.untracked(ask).map(fn(a) { a.reason }).unwrap_or("")
      card_history_open(at, fn(p) { @sf.ask_words(p, @sf.t("android-misc.adb.ask.chat.title"), reason) })
    }))
    // (elsewhere than on the phone: where it is paired, under the line's words where they start)
    let paired_here = fn() {
      mine_to(here(), card().map(fn(k) { k.assignee }).unwrap_or("")) && @settings.phone_lends_now()
    }
    u.show(fn() { link() == "unpaired" && ask().map(fn(a) { a.status == "granted" }).unwrap_or(false) && !paired_here() }, fn(n) {
      n.padding(By(fn() { (if here().inline { 25.0 } else { 0.0 }, 0.0, 0.0, 0.0) })) |> ignore
      @sf.words_node(n, fn() { @sf.t("android-misc.adb.ask.link.onPhone") }, fn() { @sf.ask_note }) |> ignore
    })
    // (on the phone, its pairing with its station a tap away, as a login's card is under its message)
    u.show(fn() {
      let h = here()
      link() == "unpaired" && ask().map(fn(a) { a.status == "granted" }).unwrap_or(false) &&
      mine_to(h, card().map(fn(k) { k.assignee }).unwrap_or("")) &&
      @settings.phone_lends_now()
    }, fn(s) {
      s.reacts(fn() { () }, fn(_) { @settings.adb_phone_ask() })
      step_card_node(s, fn() { @sf.t("android-misc.adb.ask.pair.title") }, fn() { @sf.t("android-misc.adb.ask.pair.about") }, fn() {
        open_page(Setting(@settings.Route::AdbShare(here().station)))
      })
    })
  }
  asked_or_ended_node(v, here, decided, asking, ended)
}

///|
/// What asks in place of a post's words in `v`: `asking` while not `decided`, `ended` once it is; in a chat's list each
/// in a room of its own, the card closing (faded where it is) and the line coming in its place after it.
fn asked_or_ended_node(
  v : @view.View,
  here : () -> MessageHere,
  decided : () -> Bool,
  asking : (@view.View) -> Unit,
  ended : (@view.View) -> Unit,
) -> Unit {
  if @signals.untracked(here).list is Some(_) {
    under_node(v, fn() { !decided() }, asking)
    under_node(v, decided, fades_in=true, ended)
  } else {
    v.pick(decided, fn(p, done) { if done { ended(p) } else { asking(p) } })
  }
}
