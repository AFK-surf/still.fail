// A profile's page, one in every frame (the Small stack's, the wide frame's pane, the tape's panel, the profiles'
// place): who the account is and whether it works now (its provider's mark, its name renamed here, the runtimes it
// serves, what it is, its last check, checking again; its ⋯ to delete it, or stop the machine's own), signing it in
// where that comes first, what is left of its allowance, what it spent, the stations it is on, sharing it, the
// workspaces it serves, fast mode, its models, how it runs, who uses it, the account itself (its key, signing in again)
// and its variables. Made once as nodes of the window's tree (page_node, laid out by the width its frame gives it);
// everything said is the core's (its overview's profile, the workspace's profiles, the usage view), followed as it
// changes.

///|
/// A variable's row being written: its name, its value, what it was (its name saved, "" a new one), its value masked
/// as saved ("" not a secret).
priv struct EnvRow {
  key : @ui.Field
  value : @ui.Field
  original : String
  masked : String
}

///|
/// What a profile's page opens of its own while it is made (each its node's, let go with it): the command to sign in
/// by hand shown, its variables opened to be written, a device's code copied.
priv struct ProfileOpen {
  command : @signals.Signal[Bool]
  env : @signals.Signal[Bool]
  copied : @signals.Signal[Bool]
}

///|
/// The fields of a profile's models' panel, by their key (made as first drawn).
// kept across runs: made as a panel first shows one; profile_page_reset empties it
let profile_fields : Map[String, @ui.Field] = Map([])

///|
fn profile_page_reset() -> Unit {
  profile_fields.clear()
}

///|
/// A field of the models' panel, by its key, made once.
pub fn profile_field(key : String) -> @ui.Field {
  match profile_fields.get(key) {
    Some(f) => f
    None => {
      let f = @ui.Field::new()
      profile_fields[key] = f
      f
    }
  }
}

///|
/// A profile's page (AccountPage), by its station and id, made once in node `v` (laid out by the `width` its frame gives
/// it, in the frame it is given): while the station's overview is read the first time, all of it in its bones (a profile
/// made up, through a core that answers nothing: waiting_node); one the station lists no more, that it is not found.
/// `stint`: the page's time on top, a workspace's picture asked for on it.
pub fn profile_node(
  v : @view.View,
  core : Core,
  here : () -> Here,
  address : String,
  id : String,
  on_back~ : () -> Unit,
  frame~ : () -> PageFrame,
  said? : (@sf.PageSaid) -> Unit,
  width? : () -> Double,
  tips? : @sf.TipLayer,
  stint? : () -> Int = fn() { 0 },
) -> Unit {
  let s = fn() { @settings.station_of(core, here(), address) }
  let o = fn() { field(s(), "overview") }
  // (shown in a pane by a press that asked what it reads (sfbase's show_answered): what it asked let go once this first
  // build has read it)
  @sfbase.shown_read(@sfbase.profile_shown_at(address, id))
  // (0 read the first time, 1 its profile there, 2 none of that id; the account it is, its own ask, answered too: the
  // page opens whole, its stations' block with it. Opened from a list, it opens once both are answered and never shows
  // this: a link straight to it may)
  let found = fn() {
    // (both read every time, so both are asked at once whichever comes first; its press waits for both before it
    // opens it: sfbase's account_open.mbt)
    let account = @settings.profile_read(core, here(), address, id).value
    if !(o() is Some(Object(_))) || account is None {
      0
    } else if items(o(), "profiles").iter().any(fn(p) { text(Some(p), "id") == id }) {
      1
    } else {
      2
    }
  }
  v.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
  v.pick(at_once=true, found, fn(p, what) {
    match what {
      1 => profile_found_node(p, core, here, s, address, id, on_back, frame, said, width, tips, stint)
      2 =>
        @sf.page_node(p, fn() { "Profile" }, on_back~, frame~, said?, width?, tips?, fn() { ["none"] }, fn(b, _) {
          @sf.page_note_node(b, fn() { @sf.t("web-pages.profiles.notFound", args=[("id", id)]) })
        })
      _ =>
        @sf.page_node(p, fn() { "Profile" }, on_back~, frame~, said?, width?, tips?, fn() { ["wait"] }, fn(b, _) {
          @sf.waiting_node(
            b,
            fn(w) {
              let quiet = core.quiet()
              let sp = profile_sample()
              let ss : Json? = Some({ "station": "sample", "name": Json::string(@sf.sample_words(4)) })
              let so : Json? = Some({ "profiles": [sp] })
              let open = profile_open()
              let ps = fn() { Some(sp) }
              let sv = fn() { ss }
              let ov = fn() { so }
              let entry = fn() -> Json? { None }
              profile_head_node(w, quiet, here, "sample", "sample", sv, ps, entry, tips)
              for key in @signals.untracked(fn() { profile_keys(quiet, here, ov, ps, entry) }) {
                profile_block_node(w, quiet, here, "sample", "sample", sv, ov, ps, entry, open, stint, tips, key)
              }
            },
            note=fn() { { reading: true, text: @sf.t("web-pages.profiles.loading"), failing: [] } },
          )
        })
    }
  })
}

///|
/// What a profile's page opens of its own, none of it yet.
fn profile_open() -> ProfileOpen {
  { command: @signals.signal(false), env: @signals.signal(false), copied: @signals.signal(false) }
}

///|
/// The page of a profile its station lists (AccountView), the same parts in the same order on every screen, by what a
/// person comes to it for: who the account is and whether it works now (its head, checked again there); what to do
/// first where it does not (signing it in, its trouble's next step); how much is left of it and what it spent; who uses
/// it and the stations it is on; which models it may use and how it runs; whom it is shared with; then the account
/// itself (its key, its sign-in) and its variables, what is changed least. Its head says who it is: no title over it
/// (what the frame's bar says of it, what it is of: Profile).
fn profile_found_node(
  v : @view.View,
  core : Core,
  here : () -> Here,
  s : () -> Json?,
  address : String,
  id : String,
  on_back : () -> Unit,
  frame : () -> PageFrame,
  said : ((@sf.PageSaid) -> Unit)?,
  width : (() -> Double)?,
  tips : @sf.TipLayer?,
  stint : () -> Int,
) -> Unit {
  let o = fn() { field(s(), "overview") }
  let p = fn() -> Json? {
    let all = items(o(), "profiles")
    match all.search_by(fn(x) { text(Some(x), "id") == id }) {
      Some(i) => Some(all[i])
      None => None
    }
  }
  // the account it is, on whichever stations have it: its own topic (`profile`), never the workspace's list
  let entry = fn() -> Json? { @settings.profile_of(core, here(), address, id) }
  let open = profile_open()
  @sf.page_node(
    v,
    fn() { @sf.t("android-misc.bar.place.profiles") },
    on_back~,
    frame~,
    said?,
    width?,
    tips?,
    head=fn(h) { profile_head_node(h, core, here, address, id, s, p, entry, tips) },
    actions=fn(a) { profile_more_node(a, core, here, address, p) },
    // (every block it may have, in their order, each in a room that opens as profile_keys comes to name it and closes
    // as it stops naming it, on its way, as the old page's `keys` did: none come or gone at once over what is under them)
    fn() {
      ["sign-in", "trouble", "quota", "usage", "used-by", "stations", "models", "run", "share", "workspaces", "account", "env"]
    },
    fn(b, key) {
      b.show(at_once=true, fn() { profile_keys(core, here, o, p, entry).contains(key) }, fn(r) {
        profile_block_node(r, core, here, address, id, s, o, p, entry, open, stint, tips, key)
      })
    },
  )
}


///|
/// Whether the profile `p` is another station's copy of it (shared to this one).
fn profile_copy(p : Json?) -> Bool {
  text(field(p, "share"), "role") == "user"
}

///|
/// Whether a copy of another station's profile is one its station pauses (`share.pausable`, said since 2026-11-11; a
/// station from before refuses `enabled` on a copy).
fn profile_pausable(p : Json?) -> Bool {
  profile_copy(p) && flag(field(p, "share"), "pausable") && has(p, "enabled")
}

///|
/// Whether a subscription's sign-in is under way (its `login`'s state).
fn signing_in(p : Json?) -> Bool {
  ["starting", "needs_code", "needs_approval", "verifying"].contains(text(field(p, "login"), "state"))
}

///|
/// Whether it asks to be signed in first: its check says so, it is being signed in, or its last sign-in failed.
fn sign_asked(p : Json?) -> Bool {
  text(field(p, "check"), "state") == "login" || signing_in(p) || text(field(p, "login"), "state") == "failed"
}

///|
/// The blocks of the page by what each is, as the profile is now: what to do first (signing it in, else its trouble's
/// next step), its allowance, what it spent, who uses it, the stations it is on; its models and how it runs, whom it is
/// shared with, the workspaces it serves, the account itself and its variables (a copy of another station's: none of
/// those it does not set). One come or gone opens or closes where it is.
fn profile_keys(core : Core, here : () -> Here, o : () -> Json?, p : () -> Json?, entry : () -> Json?) -> Array[String] {
  ignore(core)
  ignore(here)
  let pv = p()
  let access = field(pv, "access")
  let kind = text(access, "kind")
  let copy = profile_copy(pv)
  let machine = flag(pv, "machine")
  let signs_in = kind == "subscription" || flag(access, "login")
  let asked = sign_asked(pv)
  let out : Array[String] = []
  if !copy && signs_in && !machine && asked {
    out.push("sign-in")
  } else if field(pv, "trouble") is Some(Object(_)) && text(field(pv, "trouble"), "action") != "login" {
    out.push("trouble")
  }
  out.push("quota")
  out.push("usage")
  if profile_users(o(), pv).length() > 0 {
    out.push("used-by")
  }
  if entry() is Some(_) && !items(entry(), "places").is_empty() {
    out.push("stations")
  }
  if !copy {
    out.push("models")
    // how it runs, in one section (the web's two of the same title: fast mode, and the background on a message)
    if profile_fast(pv) || profile_background(pv) {
      out.push("run")
    }
  }
  if has(o(), "sharing") && !(field(o(), "sharing") is Some(Null)) {
    out.push("share")
  }
  if !copy {
    // (what it reads of the station's workspaces read in its block, as that is made: not asked for before it shows)
    out.push("workspaces")
    if account_shows(pv) {
      out.push("account")
    }
    if kind == "env" {
      out.push("env")
    }
  }
  out
}

///|
/// Whether it says fast mode by default (FastSection).
fn profile_fast(p : Json?) -> Bool {
  has(p, "fast") && !(field(p, "fast") is Some(Null))
}

///|
/// Whether a Claude profile says whether its agents' work goes to the background when a message comes.
fn profile_background(p : Json?) -> Bool {
  items(p, "runtimes").iter().any(fn(r) { r == "claude" }) && has(p, "backgroundOnMessage")
}

///|
/// Whether its account's own section has anything: the machine's own login, a key, or a subscription signed in and well.
fn account_shows(p : Json?) -> Bool {
  let access = field(p, "access")
  let kind = text(access, "kind")
  let machine = flag(p, "machine")
  let keyed = ["opencode-go", "anthropic-api", "api-provider"].contains(kind) && !flag(access, "login")
  let signs = (kind == "subscription" || flag(access, "login")) && !machine
  machine || keyed || (signs && !sign_asked(p))
}

///|
/// The connects bound to it, as the station's overview lists them.
fn profile_users(o : Json?, p : Json?) -> Array[Json] {
  strings(p, "usedBy").filter_map(fn(uid) {
    match items(o, "connects").search_by(fn(cn) { text(Some(cn), "id") == uid }) {
      Some(i) => Some(items(o, "connects")[i])
      None => None
    }
  })
}

