// Made-up settings in the core's shapes (WorkspaceView, StationView, LockView, VaultsView, ProfilesView, ConnectsView,
// UsageView, ArchiveView, StationMemory…) for the app with no core (src/sffix): screenshots that are the same on every
// run (scripts/shots.sh settings, web-settings). Every word here is made up. The workspace is the fixture's own ws1
// (星火工作室, lin@example.com), its stations ws1/st1 (Willow) and ws1/st2 (Maple, offline).

///|
/// What the made-up settings changed since they started (a station renamed, a chat restored), and how often.
priv struct SettingsFixture {
  names : Map[String, String]
  restored : Map[String, Bool]
  mut version : Int
  /// the stations' marks set (by id)
  marks : Map[String, String]
  /// the station's updating by itself
  mut auto : Bool
  /// the station's congestion control
  mut congestion : String
  /// the station going on afresh by itself once a session's cache is over, and its cost threshold
  mut afresh : Bool
  mut afresh_above : Double
  /// the station sending its log to still.fail
  mut logs : Bool
  /// a Windows station's running as administrator, as the core shows it (its overview's `elevation`), as a test sets
  /// it; none: not a Windows station
  mut elevation : Json?
  /// the copies of its chats as the core shows them (its overview's `copies`), as a mode sets them; none: a station
  /// from before them
  mut copies : Json?
  /// The station with two GPUs, for the resource overview's fixture.
  mut gpus : Bool
  /// Four GPUs, to exercise another row of resource dials.
  mut more_gpus : Bool
  /// Willow's CPU, memory and disk all running low (settings-stations-low): its card's line of three chips.
  mut low_meters : Bool
  /// the mode's page has no station (settings-first-station)
  mut none : Bool
  /// the subscription's sign-in: "" none, "needs_code" under way (settings-profile-login), "failed"
  /// (settings-profile-login-failed)
  mut login : String
  /// the sign-in's page can be opened in the station's own browser (settings-profile-login-station,
  /// settings-new-profile-login-station)
  mut login_station : Bool
  /// a new profile's page at an Anthropic plan's sign-in, waiting for the code (settings-new-profile-login…)
  mut new_login : Bool
  /// Claude 主账号's trouble: "" none, "quota" its allowance unreadable (settings-profile-quota-failed), "blocked"
  /// its allowance used up (settings-profile-blocked), "login" to be signed in to again (settings-profile-signin)
  mut trouble : String
  /// the vault not set up on this device (settings-vault-off)
  mut vault_off : Bool
  /// secrets of lin's still in plain text from before security mode (settings-vault-plain), until encrypted
  mut plain_left : Int
  /// lin's own vault waiting to be keyed anew on Willow, a device holding its key taken out of the lock
  /// (settings-vault-waits): its row's `waits`
  mut vault_waits : Bool
  /// the skills shared (true) or no longer (false) since the run started (`skill.share`), by name
  skills_shared : Map[String, Bool]
  /// the quota's resets used on ChatGPT 团队 (`profile.resetQuota`)
  mut resets_used : Int
  /// Two reset credits with distinct expiry times (settings-profile-quota-expiry).
  mut reset_expiry : Bool
  /// Claude 主账号's resets of two kinds: a 5-hour one usable only at a limit, a Fable one usable now, used by
  /// `profile.resetQuota` with its kind (settings-profile-quota-kinds).
  mut reset_kinds : Bool
  /// the Fable reset used (`profile.resetQuota` with `reset: model`)
  mut fable_used : Bool
  /// the models named by hand on ChatGPT 团队 (`profile.addModel`)
  models_added : Array[String]
  /// Whether the example API key is enabled.
  mut key_enabled : Bool
  /// A copy of Maple's Claude subscription among Willow's profiles (settings-profile-copy), and whether Willow uses it.
  mut copy_shown : Bool
  mut copy_enabled : Bool
  /// a new device of lin's asking to be let in with this one's code (settings-lock-prompt), until turned away or its
  /// prompt closed
  mut pairing : Bool
  mut pairing_personal : Bool
  /// asked into one more workspace meanwhile (开源, its mark an emoji): fixture_prompts_now
  mut pairing_more : Bool
  /// Maple is being added to security mode (settings-security-protecting).
  mut protecting : Bool
  /// the lock's changes made here that no station took yet, by id (settings-security-pending: `fx_pending_rows`),
  /// a failed one dropped by `lock.pendingDismiss`
  pending : Array[String]
  /// how its prompt went: "deny" (turned away), "hide" (closed, the code still good), "" while it is up
  mut pair_ended : String
  /// a device of lin's (Pixel 9) set up without the key to 林的库, waiting on this one for it (settings-vault-prompt),
  /// until given it or put away
  mut key_ask : Bool
  /// how that went: "give" (授权), "hide" (稍后, or closed), "" while it is up
  mut key_ask_ended : String
  /// the key being given it (the core's `doing`: vault.addDevice under way): fixture_prompts_now
  mut key_giving : Bool
  /// Maple online too (settings-profiles-pick: Profile's ＋ asks which station)
  mut mba_online : Bool
  // (settings-station-away: Willow away, what it last said of itself kept)
  mut willow_away : Bool
  // (settings-stations-incompatible: Willow up, saying what this core cannot read)
  mut willow_incompatible : Bool
  // (settings-stations-tasks-theirs: Willow added by another member, its mode not the viewer's to change)
  mut willow_theirs : Bool
  /// the subscriptions' allowances a month's window too, three in all (settings-profiles-monthly: OpenCode Go's)
  mut monthly : Bool
  /// the Claude subscription's allowance its models' own weeks too, under the account's: how many of Fable's, Opus's
  /// (nearly spent) and Sonnet's (settings-profiles-fable, settings-profile-fable: one; …-own3: all three, five windows)
  mut own : Int
  /// that subscription with no 5 小时 window (…-week-fable: the account's week and Fable's alone, as an account says
  /// them whose short window has not begun)
  mut no_hours : Bool
  /// five Claude subscription accounts, by their e-mails, each its own windows as a report showed them
  /// (settings-profiles-several: one row's figures a point wider than the others')
  mut several : Bool
  /// Willow's own Codex login, not a profile yet, with its allowance as the core sends an offered login's
  /// (settings-profiles-offer: what is left of its week shown where it is listed, as a profile's is)
  mut offer_quota : Bool
  /// The same subscription independently signed in and borrowed on several stations.
  mut profile_hosts : Bool
  /// Only one station is signed in; another borrows it.
  mut profile_one_owner : Bool
  /// A borrowing station cannot reach its source, and another station is offline.
  mut profile_away : Bool
  /// A station may use the account, but its copy has not arrived yet.
  mut profile_pending : Bool
  /// That station is cut off from still.fail cloud, so the copy does not come.
  mut profile_cut_off : Bool
  /// how far the made-up workspace has changed on its own (settings-workspace-motion, settings-stations-motion): 1 a
  /// person and a station come, 2 one of each goes (fixture_motion)
  mut motion : Int
  /// the bytes of the drives' files kept (`cache.usage`'s `drive`), until let go (`drive.kept.clear`)
  mut drive_kept : Double
  /// the chats' files kept let go (`cache.file.clear`), by name
  kept_cleared : Array[String]
}

///|
let fx : SettingsFixture = {
  names: {},
  restored: {},
  version: 0,
  marks: {},
  auto: false,
  congestion: "cubic",
  afresh: false,
  afresh_above: 1.0,
  logs: true,
  elevation: None,
  copies: None,
  gpus: false,
  more_gpus: false,
  low_meters: false,
  none: false,
  login: "",
  login_station: false,
  new_login: false,
  trouble: "",
  vault_off: false,
  plain_left: 0,
  vault_waits: false,
  skills_shared: {},
  resets_used: 0,
  reset_expiry: false,
  reset_kinds: false,
  fable_used: false,
  models_added: [],
  key_enabled: true,
  copy_shown: false,
  copy_enabled: true,
  pairing: false,
  pairing_personal: false,
  pairing_more: false,
  protecting: false,
  pending: [],
  pair_ended: "",
  key_ask: false,
  key_ask_ended: "",
  key_giving: false,
  mba_online: false,
  willow_away: false,
  willow_incompatible: false,
  willow_theirs: false,
  monthly: false,
  own: 0,
  no_hours: false,
  several: false,
  offer_quota: false,
  profile_hosts: false,
  profile_one_owner: false,
  profile_away: false,
  profile_pending: false,
  profile_cut_off: false,
  motion: 0,
  drive_kept: fx_drive_kept,
  kept_cleared: [],
}

///|
/// A chat's file kept (`cache.usage`'s `files`, `loose`): its session, its name, its size, the bytes kept of it, when
/// it was last opened (the fixture's clock stands at 0), unless let go.
fn fx_kept_file(key : String, name : String, size : Double, bytes : Double, opened : Double, station? : String) -> Json? {
  if fx.kept_cleared.contains(name) {
    return None
  }
  let o : Map[String, Json] = {
    "key": str(key),
    "name": str(name),
    "size": Json::number(size),
    "bytes": Json::number(bytes),
    "opened": Json::number(opened),
  }
  match station {
    Some(s) => o["station"] = str(s)
    None => ()
  }
  Some(Json::object(o))
}

///|
/// lin's own vault, 林的库 on Willow, as the core's `vaults` lists it: waiting to be keyed anew there (`waits`) in
/// settings-vault-waits only, as the core says it only while it does.
fn fx_vault_row() -> Json {
  let row : Array[(String, Json)] = [
    ("id", str("v1")),
    ("name", str("林的库")),
    ("owner", str("u1")),
    ("ownerName", str("林")),
    ("mine", Json::boolean(true)),
    ("members", []),
    ("station", str("st1")),
    ("stationName", str("Willow")),
    ("items", Json::number(3.0)),
    ("devices", Json::number(2.0)),
    ("open", Json::boolean(false)),
    ("keyed", Json::boolean(true)),
    ("missing", Json::number(0.0)),
    ("recoverable", Json::boolean(true)),
  ]
  if fx.vault_waits {
    row.push(("waits", str("Willow")))
  }
  obj(row)
}

///|
/// What the drives' files kept come to as a run starts: 38.5 MB.
let fx_drive_kept : Double = 40370176.0

///|
/// A sheet a fixture's mode puts up over its page once it is drawn (mark, add, add-existing, add-command, env), and a
/// page's list to scroll to a block ("" none).
priv struct FixtureOpen {
  mut sheet : String
  mut list : String
  mut block : Int
  mut frames : Int
  /// a dialog of the desktop's pages to put up (src/sfdesk: fixture_desk), "" none
  mut desk : String
}

///|
let fixture_open : FixtureOpen = { sheet: "", list: "", block: 0, frames: 0, desk: "" }

///|
/// The new connect's step its fixture shows (MBUI_FIXTURE=settings-new-connect: team; -platform, -scan: Feishu's).
let fx_connect_step : Ref[String] = Ref("team")

///|
/// 连接 (MBUI_FIXTURE=settings-connects): a Slack app made and not connected yet over the connects, one connect with its
/// own picture and one with its platform's mark.
let fx_connects_waiting : Ref[Bool] = Ref(false)

///|
/// A station with enough accounts in one kind to search its profiles.
let fx_station_many_profiles : Ref[Bool] = Ref(false)

///|
/// A station whose update failed because its state could not be read.
let fx_station_update_failed : Ref[Bool] = Ref(false)

///|
/// A station just updated, what the update said kept on its row (the core's `done`): a sentence beside the name, which
/// a phone with bigger words drew over it (#5117; words_large_wbtest.mbt).
let fx_station_updated : Ref[Bool] = Ref(false)

///|
/// The made-up settings as a run starts (reset): none changed, no sheet or scroll to put up.
fn fixture_reset() -> Unit {
  fx.names.clear()
  rigs_fixture_reset()
  devices_fixture_reset()
  fx_many_models.val = false
  fx_many_kept.val = false
  fx_station_many_profiles.val = false
  fx_station_update_failed.val = false
  fx_station_updated.val = false
  fx.restored.clear()
  fx.skills_shared.clear()
  fx.drive_kept = fx_drive_kept
  fx.kept_cleared.clear()
  fx.resets_used = 0
  fx.reset_expiry = false
  fx.reset_kinds = false
  fx.fable_used = false
  fx.models_added.clear()
  fx.key_enabled = true
  fx.copy_shown = false
  fx.copy_enabled = true
  fx.version = 0
  fx.marks.clear()
  fx.auto = false
  fx.afresh = false
  fx.afresh_above = 1.0
  fx.logs = true
  fx.elevation = None
  fx.copies = None
  fx.gpus = false
  fx.more_gpus = false
  fx.low_meters = false
  fx.congestion = "cubic"
  fx.none = false
  fx_adb.val = ""
  fx.login = ""
  fx.login_station = false
  fx.new_login = false
  fx.trouble = ""
  fx.vault_off = false
  fx.plain_left = 0
  fx.vault_waits = false
  fx.pairing = false
  fx.pairing_personal = false
  fx.pairing_more = false
  fx.protecting = false
  fx.pending.clear()
  fx.pair_ended = ""
  fx.key_ask = false
  fx.key_ask_ended = ""
  fx.key_giving = false
  fx.mba_online = false
  fx.willow_away = false
  fx.willow_incompatible = false
  fx.willow_theirs = false
  fx.monthly = false
  fx.own = 0
  fx.no_hours = false
  fx.several = false
  fx.offer_quota = false
  fx.profile_hosts = false
  fx.profile_one_owner = false
  fx.profile_away = false
  fx.profile_pending = false
  fx.profile_cut_off = false
  fx.motion = 0
  fixture_open.sheet = ""
  fixture_open.list = ""
  fixture_open.block = 0
  fixture_open.frames = 0
  fixture_open.desk = ""
  fx_connect_step.val = "team"
  fx_connects_waiting.val = false
}

///|
/// The made-up workspace's people (settings-workspace-motion: 林 comes, then 周 goes).
fn fx_members(me : Json) -> Json {
  let all = [
    me,
    obj([("sub", str("u2")), ("email", str("ana@example.com")), ("name", str("Ana")), ("role", str("admin"))]),
    obj([("sub", str("u3")), ("email", str("zhou@example.com")), ("name", str("周")), ("role", str("member"))]),
  ]
  if fx.motion >= 1 {
    all.push(obj([("sub", str("u5")), ("email", str("lin2@example.com")), ("name", str("林")), ("role", str("member"))]))
  }
  if fx.motion >= 2 {
    all.remove(2) |> ignore
  }
  Json::array(all)
}

///|
/// `v`'s items as the made-up workspace has changed on its own (fx's `motion`): `add` come at 1, the one `gone` names
/// gone at 2 (settings-*-motion).
fn fx_moved(v : Json, add : Json, gone : (Json) -> Bool) -> Json {
  match v {
    Object(m) =>
      match m.get("items") {
        Some(Array(a)) => {
          let b = a.copy()
          if fx.motion >= 1 {
            b.push(add)
          }
          m["items"] = Json::array(if fx.motion >= 2 { b.filter(fn(x) { !gone(x) }) } else { b })
        }
        _ => ()
      }
    _ => ()
  }
  v
}

///|
/// The made-up workspace changed on its own as far as `step` (fx's `motion`), for the recordings of its pages' lists'
/// motion: told to what follows the made-up core's topics.
pub fn fixture_motion(step : Int) -> Unit {
  fx.motion = step
  fx_changed()
}

///|
/// How often the made-up settings changed: added to the fixture's own version.
pub fn fixture_version() -> Int {
  fx.version
}

///|
/// The made-up settings changed: their version on by one, told to what follows the made-up core's topics.
fn fx_changed() -> Unit {
  fx.version += 1
  fixture_changed()
}

///|
/// The made-up core's changes (the app's fixture's and its settings'), told to what follows its topics as they happen,
/// as the core client tells a subscription's (src/core Sub.changes): fixture_changed with each, fixture_followed as a
/// topic of it is read.
// kept across runs: a count of changes; a run anew reads its topics anew
let fixture_changes : @signals.Signal[Int] = @signals.signal(0)

///|
/// The made-up core changed (the app's fixture, its settings, its browsing): what read its topics in a computed is
/// worked out again.
pub fn fixture_changed() -> Unit {
  fixture_changes.set(fixture_changes.untracked() + 1)
}

///|
/// A topic of the made-up core read: what reads it in a computed follows its changes (fixture_changed).
pub fn fixture_followed() -> Unit {
  fixture_changes.get() |> ignore
}

///|
/// A draft's words told the made-up core (`composer.text`): its topic alone changed, told to what reads that topic
/// (fixture_draft_followed), nothing else of the made-up core's, as the core changes the draft's alone.
// kept across runs: a count of changes; a run anew reads its topics anew
let fixture_draft_changes : @signals.Signal[Int] = @signals.signal(0)

///|
/// A draft's words changed in the made-up core (fixture_draft_changes).
pub fn fixture_draft_changed() -> Unit {
  fixture_draft_changes.set(fixture_draft_changes.untracked() + 1)
}

///|
/// A draft's topic of the made-up core read: followed as its words change (fixture_draft_changed).
pub fn fixture_draft_followed() -> Unit {
  fixture_draft_changes.get() |> ignore
}

///|
/// How the new device's prompt went (`lockPrompt.deny` "deny", `lockPrompt.hide` "hide"; "" while it is up).
pub fn fixture_pair_ended() -> String {
  fx.pair_ended
}

///|
/// How the prompt for a vault's key went (`vault.addDevice` "give", `vault.hidePrompt` "hide"; "" while it is up).
pub fn fixture_key_ask_ended() -> String {
  fx.key_ask_ended
}

///|
/// What the made-up core's `lockPrompts` holds now, as another device changed it (lock_prompts.mbt, vault_prompts.mbt):
/// the new device asking (`pairing`; into one more workspace meanwhile, `more`), the device waiting for the vault's key
/// (`key_ask`; the key being given it, `giving`), told to what follows its topics.
pub fn fixture_prompts_now(pairing~ : Bool, more? : Bool = false, key_ask~ : Bool, giving? : Bool = false) -> Unit {
  fx.pairing = pairing
  fx.pairing_more = more
  fx.key_ask = key_ask
  fx.key_giving = giving
  fx_changed()
}

///|
/// Willow a Windows station, running as administrator as `v` says (the core's `StationElevation`), or not.
pub fn fixture_elevation(v : Json?) -> Unit {
  fx.elevation = v
}

