// What the vault's pages share (docs/vault.md; the core's `vaults` and `vaultItems`): its kinds of item and their
// marks, how a secret is given, its grants and how long they last, the profiles' accounts by kind, whose service a
// profile runs on. Its page is src/sfpages vault.mbt's, one in every frame.

///|
/// The kinds of item, in the editor's order (Vault.kt KINDS).
// kept across runs: a table, never written
pub let vault_kinds : Array[String] = ["token", "ssh_key", "login", "file"]

///|
/// Every kind an item may be: those added by hand (`vault_kinds`), then a sign-in (kind browser: a site's cookies, kept
/// only as an agent asks to keep them from a chat's browser, never typed in).
// kept across runs: a table, never written
pub let vault_item_kinds : Array[String] = [..vault_kinds, "browser"]

///|
pub fn kind_icon(kind : String) -> String {
  match kind {
    "ssh_key" => "server"
    "login" => "user"
    "file" => "file-text"
    "browser" => "globe"
    _ => "key"
  }
}

///|
pub fn mode_name(mode : String) -> String {
  match mode {
    "proxy" | "env" | "ssh" | "file" | "browser" => tr("android-settings.vault.mode." + mode)
    m => m
  }
}

///|
/// The profiles' accounts by the kind they are listed under, in the core's order: (its title, its accounts).
pub fn profile_groups(list : Array[Json]) -> Array[(String, Array[Json])] {
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
/// The grants an approval offers for an item whose longest is `lasts` (Vault.kt scopesUpTo: every one where it names
/// none), shortest first; the longest of them the one recommended.
pub fn vault_scopes_up_to(lasts : String) -> Array[String] {
  match vault_scopes.search(lasts) {
    Some(i) => vault_scopes[:i + 1].to_array()
    None => vault_scopes.copy()
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
/// How long a grant lasts, shortest first: one use, an hour, the chat until it is archived (Vault.kt SCOPES).
// kept across runs: a table, never written
pub let vault_scopes : Array[String] = ["once", "hour", "chat"]

///|
/// The longest an item is granted for, in a word: 仅一次, 1 小时, 直到对话归档 (Vault.kt lastsName: the chat's when
/// it says none it knows).
fn lasts_name(lasts : String) -> String {
  tr("android-settings.vault.lasts." + (if vault_scopes.contains(lasts) { lasts } else { "chat" }))
}

///|
/// An item's longest grant as its editor offers it: its vault's (`default`, the library's setting), or its own
/// (Vault.kt LASTS).
// kept across runs: a table, never written
pub let vault_lasts : Array[String] = ["default", "once", "hour", "chat"]

///|
/// An item's longest grant as its editor names it (Vault.kt lastsChoice).
pub fn lasts_choice(lasts : String) -> String {
  if lasts == "default" {
    tr("android-settings.vault.lasts.default")
  } else {
    lasts_name(lasts)
  }
}
