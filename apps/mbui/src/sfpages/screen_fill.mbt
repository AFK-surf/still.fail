// A page's login filled from this device's password manager (ember docs/remote-screens.md, "Filling a login"): while
// this viewer drives a tab of a station's browser whose focus is in a login field, the station says the site (the
// tab's address, not the page's word); the person's own 1Password (@hostapi passwords.mbt: its command-line tool,
// which asks them itself) is asked for that site's logins, they pick one where there are more, and its account and
// password go to the station to fill the form (`screen.input` fill), for that site only. Where there is no such tool
// but the system has an autofill service (Android's: @hostapi autofill.mbt), that service is asked for the site's
// login instead and offers its logins itself; the one picked goes the same way. Nothing of a password is kept here,
// logged or shown.

///|
/// The login field in focus, while this viewer drives the screen: the site's host; None in none, or only looking.
fn ScreenSess::login_host(self : ScreenSess) -> String? {
  if !self.driving() {
    return None
  }
  match field(self.state, "login") {
    Some(Object(_) as l) => {
      let host = text(Some(l), "host")
      if host == "" {
        None
      } else {
        Some(host)
      }
    }
    _ => None
  }
}

///|
/// 填入 pressed: the password manager asked for the site's logins.
fn ScreenSess::fill_start(self : ScreenSess) -> Unit {
  guard self.login_host() is Some(host) else { return }
  self.fill_stop()
  self.fill_host = host
  if !@hostapi.passwords() && @hostapi.autofill_ask(host) {
    // the system's autofill service offers the site's logins itself; the one picked comes back (fill_auto_took)
    self.fill_step.set("auto")
    return
  }
  self.fill_ask(["item", "list", "--categories", "Login", "--format", "json"], "listing")
}

///|
/// The login picked in the system's autofill service: filled, where it is for the site asked for (the station fills
/// the page's form only while its tab is on that site, as for 1Password's).
fn ScreenSess::fill_auto_took(self : ScreenSess, got : (String, String, String)) -> Unit {
  let (host, username, password) = got
  guard self.fill_step.get() == "auto" && host == self.fill_host else { return }
  @hostapi.autofill_end()
  self.fill_step.set("")
  if self.input_goes() {
    self.fill_send(username, password)
  } else {
    // (the service's sign-in took the app out of sight: the view opens again, then it is sent)
    self.fill_owed = Some((username, password))
  }
}

///|
/// The login's account and password sent to the station to fill the page's form, for the site asked for only.
fn ScreenSess::fill_send(self : ScreenSess, username : String, password : String) -> Unit {
  let input : Map[String, Json] = { "t": Json::string("fill"), "host": Json::string(self.fill_host) }
  if username != "" {
    input["username"] = Json::string(username)
  }
  if password != "" {
    input["password"] = Json::string(password)
  }
  self.input(self.src, Json::object(input))
}

///|
/// `op` run with `args`, the step it is for set; one that cannot run said so.
fn ScreenSess::fill_ask(self : ScreenSess, args : Array[String], step : String) -> Unit {
  match @hostapi.op_run(args) {
    Some(r) => {
      self.fill_run = Some(r)
      self.fill_step.set(step)
    }
    None => self.fill_said(@sf.t("android-misc.screen.fill.noOp"))
  }
}

///|
fn ScreenSess::fill_said(self : ScreenSess, note : String) -> Unit {
  self.fill_note = note
  self.fill_step.set("said")
}

///|
/// One of the site's logins picked (or the only one): its account and password asked for.
fn ScreenSess::fill_pick(self : ScreenSess, l : @hostapi.PasswordLogin) -> Unit {
  self.fill_choices = []
  self.fill_ask(["item", "get", l.id, "--fields", "label=username,label=password", "--reveal", "--format", "json"], "getting")
}

///|
/// Let go of: the run under way stopped, nothing shown.
fn ScreenSess::fill_stop(self : ScreenSess) -> Unit {
  match self.fill_run {
    Some(r) => r.end()
    None => ()
  }
  self.fill_run = None
  self.fill_owed = None
  if self.fill_step.get() == "auto" {
    @hostapi.autofill_end()
  }
  self.fill_choices = []
  self.fill_note = ""
  self.fill_step.set("")
}