///|
/// The page a fixture's mode opens (MBUI_FIXTURE=settings-<page>[-dark]), by the name route_of takes.
pub fn fixture_page(mode : String) -> String {
  let m = if mode.has_suffix("-dark") {
    mode.unsafe_substring(start=0, end=mode.length() - 5)
  } else {
    mode
  }
  // a sheet up over the page, or the page scrolled down (fixture_open; the library's pages too)
  @sf.page_list_opened.val = fn(c, key, rows) { fixture_scroll(c, key, rows~) }
  let up = fn(sheet : String, list : String, block : Int) {
    fixture_open.sheet = sheet
    fixture_open.list = list
    fixture_open.block = block
    fixture_open.frames = 0
  }
  // 共享调试 as it stands with the phone (fx_adb_share), its host's word on the phone said already (settings-adb-desk: a
  // computer's host, no adb of its own)
  fx_adb.val = ""
  if m.has_prefix("settings-adb-") {
    fx_adb.val = m.unsafe_substring(start=13, end=m.length())
    adb_host.phone.set(Some(
      if fx_adb.val == "desk" {
        obj([("supported", Json::boolean(false)), ("none", Json::boolean(true))])
      } else {
        obj([
          ("supported", Json::boolean(true)),
          ("developer", Json::boolean(true)),
          ("wireless", Json::boolean(fx_adb.val != "off" && fx_adb.val != "chats-off")),
          ("wifi", Json::boolean(true)),
          ("canSwitch", Json::boolean(false)),
        ])
      },
    ))
  }
  match m {
    // The grants list with long reasons is itself in view for the spacing and corner sweeps.
    "settings-adb-chats-long" => up("", "settings/adb/", 4)
    "settings-station-mark" => up("mark", "", 0)
    "settings-station-many-profiles" => fx_station_many_profiles.val = true
    "settings-station-gpu" => fx.gpus = true
    "settings-stations-low" => fx.low_meters = true
    "settings-station-gpu-many" => {
      fx.gpus = true
      fx.more_gpus = true
    }
    // the page's 设置 (its variables' sheet up over it), its 软件与设备
    "settings-station-env" => station_parts["ws1/st1"] = "settings"
    // its 设置 while it is away: only what can be changed then
    "settings-stations-incompatible" => fx.willow_incompatible = true
    "settings-stations-tasks-theirs" => fx.willow_theirs = true
    "settings-station-away" => {
      fx.willow_away = true
      station_parts["ws1/st1"] = "settings"
    }
    // its 设置 with 高级网络设置 opened: its congestion control, a section of the page after it
    "settings-station-network" => {
      station_parts["ws1/st1"] = "settings"
      station_network_open["ws1/st1"] = true
      up("", "settings/station/ws1/st1", -1)
    }
    // its 设置 scrolled to 备份: its row (Cedar and Aspen up to date; -alone: the only station of its workspace)
    "settings-station-copies" | "settings-station-copies-alone" => {
      fx.copies = Some(fixture_copies_row(alone=m == "settings-station-copies-alone"))
      station_parts["ws1/st1"] = "settings"
      up("", "settings/station/ws1/st1", -1)
    }
    // a new station's 设置 scrolled to 备份: a backup of a station no longer there it can restore (-offer: 恢复到这台
    // live; -confirm: asked first), one being restored; -restored: what came of it, after the restart
    "settings-station-restore" => {
      fx.copies = Some(fixture_copies_restore(under_way=true, name="Old Mac"))
      station_parts["ws1/st1"] = "settings"
      up("", "settings/station/ws1/st1", -1)
    }
    // (-long: a station named in 24 characters, its confirm's title kept to one line)
    "settings-station-restore-offer" | "settings-station-restore-confirm" | "settings-station-restore-confirm-long" => {
      fx.copies = Some(fixture_copies_restore(under_way=false, name=if m == "settings-station-restore-confirm-long" { "Lin's MacBook Pro (2021)" } else { "Old Mac" }))
      station_parts["ws1/st1"] = "settings"
      up("", "settings/station/ws1/st1", -1)
      if m != "settings-station-restore-offer" {
        fixture_open.desk = "copies-confirm"
      }
    }
    "settings-station-restored" => {
      fx.copies = Some(fixture_copies_restored())
      station_parts["ws1/st1"] = "settings"
      up("", "settings/station/ws1/st1", -1)
    }
    // its 进程: what still.fail uses of the machine
    "settings-station-processes" => station_parts["ws1/st1"] = "processes"
    "settings-station-lower" => {
      station_parts["ws1/st1"] = "settings"
      up("", "settings/station/ws1/st1", 0)
    }
    "settings-station-versions" | "settings-station-update-failed" | "settings-station-updated" => {
      station_parts["ws1/st1"] = "machine"
      fx_station_update_failed.val = m == "settings-station-update-failed"
      fx_station_updated.val = m == "settings-station-updated"
      up("", "settings/station/ws1/st1", 0)
    }
    "settings-stations-add" => up("add", "", 0)
    // Profile's ＋ with more than one station online: which to add it on (pressed by the film's step)
    "settings-profiles-pick" => fx.mba_online = true
    "settings-profiles-monthly" => fx.monthly = true
    "settings-profiles-fable" | "settings-profile-fable" => fx.own = 1
    // (settings-station-own3: the station's page, for its accounts' panel pictured with them)
    "settings-profiles-own3" | "settings-profile-own3" | "settings-station-own3" => fx.own = 3
    "settings-profiles-week-fable" | "settings-profile-week-fable" => {
      fx.own = 1
      fx.no_hours = true
    }
    "settings-profiles-several" => fx.several = true
    "settings-profiles-offer" => fx.offer_quota = true
    "settings-stations-existing" => up("add-existing", "", 0)
    "settings-stations-command" => up("add-command", "", 0)
    "settings-first-station" => fx.none = true
    "settings-profile-lower" => up("", "settings/profile/ws1/st1/cc", 2)
    // The sharing section of the made-up subscription, for reviewing its on-screen layout.
    "settings-profile-share" => up("", "settings/profile/ws1/st1/cc", 6)
    "settings-profile-hosts" | "settings-profile-hosts-one" | "settings-profile-hosts-away" | "settings-profile-hosts-pending" | "settings-profile-hosts-cutoff" => {
      fx.profile_hosts = true
      fx.profile_one_owner = m == "settings-profile-hosts-one"
      fx.profile_away = m == "settings-profile-hosts-away"
      fx.profile_pending = m == "settings-profile-hosts-pending" || m == "settings-profile-hosts-cutoff"
      fx.profile_cut_off = m == "settings-profile-hosts-cutoff"
      up("", "settings/profile/ws1/st1/cc", 3)
    }
    "settings-profile-login" => {
      fx.login = "needs_code"
      up("", "settings/profile/ws1/st1/cc", 0)
    }
    // A copy of another station's subscription: its page, where this station pauses it (its ⋯'s 停用)
    "settings-profile-copy" => {
      fx.copy_shown = true
      up("", "settings/profile/ws1/st1/bx", 0)
    }
    "settings-profile-login-station" => {
      fx.login = "needs_code"
      fx.login_station = true
      up("", "settings/profile/ws1/st1/cc", 0)
    }
    "settings-new-profile-login" => fx.new_login = true
    // three stations online to add it on (Willow, Maple, Cedar): the add page's choice of them
    // (desk_profile_wbtest.mbt's station pressed)
    "settings-new-profile-stations" => {
      fx.mba_online = true
      fx.motion = 1
      fx.names["st3"] = "Cedar"
    }
    "settings-new-profile-login-station" => {
      fx.new_login = true
      fx.login_station = true
    }
    "settings-profile-login-failed" => {
      fx.login = "failed"
      up("", "settings/profile/ws1/st1/cc", 0)
    }
    "settings-profile-quota-failed" => fx.trouble = "quota"
    "settings-profile-quota-login" => fx.trouble = "quota-login"
    "settings-profile-quota-expiry" => fx.reset_expiry = true
    "settings-profile-quota-kinds" => fx.reset_kinds = true
    "settings-profile-blocked" => fx.trouble = "blocked"
    "settings-profile-signin" => fx.trouble = "login"
    // a connect's page; its way of making sessions asked (src/sfpages connect.mbt's dialog)
    "settings-connect-menu" => ()
    "settings-connect-mode" => fixture_open.desk = "connect-mode"
    "settings-vault-off" => fx.vault_off = true
    "settings-vault-plain" => fx.plain_left = 2
    "settings-vault-waits" => fx.vault_waits = true
    "settings-lock-prompt" => fx.pairing = true
    // (one asking into the person's own lock: no workspace named)
    "settings-lock-prompt-personal" => {
      fx.pairing = true
      fx.pairing_personal = true
    }
    "settings-vault-prompt" => fx.key_ask = true
    "settings-vault-words" => recovery_words["ws1"] = fx_words()
    "settings-vault-add" => fixture_open.desk = "vault-add"
    "settings-vault-editor" => fixture_open.desk = "vault-editor"
    "settings-vault-recover" => fixture_open.desk = "vault-recover"
    "settings-add-people" => up("add-people", "", 0)
    "settings-workspace-mark" => up("workspace-mark", "", 0)
    // 外观's 本机字体 open (src/sfpages font_setting.mbt local_tile: the families the host lists)
    "settings-local-fonts" => fixture_open.desk = "local-fonts"
    // the archive policy with a dialog up (src/sfpages automatic_decisions.mbt): its words, an option of the
    // station's; its 安全 with one (security.mbt): Maple to take in, turning it off
    "settings-policy-text" => fixture_open.desk = "policy-text"
    "settings-policy-option" => fixture_open.desk = "policy-option"
    "settings-security-join" => fixture_open.desk = "lock-join"
    "settings-security-off" => fixture_open.desk = "lock-off"
    "settings-security-protecting" => fx.protecting = true
    "settings-security-pending" => fx.pending.append(["p1", "p2", "p3"])
    // the run's models listed (model_list.mbt): more than 8, by series, one of another station's to borrow
    "settings-run-models" => {
      fx_many_models.val = true
      run_list["session:s-c1"] = "model"
    }
    // 本机缓存 with many chats kept (a card of 200 rows)
    "settings-kept-many" => fx_many_kept.val = true
    // the run's accounts listed (run_more.mbt account_list)
    "settings-run-accounts" => run_list["session:s-c1"] = "account"
    // the fonts page at code's faces
    "settings-fonts-code" => fonts_at.set(2)
    "settings-new-connect-platform" => fx_connect_step.val = "platform"
    "settings-new-connect-scan" => fx_connect_step.val = "feishuScan"
    // a new Comma connect's model, its first step after the platform
    "settings-new-connect-comma" => fx_connect_step.val = "commaBind"
    // a new Slack app's step: its name, its look
    "settings-new-connect-app" => fx_connect_step.val = "app"
    "settings-connects" => fx_connects_waiting.val = true
    _ => fx_connect_step.val = "team"
  }
  // a new connect's dialog over 连接 (src/sfpages new_connect.mbt), at the step said above
  if m.has_prefix("settings-new-connect") {
    fixture_open.desk = "new-connect"
  }
  match m {
    "settings" => "home"
    "settings-station-mark" | "settings-station-gpu" | "settings-station-gpu-many" | "settings-station-env" | "settings-station-processes" | "settings-station-lower" | "settings-station-versions" | "settings-station-update-failed" | "settings-station-updated" | "settings-station-network" | "settings-station-away" | "settings-station-copies" | "settings-station-copies-alone" | "settings-station-restore" | "settings-station-restore-offer" | "settings-station-restore-confirm" | "settings-station-restore-confirm-long" | "settings-station-restored" =>
      "station:ws1/st1"
    "settings-stations-add" | "settings-stations-existing" | "settings-stations-command" | "settings-first-station" =>
      "stations"
    "settings-adb" | "settings-adb-off" | "settings-adb-unpaired" | "settings-adb-pairing" | "settings-adb-connected" | "settings-adb-failed" =>
      "adb:ws1/st1"
    "settings-adb-chats" | "settings-adb-chats-off" | "settings-adb-chats-long" | "settings-adb-desk" | "settings-adb-unsigned" | "settings-adb-gate-none" | "settings-adb-gate-code" | "settings-adb-idle" | "settings-adb-lock-member" | "settings-adb-lock-two" | "settings-adb-lock-outside" =>
      "adb:"
    // the second station a phone is lent to, its first paired already
    "settings-adb-second" => "adb:ws1/st2"
    "settings-profile-menu" | "settings-profile-lower" | "settings-profile-share" | "settings-profile-login" | "settings-profile-login-station" =>
      "profile:ws1/st1#cc"
    "settings-new-profile" | "settings-new-profile-hermes" | "settings-new-profile-stations" | "settings-new-profile-login" | "settings-new-profile-login-station" => "new-profile:ws1/st1"
    "settings-connect-menu" | "settings-connect-mode" => "connect:ws1/st1#k1"
    "settings-connect-run" | "settings-connect-switch" | "settings-slack-app" => "connect:ws1/st1#k1"
    // the page of a connect of another kind, none of its sessions yet
    "settings-connect-comma" | "settings-connect-feishu" => "connect:ws1/st1#k1"
    "settings-new-connect" | "settings-new-connect-platform" | "settings-new-connect-scan" | "settings-new-connect-app" | "settings-new-connect-comma" =>
      "connects"
    "settings-vault-off" | "settings-vault-words" | "settings-vault-recover" | "settings-vault-plain" | "settings-vault-waits" =>
      "vault"
    "settings-vault-items" | "settings-vault-add" | "settings-vault-editor" => "vault-items"
    "settings-vault-item" => "vault-item:v1#it1"
    "settings-decisions" => "decisions-settings"
    "settings-completion" => "completion"
    "settings-policy" | "settings-policy-text" | "settings-policy-option" => "policy:ws1/st1"
    "settings-bars" => "bars"
    "settings-kept" | "settings-kept-many" | "settings-kept-fill" => "kept"
    "settings-changelog" => "changelog"
    "settings-about-flow" => "about"
    "settings-fonts-coming" | "settings-fonts-code" => "fonts"
    "settings-prices" => "prices:7"
    "settings-run" | "settings-run-models" | "settings-run-accounts" | "settings-run-runtime" => "run:ws1/st1#s-c1"
    "settings-add-people" | "settings-workspace-mark" | "settings-workspace-motion" => "workspace"
    "settings-stations-motion" | "settings-stations-incompatible" | "settings-stations-low" => "stations"
    "settings-connects-motion" => "connects"
    "settings-vault-motion" => "vault-items"
    "settings-local-fonts" => "fonts"
    "settings-security-join" | "settings-security-off" | "settings-security-protecting" | "settings-security-pending" => "security"
    "settings-stations-tasks" | "settings-stations-tasks-outside" | "settings-stations-tasks-theirs" | "settings-stations-devices" => "stations"
    "settings-station-devices" => "station:ws1/st1"
    "settings-station-tasks" | "settings-station-tasks-locked" => "station:ws1/aa11"
    "settings-station-tasks-other" => "station:ws1/bb22"
    "settings-notify-off" | "settings-lock-prompt" | "settings-lock-prompt-personal" | "settings-vault-prompt" => "home"
    // (the notifications' page; the system having refused them: its banner's way to allow them)
    "settings-notify" | "settings-notify-denied" => "notifications"
    "settings-station" | "settings-station-pages" | "settings-station-many-profiles" | "settings-station-own3" => "station:ws1/st1"
    "settings-station-offline" => "station:ws1/st2"
    "settings-memory" => "memory:ws1/st1"
    "settings-memory-doc" => "memory-doc:ws1/st1#发布流程"
    "settings-profile" | "settings-profile-hosts" | "settings-profile-hosts-one" | "settings-profile-hosts-away" | "settings-profile-hosts-pending" | "settings-profile-hosts-cutoff" | "settings-profile-quota-failed" | "settings-profile-blocked" | "settings-profile-signin" | "settings-profile-fable" | "settings-profile-own3" | "settings-profile-week-fable" =>
      "profile:ws1/st1#cc"
    "settings-profile-key" => "profile:ws1/st1#k2"
    "settings-profile-copy" => "profile:ws1/st1#bx"
    "settings-profile-quota" | "settings-profile-quota-login" | "settings-profile-quota-expiry" => "profile:ws1/st1#cx"
    "settings-profile-quota-kinds" => "profile:ws1/st1#cc"
    "settings-me-reading" => "me"
    "settings-usage-details-pending" => "usage"
    "settings-profiles-pick" | "settings-profiles-monthly" | "settings-profiles-fable" | "settings-profiles-own3" | "settings-profiles-week-fable" | "settings-profiles-several" | "settings-profiles-offer" => "profiles"
    "settings-connect" | "settings-connect-borrow" => "connect:ws1/st1#k1"
    _ =>
      if m.has_prefix("settings-") {
        m.unsafe_substring(start=9, end=m.length())
      } else {
        ""
      }
  }
}

///|
fn stamp_of(ago : String, until? : String = "") -> Json {
  obj([
    ("at", Json::number(0.0)),
    ("ago", str(ago)),
    ("full", str("")),
    ("until", str(until)),
    ("past", Json::boolean(true)),
  ])
}

///|
fn meter(short : String, left : Int, level : String, remaining : String, big : String, unit : String, title : String, total : String, title_short? : String = "", total_short? : String = "") -> Json {
  obj([
    ("titleShort", str(title_short)),
    ("totalShort", str(total_short)),
    ("label", str(short)),
    ("short", str(short)),
    ("percent", Json::number((100 - left).to_double())),
    ("left", Json::number(left.to_double())),
    ("level", str(level)),
    ("value", str("")),
    ("remaining", str(remaining)),
    ("big", str(big)),
    ("unit", str(unit)),
    ("title", str(title)),
    ("total", str(total)),
  ])
}

///|
fn fx_profile(id : String, name : String, kind : String, tone : String, check : String, group : String, title : String, more : Array[(String, Json)]) -> Json {
  let p : Map[String, Json] = {
    "id": str(id),
    "name": str(name),
    "runtime": str(if group == "chatgpt" { "codex" } else { "claude" }),
    "runtimes": [str(if group == "chatgpt" { "codex" } else { "claude" })],
    "access": obj([("kind", str(kind)), ("key", str(if kind == "subscription" { "" } else { "sk-…a41f" }))]),
    "home": "",
    "homeExists": true,
    "models": ["claude-opus-5-5", "claude-sonnet-5", "claude-haiku-5"],
    "named": [],
    "env": [],
    "usedBy": ["k1"],
    "loginCommand": "",
    "checkText": str(check),
    "checkTone": str(tone),
    "planText": str(if id == "cc" { "Ultra" } else if id == "cx" { "Pro 200" } else { "" }),
    // (the core's words of it: present.ts profile)
    "signInProvider": str(if group == "chatgpt" { "ChatGPT" } else { "Claude" }),
    "group": str(group),
    "groupTitle": str(title),
    "makers": obj([]),
    "names": obj([("claude-opus-5-5", str("Opus 5.5")), ("claude-sonnet-5", str("Sonnet 5")), ("claude-haiku-5", str("Haiku 5"))]),
    "series": [
      obj([("name", str("Opus")), ("models", ["claude-opus-5-5"])]),
      obj([("name", str("Sonnet")), ("models", ["claude-sonnet-5"])]),
      obj([("name", str("Haiku")), ("models", ["claude-haiku-5"])]),
    ],
    "modelsText": "3 个模型",
    "available": ["claude-opus-5-5", "claude-sonnet-5", "claude-haiku-5"],
    "usesText": "Claude Code",
    "check": obj([("state", str("ok")), ("detail", str("可用，订阅有效")), ("checkedAt", Json::number(0.0)), ("time", obj([("checkedAt", stamp_of("5 分钟前"))]))]),
    "quota": obj([
      ("state", str("ok")),
      (
        "windows",
        Json::array(
        (if fx.no_hours {
          []
        } else {
          [obj([("label", str("5 小时")), ("usedPercent", Json::number(38.0)), ("mark", str("5H")), ("left", Json::number(62.0)), ("level", str("ok")), ("refills", str(if fx.own > 0 { "3 小时 5 分钟后刷新" } else { "2 小时后恢复" }))])]
        }).iter().concat(
          // (with its models' own: named and refilling in the words the core says, their real length)
          [obj([("label", str(if fx.own > 0 { "每周" } else { "本周" })), ("usedPercent", Json::number(81.0)), ("mark", str("W")), ("left", Json::number(19.0)), ("level", str("amber")), ("refills", str(if fx.own > 0 { "2 天 4 小时后刷新" } else { "星期一恢复" }))])].iter(),
        ).concat(
          (if fx.monthly {
            [obj([("label", str("每月")), ("usedPercent", Json::number(3.0)), ("mark", str("M")), ("left", Json::number(97.0)), ("level", str("ok")), ("refills", str("11 月 1 日恢复"))])]
          } else {
            []
          }).iter(),
        ).concat(
          [("Fable", 46, "ok"), ("Opus", 8, "red"), ("Sonnet", 100, "ok")].iter().take(fx.own).map(fn(m) {
            obj([("label", str("每周 · " + m.0)), ("usedPercent", Json::number((100 - m.1).to_double())), ("scope", str(m.0)), ("mark", str(m.0)), ("left", Json::number(m.1.to_double())), ("level", str(m.2)), ("refills", str("2 天 4 小时后刷新"))])
          }),
        ).collect()),
      ),
      ..(if id == "cc" { fx_cc_resets() } else { [] }),
      ("checkedAt", Json::number(0.0)),
      ("time", obj([("checkedAt", stamp_of("3 分钟前"))])),
    ]),
  }
  for kv in more {
    p[kv.0] = kv.1
  }
  // (the core's words of it: present.ts profile, as it is after `more`)
  let pv = Some(Json::object(p))
  if !p.contains("kindText") {
    p["kindText"] = str(
      if flag(pv, "machine") {
        "终端里的登录"
      } else if text(pv, "providerName") != "" {
        text(pv, "providerName")
      } else {
        match kind {
          "subscription" => "订阅账号"
          "anthropic-api" => "Anthropic API"
          "opencode-go" => "OpenCode Go"
          "api-provider" => "API 服务商"
          "env" => "自定义环境变量"
          _ => ""
        }
      },
    )
  }
  p["checkLine"] = str(
    if has(pv, "enabled") && !flag(pv, "enabled") { "" } else { match field(pv, "check") {
      Some(Object(_)) => text(field(pv, "check"), "detail").replace(old="可用，", new="")
      _ => "尚未检查"
    } },
  )
  Json::object(p)
}

///|
/// The made-up station's profiles (Willow's), for the chats' fixture's overview of it too: one made-up world.
pub fn fixture_profiles() -> Array[Json] {
  fx_profiles()
}

///|
fn fx_profiles() -> Array[Json] {
  let profiles = [
    fx_profile("cc", "Claude 主账号", "subscription", fx_cc_tone(), "可用", "claude", "Claude 订阅", fx_cc_with([
      ("share", obj([("id", str("sh1")), ("role", str("host")), ("host", str("st1")), ("users", ["st2"])])),
      ("fast", Json::boolean(false)),
      ("backgroundOnMessage", Json::boolean(true)),
      ("workspaces", ["ws2"]),
      ("loginCommand", str("claude setup-token")),
      (
        "login",
        match fx.login {
          "" => Json::null()
          "failed" =>
            obj([
              ("profile", str("cc")),
              ("runtime", str("claude")),
              ("state", str("failed")),
              ("error", str("授权码已过期")),
              ("startedAt", Json::number(0.0)),
              ("expiresAt", Json::number(0.0)),
            ])
          state => fx_login_job("cc", state)
        },
      ),
    ])),
    fx_profile("cx", "ChatGPT 团队", "subscription", "green", "可用", "chatgpt", "ChatGPT 订阅", fx_cx_more()),
    fx_profile("k2", "备用 key", "anthropic-api", if fx.key_enabled { "red" } else { "neutral" }, if fx.key_enabled { "没能使用" } else { "已停用" }, "key", "API key", [
      ("enabled", Json::boolean(fx.key_enabled)),
      // (as the core says it: present.ts issue, trouble.key_next, trouble.key_label)
      ("trouble", if fx.key_enabled { obj([("title", str("key 已失效")), ("detail", str("服务商拒绝了这个 key")), ("next", str("核对服务商的 key 是否有效、余额和权限是否足够；可以更换 key，保存后会自动检查")), ("action", str("key")), ("label", str("更换 key"))]) } else { Json::null() }),
      ("quota", obj([("state", str("unsupported")), ("windows", []), ("checkedAt", Json::number(0.0))])),
      ("usedBy", []),
    ]),
  ]
  if fx.copy_shown {
    // Maple's Claude subscription borrowed here (share role user): its station pauses it (`enabled`), edits nothing else.
    profiles.push(
      fx_profile("bx", "maple@example.com", "subscription", if fx.copy_enabled { "green" } else { "neutral" }, if fx.copy_enabled { "可用" } else { "已停用" }, "claude", "Claude 订阅", [
        ("email", str("maple@example.com")),
        ("share", obj([("id", str("sh2")), ("role", str("user")), ("host", str("st2")), ("allow", Json::null()), ("reachable", Json::boolean(true)), ("pausable", Json::boolean(true))])),
        ("enabled", Json::boolean(fx.copy_enabled)),
        ("usedBy", []),
      ]),
    )
  }
  if fx.several {
    fx_several(profiles)
  }
  profiles
}

///|
/// The offered login's allowance (settings-profiles-offer): the figures of the fixture's own Claude subscription,
/// as the Mac's text has them.
fn fx_offer_quota() -> Json {
  obj([
    ("state", str("ok")),
    ("windows", [
      obj([("label", str("5 小时")), ("usedPercent", Json::number(38.0)), ("mark", str("5H")), ("left", Json::number(62.0)), ("level", str("ok")), ("refills", str("4 小时后恢复"))]),
      obj([("label", str("本周")), ("usedPercent", Json::number(81.0)), ("mark", str("W")), ("left", Json::number(19.0)), ("level", str("ok")), ("refills", str("星期一恢复"))]),
    ]),
    ("checkedAt", Json::number(0.0)),
  ])
}

///|
/// The Claude subscription five accounts (settings-profiles-several): the first of them its own (cc), the rest copies,
/// each by its e-mail with what is left of its windows by mark (Fable's a model's own week).
fn fx_several(profiles : Array[Json]) -> Unit {
  let accounts : Array[Array[(String, Int)]] = [
    [("5H", 26), ("W", 17), ("Fable", 52)],
    [("5H", 0), ("W", 13), ("Fable", 74)],
    [("W", 0), ("Fable", 100)],
    [("W", 48), ("Fable", 26)],
    [("5H", 0), ("W", 5), ("Fable", 70)],
  ]
  guard profiles[0] is Object(cc) else { return }
  for i, windows in accounts {
    let p = cc.copy()
    if i > 0 {
      p["id"] = str("claude-" + (i + 1).to_string())
    }
    p["name"] = str("claude" + (i + 1).to_string() + "@example.com")
    p["quota"] = obj([
      ("state", str("ok")),
      (
        "windows",
        Json::array(
          windows.map(fn(w) {
            let (mark, left) = w
            let level = if left <= 10 { "red" } else if left <= 20 { "amber" } else { "ok" }
            let (label, refills) = match mark {
              "5H" => ("5 小时", "3 小时 5 分钟后刷新")
              "W" => ("每周", "2 天 4 小时后刷新")
              _ => ("每周 · " + mark, "2 天 4 小时后刷新")
            }
            let fields = [
              ("label", str(label)),
              ("usedPercent", Json::number((100 - left).to_double())),
              ("mark", str(mark)),
              ("left", Json::number(left.to_double())),
              ("level", str(level)),
              ("refills", str(refills)),
            ]
            if mark == "Fable" {
              fields.push(("scope", str(mark)))
            }
            obj(fields)
          }),
        ),
      ),
      ("checkedAt", Json::number(0.0)),
      ("time", obj([("checkedAt", stamp_of("3 分钟前"))])),
    ])
    if i == 0 {
      profiles[0] = Json::object(p)
    } else {
      profiles.insert(i, Json::object(p))
    }
  }
}

///|
/// The station overview's accounts: the long case has nine Claude and three ChatGPT accounts.
fn fx_station_profiles() -> Array[Json] {
  let profiles = fx_profiles()
  if fx_station_many_profiles.val {
    for i in 1..<9 {
      match profiles[0] {
        Object(p) => {
          let copy = p.copy()
          copy["id"] = str("claude-" + i.to_string())
          copy["name"] = str("claude" + i.to_string() + "@example.com")
          let hours = 90 - i * 7
          let week = 92 - i * 10
          copy["quota"] = obj([
            ("state", str("ok")),
            ("windows", [
              obj([("label", str("5 小时")), ("usedPercent", Json::number((100 - hours).to_double())), ("mark", str("5H")), ("left", Json::number(hours.to_double())), ("level", str(if hours <= 20 { "amber" } else { "ok" })), ("refills", str("2 小时后恢复"))]),
              obj([("label", str("本周")), ("usedPercent", Json::number((100 - week).to_double())), ("mark", str("W")), ("left", Json::number(week.to_double())), ("level", str(if week <= 20 { "amber" } else { "ok" })), ("refills", str("星期一恢复"))]),
            ]),
            ("checkedAt", Json::number(0.0)),
          ])
          profiles.push(Json::object(copy))
        }
        _ => ()
      }
    }
    for i in 1..<3 {
      match profiles[1] {
        Object(p) => {
          let copy = p.copy()
          copy["id"] = str("chatgpt-" + i.to_string())
          copy["name"] = str("chatgpt" + i.to_string() + "@example.com")
          profiles.push(Json::object(copy))
        }
        _ => ()
      }
    }
  }
  profiles
}

