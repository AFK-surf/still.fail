// What the vault's pages and dialogs share (Vault.kt; the pages are src/sfpages vault.mbt and vault_item.mbt, the
// dialogs vault_dialogs.mbt): its calls and how they failed (`vault.*`), the recovery words shown the once, an item
// opened while its page is up (`vault.open`; what it holds never kept, never logged: stillfail/main.mbt `logged`), an
// item written (`vault.putItem`: its params, the hosts it is given to, what is wrong with it).

///|
/// The fields each kind of item holds, in the editor's order; those not secret.
fn vault_fields(kind : String) -> Array[String] {
  match kind {
    "token" => ["value"]
    "ssh_key" => ["private_key", "public_key"]
    "login" => ["username", "password", "totp"]
    "file" => ["content", "filename"]
    _ => []
  }
}

///|
/// The most a file kept may be, its bytes (the core's and the station's).
pub let file_most : Int = 64 * 1024

///|
/// A file picked to be kept, once the system's picker (`pick`) answered: `got` its bytes in base64 and its name; one
/// bigger than a file kept may be said so, and not taken. Whether it answered (the pick is then done with).
pub fn take_picked_file(core : Core, pick : @ui.Pick, got : (String, String) -> Unit) -> Bool {
  match pick.files() {
    None => false
    Some(files) => {
      match files.get(0) {
        Some(f) if f.bytes.length() > file_most || f.held != 0 => (core.say)(tr("android-settings.vault.fileTooBig"))
        Some(f) => got(@codec.base64(f.bytes), f.name)
        None => ()
      }
      true
    }
  }
}

///|
/// A file's size in words, from its base64: 820 B, 12 KB.
pub fn file_size(content : String) -> String {
  let pad = if content.has_suffix("==") {
    2
  } else if content.has_suffix("=") {
    1
  } else {
    0
  }
  let n = content.length() * 3 / 4 - pad
  if n < 1024 {
    "\{n} B"
  } else {
    "\{(n + 512) / 1024} KB"
  }
}

///|
/// What a vault call's failure says (vaultSaid): nothing when the person turned the system's prompt down
/// (`user_cancelled`), that another device wrote first (`vault_conflict`), else why.
pub fn vault_said(e : Json) -> String? {
  match text(Some(e), "code") {
    "user_cancelled" => None
    "vault_conflict" => Some(tr("android-settings.vault.conflict"))
    _ => Some(error_text(e))
  }
}

///|
/// A vault call (`vault.<name>` on the workspace), as act is for others (vaultAct): `done` said once through, a
/// failure said (a write made elsewhere first said as such; the prompt turned down, nothing).
pub fn vault_act(
  core : Core,
  ws : String,
  name : String,
  params : Array[(String, Json)],
  what : String,
  done? : String = "",
  then? : (Json) -> Unit = fn(_) {  },
  failed? : (Json) -> Unit = fn(_) {  },
) -> Unit {
  let p = [("workspace", str(ws))]
  for x in params {
    p.push(x)
  }
  (core.call)("vault." + name, obj(p), fn(r) {
    match r {
      Ok(v) => {
        if done != "" {
          (core.say)(done)
        }
        then(v)
      }
      Err(e) => {
        failed(e)
        match vault_said(e) {
          Some(why) =>
            (core.say)(
              if text(Some(e), "code") == "vault_conflict" {
                why
              } else {
                fill(
                  if text(Some(e), "code") == "unconfirmed" {
                    "android-misc.act.unconfirmed"
                  } else {
                    "android-misc.act.failed"
                  },
                  [("what", what), ("error", why)],
                )
              },
            )
          None => ()
        }
      }
    }
  })
}

///|
/// The recovery words `vault.setup` gave, by workspace, until the person says they have written them down: in memory
/// only, never kept (the core gives them only the once).
pub let recovery_words : @sf.LiveMap[String, Array[String]] = @sf.LiveMap::new()

///|
/// What `vault.open` gave of the item on its page (by item), while the page is up; whether it is being opened.
priv struct Opened {
  plain : @sf.LiveMap[String, Json]
  /// its fields as its page shows them (the core's `shown`: each its key, what it is called, its value, whether secret)
  fields : @sf.LiveMap[String, Array[Json]]
  opening : @sf.LiveMap[String, Bool]
  /// the fields shown (by item and field)
  shown : Map[String, Bool]
}

///|
let opened : Opened = { plain: @sf.LiveMap::new(), fields: @sf.LiveMap::new(), opening: @sf.LiveMap::new(), shown: {} }

///|
/// The item opened (`vault.open`: the system's prompt first where its vault is locked here), then `then` with what it
/// holds.
pub fn open_item(core : Core, ws : String, item : String, then : (Json) -> Unit) -> Unit {
  if opened.opening.contains(item) {
    return
  }
  opened.opening[item] = true
  (core.call)("vault.open", obj([("workspace", str(ws)), ("item", str(item))]), fn(r) {
    opened.opening.remove(item)
    match r {
      Ok(v) =>
        match field(Some(v), "plain") {
          Some(Object(_) as p) => {
            opened.plain[item] = p
            opened.fields.set(item, items(Some(v), "shown"))
            then(p)
          }
          _ => ()
        }
      Err(e) =>
        match vault_said(e) {
          Some(why) =>
            (core.say)(fill("android-misc.act.failed", [("what", tr("android-settings.vault.openWhat")), ("error", why)]))
          None => ()
        }
    }
  })
}

