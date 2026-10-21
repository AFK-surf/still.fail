// still.fail's links as the made-up data's core reads them (links.mbt; the core's link.parse: client/core-ts).

///|
/// What the core's `link.parse` says of `url` (client/core-ts: LinkTarget), for the made-up chats' links and the
/// tests': an item's (/o/<ws>/<station>/<session>, `service`, `history`, `entry`), a chat's
/// (/w/<ws>/s/<station>/chats/<key>), an invitation's (/invite#<token>), a screen's (/w/…/s/…/screen/<id>),
/// `?history=` alone; null for any other.
fn fixture_link_parse(url : String) -> Json {
  let (path, query) = match url.find("?") {
    Some(i) => (url.view(end_offset=i).to_string(), url.view(start_offset=i + 1).to_string())
    None => (url, "")
  }
  let q : Map[String, String] = {}
  for kv in query.split("&") {
    let kv = kv.to_string()
    match kv.find("=") {
      Some(i) => q[kv.view(end_offset=i).to_string()] = kv.view(start_offset=i + 1).to_string()
      None => ()
    }
  }
  let o : Map[String, Json] = {}
  let put = fn(k : String, v : String) { if v != "" { o[k] = Json::string(v) } }
  let after = fn(cut : String) -> Array[String]? {
    match path.find(cut) {
      Some(i) => Some(path.view(start_offset=i + cut.length()).to_string().split("/").map(fn(v) { v.to_string() }).to_array())
      None => None
    }
  }
  if path.contains("/invite") && url.contains("#") {
    put("opens", "invite")
    put("token", url.view(start_offset=url.find("#").unwrap() + 1).to_string())
  } else if after("/o/") is Some(p) && p.length() >= 3 {
    put("opens", "item")
    put("workspace", p[0])
    put("station", p[1])
    put("session", p[2])
    put("service", q.get("service").unwrap_or(""))
  } else if after("/w/") is Some(p) && p.length() >= 5 && p[1] == "s" && p[3] == "chats" {
    put("opens", "chat")
    put("workspace", p[0])
    put("station", p[2])
    put("chat", p[4])
  } else if after("/w/") is Some(p) && p.length() >= 5 && p[1] == "s" && p[3] == "screen" {
    put("opens", "screen")
    put("workspace", p[0])
    put("station", p[2])
    put("screen", p[4])
  } else if q.contains("history") {
    put("opens", "history")
  } else {
    return Json::null()
  }
  put("history", q.get("history").unwrap_or(""))
  match q.get("entry") {
    Some(e) => o["entry"] = Json::number(seq_of(e))
    None => ()
  }
  Json::object(o)
}