///|
/// Its account kinds and states, in the same shapes as the core's station view.
fn fx_station_profile_groups(profiles : Array[Json]) -> Array[Json] {
  let groups : Array[(String, String, Array[String], Array[String])] = []
  for p in profiles {
    let pv = Some(p)
    let kind = text(pv, "group")
    let at = match groups.search_by(fn(g) { g.0 == kind }) {
      Some(i) => i
      None => {
        groups.push((kind, text(pv, "groupTitle"), [], []))
        groups.length() - 1
      }
    }
    if field(pv, "trouble") is Some(Object(_)) {
      groups[at].2.push(text(pv, "id"))
    } else {
      groups[at].3.push(text(pv, "id"))
    }
  }
  groups.map(fn(g) {
    obj([
      ("group", str(g.0)), ("title", str(g.1)),
      ("profiles", Json::array(g.2.iter().concat(g.3.iter()).map(fn(id) { str(id) }).collect())),
      ("attention", Json::number(g.2.length().to_double())),
    ])
  })
}

///|
fn fx_station_profile_states(profiles : Array[Json]) -> Json {
  let states : Map[String, Json] = Map([])
  for p in profiles {
    let pv = Some(p)
    let trouble = field(pv, "trouble")
    let green = text(pv, "checkTone") == "green"
    if trouble is Some(Object(_)) && green {
      states[text(pv, "id")] = obj([("text", str(text(trouble, "title"))), ("tone", str("amber"))])
    } else if !green && text(pv, "checkText") != "" {
      states[text(pv, "id")] = obj([("text", str(text(pv, "checkText"))), ("tone", str(text(pv, "checkTone")))])
    }
  }
  Json::object(states)
}

///|
/// The profiles of one account: independently signed in on three stations and also borrowed on three.
fn fx_profile_hosts() -> Array[Json] {
  let profile_host = fn(station : String, name : String, id : String, role : String, title : String, about : String) -> Json {
    obj([
      ("station", str("ws1/" + station)), ("stationId", str(station)), ("stationName", str(name)),
      ("profileId", str(id)), ("profileName", str(id)), ("role", str(role)), ("title", str(title)),
      ("about", str(about)), ("online", Json::boolean(true)), ("usable", Json::boolean(true)),
      ("checkText", str("可用")), ("checkTone", str("green")), ("usedBy", Json::number(0.0)),
    ])
  }
  let members = [
    profile_host("st1", "Willow", "cc", "host", "Willow", "在此 station 登录，借给 Maple、Cedar、Birch"),
    profile_host("st2", "Maple", "sh1", "user", "Maple", "向 Willow 借用"),
    profile_host("st3", "Cedar", "local", "own", "Cedar", "在此 station 单独登录"),
    profile_host("st3", "Cedar", "sh1", "user", "Cedar", "向 Willow 借用"),
    profile_host("st4", "Birch", "local", "own", "Birch", "在此 station 单独登录"),
    profile_host("st4", "Birch", "sh1", "user", "Birch", "向 Willow 借用"),
  ]
  if fx.profile_one_owner {
    return [members[0], members[1]]
  }
  members
}

///|
/// The same account by station, as the core's places says it.
fn fx_profile_places() -> Array[Json] {
  let members = fx_profile_hosts()
  let chosen = if fx.profile_one_owner { members } else { [members[0], members[1], members[2], members[4]] }
  chosen.map(fn(m) {
    let v = Some(m)
    let offline = fx.profile_away && text(v, "stationId") == "st4"
    let unavailable = fx.profile_away && text(v, "stationId") == "st2"
    let pending = fx.profile_pending && text(v, "stationId") == "st2"
    obj([
      ("station", str(text(v, "station"))), ("stationId", str(text(v, "stationId"))),
      ("stationName", str(text(v, "stationName"))), ("profileId", str(if pending { "" } else { text(v, "profileId") })),
      ("online", Json::boolean(!offline)), ("usable", Json::boolean(!offline && !unavailable && !pending)),
      ("sourceName", str(if unavailable || pending { "Willow" } else { "" })),
      ("state", if pending && fx.profile_cut_off {
        obj([("text", str("无法连接 still.fail cloud")), ("tone", str("amber"))])
      } else if pending {
        obj([("text", str("等待同步")), ("tone", str("neutral"))])
      } else {
        Json::null()
      }),
    ])
  })
}

///|
/// Claude 主账号's dot as its trouble has it (fx.trouble).
fn fx_cc_tone() -> String {
  match fx.trouble {
    "login" | "blocked" => "red"
    _ => "green"
  }
}

///|
/// Claude 主账号's own (`more`) and its trouble (fx.trouble) as the core says it (present.ts profileTrouble), with what
/// its check and its allowance say then.
fn fx_cc_with(more : Array[(String, Json)]) -> Array[(String, Json)] {
  let issue = fn(title : String, detail : String, next : String, action : String, label : String) {
    ("trouble", obj([("title", str(title)), ("detail", str(detail)), ("next", str(next)), ("action", str(action)), ("label", str(label))]))
  }
  more..append(match fx.trouble {
    "quota" =>
      [
        issue("额度查询失败", "请求超时，已中止", "查不到额度不代表账号不能用。先重新查询；还是失败，再按返回的原因检查登录或网络。", "quota", "重新查询额度"),
        ("quota", obj([("state", str("unavailable")), ("detail", str("请求超时，已中止")), ("windows", []), ("checkedAt", Json::number(0.0))])),
      ]
    "blocked" =>
      [
        issue("额度已用完", "本周额度已用完", "等额度恢复，或换一个账号。", "quota", "重新查询额度"),
        ("quota", obj([("state", str("blocked")), ("detail", str("本周额度已用完")), ("windows", []), ("checkedAt", Json::number(0.0))])),
      ]
    "login" =>
      [
        issue("需要重新登录", "登录已过期", "", "login", "登录"),
        ("check", obj([("state", str("login")), ("detail", str("登录已过期")), ("checkedAt", Json::number(0.0)), ("time", obj([("checkedAt", stamp_of("5 分钟前"))]))])),
        ("checkText", str("需要登录")),
      ]
    _ => []
  })
}

///|
/// ChatGPT 团队's resets left, in the core's words.
fn fx_cx_reset_text(left : Int) -> String {
  if fx.reset_expiry {
    if left == 2 { "剩余 2 次 · 6 小时 35 分钟后、3 天 19 小时后到期" } else if left == 1 { "剩余 1 次 · 3 天 19 小时后到期" } else { "剩余 0 次" }
  } else {
    "还可重置 \{left} 次"
  }
}

///|
/// Claude 主账号's resets of two kinds, as the core offers them (settings-profile-quota-kinds).
fn fx_cc_resets() -> Array[(String, Json)] {
  if !fx.reset_kinds {
    return []
  }
  let kinds = [
    obj([
      ("id", str("session")),
      ("kind", str("session")),
      ("left", Json::number(1.0)),
      ("usable", Json::boolean(false)),
      ("title", str("5 小时重置")),
      ("leftText", str("剩 1 次")),
      ("text", str("到达它能恢复的上限后才能用")),
      ("refills", str("立即恢复 5 小时额度")),
    ]),
  ]
  if !fx.fable_used {
    kinds.push(
      obj([
        ("id", str("model")),
        ("kind", str("model")),
        ("left", Json::number(1.0)),
        ("usable", Json::boolean(true)),
        ("title", str("Fable 重置")),
        ("leftText", str("剩 1 次")),
        ("text", str("118 天后到期")),
        ("refills", str("把本周 Fable 用掉的额度还回每周额度")),
      ]),
    )
  }
  [("resetCount", Json::number(kinds.length().to_double())), ("resets", Json::array(kinds))]
}

///|
/// ChatGPT 团队's own: more models than its page shows at first (one named by hand once added, which can be taken off
/// again), a reset of its quota left.
fn fx_cx_more() -> Array[(String, Json)] {
  let ids = [
    "gpt-6", "gpt-6-mini", "gpt-6-nano", "gpt-6-codex", "gpt-6-codex-mini", "gpt-5.5", "gpt-5.5-mini", "gpt-5.5-codex", "gpt-5",
    "gpt-5-mini", "o9", "o9-mini",
  ]..append(fx.models_added)
  let names : Map[String, Json] = Map([])
  for m in ids {
    names[m] = str(m.to_upper())
  }
  let left = 2 - fx.resets_used
  [
    ("modelsText", str("\{ids.length()} 个模型")),
    ("models", Json::array(ids.map(str))),
    ("named", Json::array(fx.models_added.map(str))),
    ("added", Json::array(fx.models_added.map(str))),
    ("available", Json::array(ids.map(str))),
    ("names", Json::object(names)),
    ("series", fx_cx_series(ids)),
    ("canAddModel", Json::boolean(true)),
    (
      "quota",
      obj([
        ("state", str("ok")),
        (
          "windows",
          [
            obj([("label", str("5 小时")), ("usedPercent", Json::number(38.0)), ("mark", str("5H")), ("left", Json::number(62.0)), ("level", str("ok")), ("refills", str("2 小时后恢复"))]),
            obj([("label", str("本周")), ("usedPercent", Json::number(81.0)), ("mark", str("W")), ("left", Json::number(19.0)), ("level", str("amber")), ("refills", str("星期一恢复"))]),
          ],
        ),
        ("resetCount", Json::number(left.to_double())),
        ("resetText", str(fx_cx_reset_text(left))),
        // (one kind, which says nothing of what it gives back: as the core offers it, with no kind to ask for)
        ("resets", if left > 0 {
          [
            obj([
              ("kind", str("credit")),
              ("left", Json::number(left.to_double())),
              ("usable", Json::boolean(true)),
              ("title", str("额度重置")),
              ("leftText", str("剩 \{left} 次")),
              ("text", str(if fx.reset_expiry { if left == 2 { "6 小时 35 分钟后、3 天 19 小时后到期" } else { "3 天 19 小时后到期" } } else { "" })),
            ]),
          ]
        } else {
          []
        }),
        ("checkedAt", Json::number(0.0)),
        ("time", obj([("checkedAt", stamp_of("3 分钟前"))])),
      ]),
    ),
  ]..append(if fx.trouble == "quota-login" {
    [
      ("trouble", obj([("title", str("需要登录")), ("detail", str("ChatGPT 登录已失效，请重新登录")), ("next", str("重新登录此账号")), ("action", str("login")), ("label", str("重新登录"))])),
      ("quota", obj([("state", str("unavailable")), ("detail", str("ChatGPT 登录已失效，请重新登录")), ("windows", []), ("checkedAt", Json::number(0.0))])),
      ("check", obj([("state", str("login")), ("detail", str("ChatGPT 登录已失效，请重新登录")), ("checkedAt", Json::number(0.0)), ("time", obj([("checkedAt", stamp_of("3 分钟前"))]))])),
      ("checkText", str("需要登录")),
      ("checkTone", str("amber")),
      ("login", if fx.login == "" { Json::null() } else { fx_login_job("cx", fx.login) }),
    ]
  } else {
    []
  })
}

///|
/// Its models by series, as the core gives them (newest first, one named by hand under 其他).
fn fx_cx_series(ids : Array[String]) -> Json {
  let series = [
    ("GPT-6", ["gpt-6", "gpt-6-mini", "gpt-6-nano", "gpt-6-codex", "gpt-6-codex-mini"]),
    ("GPT-5.5", ["gpt-5.5", "gpt-5.5-mini", "gpt-5.5-codex"]),
    ("GPT-5", ["gpt-5", "gpt-5-mini"]),
    ("o9", ["o9", "o9-mini"]),
  ]
  let rest = ids.filter(fn(m) { !series.iter().any(fn(s) { s.1.contains(m) }) })
  let all = series.map(fn(s) { obj([("name", str(s.0)), ("models", Json::array(s.1.map(str)))]) })
  if rest.length() > 0 {
    all.push(obj([("name", str("其他")), ("models", Json::array(rest.map(str)))]))
  }
  Json::array(all)
}

///|
fn fx_connect(id : String, name : String, presence : String, status : String, mode : String) -> Json {
  obj([
    ("id", str(id)),
    ("name", str(name)),
    ("team", str("星火")),
    ..(if fx_connects_waiting.val && id == "k1" {
      [("botImage", str("https://app.still.fail/avatars/backend.webp"))]
    } else {
      []
    }),
    ("enabled", Json::boolean(true)),
    ("kind", str("slack")),
    ("mode", str(mode)),
    ("requireMention", Json::boolean(true)),
    ("bind", obj([("runtime", str("claude")), ("model", str("claude-opus-5-5")), ("effort", str("high"))])),
    ("slack", obj([("appToken", str("")), ("botToken", str(""))])),
    ("connection", obj([("state", str(if presence == "error" { "error" } else { "connected" })), ("error", str("Slack 拒绝了 token"))])),
    ("createdBy", obj([("id", str("lin@example.com")), ("name", str("林")), ("shown", obj([("name", str("林")), ("display", str("你")), ("mine", Json::boolean(true))]))])),
    ("sessions", Json::number(4.0)),
    // (a station that runs its new conversations elsewhere and moves it: connects/workspace.ts)
    ("startsOn", Json::null()),
    ("moves", Json::boolean(true)),
    ("statusText", str(status)),
    ("presence", str(presence)),
    ("modeText", str(if mode == "multi-session" { "每个 thread 一个会话" } else { "所有 thread 共用一个会话" })),
    ("modeShort", str("")),
    ("runtimeText", str("Claude Code")),
    ("runText", str("")),
    ("modelName", str("Opus 5.5")),
    // (the core's words of it: present.ts connect)
    ("placeText", str("星火")),
    ("modeLabel", str(if mode == "multi-session" { "每个 thread 一个会话" } else { "所有 thread 共用一个会话" })),
    (
      "modeSentence",
      str(
        if mode == "multi-session" {
          "在 thread 中 @ 它即开启一个新会话，该 thread 的后续消息都进入此会话"
        } else {
          "它看到的所有 thread 都进入同一个会话，适合长期值守的助手仅在被 @ 时唤醒。"
        },
      ),
    ),
    ("modeWords", fx_mode_words(false)),
  ])
}

///|
/// Connect k1 as one of another kind (MBUI_FIXTURE=settings-connect-comma, -feishu): Comma's, reached in Comma and
/// running a session a Task; Feishu's, its app on 飞书. No Slack workspace either, so no team.
fn fx_connect_as(kind : String) -> Json {
  let feishu = kind == "feishu"
  match fx_connect("k1", if feishu { "飞书助手" } else { "Comma 助手" }, "online", "在线", "multi-session") {
    Object(o) => {
      o["kind"] = str(kind)
      o.remove("team")
      o.remove("slack")
      o["sessions"] = Json::number(0.0)
      o["placeText"] = str(if feishu { "飞书" } else { "Comma" })
      if feishu {
        o["feishu"] = obj([
          ("appId", str("cli_a7f3e9b2c41d500e")),
          ("appSecret", str("…9c2b")),
          ("domain", str("feishu")),
          ("console", str("https://open.feishu.cn/app/cli_a7f3e9b2c41d500e")),
        ])
        o["modeWords"] = fx_mode_words(true)
        o["modeText"] = str("每个群一个会话")
        o["modeLabel"] = str("每个群一个会话")
        o["modeSentence"] = str("在群里 @ 它开始，之后群里的消息都交给这个会话；@ 它说「新会话」另开一个，话题群的每个话题各一个会话")
      }
      Json::object(o)
    }
    v => v
  }
}

///|
/// A new connect on Comma's path at its model (MBUI_FIXTURE=settings-new-connect-comma): step 2 of 3, a model picked.
fn fx_comma_flow() -> Json {
  obj([
    ("step", str("commaBind")),
    ("title", str("绑定模型")),
    ("back", str("platform")),
    ("number", Json::number(2.0)),
    ("total", Json::number(3.0)),
    ("mobile", Json::boolean(true)),
    ("platforms", [str("slack"), str("feishu"), str("comma")]),
    ("platform", str("comma")),
    ("comma", obj([("line", str("")), ("ready", Json::boolean(false)), ("error", Json::null())])),
    ("mode", str("multi-session")),
    ("requireMention", Json::boolean(true)),
    ("threads", Json::boolean(false)),
    ("modeWords", fx_mode_words(false)),
    ("noProfile", Json::boolean(false)),
    ("canCreate", Json::boolean(true)),
    ("pick", fx_session_pick()),
  ])
}

///|
/// How a connect's ways are said, as the core says them (present.ts modeWords): a Feishu one's in its groups' words.
fn fx_mode_words(feishu : Bool) -> Json {
  if feishu {
    obj([
      ("multi", obj([("label", str("每个群一个会话")), ("description", str("在群里 @ 它开始，之后群里的消息都交给这个会话；@ 它说「新会话」另开一个，话题群的每个话题各一个会话"))])),
      ("threads", obj([("label", str("每个 thread 一个会话")), ("description", str("在群里 @ 它就开一个 thread，回复都留在 thread 里；每个 thread 一个会话，thread 里的后续消息无需再 @"))])),
      ("single", obj([("label", str("所有群共用一个会话")), ("description", str("它所在的群和私聊都进入同一个会话，适合长期值守的助手"))])),
      ("mentionOn", str("被 @ 后，同一个群里的后续消息无需再 @。")),
      ("mentionOff", str("它所在的群里的每条消息都会进入会话。")),
    ])
  } else {
    obj([
      ("multi", obj([("label", str("每个 thread 一个会话")), ("description", str("在 thread 中 @ 它即开启一个新会话，该 thread 的后续消息都进入此会话"))])),
      ("single", obj([("label", str("所有 thread 共用一个会话")), ("description", str("它看到的所有 thread 都进入同一个会话，适合长期值守的助手"))])),
      ("mentionOn", str("被 @ 的 thread 中，后续回复无需再 @。")),
      ("mentionOff", str("频道中它可见的每条消息都会进入会话。")),
    ])
  }
}

///|
/// A Slack app's permissions as the core says them (present.ts slackSections).
fn fx_sections() -> Json {
  [
    obj([
      ("title", str("消息")),
      (
        "groups",
        [
          fx_group("base", "读取和回复消息", "", fixed=true),
          fx_group("public", "在未加入的公开频道发言", ""),
          fx_group("dm", "主动发私信", ""),
          fx_group("customize", "使用自定义名称和头像发消息", ""),
          fx_group("reactions", "表情回应、置顶和书签", ""),
        ],
      ),
    ]),
    obj([
      ("title", str("频道和群")),
      (
        "groups",
        [
          fx_group("channels", "创建和管理频道", ""),
          fx_group("topics", "修改频道话题和邀请成员", ""),
          fx_group("connect", "Slack Connect 跨组织频道", "接受邀请需要由能批准 Slack Connect 的人（默认为管理员）安装 app；发送邀请也受工作区设置限制，且仅限付费版"),
        ],
      ),
    ]),
    obj([
      ("title", str("文件和文档")),
      (
        "groups",
        [
          fx_group("files", "读写文件", ""),
          fx_group("canvases", "读写 canvas", ""),
          fx_group("lists", "读写列表", ""),
        ],
      ),
    ]),
    obj([
      ("title", str("成员和搜索")),
      (
        "groups",
        [
          fx_group("people", "查看成员资料", ""),
          fx_group("usergroups", "管理用户组和发起通话", "创建用户组、修改成员需要工作区设置允许，很多工作区仅限管理员；用户组仅限付费版"),
          fx_group("search", "搜索消息、文件和成员", ""),
        ],
      ),
    ]),
    obj([
      ("title", str("其他")),
      (
        "groups",
        [
          fx_group("extras", "链接预览、提醒和状态", ""),
          fx_group("more", "状态、元数据和斜杠命令", ""),
        ],
      ),
    ]),
  ]
}

///|
/// A group of a Slack app's permissions, as the core says it (`admin`: what only Slack's admins allow, "" none).
fn fx_group(id : String, label : String, admin : String, fixed? : Bool = false) -> Json {
  obj([
    ("id", str(id)),
    ("label", str(label)),
    ("description", str(label)),
    ("admin", if admin == "" { Json::null() } else { str(admin) }),
    ("tip", str(if admin == "" { label } else { label + " " + admin })),
    ("fixed", Json::boolean(fixed)),
  ])
}

///|
/// The ways a multi-session connect could be switched to, as the core says them (present.ts modeChanges).
fn fx_mode_changes() -> Json {
  let change = fn(mode : String, mention : Bool, changed : Bool, effects : Array[String], action : String) {
    obj([
      ("mode", str(mode)),
      ("requireMention", Json::boolean(mention)),
      ("changed", Json::boolean(changed)),
      ("effects", Json::array(effects.map(str))),
      ("action", str(action)),
    ])
  }
  let single = "此后它收到的消息都将进入同一个会话；现有各 thread 的会话不再接收新消息，包括这些 thread 中的回复。记录会保留。"
  let fresh = "下一条消息将开始新的单会话；也可在切换后选择已有会话。"
  Json::array([
    change("multi-session", true, false, [], "确认更改"),
    change("single-session", true, true, [single, fresh], "改为单会话"),
    change("single-session", false, true, [single, fresh, "无需 @：它可见的所有频道和私信中的每条消息都会发送给 agent，用量会明显增加。"], "改为单会话"),
  ])
}