///|
/// The block `key` of a profile's page (profile_keys') in node `b`, as the profile is now.
fn profile_block_node(
  b : @view.View,
  core : Core,
  here : () -> Here,
  address : String,
  id : String,
  s : () -> Json?,
  o : () -> Json?,
  p : () -> Json?,
  entry : () -> Json?,
  open : ProfileOpen,
  stint : () -> Int,
  tips : @sf.TipLayer?,
  key : String,
) -> Unit {
  match key {
    "sign-in" => profile_sign_in_node(b, core, address, id, s, p, open)
    "trouble" => profile_trouble_node(b, core, address, id, s, p, open)
    "quota" => profile_quota_node(b, core, address, id, p, tips)
    "usage" => profile_usage_node(b, core, here, address, id, s, entry)
    "used-by" => profile_used_by_node(b, core, address, o, p)
    "stations" => profile_stations_node(b, core, address, entry)
    "models" => profile_models_node(b, core, here, address, id, p)
    "run" => profile_run_node(b, core, address, id, p)
    "share" => profile_share_node(b, core, address, id, s, p, entry)
    "workspaces" => profile_workspaces_node(b, core, address, id, p, stint)
    "account" => profile_account_node(b, core, address, id, s, p)
    "env" => profile_env_node(b, core, address, id, p, open, tips)
    _ => ()
  }
}

///|
/// Its head (AccountView's identity) in node `h`: its provider's mark, its name (renamed here, but for the machine's own
/// and a copy) and the runtimes it serves, what it is (its station's name where it is on several), its last check and
/// when, checking again (its allowance read again with it); its ⋯.
fn profile_head_node(
  h : @view.View,
  core : Core,
  here : () -> Here,
  address : String,
  id : String,
  s : () -> Json?,
  p : () -> Json?,
  entry : () -> Json?,
  tips : @sf.TipLayer?,
) -> Unit {
  let on = [("station", address), ("id", id)]
  // what it is, in a line: its kind, the address signed in (when not its name), where it is
  let facts = fn() {
    let pv = p()
    let email = text(pv, "email")
    // of an account on several stations, this station's (each's own part is under 各 station), not all of them
    let several = items(entry(), "members").filter(fn(m) { text(Some(m), "role") != "user" }).length() > 1
    let place = if several {
      @sf.t("web-pages.profiles.onStation", args=[("station", text(s(), "name"))])
    } else {
      text(entry(), "where")
    }
    join([text(pv, "kindText"), text(pv, "planText"), if email != text(pv, "name") { email } else { "" }, place], " · ")
  }
  @sf.own_head_node(
    h,
    fn(m, _) {
      m.pick(at_once=true, fn() { (text(p(), "runtime"), text(field(p(), "access"), "kind"), text(p(), "providerMark")) }, fn(l, k) {
        @sf.provider_logo_node(l, k.0, k.1, pf_mark_glyph, k.2) |> ignore
      })
    },
    fn() { text(p(), "name") },
    rename=fn() { profile_rename(core, address, @signals.untracked(p)) },
    renames=fn() { !flag(p(), "machine") && !profile_copy(p()) },
    rename_label=fn() { @sf.t("web-pages.settings.stations.rename") },
    // its new name shows while it is saved
    busy=fn() { is_doing(core, ["profile.put"], on) },
    tags=fn(t) { runtime_tags_node(t, p) },
    lines=fn() { [facts()] },
    state=fn(st) { profile_state_node(st, core, address, id, p, tips) },
    actions=fn(a) { profile_more_node(a, core, here, address, p) },
  )
}

///|
/// How it stands under its head (profileState) in node `st`: its check's pill where it is not well, what the check said
/// and when, words of one line (short of room, cut from its end: when it was checked first; nothing of it moving under
/// the rest as what the check said changes), checking again (its allowance read again with it), a spinner while it is.
fn profile_state_node(st : @view.View, core : Core, address : String, id : String, p : () -> Json?, tips : @sf.TipLayer?) -> Unit {
  let on = [("station", address), ("id", id)]
  let checking = fn() { is_doing(core, ["profile.check"], on) }
  st.show(at_once=true, fn() { text(p(), "checkTone") != "green" }, fn(x) {
    // (its tone as the check has it now: the pill made again in it)
    x.pick(at_once=true, fn() { pill_tone(text(p(), "checkTone")) }, fn(y, tone) { @sf.pill_node(y, fn() { text(p(), "checkText") }, tone~) |> ignore })
  })
  st.box(fn(b) {
    @sf.style_node(b, fn() { pf_state })
    b.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
    @sf.words_node(b, fn() {
      let ago = text(field(field(field(p(), "check"), "time"), "checkedAt"), "ago")
      let when = if ago != "" { @sf.t("web-pages.profiles.checkedAt", args=[("time", ago)]) } else { "" }
      join([text(p(), "checkLine"), when], " · ")
    }, fn() { pf_check_words })
    |> ignore
    @sf.icon_action_node(
      b,
      "refresh",
      fn() { @sf.t("web-pages.profiles.recheck") },
      fn() {
        @settings.act(core, @sf.t("web-pages.profiles.recheck"), "profile.check", obj([("station", str(address)), ("id", str(id))]))
        // (its allowance read again with it: how much is left, as of now)
        let q = field(@signals.untracked(p), "quota")
        if q is Some(Object(_)) && text(q, "state") != "unsupported" {
          @settings.act(core, @sf.t("web-pages.profiles.refresh"), "profile.quota", obj([("station", str(address)), ("id", str(id))]))
        }
      },
      disabled=fn() { checking() || (has(p(), "enabled") && !flag(p(), "enabled")) },
      tips?,
    )
    |> ignore
    b.show(at_once=true, checking, fn(x) { @sf.spinner_node(x, size=pf_spin) |> ignore })
  })
  |> ignore
}

///|
/// The tone of a pill by the core's (red, amber, blue, green).
fn pill_tone(tone : String) -> @sf.PillTone {
  match tone {
    "red" => Red
    "amber" => Amber
    "blue" => Blue
    "green" => Green
    _ => Neutral
  }
}

///|
/// The runtimes it serves (ui.tsx RuntimeTags) in node `t`, a tag each (its short name: its maker's mark is the head's),
/// and 自动决策's, as it says them now.
fn runtime_tags_node(t : @view.View, p : () -> Json?) -> Unit {
  let tags = fn() {
    let out = items(p(), "runtimes").filter_map(fn(r) { if r is String(rt) { Some(runtime_tag(rt)) } else { None } })
    if items(p(), "uses").iter().any(fn(u) { u == "decision" }) {
      out.push(@sf.t("common.decision"))
    }
    out.mapi(fn(i, w) { (i, w) })
  }
  t.box(fn(r) {
    @sf.style_node(r, fn() { pf_tags })
    r.each(tags, fn(x) { x.0 }, fn(tag, x) {
      @sf.tag_node(tag, fn() { x.get().1 })
    })
  })
  |> ignore
}

///|
/// A runtime's short name on its tag (ui.tsx RUNTIME_TAG).
fn runtime_tag(r : String) -> String {
  match r {
    "claude" => "CC"
    "codex" => "Codex"
    "dsh" => "DSH"
    "grok" => "GROK"
    "cursor" => "Cursor"
    "devin" => "Devin"
    "hermes" => "Hermes"
    "agy" => "AGY"
    _ => r
  }
}

///|
/// Its ⋯ in node `a` (a copy of another station's: only where its station says it pauses it, `share.pausable`; one from
/// before refuses that): pressed, its menu beside it (profile_menu), lined up at its end.
fn profile_more_node(a : @view.View, core : Core, here : () -> Here, address : String, p : () -> Json?) -> Unit {
  a.show(at_once=true, fn() { !profile_copy(p()) || profile_pausable(p()) }, fn(m) {
    // (beside itself, as it is pressed)
    @sf.icon_action_opens_node(m, "more", fn() { @sf.t("common.more") }, fn(at) {
      let (x, y, w, h) = at.placed_window_now()
      profile_menu(core, here(), address, @signals.untracked(p), At(x, y, w, h))
    })
    |> ignore
  })
}

///|
/// Its menu, beside what opened it (`from`): renaming it (but the machine's own), turning a key's off or on, deleting
/// it (the machine's own login: stopping it, the login stays the machine's), asked first. A copy of another station's
/// is edited there: here only whether this station uses it (停用, 启用: `profile.put` `enabled`, kept by its station as
/// the copy is refreshed).
fn profile_menu(core : Core, here : Here, address : String, p : Json?, from : @sf.Beside) -> Unit {
  let id = text(p, "id")
  let machine = flag(p, "machine")
  let copy = profile_copy(p)
  let access = field(p, "access")
  let keyed = ["api-provider", "anthropic-api", "opencode-go"].contains(text(access, "kind")) && !flag(access, "login")
  let can_disable = (keyed && has(p, "enabled")) || profile_pausable(p)
  let item = if machine { @sf.t("web-pages.profiles.disable") } else { @sf.t("web-pages.profiles.delete") }
  let remove = fn() {
    let (title, words) = if machine {
      (
        @sf.t("web-pages.profiles.disableConfirm", args=[("name", text(p, "name"))]),
        @sf.t("web-pages.profiles.disableBody", args=[("name", "still.fail"), ("runtime", @settings.runtime_label(text(p, "runtime")))]),
      )
    } else {
      (@sf.t("web-pages.archive.deleteConfirm", args=[("title", text(p, "name"))]), @sf.t("web-pages.profiles.deleteBody", args=[("name", "still.fail")]))
    }
    confirm(title, words, item, danger=true, fn() {
      // gone from here at once: the list shows it until the station has dropped it
      place_pick.remove(place_key(here.workspace, "profiles"))
      (core.pop)()
      @settings.act(
        core,
        item,
        "profile.delete",
        obj([("station", str(address)), ("id", str(id))]),
        done=if machine { @sf.t("web-pages.profiles.disabled") } else { @sf.t("web-pages.profiles.deleted") },
      )
    })
  }
  let items : Array[@sf.MenuItem?] = []
  if !machine && !copy {
    items.push(Some(@sf.menu_item_of(@sf.t("web-pages.settings.stations.rename"), icon="edit", fn() { profile_rename(core, address, p) })))
  }
  if can_disable {
    let enabled = flag(p, "enabled")
    let label = if enabled { @sf.t("web-pages.profiles.disable") } else { @sf.t("web-pages.connect.enable") }
    let change = fn() {
      @settings.act(
        core,
        label,
        "profile.put",
        obj([("station", str(address)), ("id", str(id)), ("input", obj([("enabled", Json::boolean(!enabled))]))]),
        done=if enabled { @sf.t("web-pages.profiles.disabled") } else { @sf.t("web-pages.connect.enabled") },
      )
    }
    items.push(Some(@sf.menu_item_of(label, icon="power", disabled=is_doing(core, ["profile.put"], [("station", address), ("id", id)]), fn() {
      if enabled {
        let words = @sf.t(if copy { "web-pages.profiles.disableCopyBody" } else { "web-pages.profiles.disableKeyBody" })
        confirm(@sf.t("web-pages.profiles.disableConfirm", args=[("name", text(p, "name"))]), words, label, danger=true, change)
      } else {
        change()
      }
    })))
  }
  if !copy {
    items.push(Some(@sf.menu_item_of(item, icon="trash", danger=true, remove)))
  }
  @sf.menu(items, from~, along=End)
}

// ── what to do first ────────────────────────────────────────────────────

