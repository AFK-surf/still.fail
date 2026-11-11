// An agent's request as its card in place of its post's words (decision.mbt's vault_ask_card, phone_ask_card,
// rig_ask_card; signin_card.mbt's signin_ask_card), as nodes of the window's tree, made once as the message says it now,
// following it and the core as they change: its card while it waits, answered on it, then one line saying how it went,
// pressed for the card read again; the one in the other's place as it is decided, as anything down a column comes and
// goes (View::pick: the old under_post's fades and the list's turns are not here). The card's insides are the settings'
// (rig_card_node…), as the old ones are. Made so far: a rig's (P32), a phone's (P31: not the step left on the phone
// under its line once granted, settings' phone_ask_node says why). Not here yet: a vault item's (P30), a sign-in's (P33:
// its password manager's and the system's autofill's answers are only looked at each frame, @hostapi.polled).

///|
/// What is in place of a post's words, as the message says it now.
#derive(Eq)
priv enum InPlace {
  /// its words (the agent's message's own)
  Words
  /// a request for its person's phone
  Phone
  /// a request for a rig of the workspace
  Rig
  /// a vault item's, a sign-in's: not made as nodes yet
  NotYet
}

///|
/// What is in place of post `m`'s words (prose_with_files' cases).
fn in_place_of(m : Message) -> InPlace {
  match m.card {
    Some({ ask: Some(_), .. }) => NotYet
    Some({ phone: Some(_), .. }) => Phone
    Some({ signin: Some(_), .. }) => NotYet
    Some({ rig: Some(_), .. }) => Rig
    _ => Words
  }
}

///|
/// Post `m`'s request as its card in place of its words (prose_with_files' cards, as nodes) in `v`, of the chat `here`
/// is, answered with `core` (None where nothing is answered); nothing where it has none.
// the chat's page as nodes: held by its tests, not used by the app yet
#warnings("-unused_value")
fn message_card_node(v : @view.View, here : MessageNodeHere, core : @settings.Core?, m : () -> Message) -> Unit {
  v.pick(fn() { in_place_of(m()) }, fn(p, k) {
    match k {
      Phone => phone_ask_node(p, here, core, m)
      Rig => rig_ask_node(p, here, core, m)
      Words | NotYet => ()
    }
  })
}

///|
/// Whether what is asked of `assignee` is the viewer's to answer in the chat `here` is (mine_to's, as the view says it
/// now): anyone's where it names no one.
fn mine_to_node(here : MessageNodeHere, assignee : String) -> Bool {
  let me = (here.view)().me
  assignee == "" || me == "" || assignee.to_lower() == me.to_lower()
}

///|
/// A request read again in a panel (card_history's, as nodes; a sheet on a small screen) opened from `from`: `body` in
/// the panel's words' room.
fn card_history_node(from : @view.View, body : (@view.View) -> Unit) -> Unit {
  @sf.panel_nodes(
    @sf.t("web-main.history.details"),
    fn(p, _) {
      p.box(fn(b) {
        @sf.style_node(b, fn() { @sf.panel_words_in_node(b) })
        body(b)
      })
      |> ignore
    },
    from=Node(from),
  )
}

///|
/// A request with nothing in it (what a rig's reads where its message says none: the card going as another comes).
// kept across runs: a value (no field of it changes)
let rig_ask_none : RigAsk = {
  request: "",
  rig: "",
  name: "",
  reason: "",
  timeout_kind: "",
  timeout_seconds: 0,
  session: "",
  chat: "",
  title: "",
  by: "",
  status: "",
  why: "",
  delivered: false,
  granted_kind: "",
  granted_seconds: 0,
  device: "",
  device_name: "",
}