///|
/// What an item opened holds while its page is up (the phone's and the desktop's page alike), its fields as the page
/// shows them (the core's `shown`), and whether it is being opened.
pub fn opened_plain(item : String) -> Json? {
  opened.plain.get(item)
}

///|
pub fn opened_fields(item : String) -> Array[Json] {
  opened.fields.get(item).unwrap_or([])
}

///|
pub fn item_opening(item : String) -> Bool {
  opened.opening.contains(item)
}

///|
/// An item's page left: what it held goes.
fn vault_item_left(item : String) -> Unit {
  opened.plain.remove(item)
  opened.fields.remove(item)
  opened.opening.remove(item)
  let gone = opened.shown.keys().filter(fn(k) { k.has_prefix(item + "/") }).collect()
  for k in gone {
    opened.shown.remove(k)
  }
}

///|
/// An item being written (Editor's state): its kind, whether agents may ask for it, how, the error said under it.
pub(all) struct VaultEditing {
  kind : @signals.Signal[Int]
  agent : @signals.Signal[Bool]
  mode : @signals.Signal[String]
  /// its longest grant (vault_lasts: 跟随默认 first)
  lasts : @signals.Signal[Int]
  error : @signals.Signal[String]
  saving : @signals.Signal[Bool]
  /// the fields shown in the clear (by field)
  reveal : @sf.LiveMap[String, Bool]
  serial : Int
  /// a file's: its bytes in base64 and its name, as picked (or as it was); the system's picker while it asks
  file_content : @signals.Signal[String]
  file_name : @signals.Signal[String]
  file_pick : @signals.Signal[@ui.Pick?]
}

///|
pub let vault_serial : @signals.Signal[Int] = @signals.signal(0, same=fn(a, b) { a == b })

///|
/// What `vault.putItem` is given for an item (Vault.tsx putOf): the vault, the item's id where it is one already, what
/// it holds (`words`: its fields' words by name, as typed), and, where agents may ask for it, how (`mode`, its hosts,
/// its variable) and its longest grant (`lasts`: "default" its vault's).
pub fn vault_put_params(
  vault : String,
  row : Json?,
  was : Json?,
  k : String,
  words : Map[String, String],
  agent : Bool,
  mode : String,
  lasts : String,
) -> Array[(String, Json)] {
  let got = fn(f : String) { words.get(f).unwrap_or("").trim(chars=" \n").to_owned() }
  let name = words.get("name").unwrap_or("").trim(chars=" ").to_owned()
  let fields : Array[(String, Json)] = []
  for f in vault_fields(k) {
    // a private key as pasted (its last line break is part of it); the rest without the spaces around them
    let v = if f == "private_key" || f == "content" { words.get(f).unwrap_or("") } else { got(f) }
    if v.trim(chars=" \n") != "" {
      fields.push((f, str(v)))
    }
  }
  let plain_item = obj([
    ("kind", str(k)),
    ("name", str(name)),
    ("fields", obj(fields)),
    ("domains", Json::array(strings(was, "domains").map(str))),
    ("notes", str(text(was, "notes"))),
  ])
  let params = [("vault", str(vault)), ("plain", plain_item)]
  match row {
    Some(r) => params.push(("id", str(text(Some(r), "id"))))
    None => ()
  }
  if agent {
    let modes = match k {
      "ssh_key" => ["ssh"]
      "file" => ["file"]
      _ => [mode]
    }
    let listing = [
      ("name", str(name)),
      ("kind", str(k)),
      ("modes", Json::array(modes.map(str))),
      ("hosts", Json::array((if modes == ["proxy"] { vault_hosts(words) } else { [] }).map(str))),
    ]
    let env = got("env")
    if env != "" && k != "ssh_key" {
      listing.push(("env", str(env)))
    }
    // its own longest grant (none: its vault's)
    if lasts != "default" {
      listing.push(("lasts", str(lasts)))
    }
    params.push(("listing", obj(listing)))
  }
  params
}

///|
/// The hosts typed (`words`' hosts: by commas, spaces or lines).
pub fn vault_hosts(words : Map[String, String]) -> Array[String] {
  let out : Array[String] = []
  for h in words.get("hosts").unwrap_or("").replace_all(old=",", new=" ").replace_all(old="\n", new=" ").split(" ") {
    if h != "" {
      out.push(h.to_owned())
    }
  }
  out
}

///|
/// Whether an item's words can be saved (Vault.tsx formProblem): its name, what its kind needs, and the hosts where a
/// proxy gives it; the problem's name, or "" none.
pub fn vault_problem(k : String, words : Map[String, String], agent : Bool, mode : String) -> String {
  let got = fn(f : String) { words.get(f).unwrap_or("").trim(chars=" \n").to_owned() }
  let filled_in = match k {
    "token" => got("value") != ""
    "ssh_key" => got("private_key") != ""
    "file" => got("content") != ""
    _ => got("username") != "" || got("password") != ""
  }
  if got("name") == "" {
    "name"
  } else if !filled_in {
    "fields"
  } else if agent && mode == "proxy" && k != "ssh_key" && k != "file" && vault_hosts(words).length() == 0 {
    "hosts"
  } else {
    ""
  }
}