///|
/// Signing a subscription in without a terminal (SignIn), on a card in node `b`: still.fail runs the runtime's login on
/// its machine and this relays the browser's steps. Not under way: why (needed, or again), the way to start it, the
/// command to run by hand (shown as its button says). Under way: what the person does in the browser
/// (login_steps_node), there or in the station's own, 取消.
fn profile_sign_in_node(
  b : @view.View,
  core : Core,
  address : String,
  id : String,
  s : () -> Json?,
  p : () -> Json?,
  open : ProfileOpen,
) -> Unit {
  let on = [("station", address), ("id", id)]
  let params = fn() { obj([("station", str(address)), ("id", str(id))]) }
  let job = fn() { field(p(), "login") }
  let state = fn() { text(job(), "state") }
  let provider = fn() { text(p(), "signInProvider") }
  let needed = fn() { text(field(p(), "check"), "state") == "login" || signing_in(p()) }
  let command = fn() { text(p(), "loginCommand") }
  @sf.page_card_node(b, footed=true, fn(k) {
    k.pick(at_once=true, fn() { signing_in(p()) }, fn(q, active) {
      q.gap(Is(pf_card_gap)) |> ignore
      if !active {
        @sf.card_lines_node(
          q,
          fn() {
            if needed() {
              @sf.t("web-pages.profiles.notSignedIn", args=[("provider", provider())])
            } else {
              @sf.t("web-pages.profiles.subscriptionSignIn", args=[("provider", provider())])
            }
          },
          note=fn() {
            match state() {
              "failed" => ""
              "done" => @sf.t("web-pages.profiles.signedInSwitch")
              _ => @sf.t("web-pages.profiles.signInNote", args=[("name", "still.fail")])
            }
          },
          bad=fn() { if state() == "failed" { @sf.t("web-pages.profiles.lastFailed", args=[("error", text(job(), "error"))]) } else { "" } },
        )
        q.show(fn() { open.command.get() && command() != "" }, fn(x) {
          @sf.copy_command_node(x, command, copy=@sf.t("common.copy"), copied=@sf.t("common.copied"))
        })
        @sf.card_foot_node(q, fn(f) {
          @sf.button_node(
            f,
            fn() { if state() == "done" || !needed() { @sf.t("web-pages.signIn.again") } else { @sf.t("web-pages.profiles.signIn") } },
            fn() { @settings.act(core, @sf.t("web-pages.profiles.signIn"), "profile.login", params()) },
            tone=Primary,
            icon="log-in",
            busy=fn() { is_doing(core, ["profile.login"], on) },
          )
          |> ignore
          // (the way to sign in on the machine at the foot's end, in the card's corner concentric with it: where its
          // words are long (English) it stood just short of the corner, its ground under the hand off the corner's)
          f.box(fn(sp) { sp.grow(Is(1.0)) |> ignore }) |> ignore
          f.show(at_once=true, fn() { command() != "" }, fn(x) {
            @sf.button_node(
              x,
              // (the short words, the phone's: beside 登录 on a card's foot they fit a phone, the long ones ran past its
              // edge)
              fn() { if open.command.get() { @sf.t("web-pages.profiles.collapse") } else { @sf.t("android-settings.login.manualShort") } },
              fn() { open.command.set(!open.command.untracked()) },
              tone=Ghost,
            )
            |> ignore
          })
        })
      } else {
        @sf.card_lines_node(q, fn() { @sf.t("web-pages.profiles.signingIn", args=[("provider", provider())]) }, note=fn() {
          @sf.t("web-pages.profiles.signingInNote")
        })
        login_steps_node(
          q,
          core,
          job,
          provider,
          fn() { is_doing(core, ["profile.loginCode"], on) },
          fn(code, sent) {
            @settings.act(
              core,
              @sf.t("web-pages.profiles.finish"),
              "profile.loginCode",
              obj([("station", str(address)), ("id", str(id)), ("code", str(code))]),
              then=fn(_) { sent() },
            )
          },
          open.copied,
          in_station=(fn() { text(s(), "name") }, fn() { is_doing(core, ["profile.loginBrowser"], on) }, fn(what) {
            @settings.act(core, what, "profile.loginBrowser", params(), then=fn(v) { (core.open_screen)(address, text(Some(v), "screen")) })
          }),
        )
        @sf.card_foot_node(q, fn(f) {
          @sf.button_node(
            f,
            fn() { @sf.t("common.cancel") },
            fn() { @settings.act(core, @sf.t("common.cancel"), "profile.cancelLogin", params()) },
            tone=Ghost,
            busy=fn() { is_doing(core, ["profile.cancelLogin"], on) },
            card_words=true,
          )
          |> ignore
        })
      }
    })
  })
}

///|
/// What the person does in the browser for a sign-in under way (LoginSteps), in node `v`, as its `job` says it now: the
/// link and the code to paste back (Claude, Devin), the code to enter on the page that opens (DeviceCode: Codex, Grok,
/// OpenCode, Kimi, Cursor's page alone: copied as it is opened, `copied` saying so); while it is checked or added, said
/// so. `send`: a code pasted back sent, then `sent` (its field emptied); `sending` while it is. Where its job says the
/// station has a browser of its own (`browser`), the same page there (`in_station`: the station's name, whether it is
/// being opened, and what opens it given what it is called) is a button beside the page's button; copying the link
/// stays in the ⋯ after them.
pub fn login_steps_node(
  v : @view.View,
  core : Core,
  job : () -> Json?,
  provider : () -> String,
  sending : () -> Bool,
  send : (String, () -> Unit) -> Unit,
  copied : @signals.Signal[Bool],
  in_station? : (() -> String, () -> Bool, (String) -> Unit),
) -> Unit {
  let state = fn() { text(job(), "state") }
  let url = fn() { text(job(), "url") }
  // (1 a code to paste back, 2 a device's code, else a wait: 3 checked, 4 added, 5 its link made)
  let step = fn() {
    match state() {
      "needs_code" if url() != "" => 1
      "needs_approval" if url() != "" => 2
      "verifying" => 3
      "done" => 4
      _ => 5
    }
  }
  // beside the page's button where the station has a browser of its own (回到 … while its tab is open); in the ⋯ after
  // them, its address copied (for a browser elsewhere)
  let station_browser = fn(r : @view.View) {
    match in_station {
      Some((name, busy, go)) =>
        r.show(at_once=true, fn() { flag(job(), "browser") }, fn(x) {
          @sf.button_node(
            x,
            fn() {
              @sf.t(
                if text(job(), "screen") != "" { "common.login.backToStation" } else { "common.login.openInStation" },
                args=[("station", name())],
              )
            },
            fn() {
              let j = @signals.untracked(job)
              let label = @sf.t(
                if text(j, "screen") != "" { "common.login.backToStation" } else { "common.login.openInStation" },
                args=[("station", @signals.untracked(name))],
              )
              let claude = @signals.untracked(provider) == "Claude" && text(j, "screen") == ""
              @settings.confirm_claude_auth(claude, fn() { go(label) })
            },
            tone=Plain,
            busy~,
          )
          |> ignore
        })
      None => ()
    }
  }
  let page_more = fn(r : @view.View) {
    // (beside the box that holds it, as it is pressed)
    r.box(fn(k) {
      @sf.icon_button_node(k, "more", fn() { @sf.t("common.login.otherWays") }, fn() {
        let j = @signals.untracked(job)
        let link = text(j, "url")
        let items = [Some(@sf.menu_item_of(@sf.t("common.link.copy"), fn() { @sfbase.copy_out(link, said=@sf.t("common.link.copied")) }))]
        let (x, y, w, h) = k.placed_window_now()
        @sf.menu(items, from=At(x, y, w, h))
      })
      |> ignore
    })
    |> ignore
  }
  let waiting = fn(q : @view.View, words : () -> String) {
    q.box(fn(l) {
      @sf.style_node(l, fn() { pf_wait_line })
      @sf.spinner_node(l, size=pf_spin) |> ignore
      @sf.words_node(l, words, fn() { pf_muted }) |> ignore
    })
    |> ignore
  }
  v.pick(at_once=true, step, fn(q, k) {
    q.gap(Is(pf_card_gap)) |> ignore
    match k {
      1 => {
        q.box(fn(st) {
          @sf.style_node(st, fn() { pf_step })
          @sf.words_node(st, fn() {
            if provider() == "Devin" {
              @sf.t("web-pages.profiles.step1Devin", args=[("name", "still.fail")])
            } else {
              @sf.t("web-pages.profiles.step1", args=[("name", "still.fail")])
            }
          }, fn() { pf_words })
          |> ignore
          st.box(fn(r) {
            @sf.style_node(r, fn() { pf_step_buttons })
            r.width_share(Is(1.0)).wraps(Is(Some(pf_step_buttons_gap))) |> ignore
            @sf.button_node(r, fn() { @sf.t("web-pages.profiles.openAuth") }, fn() {
              let link = @signals.untracked(url)
              @settings.confirm_claude_auth(@signals.untracked(provider) == "Claude", fn() { (core.open_link)(link) })
            }, tone=Primary, icon="external")
            |> ignore
            station_browser(r)
            page_more(r)
          })
          |> ignore
        })
        |> ignore
        q.box(fn(st) {
          @sf.style_node(st, fn() { pf_step })
          @sf.words_node(st, fn() {
            if provider() == "Devin" {
              @sf.t("web-pages.profiles.step2Devin")
            } else {
              @sf.t("web-pages.profiles.step2")
            }
          }, fn() { pf_words })
          |> ignore
          let f = @ui.Field::new()
          let typed = fn() { f.text().trim(chars=" \t\n").to_owned() }
          let go = fn() {
            let code = @signals.untracked(typed)
            if code != "" && !@signals.untracked(sending) {
              send(code, fn() { f.set("") })
            }
          }
          st.box(fn(r) {
            @sf.style_node(r, fn() { pf_input_row })
            // (as wide as the step, its steps standing at their start: the field what the button leaves)
            r.width_share(Is(1.0)) |> ignore
            r.box(fn(g) {
              @sf.style_node(g, fn() { pf_input_grow }, in_row=true)
              g.min_width(Is(Some(0.0))) |> ignore
              @sf.input_node(g, f, placeholder=@sf.t("web-pages.profiles.pasteCode"), submitted=fn(_) { go() }) |> ignore
            })
            |> ignore
            @sf.button_node(r, fn() { @sf.t("web-pages.profiles.finish") }, go, tone=Primary, busy=sending, disabled=fn() { typed().is_empty() })
            |> ignore
          })
          |> ignore
        })
        |> ignore
      }
      2 => {
        // no code where the page only asks to confirm (Cursor's); OpenCode's and Kimi's carry it in their address
        let code = fn() { text(job(), "userCode") }
        let filled = fn() { provider() == "OpenCode" || provider() == "Kimi" || code() == "" }
        q.box(fn(d) {
          @sf.style_node(d, fn() { pf_device })
          d.show(at_once=true, fn() { code() != "" }, fn(x) {
            x.box(fn(c) {
              @sf.style_node(c, fn() { pf_device_code })
              c.box(fn(w) {
                w
                .words_runs(By(fn() { [@ui.span(code(), mono=true)] }), look=@ui.style_words(pf_device_code_words))
                .ink(By(fn() { @ui.style_ink(pf_device_code_words) }))
                |> ignore
              })
              |> ignore
            })
            |> ignore
          })
          d.box(fn(r) {
            @sf.style_node(r, fn() { pf_step_buttons })
            r.width_share(Is(1.0)).wraps(Is(Some(pf_step_buttons_gap))) |> ignore
            @sf.button_node(
              r,
              fn() {
                if filled() {
                  @sf.t("web-pages.profiles.openAuth")
                } else if copied.get() {
                  @sf.t("web-pages.profiles.copiedReopen")
                } else {
                  @sf.t("web-pages.profiles.copyOpen")
                }
              },
              fn() {
                let link = @signals.untracked(url)
                let words = @signals.untracked(code)
                let filled = @signals.untracked(filled)
                @settings.confirm_claude_auth(@signals.untracked(provider) == "Claude", fn() {
                  if !filled {
                    @ui.clipboard_set(words)
                    copied.set(true)
                  }
                  (core.open_link)(link)
                })
              },
              tone=Primary,
              icon="external",
            )
            |> ignore
            station_browser(r)
            page_more(r)
          })
          |> ignore
          @sf.words_node(d, fn() {
            if code() == "" {
              @sf.t("web-pages.profiles.deviceCodeNoteCursor")
            } else {
              match provider() {
                "OpenCode" => @sf.t("web-pages.profiles.deviceCodeNoteOpencode")
                "Kimi" => @sf.t("web-pages.profiles.deviceCodeNoteKimi")
                "Grok" => @sf.t("web-pages.profiles.deviceCodeNoteGrok")
                _ => @sf.t("web-pages.profiles.deviceCodeNote", args=[("name", "still.fail")])
              }
            }
          }, fn() { pf_muted })
          |> ignore
        })
        |> ignore
      }
      3 => waiting(q, fn() { @sf.t("web-pages.profiles.finishing") })
      4 => waiting(q, fn() { @sf.t("web-pages.profiles.adding") })
      _ => waiting(q, fn() { @sf.t("web-pages.profiles.generatingLink", args=[("provider", provider())]) })
    }
  })
}

