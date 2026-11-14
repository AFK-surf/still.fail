// A chat's link, as it is given away: from a row's
// menu, a chat's sheet, an agent's history.

///|
/// The cloud's address, for a chat's link (the app's MBUI_CLOUD, else still.fail's own).
pub fn cloud_origin() -> String {
  match @ui.env("MBUI_CLOUD") {
    "" => "https://app.still.fail"
    o => o
  }
}

///|
/// A chat's still.fail link: <cloud>/o/<workspace>/<station>/<session>; "" for a station of no
/// workspace or a chat with no session yet.
pub fn chat_link(station : String, session : String) -> String {
  match station.find("/") {
    Some(at) if at > 0 && at < station.length() - 1 && session != "" => {
      let cloud = cloud_origin()
      let base = if cloud.has_suffix("/") {
        cloud.exact_view(end=cloud.length() - 1).to_owned()
      } else {
        cloud
      }
      base +
      "/o/" +
      station.exact_view(end=at).to_owned() +
      "/" +
      station.exact_view(start=at + 1).to_owned() +
      "/" +
      @codec.encode_uri_component(session)
    }
    _ => ""
  }
}

///|
/// A link to this exact message, using the same destination as a notification.
pub fn message_link(station : String, session : String, seq : Double) -> String {
  let link = chat_link(station, session)
  if link == "" || seq <= 0.0 { return "" }
  link + "?message=" + seq_s(seq)
}

///|
/// Copies a chat's link as a reference is sent (chatLinkText): `[title](link)`, as a press asks it (a menu's item, a
/// button): on the clipboard and felt at once, said so.
pub fn copy_chat_link(title : String, link : String) -> Unit {
  let shown = title.replace_all(old="[", new=" ").replace_all(old="]", new=" ").replace_all(old="\n", new=" ").trim(chars=" ").to_owned()
  let shown = if shown == "" { link } else { shown }
  // (its first 120 characters, as Android's chatLinkText cuts it)
  let cut = StringBuilder()
  let mut n = 0
  for ch in shown {
    if n < chat_link_most {
      cut.write_char(ch)
    }
    n += 1
  }
  let shown = cut.to_string()
  copy_out("[" + shown + "](" + link + ")", said=@sf.t("web-main.chat.linkCopied"))
}

///|
/// How much of a chat's title its copied link carries.
let chat_link_most : Int = 120
