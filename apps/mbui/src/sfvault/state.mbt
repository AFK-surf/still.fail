// The vault client's state and what it reads of the core (docs/vault.md; the core's views/vault.ts): the workspace
// in view's vaults (`vaults`: whether this device may use them, the requests waiting on the person), each vault's
// items (`vaultItems`), the grants agents hold now (`vaultHeld`), the uses (`vaultUses`, an item's or a whole
// vault's). What the person does goes to the core as calls (`vault.*`); an item opened (`vault.open`: the person asked
// first, unless its vault is unlocked) is held here only while it is the one shown, never kept.

///|
/// What the sidebar picked: what is going on now (the requests, the grants held, the uses), every item, one kind's,
/// one vault's.
pub(all) enum Pick {
  Now
  All
  OfKind(String)
  InVault(String)
} derive(Eq)

///|
/// An item as the lists show it: the vault it is in, and the core's row of it (`vaultItems`' items).
pub(all) struct Row {
  vault : String
  row : Json
} derive(Eq)

///|
/// The client's state, signals all of it.
pub(all) struct State {
  src : @sfbase.Source
  pick : @signals.Signal[Pick]
  /// the item shown (its vault, its id; "" none)
  chosen : @signals.Signal[(String, String)]
  /// 小屏: the item shown over the list
  opened : @signals.Signal[Bool]
  /// the item being written ("" its id: a new one), and its kind; None: none
  editing : @signals.Signal[(String, String)?]
  /// the item shown as opened (`vault.open`'s answer: `plain`, `shown`), by its id; dropped as another is shown
  plain : @signals.Signal[(String, Json)?]
  /// the fields shown in the clear (their keys), of the item opened
  clear : @signals.Signal[Array[String]]
  /// the item shown asked to be deleted: its delete to be confirmed
  deleting : @signals.Signal[Bool]
  /// the recovery words the core gave as the vault was set up here (shown once)
  words : @signals.Signal[String]
  search : @ui.Field
}

///|
pub fn State::new(src : @sfbase.Source) -> State {
  {
    src,
    pick: @signals.signal(Now),
    chosen: @signals.signal(("", "")),
    opened: @signals.signal(false),
    editing: @signals.signal(None),
    plain: @signals.signal(None),
    clear: @signals.signal([]),
    deleting: @signals.signal(false),
    words: @signals.signal(""),
    search: @ui.Field::new(),
  }
}

// ---- what is read ----

///|
/// The workspace in view ("" none yet).
pub fn State::ws(self : State) -> String {
  match @sfbase.workspace_in_view(self.src).0 {
    Some(w) => w.id
    None => ""
  }
}

///|
fn State::topic(self : State, name : String, more : Array[(String, String)]) -> @sfbase.Topic {
  let params : Map[String, Json] = { "workspace": Json::string(self.ws()) }
  for p in more {
    params[p.0] = Json::string(p.1)
  }
  (self.src.topic)(name, params)
}

///|
/// The `vaults` topic (None while it is read).
pub fn State::vaults(self : State) -> Json? {
  self.topic("vaults", []).value
}

///|
/// The vaults this person is in (the plain library as one).
pub fn State::vault_rows(self : State) -> Array[Json] {
  @sfbase.items(self.vaults(), "vaults")
}

///|
/// A vault's row by its id.
pub fn State::vault(self : State, id : String) -> Json? {
  for v in self.vault_rows() {
    if @sfbase.text(Some(v), "id") == id {
      return Some(v)
    }
  }
  None
}

///|
/// Whether the library is in plain text on the station (no security mode).
pub fn State::plain_library(self : State) -> Bool {
  @sfbase.flag(self.vaults(), "plain")
}

///|
/// Every item of every vault this person is in.
pub fn State::rows(self : State) -> Array[Row] {
  let out : Array[Row] = []
  for v in self.vault_rows() {
    let id = @sfbase.text(Some(v), "id")
    for r in @sfbase.items(self.topic("vaultItems", [("vault", id)]).value, "items") {
      out.push({ vault: id, row: r })
    }
  }
  out
}

///|
/// An item's name as its row says it (a locked vault's not listed one: none).
pub fn row_name(r : Json) -> String {
  match @sfbase.text(Some(r), "name") {
    "" => @sf.t("web-pages.vault.kind." + @sfbase.text(Some(r), "kind"))
    n => n
  }
}