///|
/// What is wrong with it and its next step (ProfileRecovery), on a card in node `b` where it is in trouble (not signing
/// in: that is its sign-in's): why, what to do, a command to run where that is it, the button that does it (a key asked
/// for, its variables opened to be written, its allowance read again, checked again).
fn profile_trouble_node(
  b : @view.View,
  core : Core,
  address : String,
  id : String,
  s : () -> Json?,
  p : () -> Json?,
  open : ProfileOpen,
) -> Unit {
  let on = [("station", address), ("id", id)]
  let issue = fn() { field(p(), "trouble") }
  let action = fn() { text(issue(), "action") }
  let online = fn() { flag(s(), "online") }
  let checking = fn() { is_doing(core, ["profile.check"], on) }
  let refreshing = fn() { is_doing(core, ["profile.quota"], on) }
  let check = fn() {
    @settings.act(core, @sf.t("android-settings.profile.checkWhat"), "profile.check", obj([("station", str(address)), ("id", str(id))]), done=@sf.t("android-settings.profile.checked"))
  }
  @sf.page_card_node(b, footed=true, fn(k) {
    @sf.card_lines_node(
      k,
      fn() { text(issue(), "title") },
      words=fn() { text(issue(), "detail") },
      note=fn() {
        join([text(issue(), "next"), if online() { "" } else { @sf.t("android-settings.profile.offline", args=[("name", text(s(), "name"))]) }], "\n")
      },
      bad=fn() { failed_of(core, ["profile.check", "profile.quota"], on).unwrap_or("") },
    )
    k.show(at_once=true, fn() { action() == "command" }, fn(x) {
      @sf.copy_command_node(x, fn() { text(p(), "loginCommand") }, copy=@sf.t("common.copy"), copied=@sf.t("common.copied"))
    })
    @sf.card_foot_node(k, fn(f) {
      @sf.button_node(
        f,
        fn() { text(issue(), "label") },
        fn() {
          match @signals.untracked(action) {
            "key" => ask_key(core, address, @signals.untracked(p))
            "env" => open.env.set(true)
            "quota" =>
              @settings.act(core, @sf.t("android-settings.quota.checkWhat"), "profile.quota", obj([("station", str(address)), ("id", str(id))]), done=@sf.t("android-settings.quota.updated"))
            _ => check()
          }
        },
        tone=Primary,
        busy=fn() { checking() || refreshing() },
        disabled=fn() { !online() },
        card_words=true,
      )
      |> ignore
      f.show(at_once=true, fn() { action() == "key" || action() == "env" }, fn(x) {
        @sf.button_node(x, fn() { @sf.t("android-settings.profile.recheck") }, check, tone=Ghost, busy=checking, disabled=fn() { !online() })
        |> ignore
      })
    })
  })
}

// ── its allowance and what it spent ─────────────────────────────────────

///|
/// What is left of its allowance (QuotaSection) in node `b`: each window as a dial, when it was read under them, reading
/// it again at its title's end; its credits and its resets (resetting one asked first), a row each.
fn profile_quota_node(b : @view.View, core : Core, address : String, id : String, p : () -> Json?, tips : @sf.TipLayer?) -> Unit {
  let on = [("station", address), ("id", id)]
  let params = fn() { obj([("station", str(address)), ("id", str(id))]) }
  let quota = fn() { field(p(), "quota") }
  let windows = fn() { items(quota(), "windows") }
  let credits = fn() { text(quota(), "creditsText") }
  @sf.section_node(
    b,
    fn() { @sf.t("web-pages.profiles.quota") },
    ends=fn(e) {
      @sf.action_node(
        e,
        fn() { @sf.t("web-pages.profiles.refresh") },
        fn() { @settings.act(core, @sf.t("web-pages.profiles.refresh"), "profile.quota", params()) },
        icon="refresh",
        busy=fn() { is_doing(core, ["profile.quota"], on) },
        disabled=fn() { has(p(), "enabled") && !flag(p(), "enabled") },
      )
    },
    fn(sec) {
      @sf.group_node(sec, fn(g) {
        // (0 not read yet, 1 what the core could not say, 2 its windows, 3 none of them but its credits)
        let what = fn() {
          let q = quota()
          if q is (None | Some(Null)) {
            0
          } else if text(q, "state") != "ok" || windows().length() == 0 {
            if credits() == "" {
              1
            } else {
              3
            }
          } else {
            2
          }
        }
        g.show(at_once=true, fn() { what() == 0 }, fn(x) { said_row_node(x, fn() { @sf.t("web-main.quota.unchecked") }) })
        g.show(at_once=true, fn() { what() == 1 }, fn(x) {
          said_row_node(x, fn() {
            match opt_text(quota(), "detail") {
              Some(d) => d
              None => @sf.t("web-main.quota.unknown")
            }
          })
        })
        g.show(at_once=true, fn() { what() == 2 }, fn(x) {
          @sf.block_node(x, fn(bl) {
            @sf.dials_node(bl, fn() { quota_dials_of(windows()) }, lines=2)
            bl.show(at_once=true, fn() { text(field(field(quota(), "time"), "checkedAt"), "ago") != "" }, fn(w) {
              @sf.words_node(w, fn() {
                @sf.t("android-settings.quota.checkedAt", args=[("ago", text(field(field(quota(), "time"), "checkedAt"), "ago"))])
              }, fn() { @sf.caption })
              |> ignore
            })
          })
        })
        g.show(at_once=true, fn() { credits() != "" }, fn(x) {
          @sf.link_row_node(x, fn() { @sf.t("android-settings.quota.credits") }, fn() {  }, value=credits, goes=false)
        })
        // Each kind of reset it holds, a row each: how many are left at its end, where they are seen at once (the user,
        // 2026-11-10), what one gives back and till when under its name; the row pressed asks first, then uses one.
        g.each(fn() { items(quota(), "resets") }, fn(r) { text(Some(r), "kind") }, fn(x, rs) {
          let rv = fn() { Some(rs.get()) }
          let busy = fn() { is_doing(core, ["profile.resetQuota"], on) }
          let usable = fn() { count(rv(), "left") > 0 && flag(rv(), "usable") }
          // (lit only when one can be used now: one usable only at a limit says why under it, unpressed)
          x.pick(at_once=true, fn() { (usable(), usable() && !busy()) }, fn(r, k) {
            let (lit, goes) = k
            @sf.link_row_node(
              r,
              fn() { text(rv(), "title") },
              fn() {
                let one = @signals.untracked(rv)
                let name = text(@signals.untracked(p), "name")
                let body = match opt_text(one, "refills") {
                  Some(refills) =>
                    @sf.t("web-pages.profiles.resetKindBody", args=[("name", name), ("kind", text(one, "title")), ("refills", refills)])
                  None => @sf.t("web-pages.profiles.resetBody", args=[("name", name), ("n", count(one, "left").to_string())])
                }
                let asked = match opt_text(one, "id") {
                  Some(kind) => obj([("station", str(address)), ("id", str(id)), ("reset", str(kind))])
                  None => params()
                }
                confirm(
                  @sf.t("web-pages.profiles.resetConfirm"),
                  body,
                  @sf.t("web-pages.profiles.resetAction"),
                  fn() {
                    @settings.act(core, @sf.t("web-pages.profiles.resetAction"), "profile.resetQuota", asked, done=@sf.t("web-pages.profiles.quotaReset"))
                  },
                )
              },
              note=fn() { reset_note(rv()) },
              value=fn() { text(rv(), "leftText") },
              value_lit=lit,
              chevron=false,
              goes~,
              tail=fn(t) { doing_mark_node(t, busy, fn() { failed_of(core, ["profile.resetQuota"], on) }, tips?) },
            )
          })
        })
      })
    },
  )
}

///|
/// Under a kind of reset's name: what one gives back, and when they end or why none can be used now.
fn reset_note(r : Json?) -> String {
  [opt_text(r, "refills").unwrap_or(""), text(r, "text")].filter(fn(w) { w != "" }).join(" · ")
}

///|
/// What it spent in the last 7 days (UsageSection) in node `b`, once the usage view is read: its cost (its share of the
/// workspace's under it) and tokens (the model it used most under them) as the usage view counts them for it (its calls
/// not, nor what its tokens are made of: they say nothing a person acts on, the user 2026-10-31), side by side; on
/// several stations, here's alone. The way to the whole usage at its heading.
fn profile_usage_node(
  b : @view.View,
  core : Core,
  here : () -> Here,
  address : String,
  id : String,
  s : () -> Json?,
  entry : () -> Json?,
) -> Unit {
  let usage = fn() { (core.topic)("usage", { "scope": str(here().workspace), "days": Json::number(7.0) }).get().value }
  let item = fn() -> Json? {
    let u = usage()
    match items(u, "lists").search_by(fn(l) { text(Some(l), "key") == "profiles" }) {
      Some(i) => {
        let list = items(Some(items(u, "lists")[i]), "items")
        match list.search_by(fn(x) { text(Some(x), "key") == address + "/" + id }) {
          Some(k) => Some(list[k])
          None => None
        }
      }
      None => None
    }
  }
  b.show(at_once=true, fn() { usage() is Some(_) }, fn(u) {
    @sf.section_node(
      u,
      fn() {
        if items(entry(), "members").length() > 1 {
          @sf.t("web-pages.profiles.usageHere", args=[("station", text(s(), "name"))])
        } else {
          @sf.t("web-pages.profiles.usage")
        }
      },
      ends=fn(e) {
        @sf.action_node(e, fn() { @sf.t("web-pages.profiles.usageAll") }, fn() {
          @sfbase.history_push()
          app.nav.push(Setting(Usage))
        }, icon="chart")
      },
      fn(sec) {
        sec.pick(at_once=true, fn() { item() is Some(_) }, fn(x, has) {
          if has {
            @sf.figures_node(x, fn() {
              let it = item()
              [
                (@sf.t("web-pages.profiles.usageCost"), text(it, "costText"), @sf.t("web-pages.profiles.usageShare", args=[("share", text(it, "shareText"))])),
                ("Tokens", text(it, "tokensText"), text(it, "topModel")),
              ]
            })
          } else {
            @sf.group_node(x, fn(g) {
              g.pick(fn() { flag(field(usage(), "wait"), "reading") }, fn(y, reading) {
                if reading {
                  @sf.block_node(y, fn(bl) { @sf.wait_line_node(bl, fn() { @sf.t("common.reading") }) |> ignore })
                } else {
                  said_row_node(y, fn() { @sf.t("web-pages.profiles.usageNone") })
                }
              })
            })
          }
        })
      },
    )
  })
}

// ── who uses it, where it is ────────────────────────────────────────────

///|
/// Who uses it (the connects bound to it: Slack, Feishu) in node `b`, a row each, the model it runs at its end, to the
/// connect's page.
fn profile_used_by_node(b : @view.View, core : Core, address : String, o : () -> Json?, p : () -> Json?) -> Unit {
  @sf.section_node(b, fn() { @sf.t("web-pages.profiles.usedBy") }, fn(sec) {
    @sf.group_node(sec, fn(g) {
      g.each(fn() { profile_users(o(), p()) }, fn(cn) { text(Some(cn), "id") }, fn(r, cn) {
        let cv = fn() { Some(cn.get()) }
        let model = fn() {
          match opt_text(cv(), "modelName") {
            Some(m) => m
            None =>
              match opt_text(p(), "model") {
                Some(m) => match text(field(p(), "names"), m) { "" => m; n => n }
                None => @sf.t("web-pages.profiles.defaultModel")
              }
          }
        }
        let cid = @signals.untracked(fn() { text(cv(), "id") })
        @sf.link_row_node(
          r,
          fn() { text(cv(), "name") },
          fn() { (core.push)(Connect(address, cid)) },
          value=model,
          title_cut=true,
          value_cut=true,
          lead=LeadMade(fn(l) { @sf.avatar_node(l, fn() { text(cv(), "id") }, fn() { text(cv(), "name") }, fn() { "" }, pf_user_avatar) }),
        )
      })
    })
  })
}