///|
fn fx_station(address : String) -> Json {
  let id = station_name(address)
  let renamed = fx.names.get(id)
  if address == "ws1/st1" {
    let profiles = fx_station_profiles()
    obj([
      ("station", str(address)),
      ("id", str(id)),
      ("name", str(renamed.unwrap_or("Willow"))),
      ("icon", str(fx.marks.get(id).unwrap_or("glyph:desktop"))),
      ("summary", str(if fx.willow_incompatible { "版本不兼容，需要更新" } else if fx.gpus { "AMD EPYC · 2 个 agent 在工作" } else { "Apple M1 Pro · 2 个 agent 在工作" })),
      ("face", str("working")),
      ("line", str(if fx.willow_incompatible { "版本不兼容，需要更新" } else if fx.gpus { "AMD EPYC · 32 GB · Linux" } else { "Apple M1 Pro · 32 GB · macOS 26" })),
      ("online", Json::boolean(!fx.willow_away)),
      // the viewer added it: its mode theirs to change (the core's `mine`)
      ("mine", Json::boolean(!fx.willow_theirs)),
      ("profileGroups", Json::array(fx_station_profile_groups(profiles))),
      ("profileStates", fx_station_profile_states(profiles)),
      ("link", obj([("state", str(if fx.willow_away { "offline" } else { "online" }))])),
      ("stateText", str(if fx.willow_away { "2 天前在线" } else { "" })),
      (
        "problems",
        if fx.willow_incompatible {
          [obj([("key", str("incompatible")), ("level", str("amber")), ("text", str("版本不兼容：这台 station 和这个 still.fail 的版本不匹配，部分信息无法显示。请更新 still.fail 和这台 station。"))])]
        } else if fx.willow_away {
          [obj([("key", str("away")), ("level", str("red")), ("text", str("离线：在该机器上打开 still.fail 即可重新连接"))])]
        } else {
          []
        },
      ),
      // the runtimes it runs, each with its models (its page's: the connect page asks whether one runs on its runtime)
      ("runtimes", [obj([("runtime", str("claude")), ("models", [str("claude-opus-5-5"), str("claude-sonnet-5")])])]),
      // what its profiles have turned on (Claude 主账号's: Opus 5.5 and Sonnet 5, on claude)
      (
        "models",
        [
          obj([("model", str("claude-opus-5-5")), ("name", str("Opus 5.5")), ("family", str("Opus")), ("maker", obj([("id", str("anthropic"))])), ("runtimes", ["claude"])]),
          obj([("model", str("claude-sonnet-5")), ("name", str("Sonnet 5")), ("family", str("Sonnet")), ("maker", obj([("id", str("anthropic"))])), ("runtimes", ["claude"])]),
        ],
      ),
      (
        "host",
        if fx.willow_incompatible {
          Json::null()
        } else {
        obj([
          ("identity", str(if fx.gpus { "AMD EPYC · 32 GB · Linux" } else { "Apple M1 Pro · 32 GB · macOS 26" })),
          ("gpus", if fx.gpus {
            let cards : Array[Json] = [
              obj([("big", str("63")), ("unit", str("%")), ("left", Json::number(63.0)), ("level", str("ok")), ("title", str("GPU 1 空闲率")), ("total", str("显存剩 20/24G")), ("model", str("NVIDIA GeForce RTX 4090"))]),
              obj([("big", str("100")), ("unit", str("%")), ("left", Json::number(100.0)), ("level", str("ok")), ("title", str("GPU 2 空闲率")), ("total", str("显存剩 23/24G")), ("model", str("NVIDIA GeForce RTX 4090"))]),
            ]
            if fx.more_gpus {
              cards.push(obj([("big", str("50")), ("unit", str("%")), ("left", Json::number(50.0)), ("level", str("ok")), ("title", str("GPU 3 空闲率")), ("total", str("显存剩 12/24G")), ("model", str("NVIDIA GeForce RTX 4090"))]))
              cards.push(obj([("big", str("20")), ("unit", str("%")), ("left", Json::number(20.0)), ("level", str("amber")), ("title", str("GPU 4 空闲率")), ("total", str("显存剩 5/24G")), ("model", str("NVIDIA GeForce RTX 4090"))]))
            }
            Json::array(cards)
          } else { [] }),
          (
            "meters",
            [
              meter("CPU", if fx.low_meters { 8 } else { 72 }, if fx.low_meters { "red" } else { "ok" }, if fx.low_meters { "空闲 8%" } else { "空闲 72%" }, if fx.low_meters { "8" } else { "72" }, "%", "CPU 空闲率", "负载 1.4", title_short="CPU 空闲"),
              meter("内存", 18, "amber", "剩 5.8 G", "5.8", "GB", "可用内存", "总内存 32 GB", total_short="总 32 GB"),
              if fx.low_meters {
                meter("磁盘", 9, "amber", "剩 19.4 G", "19.4", "GB", "可用磁盘", "总磁盘 1 TB", total_short="总 1 TB")
              } else {
                meter("磁盘", 42, "ok", "剩 420 G", "420", "GB", "可用磁盘", "总磁盘 1 TB", total_short="总 1 TB")
              },
            ],
          ),
          (
            "details",
            [
              obj([("label", str("主机名")), ("value", str("willow"))]),
              obj([("label", str("芯片")), ("value", str("Apple M1 Pro，10 核"))]),
              obj([("label", str("已运行")), ("value", str("6 天 4 小时"))]),
              obj([("label", str("进程")), ("value", str("station 412 MB"))]),
            ],
          ),
        ])
        },
      ),
      (
        "net",
        obj([
          ("path", str("直连")),
          ("via", str("direct")),
          ("rtt", obj([("text", str("38 ms")), ("level", str("ok"))])),
          ("rttHistory", []),
          ("down", str("1.4 MB/s")),
          ("up", str("96 KB/s")),
          ("total", str("")),
          ("downTotal", str("212 MB")),
          ("upTotal", str("9.6 MB")),
        ]),
      ),
      (
        "overview",
        obj([
          ("connects", [fx_connect("k1", "星火助手", "online", "在线", "multi-session")]),
          ("profiles", Json::array(profiles)),
          // a new profile's sign-in under way (settings-new-profile-login…)
          ("logins", if fx.new_login { [obj([("id", str("login-new")), ("runtime", str("claude")), ("job", fx_login_job("login-new", "needs_code"))])] } else { [] }),
          ("processesText", str("2 个 agent 进程 · claude 1.2 GB")),
          (
            "slackApps",
            if fx_connects_waiting.val {
              [
                obj([
                  ("appId", str("A07GEMINI01")),
                  ("name", str("Gemini-Monoid")),
                  ("teamId", str("T04ACME0001")),
                  ("team", str("星火")),
                  ("installed", Json::boolean(false)),
                  ("install", str("https://slack.com/oauth/v2/authorize?client_id=1")),
                ]),
              ]
            } else {
              []
            },
          ),
          ("drive", obj([("roots", [{ "path": "~/项目", "name": "项目", "state": "ok" }, { "path": "~/文档", "name": "文档", "state": "ok" }]), ("all", Json::boolean(false))])),
          (
            "updates",
            [
              obj([
                ("id", str("station")),
                ("name", str("Station")),
                ("installed", Json::boolean(true)),
                ("version", str(if fx_station_updated.val { "0.1.1300" } else { "0.1.1288" })),
                ("latest", str("0.1.1300")),
                ("newer", Json::boolean(!fx_station_updated.val)),
                ("channel", str("stable")),
                ("auto", Json::boolean(fx.auto)),
                ("updatable", Json::boolean(true)),
                ("state", str(if fx_station_update_failed.val { "failed" } else { "idle" })),
                ("failedText", str("更新失败")),
                ("message", str(if fx_station_update_failed.val { "无法读取 C:\\Users\\Willow\\.stillfail\\mesh\\cloud.json：文件可能已加密或损坏。请在文件加密软件中允许程序 C:\\Users\\Willow\\.stillfail\\app\\node\\node.exe 读取，或从备份恢复文件。" } else { "" })),
                ("checkedAt", Json::number(1.0)),
                ("done", str(if fx_station_updated.val { "已更新到 0.1.1300，agent 未中断" } else { "" })),
                // (the core's words of it: present.ts software)
                ("shownText", str(if fx_station_updated.val { "0.1.1300" } else { "0.1.1288" })),
                ("tipText", str("")),
              ]),
              obj([
                ("id", str("claude")),
                ("name", str("Claude Code")),
                ("installed", Json::boolean(true)),
                ("version", str("2.1.4")),
                ("latest", str("2.1.4")),
                ("newer", Json::boolean(false)),
                ("updatable", Json::boolean(true)),
                ("state", str("idle")),
                ("checkedAt", Json::number(1.0)),
                ("shownText", str("2.1.4")),
                ("tipText", str("已是最新")),
              ]),
              obj([
                ("id", str("codex")),
                ("name", str("Codex")),
                ("installed", Json::boolean(false)),
                ("newer", Json::boolean(false)),
                ("updatable", Json::boolean(true)),
                ("state", str("idle")),
                ("checkedAt", Json::number(1.0)),
                ("shownText", str("未安装")),
                ("tipText", str("")),
              ]),
            ],
          ),
          (
            "permissions",
            obj([
              (
                "grants",
                [
                  obj([("id", str("capture")), ("name", str("屏幕录制")), ("line", str("查看这台 Mac 的屏幕")), ("granted", Json::boolean(true)), ("asking", Json::boolean(false))]),
                  obj([("id", str("control")), ("name", str("辅助功能")), ("line", str("操作这台 Mac 的鼠标和键盘")), ("granted", Json::boolean(false)), ("asking", Json::boolean(false))]),
                  obj([("id", str("documents")), ("name", str("文稿")), ("line", str("读写「文稿」中的文件")), ("granted", Json::boolean(false)), ("asking", Json::boolean(true))]),
                ],
              ),
              ("note", str("未允许辅助功能：agent 只能查看屏幕，不能操作")),
              ("canRequest", Json::boolean(true)),
            ]),
          ),
          (
            "agentEnv",
            [
              obj([("key", str("HTTPS_PROXY")), ("secret", Json::boolean(false)), ("value", str("http://127.0.0.1:7890"))]),
              obj([("key", str("NO_PROXY")), ("secret", Json::boolean(false)), ("value", str("localhost,.internal"))]),
            ],
          ),
          ("search", obj([("files", str("spotlight")), ("personal", Json::boolean(false))])),
          ("context", obj([("afreshWhenCold", Json::boolean(fx.afresh)), ("afreshAbove", Json::number(fx.afresh_above))])),
          ("diagnostics", obj([("logs", Json::boolean(fx.logs))])),
          ("network", obj([("congestion", str(fx.congestion))])),
          ("elevation", fx.elevation.unwrap_or(Json::null())),
          ("copies", fx.copies.unwrap_or(Json::null())),
          ("sharing", Json::boolean(true)),
          (
            "machineLogins",
            [
              obj([("runtime", str("codex")), ("installed", Json::boolean(true)), ("loggedIn", Json::boolean(true)), ("email", str("lin@example.com")), ("plan", str("plus")), ("planText", str("Plus")), ("usable", Json::boolean(true)), ("text", str("")), ("offered", Json::boolean(true)),
                // (null where the fixture says none: a field left as it is, as field_made has it)
                ("quota", if fx.offer_quota { fx_offer_quota() } else { Json::null() }),
              ]),
            ],
          ),
          (
            "archiving",
            // (the core's words and choices)
            obj([
              ("days", Json::number(1.0)),
              ("slackDays", Json::number(3.0)),
              ("reviewed", Json::boolean(false)),
              ("canEdit", Json::boolean(true)),
              ("mode", str("idle")),
              ("summaryText", str("空闲就归档 · 1 天 · Slack：3 天")),
              ("daysOffered", [Json::number(1.0), Json::number(3.0), Json::number(7.0), Json::number(30.0)]),
              ("slackDaysOffered", [Json::number(0.0), Json::number(3.0), Json::number(7.0), Json::number(30.0)]),
              ("daysOfferedText", [str("1 天"), str("3 天"), str("7 天"), str("30 天")]),
              ("slackDaysOfferedText", [str("不归档"), str("3 天"), str("7 天"), str("30 天")]),
              ("reviewOn", Json::boolean(true)),
              ("reviewText", str("已开启 · GPT-6 mini")),
              ("stalled", Json::boolean(false)),
              ("lineText", str("空闲就归档 · 1 天 · Slack：3 天")),
              (
                "modes",
                [
                  obj([("mode", str("off")), ("label", str("不自动归档")), ("days", Json::number(0.0)), ("reviewed", Json::boolean(false)), ("allowed", Json::boolean(true))]),
                  obj([("mode", str("idle")), ("label", str("空闲就归档")), ("days", Json::number(1.0)), ("reviewed", Json::boolean(false)), ("allowed", Json::boolean(true))]),
                  obj([("mode", str("reviewed")), ("label", str("按模型判断")), ("days", Json::number(1.0)), ("reviewed", Json::boolean(true)), ("allowed", Json::boolean(true))]),
                ],
              ),
              ("modeNote", str("空闲超过下面的天数就归档。只看状态，不读内容：chat 里提到但没做完的事，它看不出来。")),
            ]),
          ),
          (
            "automaticDecisions",
            obj([
              ("canEdit", Json::boolean(true)),
              ("canReview", Json::boolean(true)),
              ("settings", obj([("completion", obj([("enabled", Json::boolean(true))]))])),
              ("models", [obj([("id", str("gpt-6-mini")), ("name", str("GPT-6 mini")), ("profiles", ["cx"])])]),
              ("recent", []),
              (
                "policy",
                obj([
                  ("text", str("做完、没有待办的对话归档；还在等人回复或有后续计划的留下。")),
                  (
                    "options",
                    [
                      obj([("id", str("o1")), ("name", str("已完成")), ("rubric", str("任务做完，没有后续")), ("archive", Json::boolean(true)), ("count", Json::number(12.0)), ("chats", [obj([("session", str("s-c3")), ("title", str("夜里的构建又失败了"))])])]),
                      obj([("id", str("o2")), ("name", str("被放弃")), ("rubric", str("明确不再继续")), ("archive", Json::boolean(true)), ("count", Json::number(3.0)), ("chats", [])]),
                      obj([("id", str("o3")), ("name", str("等回复")), ("rubric", str("在等某人的答复")), ("archive", Json::boolean(false)), ("count", Json::number(5.0)), ("chats", [])]),
                    ],
                  ),
                  ("days", Json::number(7.0)),
                  ("checked", Json::number(20.0)),
                  ("failed", Json::number(0.0)),
                  ("edited", Json::boolean(false)),
                  ("summaryText", str("近 7 天检查了 20 个对话")),
                  ("changeText", str("上次修改 3 天前")),
                ]),
              ),
            ]),
          ),
        ]),
      ),
      ("betaOffered", Json::boolean(true)),
    ])
  } else {
    obj([
      ("station", str(address)),
      ("id", str(id)),
      ("name", str(renamed.unwrap_or("Maple"))),
      ("icon", str(fx.marks.get(id).unwrap_or("glyph:laptop:teal"))),
      ("summary", str(if fx.mba_online { "Apple M3 · 空闲" } else { "离线 · 2 天前" })),
      ("face", str(if fx.mba_online { "idle" } else { "offline" })),
      ("online", Json::boolean(fx.mba_online)),
      ("link", obj([("state", str(if fx.mba_online { "online" } else { "offline" }))])),
      ("runtimes", []),
      ("models", []),
    ])
  }
}

///|
fn fx_archive() -> Json {
  let all = [
    ("a1", "整理上个月的发票", "已经把 23 张发票按月份归好", "14:05", "今天", true),
    ("a2", "试一下新的图标尺寸", "三种尺寸的对比图放在共享文件夹里", "11:30", "今天", true),
    ("a3", "周会纪要", "下周一前补上第三项的负责人", "18:20", "昨天", false),
    ("a4", "清理旧的构建缓存", "删掉了 41 GB 的旧缓存", "09:12", "星期三", true),
  ]
  let days : Array[(String, Array[Json])] = []
  for a in all {
    if fx.restored.contains("s-" + a.0) {
      continue
    }
    let row = obj([
      ("station", str("ws1/st1")),
      ("id", str(a.0)),
      ("session", str("s-" + a.0)),
      ("thread", Json::number(a.0.length().to_double())),
      ("title", str(a.1)),
      ("last", str(a.2)),
      ("at", Json::number(0.0)),
      ("clock", str(a.3)),
      ("how", str("手动归档")),
      ("deletable", Json::boolean(a.5)),
    ])
    match days.iter().find_first(fn(d) { d.0 == a.4 }) {
      Some(d) => d.1.push(row)
      None => days.push((a.4, [row]))
    }
  }
  obj([
    ("days", Json::array(days.map(fn(d) { obj([("label", str(d.0)), ("items", Json::array(d.1))]) }))),
    ("errors", []),
    ("wait", obj([("reading", Json::boolean(false)), ("failing", []), ("empty", Json::boolean(days.length() == 0))])),
    ("total", Json::number(days.length().to_double())),
    ("more", Json::boolean(false)),
  ])
}

///|
/// The list `only` (a key) is of ("" none).
fn only_shown_list(lists : Array[(String, String, Array[(String, String, String, String, Double)])], only : String) -> String {
  for l in lists {
    if l.2.search_by(fn(it) { it.0 == only }) is Some(_) {
      return l.0
    }
  }
  ""
}

///|
/// 用量's summary as the core says it (views/usage-summary.ts), its year from 2025-10-05: a workspace counted since March, most days busy
/// and weekends quieter, today Friday 10/2 (a Saturday after it).
fn fx_usage_summary() -> Json {
  let cells : Array[Json] = []
  let levels : Array[Int] = []
  for i in 0..<(52 * 7) {
    let week = i / 7
    let wd = i % 7
    let level = if i == 51 * 7 + 6 {
      -1
    } else if week < 22 {
      0
    } else {
      // (a made-up mix: weekdays busier, a quiet day now and then)
      let h = (i * 7919 + week * 104729 + wd * 31) % 997
      if wd == 0 || wd == 6 {
        h % 3
      } else {
        h % 5
      }
    }
    cells.push(Json::number(level.to_double()))
    levels.push(level)
  }
  // each day's date from 2025-10-05 (2026 no leap year), as the core says it under the pointer
  let lengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
  let date = fn(n : Int) {
    let mut m = 9
    let mut d = 5 + n
    while d > lengths[m] {
      d = d - lengths[m]
      m = (m + 1) % 12
    }
    "\{m + 1}月\{d}日"
  }
  let tips : Array[Json] = []
  let week_tips : Array[Json] = []
  let running_tips : Array[Json] = []
  for i, level in levels {
    tips.push(
      str(
        if level < 0 {
          ""
        } else if level == 0 {
          date(i) + " · 没有用 token"
        } else {
          date(i) + " · \{level * 1200} 万 token"
        },
      ),
    )
  }
  for w in 0..<52 {
    week_tips.push(str(date(w * 7) + "起一周 · " + (if w < 22 { "没有用 token" } else { "\{(w * 5 % 4) + 3} 千万 token" })))
    running_tips.push(str("截至" + date(@cmp.minimum(w * 7 + 6, 51 * 7 + 5)) + " · 共 \{w} 亿 token"))
  }
  let weekly : Array[Json] = []
  let cumulative : Array[Json] = []
  for w in 0..<52 {
    weekly.push(Json::number((if w < 22 { 0 } else { (w * 5 % 4) + 3 }).to_double()))
    cumulative.push(Json::number((if w < 22 { 0 } else { (w - 21) * 7 / 30 + 1 }).to_double()))
  }
  let months = [(4, "11月"), (9, "12月"), (13, "1月"), (17, "2月"), (21, "3月"), (26, "4月"), (30, "5月"), (35, "6月"), (39, "7月"), (43, "8月"), (48, "9月")]
  let named = fn(title : String, key : String, rows : Array[(String, String)]) {
    obj([("title", str(title)), ("items", Json::array(rows.map(fn(r) { obj([(key, str(r.0)), ("value", str(r.1))]) })))])
  }
  obj([
    ("title", str("星火工作室")),
    (
      "figures",
      Json::array([("累计 token", "18.3 亿"), ("归档的对话", "1,358"), ("跨设备任务", "312"), ("决策点击率", "48%"), ("一起干活的设备", "3")].map(fn(f) {
        obj([("label", str(f.0)), ("value", str(f.1))])
      })),
    ),
    (
      "activity",
      obj([
        ("title", str("Token 活跃度")),
        ("sub", str("近 12 个月")),
        ("views", [str("按天"), str("按周"), str("累计")]),
        ("weekdays", Json::array(["日", "一", "二", "三", "四", "五", "六"].map(str))),
        ("months", Json::array(months.map(fn(m) { obj([("week", Json::number(m.0.to_double())), ("label", str(m.1))]) }))),
        ("cells", Json::array(cells)),
        ("weekly", Json::array(weekly)),
        ("cumulative", Json::array(cumulative)),
        ("tips", Json::array(tips)),
        ("weekTips", Json::array(week_tips)),
        ("runningTips", Json::array(running_tips)),
        ("less", str("少")),
        ("more", str("多")),
        ("captions", [str(""), str("每列一周 · 最高 1.1 亿"), str("累计 · 共 18.3 亿")]),
      ]),
    ),
    ("stations", named("各设备的工作量", "name", [("Willow", "12.6 亿 token · 69%"), ("Maple", "4.1 亿 token · 22%"), ("Birch", "1.6 亿 token · 9%")])),
    ("places", named("对话来自", "name", [("still.fail", "1,212 个对话"), ("Slack", "184 个对话"), ("飞书", "34 个对话")])),
    ("asOf", str("统计截至 10月2日")),
  ])
}

///|
/// What the core's `usage` view says (views/usage.ts) of a made-up workspace: its days split by the list `split`
/// asks for, of the one person, account or model `only` names (its key) alone; as it is sent (client/core-ts
/// schema.ts UsageView: not its accounts' allowances, its scale's lines, a day's calls and parts, an item's calls).
fn fx_usage(days : Int, split? : String = "people", only? : String = "", day? : String = "", details_pending? : Bool = false) -> Json {
  // (the one alone: a part of everything)
  let part = if only == "" { 1.0 } else { 0.42 }
  let daily : Array[Json] = []
  for i in 0..<days {
    let cost = (((i * 37 + 11) % 23).to_double() + 4.0) * part
    daily.push(
      obj([
        ("day", str("2026-10-" + (if i + 1 < 10 { "0" } else { "" }) + (i + 1).to_string())),
        ("label", str("10/" + (i + 1).to_string())),
        ("cost", Json::number(cost)),
        ("costText", str("$" + cost.to_int().to_string())),
        // (what the core says of it: views/usage.ts)
        ("name", str(if i == days - 1 { "今天" } else { "10/" + (i + 1).to_string() })),
        ("tick", str(if i == days - 1 { "今天" } else if days <= 10 || (days - 1 - i) % 7 == 0 { "10/" + (i + 1).to_string() } else { "" })),
        ("shares", [Json::number(0.6), Json::number(0.3), Json::number(0.1)]),
      ]),
    )
  }
  let item = fn(key : String, title : String, sub : String, cost : String, share : Double, shareText : String) {
    obj([
      ("key", str(key)),
      ("title", str(title)),
      ("sub", str(sub)),
      ("costText", str(cost)),
      ("share", Json::number(share)),
      ("shareText", str(shareText)),
      ("tokensText", str("")),
    ])
  }
  let series = match split {
    "models" => [("claude-opus-5-5", "Opus 5.5"), ("gpt-6", "GPT-6"), ("", "其他")]
    "profiles" => [("Willow/cc", "公司 Claude"), ("Willow/codex", "Codex 团队"), ("", "其他")]
    "chats" => [("Willow/1", "整理发布清单"), ("Willow/4", "给设置页加一个深色模式开关"), ("", "其他")]
    _ => [("lin@example.com", "林"), ("ana@example.com", "Ana"), ("", "其他")]
  }
  // The core ranks the filtered rows too: the selected split then contains only the chosen part.
  let series = if only != "" && series.iter().any(fn(s) { s.0 == only }) { series.filter(fn(s) { s.0 == only }) } else { series }
  let lists = [
    ("people", "按人", [("lin@example.com", "林", "", "$80", 0.68), ("ana@example.com", "Ana", "", "$31", 0.26), ("wu@example.com", "吴", "", "$7.20", 0.06)]),
    (
      "chats",
      "按对话",
      [
        ("Willow/1", "整理发布清单", "林 · Opus 5.5 · Willow", "$31", 0.26),
        ("Willow/4", "给设置页加一个深色模式开关", "Ana · GPT-6 · Willow", "$22", 0.19),
        ("Maple/3", "夜里的构建又失败了", "林 · Opus 5.5 · Maple", "$15", 0.13),
      ],
    ),
    ("profiles", "按账号", [("Willow/cc", "公司 Claude", "Willow · 最多 Opus 5.5", "$84", 0.71), ("Willow/codex", "Codex 团队", "Willow · 最多 GPT-6", "$34", 0.29)]),
    ("models", "按模型", [("claude-opus-5-5", "Opus 5.5", "", "$84", 0.71), ("gpt-6", "GPT-6", "", "$28", 0.24), ("claude-haiku-5", "Haiku 5", "", "$6.10", 0.05)]),
  ]
  // (the day's name as the core says it: 10/5 for 2026-10-05)
  let dd = if day.length() >= 10 { day[8:].to_owned() } else { "" }
  // (its cost, as its bar says it)
  let day_cost = match daily.search_by(fn(d) { day != "" && text(Some(d), "day") == day }) {
    Some(i) => text(Some(daily[i]), "costText")
    None => ""
  }
  let day_name = if day == "" { "" } else { "10/" + (if dd.has_prefix("0") { dd[1:].to_owned() } else { dd }) }
  let only_shown = match lists.search_by(fn(l) { l.2.search_by(fn(it) { it.0 == only }) is Some(_) }) {
    Some(k) if only != "" => {
      let (_, _, its) = lists[k]
      let it = its[its.search_by(fn(it) { it.0 == only }).unwrap()]
      obj([("title", str(it.1))])
    }
    _ => Json::null()
  }
  obj([
    ("split", str(split)),
    ("only", only_shown),
    ("wait", obj([("reading", Json::boolean(details_pending)), ("failing", []), ("empty", Json::boolean(false))])),
    ("empty", Json::boolean(details_pending)),
    ("detailsPreparing", Json::boolean(details_pending)),
    (
      "tiles",
      [
        obj([
          ("label", str("折合费用")),
          ("value", str(if details_pending { "$0" } else if day_cost != "" { day_cost } else if only != "" { "$50" } else if days == 7 { "$118" } else { "$486" })),
          // (a day picked: against nothing)
          ("change", if details_pending || day != "" { Json::null() } else { str(if days == 7 { "↑18%" } else { "↓6.4%" }) }),
        ]),
        obj([
          ("label", str("模型调用")),
          ("value", str(if only != "" { "595 次" } else if days == 7 { "1,416 次" } else { "5,830 次" })),
          ("change", str(if days == 7 { "↑9.2%" } else { "↓3.1%" })),
        ]),
        obj([
          ("label", str("输入 token")),
          ("value", str(if only != "" { "970 万" } else if days == 7 { "2,310 万" } else { "9,870 万" })),
          ("change", str(if days == 7 { "↑21%" } else { "↑2.5%" })),
        ]),
        obj([
          ("label", str("输出 token")),
          ("value", str(if only != "" { "18 万" } else if days == 7 { "43 万" } else { "1.8 亿" })),
          ("change", str(if days == 7 { "↓4.0%" } else { "持平" })),
        ]),
      ],
    ),
    ("versus", str("比前 " + days.to_string() + " 天")),
    ("period", str(if day != "" { day_name } else { "近 " + days.to_string() + " 天" })),
    ("summary", fx_usage_summary()),
    ("series", Json::array(series.map(fn(x) { obj([("key", str(x.0)), ("name", str(x.1))]) }))),
    ("daily", Json::array(daily)),
    ("many", Json::boolean(days > 10)),
    // (the scale the core works out for it: views/usage.ts scale)
    ("top", Json::number(30.0)),
    (
      "lists",
      Json::array(
        lists.map(fn(l) {
          let (key, title, its) = l
          let shown = if only == "" { its } else { its.filter(fn(it) { it.0 == only || key != only_shown_list(lists, only) }) }
          let listed = shown.map(fn(it) { item(it.0, it.1, it.2, it.3, it.4, (it.4 * 100.0).to_int().to_string() + "%") })
          obj([
            ("key", str(key)),
            ("title", str(title)),
            ("items", Json::array(listed)),
            // (its first three and the rest: as many here, each its key)
            ("parts", Json::array(shown.map(fn(it) { obj([("key", str(it.0))]) }))),
          ])
        }),
      ),
    ),
    ("notes", if details_pending { [str("正在读取历史记录，数据可能变化")] } else { [] }),
    ("basis", str("按各服务商公开的 API 价格折算，不是实际账单。")),
    (
      "prices",
      [
        obj([
          ("station", str("Willow")),
          ("note", str("每百万 token 的美元价格，取自服务商公开价格")),
          (
            "rows",
            [
              obj([("model", str("Opus 5.5")), ("rates", [obj([("label", str("输入")), ("value", str("$5"))]), obj([("label", str("输出")), ("value", str("$25"))]), obj([("label", str("缓存读")), ("value", str("$0.5"))])])]),
              obj([("model", str("Sonnet 5")), ("rates", [obj([("label", str("输入")), ("value", str("$3"))]), obj([("label", str("输出")), ("value", str("$15"))]), obj([("label", str("缓存读")), ("value", str("$0.3"))])])]),
            ],
          ),
        ]),
        obj([("station", str("Maple")), ("note", str("station 离线，读不到它的价格表")), ("rows", [])]),
      ],
    ),
  ])
}

