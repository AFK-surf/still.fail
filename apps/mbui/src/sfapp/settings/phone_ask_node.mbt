// An agent's request to debug its person's phone as its card (phone_ask.mbt's phone_card, phone_foot, phone_outcome),
// as nodes of the window's tree, made once, following the card and the core as they change: what is asked in its
// title, the agent's reason under it, and at its foot 允许, 拒绝 and how long (`adb.decide` on the chat's station);
// elsewhere whose it is. What it keeps between frames is the vault card's, keyed `phone/<id>` (vault_pending,
// vault_picked: signals). Whether this device is a phone that lends its own adb is its host's answer to `adb.phone`
// (adb_phone_node: asked as its answer's node is made, a signal told as the host says it), so 允许 turns its 共享调试
// on with it; once granted, the step left on the phone is a card under the line (sfpages' phone_ask_node).

///|
/// What a phone's request's card says, as its message has it now (phone_card's arguments): the request, the agent's
/// reason, the longest its owner lets it be granted for (`lasts`: hour, chat), whether it is the viewer's to answer
/// (`mine`), whose it is (`who`), and how it went once decided (`ended`: status, scope, why).
#derive(Eq)
pub(all) struct PhoneCard {
  request : String
  reason : String
  lasts : String
  mine : Bool
  who : String?
  ended : (String, String, String)?
}

///|
/// Whether this device lends its own adb as far as it has said so (phone_lends', without asking its host: see the
/// head).
fn phone_lends_said() -> Bool {
  flag(adb_host.phone.get(), "supported")
}

///|
/// The card of request `card` (as it says it now) in `v` (phone_card's, as nodes): its words, and its answer where it is
/// the viewer's and a core is there (answered in place once decided), else whose it is. `how`: settings' 共享调试
/// opened, where this device is to be approved first.
pub fn phone_card_node(
  v : @view.View,
  core : Core?,
  station : String,
  card : () -> PhoneCard,
  how? : () -> Unit = fn() {  },
) -> Unit {
  @sf.ask_card_node(v, fn(k) {
    @sf.ask_words_node(k, fn() { tr("android-misc.adb.ask.chat.title") }, fn() { card().reason }) |> ignore
    let answers = fn() { core is Some(_) && card().mine }
    k.show(fn() { answers() || card().who.unwrap_or("") != "" }, fn(s) {
      s.pick(answers, fn(p, here) {
        match (here, core) {
          (true, Some(core)) =>
            answered_in_place_node(
              p,
              fn() { card().ended.map(fn(e) { (e.0 == "granted", [@ui.span(phone_outcome_words(e.0, e.1, e.2))]) }) },
              fn(a) { phone_foot_node(a, core, station, card, how) },
            )
          _ => @sf.words_node(p, fn() { card().who.unwrap_or("") }, fn() { @sf.ask_note }) |> ignore
        }
      })
    })
  })
  |> ignore
}

///|
/// What stands in the way of allowing it here, as the core's `adbShare` has the request now (phone_foot's): a station
/// from before signatures, this device not approved by its person's trusted devices (`join`: 查看步骤 in 允许's place),
/// else None.
fn phone_lacks(core : Core, request : String) -> (String, Bool)? {
  let row = phone_row(core, request)
  if flag(row, "oldStation") {
    Some((tr("android-misc.personal.updateStation"), false))
  } else if flag(row, "join") {
    Some((tr("android-misc.adb.ask.approve"), true))
  } else {
    None
  }
}