///|
/// Each station that has the account, once, in node `b`: how it stands there at its end, this one's said, another's
/// that has a profile of it opening that one.
fn profile_stations_node(b : @view.View, core : Core, here_station : String, entry : () -> Json?) -> Unit {
  @sf.section_node(b, fn() { @sf.t("web-pages.profiles.account.each") }, fn(sec) {
    @sf.group_node(sec, fn(g) {
      g.each(fn() { items(entry(), "places") }, fn(m) { text(Some(m), "station") }, fn(r, m) {
        let mv = fn() { Some(m.get()) }
        let station = @signals.untracked(fn() { text(mv(), "station") })
        let pid = fn() { text(mv(), "profileId") }
        let state = fn() { field(mv(), "state") }
        let current = station == here_station
        // (how it stands there: offline, not signed in there, its lender away, else what its check says)
        let pill = fn() -> (String, @sf.PillTone) {
          if !flag(mv(), "online") {
            (@sf.t("web-pages.stations.offline"), Neutral)
          } else if pid() == "" && text(state(), "text") != "" {
            (text(state(), "text"), pill_tone(text(state(), "tone")))
          } else if !flag(mv(), "usable") {
            (@sf.t("web-pages.settings.profiles.hostAway", args=[("station", text(mv(), "sourceName"))]), Red)
          } else {
            (text(state(), "text"), pill_tone(text(state(), "tone")))
          }
        }
        r.pick(at_once=true, fn() { !current && pid() != "" }, fn(x, opens) {
          @sf.link_row_node(
            x,
            fn() { text(mv(), "stationName") },
            fn() {
              let to = @signals.untracked(pid)
              place_pick[place_key(workspace_of(station), "profiles")] = Profile(station, to)
              (core.push)(Profile(station, to))
            },
            goes=opens,
            chevron_room=true,
            title_after=fn(a) { @sf.pill_node(a, fn() { @sf.t("web-pages.connect.current") }) |> ignore },
            title_after_shown=fn() { current },
            tail=fn(t) { t.pick(at_once=true, fn() { pill().1 }, fn(y, tone) { @sf.pill_node(y, fn() { pill().0 }, tone~) |> ignore }) },
            tail_shown=fn() { pill().0 != "" },
          )
        })
      })
    })
  })
}

// ── how it runs ─────────────────────────────────────────────────────────

///|
/// Its models in node `b`: how many it runs, one row (2026-11-02 用户「既然这样就不要平铺展示了」), all of them a press away
/// in a dialog of their own (profile_models_panel). A provider that answers the automatic decisions alone: the models
/// its probe found.
fn profile_models_node(b : @view.View, core : Core, here : () -> Here, address : String, id : String, p : () -> Json?) -> Unit {
  b.pick(at_once=true, fn() { flag(p(), "decisionOnly") }, fn(x, only) {
    if only {
      @sf.section_node(x, fn() { @sf.t("web-pages.profiles.decisionModels") }, fn(sec) {
        @sf.loose_node(sec, fn(l) {
          l.show(at_once=true, fn() { strings(p(), "decisionModels").length() > 0 }, fn(c) {
            c.box(fn(chips) {
              @sf.style_node(chips, fn() { pf_chips })
              chips.wraps(Is(Some(0.0))) |> ignore
              chips.each(fn() { strings(p(), "decisionModels") }, fn(m) { m }, fn(chip, m) {
                @sf.style_node(chip, fn() { pf_chip })
                @sf.words_node(chip, fn() { m.get() }, fn() { pf_chip_words }) |> ignore
              })
            })
            |> ignore
          })
          l.show(at_once=true, fn() { text(p(), "decisionText") != "" }, fn(w) { @sf.words_node(w, fn() { text(p(), "decisionText") }, fn() { pf_muted }) |> ignore })
        })
      })
    } else {
      let all = fn() { strings(p(), "available") }
      @sf.section_node(
        x,
        fn() { @sf.t("web-pages.profiles.models") },
        note=fn() { if all().length() > 0 { @sf.t("web-pages.profiles.modelsAbout") } else { @sf.t("web-pages.profiles.modelsAboutNone") } },
        fn(sec) {
          @sf.group_node(sec, fn(g) {
            @sf.link_row_node(
              g,
              fn() { @sf.t("web-main.model.allModels") },
              fn() {
                let fusion : @signals.Signal[Json?] = @signals.signal(None)
                let p0 = @signals.untracked(p)
                if text(p0, "runtime") == "devin" && text(field(p0, "share"), "role") != "user" {
                  (core.call)(
                    "profile.fusion",
                    obj([("station", str(address)), ("id", str(id))]),
                    fn(r) {
                      if r is Ok(v) && field(Some(v), "fusion") is (Some(Object(_)) as f) {
                        fusion.set(f)
                      }
                    },
                  )
                }
                @sf.panel(
                  @sf.t("web-pages.profiles.models"),
                  fn(c, _) {
                    // (the profile as its station says it now, as its page reads it: a model added or taken off shown)
                    let listed = items(field(@settings.station_of(core, here(), address), "overview"), "profiles")
                    let now = match listed.search_by(fn(y) { text(Some(y), "id") == id }) {
                      Some(i) => Some(listed[i])
                      None => @signals.untracked(p)
                    }
                    profile_models_panel(c, core, address, now, fusion.get())
                  },
                  // (a dialog of its own, not beside its row: 2026-11-02 用户「用弹窗」)
                  from=Unanchored,
                  lists=true,
                )
              },
              value=fn() { if all().length() == 0 { @sf.t("web-pages.profiles.noModels") } else { text(p(), "modelsText") } },
            )
          })
        },
      )
    }
  })
}

///|
/// How it runs (FastSection, and a Claude profile's background on a message) in node `b`: fast mode by default, its
/// agents' work moved to the background when a message comes; each switch saved at once, what went wrong under them.
fn profile_run_node(b : @view.View, core : Core, address : String, id : String, p : () -> Json?) -> Unit {
  let on = [("station", address), ("id", id)]
  let busy = fn() { is_doing(core, ["profile.put"], on) }
  let put = fn(what : String, key : String, value : Bool, done : String) {
    @settings.act(core, what, "profile.put", obj([("station", str(address)), ("id", str(id)), ("input", obj([(key, Json::boolean(value))]))]), done~)
  }
  @sf.section_node(b, fn() { @sf.t("web-pages.profiles.run") }, fn(sec) {
    @sf.group_node(sec, fn(g) {
      g.show(at_once=true, fn() { profile_fast(p()) }, fn(r) {
        @sf.switch_row_node(
          r,
          fn() { @sf.t("web-pages.profiles.fast") },
          fn() { flag(p(), "fast") },
          fn(next) {
            put(@sf.t("web-pages.profiles.fastSave"), "fast", next, if next { @sf.t("web-pages.profiles.fastOn") } else { @sf.t("web-pages.profiles.fastOff") })
          },
          note=fn() { @sf.t("web-pages.profiles.fastLead") },
          busy~,
        )
      })
      g.show(at_once=true, fn() { profile_background(p()) }, fn(r) {
        @sf.switch_row_node(
          r,
          fn() { @sf.t("web-pages.profiles.background") },
          fn() { flag(p(), "backgroundOnMessage") },
          fn(next) {
            put(@sf.t("web-pages.profiles.background"), "backgroundOnMessage", next, if next { @sf.t("web-pages.profiles.turnedOn") } else { @sf.t("web-pages.profiles.turnedOff") })
          },
          note=fn() { if flag(p(), "backgroundOnMessage") { @sf.t("web-pages.profiles.backgroundOn") } else { @sf.t("web-pages.profiles.backgroundOff") } },
          busy~,
        )
      })
    })
    sec.show(at_once=true, fn() { failed_of(core, ["profile.put"], on) is Some(_) }, fn(n) {
      @sf.page_note_node(n, fn() { failed_of(core, ["profile.put"], on).unwrap_or("") }, bad=fn() { true })
    })
  })
}

// ── whom it is shared with ──────────────────────────────────────────────

///|
/// Sharing it with the workspace's other stations (ShareSection) in node `b`: a switch (turned on, asked first what the
/// others do with it); once on, where a subscription is signed in (moved from here to another) and which stations may
/// use it, a row each. A copy of another station's says whose it is, its page a tap away.
fn profile_share_node(
  b : @view.View,
  core : Core,
  address : String,
  id : String,
  s : () -> Json?,
  p : () -> Json?,
  entry : () -> Json?,
) -> Unit {
  let on = [("station", address), ("id", id)]
  let share = fn() { field(p(), "share") }
  let stations = fn() { items(entry(), "stations") }
  let name_of = fn(sid : String) -> String {
    let all = stations()
    match all.search_by(fn(x) { text(Some(x), "id") == sid }) {
      Some(i) => text(Some(all[i]), "name")
      None => sid.clamped_view(end=@cmp.minimum(8, sid.length())).to_owned()
    }
  }
  let subscription = fn() { text(field(p(), "access"), "kind") == "subscription" }
  let user = fn() { text(share(), "role") == "user" }
  let shared = fn() { share() is Some(Object(_)) }
  let sharing = fn() { is_doing(core, ["profile.share"], on) }
  let moving = fn() { is_doing(core, ["profile.move"], on) }
  let sid = fn() { text(s(), "id") }
  let allowed = fn() -> Array[String]? {
    match field(share(), "allow") {
      Some(Array(a)) => Some(a.filter_map(fn(x) { if x is String(v) { Some(v) } else { None } }))
      _ => None
    }
  }
  @sf.section_node(b, fn() { @sf.t("web-pages.profiles.share.title") }, fn(sec) {
    @sf.group_node(sec, fn(g) {
      // a copy of another station's: whose it is, its page a tap away
      g.show(at_once=true, user, fn(x) {
        let lender = fn() -> Json? {
          let host = text(share(), "host")
          let members = items(entry(), "members")
          match members.search_by(fn(m) { text(Some(m), "stationId") == host && text(Some(m), "role") == "host" }) {
            Some(i) => Some(members[i])
            None => None
          }
        }
        x.pick(at_once=true, fn() { lender() is Some(_) }, fn(r, goes) {
          @sf.link_row_node(
            r,
            fn() { @sf.t("web-pages.profiles.share.copy", args=[("station", name_of(text(share(), "host")))]) },
            fn() {
              match @signals.untracked(lender) {
                Some(m) => (core.push)(Profile(text(Some(m), "station"), text(Some(m), "profileId")))
                None => ()
              }
            },
            note=fn() {
              let host = name_of(text(share(), "host"))
              if subscription() && field(share(), "reachable") is Some(False) {
                @sf.t("web-pages.profiles.share.hostAway", args=[("station", host)])
              } else {
                @sf.t("web-pages.profiles.share.changeThere")
              }
            },
            goes~,
          )
        })
      })
      g.show(at_once=true, fn() { !user() }, fn(x) {
        @sf.switch_row_node(
          x,
          fn() { @sf.t("web-pages.profiles.share.switch") },
          shared,
          fn(now) {
            let change = fn() {
              @settings.act(
                core,
                @sf.t("web-pages.profiles.share.switch"),
                "profile.share",
                obj([("station", str(address)), ("id", str(id)), ("on", Json::boolean(now))]),
                done=if now { @sf.t("web-pages.profiles.share.shared") } else { @sf.t("web-pages.profiles.share.unshared") },
              )
            }
            if now {
              let sub = @signals.untracked(subscription)
              let claude = sub && text(@signals.untracked(p), "runtime") == "claude"
              @sf.confirm(
                if claude { @sf.t("web-pages.profiles.share.confirmClaudeTitle") } else { @sf.t("web-pages.profiles.share.confirmTitle") },
                if claude {
                  @sf.t("web-pages.profiles.share.confirmClaudeBody")
                } else if sub {
                  @sf.t("web-pages.profiles.share.confirmSubscriptionBody")
                } else {
                  @sf.t("web-pages.profiles.share.confirmCopyBody")
                },
                if claude { @sf.t("web-pages.profiles.share.confirmUnderstood") } else { @sf.t("web-pages.profiles.share.confirmAction") },
                change,
                warning=if claude { @sf.t("web-pages.profiles.share.confirmClaudeWarning") } else { "" },
              )
            } else {
              change()
            }
          },
          note=fn() {
            if !shared() {
              @sf.t("web-pages.profiles.share.onlyHere", args=[("station", text(s(), "name"))])
            } else if subscription() {
              @sf.t("web-pages.profiles.share.lent")
            } else {
              @sf.t("web-pages.profiles.share.copied")
            }
          },
          busy=sharing,
        )
      })
      // where a shared subscription is signed in, moved to another
      let targets = fn() { stations().filter(fn(x) { text(Some(x), "id") != sid() }) }
      g.show(at_once=true, fn() { !user() && shared() && subscription() && !flag(p(), "machine") }, fn(x) {
        x.pick(at_once=true, fn() { !moving() && targets().length() > 0 }, fn(r, goes) {
          @sf.link_row_node(
            r,
            fn() { @sf.t("web-pages.profiles.share.signedIn") },
            fn() { move_dialog(core, @signals.untracked(s), @signals.untracked(p), @signals.untracked(targets)) },
            value=fn() { text(s(), "name") },
            goes~,
            tail=fn(t) { doing_mark_node(t, moving, fn() { failed_of(core, ["profile.move"], on) }) },
          )
        })
      })
      // which stations may use it
      g.show(at_once=true, fn() { !user() && shared() }, fn(x) {
        x.pick(at_once=true, fn() { !sharing() }, fn(r, goes) {
          @sf.link_row_node(
            r,
            fn() { @sf.t("web-pages.profiles.share.stations") },
            fn() {
              pick_stations(core, address, id, @signals.untracked(stations), @signals.untracked(sid), @signals.untracked(allowed))
            },
            note=fn() {
              let users = strings(share(), "users").map(name_of)
              if users.length() > 0 {
                @sf.t("web-pages.profiles.share.users", args=[("stations", users.join(@sf.t("web-main.list.separator")))])
              } else {
                ""
              }
            },
            value=fn() {
              match allowed() {
                None => @sf.t("web-pages.profiles.share.everyStation")
                Some(a) =>
                  stations()
                  .filter(fn(x) { a.contains(text(Some(x), "id")) || text(Some(x), "id") == sid() })
                  .map(fn(x) { text(Some(x), "name") })
                  .join(@sf.t("web-main.list.separator"))
              }
            },
            goes~,
          )
        })
      })
    })
  })
}