///|
fn fx_memory() -> Json {
  obj([
    (
      "global",
      obj([
        ("path", str("~/.claude/CLAUDE.md")),
        ("text", str("")),
        ("size", str("4 KB")),
        (
          "sections",
          [
            obj([("title", str("开头")), ("text", str("这台机器上的 agent 共用的记忆。")), ("note", str("1 KB"))]),
            obj([("title", str("习惯")), ("text", str("- 提交前先跑测试\n- 说明写成完整的句子")), ("note", str("2 条"))]),
          ],
        ),
      ]),
    ),
    (
      "skills",
      [
        obj([
          ("name", str("发布流程")),
          ("description", str("项目记忆：发布新版本时")),
          ("project", Json::boolean(true)),
          ("builtin", Json::boolean(false)),
          ("text", str("")),
          ("body", str("## 步骤\n\n1. 改版本号\n2. 写更新说明\n3. 打包并上传")),
          ("about", str("发布新版本时")),
          ("size", str("3 KB")),
          ("files", [obj([("name", str("checklist.md")), ("text", str("- 签名\n- 截图")), ("label", str("checklist")), ("size", str("1 KB"))])]),
          // (the core's words of it: looks.ts)
          ("group", str("project")), ("kindText", str("项目记忆")), ("whenText", str("发布新版本时")), ("line", str("发布新版本时")), ("pages", [obj([("key", str("")), ("label", str("总览")), ("text", str("## 步骤\n\n1. 改版本号\n2. 写更新说明\n3. 打包并上传"))]), obj([("key", str("checklist.md")), ("label", str("checklist")), ("size", str("1 KB")), ("text", str("- 签名\n- 截图"))])]),
          (
            "share",
            if fx.skills_shared.get("发布流程").unwrap_or(true) {
              obj([("id", str("sh1")), ("role", str("host")), ("host", str("st1")), ("conflicts", ["SKILL.md"]), ("users", ["st2"]), ("missing", [])])
            } else {
              obj([])
            },
          ),
        ]),
        obj([
          ("name", str("周报")),
          ("description", str("写周报时用的格式")),
          ("project", Json::boolean(false)),
          ("builtin", Json::boolean(false)),
          ("text", str("每周五下午写。")),
          ("size", str("1 KB")),
          ("group", str("skill")), ("kindText", str("Skill")), ("whenText", str("写周报时用的格式")), ("line", str("写周报时用的格式")), ("pages", [obj([("key", str("")), ("label", str("总览")), ("text", str("每周五下午写。"))])]),
        ]),
        obj([("name", str("pdf")), ("size", str("2 KB")), ("description", str("读写 PDF")), ("project", Json::boolean(false)), ("builtin", Json::boolean(true)), ("text", str("")), ("group", str("builtin")), ("kindText", str("station 内置")), ("whenText", str("读写 PDF")), ("line", str("读写 PDF")), ("pages", [obj([("key", str("")), ("label", str("总览")), ("text", str("（空）"))])])]),
        obj([("name", str("xlsx")), ("size", str("2 KB")), ("description", str("读写表格")), ("project", Json::boolean(false)), ("builtin", Json::boolean(true)), ("text", str("")), ("group", str("builtin")), ("kindText", str("station 内置")), ("whenText", str("读写表格")), ("line", str("读写表格")), ("pages", [obj([("key", str("")), ("label", str("总览")), ("text", str("（空）"))])])]),
      ],
    ),
  ])
}

///|
/// The workspaces the new device asks into (settings-lock-prompt): 星火工作室 and 个人, and 开源 once it asked there
/// too (fx's `pairing_more`).
fn pairing_places() -> Array[Json] {
  let places = [obj([("id", str("ws1")), ("name", str("星火工作室"))]), obj([("id", str("ws2")), ("name", str("个人"))])]
  if fx.pairing_more {
    places.push(obj([("id", str("ws3")), ("name", str("开源")), ("emoji", str("🌲"))]))
  }
  places
}

