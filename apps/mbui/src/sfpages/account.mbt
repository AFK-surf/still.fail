// 账号, one page in every frame (web/src/cloud/settings.tsx AccountSettings; the narrow app's mobile/Me.tsx), the same
// on every width (the user, 2026-10-26: 「设置感觉很乱」; it was four sections and two cards wide, one card narrow): the
// accounts on this device on one card, the one in view first with who it is (its picture, name, email and how it
// signs in) and signing out of it, the others each signed out of by itself, another added; where it is signed in (each
// device, signed out from here but this one); deleting the account, in red at the foot. Signing out and deleting
// asked first (@sf.confirm).

///|
/// 账号 (AccountSettings, MeScreen) made once as nodes in node `v`, laid out by the `width` its frame gives it (narrow
/// where none is given): the accounts on this device on one card (the one in view first with who it is, signed out of
/// at its end; the others each signed out of by itself; another added), where it is signed in, deleting it at the foot;
/// all followed as the core says it. `here`: who and where, as that changes; `stint`: the page's time on top, what the
/// pictures are asked for on. What it says of itself told `said`.
pub fn me_node(
  v : @view.View,
  core : Core,
  here : () -> Here,
  on_back~ : () -> Unit,
  frame~ : () -> PageFrame,
  stint~ : () -> Int,
  said? : (@sf.PageSaid) -> Unit,
  width? : () -> Double,
) -> Unit {
  let name = fn() {
    let h = here()
    if h.person != "" {
      h.person
    } else {
      h.email
    }
  }
  let how = fn() {
    let sub = here().sub
    if sub.has_prefix("em-") || sub.has_prefix("pw-") {
      @sf.t("web-pages.settings.account.email")
    } else {
      @sf.t("web-pages.settings.account.google")
    }
  }
  let others = fn() {
    let sub = here().sub
    match (core.topic)("accounts", Map::new()).value {
      Some(Array(a)) => a.filter(fn(a) { text(Some(a), "sub") != sub })
      _ => []
    }
  }
  let picture = fn(p : String) { if p == "" { "" } else { (core.picture)(p, stint()) } }
  // signing out of one: asked first, then the chats (the account in view goes with it)
  let sign_out = fn(sub : String, email : String) {
    @sf.confirm(
      @sf.t("web-pages.settings.account.signOutConfirm", args=[("email", email)]),
      @sf.t("web-pages.settings.account.signOutConfirmBody"),
      @sf.t("web-pages.settings.account.signOutAction"),
      fn() {
        if sub == here().sub {
          (core.home)()
        }
        @settings.act(
          core,
          @sf.t("web-pages.settings.account.signOut"),
          "auth.signOut",
          obj([("account", str(sub))]),
          done=@sf.t("web-pages.settings.account.signedOut", args=[("email", email)]),
        )
      },
    )
  }
  let delete = fn() {
    let h = here()
    @sf.confirm(
      @sf.t("web-pages.settings.account.delete"),
      @sf.t("web-pages.settings.account.deleteConfirmBody", args=[("email", h.email)]),
      @sf.t("web-pages.settings.account.deleteAction"),
      danger=true,
      fn() {
        (core.home)()
        @settings.act(
          core,
          @sf.t("web-pages.settings.account.deleteAction"),
          "auth.deleteAccount",
          obj([("account", str(h.sub))]),
          done=@sf.t("web-pages.settings.account.deleted", args=[("email", h.email)]),
        )
      },
    )
  }
  @sf.page_node(v, fn() { @sf.t("android-settings.me.title") }, on_back~, frame~, said?, width?, fn() {
    ["accounts", "sessions", "delete"]
  }, fn(b, key) {
    match key {
      // the accounts on this device on one card (Me.tsx): the one in view with who it is, then the others, each signed
      // out of by itself, another added
      "accounts" =>
        @sf.group_node(b, fn(g) {
          @sf.link_row_node(
            g,
            name,
            fn() {  },
            note=fn() { here().email + " · " + how() },
            strong=true,
            goes=false,
            lead=LeadMade(fn(l) {
              @sf.avatar_node(l, fn() { here().email }, name, fn() { picture(here().picture) }, acc_picture)
            }),
            control=fn(e) {
              @sf.button_node(
                e,
                fn() {
                  if others().length() > 0 {
                    @sf.t("android-settings.me.signOut")
                  } else {
                    @sf.t("android-settings.me.signOutOnly")
                  }
                },
                fn() {
                  let h = here()
                  sign_out(h.sub, h.email)
                },
                tone=Ghost,
              )
              |> ignore
            },
          )
          g.each(others, fn(a) { text(Some(a), "sub") }, fn(r, a) {
            let at = fn() { Some(a.get()) }
            let email = fn() { text(at(), "email") }
            let shown = fn() { if text(at(), "name") != "" { text(at(), "name") } else { email() } }
            // (each with their face, as the one in view)
            @sf.link_row_node(
              r,
              email,
              fn() {  },
              goes=false,
              lead=LeadMade(fn(l) { @sf.avatar_node(l, email, shown, fn() { picture(text(at(), "picture")) }, acc_picture) }),
              control=fn(e) {
                @sf.button_node(e, fn() { @sf.t("android-settings.me.signOut") }, fn() {
                  sign_out(text(@signals.untracked(at), "sub"), @signals.untracked(email))
                }, tone=Ghost)
                |> ignore
              },
            )
          })
          @sf.link_row_node(g, fn() { @sf.t("android-settings.me.addAccount") }, fn() { (core.sign_in)() }, chevron=false)
        })
      "sessions" =>
        @sf.section_node(
          b,
          fn() { @sf.t("web-pages.settings.account.sessions") },
          note=fn() { @sf.t("web-pages.settings.account.sessionsLead", args=[("name", "still.fail")]) },
          fn(sec) { acc_devices_node(sec, core, here) },
        )
      // deleting the account in view, at the foot, in red (Me.tsx)
      _ =>
        @sf.group_node(b, fn(g) {
          @sf.link_row_node(g, fn() { @sf.t("android-settings.me.delete") }, delete, danger=true, chevron=false)
        })
    }
  })
}