///|
/// Where a shared subscription is signed in, moved to another station (`profile.move`): the others, a row each, picked
/// in a panel (one away, said so and not picked).
fn move_dialog(core : Core, s : Json?, p : Json?, targets : Array[Json]) -> Unit {
  let address = text(s, "station")
  let id = text(p, "id")
  open_dialog(
    @sf.t("web-pages.profiles.share.moveTitle"),
    description=@sf.t("web-pages.profiles.share.moveLead", args=[("station", text(s, "name"))]),
    fn(c, shut) {
      @sf.group(c, fn() {
        for x in targets {
          let xv = Some(x)
          let online = flag(xv, "online")
          @sf.link_row(
            c,
            "profile-move-to/" + text(xv, "id"),
            text(xv, "name"),
            value=if online { "" } else { @sf.t("web-pages.stations.offline") },
            chevron=false,
            goes=online,
            lead=fn() { @sf.status_dot(c, if online { "online" } else { "offline" }) },
            on_press=fn() {
              shut()
              @settings.act(
                core,
                @sf.t("web-pages.profiles.share.move"),
                "profile.move",
                obj([("station", str(address)), ("id", str(id)), ("to", str(text(xv, "id")))]),
                done=@sf.t("web-pages.profiles.share.moved", args=[("station", text(xv, "name"))]),
              )
            },
          ) |> ignore
        }
      })
    },
    fn(_, _) {  },
  )
}

///|
/// Which stations may use a share (PickStations), ticked in a panel: every one (those to come too), or those ticked;
/// the one that has it always.
fn pick_stations(core : Core, address : String, id : String, stations : Array[Json], own : String, allowed : Array[String]?) -> Unit {
  let ticked : Map[String, Bool] = Map([])
  for x in stations {
    let xid = text(Some(x), "id")
    ticked[xid] = match allowed {
      None => true
      Some(a) => a.contains(xid)
    }
  }
  let all = fn() { stations.iter().all(fn(x) { text(Some(x), "id") == own || ticked.get(text(Some(x), "id")).unwrap_or(false) }) }
  open_dialog(
    @sf.t("web-pages.profiles.share.stations"),
    fn(c, _) {
      @sf.page_note(c, if all() { @sf.t("web-pages.profiles.share.futureIn") } else { @sf.t("web-pages.profiles.share.futureOut") })
      @sf.group(c, fn() {
        for x in stations {
          let xv = Some(x)
          let xid = text(xv, "id")
          let self = xid == own
          let on = self || ticked.get(xid).unwrap_or(false)
          let now = @sf.switch_row(
            c,
            "profile-pick/" + xid,
            text(xv, "name"),
            on,
            note=if self { @sf.t("web-pages.profiles.share.here") } else if flag(xv, "online") { "" } else { @sf.t("web-pages.stations.offline") },
            disabled=self,
          )
          if !self && now != on {
            ticked[xid] = now
          }
        }
      })
    },
    fn(c, shut) {
      @sf.button(c, @sf.t("web-pages.profiles.share.done"), key="profile-pick-done/" + address + "/" + id, tone=Primary, on_press=fn() {
        shut()
        let params = [("station", str(address)), ("id", str(id)), ("on", Json::boolean(true))]
        if !all() {
          let allow : Array[Json] = [str(own)]
          for x in stations {
            let xid = text(Some(x), "id")
            if xid != own && ticked.get(xid).unwrap_or(false) {
              allow.push(str(xid))
            }
          }
          params.push(("allow", Json::array(allow)))
        }
        @settings.act(core, @sf.t("web-pages.profiles.share.stations"), "profile.share", obj(params))
      }) |> ignore
    },
  )
}

///|
/// Which of the workspaces the station joined may run their chats on it (WorkspacesSection), in node `b`, a switch
/// each (a workspace's mark before its name where it has one), for its home's managers once the station is in more
/// than one; read as its block is made.
fn profile_workspaces_node(b : @view.View, core : Core, address : String, id : String, p : () -> Json?, stint : () -> Int) -> Unit {
  let joined = fn() {
    let m = (core.topic)("memberships", { "station": str(address) }).get().value
    if flag(m, "manages") {
      items(m, "workspaces").filter(fn(w) { !flag(Some(w), "home") })
    } else {
      []
    }
  }
  let busy = fn() { is_doing(core, ["profile.put"], [("station", address), ("id", id)]) }
  b.show(at_once=true, fn() { joined().length() > 0 }, fn(x) {
    @sf.section_node(x, fn() { @sf.t("web-pages.profiles.workspaces.title") }, note=fn() { @sf.t("web-pages.profiles.workspaces.lead") }, fn(sec) {
      @sf.group_node(sec, fn(g) {
        g.each(joined, fn(w) { text(Some(w), "workspace") }, fn(r, w) {
          let wv = fn() { Some(w.get()) }
          let ws = @signals.untracked(fn() { text(wv(), "workspace") })
          let name = fn() { text(wv(), "name") }
          let emoji = fn() { text(wv(), "emoji") }
          let icon = fn() { text(wv(), "icon") }
          let on = fn() { strings(p(), "workspaces").contains(ws) }
          // With no mark of its own, the name is enough (a bare initial reads as another word: 「个 个人」).
          r.pick(at_once=true, fn() { @sf.has_station_mark(emoji(), icon()) }, fn(y, marked) {
            @sf.switch_row_node(
              y,
              name,
              on,
              fn(next) {
                let now = strings(@signals.untracked(p), "workspaces")
                let list = if next { now.copy() } else { now.filter(fn(x) { x != ws }) }
                if next {
                  list.push(ws)
                }
                let named = @signals.untracked(name)
                @settings.act(
                  core,
                  @sf.t("web-pages.profiles.workspaces.title"),
                  "profile.put",
                  obj([("station", str(address)), ("id", str(id)), ("input", obj([("workspaces", Json::array(list.map(str)))]))]),
                  done=@sf.t(if next { "web-pages.profiles.workspaces.turnedOn" } else { "web-pages.profiles.workspaces.turnedOff" }, args=[("name", named)]),
                )
              },
              note=fn() { @sf.t(if on() { "web-pages.profiles.workspaces.on" } else { "web-pages.profiles.workspaces.off" }, args=[("name", name())]) },
              busy~,
              lead?=if marked {
                Some(fn(l) { @sf.station_mark_node(l, emoji, icon, profile_ws_mark, fn() { @sf.theme().p.text }, stint) })
              } else {
                None
              },
            )
          })
        })
      })
    })
  })
}

// ── the account ─────────────────────────────────────────────────────────

///|
/// The account itself (AccountSection) in node `b`, a row each: its key masked and where its provider is (each changed
/// from its row: asked for), a subscription signed in again or by hand on the machine, or whose login the machine's own
/// is.
fn profile_account_node(b : @view.View, core : Core, address : String, id : String, s : () -> Json?, p : () -> Json?) -> Unit {
  let on = [("station", address), ("id", id)]
  let access = fn() { field(p(), "access") }
  let kind = fn() { text(access(), "kind") }
  let machine = fn() { flag(p(), "machine") }
  let keyed = fn() { ["opencode-go", "anthropic-api", "api-provider"].contains(kind()) && !flag(access(), "login") }
  let saving = fn() { is_doing(core, ["profile.put"], on) }
  let starting = fn() { is_doing(core, ["profile.login"], on) }
  let command = fn() { text(p(), "loginCommand") }
  @sf.section_node(b, fn() { @sf.t("web-pages.profiles.account") }, fn(sec) {
    @sf.group_node(sec, fn(g) {
      g.show(at_once=true, machine, fn(x) {
        let runtime = fn() { @settings.runtime_label(text(p(), "runtime")) }
        said_row_node(
          x,
          fn() {
            if text(s(), "name") != "" {
              @sf.t("web-pages.profiles.machineLoginOn", args=[("station", text(s(), "name")), ("runtime", runtime())])
            } else {
              @sf.t("web-pages.profiles.machineLoginHere", args=[("runtime", runtime())])
            }
          },
          note=fn() { @sf.t("web-pages.profiles.machineLoginAbout", args=[("runtime", runtime())]) },
        )
      })
      g.show(at_once=true, fn() { !machine() && keyed() }, fn(x) {
        x.pick(at_once=true, fn() { !saving() }, fn(r, goes) {
          @sf.link_row_node(
            r,
            fn() {
              if kind() == "opencode-go" {
                "OpenCode Go key"
              } else if text(p(), "providerName") != "" {
                text(p(), "providerName") + " key"
              } else {
                "API key"
              }
            },
            fn() { ask_key(core, address, @signals.untracked(p)) },
            note=fn() { if text(access(), "key") != "" { text(access(), "key") } else { @sf.t("web-pages.profiles.notSaved") } },
            value=fn() { @sf.t("web-pages.profiles.replace") },
            value_lit=true,
            chevron=false,
            goes~,
            tail=fn(t) { doing_mark_node(t, saving, fn() { failed_of(core, ["profile.put"], on) }) },
          )
        })
      })
      g.show(at_once=true, fn() { !machine() && keyed() && has(access(), "endpoint") }, fn(x) {
        x.pick(at_once=true, fn() { !saving() }, fn(r, goes) {
          @sf.link_row_node(
            r,
            fn() { @sf.t("common.provider.endpoint") },
            fn() {
              let endpoint = text(@signals.untracked(access), "endpoint")
              let kind = @signals.untracked(kind)
              ask(@sf.t("common.provider.endpoint"), endpoint, "https://", @sf.t("common.save"), fn(value) {
                @settings.act(
                  core,
                  @sf.t("web-pages.profiles.replace"),
                  "profile.put",
                  obj([("station", str(address)), ("id", str(id)), ("input", obj([("access", obj([("kind", str(kind)), ("endpoint", str(value.trim(chars=" \t\n").to_owned()))]))]))]),
                  done=@sf.t("web-pages.profiles.savedChecking"),
                )
              })
            },
            note=fn() { text(access(), "endpoint") },
            value=fn() { @sf.t("web-pages.profiles.replace") },
            value_lit=true,
            chevron=false,
            goes~,
          )
        })
      })
      // signed in and well: signing in again, or by hand on the machine (OpenCode's has no command to run)
      g.show(at_once=true, fn() { !machine() && !keyed() }, fn(x) {
        x.pick(at_once=true, fn() { !starting() }, fn(r, goes) {
          @sf.link_row_node(
            r,
            fn() { @sf.t("web-pages.signIn.again") },
            fn() { @settings.act(core, @sf.t("web-pages.profiles.signIn"), "profile.login", obj([("station", str(address)), ("id", str(id))])) },
            note=fn() { @sf.t("web-pages.profiles.subscriptionSignIn", args=[("provider", text(p(), "signInProvider"))]) },
            chevron=false,
            goes~,
            tail=fn(t) { doing_mark_node(t, starting, fn() { failed_of(core, ["profile.login"], on) }) },
          )
        })
      })
      g.show(at_once=true, fn() { !machine() && !keyed() && command() != "" }, fn(x) {
        @sf.link_row_node(
          x,
          fn() { @sf.t("web-pages.profiles.manual") },
          fn() {
            let words = @signals.untracked(command)
            @sf.panel(
              @sf.t("web-pages.profiles.manual"),
              fn(c, _) { @sf.copy_command(c, "profile-command/" + address + "/" + id, words, copy=@sf.t("common.copy"), copied=@sf.t("common.copied")) },
              from=Unanchored,
            )
          },
          chevron=false,
        )
      })
    })
  })
}