///|
/// Post `m`'s request for a rig in place of its words (rig_ask_card's, as nodes) in `v`: its card while it waits
/// (answered by the rig's person with `rig.decide` on the chat's station), then a line saying how it went, pressed for
/// what was asked; decided, the line in the card's place.
fn rig_ask_node(v : @view.View, here : MessageNodeHere, core : @settings.Core?, m : () -> Message) -> Unit {
  let ask = fn() {
    match m().card {
      Some({ rig: Some(a), .. }) => a
      _ => rig_ask_none
    }
  }
  let assignee = fn() { m().card.map(fn(c) { c.assignee }).unwrap_or("") }
  let who = fn() { m().card.bind(fn(c) { c.assignee_text }) }
  v.pick(fn() { ask().status != "" }, fn(p, decided) {
    @sf.style_node(p, fn() { under_post_room })
    if !decided {
      // (the card as wide as what it says: lined up at the column's start, not across it)
      p.lines_up(Is(Some(Start))) |> ignore
      p.box(fn(r) {
        @sf.style_node(r, fn() { @sf.ask_card_room.then(ask_card_under_head) })
        let card = @signals.computed(fn(_) -> @settings.RigCard {
          let a = ask()
          {
            request: a.request,
            name: a.name,
            reason: a.reason,
            timeout: (a.timeout_kind, a.timeout_seconds),
            ask: {
              "rig": Json::string(a.rig),
              "name": Json::string(a.name),
              "session": Json::string(a.session),
              "chat": Json::string(a.chat),
              "title": Json::string(a.title),
              "by": Json::string(a.by),
              "device": Json::string(a.device),
              "deviceName": Json::string(a.device_name),
            },
            mine: mine_to_node(here, assignee()),
            who: who(),
            device: a.device_name,
            ended: if a.status != "" {
              Some((a.status == "granted", @settings.rig_outcome_words(a.status, a.why, a.delivered, (a.granted_kind, a.granted_seconds))))
            } else {
              None
            },
          }
        })
        @settings.rig_card_node(r, core, here.station, fn() { card.get() }, lock=fn() {
          open_page(Setting(@settings.Route::AdbShare("")))
        })
      })
      |> ignore
    } else {
      @settings.rig_outcome_node(
        p,
        fn() { ask().status },
        fn() { ask().why },
        fn() { ask().delivered },
        fn() { (ask().granted_kind, ask().granted_seconds) },
        fn() { message_inline(here) },
        history=Some(fn(from) {
          card_history_node(from, fn(b) {
            @sf.ask_words_node(
              b,
              fn() { @sf.t("web-pages.rigs.ask.title", args=[("name", ask().name)]) },
              fn() { ask().reason },
            )
            |> ignore
          })
        }),
      )
    }
  })
}

///|
/// A request with nothing in it (what a phone's reads where its message says none: the card going as another comes).
// kept across runs: a value (no field of it changes)
let phone_ask_none : PhoneAsk = { request: "", reason: "", status: "", scope: "", why: "", link: "", lasts: "" }

///|
/// Post `m`'s request for its person's phone in place of its words (phone_ask_card's, as nodes) in `v`: its card while it
/// waits (answered with `adb.decide` on the chat's station), then a line saying how it went, how its station holds the
/// phone after it, pressed for what was asked; decided, the line in the card's place. Not here yet: the step left on
/// the phone under the line (settings' phone_ask_node).
fn phone_ask_node(v : @view.View, here : MessageNodeHere, core : @settings.Core?, m : () -> Message) -> Unit {
  let ask = fn() {
    match m().card {
      Some({ phone: Some(a), .. }) => a
      _ => phone_ask_none
    }
  }
  let assignee = fn() { m().card.map(fn(c) { c.assignee }).unwrap_or("") }
  let who = fn() { m().card.bind(fn(c) { c.assignee_text }) }
  v.pick(fn() { ask().status != "" }, fn(p, decided) {
    @sf.style_node(p, fn() { under_post_room })
    if !decided {
      // (the card as wide as what it says: lined up at the column's start, not across it)
      p.lines_up(Is(Some(Start))) |> ignore
      p.box(fn(r) {
        @sf.style_node(r, fn() { @sf.ask_card_room.then(ask_card_under_head) })
        let card = @signals.computed(fn(_) -> @settings.PhoneCard {
          let a = ask()
          {
            request: a.request,
            reason: a.reason,
            lasts: a.lasts,
            mine: mine_to_node(here, assignee()),
            who: who(),
            ended: if a.status != "" { Some((a.status, a.scope, a.why)) } else { None },
          }
        })
        @settings.phone_card_node(r, core, here.station, fn() { card.get() }, how=fn() {
          open_page(Setting(@settings.Route::AdbShare("")))
        })
      })
      |> ignore
    } else {
      @settings.phone_outcome_node(
        p,
        fn() { ask().status },
        fn() { ask().scope },
        fn() { ask().why },
        fn() { @settings.phone_link(core, here.station, ask().link) },
        fn() { message_inline(here) },
        history=Some(fn(from) {
          card_history_node(from, fn(b) {
            @sf.ask_words_node(b, fn() { @sf.t("android-misc.adb.ask.chat.title") }, fn() { ask().reason }) |> ignore
          })
        }),
      )
    }
  })
}
