// A page's login filled from this device's password manager (ember docs/remote-screens.md, "Filling a login"): while
// this viewer drives a tab of a station's browser whose focus is in a login field, the station says the site (the
// tab's address, not the page's word); the person's own 1Password (@hostapi passwords.mbt: its command-line tool,
// which asks them itself) is asked for that site's logins, they pick one where there are more, and its account and
// password go to the station to fill the form (`screen.input` fill), for that site only. Nothing of a password is kept
// here, logged or shown.

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
  self.fill_ask(["item", "list", "--categories", "Login", "--format", "json"], "listing")
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
      let input : Map[String, Json] = { "t": Json::string("fill"), "host": Json::string(self.fill_host) }
      if username != "" {
        input["username"] = Json::string(username)
      }
      if password != "" {
        input["password"] = Json::string(password)
      }
      self.input(self.src, Json::object(input))
      self.fill_step.set("")
    }
    _ => ()
  }
}

///|
/// 用 1Password 填入, over the stage while the focus is in a login field of a page this viewer drives (on a host that
/// has a password manager to ask): what it is at, the logins to pick from, or why it did not fill.
fn login_fill(c : @ui.Ctx, s : ScreenSess) -> Unit {
  // a run under way: its end taken once it came (after this frame: what the page shows changes then)
  match s.fill_run {
    Some(r) if r.done() is Some(_) => c.tell("screen-fill/" + s.view, fn() { s.fill_took() })
    _ => ()
  }
  let step = s.fill_step.get()
  let host = s.login_host()
  if !@hostapi.passwords() || (host is None && step == "") {
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
          "choosing" => @sf.t("android-misc.screen.fill.pick", args=[("host", s.fill_host)])
          "said" => s.fill_note
          _ => @sf.t("android-misc.screen.fill.offer")
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
            c.box(style=fill_choices, fn() {
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
let fill_choices : @ui.Style = @ui.css("align=AStart pt=S2 gap=S2")