///|
/// A new key asked for, in a field that shows dots (secret), and saved (`profile.put` with the account's kind and the
/// key); the station checks it again.
fn ask_key(core : Core, station : String, p : Json?) -> Unit {
  let id = text(p, "id")
  let kind = text(field(p, "access"), "kind")
  ask(
    if kind == "opencode-go" { @sf.t("web-pages.profiles.newOpencodeKey") } else { @sf.t("web-pages.profiles.newApiKey") },
    "",
    @sf.t("web-pages.profiles.pasteKey"),
    @sf.t("common.save"),
    secret=true,
    hint=@sf.t("web-pages.profiles.recheckHint"),
    fn(key) {
      @settings.act(
        core,
        @sf.t("web-pages.profiles.replace"),
        "profile.put",
        obj([("station", str(station)), ("id", str(id)), ("input", obj([("access", obj([("kind", str(kind)), ("key", str(key))]))]))]),
        done=@sf.t("web-pages.profiles.savedChecking"),
      )
    },
  )
}

///|
/// Its new name asked for and saved (`profile.put` its name).
fn profile_rename(core : Core, address : String, p : Json?) -> Unit {
  let id = text(p, "id")
  ask(@sf.t("web-pages.profiles.name"), text(p, "name"), @sf.t("web-pages.profiles.name"), @sf.t("common.save"), fn(line) {
    let to = line.trim(chars=" \t\n").to_owned()
    if to != "" && to != text(p, "name") {
      @settings.act(
        core,
        @sf.t("web-pages.settings.stations.rename"),
        "profile.put",
        obj([("station", str(address)), ("id", str(id)), ("input", obj([("name", str(to))]))]),
        done=@sf.t("web-pages.settings.workspace.renamed"),
      )
    }
  })
}

///|
/// The variables a custom profile runs with (EnvSection) in node `b`: a row each, its name and its value (a secret's
/// masked); the last row opens them to be written on a card under them (env_editor_node), as it says.
fn profile_env_node(b : @view.View, core : Core, address : String, id : String, p : () -> Json?, open : ProfileOpen, tips : @sf.TipLayer?) -> Unit {
  let on = [("station", address), ("id", id)]
  let busy = fn() { is_doing(core, ["profile.put"], on) }
  @sf.section_node(b, fn() { @sf.t("web-pages.profiles.env") }, note=fn() { @sf.t("web-pages.profiles.envLead", args=[("route", "{route}")]) }, fn(sec) {
    @sf.group_node(sec, fn(g) {
      g.each(fn() { items(p(), "env") }, fn(e) { text(Some(e), "key") }, fn(r, e) {
        @sf.link_row_node(r, fn() { text(Some(e.get()), "key") }, fn() {  }, note=fn() { text(Some(e.get()), "value") }, goes=false)
      })
      @sf.link_row_node(
        g,
        fn() { if open.env.get() { @sf.t("web-pages.profiles.collapse") } else { @sf.t("android-settings.env.edit") } },
        fn() { open.env.set(!open.env.untracked()) },
        chevron=false,
        tail=fn(t) { doing_mark_node(t, busy, fn() { failed_of(core, ["profile.put"], on) }, tips?) },
      )
    })
    sec.show(fn() { open.env.get() }, fn(x) { @sf.page_card_node(x, footed=true, fn(k) { env_editor_node(k, core, address, id, p, busy) }) })
  })
}

///|
/// Its variables written (EnvSection's table) on the card `k`: a name and a value a row (a secret's kept masked until it
/// is written anew), deleted or added, saved as what changed (a name gone or renamed: null). The rows as the profile has
/// them as the card is made (opened).
fn env_editor_node(k : @view.View, core : Core, address : String, id : String, p : () -> Json?, busy : () -> Bool) -> Unit {
  let env = @signals.untracked(fn() { items(p(), "env") })
  let row_of = fn(key : String, value : String, masked : String) -> EnvRow {
    { key: @ui.Field::new(text=key), value: @ui.Field::new(text=value), original: key, masked }
  }
  // (the rows themselves the list: each its own fields, a row on the page for each, View::each_of)
  let rows : @signals.Signal[Array[EnvRow]] = @signals.signal(
    env.map(fn(e) {
      let ev = Some(e)
      let secret = flag(ev, "secret")
      row_of(text(ev, "key"), if secret { "" } else { text(ev, "value") }, if secret { text(ev, "value") } else { "" })
    }),
    same=fn(x, y) { physical_equal(x, y) },
  )
  k.box(fn(t) {
    @sf.style_node(t, fn() { pf_env_table })
    t.each_of(fn() { rows.get() }, fn(r, row) {
      @sf.style_node(r, fn() { pf_env_row })
      r.box(fn(c) {
        @sf.style_node(c, fn() { pf_env_name }, in_row=true)
        @sf.input_node(c, row.key, placeholder="NAME") |> ignore
      })
      |> ignore
      r.box(fn(c) {
        @sf.style_node(c, fn() { pf_input_grow }, in_row=true)
        c.basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
        @sf.input_node(
          c,
          row.value,
          placeholder=if row.masked != "" { @sf.t("web-pages.profiles.envSaved", args=[("masked", row.masked)]) } else { @sf.t("web-pages.profiles.envValue") },
          secret=true,
        )
        |> ignore
      })
      |> ignore
      @sf.button_node(r, fn() { @sf.t("common.delete") }, fn() {
        rows.set(rows.untracked().filter(fn(x) { !physical_equal(x, row) }))
      }, tone=Ghost)
      |> ignore
    })
    @sf.button_node(t, fn() { @sf.t("web-pages.profiles.envAdd") }, fn() {
      rows.set(rows.untracked() + [row_of("", "", "")])
    }, tone=Ghost, icon="plus")
    |> ignore
  })
  |> ignore
  @sf.card_foot_node(k, at_end=true, fn(f) {
    @sf.button_node(f, fn() { @sf.t("common.save") }, fn() {
      // what changed: a name gone or renamed null, a secret left blank kept as it is
      let now = rows.untracked()
      let patch : Map[String, Json] = Map([])
      let kept = now.map(fn(r) { r.key.text().trim(chars=" \t\n").to_owned() })
      for e in env {
        if !kept.contains(text(Some(e), "key")) {
          patch[text(Some(e), "key")] = Json::null()
        }
      }
      for r in now {
        let name = r.key.text().trim(chars=" \t\n").to_owned()
        if name == "" {
          continue
        }
        if r.original != "" && r.original != name {
          patch[r.original] = Json::null()
        }
        if r.masked != "" && r.value.text() == "" && r.original == name {
          continue
        }
        patch[name] = str(r.value.text())
      }
      @settings.act(
        core,
        @sf.t("web-pages.profiles.env"),
        "profile.put",
        obj([("station", str(address)), ("id", str(id)), ("input", obj([("env", Json::object(patch))]))]),
        done=@sf.t("web-pages.profiles.saved"),
      )
    }, tone=Primary, busy~)
    |> ignore
  })
}

// ── its models' panel (a presenter's, an old view) ─────────────────────────

///|
/// All of a profile's models (by the core's series, each under its name where there are more than one), each with
/// a box before it, ticked while it is starred (`pick.like`, as the model control's are: 2026-11-02 用户「这里改成也能
/// 点勾」), its id under the pointer; one named by hand that its provider does not list taken off by its ×; one more
/// named by hand over them, where it can be. (In the panel profile_models_node opens: a presenter's, an old view.)
fn profile_models_panel(c : @ui.Ctx, core : Core, address : String, p : Json?, fusion : Json?) -> Unit {
  let id = text(p, "id")
  let key = address + "/" + id
  let added = strings(p, "added")
  let named = strings(p, "named")
  let names = field(p, "names")
  let name = fn(m : String) { match text(names, m) { "" => m; n => n } }
  let busy = has(p, "modelsSaving") && !(field(p, "modelsSaving") is Some(Null))
  // what is starred, as the new chat's model control of this station has it (its options, each `liked`, by spelling)
  let options = items((core.topic)("pick", { "station": Json::string(address), "of": Json::string("new") }).get().value, "options")
  let liked = fn(m : String) {
    options.iter().any(fn(o) { flag(Some(o), "liked") && (text(Some(o), "model") == m || strings(Some(o), "ids").contains(m)) })
  }
  let fusion_uids : Map[String, Bool] = Map([])
  if fusion is Some(Object(_)) {
    let sides = items(fusion, "sides")
    for lead in items(fusion, "leads") {
      let lv = Some(lead)
      let lead_id = text(lv, "id")
      for idx_json in items(lv, "sides") {
        if idx_json is Number(idx, ..) && sides.get(idx.to_int()) is Some(side) {
          fusion_uids["fusion-" + lead_id + "-sidekick-" + text(Some(side), "id")] = true
        }
      }
    }
  }
  let shown_series : Array[(String, Array[String])] = []
  for s in items(p, "series") {
    let sv = Some(s)
    let models = strings(sv, "models").filter(fn(m) { !fusion_uids.contains(m) })
    if !models.is_empty() {
      shown_series.push((text(sv, "name"), models))
    }
  }
  // (one more named by hand over them, where it can be: under them it stood in the panel's corner)
  if flag(p, "canAddModel") {
    c.box(style=pf_models_add, fn() { add_model(c, core, address, id) }) |> ignore
  }
  @sf.panel_column(c, "profile-models/" + key, pf_models_most, pf_model_rows.then(pf_models_foot()), fn() {
    for entry in shown_series {
      let (series_name, models) = entry
      if shown_series.length() > 1 {
        c.box(style=pf_series_room, fn() { c.text(series_name, style=pf_series_words) |> ignore }) |> ignore
      }
      for m in models {
        let on = liked(m)
        let item = c.id("profile-model-item/" + key + "/" + m)
        c.box(style=pf_model_row.then(@sf.row_least_h()), id=item, taps=false, points=true, fn() {
          let now = @kit.checkbox(
              c,
              "profile-model-like/" + key + "/" + m,
              if on { On } else { Off },
              label=@sf.t("web-main.model.likeModel", args=[("model", name(m))]),
            ).value
          if (now == On) != on {
            (core.call)(
              "pick.like",
              obj([("station", str(address)), ("of", str("new")), ("model", str(m)), ("liked", Json::boolean(now == On))]),
              @sfbase.answer_unread,
            )
          }
          @sf.maker_mark(c, text(field(field(p, "makers"), m), "id"), text(p, "runtime"), pf_chip_glyph) |> ignore
          c.text(name(m), style=pf_model_words) |> ignore
          if added.contains(m) {
            @sf.icon_button(
              c,
              "close",
              key="profile-model-off/" + key + "/" + m,
              size=pf_chip_off,
              icon_size=pf_chip_glyph,
              round=true,
              disabled=busy,
              label=@sf.t("web-pages.profiles.removeModel", args=[("model", name(m))]),
              on_press=fn() {
                @settings.act(
                  core,
                  @sf.t("web-pages.profiles.removeModel", args=[("model", name(m))]),
                  "profile.put",
                  obj([("station", str(address)), ("id", str(id)), ("input", obj([("models", Json::array(named.filter(fn(x) { x != m }).map(str)))]))]),
                )
              },
            ) |> ignore
          }
        })
        |> ignore
        @sf.tip(c, "profile-model-item/" + key + "/" + m + "/tip", item, m, side=Right, repeats=name(m) == m)
      }
    }
    if fusion is Some(Object(_)) {
      profile_fusion_section(c, core, address, id, key, p, fusion, named, liked, busy)
    }
  })
}