///|
/// A made-up settings topic, None for one these do not make.
pub fn fixture_topic(mode : String, name : String, params : Map[String, Json]) -> Json? {
  if name == "lock" && mode.has_prefix("lock-") {
    return Some(waiting_lock(mode))
  }
  let me : Json = obj([("sub", str("u1")), ("email", str("lin@example.com")), ("name", str("林")), ("role", str("owner"))])
  match name {
    // Willow's logins (station_logins.mbt): codex's under way, gh's done yesterday
    // (the settings' own pages only: a chat's login cards are the chats' fixture's)
    "machineLogins" if mode.has_prefix("settings") && text(Some(Json::object(params)), "station") == "ws1/st1" => {
      let gh_login = obj([
        ("id", str("login-0")),
        ("active", Json::boolean(false)),
        ("name", str("gh")),
        ("command", str("env GH_HOST=github.com /opt/homebrew/bin/gh auth login")),
        ("chat", str("s-c1")),
        ("chatTitle", str("整理发布清单")),
        ("whenText", str("昨天")),
        ("statusText", str("已登录")),
        ("doneByText", str("林 完成")),
        ("state", str("done")),
      ])
      Some(
        obj([
          ("supported", Json::boolean(true)),
          ("canLogin", Json::boolean(true)),
          ("canRelay", Json::boolean(true)),
          (
            "logins",
            [
              obj([("id", str("login-2")), ("active", Json::boolean(true)), ("command", str("codex login"))]),
              gh_login,
            ],
          ),
          (
            "tools",
            [
              obj([
                ("name", str("gh")),
                ("summaryText", str("林 登录 · 昨天")),
                ("failed", Json::boolean(false)),
                ("chat", str("s-c1")),
                ("chatTitle", str("整理发布清单")),
                ("countText", str("1 次")),
                ("tries", [gh_login]),
              ]),
            ],
          ),
        ]),
      )
    }
    "machineLogin" if mode.has_prefix("settings") && text(Some(Json::object(params)), "id") == "login-2" =>
      Some(
        obj([
          ("id", str("login-2")),
          ("title", str("在 Willow 上登录 codex")),
          ("state", str("browser")),
          ("step", str("open")),
          ("url", str("https://auth.openai.com/log-in")),
          ("domain", str("auth.openai.com")),
          ("active", Json::boolean(true)),
          ("statusText", str("等你在浏览器里登录")),
        ]),
      )
    "workspace" =>
      Some(
        obj([
          ("id", str("ws1")),
          ("name", str("星火工作室")),
          ("role", str("owner")),
          (
            "members",
            fx_members(me),
          ),
          ("stations", [obj([("id", str("st1")), ("name", str("Willow"))]), obj([("id", str("st2")), ("name", str("Maple"))])]),
          ("rigs", rigs_fixture_listed(mode)),
          ("invitations", [obj([("id", str("i1")), ("role", str("member")), ("email", str("qin@example.com")), ("time", obj([("expires_at", stamp_of("", until="6 天后"))]))])]),
          ("added", [obj([("email", str("he@example.com")), ("role", str("member"))])]),
          ("relays", []),
        ]),
      )
    // the workspace's stations that only run tasks (rigs_fixture.mbt)
    "rigs" if rigs_fixture_mode(mode) => Some(rigs_fixture_topic(mode))
    // the workspace's devices (devices_fixture.mbt)
    "devices" if devices_fixture_mode(mode) => Some(devices_fixture_topic())
    // every way its devices reach its stations (the core's views/ways.ts), the punched path turned off
    "workspaceWays" =>
      Some(
        obj([
          (
            "ways",
            [
              obj([("id", str("https://app.still.fail/")), ("kind", str("relay")), ("name", str("Cloudflare")), ("own", Json::boolean(false)), ("on", Json::boolean(true))]),
              obj([("id", str("https://39.105.157.122/")), ("kind", str("relay")), ("name", str("北京")), ("own", Json::boolean(false)), ("on", Json::boolean(true))]),
              obj([("id", str("lan")), ("kind", str("lan")), ("name", str("")), ("own", Json::boolean(false)), ("on", Json::boolean(true))]),
              obj([("id", str("tailnet")), ("kind", str("tailnet")), ("name", str("")), ("own", Json::boolean(false)), ("on", Json::boolean(true))]),
              obj([("id", str("direct")), ("kind", str("direct")), ("name", str("")), ("own", Json::boolean(false)), ("on", Json::boolean(false))]),
            ],
          ),
          ("off", Json::number(1.0)),
          ("offLabel", str("已关闭 1 项")),
        ]),
      )
    "stations" =>
      if fx.none {
        Some([])
      } else {
        // (settings-stations-motion: 3 comes, then Maple goes)
        let all = [fx_station("ws1/st1"), fx_station("ws1/st2")]
        if fx.motion >= 1 {
          all.push(fx_station("ws1/st3"))
        }
        if fx.motion >= 2 {
          all.remove(1) |> ignore
        }
        Some(Json::array(all))
      }
    // a new device asking with this one's code (lock_prompts.mbt)
    "lockPrompts" =>
      Some(
        obj([
          (
            "pairing",
            if fx.pairing {
              [
                obj([
                  ("device", str("d-new")),
                  ("name", str("林")),
                  ("email", str("lin@example.com")),
                  ("kind", str("android")),
                  ("label", str("Pixel 9")),
                  ("code", str("482915")),
                  ("deviceText", str("Pixel 9")),
                  ("created_at", Json::number(0.0)),
                  ("untilText", str("14:05 前有效")),
                  ("workspaces", if fx.pairing_personal { [] } else { Json::array(pairing_places()) }),
                ]),
              ]
            } else {
              []
            },
          ),
          // a device of lin's waiting on this one for the key to 林的库 (vault_prompts.mbt)
          (
            "asks",
            if fx.key_ask {
              [
                obj([
                  ("workspace", str("ws1")),
                  ("workspaceName", str("星火工作室")),
                  ("vault", str("v1")),
                  ("vaultName", str("林的库")),
                  ("device", str("d-new")),
                  ("deviceText", str("Pixel 9")),
                  ("at", Json::number(0.0)),
                  ("atText", str("3 分钟前")),
                ]),
              ]
            } else {
              []
            },
          ),
        ]),
      )
    "screens" => {
      let m = if mode.has_suffix("-dark") { mode.unsafe_substring(start=0, end=mode.length() - 5) } else { mode }
      if m == "settings-station-pages" || m == "screen-pages" || m == "screen-user-pages" || m == "screen-user-tabs" {
        Some(
          obj([
            (
              "screens",
              [
                obj([("id", str("desktop")), ("kind", str("desktop")), ("title", str("Willow 的屏幕")), ("width", Json::number(3024.0)), ("height", Json::number(1964.0)), ("line", str("3024 × 1964 · 无人在看")), ("link", str(""))]),
                obj([("id", str("browser:u_mail")), ("kind", str("browser")), ("userTab", Json::boolean(true)), ("closable", Json::boolean(true)), ("openUrl", Json::boolean(true)), ("site", str("mail.proton.me")), ("title", str("收件箱 - Proton Mail")), ("width", Json::number(1280.0)), ("height", Json::number(800.0)), ("line", str("mail.proton.me")), ("link", str(""))]),
                obj([("id", str("browser:u_gh")), ("kind", str("browser")), ("userTab", Json::boolean(true)), ("sleeping", Json::boolean(true)), ("closable", Json::boolean(true)), ("openUrl", Json::boolean(true)), ("site", str("github.com")), ("title", str("GitHub")), ("width", Json::number(0.0)), ("height", Json::number(0.0)), ("line", str("github.com")), ("link", str(""))]),
                obj([("id", str("browser:tab-1")), ("kind", str("browser")), ("closable", Json::boolean(true)), ("openUrl", Json::boolean(true)), ("title", str("Sign in · Anthropic")), ("width", Json::number(1280.0)), ("height", Json::number(720.0)), ("line", str("浏览器标签页 · 1280 × 720")), ("link", str(""))]),
              ],
            ),
            ("browser", Json::boolean(true)),
            ("outdated", Json::boolean(false)),
            ("control", Json::boolean(true)),
            ("known", Json::boolean(true)),
          ]),
        )
      } else {
        Some(
          obj([
            (
              "screens",
              [
                obj([("id", str("desktop")), ("kind", str("desktop")), ("title", str("Willow 的屏幕")), ("width", Json::number(3024.0)), ("height", Json::number(1964.0)), ("line", str("3024 × 1964 · 无人在看")), ("link", str(""))]),
                obj([("id", str("browser:t1")), ("kind", str("browser")), ("title", str("发布清单 - 文档")), ("width", Json::number(1280.0)), ("height", Json::number(800.0)), ("line", str("浏览器标签页 · 1280 × 800")), ("link", str(""))]),
              ],
            ),
            ("outdated", Json::boolean(false)),
            ("control", Json::boolean(true)),
            ("known", Json::boolean(true)),
          ]),
        )
      }
    }
    // what still.fail uses of Willow's machine (the `resources` view): a chat's agent and the station
    "resources" => Some(fx_resources())
    "adbShare" => Some(fx_adb_share())
    "joinable" =>
      Some(
        obj([
          ("offered", Json::boolean(true)),
          ("loading", Json::boolean(false)),
          (
            "items",
            [
              obj([("station", str("ws2/st9")), ("id", str("st9")), ("name", str("家里的 mini")), ("icon", str("glyph:mini:green")), ("workspace", str("ws2")), ("workspaceName", str("个人")), ("online", Json::boolean(true)), ("line", str("个人 · 在线"))]),
              obj([("station", str("ws3/st7")), ("id", str("st7")), ("name", str("实验机")), ("workspace", str("ws3")), ("workspaceName", str("实验室")), ("online", Json::boolean(false)), ("line", str("实验室已开启安全模式，此 workspace 未开启")), ("needsLock", Json::boolean(true))]),
            ],
          ),
        ]),
      )
    "memberships" =>
      Some(
        obj([
          ("manages", Json::boolean(true)),
          ("loading", Json::boolean(false)),
          ("canJoin", Json::boolean(true)),
          (
            "workspaces",
            [
              obj([("id", str("ws1")), ("workspace", str("ws1")), ("home", Json::boolean(true)), ("name", str("星火工作室")), ("line", str("主 workspace"))]),
              obj([("id", str("ws2")), ("workspace", str("ws2")), ("home", Json::boolean(false)), ("name", str("个人")), ("line", str("~/项目/个人"))]),
            ],
          ),
        ]),
      )
    "profileFlow" if fx.new_login => Some(fx_profile_flow_plan())
    "profileFlow" => Some(fx_profile_flow(hermes=mode == "settings-new-profile-hermes"))
    "pick" if text(Some(Json::object(params)), "of").has_prefix("session:") => {
      let v = fx_session_pick()
      if mode == "settings-run-runtime" {
        match v {
          Object(o) => {
            o["runtimeFixed"] = Json::boolean(false)
            o["runtimes"] = ["claude", "codex"]
            Some(Json::object(o))
          }
          _ => Some(v)
        }
      } else {
        Some(v)
      }
    }
    "connectFlow" if fx_connect_step.val == "commaBind" => Some(fx_comma_flow())
    "connectFlow" if fx_connect_step.val != "team" && fx_connect_step.val != "app" =>
      Some(fx_feishu_flow(fx_connect_step.val))
    "connectFlow" =>
      Some(
        obj([
          ("step", str(fx_connect_step.val)),
          ("title", str(if fx_connect_step.val == "app" { "Slack 应用" } else { "Slack 工作区" })),
          ("back", str(if fx_connect_step.val == "app" { "team" } else { "close" })),
          ("number", Json::number(if fx_connect_step.val == "app" { 2.0 } else { 1.0 })),
          ("total", Json::number(4.0)),
          ("mobile", Json::boolean(true)),
          ("adding", Json::boolean(false)),
          (
            "settings",
            obj([
              ("name", str("still.fail")),
              ("description", str("Coding agent in your threads (still.fail)")),
              ("backgroundColor", str("#F3E3D3")),
            ]),
          ),
          ("config", str("")),
          ("configReady", Json::boolean(false)),
          ("mode", str("multi-session")),
          ("requireMention", Json::boolean(true)),
          ("gettingToken", Json::boolean(false)),
          ("noProfile", Json::boolean(false)),
          ("canMake", Json::boolean(false)),
          ("canCreate", Json::boolean(false)),
          (
            "teams",
            [
              obj([("teamId", str("T1")), ("name", str("星火")), ("owner", obj([("user", str("林")), ("teamDomain", str("xinghuo"))]))]),
              obj([("teamId", str("T2")), ("name", str("实验室")), ("owner", obj([("user", str("林"))]))]),
            ],
          ),
          ("chosen", obj([("teamId", str("T1")), ("name", str("星火"))])),
          ("modeWords", fx_mode_words(fx_connect_step.val.has_prefix("feishu"))),
          ("sections", fx_sections()),
        ]),
      )
    "slackApp" =>
      Some(
        obj([
          ("state", str("ok")),
          ("appId", str("A1")),
          ("links", obj([("settings", str("https://api.slack.com/apps/A1")), ("install", str("")), ("appToken", str("")), ("oauth", str(""))])),
          (
            "settings",
            obj([
              ("name", str("星火助手")),
              ("displayName", str("星火助手")),
              ("description", str("帮团队整理发布和构建")),
              ("longDescription", str("")),
              ("backgroundColor", str("#F3E3D3")),
              ("groups", obj([("base", Json::boolean(true)), ("public", Json::boolean(true)), ("dm", Json::boolean(true)), ("files", Json::boolean(true))])),
            ]),
          ),
          // its permissions as the core says them (present.ts slackSections)
          ("sections", fx_sections()),
        ]),
      )
    "vaultUses" =>
      Some(
        obj([
          (
            "uses",
            [
              obj([("at", stamp_of("昨天")), ("session", str("s-c1")), ("station", str("st1")), ("chatTitle", str("整理发布清单")), ("mode", str("proxy")), ("hosts", ["api.github.com"]), ("command", str("git push origin main")), ("howText", str("git push origin main · 代理"))]),
              obj([("at", stamp_of("3 天前")), ("session", str("s-c4")), ("station", str("st1")), ("chatTitle", str("给设置页加一个深色模式开关")), ("mode", str("proxy")), ("hosts", []), ("denied", Json::boolean(true)), ("howText", str("代理"))]),
            ],
          ),
        ]),
      )
    "decisionForm" =>
      Some(obj([("enabled", Json::boolean(true)), ("model", str("gpt-6-mini")), ("dirty", Json::boolean(false)), ("pending", Json::boolean(false))]))
    "policyForm" =>
      Some(
        obj([
          ("policy", str("做完、没有待办的对话归档；还在等人回复或有后续计划的留下。")),
          // the station's options, each its draft's key its id
          (
            "options",
            [
              obj([("key", str("o1")), ("id", str("o1")), ("name", str("已完成")), ("rubric", str("任务做完，没有后续")), ("archive", Json::boolean(true))]),
              obj([("key", str("o2")), ("id", str("o2")), ("name", str("被放弃")), ("rubric", str("明确不再继续")), ("archive", Json::boolean(true))]),
              obj([("key", str("o3")), ("id", str("o3")), ("name", str("等回复")), ("rubric", str("在等某人的答复")), ("archive", Json::boolean(false))]),
            ],
          ),
          ("dirty", Json::boolean(false)),
          ("pending", Json::boolean(false)),
        ]),
      )
    // what the settings say of the workspace (the core's views/settings.ts): Willow's completion rule on
    "settings" =>
      Some(
        obj([
          ("decisionsOn", Json::number(1.0)),
          ("decisionsText", str("1 台 station 已启用")),
          // (Willow reviews, Maple is offline: nothing to say of the hint)
          ("hintNoReview", Json::boolean(false)),
          ("hintReviewText", str("")),
        ]),
      )
    // (as the core answers it: every tab, the one asked (`part`, the first where none or another is said) with its
    // days, its first `limit` of them; two changes, none more)
    "changelog" => {
      let asked = match params.get("part") {
        Some(String("station")) => "station"
        _ => "app"
      }
      let days : Array[Json] = [
        obj([
          ("day", Json::number(20380.0)),
          ("label", str("10 月 19 日")),
          (
            "entries",
            [
              obj([("version", Json::number(2.0)), ("versionName", str("0.1.1300")), ("lines", [obj([("kind", str("new")), ("label", str("新增")), ("text", str("设置里可以添加 station 和 Profile"))])]), ("has", Json::boolean(false)), ("note", str("更新后可用"))]),
              obj([("version", Json::number(1.0)), ("versionName", str("0.1.1288")), ("lines", [obj([("kind", str("fix")), ("label", str("修复")), ("text", str("对话列表偶尔把同一行显示两次，滑到底再滑回来也不会消失"))])]), ("has", Json::boolean(true)), ("note", str(""))]),
            ],
          ),
        ]),
      ]
      Some(
        obj([
          ("build", Json::number(1300.0)),
          (
            "tabs",
            [
              obj([("part", str("app")), ("label", str("此 app")), ("days", if asked == "app" { Json::array(days) } else { [] })]),
              obj([("part", str("station")), ("label", str("Station")), ("days", [])]),
            ],
          ),
        ]),
      )
    }
    "agentEnvForm" =>
      Some(
        obj([
          ("text", str("HTTPS_PROXY=http://127.0.0.1:7890\nNO_PROXY=localhost,.internal\nBAD LINE")),
          (
            "lines",
            [
              obj([("parts", []), ("error", Json::boolean(false))]),
              obj([("parts", []), ("error", Json::boolean(false))]),
              obj([("parts", []), ("error", Json::boolean(true)), ("problem", str("缺少「=」"))]),
            ],
          ),
          ("errors", Json::number(1.0)),
          ("dirty", Json::boolean(true)),
          ("pending", Json::boolean(false)),
        ]),
      )
    "connects" =>
      Some(
        fx_moved(obj([
          ("me", obj([("email", str("lin@example.com"))])),
          (
            "items",
            [
              obj([
                ("station", str("ws1/st1")),
                ("stationName", str("Willow")),
                (
                  "connect",
                  match mode {
                    "settings-connect-comma" => fx_connect_as("comma")
                    "settings-connect-feishu" => fx_connect_as("feishu")
                    _ => fx_connect("k1", "星火助手", "online", "在线", "multi-session")
                  },
                ),
                ("runtimeChanges", Json::boolean(mode == "settings-connect-switch")),
                (
                  "sessions",
                  if mode == "settings-connect-comma" || mode == "settings-connect-feishu" {
                    []
                  } else {
                    [
                      obj([("key", str("s-c7")), ("titleText", str("Slack 里问的报销流程")), ("statusText", str("昨天"))]),
                      obj([("key", str("s-c2")), ("titleText", str("首页的列表改成按天分组")), ("statusText", str("8 分钟前"))]),
                    ]
                  },
                ),
                ("candidates", []),
                ("running", Json::number(0.0)),
                ("changes", fx_mode_changes()),
              ]),
              obj([
                ("station", str("ws1/st1")),
                ("stationName", str("Willow")),
                ("connect", fx_connect("k2", "值班机器人", "error", "连接失败", "single-session")),
                ("sessions", []),
                ("candidates", []),
                ("running", Json::number(0.0)),
                ("changes", Json::array([])),
              ]),
            ],
          ),
          ("wait", obj([("reading", Json::boolean(false)), ("failing", []), ("empty", Json::boolean(false))])),
        ]), obj([
          ("station", str("ws1/st1")),
          ("stationName", str("Willow")),
          ("connect", fx_connect("k9", "发布助手", "online", "在线", "multi-session")),
          ("sessions", []),
          ("candidates", []),
          ("running", Json::number(0.0)),
          ("changes", Json::array([])),
        ]), fn(x) { text(field(Some(x), "connect"), "id") == "k2" }),
      )
    "lock" =>
      Some(
        obj([
          ("available", Json::boolean(true)),
          ("locked", Json::boolean(true)),
          ("notice", Json::boolean(false)),
          ("role", str("owner")),
          ("manages", Json::boolean(true)),
          ("owner", Json::boolean(true)),
          ("canSign", Json::boolean(true)),
          ("signs", Json::boolean(true)),
          ("signers", Json::number(5.0)),
          ("protected", Json::number(1.0)),
          ("attention", Json::number(0.0)),
          (
            "members",
            [
              obj([
                ("sub", str("u1")),
                ("email", str("lin@example.com")),
                ("name", str("林")),
                ("role", str("owner")),
                ("you", Json::boolean(true)),
                ("nameText", str("林")),
                ("roleText", str("Owner")),
                (
                  "groups",
                  [
                    obj([
                      ("appText", str("still.fail Android")),
                      ("devices", [
                        obj([("id", str("d1")), ("kind", str("app")), ("label", str("still.fail Android · Pixel 9")), ("signs", Json::boolean(true)), ("older", Json::boolean(false)), ("mine", Json::boolean(true)), ("renewSoon", Json::boolean(false)), ("recent", Json::boolean(false)), ("lastSeen", Json::number(1760000000.0)), ("removable", Json::boolean(false)), ("nameText", str("Pixel 9")), ("fullText", str("Pixel 9 · still.fail Android")), ("metaText", str("此设备 · 受信任"))]),
                      ]),
                    ]),
                    obj([
                      ("appText", str("still.fail 桌面版")),
                      ("devices", [
                        obj([("id", str("d4")), ("kind", str("app")), ("label", str("still.fail 桌面版 · 林的 MacBook Pro")), ("signs", Json::boolean(true)), ("older", Json::boolean(false)), ("mine", Json::boolean(false)), ("renewSoon", Json::boolean(false)), ("recent", Json::boolean(false)), ("lastSeen", Json::number(1759990000.0)), ("removable", Json::boolean(true)), ("nameText", str("林的 MacBook Pro")), ("fullText", str("林的 MacBook Pro · still.fail 桌面版")), ("metaText", str("一天内使用过 · 受信任"))]),
                        obj([("id", str("d6")), ("kind", str("app")), ("label", str("still.fail 桌面版 · 示例工作站")), ("signs", Json::boolean(true)), ("older", Json::boolean(false)), ("mine", Json::boolean(false)), ("renewSoon", Json::boolean(false)), ("recent", Json::boolean(false)), ("lastSeen", Json::number(1759700000.0)), ("removable", Json::boolean(true)), ("nameText", str("示例工作站")), ("fullText", str("示例工作站 · still.fail 桌面版")), ("metaText", str("3 天前使用过 · 受信任"))]),
                      ]),
                    ]),
                    obj([
                      ("appText", str("still.fail 网页版")),
                      ("devices", [
                        obj([("id", str("d2")), ("kind", str("web")), ("label", str("still.fail 网页版 · Chrome · macOS")), ("signs", Json::boolean(false)), ("older", Json::boolean(false)), ("mine", Json::boolean(false)), ("daysLeft", Json::number(4.0)), ("renewSoon", Json::boolean(true)), ("recent", Json::boolean(false)), ("lastSeen", Json::number(1759800000.0)), ("removable", Json::boolean(true)), ("nameText", str("Chrome · macOS")), ("fullText", str("Chrome · macOS · still.fail 网页版")), ("metaText", str("2 天前使用过 · 剩余 4 天"))]),
                      ]),
                    ]),
                    obj([
                      ("appText", str("其他")),
                      ("devices", [
                        obj([("id", str("d5")), ("kind", str("app")), ("label", str("")), ("signs", Json::boolean(true)), ("older", Json::boolean(false)), ("mine", Json::boolean(false)), ("renewSoon", Json::boolean(false)), ("recent", Json::boolean(false)), ("removable", Json::boolean(true)), ("nameText", str("客户端")), ("fullText", str("客户端")), ("metaText", str("超过一个月未使用 · 受信任"))]),
                      ]),
                    ]),
                  ],
                ),
              ]),
              obj([
                ("sub", str("u2")),
                ("email", str("ana@example.com")),
                ("name", str("Ana")),
                ("role", str("admin")),
                ("you", Json::boolean(false)),
                ("nameText", str("Ana")),
                ("roleText", str("管理员")),
                (
                  "groups",
                  [
                    obj([
                      ("appText", str("still.fail 桌面版")),
                      ("devices", [
                        obj([("id", str("d3")), ("kind", str("app")), ("label", str("still.fail 桌面版 · Ana 的 MacBook Air")), ("signs", Json::boolean(true)), ("older", Json::boolean(false)), ("mine", Json::boolean(false)), ("renewSoon", Json::boolean(false)), ("recent", Json::boolean(false)), ("lastSeen", Json::number(1759570000.0)), ("removable", Json::boolean(false)), ("nameText", str("Ana 的 MacBook Air")), ("fullText", str("Ana 的 MacBook Air · still.fail 桌面版")), ("metaText", str("5 天前使用过 · 受信任"))]),
                      ]),
                    ]),
                  ],
                ),
              ]),
            ],
          ),
          (
            "stations",
            [
              obj([("id", str("st1")), ("name", str("Willow")), ("online", Json::boolean(true)), ("protected", Json::boolean(true))]),
              obj([("id", str("st2")), ("name", str("Maple")), ("online", Json::boolean(false)), ("protected", Json::boolean(false))]),
            ],
          ),
          ("renew", []),
        ] +
        fx_pending_fields()),
      )
    "vaults" =>
      Some(
        obj([
          ("available", Json::boolean(true)),
          ("locked", Json::boolean(true)),
          ("canSign", Json::boolean(true)),
          ("setUp", Json::boolean(!fx.vault_off)),
          ("plainLeft", Json::number(fx.plain_left.to_double())),
          (
            "vaults",
            [fx_vault_row()],
          ),
          (
            "requests",
            [
              obj([
                ("id", str("r1")),
                ("vault", str("v1")),
                ("vaultName", str("林的库")),
                ("item", str("it1")),
                ("itemName", str("GitHub token")),
                ("session", str("s-c1")),
                ("station", str("st1")),
                ("chat", str("c1")),
                ("mode", str("proxy")),
                ("reason", str("要把发布清单推到仓库")),
                ("command", str("git push origin main")),
                ("hosts", ["api.github.com"]),
                ("howText", str("代理 · 限 api.github.com")),
                ("at", Json::number(0.0)),
              ]),
            ],
          ),
          ("refused", []),
          // (the core's words of it: its one request waits)
          ("statusText", str("1 个待批准")),
          ("statusBad", Json::boolean(true)),
        ]),
      )
    "vaultItems" =>
      Some(
        fx_moved(obj([
          ("vault", str("v1")),
          ("name", str("林的库")),
          ("open", Json::boolean(false)),
          (
            "items",
            [
              obj([("id", str("it1")), ("version", Json::number(1.0)), ("at", Json::number(0.0)), ("name", str("GitHub token")), ("kind", str("token")), ("listed", Json::boolean(true)), ("modes", ["proxy"]), ("hosts", ["api.github.com"]), ("lastUse", obj([("at", stamp_of("昨天")), ("session", str("s-c1")), ("chatTitle", str("修 CI")), ("mode", str("proxy")), ("hosts", [])])), ("kindText", str("Token")), ("shut", [obj([("key", str("value")), ("label", str("值")), ("value", str("••••••••••••••••••••")), ("secret", Json::boolean(true)), ("mono", Json::boolean(true))])]), ("agentText", str("允许 agent 申请 · 代理 · api.github.com")), ("lineText", str("代理 · api.github.com · 昨天在「修 CI」用过")), ("howText", str("代理 · 限 api.github.com")), ("lastsText", str("跟随默认 · 直到对话归档"))]),
              obj([("id", str("it2")), ("version", Json::number(1.0)), ("at", Json::number(0.0)), ("name", str("部署机")), ("kind", str("ssh_key")), ("listed", Json::boolean(true)), ("modes", ["ssh"]), ("hosts", []), ("kindText", str("SSH 密钥")), ("shut", [obj([("key", str("private_key")), ("label", str("私钥")), ("value", str("••••••••••••••••••••")), ("secret", Json::boolean(true)), ("mono", Json::boolean(true))])]), ("agentText", str("允许 agent 申请 · ssh-agent")), ("lineText", str("ssh-agent")), ("howText", str("ssh-agent")), ("lastsText", str("跟随默认 · 直到对话归档"))]),
              obj([("id", str("it3")), ("version", Json::number(1.0)), ("at", Json::number(0.0)), ("kind", str("login")), ("listed", Json::boolean(false)), ("modes", []), ("hosts", []), ("kindText", str("登录")), ("shut", [obj([("key", str("username")), ("label", str("用户名")), ("value", str("••••••••••")), ("secret", Json::boolean(false)), ("mono", Json::boolean(false))]), obj([("key", str("password")), ("label", str("密码")), ("value", str("••••••••••••")), ("secret", Json::boolean(true)), ("mono", Json::boolean(true))])]), ("agentText", str("仅自己可见")), ("lineText", str("仅自己可见")), ("howText", str("")), ("lastsText", str("跟随默认 · 直到对话归档"))]),
            ],
          ),
        ]), obj([("id", str("it4")), ("version", Json::number(1.0)), ("at", Json::number(0.0)), ("name", str("OpenAI key")), ("kind", str("token")), ("listed", Json::boolean(true)), ("modes", ["proxy"]), ("hosts", ["api.openai.com"]), ("kindText", str("Token")), ("shut", []), ("agentText", str("允许 agent 申请 · 代理 · api.openai.com")), ("lineText", str("代理 · api.openai.com")), ("howText", str("代理 · 限 api.openai.com")), ("lastsText", str("跟随默认 · 直到对话归档"))]), fn(x) { text(Some(x), "id") == "it1" }),
      )
    "profiles" => {
      let list = fx_profiles().map(fn(p) {
        // how it is, as the core says it (views/profiles.ts stateOf): its trouble, in its check's words where the check
        // did not pass
        let pv = Some(p)
        let look = field(pv, "trouble") is Some(Object(_))
        let green = text(pv, "checkTone") == "green"
        let state = if look && green {
          obj([("text", str(text(field(pv, "trouble"), "title"))), ("tone", str("amber"))])
        } else if green {
          Json::null()
        } else {
          obj([("text", str(text(pv, "checkText"))), ("tone", str(text(pv, "checkTone")))])
        }
        obj([
          ("key", str("ws1/st1/" + text(Some(p), "id"))),
          ("group", str(text(Some(p), "group"))),
          ("groupTitle", str(text(Some(p), "groupTitle"))),
          ("station", str("ws1/st1")),
          // (as the list is sent it: client/core-ts schema.ts WorkspaceProfile, ListedProfile)
          ("profile", listed_profile_said(p)),
          ("title", str(if text(Some(p), "email") == "" { text(Some(p), "name") } else { text(Some(p), "email") })),
          ("usable", Json::boolean(true)),
          ("state", state),
          ("look", Json::boolean(look)),
          ("where", str(if fx.trouble == "quota-login" && text(pv, "id") == "cx" { "Willow" } else { "Willow 可用" })),
          (
            "stations",
            [
              obj([("id", str("st1")), ("name", str("Willow")), ("online", Json::boolean(true))]),
              obj([("id", str("st2")), ("name", str("Maple")), ("online", Json::boolean(false))]),
            ],
          ),
          (
            "members",
            if fx.profile_hosts && text(pv, "id") == "cc" {
              Json::array(
                fx_profile_hosts()
                .filter(fn(m) { !fx.profile_pending || text(Some(m), "stationId") != "st2" })
                .map(fn(m) { fields_dropped(m, ["stationName", "profileName", "checkText", "usedBy"]) }),
              )
            } else { [
              obj([("station", str("ws1/st1")), ("stationId", str("st1")), ("online", Json::boolean(true)), ("profileId", str(text(Some(p), "id"))), ("role", str("host")), ("about", str("")), ("usable", Json::boolean(true)), ("checkTone", str("green"))]),
            ] },
          ),
          (
            "places",
            if fx.profile_hosts && text(pv, "id") == "cc" {
              Json::array(fx_profile_places().map(fn(pl) { fields_dropped(pl, ["stationId"]) }))
            } else {
              [obj([("station", str("ws1/st1")), ("stationName", str("Willow")), ("profileId", str(text(pv, "id"))), ("online", Json::boolean(true)), ("usable", Json::boolean(true)), ("sourceName", str("")), ("state", Json::null())])]
            },
          ),
        ])
      })
      let attention = list.filter(fn(e) { flag(Some(e), "look") }).length()
      Some(
        obj([
          ("items", Json::array(list)),
          ("attention", Json::number(attention.to_double())),
          ("wait", obj([("reading", Json::boolean(false)), ("failing", []), ("empty", Json::boolean(false))])),
        ]),
      )
    }
    "usage" =>
      Some(
        fx_usage(
          match params.get("days") {
            Some(Number(n, ..)) => n.to_int()
            _ => 7
          },
          split=match params.get("split") {
            Some(String(l)) => l
            _ => "people"
          },
          only=match params.get("only") {
            Some(Object(o)) =>
              match o.get("key") {
                Some(String(k)) => k
                _ => ""
              }
            _ => ""
          },
          day=match params.get("day") {
            Some(String(d)) => d
            _ => ""
          },
          details_pending=mode == "settings-usage-details-pending",
        ),
      )
    "archive" => Some(fx_archive())
    "memory" => Some(fx_memory())
    // (settings-me-reading: where the account is signed in not read yet, its wait line shown)
    "loginSessions" if mode.has_prefix("settings-me-reading") => None
    "loginSessions" =>
      Some([
        obj([("id", str("l1")), ("name", str("Pixel 9 · still.fail")), ("current", Json::boolean(true)), ("time", obj([("created_at", stamp_of("3 天前")), ("expires_at", stamp_of("", until="27 天后"))]))]),
        obj([("id", str("l2")), ("name", str("Chrome · macOS")), ("current", Json::boolean(false)), ("time", obj([("created_at", stamp_of("2 周前")), ("expires_at", stamp_of("", until="16 天后"))]))]),
      ])
    "notify" => {
      // notifications off (slice 10's settings-notify-off)
      let on = !mode.has_prefix("settings-notify-off")
      Some(
        obj([
          ("on", Json::boolean(on)),
          ("asked", Json::boolean(true)),
          ("push", Json::boolean(false)),
          ("show", []),
          ("kinds", obj([("wait", Json::boolean(true)), ("failed", Json::boolean(true)), ("done", str("away")), ("message", Json::boolean(false))])),
          ("preview", Json::boolean(true)),
          ("permission", str(if mode.has_prefix("settings-notify-denied") { "denied" } else { "granted" })),
          // (the account's two workspaces, 个人 turned off)
          ("muted", [str("ws2")]),
          (
            "workspaces",
            [
              obj([("id", str("ws1")), ("name", str("星火工作室")), ("on", Json::boolean(true))]),
              obj([("id", str("ws2")), ("name", str("个人")), ("on", Json::boolean(false))]),
            ],
          ),
        ]),
      )
    }
    "doing" => Some(obj([("doing", if fx.protecting {
      [obj([("call", str("lock.joinStation")), ("stage", str("running")), ("params", obj([("workspace", str("ws1")), ("station", str("st2"))]))])]
    } else if fx.key_giving {
      [obj([("call", str("vault.addDevice")), ("stage", str("running")), ("params", obj([("workspace", str("ws1")), ("vault", str("v1")), ("device", str("d-new"))]))])]
    } else {
      []
    })]))
    "lockDraft" =>
      Some(
        obj([
          ("available", Json::boolean(true)),
          ("loading", Json::boolean(false)),
          ("canSign", Json::boolean(true)),
          ("owner", Json::boolean(true)),
          ("ready", Json::boolean(true)),
          (
            "members",
            [
              obj([("sub", str("u1")), ("email", str("lin@example.com")), ("name", str("林")), ("role", str("owner")), ("nameText", str("林")), ("roleText", str("Owner"))]),
              obj([("sub", str("u2")), ("email", str("ana@example.com")), ("name", str("Ana")), ("role", str("admin")), ("nameText", str("Ana")), ("roleText", str("管理员"))]),
            ],
          ),
          (
            "devices",
            [
              obj([("id", str("d1")), ("person", str("林")), ("kind", str("app")), ("label", str("这台手机")), ("older", Json::boolean(false)), ("current", Json::boolean(true)), ("on", Json::boolean(true)), ("fixed", Json::boolean(true)), ("nameText", str("林 · 此设备")), ("howText", str("客户端 · 受信任"))]),
              obj([("id", str("d3")), ("person", str("Ana")), ("kind", str("app")), ("label", str("MacBook")), ("older", Json::boolean(false)), ("current", Json::boolean(false)), ("on", Json::boolean(true)), ("fixed", Json::boolean(false)), ("nameText", str("Ana · MacBook")), ("howText", str("客户端"))]),
            ],
          ),
          (
            "stations",
            [
              obj([("id", str("st1")), ("name", str("Willow")), ("version", str("0.1.4600")), ("state", str("ok")), ("on", Json::boolean(true)), ("fixed", Json::boolean(false))]),
              obj([("id", str("st2")), ("name", str("Maple")), ("state", str("offline")), ("on", Json::boolean(false)), ("fixed", Json::boolean(true)), ("stateText", str("离线 · 上线后可在此保护"))]),
            ],
          ),
        ]),
      )
    _ => None
  }
}

