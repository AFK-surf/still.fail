// A chat's link, as it is given away (ChatLink.kt, the web's chatRefs.ts shareLink and copyChatLink): from a row's
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
/// A chat's still.fail link (ChatLink.kt chatLink): <cloud>/o/<workspace>/<station>/<session>; "" for a station of no
/// workspace or a chat with no session yet.
pub fn chat_link(station : String, session : String) -> String {
  match station.find("/") {
    Some(at) if at > 0 && at < station.length() - 1 && session != "" => {
      let cloud = cloud_origin()
      let base = if cloud.has_suffix("/") {
        cloud.view(end_offset=cloud.length() - 1).to_owned()
      } else {
        cloud
      }
      base +
      "/o/" +
      station.view(end_offset=at).to_owned() +
      "/" +
      station.view(start_offset=at + 1).to_owned() +
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
/// Copies a chat's link as a reference is sent (ChatLink.kt copyChatLink, chatLinkText): `[title](link)`.
pub fn copy_chat_link(c : @ui.Ctx, title : String, link : String) -> Unit {
  let shown = title.replace_all(old="[", new=" ").replace_all(old="]", new=" ").replace_all(old="\n", new=" ").trim(chars=" ").to_string()
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
  c.copy_text("[" + shown + "](" + link + ")")
  say(c, @sf.t("web-main.chat.linkCopied"))
}

///|
/// How much of a chat's title its copied link carries (ChatLink.kt chatLinkText: 120 characters).
let chat_link_most : Int = 120