///|
/// Where the account is signed in (the `loginSessions` topic) as nodes in `v`: each device's row (devices_node); its
/// error said in red where it has one; read the first time, rows' shapes where their card's rows will be (settings.tsx:
/// Waiting, 3).
fn acc_devices_node(v : @view.View, core : Core, here : () -> Here) -> Unit {
  let topic = fn() { (core.topic)("loginSessions", { "account": str(here().sub) }) }
  let list = fn() {
    match topic().value {
      Some(Array(a)) => Some(a)
      _ => None
    }
  }
  let failed = fn() {
    match topic().error {
      Some(e) => @sf.t("web-pages.settings.account.sessionsFailed", args=[("error", error_text(e))])
      None => ""
    }
  }
  v.pick(fn() { if list() is Some(_) { 0 } else if failed() != "" { 1 } else { 2 } }, fn(p, which) {
    match which {
      0 => devices_node(p, core, here, fn() { list().unwrap_or([]) })
      1 => @sf.page_note_node(p, failed, bad=fn() { true })
      _ =>
        @sf.waiting_node(p, fn(s) { devices_node(s, core.quiet(), here, devices_sample) }, note=fn() {
          { reading: true, text: @sf.t("common.reading"), failing: [] }
        })
    }
  })
}

///|
/// The devices the account is signed in on (`list`) as nodes in `v`, on a card: each a row of its own by its id, its
/// name (当前 after it on this one), 退出 at its end on the others (`loginSession.revoke`), when it signed in and until
/// when under them.
fn devices_node(v : @view.View, core : Core, here : () -> Here, list : () -> Array[Json]) -> Unit {
  @sf.group_node(v, fn(g) {
    g.each(list, fn(d) { text(Some(d), "id") }, fn(r, d) {
      let dv = fn() { Some(d.get()) }
      let id = text(@signals.untracked(dv), "id")
      let current = fn() { flag(dv(), "current") }
      @sf.link_row_node(
        r,
        fn() {
          match text(dv(), "name") {
            "" => @sf.t("web-pages.settings.account.unnamedDevice")
            n => n
          }
        },
        fn() {  },
        note=fn() {
          @sf.t("web-pages.settings.account.sessionTimes", args=[
            ("time", stamp(dv(), "created_at", "ago")),
            ("until", stamp(dv(), "expires_at", "until")),
          ])
        },
        goes=false,
        title_after=fn(a) { you_node(a, fn() { @sf.t("web-pages.settings.account.here") }) },
        title_after_shown=current,
        control=fn(e) {
          e.show(fn() { !current() }, fn(k) {
            @sf.button_node(
              k,
              fn() { @sf.t("web-pages.settings.account.revoke") },
              fn() {
                @settings.act(
                  core,
                  @sf.t("web-pages.settings.account.revoke"),
                  "loginSession.revoke",
                  obj([("id", str(id)), ("account", str(@signals.untracked(here).sub))]),
                  done=@sf.t("web-pages.settings.account.revoked"),
                )
              },
              tone=Ghost,
              busy=fn() { is_doing(core, ["loginSession.revoke"], [("id", id)]) },
            )
            |> ignore
          })
        },
      )
    })
  })
}

///|
/// A word in the accent's wash as a node (@settings.you's: 当前), `words` as it says it now.
fn you_node(parent : @view.View, words : () -> String) -> Unit {
  parent.box(fn(w) {
    w.padding(Is((you_in, 0.0, you_in, 0.0))).radius(By(fn() { @ui.tree_theme().corner(Md) })).ground(By(fn() {
      @ui.tree_theme().color(AccentBg)
    }))
    |> ignore
    @sf.words_node(w, words, fn() { you_words }) |> ignore
  })
  |> ignore
}

///|
/// You's wash: 6 in at its sides (px=S1_5).
let you_in : Double = 6.0

///|
/// Small words in the accent's ink (@settings.you's).
// kept across runs: a value (no field of it changes)
let you_words : @ui.TextStyle = @sf.caption.then(@ui.text_style(color=AccentText))

///|
let acc_picture : Double = @sf.identity_mark

///|
// kept across runs: a value (no field of it changes)
pub let acc_delete_words : @ui.TextStyle = @sf.body.then(@sf.bad)

///|
/// (a narrow page's foot: what takes something away, 16 over it)
// kept across runs: a value (no field of it changes)
pub let acc_narrow_foot : @ui.Style = @ui.css("w=Full pt=S4")

///|
/// Devices made up, for what is shown while they are read (devices_list in its bones): this one and two others.
fn devices_sample() -> Array[Json] {
  [(6, true), (9, false), (7, false)].mapi(fn(i, d) {
    Json::object({
      "id": Json::string("sample" + i.to_string()),
      "name": Json::string(@sf.sample_words(d.0)),
      "current": Json::boolean(d.1),
      "created_at": { "ago": Json::string(@sf.sample_words(4)) },
      "expires_at": { "until": Json::string(@sf.sample_words(4)) },
    })
  })
}