///|
/// A made-up settings call (a station renamed, a chat restored, a station's memory read), None for one these do not
/// take.
pub fn fixture_call(name : String, params : Json) -> Result[Json, Json]? {
  let p = Some(params)
  match rigs_fixture_call(name, p) {
    Some(r) => return Some(r)
    None => ()
  }
  match devices_fixture_call(name, p) {
    Some(r) => return Some(r)
    None => ()
  }
  match name {
    "workspace.renameStation" => {
      // a name, or (the mark picker's) a mark
      match field(p, "icon") {
        Some(_) => fx.marks[text(p, "station")] = text(p, "icon")
        None => fx.names[text(p, "station")] = text(p, "name")
      }
      fx_changed()
      Some(Ok(obj([])))
    }
    "chat.archive" if field(p, "archived") is Some(False) => {
      fx.restored[text(p, "session")] = true
      fx_changed()
      Some(Ok(obj([])))
    }
    // still.fail's buddies a Slack app can wear (the core's own list, web/public/avatars/index.json: three of it)
    "buddies" =>
      Some(
        Ok(
          Json::array([
            obj([("id", str("backend")), ("label", str("后端接口")), ("bg", str("#B582EB"))]),
            obj([("id", str("mobile")), ("label", str("移动应用")), ("bg", str("#B9D84A"))]),
            obj([("id", str("documentation")), ("label", str("写文档")), ("bg", str("#F3CA43"))]),
          ]),
        ),
      )
    // lin's secrets from before security mode encrypted into their vault
    "vault.migrate" => {
      fx.plain_left = 0
      fx_changed()
      Some(Ok(obj([])))
    }
    // the device waiting for a key given it (the vault's key unsealed here), or its prompt put away: no longer shown
    "vault.addDevice" | "vault.hidePrompt" => {
      fx.key_ask = false
      fx.key_ask_ended = if name == "vault.addDevice" { "give" } else { "hide" }
      fx_changed()
      Some(Ok(obj([("added", Json::number(1.0))])))
    }
    // this device asking for the keys it lacks: its other devices told
    "vault.ask" => Some(Ok(obj([("asked", Json::number(1.0))])))
    // the new device turned away, or its prompt closed: no longer shown
    "lockPrompt.deny" | "lockPrompt.hide" => {
      fx.pairing = false
      fx.pair_ended = if name == "lockPrompt.deny" { "deny" } else { "hide" }
      fx_changed()
      Some(Ok(obj([])))
    }
    // a skill shared with the workspace's other stations, or no longer
    "skill.share" => {
      fx.skills_shared[text(p, "name")] = flag(p, "on")
      fx_changed()
      Some(Ok(obj([])))
    }
    "cache.usage" =>
      Some(
        Ok(
          obj([
            (
              "chats",
              Json::array(([
                // a PDF opened, 5 minutes ago; a video, 12 of its 48 MB come
                obj([
                  ("station", str("ws1/st1")),
                  ("thread", Json::number(1.0)),
                  ("title", str("整理发布清单")),
                  ("sessions", ["s-c1"]),
                  ("bytes", Json::number(2400000.0)),
                  (
                    "files",
                    Json::array(
                      [
                        fx_kept_file("s-c1", "季度报告.pdf", 3355443.0, 3355443.0, -300000.0),
                        fx_kept_file("s-c1", "演示录屏.mp4", 50331648.0, 12582912.0, -7200000.0),
                      ].filter_map(fn(f) { f }),
                    ),
                  ),
                ]),
                obj([("station", str("ws1/st1")), ("thread", Json::number(4.0)), ("title", str("给设置页加一个深色模式开关")), ("sessions", ["s-c4"]), ("bytes", Json::number(860000.0))]),
                obj([("station", str("ws1/st2")), ("thread", Json::number(3.0)), ("title", str("夜里的构建又失败了")), ("sessions", ["s-c3"]), ("bytes", Json::number(41000.0))]),
                ] +
                fx_kept_many())
                |> fx_kept_most_first,
              ),
            ),
            ("drive", Json::number(fx.drive_kept)),
            // one of a chat no longer kept here, 3 days ago
            ("loose", Json::array([fx_kept_file("s-old", "旧日志.zip", 921600.0, 921600.0, -3.0 * 86400000.0, station="ws1/st2")].filter_map(fn(f) { f }))),
          ]),
        ),
      )
    // a failed pending change read, dropped (a waiting one stays)
    "lock.pendingDismiss" => {
      let id = text(p, "id")
      if fx_pending_rows().iter().any(fn(r) { text(Some(r), "id") == id && text(Some(r), "state") == "failed" }) {
        fx.pending.retain(fn(x) { x != id })
        fx_changed()
      }
      Some(Ok(Json::null()))
    }
    "drive.kept.clear" => {
      fx.drive_kept = 0.0
      fx_changed()
      Some(Ok(Json::null()))
    }
    "cache.file.clear" => {
      fx.kept_cleared.push(text(p, "name"))
      fx_changed()
      Some(Ok(Json::null()))
    }
    "machineSessions.list" => Some(Ok(obj([("sessions", [])])))
    "workspace.enroll" =>
      Some(
        Ok(
          obj([
            ("token", str("made-up")),
            ("install", str("curl -fsSL https://still.fail/install.sh | sh -s -- 4f7c2a9e1b")),
            ("installWindows", str("& ([scriptblock]::Create((irm https://still.fail/install.ps1))) 4f7c2a9e1b")),
            ("command", str("stillfail station enroll https://still.fail 4f7c2a9e1b")),
          ]),
        ),
      )
    "software.auto" => {
      fx.auto = flag(p, "on")
      fx_changed()
      Some(Ok(obj([])))
    }
    "network.setCongestion" => {
      fx.congestion = text(p, "congestion")
      Some(Ok(obj([])))
    }
    "station.restart" => Some(Ok(obj([("restarting", Json::boolean(true))])))
    "elevation.set" => {
      match fx.elevation {
        Some(Object(e)) => {
          let shown = e.copy()
          shown["on"] = Json::boolean(flag(p, "on"))
          shown["busy"] = Json::boolean(true)
          shown["canChange"] = Json::boolean(false)
          fx.elevation = Some(Json::object(shown))
          fx_changed()
        }
        _ => ()
      }
      Some(Ok(obj([])))
    }
    "context.setAfresh" => {
      match field(p, "afreshWhenCold") {
        Some(True) => fx.afresh = true
        Some(False) => fx.afresh = false
        _ => ()
      }
      match field(p, "afreshAbove") {
        Some(Number(above, ..)) => fx.afresh_above = above
        _ => ()
      }
      fx_changed()
      Some(Ok(obj([])))
    }
    "diagnostics.setLogs" => {
      fx.logs = flag(p, "logs")
      fx_changed()
      Some(Ok(obj([])))
    }
    "software.check" | "software.update" | "software.channel" | "search.setPersonal" | "permissions.request" =>
      Some(Ok(obj([])))
    "agentEnv.form.open" | "agentEnv.form.edit" | "agentEnv.form.drop" | "agentEnv.form.save" => Some(Ok(obj([])))
    // ChatGPT 团队's models named by hand, one taken off
    "profile.put" if text(p, "id") == "cx" && field(field(p, "input"), "models") is Some(Array(_)) => {
      let named = items(field(p, "input"), "models").filter_map(fn(m) { if m is String(m) { Some(m) } else { None } })
      fx.models_added.retain(fn(m) { named.contains(m) })
      fx_changed()
      Some(Ok(obj([])))
    }
    "profile.put" if text(p, "id") == "k2" && has(field(p, "input"), "enabled") => {
      fx.key_enabled = flag(field(p, "input"), "enabled")
      fx_changed()
      Some(Ok(obj([])))
    }
    "profile.put" if text(p, "id") == "bx" && has(field(p, "input"), "enabled") => {
      fx.copy_enabled = flag(field(p, "input"), "enabled")
      fx_changed()
      Some(Ok(obj([])))
    }
    "profile.quota" | "profile.check" | "profile.put" => Some(Ok(obj([])))
    // the subscription's sign-in begun: as settings-profile-login has it, waiting on the code
    "profile.login" => {
      fx.login = "needs_code"
      fx_changed()
      Some(Ok(obj([])))
    }
    "profile.resetQuota" if text(p, "reset") == "model" => {
      fx.fable_used = true
      fx_changed()
      Some(Ok(obj([])))
    }
    "profile.resetQuota" => {
      fx.resets_used += 1
      fx_changed()
      Some(Ok(obj([])))
    }
    "profile.addModel" => {
      if text(p, "id") == "cx" {
        fx.models_added.push(text(p, "model"))
      }
      fx_changed()
      Some(Ok(obj([])))
    }
    // a new connect's wizard gone on or back (its back as the core's: the app's step back to the workspace's, the first
    // closing it)
    "connect.flow.go" => {
      let to = text(field(p, "input"), "to")
      let target = match (to, fx_connect_step.val) {
        ("back", "app") => "team"
        ("back", "feishuScan") => "feishuWay"
        ("back", _) => "close"
        (step, _) => step
      }
      if target == "close" {
        Some(Ok(obj([("close", Json::boolean(true))])))
      } else {
        fx_connect_step.val = target
        fx_changed()
        Some(Ok(obj([])))
      }
    }
    // the drafts' forms (a new profile's, a new connect's, the decisions' and the archive policy's), opened and edited
    // an Anthropic plan's sign-in for a new profile, begun (settings-new-profile-login…)
    "login.new" if fx.new_login => Some(Ok(obj([("id", str("login-new")), ("job", fx_login_job("login-new", "needs_code"))])))
    "profile.flow.open" | "profile.flow.edit" | "profile.flow.drop" | "connect.flow.open" | "connect.flow.edit"
    | "connect.flow.drop" | "automaticDecisions.form.open" | "automaticDecisions.form.edit"
    | "automaticDecisions.form.drop" | "automaticDecisions.policy.open" | "automaticDecisions.policy.drop" =>
      Some(Ok(obj([])))
    // people added: each as one who has not signed in yet
    "workspace.addMembers" =>
      Some(Ok(obj([("joined", []), ("added", field(p, "emails").unwrap_or(Json::array([]))), ("already", [])])))
    _ => None
  }
}

///|
/// The trusted devices a waiting device dials (the lock's `me.pair.approvers`): a phone and a laptop, the phone
/// showing the code where `code`.
fn waiting_approvers(code : Bool) -> Json {
  [
    obj([
      ("id", str("d-phone")),
      ("showing", Json::boolean(code)),
      ("kind", str("phone")),
      ("nameText", str("Pixel 9")),
    ]),
    obj([
      ("id", str("d-laptop")),
      ("showing", Json::boolean(false)),
      ("kind", str("computer")),
      ("nameText", str("林的 MacBook Pro")),
    ]),
  ]
}

///|
/// The lock as a device not confirmed in it has it (MBUI_FIXTURE=lock-waiting, lock-finding, lock-code, lock-wrong,
/// lock-wrong-gone, lock-checking, lock-none, lock-failed, lock-nocode, lock-security, each also -dark: its waiting page
/// asking, finding, the code being typed, typed wrong (or the device showing it gone), being checked, no device found,
/// the pairing failed (lock-elsewhere: approved in another workspace, not this one), this device without
/// its code yet; its security page): this device waiting, not a signer. lock-upgrade: in the lock but not signing (its key lost), the code being typed on its
/// security page.
fn waiting_lock(mode : String) -> Json {
  let mode = if mode.has_suffix("-dark") { mode.unsafe_substring(start=0, end=mode.length() - 5) } else { mode }
  let pair = match mode {
    // (the devices it dials, the core's rows; one showing the code, once it does)
    "lock-finding" => obj([("state", str("finding")), ("approvers", waiting_approvers(false))])
    "lock-code" | "lock-upgrade" =>
      obj([("state", str("code")), ("left", Json::number(3.0)), ("untilText", str("14:05 前有效")), ("approvers", waiting_approvers(true))])
    "lock-wrong" => obj([("state", str("wrong")), ("left", Json::number(2.0)), ("untilText", str("14:05 前有效"))])
    "lock-wrong-gone" =>
      obj([("state", str("wrong")), ("left", Json::number(2.0)), ("error", str("安全码不对，或显示它的设备已断开，还可以试 2 次")), ("untilText", str("14:05 前有效"))])
    "lock-checking" => obj([("state", str("checking")), ("left", Json::number(3.0))])
    "lock-none" => obj([("state", str("none")), ("approvers", waiting_approvers(false))])
    "lock-failed" => obj([("state", str("failed")), ("error", str("配对超时"))])
    "lock-elsewhere" =>
      obj([("state", str("failed")), ("devices", Json::number(0.0)), ("error", str("此设备已在「日常」获批，在这里还需要此 workspace 的管理员或你在这里的受信任设备批准"))])
    _ => Json::null()
  }
  // in the lock, its key since lost (a phone moved to a new one): made one that signs on its security page
  let upgrade = mode == "lock-upgrade"
  let code = if mode == "lock-nocode" { "" } else { "Q4K-7PM" }
  obj([
    ("available", Json::boolean(true)),
    ("locked", Json::boolean(true)),
    ("notice", Json::boolean(false)),
    ("role", str("owner")),
    ("manages", Json::boolean(true)),
    ("owner", Json::boolean(true)),
    ("canSign", Json::boolean(true)),
    ("signs", Json::boolean(false)),
    ("signers", Json::number(5.0)),
    ("protected", Json::number(4.0)),
    ("attention", Json::number(0.0)),
    (
      "me",
      obj([
        ("device", str("d-me")),
        ("code", str(code)),
        ("kind", str("app")),
        ("confirmed", Json::boolean(upgrade)),
        ("waiting", Json::boolean(!upgrade)),
        ("unsigned", Json::boolean(upgrade)),
        ("pair", pair),
      ]),
    ),
    (
      "members",
      [
        obj([
          ("sub", str("u1")),
          ("email", str("lin@example.com")),
          ("name", str("林")),
          ("role", str("owner")),
          ("you", Json::boolean(true)),
          ("nameText", str("林")),
          ("roleText", str("Owner")),
          (
            "groups",
            [
              obj([
                ("appText", str("still.fail Android")),
                ("devices", [
                  obj([("id", str("d1")), ("kind", str("app")), ("label", str("still.fail Android · OPPO PLP110")), ("signs", Json::boolean(true)), ("older", Json::boolean(false)), ("mine", Json::boolean(false)), ("renewSoon", Json::boolean(false)), ("recent", Json::boolean(false)), ("lastSeen", Json::number(1760000000.0)), ("removable", Json::boolean(false)), ("nameText", str("OPPO PLP110")), ("fullText", str("OPPO PLP110 · still.fail Android")), ("metaText", str("一天内使用过 · 受信任"))]),
                ]),
              ]),
            ],
          ),
        ]),
      ],
    ),
    ("stations", []),
    ("renew", []),
  ])
}

///|
/// The dialog of the desktop's pages a fixture's mode puts up ("" none), taken once: the desktop's page puts it up
/// once it is drawn with what it needs.
pub fn fixture_copies() -> Json? {
  fx.copies
}

///|
/// What a fixture's mode puts up over the settings (MBUI_FIXTURE=settings-…), said once.
pub fn fixture_desk() -> String {
  let d = fixture_open.desk
  fixture_open.desk = ""
  d
}

///|
/// The sheet a fixture's mode puts up, once its page is drawn with what it needs (`page`).
fn fixture_sheet(core : Core, here : Here) -> Unit {
  let what = fixture_open.sheet
  if what == "" {
    return
  }
  fixture_open.sheet = ""
  match what {
    "mark" => {
      let s = Some(fx_station("ws1/st1"))
      open_mark_pick(core, text(s, "name"), text(s, "emoji"), text(s, "icon"), "", fn(_, _, _) {  })
    }
    "add-people" => open_add_people(core, here, workspace_view(core, here).value)
    "workspace-mark" => open_mark_pick(core, "星火工作室", "", "glyph:rocket:orange", "", fn(_, _, _) {  })
    "add" | "add-existing" | "add-command" => {
      open_add_station(core, here, ["st1", "st2"], existing=what == "add-existing")
      if what == "add-command" {
        adding.made.set(Some(
          (
            "curl -fsSL https://still.fail/install.sh | sh -s -- 4f7c2a9e1b",
            "& ([scriptblock]::Create((irm https://still.fail/install.ps1))) 4f7c2a9e1b",
          ),
        ))
      }
    }
    _ => ()
  }
}

///|
/// A page's list scrolled as a fixture's mode asks (its first frames), by its key: to its block, or (a block under 0,
/// the list's `rows` known) its last.
fn fixture_scroll(c : @ui.Ctx, key : String, rows? : Int = 0) -> Unit {
  if fixture_open.list == key && fixture_open.frames < 4 {
    fixture_open.frames += 1
    // (the list asks for the frames its scroll takes)
    c.list_scroll_to(key, if fixture_open.block < 0 { rows - 1 } else { fixture_open.block })
  }
}

///|
/// Made-up recovery words for the words' screenshot (no one's: the words of a fixture are not a key to anything).
fn fx_words() -> Array[String] {
  [
    "amber", "basin", "cedar", "delta", "ember", "fable", "grove", "harbor", "island", "jasper", "kettle", "lantern", "meadow",
    "nectar", "orbit", "pebble", "quarry", "river", "saddle", "timber", "umbra", "velvet", "willow", "zephyr",
  ]
}

///|
/// A subscription's sign-in under way in `state` (a profile's, or a new one's by its login's id): its page, and that
/// the station's own browser can open it where the fixture says so.
fn fx_login_job(profile : String, state : String) -> Json {
  let o = [
    ("profile", str(profile)),
    ("runtime", str(if profile == "cx" { "codex" } else { "claude" })),
    ("state", str(state)),
    ("url", str("https://claude.example/oauth/authorize")),
    ("startedAt", Json::number(0.0)),
    ("expiresAt", Json::number(0.0)),
  ]
  if fx.login_station {
    o.push(("browser", Json::boolean(true)))
  }
  obj(o)
}

///|
/// A new profile's draft at an Anthropic plan's sign-in (`profileFlow`, settings-new-profile-login…): 连接 Anthropic.
fn fx_profile_flow_plan() -> Json {
  obj([
    ("step", str("connect")),
    ("station", str("ws1/st1")),
    ("title", str("连接 Anthropic")),
    ("hint", str("")),
    ("method", str("plan")),
    ("tile", obj([("id", str("anthropic")), ("name", str("Anthropic")), ("kind", str("subscription")), ("runtime", str("claude")), ("mark", str("anthropic"))])),
    ("signIn", obj([("runtime", str("claude")), ("provider", str("Claude")), ("access", str(""))])),
    ("groups", []),
    ("choices", []),
    ("showEndpoint", Json::boolean(false)),
    ("endpoint", str("")),
    ("protocols", []),
    ("showKey", Json::boolean(false)),
    ("key", str("")),
    ("keyLabel", str("")),
    ("canSubmit", Json::boolean(false)),
    ("pending", Json::boolean(false)),
    ("submitLabel", str("")),
    ("usesLine", str("")),
  ])
}

///|
/// A new profile's draft at its first step (`profileFlow`): the providers by group.
fn fx_profile_flow(hermes? : Bool = false) -> Json {
  let provider = fn(id : String, name : String, group : String, runtime : String, mark : String) {
    obj([("id", str(id)), ("name", str(name)), ("group", str(group)), ("kind", str("api-provider")), ("runtime", str(runtime)), ("mark", str(mark))])
  }
  let groups : Array[Json] = [
    obj([
      ("id", str("labs")),
      ("title", str("模型厂商")),
      (
        "providers",
        [
          provider("openai", "OpenAI", "labs", "codex", "openai"),
          provider("anthropic", "Anthropic", "labs", "claude", "anthropic"),
          provider("deepseek", "DeepSeek", "labs", "", "deepseek"),
          provider("kimi", "Kimi", "labs", "", "kimi"),
        ],
      ),
    ]),
    obj([("id", str("gateways")), ("title", str("中转站")), ("providers", [provider("openrouter", "OpenRouter", "gateways", "", "openrouter")])]),
  ]
  if hermes {
    groups.push(obj([
      ("id", str("local")), ("title", str("自定义变量")),
      ("providers", [obj([
        ("id", str("env-hermes")), ("name", str("Hermes Agent")), ("group", str("local")),
        ("kind", str("env")), ("runtime", str("hermes")),
      ])]),
    ]))
  }
  obj([
    ("step", str("pick")),
    ("station", str("ws1/st1")),
    ("title", str("选择服务商")),
    ("hint", str("订阅和 API key 都在这里添加，选择服务商开始")),
    ("groups", Json::array(groups)),
    ("choices", []),
    ("showEndpoint", Json::boolean(false)),
    ("endpoint", str("")),
    ("protocols", []),
    ("showKey", Json::boolean(false)),
    ("key", str("")),
    ("keyLabel", str("")),
    ("canSubmit", Json::boolean(false)),
    ("pending", Json::boolean(false)),
    ("submitLabel", str("")),
    ("usesLine", str("")),
  ])
}

///|
/// Whether the run's models are many (MBUI_FIXTURE=settings-run-models).
let fx_many_models : Ref[Bool] = Ref(false)

///|
/// Whether many chats are kept (MBUI_FIXTURE=settings-kept-many): 200 more after the three, each with a few KB.
let fx_many_kept : Ref[Bool] = Ref(false)

///|
/// The chats kept after the three when many are (fx_many_kept): 测试会话 1 to 200.
fn fx_kept_many() -> Array[Json] {
  if !fx_many_kept.val {
    return []
  }
  Array::makei(200, fn(i) -> Json {
    obj([
      ("station", str("ws1/st2")),
      ("thread", Json::number((100 + i).to_double())),
      ("title", str("测试会话 \{i + 1}")),
      ("sessions", Json::array([str("s-m\{i}")])),
      ("bytes", Json::number((4096 * (i + 1)).to_double())),
    ])
  })
}

///|
/// The chats kept, the one keeping most (its messages and its files) first, as the core gives them.
fn fx_kept_most_first(chats : Array[Json]) -> Array[Json] {
  let all = fn(x : Json) {
    items(Some(x), "files").fold(init=number(Some(x), "bytes"), fn(s, f) { s + number(Some(f), "bytes") })
  }
  let out = chats.copy()
  out.sort_by(fn(a, b) { all(b).compare(all(a)) })
  out
}

///|
/// A chat's agent as it runs and as it is to run (`pick` of `session:<key>`, MBUI_FIXTURE=settings-run): its effort
/// raised to high, the rest as it was.
fn fx_session_pick() -> Json {
  let model = obj([("model", str("claude-opus-5-5")), ("name", str("Opus 5.5")), ("maker", obj([("id", str("anthropic"))]))])
  let m = fn(id : String, name : String, family : String) {
    obj([("model", str(id)), ("name", str(name)), ("family", str(family)), ("maker", obj([("id", str("anthropic"))]))])
  }
  // (MBUI_FIXTURE=settings-run-models: many, by series, one borrowed from Maple)
  let options : Json = if fx_many_models.val {
    [
      obj([("model", str("claude-opus-5-5")), ("name", str("Opus 5.5")), ("family", str("Opus")), ("maker", obj([("id", str("anthropic"))]))]),
      m("claude-opus-5-1", "Opus 5.1", "Opus"),
      m("claude-opus-5", "Opus 5", "Opus"),
      m("claude-sonnet-5-5", "Sonnet 5.5", "Sonnet"),
      m("claude-sonnet-5", "Sonnet 5", "Sonnet"),
      m("claude-sonnet-4-5", "Sonnet 4.5", "Sonnet"),
      m("claude-haiku-4-5", "Haiku 4.5", "Haiku"),
      m("claude-haiku-4", "Haiku 4", "Haiku"),
      obj([
        ("model", str("claude-fable-5-1")),
        ("name", str("Fable 5.1")),
        ("family", str("Fable")),
        ("maker", obj([("id", str("anthropic"))])),
        ("availability", str("borrowable")),
        ("fromStation", obj([("name", str("Maple")), ("icon", str("glyph:laptop:teal"))])),
        ("fromText", str("借自 Maple")),
      ]),
    ]
  } else {
    [model]
  }
  obj([
    ("value", obj([("model", str("claude-opus-5-5")), ("runtime", str("claude"))])),
    ("draft", obj([("model", str("claude-opus-5-5")), ("runtime", str("claude")), ("effort", str("high"))])),
    ("option", str("claude-opus-5-5")),
    ("options", options),
    ("maker", obj([("id", str("anthropic"))])),
    ("modelText", str("Opus 5.5")),
    ("efforts", ["low", "medium", "high"]),
    ("was", ["Opus 5.5", "默认深度", "自动 · Claude 主账号"]),
    ("becomes", ["Opus 5.5", "high", "自动 · Claude 主账号"]),
    ("accountText", str("自动分配")),
    ("accountNote", str("Claude 主账号 · 5 小时窗口已用 62%")),
    ("repick", str("重新分配")),
    // (PickProfile: its kind, its runtime, its allowance as its chips draw it)
    (
      "accounts",
      [
        obj([
          ("id", str("p1")),
          ("name", str("Claude 主账号")),
          ("kind", str("subscription")),
          ("runtime", str("claude")),
          (
            "quota",
            obj([
              ("state", str("ok")),
              ("windows", [obj([("mark", str("5H")), ("left", Json::number(38.0)), ("level", str("ok"))]), obj([("mark", str("W")), ("left", Json::number(70.0)), ("level", str("ok"))])]),
            ]),
          ),
        ]),
      ],
    ),
    ("changed", Json::boolean(true)),
    ("saveText", str("改成 Opus 5.5 · high · 自动分配")),
  ])
}

