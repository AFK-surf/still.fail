// What the vault's pages share (docs/vault.md; the core's `vaults` and `vaultItems`): its kinds of item and their
// marks, how a secret is given, its grants and how long they last, the profiles' accounts by kind, whose service a
// profile runs on. Its page is src/sfdesk vault.mbt's, one in every frame.

///|
/// The kinds of item, in the editor's order (Vault.kt KINDS).
// kept across runs: a table, never written
pub let vault_kinds : Array[String] = ["token", "ssh_key", "login"]

///|
pub fn kind_icon(kind : String) -> String {
  match kind {
    "ssh_key" => "server"
    "login" => "user"
    _ => "key"
  }
}

///|
pub fn mode_name(mode : String) -> String {
  match mode {
    "proxy" | "env" | "ssh" => tr("android-settings.vault.mode." + mode)
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
/// Whose service a profile runs on (Parts.kt ProviderMark): OpenCode's square, a listed provider's maker (the plug where
/// there is none), Anthropic, xAI, Cursor, Devin or OpenAI by its runtime.
pub fn provider_mark(c : @ui.Ctx, runtime : String, kind : String, size : Double, mark : String) -> Unit {
  let t = @sf.theme()
  if kind == "opencode-go" || mark == "opencode" {
    c.box(w=Px(size), h=Px(size), align=ACenter, justify=JCenter, fn() {
      c.box(w=Px(size / 2.0), h=Px(size * 2.0 / 3.0), border=size / 10.0, border_color=t.p.text, fn() {  }) |> ignore
    })
    |> ignore
    return
  }
  let maker = if kind == "api-provider" {
    mark
  } else if runtime == "claude" || kind == "anthropic-api" {
    "anthropic"
  } else {
    match runtime {
      "grok" => "xai"
      "cursor" => "cursor"
      "devin" => "devin"
      _ => "openai"
    }
  }
  if maker == "" || !@sf.has_drawable("maker_" + maker.replace_all(old="-", new="_")) {
    @sf.icon(c, "plug", size~, color=t.p.text) |> ignore
  } else {
    @sf.maker_mark(c, maker, runtime, size) |> ignore
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