///|
/// What the list shows now: what the sidebar picked, as the search finds it (its name, kind, domains, variable), by
/// name.
pub fn State::listed(self : State) -> Array[Row] {
  let p = self.pick.get()
  let q = self.search.text().trim(chars=" ").to_owned().to_lower()
  let out = self
    .rows()
    .filter(fn(r) {
      let v = Some(r.row)
      let picked = match p {
        Now | All => true
        OfKind(k) => @sfbase.text(v, "kind") == k
        InVault(id) => r.vault == id
      }
      picked &&
      (q == "" ||
      row_name(r.row).to_lower().contains(q) ||
      @sfbase.text(v, "kindText").to_lower().contains(q) ||
      @sfbase.text(v, "env").to_lower().contains(q) ||
      @settings.strings(v, "hosts").iter().any(fn(h) { h.to_lower().contains(q) }))
    })
  out.sort_by(fn(a, b) { in_order(row_name(a.row), row_name(b.row)) })
  out
}

///|
/// How `a` and `b` are ordered as words are, character by character (a shorter one first where one begins the other).
fn in_order(a : String, b : String) -> Int {
  let x = a.to_lower().to_array()
  let y = b.to_lower().to_array()
  let n = if x.length() < y.length() { x.length() } else { y.length() }
  for i in 0..<n {
    if x[i] != y[i] {
      return x[i].compare(y[i])
    }
  }
  x.length().compare(y.length())
}

///|
/// The item shown's row (None: none, or gone).
pub fn State::chosen_row(self : State) -> Json? {
  let (vault, id) = self.chosen.get()
  for r in @sfbase.items(self.topic("vaultItems", [("vault", vault)]).value, "items") {
    if @sfbase.text(Some(r), "id") == id {
      return Some(r)
    }
  }
  None
}

///|
/// The requests waiting on the person (`vaults`' requests).
pub fn State::requests(self : State) -> Array[Json] {
  @sfbase.items(self.vaults(), "requests")
}

///|
/// The grants agents hold now that the person may take back.
pub fn State::grants(self : State) -> Array[Json] {
  @sfbase.items(self.topic("vaultHeld", []).value, "grants")
}

///|
/// An item's uses, the latest first.
pub fn State::item_uses(self : State, vault : String, item : String) -> Array[Json] {
  @sfbase.items(self.topic("vaultUses", [("vault", vault), ("item", item)]).value, "uses")
}

///|
/// Every vault's uses together, the latest first, at most `most`.
pub fn State::recent(self : State, most? : Int = 12) -> Array[Json] {
  let all : Array[Json] = []
  for v in self.vault_rows() {
    for u in self.item_uses(@sfbase.text(Some(v), "id"), "") {
      all.push(u)
    }
  }
  all.sort_by(fn(a, b) { at_of(b).compare(at_of(a)) })
  if all.length() > most {
    all[:most].to_array()
  } else {
    all
  }
}

///|
/// When a use or a grant was (its stamp's ms).
fn at_of(v : Json) -> Double {
  @sfbase.number(@sfbase.field(Some(v), "at"), "at")
}

///|
/// How many items each pick holds.
pub fn State::count(self : State, p : Pick) -> Int {
  match p {
    Now => self.requests().length()
    All => self.rows().length()
    OfKind(k) => self.rows().filter(fn(r) { @sfbase.text(Some(r.row), "kind") == k }).length()
    InVault(id) => self.rows().filter(fn(r) { r.vault == id }).length()
  }
}

// ---- what is done ----

///|
fn State::params(self : State, more : Array[(String, Json)]) -> Json {
  @settings.obj([("workspace", @settings.str(self.ws())), ..more])
}

///|
/// Item `id` of `vault` shown (its fields not opened yet).
pub fn State::show(self : State, vault : String, id : String) -> Unit {
  self.chosen.set((vault, id))
  self.opened.set(true)
  self.editing.set(None)
  self.deleting.set(false)
  self.clear.set([])
  self.plain.set(None)
}

///|
/// The item shown opened (the person asked, unless its vault is unlocked): its fields, then `then`.
pub fn State::open(self : State, then? : () -> Unit = fn() {  }) -> Unit {
  let (_, id) = @signals.untracked(fn() { self.chosen.get() })
  @sfbase.act(self.src, @sf.t("web-pages.vault.unlockWhat"), "vault/open/" + id, "vault.open", self.params([("item", @settings.str(id))]), ok=fn(v) {
    // (still the one shown)
    if @signals.untracked(fn() { self.chosen.get() }).1 == id {
      self.plain.set(Some((id, v)))
      then()
    }
  })
}

///|
/// A field of the item opened shown in the clear, or hidden again.
pub fn State::toggle_clear(self : State, key : String) -> Unit {
  let now = @signals.untracked(fn() { self.clear.get() })
  self.clear.set(if now.contains(key) { now.filter(fn(k) { k != key }) } else { [..now, key] })
}