///|
/// Its answer in `v` (phone_foot's, as nodes), as the card and the core say it now: 允许 (for the length chosen), 拒绝,
/// and the length's choice; where it cannot be allowed here yet, why, and 查看步骤 (`how`) in 允许's place for a device to
/// be approved. Pressed, the one pressed turns and neither takes a press till the core has it.
fn phone_foot_node(v : @view.View, core : Core, station : String, card : () -> PhoneCard, how : () -> Unit) -> Unit {
  // (whether this device lends its own adb: asked of its host as the answer is made, phone_lends_said reads it)
  adb_phone_node(v) |> ignore
  let key = fn() { "phone/" + card().request }
  let lacks = fn() { phone_lacks(core, card().request) }
  let scopes = fn() { if card().lasts == "hour" { ["hour"] } else { ["hour", "idle", "eight", "chat"] } }
  let scope = fn() {
    let all = scopes()
    match vault_picked.get(key()) {
      Some(s) if all.contains(s) => s
      _ => if all.contains("idle") { "idle" } else { all[all.length() - 1] }
    }
  }
  let pending = fn() { vault_pending.get(key()) }
  let under = fn() { pending() is Some(_) || is_doing(core, ["adb.decide"], [("station", station), ("request", card().request)]) }
  let decide = fn(yes : Bool) {
    if core.read_only != "" {
      (core.say)(core.read_only)
      return
    }
    let request = @signals.untracked(card).request
    let k = "phone/" + request
    vault_pending[k] = yes
    // (Wireless debugging the app may turn on itself: on as it is allowed, as the switch turned on does)
    let turn_on = @signals.untracked(phone_lends_said) &&
      !flag(@signals.untracked(fn() { (core.topic)("adbShare", Map([])).get().value }), "on")
    if yes && turn_on {
      adb_turn(core, true)
    } else if yes {
      adb_switch_on()
    }
    let params : Array[(String, Json)] = [("station", str(station)), ("request", str(request))]
    if yes {
      params.push(("scope", str(@signals.untracked(scope))))
    }
    (core.call)("adb.decide", obj(params), fn(r) {
      match r {
        Err(e) => {
          vault_pending.remove(k)
          let what = tr(if yes { "android-settings.vault.act.allowWhat" } else { "android-settings.vault.act.denyWhat" })
          (core.say)(fill("android-misc.act.failed", [("what", what), ("error", error_text(e))]))
        }
        Ok(_) => ()
      }
    })
  }
  v.show(fn() { lacks() is Some(_) }, fn(s) {
    @sf.words_node(
      s,
      fn() { fill("android-misc.adb.ask.first", [("step", lacks().map(fn(l) { l.0 }).unwrap_or(""))]) },
      fn() { @sf.ask_note },
    )
    |> ignore
  })
  @sf.ask_buttons_node(v, fn(f) {
    // (0: 允许; 1: 查看步骤; 2: neither, a station from before)
    let first = fn() {
      match lacks() {
        None => 0
        Some((_, true)) => 1
        Some(_) => 2
      }
    }
    f.show(fn() { first() != 2 }, fn(s) {
      s.pick(fn() { first() == 0 }, fn(p, allow) {
        if allow {
          @sf.button_node(
            p,
            fn() { tr("android-settings.vault.act.allow") },
            fn() { decide(true) },
            tone=Primary,
            busy=fn() { pending() == Some(true) },
            disabled=under,
            card_words=true,
          )
          |> ignore
        } else {
          @sf.button_node(p, fn() { tr("android-misc.adb.ask.how") }, how, tone=Primary, card_words=true) |> ignore
        }
      })
    })
    @sf.button_node(
      f,
      fn() { tr("android-settings.vault.act.deny") },
      fn() { decide(false) },
      tone=Ghost,
      busy=fn() { pending() == Some(false) },
      disabled=under,
      card_words=true,
    )
    |> ignore
    // (nothing to allow yet, or one length alone: no length to choose)
    f.show(fn() { scopes().length() >= 2 && lacks() is None }, fn(s) {
      @sf.foot_chooser_node(
        s,
        fn() { tr("android-settings.vault.scope." + scope()) },
        fn() { scopes().map(fn(x) { (x, tr("android-settings.vault.scope." + x)) }) },
        scope,
        fn(x) { vault_picked[@signals.untracked(key)] = x },
      )
      |> ignore
    })
  })
  |> ignore
}

///|
/// How a request ended in `v` (phone_outcome's, as nodes), as the card and the core say it now: a dot (green while
/// granted and held, or not said) and its words, how its station's adb holds the phone after them (`link`,
/// phone_link's); granted and waiting to be paired, under the line's words that it is paired on the phone. `inline`,
/// `history`: ask_outcome_node's. `step_here`: on the phone, a card under the line says what is left to do (sfpages'
/// phone_ask_node), so the line says no more than what was allowed.
pub fn phone_outcome_node(
  v : @view.View,
  status : () -> String,
  scope : () -> String,
  why : () -> String,
  link : () -> String,
  inline : () -> Bool,
  history? : ((@view.View) -> Unit)? = None,
  step_here? : () -> Bool = fn() { false },
) -> Unit {
  let granted = fn() { status() == "granted" }
  ask_outcome_node(
    v,
    fn() { granted() && (link() == "" || link() == "connected") },
    fn() {
      let words = phone_outcome_words(status(), scope(), why())
      // (on the phone, a step left: its card under the line says so, the line not again, 2026-11-11)
      [@ui.span(if granted() && link() != "" && !step_here() { words + " · " + phone_link_words(link()) } else { words })]
    },
    inline,
    history~,
  )
  // (elsewhere than on the phone: where it is paired, under the line's words where they start)
  v.show(fn() { granted() && link() == "unpaired" && !step_here() }, fn(s) {
    @sf.style_node(s, fn() { if inline() { ask_ended_past } else { ask_ended_at } })
    @sf.words_node(s, fn() { tr("android-misc.adb.ask.link.onPhone") }, fn() { @sf.ask_note }) |> ignore
  })
}