///|
/// A new connect on Feishu's path (MBUI_FIXTURE=settings-new-connect-platform, -scan): the platform picked (飞书), or
/// the bot being made by scanning, its QR code waiting.
fn fx_feishu_flow(step : String) -> Json {
  let scan = step == "feishuScan"
  let feishu : Array[(String, Json)] = [
    ("way", str("scan")),
    ("appId", str("")),
    ("appSecret", str("")),
    ("lark", Json::boolean(false)),
    ("canVerify", Json::boolean(false)),
    ("verified", Json::boolean(false)),
    ("errors", []),
    ("failed", Json::boolean(false)),
    ("creating", Json::boolean(false)),
    ("error", Json::null()),
    ("connect", Json::null()),
  ]
  if scan {
    feishu.push(("registration", obj([("state", str("waiting")), ("url", str("https://open.feishu.cn/page/launcher?code=made-up"))])))
    feishu.push(("stateText", str("使用飞书扫描二维码，按提示创建机器人")))
    feishu.push(("qr", fx_qr(25)))
  }
  obj([
    ("step", str(step)),
    ("title", str(if scan { "扫码创建" } else { "选择平台" })),
    ("back", str(if scan { "feishuWay" } else { "close" })),
    ("number", Json::number(if scan { 4.0 } else { 1.0 })),
    ("total", Json::number(4.0)),
    ("mobile", Json::boolean(true)),
    ("platforms", [str("slack"), str("feishu")]),
    ("platform", str("feishu")),
    ("feishu", obj(feishu)),
    ("mode", str("multi-session")),
    ("requireMention", Json::boolean(true)),
    ("noProfile", Json::boolean(false)),
    ("canCreate", Json::boolean(true)),
  ])
}

///|
/// A made-up QR code's modules, `n` a side (the three finder squares, the rest a fixed scatter): only drawn, never
/// read.
fn fx_qr(n : Int) -> Json {
  let rows : Array[Json] = []
  for y in 0..<n {
    let row = StringBuilder()
    for x in 0..<n {
      let finder = fn(ox : Int, oy : Int) {
        let dx = x - ox
        let dy = y - oy
        if dx < 0 || dy < 0 || dx > 6 || dy > 6 {
          None
        } else {
          let ring = if dx < dy { dx } else { dy }
          let far = if 6 - dx < 6 - dy { 6 - dx } else { 6 - dy }
          let d = if ring < far { ring } else { far }
          Some(d != 1)
        }
      }
      let dark = match finder(0, 0) {
        Some(b) => b
        None =>
          match finder(n - 7, 0) {
            Some(b) => b
            None =>
              match finder(0, n - 7) {
                Some(b) => b
                None => (x * 7 + y * 13 + x * y * 3) % 5 < 2
              }
          }
      }
      row.write_char(if dark { '1' } else { '0' })
    }
    rows.push(str(row.to_string()))
  }
  obj([("size", Json::number(n.to_double())), ("rows", Json::array(rows))])
}

///|
/// A use, its figures and each said (ResourceUse): CPU, memory, the network's and the disk's rates.
fn fx_use(cpu : Double, memory : Double, net : Double, disk : Double, texts : (String, String, String, String)) -> Json {
  let (cpu_text, memory_text, net_text, disk_text) = texts
  obj([
    ("cpu", Json::number(cpu)),
    ("memory", Json::number(memory)),
    ("netIn", Json::number(net / 2.0)),
    ("netOut", Json::number(net / 2.0)),
    ("net", Json::number(net)),
    ("diskRead", Json::number(disk)),
    ("diskWrite", Json::number(0.0)),
    ("disk", Json::number(disk)),
    ("cpuText", str(cpu_text)),
    ("memoryText", str(memory_text)),
    ("netText", str(net_text)),
    ("diskText", str(disk_text)),
  ])
}

///|
/// What still.fail uses of Willow's machine now (ResourcesView), as a busy Mac says it: its four totals with what is
/// under each (the network and the disk both read), two chats' agents (one titled at length) and the station, each with
/// its processes.
fn fx_resources() -> Json {
  let process = fn(key : String, pid : Double, name : String, endable : Bool, u : Json) {
    obj([("key", str(key)), ("pid", Json::number(pid)), ("name", str(name)), ("endable", Json::boolean(endable)), ("use", u)])
  }
  let tile = fn(key : String, label : String, value : String, sub : String, points : Array[Double]) {
    obj([("key", str(key)), ("label", str(label)), ("value", str(value)), ("sub", str(sub)), ("points", Json::array(points.map(x => Json::number(x))))])
  }
  let chat = fx_use(25.9, 59.0e6, 0.0, 2.9e6, ("25.9%", "59 MB", "0 B/s", "2.9 MB/s"))
  let notes = fx_use(14.1, 980.0e6, 0.0, 13.0e3, ("14.1%", "980 MB", "0 B/s", "13 KB/s"))
  let station = fx_use(2.8, 363.0e6, 56.0e3, 0.0, ("2.8%", "363 MB", "56 KB/s", "0 B/s"))
  obj([
    ("wait", obj([("reading", Json::boolean(false)), ("text", str("")), ("failing", [])])),
    ("empty", Json::boolean(false)),
    ("net", Json::boolean(true)),
    ("disk", Json::boolean(true)),
    ("everyMs", Json::number(5000.0)),
    (
      "tiles",
      [
        tile("cpu", "CPU", "20.5%", "占 10 核的 2%", [12.0, 18.0, 15.0, 22.0, 20.5]),
        tile("memory", "内存", "508 MB", "占 32 GB 的 2%", [480.0, 495.0, 500.0, 504.0, 508.0]),
        tile("disk", "磁盘", "↓ 2.9 MB/s", "↑ 13 KB/s", [9.0, 1.0, 1.2, 0.9, 2.9]),
        tile("net", "网络", "↓ 1.6 KB/s", "↑ 410 B/s", [0.8, 2.4, 1.1, 1.9, 1.6]),
      ],
    ),
    ("kinds", [obj([("key", str("chat")), ("label", str("对话"))]), obj([("key", str("station")), ("label", str("Station"))])]),
    (
      "groups",
      [
        obj([
          ("key", str("chat:c1")),
          ("kind", str("chat")),
          ("title", str("修一下登录")),
          ("kindText", str("对话")),
          ("chat", obj([("station", str("ws1/st1")), ("session", str("s1"))])),
          ("station", str("ws1/st1")),
          ("session", str("s1")),
          ("use", chat),
          (
            "processes",
            [
              process("p1", 4211.0, "claude", false, fx_use(12.0, 41.0e6, 0.0, 1.9e6, ("12.0%", "41 MB", "0 B/s", "1.9 MB/s"))),
              process("p2", 4290.0, "node", true, fx_use(13.9, 18.0e6, 0.0, 1.0e6, ("13.9%", "18 MB", "0 B/s", "1.0 MB/s"))),
            ],
          ),
        ]),
        obj([
          ("key", str("chat:c2")),
          ("kind", str("chat")),
          ("title", str("把发版日志按平台分开写清楚，再给每一条补上改前改后的截图")),
          ("kindText", str("对话")),
          ("chat", obj([("station", str("ws1/st1")), ("session", str("s2"))])),
          ("station", str("ws1/st1")),
          ("session", str("s2")),
          ("use", notes),
          ("processes", [process("p4", 5120.0, "claude", false, notes)]),
        ]),
        obj([
          ("key", str("station")),
          ("kind", str("station")),
          ("title", str("Station")),
          ("kindText", str("")),
          ("station", str("ws1/st1")),
          ("use", station),
          ("processes", [process("p3", 812.0, "stillfail", false, station)]),
        ]),
      ],
    ),
    (
      "stations",
      [
        obj([
          ("station", str("ws1/st1")),
          ("net", Json::boolean(true)),
          ("use", fx_use(20.5, 508.0e6, 1.6e3, 2.9e6, ("20.5%", "508 MB", "1.6 KB/s", "2.9 MB/s"))),
        ]),
      ],
    ),
    ("notes", []),
    ("basis", str("按 Activity Monitor 的口径：CPU 100% 是一个核")),
  ])
}

///|
/// 共享调试 as a fixture's mode has it (MBUI_FIXTURE=settings-adb-<off|unpaired|pairing|connected|failed|chats|idle|desk>;
/// "" not lent).
let fx_adb : Ref[String] = Ref("")

///|
/// The core's `adbShare` for fx_adb: lent to Willow (ws1/st1) and how its adb holds the phone, the ports the app found.
fn fx_adb_share() -> Json {
  let lent = fn(adb : String, fields : Array[(String, Json)]) {
    obj(
      [
        ("sharing", Json::boolean(true)),
        ("station", str("ws1/st1")),
        ("phase", str("offered")),
        ("serial", str("127.0.0.1:37762")),
        ("adb", str(adb)),
        ("tunnels", Json::number(0.0)),
        ("connectPort", Json::number(41239.0)),
      ]..append(fields),
    )
  }
  // lent for a chat's grant (the station's adb as `adb` holds the phone), as a core of grants says it: the first lending
  // at its top, each in `lends`
  let granted = fn(adb : String, fields : Array[(String, Json)]) {
    lent(adb, [
      ("on", Json::boolean(true)),
      ("lends", Json::array([obj([("station", str("ws1/st1")), ("phase", str("offered")), ("adb", str(adb)), ("serial", str("127.0.0.1:37762")), ("tunnels", Json::number(0.0))])])),
      ("grants", Json::array([obj([("station", str("ws1/st1")), ("id", str("p-1")), ("session", str("s-c1")), ("chatTitle", str("通知权限检查")), ("reason", str("装上刚编好的测试包，看首屏在折叠屏展开时排得对不对")), ("status", str("granted")), ("scope", str("chat"))])])),
      ..fields,
    ])
  }
  // a device on the person's own lock
  let device = fn(key : String, label : String, me : Bool) { obj([("key", str(key)), ("label", str(label)), ("me", Json::boolean(me))]) }
  match fx_adb.val {
    // the person's own lock on 共享调试: this device on it (its devices listed, two), or to be approved by one
    "lock-member" =>
      lent("connected", [
        ("personal", Json::array([obj([("sub", str("s")), ("email", str("lin@example.com")), ("standing", str("member")), ("devices", Json::array([
          device("ed25519:aa", "OPPO PLP110", true),
          device("ed25519:bb", "MacBook Pro", false),
        ]))])])),
        ("toConfirm", Json::number(2.0)),
      ])
    // on the locks of two accounts (a phone signed in to both), the second's email long; a chat's grant held
    "lock-two" =>
      granted("connected", [
        ("personal", Json::array([
          obj([("sub", str("s-zuo")), ("email", str("zuozijian1994@gmail.com")), ("standing", str("member")), ("devices", Json::array([
            device("ed25519:z1", "youdid.wtf 桌面版 · 左子健的 MacBook Air", false),
            device("ed25519:z2", "youdid.wtf Android · OPPO Find N6", true),
            device("ed25519:z3", "still.fail Android · OPPO Find N6", false),
          ]))]),
          obj([("sub", str("s-work")), ("email", str("zijian.zuo.engineering@example-company.com")), ("standing", str("member")), ("devices", Json::array([
            device("ed25519:w1", "youdid.wtf Android · OPPO Find N6", true),
            device("ed25519:w2", "still.fail 桌面版 · Mac Studio", false),
          ]))]),
        ])),
      ])
    // 共享调试 with no lock of the person's own yet (the page as it is: allowing a request begins it), or this device
    // typing the code a trusted device of theirs shows (the page is that step alone)
    "gate-none" => lent("connected", [("personal", Json::array([obj([("sub", str("s")), ("email", str("lin@example.com")), ("standing", str("none")), ("devices", Json::array([]))])]))])
    "gate-code" =>
      lent("connected", [
        ("personal", Json::array([obj([("sub", str("s")), ("email", str("lin@example.com")), ("standing", str("outside")), ("devices", Json::array([])), ("pair", obj([("state", str("code")), ("devices", Json::number(1.0)), ("untilText", str("14:05 前有效")), ("showing", Json::array([str("MacBook Pro")]))]))])])),
      ])
    "lock-outside" => lent("connected", [("personal", Json::array([obj([("sub", str("s")), ("email", str("lin@example.com")), ("standing", str("outside")), ("devices", Json::array([]))])]))])
    // lent for a chat's grant to Willow: its adb waiting to be paired (the pairing dialog not open yet, then open),
    // holding the phone, failing
    "unpaired" => granted("unpaired", [])
    "pairing" => granted("unpaired", [("pairPort", Json::number(37115.0))])
    "connected" => granted("connected", [("tunnels", Json::number(1.0))])
    "failed" =>
      granted("failed", [
        // (the phone's own words, as a station says them: station/src/adb/link.ts Refused)
        ("message", str("无法连接手机上的 adb：Connection refused (os error 111)")),
        ("refusedPort", Json::number(41239.0)),
      ])
    // settings' 共享调试, its switch off: nothing granted
    "idle" => obj([("sharing", Json::boolean(false)), ("phase", str("off")), ("on", Json::boolean(false)), ("tunnels", Json::number(0.0))])
    // lent for chats' grants to two stations: Willow's adb holds the phone, the other's waits to be paired with it (as
    // a core from before it said the one it names at its top: the first)
    "second" =>
      lent("connected", [
        ("on", Json::boolean(true)),
        ("pairPort", Json::number(37115.0)),
        (
          "lends",
          Json::array([
            obj([("station", str("ws1/st1")), ("phase", str("offered")), ("adb", str("connected")), ("serial", str("127.0.0.1:37762")), ("tunnels", Json::number(1.0))]),
            obj([("station", str("ws1/st2")), ("phase", str("offered")), ("adb", str("unpaired")), ("serial", str("127.0.0.1:37715")), ("tunnels", Json::number(0.0))]),
          ]),
        ),
        (
          "grants",
          Json::array([
            obj([("station", str("ws1/st1")), ("id", str("p-1")), ("reason", str("装上刚编好的测试包，看首屏在折叠屏展开时排得对不对")), ("status", str("granted")), ("scope", str("chat"))]),
            obj([("station", str("ws1/st2")), ("id", str("p-2")), ("reason", str("录一段登录流程的视频")), ("status", str("granted")), ("scope", str("hour"))]),
          ]),
        ),
      ])
    // The length and mix of reasons people see in the grants list, including one from before use times were recorded
    // (desk: the same seen on a computer, which lends no adb of its own)
    "chats-long" | "desk" =>
      obj([
        ("sharing", Json::boolean(true)),
        ("station", str("ws1/st1")),
        ("phase", str("offered")),
        ("adb", str("connected")),
        ("on", Json::boolean(true)),
        ("tunnels", Json::number(0.0)),
        ("lends", [obj([("station", str("ws1/st1")), ("phase", str("offered")), ("adb", str("connected")), ("tunnels", Json::number(1.0))])]),
        ("grants", [
          obj([("station", str("ws1/st1")), ("id", str("p-long-1")), ("session", str("s-c1")), ("chatTitle", str("键盘升起卡顿排查")), ("reason", str("在开发版里打开对话，让键盘升起再收起，记录每一帧的时间和显示时刻，量完就停")), ("status", str("granted")), ("scope", str("chat")), ("time", obj([("lastUsedAt", stamp_of("3 分钟前"))]))]),
          obj([("station", str("ws1/st1")), ("id", str("p-long-2")), ("session", str("s-c2")), ("chatTitle", str("客户端卡顿排查")), ("reason", str("量整页重搭那一帧实际跑多久，CPU 跑在什么频率，并比较改动前后的差别")), ("status", str("granted")), ("scope", str("chat")), ("time", obj([("lastUsedAt", stamp_of("2 小时前"))]))]),
          obj([("station", str("ws1/st1")), ("id", str("p-long-3")), ("session", str("s-c3")), ("chatTitle", str("检查登录页面")), ("reason", str("检查登录页面")), ("status", str("granted")), ("scope", str("hour"))]),
        ]),
      ])
    // a grant from before the person's own lock: signed by no device on it, so the phone
    // lends nothing on it; no reason given, and its station not lent yet
    "unsigned" =>
      obj([
        ("sharing", Json::boolean(false)),
        ("phase", str("idle")),
        ("on", Json::boolean(true)),
        ("tunnels", Json::number(0.0)),
        ("toConfirm", Json::number(1.0)),
        ("grants", [
          obj([("station", str("ws1/st1")), ("id", str("p-u-1")), ("session", str("s-c1")), ("chatTitle", str("定时 · 每 15 分钟审 mbui 三条线")), ("status", str("granted")), ("scope", str("chat")), ("held", Json::boolean(false))]),
        ]),
      ])
    // settings' 共享调试, its switch on: two chats granted it, one asking; lent to both their stations, Willow's adb
    // holding the phone and the other's waiting to be paired
    "chats" | "chats-off" =>
      obj([
        ("sharing", Json::boolean(true)),
        ("station", str("ws1/st2")),
        ("phase", str("offered")),
        ("adb", str(if fx.motion == 0 { "unpaired" } else { "connected" })),
        ("on", Json::boolean(true)),
        ("tunnels", Json::number(0.0)),
        (
          "lends",
          Json::array([
            obj([("station", str("ws1/st1")), ("phase", str("offered")), ("adb", str("connected")), ("tunnels", Json::number(1.0))]),
            obj([("station", str("ws1/st2")), ("phase", str("offered")), ("adb", str(if fx.motion == 0 { "unpaired" } else { "connected" })), ("tunnels", Json::number(0.0))]),
          ]),
        ),
        (
          "grants",
          Json::array([
            obj([("station", str("ws1/st1")), ("id", str("p-1")), ("reason", str("装上刚编好的测试包，看首屏在折叠屏展开时排得对不对")), ("status", str("granted")), ("scope", str("chat"))]),
            obj([("station", str("ws1/st2")), ("id", str("p-2")), ("reason", str("录一段登录流程的视频")), ("status", str("granted")), ("scope", str("hour"))]),
            obj([("station", str("ws1/st1")), ("id", str("p-3")), ("session", str("s-c1")), ("chatTitle", str("通知权限检查")), ("reason", str("看通知权限弹窗的文案")), ("status", str("pending"))]),
          ]),
        ),
      ])
    _ => obj([("sharing", Json::boolean(false)), ("phase", str("idle")), ("tunnels", Json::number(0.0))])
  }
}

///|
/// MBUI_FIXTURE=newchat-machine: the sessions Willow's machine kept (as the core gives them: the parts of each line
/// apart too), their list open over the new chat: two runtimes, a few folders, still.fail's own among them, one of them
/// already going on in a chat.
pub fn fixture_machine_sessions(core : Core) -> Unit {
  let s = fn(id : String, runtime : String, title : String, where_ : String, day : String, when : String, session : String) {
    let label = if runtime == "claude" { "Claude Code" } else { "Codex" }
    let parts = where_.split("/").to_array()
    obj([
      ("id", str(id)),
      ("runtime", str(runtime)),
      ("title", str(title)),
      ("first", str(title)),
      ("where", str(where_)),
      ("folder", str(parts[parts.length() - 1].to_owned())),
      ("day", str(day)),
      ("when", str(when)),
      ("own", Json::boolean(where_.has_prefix("~/.stillfail/"))),
      ("meta", str(label + " · " + where_)),
      ("session", if session == "" { Json::null() } else { str(session) }),
    ])
  }
  let own = "~/.stillfail/sessions/chat/c-41f2/workspace"
  machine_sessions_asked["ws1/st1"] = true
  machine_sessions["ws1/st1"] = [
    s("m1", "codex", "检查线程并操作应用内浏览器", "~/Documents/GitHub/still.fail", "今天", "3 分钟前", ""),
    s("m2", "codex", "Use your image generation tool to make the app icon", own, "今天", "20 分钟前", ""),
    s("m3", "codex", "[财务] 建立全自动记账系统", "~/Documents/Codex/ledger", "今天", "1 小时前", "s-c2"),
    s("m4", "claude", "整理构建脚本，把 Windows 的打包也接进 CI", "~/Documents/GitHub/still.fail", "今天", "3 小时前", ""),
    s("m5", "codex", "Create PR for airbuild integration with the release workflow", "~/Documents/GitHub/still.fail", "昨天", "22:41", ""),
    s("m6", "claude", "确认沉星之序大地图解密知识锁", "~/Documents/Codex/game", "昨天", "15:02", ""),
    s("m7", "codex", "Use your image generation tool to draw the empty state", own, "昨天", "11:20", ""),
    s("m8", "claude", "Review the onboarding copy", "~/Documents/GitHub/still.fail", "星期二", "18:09", ""),
    s("m9", "codex", "把发票 PDF 按月份归档", "~/Documents/Codex/ledger", "10月20日", "09:31", ""),
  ]
  open_machine_sessions(core, "ws1/st1", "Willow")
}

///|
/// Willow's 备份 row as the core shows it (StationCopies): Cedar and Aspen up to date; `alone`: the only station of its
/// workspace.
fn fixture_copies_row(alone~ : Bool) -> Json {
  obj([
    ("line", str(if alone { "再加一台 station 就会自动备份" } else { "已备份到 Cedar 和 Aspen · 2 分钟前" })),
    ("level", str(if alone { "amber" } else { "ok" })),
    ("offers", []),
    ("canRestore", Json::boolean(true)),
    ("formerly", []),
  ])
}

///|
/// A new station's 备份 (StationCopies): no chat of its own yet, Old Mac's backup (at Cedar) to restore; `under_way`:
/// it being restored, how in its row (恢复到这台 waits), else 恢复到这台 live.
fn fixture_copies_restore(under_way~ : Bool, name~ : String) -> Json {
  obj([
    ("line", str("还没备份好 · Cedar 连不上")),
    ("level", str("amber")),
    (
      "offers",
      [
        obj([
          ("station", str("st9")),
          ("gen", str("1-abcdef01")),
          ("name", str(name)),
          ("line", str(if under_way { "正在恢复：37 / 412 个文件" } else { name + " 的 128 个聊天" })),
          ("fromStation", str("st2")),
          ("busy", Json::boolean(under_way)),
        ]),
      ],
    ),
    ("canRestore", Json::boolean(!under_way)),
    ("formerly", []),
  ])
}

///|
/// The station after the restart that took Old Mac's chats in: what came of it, in its 备份 row until a station is up to
/// date with it.
fn fixture_copies_restored() -> Json {
  obj([
    ("line", str("已恢复 Old Mac 的 128 个聊天 · 2 分钟前")),
    ("level", str("amber")),
    ("offers", []),
    ("canRestore", Json::boolean(true)),
    ("formerly", [str("st9")]),
  ])
}

///|
/// The lock's changes made here that no station took yet, as the core's `lock` topic has them (lock-pending.ts
/// `pendingRow`), oldest first: a device of a long name taken out, waiting for Willow and Maple; Ana's role, changed
/// meanwhile on another device; a web page's renewal refused, in the station's words.
fn fx_pending_rows() -> Array[Json] {
  let all = [
    obj([
      ("id", str("p1")),
      ("text", str("移除设备 林的 MacBook Pro（2024 款 · 公司配的那台 · 放在办公室）：已记下，等 Willow、Maple 上线后生效")),
      ("state", str("waiting")),
      ("stations", [str("Willow"), str("Maple")]),
    ]),
    obj([
      ("id", str("p2")),
      ("text", str("把 Ana 改为成员：没有生效。「Ana」在这之后又被改过，请查看现在的状态，仍然需要的话再操作一次")),
      ("state", str("failed")),
      ("stations", []),
      ("dismissText", str("知道了")),
    ]),
    obj([
      ("id", str("p3")),
      ("text", str("续期 Chrome · macOS：没有生效。请查看现在的状态，仍然需要的话再操作一次")),
      ("state", str("failed")),
      ("stations", []),
      ("why", str("这台设备已不在安全模式中")),
      ("dismissText", str("知道了")),
    ]),
  ]
  all.filter(fn(r) { fx.pending.contains(text(Some(r), "id")) })
}

///|
/// The `lock` topic's fields of what is pending: the rows, and their heading while there are any.
fn fx_pending_fields() -> Array[(String, Json)] {
  let rows = fx_pending_rows()
  if rows.is_empty() {
    [("pending", Json::array(rows))]
  } else {
    [("pending", Json::array(rows)), ("pendingText", str("以下改动还没有生效"))]
  }
}

///|
/// What is pending made `ids` (of settings-security-pending's), as the core says it changed: a station took one, or one
/// was dropped.
pub fn fixture_pending_set(ids : Array[String]) -> Unit {
  fx.pending.clear()
  fx.pending.append(ids)
  fx_changed()
}
