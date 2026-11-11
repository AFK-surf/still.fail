// An agent's request for a rig of the workspace as its card (rig_ask.mbt's rig_card, rig_foot, rig_outcome), as nodes
// of the window's tree, made once, following the card and the core as they change: which rig in its title, the agent's
// reason under it, and at its foot 允许, 拒绝 and for how long (`rig.decide` on the chat's station), only for the rig's
// person; elsewhere whose it is. What it keeps between frames is the vault card's, keyed `rig/<id>` (vault_pending,
// vault_picked: signals).

///|
/// What a rig's request's card says, as its message has it now (rig_card's arguments): the request, the rig's name, the
/// agent's reason, the time it asked for, what it said of the chat (`rig.decide`'s `ask`), whether it is the viewer's
/// to answer (`mine`), whose it is (`who`), one of its devices alone (`device`: its name, "" the rig itself), and how
/// it went once decided (`ended`: granted, its words).
#derive(Eq)
pub(all) struct RigCard {
  request : String
  name : String
  reason : String
  timeout : (String, Int)
  ask : Json
  mine : Bool
  who : String?
  device : String
  ended : (Bool, String)?
}

///|
/// The card of request `card` (as it says it now) in `v` (rig_card's, as nodes): its words, and its answer where it is
/// the viewer's and a core is there (answered in place once decided), else whose it is. `lock`: the person's own
/// lock's page opened.
pub fn rig_card_node(
  v : @view.View,
  core : Core?,
  station : String,
  card : () -> RigCard,
  lock? : () -> Unit = fn() {  },
) -> Unit {
  @sf.ask_card_node(v, fn(k) {
    @sf.ask_words_node(
      k,
      fn() {
        let c = card()
        if c.device == "" {
          fill("web-pages.rigs.ask.title", [("name", c.name)])
        } else {
          fill("web-pages.devices.ask.title", [("device", c.device), ("name", c.name)])
        }
      },
      fn() { card().reason },
    )
    |> ignore
    let answers = fn() { core is Some(_) && card().mine }
    k.show(fn() { answers() || card().who.unwrap_or("") != "" }, fn(s) {
      s.pick(answers, fn(p, here) {
        match (here, core) {
          (true, Some(core)) =>
            answered_in_place_node(p, fn() { card().ended.map(fn(e) { (e.0, [@ui.span(e.1)]) }) }, fn(a) {
              rig_foot_node(a, core, station, card, lock)
            })
          _ => @sf.words_node(p, fn() { card().who.unwrap_or("") }, fn() { @sf.ask_note }) |> ignore
        }
      })
    })
  })
  |> ignore
}

///|
/// What stands in the way of allowing a rig on this device, as the workspace's `rigs` says it now (rig_foot's): a web
/// page (its words, nothing to press), a device its person's trusted devices have not approved (its words, and the way
/// there in 允许's place), else None.
fn rig_lacks(core : Core, station : String) -> (String, Bool)? {
  let ws = match station.find("/") {
    Some(i) => station.exact_view(end=i).to_owned()
    None => ""
  }
  let rigs = (core.topic)("rigs", { "workspace": str(ws) }).get().value
  if rigs is Some(_) && !flag(rigs, "app") {
    Some((tr("web-pages.rigs.ask.appOnly"), false))
  } else if rigs is Some(_) && (text(rigs, "personal") == "outside" || text(rigs, "personal") == "replaced") {
    Some((tr("android-misc.adb.lock.join"), true))
  } else {
    None
  }
}

///|
/// Its answer in `v` (rig_foot's, as nodes), as the card and the core say it now: 允许 (for the time chosen), 拒绝,
/// and the time's choice; on a device that does not sign as its person, what first, and the way there in 允许's place.
/// Pressed, the one pressed turns and neither takes a press till the core has it (vault_pending, its doing).
fn rig_foot_node(v : @view.View, core : Core, station : String, card : () -> RigCard, lock : () -> Unit) -> Unit {
  let key = fn() { "rig/" + card().request }
  let lacks = fn() { rig_lacks(core, station) }
  let times = fn() {
    let asked = card().timeout
    rig_timeouts(if asked.1 > 0 { asked } else { ("idle", 3600) })
  }
  let label = fn(t : (String, Int)) { t.0 + "/" + t.1.to_string() }
  let time = fn() {
    let all = times()
    match vault_picked.get(key()) {
      Some(s) => all.iter().find_first(fn(t) { label(t) == s }).unwrap_or(all[0])
      None => all[0]
    }
  }
  let pending = fn() { vault_pending.get(key()) }
  let under = fn() { pending() is Some(_) || is_doing(core, ["rig.decide"], [("station", station), ("request", card().request)]) }
  let decide = fn(yes : Bool) {
    if core.read_only != "" {
      (core.say)(core.read_only)
      return
    }
    let now = @signals.untracked(card)
    let request = now.request
    let k = "rig/" + request
    vault_pending[k] = yes
    let params : Array[(String, Json)] = [
      ("station", str(station)),
      ("request", str(request)),
      ("allow", Json::boolean(yes)),
      ("ask", now.ask),
    ]
    if yes {
      let t = @signals.untracked(time)
      params.push(("timeoutKind", str(t.0)))
      params.push(("timeoutSeconds", Json::number(t.1.to_double())))
    }
    (core.call)("rig.decide", obj(params), fn(r) {
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
    @sf.words_node(s, fn() { lacks().map(fn(l) { l.0 }).unwrap_or("") }, fn() { @sf.ask_note }) |> ignore
  })
  @sf.ask_buttons_node(v, fn(f) {
    // (0: 允许; 1: the way to the lock; 2: neither, a web page's)
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
          @sf.button_node(p, fn() { tr("android-misc.adb.ask.how") }, lock, tone=Primary, card_words=true) |> ignore
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
    // (nothing to allow yet: no time to choose)
    f.show(fn() { lacks() is None }, fn(s) {
      @sf.foot_chooser_node(
        s,
        fn() {
          let t = time()
          rig_timeout_short(t.0, t.1)
        },
        fn() { times().map(fn(t) { (label(t), rig_timeout_words(t.0, t.1)) }) },
        fn() { label(time()) },
        fn(s) { vault_picked[@signals.untracked(key)] = s },
      )
      |> ignore
    })
  })
  |> ignore
}

///|
/// How a request ended in `v` (rig_outcome's, as nodes), as the card says it now: a dot (green once the rig took the
/// grant) and its words (rig_outcome_words); `inline`, `history`: ask_outcome_node's.
pub fn rig_outcome_node(
  v : @view.View,
  status : () -> String,
  why : () -> String,
  delivered : () -> Bool,
  granted : () -> (String, Int),
  inline : () -> Bool,
  history? : ((@view.View) -> Unit)? = None,
) -> Unit {
  ask_outcome_node(
    v,
    fn() { status() == "granted" && delivered() },
    fn() { [@ui.span(rig_outcome_words(status(), why(), delivered(), granted()))] },
    inline,
    history~,
  )
}
