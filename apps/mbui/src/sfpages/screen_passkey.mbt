// A page's sign-in with a passkey, signed on this device (ember docs/remote-screens.md, "Signing in with a passkey"):
// while this viewer drives a tab of a station's browser whose page asks for one, the station says the site and the
// client data to sign (the tab's origin, as the browser has its address); the person's own device (@hostapi
// passkeys.mbt: Windows, which asks them itself) signs it with a passkey of theirs for that site, and what it signed
// goes to the station to answer the page (`screen.input` passkey). A no is answered as a browser answers it.

///|
/// The page's ask for a passkey, while this viewer drives the screen; None in none, or only looking.
fn ScreenSess::passkey_ask(self : ScreenSess) -> Json? {
  if !self.driving() {
    return None
  }
  match field(self.state, "passkey") {
    Some(Object(_) as p) if text(Some(p), "id") != "" => Some(p)
    _ => None
  }
}

///|
/// 登录 pressed: the device asked to sign the page's ask.
fn ScreenSess::passkey_start(self : ScreenSess) -> Unit {
  guard self.passkey_ask() is Some(p) else { return }
  self.passkey_stop()
  self.passkey_id = text(Some(p), "id")
  let allow = match field(Some(p), "allow") {
    Some(Array(a)) =>
      a
      .filter_map(fn(v) {
        match v {
          String(s) => Some(s)
          _ => None
        }
      })
    _ => []
  }
  match @hostapi.passkey_get(text(Some(p), "rpId"), text(Some(p), "clientData"), allow, text(Some(p), "userVerification")) {
    Some(r) => {
      self.passkey_run = Some(r)
      self.passkey_step.set("asking")
    }
    None => {
      self.passkey_note = @sf.t("android-misc.screen.passkey.failed", args=[("why", "webauthn.dll")])
      self.passkey_step.set("said")
    }
  }
}

///|
/// Let go of: the ask under way forgotten, nothing shown.
fn ScreenSess::passkey_stop(self : ScreenSess) -> Unit {
  match self.passkey_run {
    Some(r) => r.end()
    None => ()
  }
  self.passkey_run = None
  self.passkey_note = ""
  self.passkey_step.set("")
}

///|
/// The ask under way ended: what it signed sent, or the page told no (once).
fn ScreenSess::passkey_took(self : ScreenSess) -> Unit {
  guard self.passkey_run is Some(r) else { return }
  guard r.done() is Some(d) else { return }
  r.end()
  self.passkey_run = None
  let id = self.passkey_id
  if d.code == 0 && d.credential != "" && d.authenticator_data != "" && d.signature != "" {
    let input : Map[String, Json] = {
      "t": Json::string("passkey"),
      "id": Json::string(id),
      "credential": Json::string(d.credential),
      "authenticatorData": Json::string(d.authenticator_data),
      "signature": Json::string(d.signature),
    }
    if d.user_handle != "" {
      input["userHandle"] = Json::string(d.user_handle)
    }
    self.input(self.src, Json::object(input))
    self.passkey_step.set("")
    return
  }
  // (the person said no, or no passkey of the site's here: the page told as a browser tells it; else why, kept for
  // them to read, the page still asking)
  if d.code == 1 {
    self.input(self.src, Json::object({ "t": Json::string("passkey"), "id": Json::string(id), "error": Json::string("NotAllowedError") }))
    self.passkey_step.set("")
    return
  }
  self.passkey_note = @sf.t("android-misc.screen.passkey.failed", args=[("why", d.err.trim(chars=" \n").to_owned())])
  self.passkey_step.set("said")
}

///|
/// 用通行密钥登录, over the stage while a page this viewer drives asks for a passkey (on a host whose device has passkeys
/// to ask): the site and 登录, what it is at, or why it did not sign.
fn passkey_sign(c : @ui.Ctx, s : ScreenSess) -> Unit {
  // an ask under way: its end taken once it came (after this frame: what the page shows changes then)
  match s.passkey_run {
    Some(r) if r.done() is Some(_) => c.tell("screen-passkey/" + s.view, fn() { s.passkey_took() })
    _ => ()
  }
  let step = s.passkey_step.get()
  let ask = s.passkey_ask()
  if !@hostapi.passkeys() || (ask is None && step == "") {
    return
  }
  c.box(style=drops_box, fn() {
    c.box(style=drop_row_box, fn() {
      c.box(style=drop_icon_box, fn() {
        @sf.icon(c, if step == "said" { "info" } else { "key" }, size=drop_icon, color=c.color(Muted)) |> ignore
      })
      |> ignore
      @sf.row_lines(c, fn() {
        let title = match step {
          "asking" => @sf.t("android-misc.screen.passkey.asking")
          "said" => s.passkey_note
          _ => @sf.t("android-misc.screen.passkey.offer")
        }
        c.box(style=drop_words, fn() { c.text(title, style=if step == "said" { drop_path_words } else { drop_name }) |> ignore })
        |> ignore
        if step == "said" && screen_row_key(c, "passkey-close", "close", @sf.t("common.close")) {
          s.passkey_stop()
        }
      }, fn() {
        if step == "" {
          // the site under the words, 登录 under it (as 用 1Password 填入 says it)
          match ask {
            Some(p) => c.text(text(Some(p), "host"), style=drop_path_words) |> ignore
            None => ()
          }
          c.box(style=drop_buttons, fn() {
            if soft_button(c, "passkey", @sf.t("android-misc.screen.passkey.button")) {
              c.tell("screen-passkey-start/" + s.view, fn() { s.passkey_start() })
            }
          })
          |> ignore
        }
      })
    })
    |> ignore
  })
  |> ignore
}