///|
/// The run under way ended: what it said taken (once).
fn ScreenSess::fill_took(self : ScreenSess) -> Unit {
  guard self.fill_run is Some(r) else { return }
  guard r.done() is Some(d) else { return }
  r.end()
  self.fill_run = None
  if d.code != 0 {
    // (`op` missing, not signed in through the desktop app, or the person said no)
    let why = d.err.trim(chars=" \n").to_owned()
    self.fill_said(
      if d.code == -1 || why.contains("not found") || why.contains("not currently signed in") || why.contains("integration") {
        @sf.t("android-misc.screen.fill.noOp")
      } else {
        @sf.t("android-misc.screen.fill.failed", args=[("why", why)])
      },
    )
    return
  }
  match self.fill_step.get() {
    "listing" => {
      let found = @hostapi.logins_for(d.out, self.fill_host)
      if found.is_empty() {
        self.fill_said(@sf.t("android-misc.screen.fill.none", args=[("host", self.fill_host)]))
      } else if found.length() == 1 {
        self.fill_pick(found[0])
      } else {
        self.fill_choices = found
        self.fill_step.set("choosing")
      }
    }
    "getting" => {
      let (username, password) = @hostapi.login_fields(d.out)
      if username == "" && password == "" {
        self.fill_said(@sf.t("android-misc.screen.fill.empty"))
        return
      }
      self.fill_send(username, password)
      self.fill_step.set("")
    }
    _ => ()
  }
}

///|
/// 用 1Password 填入 (用密码管理器填入 where the system's autofill service is asked), over the stage while the focus is
/// in a login field of a page this viewer drives (on a host that has a password manager to ask): what it is at, the
/// logins to pick from, or why it did not fill.
fn login_fill(c : @ui.Ctx, s : ScreenSess) -> Unit {
  // a run under way: its end taken once it came (after this frame: what the page shows changes then)
  match s.fill_run {
    Some(r) if r.done() is Some(_) => c.tell("screen-fill/" + s.view, fn() { s.fill_took() })
    _ => ()
  }
  let step = s.fill_step.get()
  let host = s.login_host()
  let op = @hostapi.passwords()
  // the login picked in the service's offer, once it came (the page's focus may have left the login meanwhile: the
  // app's own tap on 填入 can take it, before the service answers; it is filled as 1Password's is, below)
  if step == "auto" {
    match @hostapi.autofill_take() {
      Some(got) => c.tell("screen-fill-auto/" + s.view, fn() { s.fill_auto_took(got) })
      None => ()
    }
  }
  if s.fill_owed is Some(_) && s.input_goes() {
    c.tell("screen-fill-owed/" + s.view, fn() {
      match s.fill_owed {
        Some((username, password)) => {
          s.fill_owed = None
          s.fill_send(username, password)
        }
        None => ()
      }
    })
  }
  if (!op && !@hostapi.autofill()) || (host is None && step == "") {
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
          "listing" | "getting" => @sf.t("android-misc.screen.fill.asking")
          "auto" => @sf.t("android-misc.screen.fill.autoPick", args=[("host", s.fill_host)])
          "choosing" => @sf.t("android-misc.screen.fill.pick", args=[("host", s.fill_host)])
          "said" => s.fill_note
          _ => @sf.t(if op { "android-misc.screen.fill.offer" } else { "android-misc.screen.fill.offerAuto" })
        }
        c.box(style=drop_words, fn() { c.text(title, style=if step == "said" { drop_path_words } else { drop_name }) |> ignore })
        |> ignore
        if step != "" && screen_row_key(c, "fill-close", "close", @sf.t("common.close")) {
          s.fill_stop()
        }
      }, fn() {
        match step {
          "" => {
            // the site under the words, 填入 under it (as a file sent says where it is, then what is done with it)
            match host {
              Some(h) => c.text(h, style=drop_path_words) |> ignore
              None => ()
            }
            c.box(style=drop_buttons, fn() {
              if soft_button(c, "fill", @sf.t("android-misc.screen.fill.button")) {
                c.tell("screen-fill-start/" + s.view, fn() { s.fill_start() })
              }
            })
            |> ignore
          }
          "choosing" =>
            // one under another, as wide as its words (none out to the panel's corner)
            c.box(style=fill_choice_list, fn() {
              for i, l in s.fill_choices {
                let words = if l.username == "" { l.title } else { l.title + " · " + l.username }
                if soft_button(c, "fill-pick/\{i}", words) {
                  let picked = l
                  c.tell("screen-fill-pick/" + s.view, fn() { s.fill_pick(picked) })
                }
              }
            })
            |> ignore
          _ => ()
        }
      })
    })
    |> ignore
  })
  |> ignore
}

///|
/// The logins to pick from: one under another, each as wide as its words.
// kept across runs: a value (no field of it changes)
let fill_choice_list : @ui.Style = @ui.css("align=AStart pt=S2 gap=S2")