///|
/// A field's value copied: a secret one cleared from the clipboard after 90 s (as a password manager does).
pub fn State::copy(self : State, label : String, value : String, secret : Bool) -> Unit {
  ignore(self)
  if secret {
    @hostapi.clipboard_set_secret(value, clear_ms=90000.0)
    @sfbase.toast_later(@sf.t("web-pages.vaultApp.copiedSecret", args=[("label", label)]))
  } else {
    @ui.clipboard_set(value)
    @sfbase.toast_later(@sf.t("web-pages.vaultApp.copiedField", args=[("label", label)]))
  }
}

///|
/// The vault's unlocked keys forgotten now.
pub fn State::lock(self : State) -> Unit {
  self.plain.set(None)
  self.clear.set([])
  @sfbase.act(self.src, @sf.t("web-pages.vault.lockNow"), "vault/lock", "vault.lock", self.params([]))
}

///|
/// A vault unlocked (by opening one of its items: the person asked).
pub fn State::unlock(self : State, vault : String) -> Unit {
  let first = @signals.untracked(fn() { @sfbase.items(self.topic("vaultItems", [("vault", vault)]).value, "items") })
  guard first.get(0) is Some(r) else { return }
  @sfbase.act(self.src, @sf.t("web-pages.vault.unlockWhat"), "vault/unlock/" + vault, "vault.open", self.params([
    ("item", @settings.str(@sfbase.text(Some(r), "id"))),
  ]))
}

///|
/// A request approved: once, or for `seconds` (`kind`: idle or fixed), as far as the item allows; a secret to keep
/// kept.
pub fn State::approve(self : State, request : String, timeout? : (String, Int)) -> Unit {
  let ps : Array[(String, Json)] = [("request", @settings.str(request))]
  match timeout {
    Some((kind, seconds)) => {
      ps.push(("scope", @settings.str(if seconds <= 3600 { "hour" } else { "chat" })))
      ps.push(("timeout", @settings.obj([("kind", @settings.str(kind)), ("seconds", Json::number(seconds.to_double()))])))
    }
    None => ps.push(("scope", @settings.str("once")))
  }
  @sfbase.act(self.src, @sf.t("android-settings.vault.act.allowWhat"), "vault/approve/" + request, "vault.approve", self.params(ps))
}

///|
pub fn State::deny(self : State, request : String) -> Unit {
  @sfbase.act(self.src, @sf.t("android-settings.vault.act.denyWhat"), "vault/deny/" + request, "vault.deny", self.params([
    ("request", @settings.str(request)),
  ]))
}

///|
/// A grant agents hold taken back now.
pub fn State::revoke(self : State, request : String) -> Unit {
  @sfbase.act(
    self.src,
    @sf.t("web-pages.vaultApp.revokeWhat"),
    "vault/revoke/" + request,
    "vault.revoke",
    self.params([("request", @settings.str(request))]),
    done=@sf.t("web-pages.vaultApp.revoked"),
  )
}

///|
/// The item shown deleted.
pub fn State::delete(self : State) -> Unit {
  let (vault, id) = @signals.untracked(fn() { self.chosen.get() })
  @sfbase.act(
    self.src,
    @sf.t("web-pages.vaultApp.deleteWhat"),
    "vault/delete/" + id,
    "vault.deleteItem",
    self.params([("vault", @settings.str(vault)), ("item", @settings.str(id))]),
    done=@sf.t("web-pages.vaultApp.deleted"),
    ok=fn(_) {
      self.chosen.set(("", ""))
      self.opened.set(false)
      self.deleting.set(false)
    },
  )
}

///|
/// This device's vault turned on (`vault.setup`): the recovery words shown the first time.
pub fn State::set_up(self : State) -> Unit {
  @sfbase.act(self.src, @sf.t("web-pages.vault.setUpWhat"), "vault/setup", "vault.setup", self.params([]), ok=fn(v) {
    let w = @sfbase.text(Some(v), "words")
    if w != "" {
      self.words.set(w)
    }
  })
}

///|
/// This device asking the person's other devices for the keys it lacks.
pub fn State::ask_keys(self : State) -> Unit {
  @sfbase.act(self.src, @sf.t("web-pages.vault.askWhat"), "vault/ask", "vault.ask", self.params([]), done=@sf.t("web-pages.vault.asked"))
}

///|
/// Whether `key`'s call is under way.
pub fn doing(key : String) -> Bool {
  @sfbase.acting.doing.get(key).unwrap_or(false)
}