///|
/// Devin's Fusion combinations (`lead + sidekick`), opted into by ticking so hundreds of pairs do not crowd the picker.
fn profile_fusion_section(
  c : @ui.Ctx,
  core : Core,
  address : String,
  id : String,
  key : String,
  p : Json?,
  fusion : Json?,
  named : Array[String],
  liked : (String) -> Bool,
  busy : Bool,
) -> Unit {
  let sides = items(fusion, "sides")
  let leads = items(fusion, "leads")
  guard !sides.is_empty() && !leads.is_empty() else { return }
  let f = profile_field("fusion-search/" + key)
  let q = f.text().trim(chars=" \t\n").to_lower()
  c.box(style=pf_fusion_head, fn() {
    c.text(@sf.t("web-pages.profiles.fusionModels"), style=pf_series_words) |> ignore
    c.text(@sf.t("web-pages.profiles.fusionHint"), style=pf_muted) |> ignore
  })
  |> ignore
  c.box(style=pf_fusion_search, fn() {
    @sf.input(
      c,
      "profile-fusion-search/" + key,
      placeholder=@sf.t("web-pages.profiles.searchFusion"),
      field=f,
    )
    |> ignore
  })
  |> ignore
  let ticked : Array[(String, String, String, Bool)] = []
  let rest : Array[(String, String, String, Bool)] = []
  for lead in leads {
    let lv = Some(lead)
    let lead_id = text(lv, "id")
    let lead_name = text(lv, "name")
    let maker_id = text(field(lv, "maker"), "id")
    for idx_json in items(lv, "sides") {
      if idx_json is Number(idx, ..) && sides.get(idx.to_int()) is Some(side) {
        let sv = Some(side)
        let side_id = text(sv, "id")
        let side_name = text(sv, "name")
        let uid = "fusion-" + lead_id + "-sidekick-" + side_id
        let display = lead_name + " + " + side_name
        if q == "" || display.to_lower().contains(q) || uid.to_lower().contains(q) {
          let on = named.contains(uid)
          if on {
            ticked.push((uid, display, maker_id, true))
          } else if rest.length() < pf_fusion_most {
            rest.push((uid, display, maker_id, false))
          }
        }
      }
    }
  }
  let runtime = text(p, "runtime")
  for row in ticked + rest {
    let (uid, display, maker_id, on) = row
    let item = c.id("profile-fusion-item/" + key + "/" + uid)
    c.box(style=pf_model_row.then(@sf.row_least_h()), id=item, taps=false, points=true, fn() {
      let now = @kit.checkbox(
        c,
        "profile-fusion-check/" + key + "/" + uid,
        if on { On } else { Off },
        disabled=busy,
        label=display,
      ).value
      if (now == On) != on && !busy {
        let next_named = if now == On {
          if named.contains(uid) { named } else { named + [uid] }
        } else {
          named.filter(fn(x) { x != uid })
        }
        @settings.act(
          core,
          @sf.t("web-pages.profiles.fusionModels"),
          "profile.put",
          obj([("station", str(address)), ("id", str(id)), ("input", obj([("models", Json::array(next_named.map(str)))]))]),
        )
        if now == On || liked(uid) {
          (core.call)(
            "pick.like",
            obj([("station", str(address)), ("of", str("new")), ("model", str(uid)), ("liked", Json::boolean(now == On))]),
            @sfbase.answer_unread,
          )
        }
      }
      @sf.maker_mark(c, maker_id, runtime, pf_chip_glyph) |> ignore
      c.text(display, style=pf_model_words) |> ignore
    })
    |> ignore
    @sf.tip(c, "profile-fusion-item/" + key + "/" + uid + "/tip", item, uid, side=Right)
  }
}

///|
/// A model named by hand (AddModel), for a provider that does not list them all.
fn add_model(c : @ui.Ctx, core : Core, address : String, id : String) -> Unit {
  let f = profile_field("add-model/" + address + "/" + id)
  let adding = is_doing(core, ["profile.addModel"], [("station", address), ("id", id)])
  let add = fn() {
    let m = f.text().trim(chars=" \t\n").to_owned()
    if m != "" && !adding {
      @settings.act(core, @sf.t("web-pages.profiles.addModelWhat"), "profile.addModel", obj([("station", str(address)), ("id", str(id)), ("model", str(m))]))
      f.set("")
    }
  }
  c.box(style=pf_input_row, fn() {
    c.box(style=pf_input_grow, fn() {
      if @sf.input(
          c,
          "profile-add-model/" + address + "/" + id,
          placeholder=@sf.t("web-pages.profiles.addModelPlaceholder"),
          shorter=[@sf.t("web-mobile.profiles.addModelPlaceholder")],
          field=f,
        ).submitted {
        add()
      }
    })
    |> ignore
    @sf.button(c, @sf.t("web-pages.profiles.addModel"), key="profile-add-model-go/" + address + "/" + id, busy=adding, disabled=f.text().trim(chars=" \t\n").is_empty(), on_press=fn() {
      add()
    }) |> ignore
  })
  |> ignore
}

// ── styles (pages.css.ts identity) ─────────────────────

///|
/// Words on its cards, and the quieter ones (the ui's 13 on 24; muted).
// kept across runs: a value (no field of it changes)
let pf_words : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Fg, w=Full)

///|
// kept across runs: a value (no field of it changes)
let pf_muted : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, w=Full)

///|
let pf_mark_glyph : Double = 26.0

///|
let pf_chip_glyph : Double = 14.0

///|
let pf_user_avatar : Double = 24.0

///|
/// What its last check said, cut short where its line has less.
// kept across runs: a value (no field of it changes)
let pf_check_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, wrap=false, w=Cut)

///|
/// Its state under its name (profileState: 8 apart).
// kept across runs: a value (no field of it changes)
let pf_state : @ui.Style = @ui.css("row gap=S2 align=ACenter")

///|
/// The runtimes' tags (runtimeTags: 4 apart, 8 after the name; each the library's tag_node).
// kept across runs: a value (no field of it changes)
let pf_tags : @ui.Style = @ui.css("row gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let pf_wait_line : @ui.Style = @ui.css("row gap=S2 align=ACenter")

///|
/// A card's parts apart, what a part of it shows in its own room too (desk_card's gap=S3_5).
let pf_card_gap : Double = 14.0

///|
/// A sign-in's step (steps: its words over what is done in it).
// kept across runs: a value (no field of it changes)
let pf_step : @ui.Style = @ui.css("w=Full gap=S2 align=AStart")

///|
/// A step's page buttons (its own and, where the station has a browser, the station's) and the ⋯ after them (copying
/// the link for a browser elsewhere): wrapped across lines on a narrow card or large words.
let pf_step_buttons_gap : Double = 8.0

///|
// kept across runs: a value (no field of it changes)
let pf_step_buttons : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let pf_input_row : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let pf_input_grow : @ui.Style = @ui.style(w=@sf.grow)

///|
/// A device's code (deviceCode: the code large, then its one button, 10 apart).
// kept across runs: a value (no field of it changes)
let pf_device : @ui.Style = @ui.css("w=Full gap=S2_5 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let pf_device_code : @ui.Style = @ui.css("px=S3 py=S1_5 radius=Lg bg=Hover")

///|
// kept across runs: a value (no field of it changes)
let pf_device_code_words : @ui.TextStyle = @ui.text_style(size=Heading, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let pf_chips : @ui.Style = @ui.css("row w=Full gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let pf_chip : @ui.Style = @ui.css("row px=S2_5 py=S1 gap=S1_5 align=ACenter radius=Full bg=Hover")

///|
/// A profile's models in their panel: a row each (a box, its maker's mark, its name, its ×), 1 apart, scrolling past
/// this; a series' name over its models; one more named by hand over them.
let pf_models_most : Double = 420.0

///|
// kept across runs: a value (no field of it changes)
let pf_model_rows : @ui.Style = @ui.css("w=Full gap=SPx")

///|
/// Under the models, as much room as keeps the last one's box out of the panel's foot corner: a box there, its row's
/// words on the panel's words' line (34 in from a corner 42 round), would have to be concentric with the corner (8
/// round, a box's 6: the corner rule), so it stands clear of it, its rows' spacing as it was (a card row's control the
/// same: @sf.card_control_end).
fn pf_models_foot() -> @ui.Style {
  @ui.style(pb=@sf.panel_foot_clear(@sf.theme().items.least, pf_like_box))
}

///|
/// How big a model's box is (@kit.checkbox's).
let pf_like_box : Double = 18.0

///|
// kept across runs: a value (no field of it changes)
let pf_model_row : @ui.Style = @ui.css("row w=Cut px=S2_5 gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let pf_model_words : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let pf_series_room : @ui.Style = @ui.css("w=Full px=S2_5 pt=S2 pb=S1")

///|
// kept across runs: a value (no field of it changes)
let pf_series_words : @ui.TextStyle = @ui.text_style(size=Meta, weight=Medium, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let pf_models_add : @ui.Style = @ui.css("w=Full pb=S2")

///|
/// How many unticked Fusion pairs are listed at once before filtering by search.
let pf_fusion_most : Int = 40

///|
// kept across runs: a value (no field of it changes)
let pf_fusion_head : @ui.Style = @ui.css("w=Full px=S2_5 pt=S3 pb=S1 gap=S0_5")

///|
// kept across runs: a value (no field of it changes)
let pf_fusion_search : @ui.Style = @ui.css("w=Full px=S2_5 pb=S1_5")

///|
/// The × of a model named by hand on its chip (a round button as high as its words' line).
let pf_chip_off : Double = 18.0

///|
// kept across runs: a value (no field of it changes)
let pf_chip_words : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Fg, wrap=false)

///|
/// The variables' rows (envTable: 8 apart; a row its name, its value wider, deleting it).
// kept across runs: a value (no field of it changes)
let pf_env_table : @ui.Style = @ui.css("w=Full gap=S2")

///|
// kept across runs: a value (no field of it changes)
let pf_env_row : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let pf_env_name : @ui.Style = @ui.css("w=S48")

///|
/// A profile made up, for what its page shows while it is read (profile_node's, in its bones): its name, how it stands,
/// its allowance, the models it may use.
fn profile_sample() -> Json {
  let models = [7, 9, 6, 8, 5].mapi(fn(i, n) { ("sample" + i.to_string(), @sf.sample_words(n)) })
  let w = fn(n : Int) { Json::string(@sf.sample_words(n)) }
  let window = fn(left : Int) -> Json { { "left": Json::number(left.to_double()), "level": "ok", "label": w(3), "refills": w(5) } }
  {
    "id": "sample",
    "name": Json::string(@sf.sample_words(8)),
    "kindText": w(4),
    "checkTone": "green",
    "checkLine": w(4),
    "check": { "time": { "checkedAt": { "ago": w(5) } } },
    "quota": { "state": "ok", "windows": [window(60), window(20)], "time": { "checkedAt": { "ago": w(5) } } },
    "available": Json::array(models.map(fn(m) { Json::string(m.0) })),
    "models": Json::array(models.map(fn(m) { Json::string(m.0) })),
    "names": Json::object(Map::from_array(models.map(fn(m) { (m.0, Json::string(m.1)) }))),
  }
}

///|
/// A workspace's mark before its switch's title.
let profile_ws_mark : Double = 16.0
